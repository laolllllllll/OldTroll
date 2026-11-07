//
//  OTAppDelegate.h
//  OldTroll
//

#import <UIKit/UIKit.h>

@class OTInstallRequest;
@class OTTabBarController;

@interface OTAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) OTTabBarController *tabBarController;

// Returns and clears the install request queued by a URL callback. The apps
// list pulls this when it appears, which covers cold launches where a
// notification can fire before any view controller exists.
- (OTInstallRequest *)takePendingRequest;

@end
