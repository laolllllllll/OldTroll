//
//  OTAppManager.m
//  OldTroll
//

#import "OTAppManager.h"
#import "OTAppInfo.h"
#import "OTCompat.h"
#import "OTProcessRunner.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <sys/stat.h>

static NSString * const OTDataDirectory = @"/var/mobile/Library/OldTroll";
static NSString * const OTInstalledListPath = @"/var/mobile/Library/OldTroll/installed.plist";
static NSString * const OTHelperPath = @"/usr/bin/oldtroll_helper";

NSString *OTPackageIdentifierForBundleId(NSString *bundleId) {
    NSString *lower = [OTNonEmptyString(bundleId, @"com.oldtroll.app") lowercaseString];
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        BOOL allowed = (character >= 'a' && character <= 'z') ||
                       (character >= '0' && character <= '9') ||
                       character == '.' || character == '-' ||
                       character == '+' || character == '_';
        [result appendFormat:@"%C", (unichar)(allowed ? character : (unichar)'-')];
    }
    while (result.length > 0) {
        unichar first = [result characterAtIndex:0];
        if ((first >= 'a' && first <= 'z') || (first >= '0' && first <= '9')) {
            break;
        }
        [result deleteCharactersInRange:NSMakeRange(0, 1)];
    }
    if (result.length > 120) {
        [result deleteCharactersInRange:NSMakeRange(120, result.length - 120)];
    }
    return result.length > 0 ? result : @"com.oldtroll.app";
}

static BOOL OTHelperIsPrivileged(void) {
    struct stat info;
    if (stat([OTHelperPath fileSystemRepresentation], &info) != 0) {
        return NO;
    }
    return (info.st_mode & S_ISUID) != 0 && info.st_uid == 0;
}

@interface OTAppManager ()
@property (nonatomic, strong) NSMutableArray *cachedRecords;
@end

@implementation OTAppManager

+ (instancetype)sharedManager {
    static OTAppManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[OTAppManager alloc] init];
    });
    return manager;
}

#pragma mark - Records

- (NSMutableArray *)records {
    if (_cachedRecords != nil) {
        return _cachedRecords;
    }

    NSMutableArray *records = [NSMutableArray array];
    NSArray *stored = [NSArray arrayWithContentsOfFile:OTInstalledListPath];
    for (id item in stored) {
        if ([item isKindOfClass:[NSString class]]) {
            // OldTroll 1.0 stored a plain array of bundle identifiers.
            [records addObject:[@{@"bundleId": item, @"package": item} mutableCopy]];
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            NSString *bundleId = item[@"bundleId"];
            if (OTStringIsEmpty(bundleId)) {
                continue;
            }
            NSMutableDictionary *record = [item mutableCopy];
            if (OTStringIsEmpty(record[@"package"])) {
                record[@"package"] = OTPackageIdentifierForBundleId(bundleId);
            }
            [records addObject:record];
        }
    }
    _cachedRecords = records;
    return _cachedRecords;
}

- (void)saveRecords {
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:OTDataDirectory]) {
        [manager createDirectoryAtPath:OTDataDirectory
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];
    }
    [self.records writeToFile:OTInstalledListPath atomically:YES];
}

- (NSDictionary *)recordForBundleId:(NSString *)bundleId {
    for (NSDictionary *record in self.records) {
        if ([record[@"bundleId"] isEqualToString:bundleId]) {
            return record;
        }
    }
    return nil;
}

- (NSDictionary *)appPathsByBundleId {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *roots = @[@"/Applications", @"/var/stash"];
    for (NSString *root in roots) {
        NSArray *children = [manager contentsOfDirectoryAtPath:root error:NULL];
        for (NSString *child in children) {
            if (![[[child pathExtension] lowercaseString] isEqualToString:@"app"]) {
                continue;
            }
            NSString *path = [root stringByAppendingPathComponent:child];
            NSString *plistPath = [path stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            NSString *bundleId = info[@"CFBundleIdentifier"];
            if (OTStringIsEmpty(bundleId) || map[bundleId] != nil) {
                continue;
            }
            map[bundleId] = path;
        }
    }
    return map;
}

#pragma mark - Queries

- (NSArray *)installedApps {
    NSDictionary *pathMap = [self appPathsByBundleId];
    NSMutableArray *apps = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];

    for (NSDictionary *record in self.records) {
        NSString *bundleId = record[@"bundleId"];
        if (OTStringIsEmpty(bundleId) || [seen containsObject:bundleId]) {
            continue;
        }

        NSString *path = record[@"path"];
        if (OTStringIsEmpty(path) || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            path = pathMap[bundleId];
        }
        if (OTStringIsEmpty(path)) {
            continue;
        }

        OTAppInfo *app = [OTAppInfo infoWithAppPath:path];
        if (app == nil) {
            continue;
        }
        [seen addObject:bundleId];
        [apps addObject:app];
    }

    [apps sortUsingComparator:^NSComparisonResult(OTAppInfo *left, OTAppInfo *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    return apps;
}

- (BOOL)isInstalledWithBundleId:(NSString *)bundleId {
    return [self recordForBundleId:bundleId] != nil;
}

- (NSString *)packageIdentifierForBundleId:(NSString *)bundleId {
    NSDictionary *record = [self recordForBundleId:bundleId];
    NSString *package = record[@"package"];
    return OTStringIsEmpty(package) ? OTPackageIdentifierForBundleId(bundleId) : package;
}

- (NSString *)installedPathForBundleId:(NSString *)bundleId {
    NSDictionary *record = [self recordForBundleId:bundleId];
    NSString *path = record[@"path"];
    if (!OTStringIsEmpty(path) && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return path;
    }
    return [self appPathsByBundleId][bundleId];
}

#pragma mark - Mutations

- (void)recordInstalledAppWithBundleId:(NSString *)bundleId
                               package:(NSString *)package
                                  path:(NSString *)path {
    if (OTStringIsEmpty(bundleId)) {
        return;
    }
    NSMutableArray *records = self.records;
    for (NSInteger index = (NSInteger)records.count - 1; index >= 0; index--) {
        NSDictionary *record = records[index];
        if ([record[@"bundleId"] isEqualToString:bundleId]) {
            [records removeObjectAtIndex:(NSUInteger)index];
        }
    }
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    record[@"bundleId"] = bundleId;
    record[@"package"] = OTNonEmptyString(package, OTPackageIdentifierForBundleId(bundleId));
    if (!OTStringIsEmpty(path)) {
        record[@"path"] = path;
    }
    [records addObject:record];
    [self saveRecords];
}

- (void)removeInstalledAppWithBundleId:(NSString *)bundleId {
    if (OTStringIsEmpty(bundleId)) {
        return;
    }
    NSMutableArray *records = self.records;
    for (NSInteger index = (NSInteger)records.count - 1; index >= 0; index--) {
        NSDictionary *record = records[index];
        if ([record[@"bundleId"] isEqualToString:bundleId]) {
            [records removeObjectAtIndex:(NSUInteger)index];
        }
    }
    [self saveRecords];
}

- (BOOL)uninstallAppAtPath:(NSString *)path bundleId:(NSString *)bundleId error:(NSString **)error {
    NSString *package = [self packageIdentifierForBundleId:bundleId];
    NSString *lastError = nil;
    BOOL removed = NO;

    if (OTHelperIsPrivileged()) {
        OTProcessResult *result = [OTProcessRunner run:OTHelperPath arguments:@[@"remove", package]];
        if (result.succeeded) {
            removed = YES;
        } else {
            lastError = OTNonEmptyString(result.output, @"dpkg failed to remove the package.");
        }
    }

    if (!removed) {
        NSFileManager *manager = [NSFileManager defaultManager];
        NSMutableArray *targets = [NSMutableArray array];
        NSString *bundleName = [path lastPathComponent];
        if (!OTStringIsEmpty(path)) {
            [targets addObject:path];
        }
        if (!OTStringIsEmpty(bundleName)) {
            [targets addObject:[@"/Applications" stringByAppendingPathComponent:bundleName]];
            [targets addObject:[@"/var/stash" stringByAppendingPathComponent:bundleName]];
        }
        for (NSString *target in targets) {
            if (![manager fileExistsAtPath:target]) {
                continue;
            }
            NSError *removeError = nil;
            if ([manager removeItemAtPath:target error:&removeError]) {
                removed = YES;
            } else if (lastError == nil) {
                lastError = removeError.localizedDescription;
            }
        }
    }

    if (removed) {
        [self removeInstalledAppWithBundleId:bundleId];
    }
    [self refreshIconCache];

    if (!removed && error != NULL) {
        *error = lastError ?: @"The app could not be removed. Reinstall OldTroll and try again.";
    }
    return removed;
}

- (BOOL)openAppWithBundleId:(NSString *)bundleId {
    if (OTStringIsEmpty(bundleId)) {
        return NO;
    }

    void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    if (handle != NULL) {
        typedef int (*OTSBSLaunchApplication)(CFStringRef, Boolean);
        OTSBSLaunchApplication launch = (OTSBSLaunchApplication)dlsym(handle, "SBSLaunchApplicationWithIdentifier");
        if (launch != NULL) {
            int result = launch((__bridge CFStringRef)bundleId, false);
            dlclose(handle);
            if (result == 0) {
                return YES;
            }
        } else {
            dlclose(handle);
        }
    }

    NSString *scheme = [bundleId stringByAppendingString:@"://"];
    NSURL *url = [NSURL URLWithString:scheme];
    if (url != nil) {
        return [[UIApplication sharedApplication] openURL:url];
    }
    return NO;
}

- (void)refreshIconCache {
    if (OTHelperIsPrivileged()) {
        [OTProcessRunner run:OTHelperPath arguments:@[@"uicache"]];
        return;
    }
    NSString *uicache = [OTProcessRunner findExecutable:@[@"/usr/bin/uicache", @"/usr/local/bin/uicache"]];
    if (uicache != nil) {
        [OTProcessRunner run:uicache arguments:@[]];
    }
}

#pragma mark - Cache

+ (void)clearCache {
    NSMutableSet *directories = [NSMutableSet setWithObject:@"/tmp"];
    NSString *temporary = NSTemporaryDirectory();
    if (temporary.length > 0) {
        [directories addObject:temporary];
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *directory in directories) {
        NSArray *children = [manager contentsOfDirectoryAtPath:directory error:NULL];
        for (NSString *child in children) {
            if (![child.lowercaseString hasPrefix:@"oldtroll_"]) {
                continue;
            }
            [manager removeItemAtPath:[directory stringByAppendingPathComponent:child] error:NULL];
        }
    }
    [manager removeItemAtPath:@"/tmp/oldtroll_helper.log" error:NULL];
}

@end
