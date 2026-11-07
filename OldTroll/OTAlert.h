//
//  OTAlert.h
//  OldTroll
//
//  UIAlertView wrappers. UIAlertView is deprecated but it is the only alert
//  API that exists on every supported OS (iOS 6 through 10). Using it also
//  avoids the iPad popover crash that UIAlertController action sheets have
//  when they are presented without a source view.
//

#import <UIKit/UIKit.h>

// buttonIndex follows UIAlertView's indexing: 0 is the cancel button when a
// cancel title was supplied, followed by the other buttons in order. `text`
// is non-nil only for input alerts.
typedef void (^OTAlertHandler)(NSInteger buttonIndex, NSString *text);

@interface OTAlert : NSObject

+ (void)showWithTitle:(NSString *)title
              message:(NSString *)message
         cancelButton:(NSString *)cancelButton
              buttons:(NSArray *)otherButtons
              handler:(OTAlertHandler)handler;

// Plain-text input alert (UIAlertViewStylePlainTextInput, available since
// iOS 5). Button index 1 is the confirm button, 0 is cancel.
+ (void)showInputWithTitle:(NSString *)title
                   message:(NSString *)message
               placeholder:(NSString *)placeholder
                      text:(NSString *)text
              cancelButton:(NSString *)cancelButton
             confirmButton:(NSString *)confirmButton
                   handler:(OTAlertHandler)handler;

@end
