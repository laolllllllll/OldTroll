//
//  OTFilePickerViewController.h
//  OldTroll
//

#import <UIKit/UIKit.h>

@class OTFilePickerViewController;

@protocol OTFilePickerViewControllerDelegate <NSObject>
- (void)filePicker:(OTFilePickerViewController *)picker didSelectFileAtPath:(NSString *)path;
@end

@interface OTFilePickerViewController : UIViewController

- (instancetype)initWithPath:(NSString *)path;

@property (nonatomic, weak) id<OTFilePickerViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *currentPath;

@end
