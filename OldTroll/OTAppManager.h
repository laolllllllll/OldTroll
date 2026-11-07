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
                                  path:(NSString *)path;
- (void)removeInstalledAppWithBundleId:(NSString *)bundleId;

// Removes the dpkg package (through the setuid helper). Falls back to removing
// the app bundle and its /Applications symlink if dpkg is unavailable.
- (BOOL)uninstallAppAtPath:(NSString *)path bundleId:(NSString *)bundleId error:(NSString **)error;

- (BOOL)openAppWithBundleId:(NSString *)bundleId;
- (void)refreshIconCache;

// Deletes /tmp/oldtroll_* build products and downloaded IPAs.
+ (void)clearCache;

@end
