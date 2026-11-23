//
//  OTInstallMetadataViewController.h
//  OldTroll
//

#import <UIKit/UIKit.h>

@interface OTInstallMetadataViewController : UIViewController

- (instancetype)initWithName:(NSString *)name
                    bundleId:(NSString *)bundleId
                     version:(NSString *)version
                        size:(NSString *)size
                        icon:(UIImage *)icon;

@property (nonatomic, copy) void (^cancelBlock)(void);
@property (nonatomic, copy) void (^installBlock)(void);

@end
