//
//  OTAppManager.h
//  OldTroll
//
//  Tracks apps that were installed through OldTroll and exposes the handful
//  of privileged operations the UI needs.
//

#import <UIKit/UIKit.h>

@class OTAppInfo;

@interface OTAppManager : NSObject

+ (instancetype)sharedManager;

// Sorted by display name. Only apps recorded by OldTroll are included.
- (NSArray *)installedApps;

- (BOOL)isInstalledWithBundleId:(NSString *)bundleId;
- (NSString *)packageIdentifierForBundleId:(NSString *)bundleId;
- (NSString *)installedPathForBundleId:(NSString *)bundleId;

- (void)recordInstalledAppWithBundleId:(NSString *)bundleId
                               package:(NSString *)package
                                  path:(NSString *)path
                                method:(NSString *)method;
- (void)removeInstalledAppWithBundleId:(NSString *)bundleId;

// Uninstalls through appinst for AppSync installs. OldTroll 1.x records still
// use dpkg so upgrades do not leave orphaned application bundles behind.
- (BOOL)uninstallAppAtPath:(NSString *)path bundleId:(NSString *)bundleId error:(NSString **)error;

- (BOOL)openAppWithBundleId:(NSString *)bundleId;
- (void)refreshIconCache;

// Deletes /tmp/oldtroll_* preview files and downloaded IPAs.
+ (void)clearCache;

@end
