//
//  OTProcessRunner.m
//  OldTroll
//

#import "OTProcessRunner.h"
#import "OTCompat.h"

#import <errno.h>
#import <fcntl.h>
#import <spawn.h>
#import <stdlib.h>
#import <string.h>
#import <sys/wait.h>

@implementation OTProcessResult

- (BOOL)succeeded {
    return self.exitCode == 0;
}

@end

@implementation OTProcessRunner

+ (OTProcessResult *)run:(NSString *)executable arguments:(NSArray *)arguments {
    OTProcessResult *result = [[OTProcessResult alloc] init];
    if (!OTIsExecutable(executable)) {
        result.exitCode = 127;
        result.output = [NSString stringWithFormat:@"%@: command not found or not executable", OTNonEmptyString(executable, @"(null)")];
        return result;
    }

    NSString *logPath = [NSString stringWithFormat:@"/tmp/oldtroll_cmd_%d_%u.log", getpid(), arc4random()];
    [[NSFileManager defaultManager] removeItemAtPath:logPath error:NULL];

    NSMutableArray *allArguments = [NSMutableArray arrayWithObject:executable];
    if ([arguments isKindOfClass:[NSArray class]]) {
        [allArguments addObjectsFromArray:arguments];
    }

    char **argv = calloc(allArguments.count + 1, sizeof(char *));
    if (argv == NULL) {
        result.exitCode = 127;
        result.output = @"Could not allocate command arguments.";
        return result;
    }
    for (NSUInteger index = 0; index < allArguments.count; index++) {
        argv[index] = strdup([[allArguments objectAtIndex:index] UTF8String]);
    }
    argv[allArguments.count] = NULL;

    // A controlled environment keeps root helpers from inheriting anything
    // unexpected from the app process.
    char *envp[] = {
        "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME=/var/mobile",
        "TMPDIR=/tmp",
        "LANG=en_US.UTF-8",
        "LC_ALL=en_US.UTF-8",
        NULL
    };

    const char *executablePath = [executable fileSystemRepresentation];
    const char *logPathC = [logPath fileSystemRepresentation];

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logPathC, O_WRONLY | O_CREAT | O_APPEND, 0600);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, logPathC, O_WRONLY | O_CREAT | O_APPEND, 0600);

    pid_t child = 0;
    int spawnError = posix_spawn(&child, executablePath, &actions, NULL, argv, envp);
    posix_spawn_file_actions_destroy(&actions);

    for (NSUInteger index = 0; index < allArguments.count; index++) {
        free(argv[index]);
    }
    free(argv);

    if (spawnError != 0) {
        result.exitCode = 127;
        result.output = [NSString stringWithFormat:@"Failed to launch %@: %s", executable, strerror(spawnError)];
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:NULL];
        return result;
    }

    int status = 0;
    pid_t waited = (pid_t)-1;
    do {
        waited = waitpid(child, &status, 0);
    } while (waited == (pid_t)-1 && errno == EINTR);

    if (waited == (pid_t)-1) {
        result.exitCode = -1;
    } else if (WIFEXITED(status)) {
        result.exitCode = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result.exitCode = 128 + WTERMSIG(status);
    } else {
        result.exitCode = -1;
    }

    NSData *logData = [NSData dataWithContentsOfFile:logPath];
    NSString *output = nil;
    if (logData.length > 0) {
        output = [[NSString alloc] initWithData:logData encoding:NSUTF8StringEncoding];
        if (output == nil) {
            output = [[NSString alloc] initWithData:logData encoding:NSISOLatin1StringEncoding];
        }
    }
    result.output = OTStringIsEmpty(output) ? @"" : output;

    [[NSFileManager defaultManager] removeItemAtPath:logPath error:NULL];
    return result;
}

+ (NSString *)findExecutable:(NSArray *)candidates {
    for (NSString *candidate in candidates) {
        if (OTIsExecutable(candidate)) {
            return candidate;
        }
    }
    return nil;
}

@end
