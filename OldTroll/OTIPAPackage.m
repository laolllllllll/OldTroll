//
//  OTIPAPackage.m
//  OldTroll
//

#import "OTIPAPackage.h"
#import "OTAppInfo.h"
#import "OTAppManager.h"
#import "OTCompat.h"
#import "OTProcessRunner.h"

#import <sys/stat.h>

static NSString * const OTHelperPath = @"/usr/bin/oldtroll_helper";
static NSString * const OTDpkgDebPath = @"/usr/bin/dpkg-deb";
static NSString * const OTInstallLogPath = @"/tmp/oldtroll_install.log";

static NSError *OTPackageError(NSString *message) {
    return [NSError errorWithDomain:@"com.cor.oldtroll.package"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *OTSingleLineString(NSString *value, NSString *fallback) {
    if (OTStringIsEmpty(value)) {
        return fallback;
    }
    NSArray *lines = [value componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            [parts addObject:trimmed];
        }
    }
    NSString *joined = [parts componentsJoinedByString:@" "];
    return joined.length > 0 ? joined : fallback;
}

static NSString *OTSafeFileName(NSString *value, NSString *fallback) {
    NSString *source = OTSingleLineString(value, fallback);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < source.length; index++) {
        unichar character = [source characterAtIndex:index];
        BOOL allowed = (character >= 'a' && character <= 'z') ||
                       (character >= 'A' && character <= 'Z') ||
                       (character >= '0' && character <= '9') ||
                       character == ' ' || character == '-' || character == '_' ||
                       character == '.' || character == '(' || character == ')';
        if (allowed) {
            [result appendFormat:@"%C", character];
        }
    }
    NSString *trimmed = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length > 64) {
        trimmed = [trimmed substringToIndex:64];
    }
    return trimmed.length > 0 ? trimmed : fallback;
}

static BOOL OTIsSafeExecutableName(NSString *name) {
    if (OTStringIsEmpty(name)) {
        return NO;
    }
    if ([name rangeOfString:@"/"].location != NSNotFound) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+"];
    return [name rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

static NSString *OTSafeVersionString(NSString *value) {
    NSString *source = OTSingleLineString(value, @"1.0");
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < source.length; index++) {
        unichar character = [source characterAtIndex:index];
        BOOL allowed = (character >= 'a' && character <= 'z') ||
                       (character >= 'A' && character <= 'Z') ||
                       (character >= '0' && character <= '9') ||
                       character == '.' || character == '-' || character == '+' ||
                       character == '~' || character == '_';
        [result appendFormat:@"%C", (unichar)(allowed ? character : (unichar)'.')];
    }
    if (result.length > 0) {
        unichar first = [result characterAtIndex:0];
        if (first < '0' || first > '9') {
            return @"1.0";
        }
    }
    return result.length > 0 ? result : @"1.0";
}

static BOOL OTHelperIsAvailable(NSString **reason) {
    struct stat info;
    if (stat([OTHelperPath fileSystemRepresentation], &info) != 0) {
        if (reason != NULL) {
            *reason = @"The privileged helper /usr/bin/oldtroll_helper is missing. Reinstall OldTroll.";
        }
        return NO;
    }
    if ((info.st_mode & S_ISUID) == 0 || info.st_uid != 0) {
        if (reason != NULL) {
            *reason = @"oldtroll_helper lost its setuid root bit. Reinstall OldTroll.";
        }
        return NO;
    }
    return YES;
}

@interface OTIPAPackage ()
@property (nonatomic, copy) NSString *executableName;
@property (nonatomic, assign) BOOL built;
@end

@implementation OTIPAPackage

- (instancetype)initWithIPAPath:(NSString *)ipaPath {
    self = [super init];
    if (self) {
        _ipaPath = [ipaPath copy];
        _version = @"1.0";
        _built = NO;
    }
    return self;
}

- (void)dealloc {
    // Deliberately does not delete tempDir: the caller decides when to clean up.
}

#pragma mark - Helpers

- (NSString *)makeTempDirectoryWithError:(NSError **)error {
    NSString *name = [NSString stringWithFormat:@"/tmp/oldtroll_%ld_%u",
                      (long)[[NSDate date] timeIntervalSince1970], arc4random()];
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtPath:name error:NULL];
    if (![manager createDirectoryAtPath:name withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    return name;
}

- (NSString *)findUnzip {
    return [OTProcessRunner findExecutable:@[@"/usr/bin/unzip", @"/bin/unzip", @"/usr/local/bin/unzip"]];
}

- (NSString *)findLdid {
    return [OTProcessRunner findExecutable:@[@"/usr/bin/ldid", @"/usr/local/bin/ldid", @"/usr/bin/ldid2"]];
}

- (NSString *)findDpkgDeb {
    if (OTIsExecutable(OTDpkgDebPath)) {
        return OTDpkgDebPath;
    }
    return [OTProcessRunner findExecutable:@[@"/usr/local/bin/dpkg-deb", @"/bin/dpkg-deb"]];
}

- (BOOL)copyAppBundleFrom:(NSString *)source to:(NSString *)destination error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *copyError = nil;
    if ([manager copyItemAtPath:source toPath:destination error:&copyError]) {
        return YES;
    }

    // Some app bundles contain symlinks that NSFileManager refuses to copy on
    // older iOS releases. Fall back to cp -R, which handles them reliably.
    NSString *cp = [OTProcessRunner findExecutable:@[@"/bin/cp", @"/usr/bin/cp"]];
    if (cp != nil) {
        OTProcessResult *result = [OTProcessRunner run:cp arguments:@[@"-R", source, destination]];
        if (result.succeeded) {
            return YES;
        }
    }

    if (error != NULL) {
        *error = copyError ?: OTPackageError(@"Could not copy the extracted .app bundle.");
    }
    return NO;
}

- (BOOL)writeString:(NSString *)contents toFile:(NSString *)path error:(NSError **)error {
    return [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (BOOL)makeExecutable:(NSString *)path {
    NSDictionary *attributes = @{NSFilePosixPermissions: @0755};
    return [[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:path error:NULL];
}

#pragma mark - Parse

- (BOOL)parseIPAWithError:(NSError **)error {
    if (OTStringIsEmpty(self.ipaPath) || ![[NSFileManager defaultManager] fileExistsAtPath:self.ipaPath]) {
        if (error != NULL) {
            *error = OTPackageError(@"The selected IPA file does not exist.");
        }
        return NO;
    }
    if (![[[self.ipaPath pathExtension] lowercaseString] isEqualToString:@"ipa"]) {
        if (error != NULL) {
            *error = OTPackageError(@"The selected file is not an .ipa file.");
        }
        return NO;
    }

    NSString *unzip = [self findUnzip];
    if (unzip == nil) {
        if (error != NULL) {
            *error = OTPackageError(@"unzip is not installed. Install the \"unzip\" package from Cydia and try again.");
        }
        return NO;
    }

    [self cleanup];
    NSError *directoryError = nil;
    self.tempDir = [self makeTempDirectoryWithError:&directoryError];
    if (self.tempDir == nil) {
        if (error != NULL) {
            *error = directoryError ?: OTPackageError(@"Could not create a temporary directory.");
        }
        return NO;
    }

    NSString *extractDirectory = [self.tempDir stringByAppendingPathComponent:@"extract"];
    [[NSFileManager defaultManager] createDirectoryAtPath:extractDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    OTProcessResult *unzipResult = [OTProcessRunner run:unzip
                                              arguments:@[@"-o", self.ipaPath, @"-d", extractDirectory]];
    if (!unzipResult.succeeded) {
        if (error != NULL) {
            NSString *output = [unzipResult.output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            *error = OTPackageError(output.length > 0 ? [@"IPA extraction failed: " stringByAppendingString:output] : @"IPA extraction failed. The file may be corrupted or encrypted.");
        }
        return NO;
    }

    NSString *payload = [extractDirectory stringByAppendingPathComponent:@"Payload"];
    NSArray *payloadChildren = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payload error:NULL];
    if (payloadChildren == nil) {
        if (error != NULL) {
            *error = OTPackageError(@"The IPA does not contain a Payload directory.");
        }
        return NO;
    }

    NSString *appPath = nil;
    NSDictionary *appInfo = nil;
    for (NSString *child in payloadChildren) {
        if (![[[child pathExtension] lowercaseString] isEqualToString:@"app"]) {
            continue;
        }
        NSString *candidate = [payload stringByAppendingPathComponent:child];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[candidate stringByAppendingPathComponent:@"Info.plist"]];
        if (![info isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if (!OTStringIsEmpty(info[@"CFBundleIdentifier"]) && !OTStringIsEmpty(info[@"CFBundleExecutable"])) {
            appPath = candidate;
            appInfo = info;
            break;
        }
        if (appPath == nil) {
            appPath = candidate;
            appInfo = info;
        }
    }

    if (appPath == nil || appInfo == nil) {
        if (error != NULL) {
            *error = OTPackageError(@"No Payload/*.app bundle was found inside the IPA.");
        }
        return NO;
    }

    self.appPath = appPath;
    self.bundleId = OTSingleLineString(appInfo[@"CFBundleIdentifier"], nil);
    if (OTStringIsEmpty(self.bundleId)) {
        if (error != NULL) {
            *error = OTPackageError(@"The app has no CFBundleIdentifier.");
        }
        return NO;
    }

    self.appName = OTSingleLineString(appInfo[@"CFBundleDisplayName"],
                                      OTSingleLineString(appInfo[@"CFBundleName"],
                                                         [[appPath lastPathComponent] stringByDeletingPathExtension]));
    self.version = OTSafeVersionString(appInfo[@"CFBundleShortVersionString"] ?: appInfo[@"CFBundleVersion"]);
    self.executableName = OTSingleLineString(appInfo[@"CFBundleExecutable"], nil);
    if (!OTIsSafeExecutableName(self.executableName)) {
        if (error != NULL) {
            *error = OTPackageError(@"The app has a missing or invalid CFBundleExecutable.");
        }
        return NO;
    }

    self.iconPath = [OTAppInfo iconPathForAppPath:appPath info:appInfo];
    self.icon = [OTAppInfo iconForAppPath:appPath info:appInfo];
    self.packageIdentifier = OTPackageIdentifierForBundleId(self.bundleId);

    NSString *baseName = OTSafeFileName(self.appName, OTNonEmptyString([[self.bundleId pathComponents] lastObject], @"App"));
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *candidateName = baseName;
    NSInteger suffix = 1;
    while (suffix < 50) {
        NSString *bundleFolder = [candidateName stringByAppendingString:@".app"];
        NSString *candidatePath = [@"/Applications" stringByAppendingPathComponent:bundleFolder];
        NSString *candidateStashPath = [@"/var/stash" stringByAppendingPathComponent:bundleFolder];
        if (![manager fileExistsAtPath:candidatePath] && ![manager fileExistsAtPath:candidateStashPath]) {
            break;
        }
        NSString *existingPath = [manager fileExistsAtPath:candidatePath] ? candidatePath : candidateStashPath;
        NSDictionary *existingInfo = [NSDictionary dictionaryWithContentsOfFile:[existingPath stringByAppendingPathComponent:@"Info.plist"]];
        NSString *existingBundleId = existingInfo[@"CFBundleIdentifier"];
        if ([existingBundleId isEqualToString:self.bundleId]) {
            break;
        }
        suffix++;
        candidateName = [baseName stringByAppendingFormat:@"-%ld", (long)suffix];
    }
    self.safeName = candidateName;
    self.installPath = [@"/Applications" stringByAppendingPathComponent:[candidateName stringByAppendingString:@".app"]];
    return YES;
}

#pragma mark - Build

- (BOOL)buildDebWithProgress:(OTIPAPackageProgressBlock)progress error:(NSError **)error {
    if (OTStringIsEmpty(self.appPath) || OTStringIsEmpty(self.tempDir)) {
        if (error != NULL) {
            *error = OTPackageError(@"Please call parseIPAWithError: first.");
        }
        return NO;
    }

    NSString *ldid = [self findLdid];
    if (ldid == nil) {
        if (error != NULL) {
            *error = OTPackageError(@"ldid is not installed. Install the \"ldid\" package from Cydia and try again.");
        }
        return NO;
    }

    if (progress != nil) {
        progress(0.12, @"Signing binary...");
    }

    NSString *binaryPath = [self.appPath stringByAppendingPathComponent:self.executableName];
    OTProcessResult *signResult = [OTProcessRunner run:ldid arguments:@[@"-S", binaryPath]];
    if (!signResult.succeeded) {
        if (error != NULL) {
            NSString *output = [signResult.output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            *error = OTPackageError(output.length > 0 ? [@"ldid failed: " stringByAppendingString:output] : @"ldid could not pseudo-sign the app binary.");
        }
        return NO;
    }

    if (progress != nil) {
        progress(0.32, @"Building package...");
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *packageDirectory = [self.tempDir stringByAppendingPathComponent:@"package"];
    [manager removeItemAtPath:packageDirectory error:NULL];
    NSString *stashDirectory = [packageDirectory stringByAppendingPathComponent:@"var/stash"];
    NSString *iconDirectory = [packageDirectory stringByAppendingPathComponent:@"usr/share/icons"];
    NSString *debianDirectory = [packageDirectory stringByAppendingPathComponent:@"DEBIAN"];
    for (NSString *directory in @[stashDirectory, iconDirectory, debianDirectory]) {
        if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    NSString *stashedApp = [stashDirectory stringByAppendingPathComponent:[self.safeName stringByAppendingString:@".app"]];
    NSError *copyError = nil;
    if (![self copyAppBundleFrom:self.appPath to:stashedApp error:&copyError]) {
        if (error != NULL) {
            *error = copyError;
        }
        return NO;
    }
    [self makeExecutable:[stashedApp stringByAppendingPathComponent:self.executableName]];

    BOOL hasIcon = NO;
    if (!OTStringIsEmpty(self.iconPath) && [[NSFileManager defaultManager] fileExistsAtPath:self.iconPath]) {
        NSString *iconDestination = [iconDirectory stringByAppendingPathComponent:[self.packageIdentifier stringByAppendingString:@".png"]];
        if ([manager copyItemAtPath:self.iconPath toPath:iconDestination error:NULL]) {
            [manager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:iconDestination error:NULL];
            hasIcon = YES;
        }
    }

    NSString *iconField = hasIcon ? [NSString stringWithFormat:@"Icon: file:///usr/share/icons/%@.png\n", self.packageIdentifier] : @"";
    NSString *description = [NSString stringWithFormat:@"%@ installed via OldTroll, ldid pseudo-signed.",
                             OTSingleLineString(self.appName, self.bundleId)];
    NSString *control = [NSString stringWithFormat:
        @"Package: %@\n"
         "Name: %@\n"
         "Version: %@-1\n"
         "Architecture: iphoneos-arm\n"
         "Section: Utilities\n"
         "Maintainer: OldTroll\n"
         "Depends: firmware (>= 6.0)\n"
         "%@"
         "Description: %@\n",
        self.packageIdentifier, OTSingleLineString(self.appName, self.bundleId),
        self.version, iconField, description];

    // Paths in maintainer scripts are single-quoted. safeName only allows
    // characters that are harmless inside a POSIX shell single-quoted string.
    NSString *postinst = [NSString stringWithFormat:
        @"#!/bin/sh\n"
         "chown -R root:wheel '/var/stash/%@.app'\n"
         "chmod -R 755 '/var/stash/%@.app'\n"
         "chmod 755 '/var/stash/%@.app/%@'\n"
         "if [ ! -e '/Applications/%@.app' ]; then ln -sf '/var/stash/%@.app' '/Applications/%@.app'; fi\n"
         "if [ -x /usr/bin/uicache ]; then /usr/bin/uicache > /dev/null 2>&1; else uicache > /dev/null 2>&1; fi\n"
         "exit 0\n",
        self.safeName, self.safeName, self.safeName, self.executableName,
        self.safeName, self.safeName, self.safeName];

    NSString *postrm = [NSString stringWithFormat:
        @"#!/bin/sh\n"
         "rm -f '/Applications/%@.app'\n"
         "rm -f '/usr/share/icons/%@.png'\n"
         "if [ -x /usr/bin/uicache ]; then /usr/bin/uicache > /dev/null 2>&1; else uicache > /dev/null 2>&1; fi\n"
         "exit 0\n",
        self.safeName, self.packageIdentifier];

    NSError *writeError = nil;
    if (![self writeString:control toFile:[debianDirectory stringByAppendingPathComponent:@"control"] error:&writeError] ||
        ![self writeString:postinst toFile:[debianDirectory stringByAppendingPathComponent:@"postinst"] error:&writeError] ||
        ![self writeString:postrm toFile:[debianDirectory stringByAppendingPathComponent:@"postrm"] error:&writeError]) {
        if (error != NULL) {
            *error = writeError ?: OTPackageError(@"Could not write the Debian control files.");
        }
        return NO;
    }
    [manager setAttributes:@{NSFilePosixPermissions: @0644}
                ofItemAtPath:[debianDirectory stringByAppendingPathComponent:@"control"]
                       error:NULL];
    for (NSString *script in @[@"postinst", @"postrm"]) {
        NSString *path = [debianDirectory stringByAppendingPathComponent:script];
        [manager setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:path error:NULL];
    }

    if (progress != nil) {
        progress(0.68, @"Packaging deb...");
    }

    NSString *output = [NSString stringWithFormat:@"/tmp/oldtroll_%@_%@-1_iphoneos-arm.deb",
                        OTSafeFileName(self.safeName, @"app"), self.packageIdentifier];
    [[NSFileManager defaultManager] removeItemAtPath:output error:NULL];
    self.outputDebPath = output;

    NSString *dpkgDeb = [self findDpkgDeb];
    BOOL packaged = NO;
    if (dpkgDeb != nil) {
        OTProcessResult *result = [OTProcessRunner run:dpkgDeb
                                              arguments:@[@"-b", @"-Zgzip", @"-z9", packageDirectory, output]];
        packaged = result.succeeded;
        if (!packaged && error != NULL) {
            NSString *text = [result.output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            *error = OTPackageError(text.length > 0 ? [@"deb packaging failed: " stringByAppendingString:text] : @"deb packaging failed.");
        }
    }

    if (!packaged) {
        // Fallback for devices without dpkg-deb, mirroring the approach used
        // by OldTroll 1.0. The shell string is built only from paths we create.
        NSString *shell = [OTProcessRunner findExecutable:@[@"/bin/sh"]];
        NSString *tar = [OTProcessRunner findExecutable:@[@"/usr/bin/tar", @"/bin/tar"]];
        NSString *ar = [OTProcessRunner findExecutable:@[@"/usr/bin/ar", @"/bin/ar"]];
        if (shell != nil && tar != nil && ar != nil) {
            NSString *script = [NSString stringWithFormat:
                @"cd '%@' && printf '2.0\\n' > debian-binary && "
                 "'%@' -czf control.tar.gz -C DEBIAN . && "
                 "'%@' -czf data.tar.gz var usr && "
                 "'%@' r '%@' debian-binary control.tar.gz data.tar.gz",
                packageDirectory, tar, tar, ar, output];
            OTProcessResult *result = [OTProcessRunner run:shell arguments:@[@"-c", script]];
            packaged = result.succeeded && [[NSFileManager defaultManager] fileExistsAtPath:output];
            if (!packaged && error != NULL) {
                NSString *text = [result.output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                *error = OTPackageError(text.length > 0 ? [@"deb packaging failed: " stringByAppendingString:text] : @"deb packaging failed. Install dpkg from Cydia and try again.");
            }
        } else if (error != NULL) {
            *error = OTPackageError(@"dpkg-deb, tar and ar are all unavailable. Install dpkg from Cydia.");
        }
    }

    if (!packaged) {
        return NO;
    }

    [manager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:output error:NULL];
    self.built = YES;
    if (progress != nil) {
        progress(1.0, @"Done!");
    }
    return YES;
}

#pragma mark - Install

- (BOOL)installDebWithError:(NSError **)error {
    if (!self.built || OTStringIsEmpty(self.outputDebPath) || ![[NSFileManager defaultManager] fileExistsAtPath:self.outputDebPath]) {
        if (error != NULL) {
            *error = OTPackageError(@"The deb file does not exist. Build the package first.");
        }
        return NO;
    }

    NSString *helperError = nil;
    if (!OTHelperIsAvailable(&helperError)) {
        if (error != NULL) {
            *error = OTPackageError(helperError);
        }
        return NO;
    }

    OTProcessResult *result = [OTProcessRunner run:OTHelperPath arguments:@[@"install", self.outputDebPath]];
    if (!result.succeeded) {
        NSString *log = [NSString stringWithContentsOfFile:OTInstallLogPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
        NSString *detail = OTStringIsEmpty(log) ? result.output : log;
        detail = [detail stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (error != NULL) {
            *error = OTPackageError(detail.length > 0 ? [@"Installation failed: " stringByAppendingString:detail] : @"Installation failed. See /tmp/oldtroll_install.log for details.");
        }
        return NO;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:self.installPath]) {
        if (error != NULL) {
            *error = OTPackageError(@"dpkg reported success but the app was not created in /Applications.");
        }
        return NO;
    }

    [[OTAppManager sharedManager] recordInstalledAppWithBundleId:self.bundleId
                                                         package:self.packageIdentifier
                                                            path:self.installPath];
    return YES;
}

#pragma mark - Cleanup

- (void)cleanup {
    if (!OTStringIsEmpty(self.tempDir)) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:NULL];
        self.tempDir = nil;
    }
    if (!OTStringIsEmpty(self.outputDebPath)) {
        [[NSFileManager defaultManager] removeItemAtPath:self.outputDebPath error:NULL];
        self.outputDebPath = nil;
    }
}

+ (void)clearAllCache {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *children = [manager contentsOfDirectoryAtPath:@"/tmp" error:NULL];
    for (NSString *child in children) {
        if ([child.lowercaseString hasPrefix:@"oldtroll_"]) {
            [manager removeItemAtPath:[@"/tmp" stringByAppendingPathComponent:child] error:NULL];
        }
    }
}

@end
