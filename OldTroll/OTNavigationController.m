//
//  OTNavigationController.m
//  OldTroll
//

#import "OTNavigationController.h"
#import "OTCompat.h"

@implementation OTNavigationController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return OT_IS_IPAD ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return OT_IS_IPAD ? YES : (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
