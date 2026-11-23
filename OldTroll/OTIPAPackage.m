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
static NSString * const OTBundledUnzipPath = @"/usr/libexec/oldtroll/unzip";
static NSString * const OTAppSyncDylibPath = @"/Library/MobileSubstrate/DynamicLibraries/OldTrollAppSync-installd.dylib";
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

static BOOL OTAppSyncIsAvailable(NSString **reason) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *framework = @"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate";
    if (![manager fileExistsAtPath:framework] || ![manager fileExistsAtPath:OTAppSyncDylibPath]) {
        if (reason != NULL) {
            *reason = @"The bundled AppSync runtime is incomplete. Reinstall OldTroll and respring.";
        }
        return NO;
    }
    if (![manager isExecutableFileAtPath:@"/usr/libexec/oldtroll/appinst"]) {
        if (reason != NULL) {
            *reason = @"The bundled appinst installer is missing. Reinstall OldTroll.";
        }
        return NO;
    }
    return YES;
}

@interface OTIPAPackage ()
@property (nonatomic, copy) NSString *executableName;
@end

@implementation OTIPAPackage

- (instancetype)initWithIPAPath:(NSString *)ipaPath {
    self = [super init];
    if (self) {
        _ipaPath = [ipaPath copy];
        _version = @"1.0";
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
    if (OTIsExecutable(OTBundledUnzipPath)) {
        return OTBundledUnzipPath;
    }
    return [OTProcessRunner findExecutable:@[@"/usr/bin/unzip", @"/bin/unzip"]];
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
            *error = OTPackageError(@"The bundled unzip tool is missing. Reinstall OldTroll.");
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
    return YES;
}

#pragma mark - Install

- (BOOL)installIPAWithError:(NSError **)error {
    if (OTStringIsEmpty(self.ipaPath) || ![[NSFileManager defaultManager] fileExistsAtPath:self.ipaPath]) {
        if (error != NULL) {
            *error = OTPackageError(@"The IPA file does not exist.");
        }
        return NO;
    }

    NSString *helperError = nil;
    if (!OTHelperIsAvailable(&helperError) ||
        (helperError == nil && !OTAppSyncIsAvailable(&helperError))) {
        if (error != NULL) {
            *error = OTPackageError(helperError);
        }
        return NO;
    }

    OTProcessResult *result = [OTProcessRunner run:OTHelperPath arguments:@[@"install", self.ipaPath, self.bundleId]];
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

    NSString *installedPath = [[OTAppManager sharedManager] installedPathForBundleId:self.bundleId];
    if (OTStringIsEmpty(installedPath)) {
        if (error != NULL) {
            *error = OTPackageError(@"appinst reported success but the installed app could not be located.");
        }
        return NO;
    }

    self.installedPath = installedPath;
    [[OTAppManager sharedManager] recordInstalledAppWithBundleId:self.bundleId
                                                         package:nil
                                                            path:installedPath
                                                          method:@"appsync"];
    return YES;
}

#pragma mark - Cleanup

- (void)cleanup {
    if (!OTStringIsEmpty(self.tempDir)) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:NULL];
        self.tempDir = nil;
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
