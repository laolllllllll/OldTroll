//
//  OTAppDelegate.m
//  OldTroll
//

#import "OTAppDelegate.h"
#import "OTAlert.h"
#import "OTAppListViewController.h"
#import "OTCompat.h"
#import "OTInstallRequest.h"
#import "OTNavigationController.h"
#import "OTSettingsViewController.h"
#import "OTTabBarController.h"

NSString * const OTInstallRequestReceivedNotification = @"OTInstallRequestReceivedNotification";
NSString * const OTURLSchemeEnabledKey = @"urlSchemeEnabled";

@interface OTAppDelegate ()
@property (nonatomic, strong) OTInstallRequest *pendingRequest;
@property (nonatomic, copy) NSString *lastHandledURLString;
@property (nonatomic, assign) NSTimeInterval lastHandledTime;
@end

@implementation OTAppDelegate

#pragma mark - Launch

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // The URL-scheme integration is opt-out, not opt-in. Previous versions
    // defaulted to NO, which made external calls silently do nothing.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{OTURLSchemeEnabledKey: @YES}];

    OTAppListViewController *apps = [[OTAppListViewController alloc] init];
    OTNavigationController *appsNavigation = [[OTNavigationController alloc] initWithRootViewController:apps];
    UIImage *appsImage = [UIImage imageNamed:@"tab_apps"];
    if ([appsImage respondsToSelector:@selector(imageWithRenderingMode:)]) {
        appsImage = [appsImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    appsNavigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Apps" image:appsImage tag:0];

    OTSettingsViewController *settings = [[OTSettingsViewController alloc] init];
    OTNavigationController *settingsNavigation = [[OTNavigationController alloc] initWithRootViewController:settings];
    UIImage *settingsImage = [UIImage imageNamed:@"tab_settings"];
    if ([settingsImage respondsToSelector:@selector(imageWithRenderingMode:)]) {
        settingsImage = [settingsImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    settingsNavigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:settingsImage tag:1];

    self.tabBarController = [[OTTabBarController alloc] init];
    self.tabBarController.viewControllers = @[appsNavigation, settingsNavigation];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    self.window.rootViewController = self.tabBarController;
    [self.window makeKeyAndVisible];

    // A cold launch triggered by a URL also receives the URL in launchOptions.
    // Handling both this and openURL: is harmless because duplicate URLs are
    // suppressed below, and it guarantees the URL is never dropped.
    NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
    if (launchURL != nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self handleIncomingURL:launchURL];
        });
    }

    return YES;
}

#pragma mark - URL handling

// iOS 9 and later call this method when it is implemented. On iOS 10 the
// legacy callback alone is not enough, which is why OldTroll 1.0 appeared to
// do nothing when opened from another app.
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    return [self handleIncomingURL:url];
}

// iOS 6-9 (and older SDK compatibility).
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    return [self handleIncomingURL:url];
}

- (BOOL)handleIncomingURL:(NSURL *)url {
    if (url == nil) {
        return NO;
    }

    NSString *scheme = [url.scheme lowercaseString];
    BOOL isOwnScheme = [scheme isEqualToString:@"cor-oldtroll"] ||
                       [scheme isEqualToString:@"apple-magnifier"] ||
                       [scheme isEqualToString:@"file"];
    if (!isOwnScheme) {
        return NO;
    }

    // Both launchOptions and openURL: can deliver the same URL on a cold
    // launch. Suppress the duplicate before a second install is queued.
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (self.lastHandledURLString != nil &&
        [self.lastHandledURLString isEqualToString:url.absoluteString] &&
        now - self.lastHandledTime < 5.0) {
        return YES;
    }
    self.lastHandledURLString = url.absoluteString;
    self.lastHandledTime = now;

    NSString *reason = nil;
    OTInstallRequest *request = [OTInstallRequest requestWithIncomingURL:url error:&reason];
    if (request == nil) {
        NSString *message = reason ?: @"The link does not contain a valid IPA URL.";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [OTAlert showWithTitle:@"Invalid URL"
                           message:message
                      cancelButton:@"OK"
                           buttons:nil
                           handler:nil];
        });
        return YES;
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:OTURLSchemeEnabledKey]) {
        __weak typeof(self) weakSelf = self;
        [OTAlert showWithTitle:@"External URL Call Disabled"
                       message:@"Enable URL Scheme in Settings to install IPAs from links."
                  cancelButton:@"Cancel"
                       buttons:@[@"Enable & Install"]
                       handler:^(NSInteger buttonIndex, NSString *text) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || buttonIndex != 1) {
                return;
            }
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OTURLSchemeEnabledKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [strongSelf enqueueRequest:request];
        }];
        return YES;
    }

    [self enqueueRequest:request];
    return YES;
}

- (void)enqueueRequest:(OTInstallRequest *)request {
    if (request == nil) {
        return;
    }

    NSString *incoming = request.displayString;
    NSString *pending = self.pendingRequest.displayString;
    if (pending != nil && [pending isEqualToString:incoming] &&
        [[NSDate date] timeIntervalSinceDate:self.pendingRequest.createdAt] < 5.0) {
        return;
    }

    self.pendingRequest = request;
    self.tabBarController.selectedIndex = 0;
    [[NSNotificationCenter defaultCenter] postNotificationName:OTInstallRequestReceivedNotification object:nil];
}

- (OTInstallRequest *)takePendingRequest {
    OTInstallRequest *request = self.pendingRequest;
    self.pendingRequest = nil;
    return request;
}

#pragma mark - Lifecycle

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (self.pendingRequest != nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:OTInstallRequestReceivedNotification object:nil];
        });
    }
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    // Icons are the largest in-memory objects OldTroll keeps; releasing them
    // is cheap because the list reloads from disk.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OldTrollMemoryWarning" object:nil];
}

@end
