//
//  OTCompat.h
//  OldTroll
//
//  Shared compatibility helpers. OldTroll targets iOS 6.0 - 10.x on armv7,
//  so everything in the app must stay callable on UIKit from that era.
//

#ifndef OLD_TROLL_COMPAT_H
#define OLD_TROLL_COMPAT_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <unistd.h>

#define OT_VERSION_STRING @"1.1"

#define OT_IS_IPAD (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define OT_SYSTEM_VERSION ([[[UIDevice currentDevice] systemVersion] floatValue])
#define OT_IS_IOS8_OR_LATER (OT_SYSTEM_VERSION >= 8.0)

// Posted whenever the app delegate has queued an incoming install request.
extern NSString * const OTInstallRequestReceivedNotification;

// NSUserDefaults key backing the "URL Scheme Enabled" switch.
extern NSString * const OTURLSchemeEnabledKey;

static inline BOOL OTStringIsEmpty(NSString *value) {
    return value == nil || ![value isKindOfClass:[NSString class]] || value.length == 0;
}

static inline NSString *OTNonEmptyString(NSString *value, NSString *fallback) {
    return OTStringIsEmpty(value) ? fallback : value;
}

static inline BOOL OTIsExecutable(NSString *path) {
    return !OTStringIsEmpty(path) && access([path fileSystemRepresentation], X_OK) == 0;
}

// Returns the top-most view controller currently on screen, walking through
// presented controllers, tab bars and navigation stacks. Used by alerts that
// can be triggered from a URL callback at any point in the app's lifetime.
UIViewController *OTTopViewController(void);

// Turns a bundle identifier into a valid, lowercase Debian package name.
NSString *OTPackageIdentifierForBundleId(NSString *bundleId);

#endif /* OLD_TROLL_COMPAT_H */
