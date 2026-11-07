//
//  OTTabBarController.m
//  OldTroll
//

#import "OTTabBarController.h"
#import "OTCompat.h"

@implementation OTTabBarController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // iPad supports all four orientations. iPhone stays portrait, matching
    // the Info.plist orientation list.
    return OT_IS_IPAD ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return OT_IS_IPAD ? YES : (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
