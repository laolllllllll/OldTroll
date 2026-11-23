//
//  main.c
//  oldtroll_helper
//
//  Small setuid-root helper. OldTroll runs as the mobile user, so dpkg,
//  killall and uicache are executed here instead of through a shell.
//  Arguments are validated and passed directly to execve; no shell is used.
//

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

#define OT_HELPER_VERSION "1.2"
#define OT_APPINST_PATH "/usr/libexec/oldtroll/appinst"
#define OT_INSTALL_LOG "/tmp/oldtroll_install.log"
#define OT_HELPER_LOG "/tmp/oldtroll_helper.log"

static char *const helper_environment[] = {
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME=/var/root",
    "TMPDIR=/tmp",
    "LANG=C",
    "LC_ALL=C",
    NULL
};

static void helper_log(const char *format, ...) {
    int descriptor = open(OT_HELPER_LOG, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0644);
    if (descriptor < 0) {
        return;
    }
    FILE *file = fdopen(descriptor, "a");
    if (file == NULL) {
        close(descriptor);
        return;
    }
    va_list arguments;
    va_start(arguments, format);
    vfprintf(file, format, arguments);
    va_end(arguments);
    fputc('\n', file);
    fclose(file);
}

static int run_command(char *const arguments[], const char *outputPath, uid_t runUid) {
    if (arguments == NULL || arguments[0] == NULL) {
        return 127;
    }
    if (access(arguments[0], X_OK) != 0) {
        fprintf(stderr, "%s: not executable\n", arguments[0]);
        helper_log("not executable: %s", arguments[0]);
        return 127;
    }

    pid_t child = fork();
    if (child < 0) {
        fprintf(stderr, "fork failed: %s\n", strerror(errno));
        return 127;
    }

    if (child == 0) {
        int input = open("/dev/null", O_RDONLY);
        if (input >= 0) {
            dup2(input, STDIN_FILENO);
            close(input);
        }
        if (outputPath != NULL) {
            int output = open(outputPath, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0644);
            if (output >= 0) {
                dup2(output, STDOUT_FILENO);
                dup2(output, STDERR_FILENO);
                close(output);
            }
        }
        if (runUid != 0) {
            // uicache writes to the mobile user's icon cache; run it unprivileged.
            setgid(runUid);
            setuid(runUid);
            setenv("HOME", "/var/mobile", 1);
        }
        execve(arguments[0], arguments, helper_environment);
        _exit(127);
    }

    int status = 0;
    pid_t waited = (pid_t)-1;
    do {
        waited = waitpid(child, &status, 0);
    } while (waited == (pid_t)-1 && errno == EINTR);

    if (waited == (pid_t)-1) {
        return 127;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 127;
}

static int is_safe_ipa_path(const char *path) {
    size_t length = strlen(path);
    if (length < 5 || length >= PATH_MAX) {
        return 0;
    }
    if (strcmp(path + length - 4, ".ipa") != 0) {
        return 0;
    }
    // Imported IPAs can live outside the app container (for example at /),
    // so only require an absolute path to a regular .ipa file.
    if (path[0] != '/') {
        return 0;
    }
    struct stat info;
    if (stat(path, &info) != 0 || !S_ISREG(info.st_mode)) {
        return 0;
    }
    return 1;
}

static int has_prefix(const char *value, const char *prefix) {
    return strncmp(value, prefix, strlen(prefix)) == 0;
}

static int copy_file_by_path(const char *source, const char *destination, mode_t mode) {
    int input = open(source, O_RDONLY | O_NOFOLLOW);
    if (input < 0) {
        return -1;
    }
    struct stat info;
    if (fstat(input, &info) != 0 || !S_ISREG(info.st_mode)) {
        close(input);
        return -1;
    }

    int output = open(destination, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode);
    if (output < 0) {
        close(input);
        return -1;
    }

    char buffer[8192];
    ssize_t readCount = 0;
    int result = 0;
    while ((readCount = read(input, buffer, sizeof(buffer))) > 0) {
        ssize_t offset = 0;
        while (offset < readCount) {
            ssize_t written = write(output, buffer + offset, (size_t)(readCount - offset));
            if (written <= 0) {
                result = -1;
                break;
            }
            offset += written;
        }
        if (result != 0) {
            break;
        }
    }
    if (readCount < 0) {
        result = -1;
    }

    fchmod(output, mode);
    fchown(output, 0, 0);
    close(output);
    close(input);
    return result;
}

static int install_icon_set(const char *directory) {
    static const char *names[] = {
        "Icon.png", "Icon@2x.png",
        "Icon-72.png", "Icon-72@2x.png",
        "Icon-76.png", "Icon-76@2x.png",
        "Icon-60.png", "Icon-60@2x.png",
        "Icon-40.png", "Icon-40@2x.png",
        "Icon-Small.png", "Icon-Small@2x.png",
        "CydiaIcon.png"
    };
    const char *appDirectory = "/Applications/OldTroll.app";
    const char *cydiaIcon = "/usr/share/icons/com.cor.oldtroll.png";

    for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); index++) {
        char sourcePath[PATH_MAX];
        char destinationPath[PATH_MAX];
        if (snprintf(sourcePath, sizeof(sourcePath), "%s/%s", directory, names[index]) >= (int)sizeof(sourcePath)) {
            return -1;
        }
        if (strcmp(names[index], "CydiaIcon.png") == 0) {
            snprintf(destinationPath, sizeof(destinationPath), "%s", cydiaIcon);
        } else {
            snprintf(destinationPath, sizeof(destinationPath), "%s/%s", appDirectory, names[index]);
        }
        if (copy_file_by_path(sourcePath, destinationPath, 0644) != 0) {
            helper_log("icon copy failed: %s -> %s", sourcePath, destinationPath);
            return -1;
        }
    }
    return 0;
}

static int is_safe_package_name(const char *name) {
    size_t length = strlen(name);
    if (length == 0 || length > 200) {
        return 0;
    }
    if (!isalnum((unsigned char)name[0])) {
        return 0;
    }
    for (size_t index = 0; index < length; index++) {
        unsigned char character = (unsigned char)name[index];
        if (!isalnum(character) && character != '.' && character != '-' &&
            character != '+' && character != '_') {
            return 0;
        }
    }
    return 1;
}

static void usage(void) {
    fprintf(stderr,
            "Usage: oldtroll_helper <install|remove|remove-deb|respring|uicache|set-icons|version> [argument]\n"
            "  install <ipa path> <bundle id>  install an IPA through bundled appinst\n"
            "  remove <bundle id>   uninstall an AppSync-installed application\n"
            "  remove-deb <package> remove a package installed by OldTroll 1.x\n"
            "  respring             restart SpringBoard\n"
            "  uicache              refresh the icon cache\n"
            "  set-icons <dir>      install tinted icons generated by the app\n"
            "  version              print the helper version\n");
}

int main(int argc, char *argv[]) {
    umask(022);

    if (geteuid() != 0) {
        fprintf(stderr, "oldtroll_helper must run setuid root.\n");
        helper_log("refused: effective uid is %d, not root", (int)geteuid());
        return 1;
    }

    if (argc < 2) {
        usage();
        return 64;
    }

    const char *command = argv[1];
    helper_log("command=%s argc=%d", command, argc);

    if (strcmp(command, "version") == 0) {
        printf("oldtroll_helper %s\n", OT_HELPER_VERSION);
        return 0;
    }

    if (strcmp(command, "install") == 0) {
        if (argc != 4) {
            usage();
            return 64;
        }
        if (!is_safe_package_name(argv[3])) {
            fprintf(stderr, "Invalid bundle identifier.\n");
            return 3;
        }

        char resolved[PATH_MAX];
        if (realpath(argv[2], resolved) == NULL) {
            fprintf(stderr, "Cannot resolve IPA path: %s\n", strerror(errno));
            return 2;
        }
        if (!is_safe_ipa_path(resolved)) {
            fprintf(stderr, "Invalid IPA path.\n");
            helper_log("refused IPA path: %s", resolved);
            return 3;
        }
        if (access(OT_APPINST_PATH, X_OK) != 0) {
            fprintf(stderr, "The bundled appinst is missing. Reinstall OldTroll.\n");
            return 127;
        }

        int truncate = open(OT_INSTALL_LOG, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
        if (truncate >= 0) {
            close(truncate);
        }

        char *arguments[] = {OT_APPINST_PATH, "--install", argv[3], resolved, NULL};
        helper_log("AppSync install %s", resolved);
        int status = run_command(arguments, OT_INSTALL_LOG, 0);
        if (status == 0) {
            printf("Installed %s\n", resolved);
        } else {
            fprintf(stderr, "appinst exited with status %d\n", status);
        }
        return status;
    }

    if (strcmp(command, "remove") == 0) {
        if (argc != 3) {
            usage();
            return 64;
        }
        if (!is_safe_package_name(argv[2])) {
            fprintf(stderr, "Invalid bundle identifier.\n");
            return 3;
        }
        if (access(OT_APPINST_PATH, X_OK) != 0) {
            fprintf(stderr, "The bundled appinst is missing. Reinstall OldTroll.\n");
            return 127;
        }

        int truncate = open(OT_INSTALL_LOG, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
        if (truncate >= 0) {
            close(truncate);
        }

        char *arguments[] = {OT_APPINST_PATH, "--uninstall", argv[2], NULL};
        helper_log("AppSync uninstall %s", argv[2]);
        return run_command(arguments, OT_INSTALL_LOG, 0);
    }

    if (strcmp(command, "remove-deb") == 0) {
        if (argc != 3) {
            usage();
            return 64;
        }
        if (!is_safe_package_name(argv[2])) {
            fprintf(stderr, "Invalid package name.\n");
            return 3;
        }

        char *dpkg = "/usr/bin/dpkg";
        if (access(dpkg, X_OK) != 0) {
            dpkg = "/bin/dpkg";
        }
        if (access(dpkg, X_OK) != 0) {
            fprintf(stderr, "dpkg is not installed.\n");
            return 127;
        }

        int truncate = open(OT_INSTALL_LOG, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
        if (truncate >= 0) {
            close(truncate);
        }

        char *arguments[] = {dpkg, "-r", argv[2], NULL};
        helper_log("remove legacy deb %s", argv[2]);
        return run_command(arguments, OT_INSTALL_LOG, 0);
    }

    if (strcmp(command, "set-icons") == 0) {
        if (argc != 3) {
            usage();
            return 64;
        }
        char resolved[PATH_MAX];
        if (realpath(argv[2], resolved) == NULL) {
            fprintf(stderr, "Cannot resolve icon directory: %s\n", strerror(errno));
            return 2;
        }
        if (!has_prefix(resolved, "/private/var/mobile/") &&
            !has_prefix(resolved, "/var/mobile/") &&
            strcmp(resolved, "/private/var/tmp/oldtroll_icons") != 0 &&
            strcmp(resolved, "/var/tmp/oldtroll_icons") != 0) {
            fprintf(stderr, "Invalid icon directory.\n");
            helper_log("refused icon directory: %s", resolved);
            return 3;
        }
        if (install_icon_set(resolved) != 0) {
            fprintf(stderr, "Could not install the icon set.\n");
            return 1;
        }
        helper_log("set-icons %s", resolved);
        printf("Icons updated.\n");
        return 0;
    }

    if (strcmp(command, "respring") == 0) {
        char *killall = "/usr/bin/killall";
        if (access(killall, X_OK) != 0) {
            killall = "/bin/killall";
        }
        if (access(killall, X_OK) != 0) {
            fprintf(stderr, "killall is not installed.\n");
            return 127;
        }
        char *arguments[] = {killall, "-9", "SpringBoard", NULL};
        helper_log("respring");
        return run_command(arguments, NULL, 0);
    }

    if (strcmp(command, "uicache") == 0) {
        char *uicache = "/usr/bin/uicache";
        if (access(uicache, X_OK) != 0) {
            uicache = "/usr/local/bin/uicache";
        }
        if (access(uicache, X_OK) != 0) {
            fprintf(stderr, "uicache is not installed.\n");
            return 127;
        }
        char *arguments[] = {uicache, NULL};
        helper_log("uicache");
        return run_command(arguments, NULL, 501);
    }

    usage();
    return 64;
}
