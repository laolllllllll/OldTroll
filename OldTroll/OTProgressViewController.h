//
//  OTProgressViewController.h
//  OldTroll
//
//  One screen owns the whole URL-scheme install: download (if needed),
//  inspect the IPA, install through appinst, and report back.
//

#import <UIKit/UIKit.h>

@class OTAppInfo;
@class OTInstallRequest;

typedef void (^OTProgressCompletionBlock)(BOOL success, OTAppInfo *app, NSString *message);

@interface OTProgressViewController : UIViewController

- (instancetype)initWithRequest:(OTInstallRequest *)request;

// Keeps the Apps list visible underneath instead of presenting a blank modal
// context. The caller should pass its tab bar controller when available.
- (void)presentOverViewController:(UIViewController *)host;

@property (nonatomic, copy) OTProgressCompletionBlock completionBlock;

@end
