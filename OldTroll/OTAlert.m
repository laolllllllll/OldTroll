//
//  OTAlert.m
//  OldTroll
//

#import "OTAlert.h"
#import "OTCompat.h"
#import <objc/runtime.h>

static const void *OTAlertDelegateKey = &OTAlertDelegateKey;

@interface OTAlert () <UIAlertViewDelegate>
@property (nonatomic, copy) OTAlertHandler handler;
@property (nonatomic, assign) BOOL inputMode;
@property (nonatomic, assign) BOOL finished;
@end

@implementation OTAlert

+ (void)attach:(OTAlert *)delegate toAlert:(UIAlertView *)alert {
    // UIAlertView's delegate is an assign property. Associate the delegate so
    // it stays alive for exactly as long as the alert does.
    objc_setAssociatedObject(alert, OTAlertDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [alert show];
}

+ (void)showWithTitle:(NSString *)title
              message:(NSString *)message
         cancelButton:(NSString *)cancelButton
              buttons:(NSArray *)otherButtons
              handler:(OTAlertHandler)handler {
    OTAlert *delegate = [[OTAlert alloc] init];
    delegate.handler = handler;

    NSString *cancel = OTStringIsEmpty(cancelButton) ? @"OK" : cancelButton;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                   message:message
                                                  delegate:delegate
                                         cancelButtonTitle:cancel
                                         otherButtonTitles:nil];
    for (NSString *button in otherButtons) {
        if (OTStringIsEmpty(button)) {
            continue;
        }
        [alert addButtonWithTitle:button];
    }
    [self attach:delegate toAlert:alert];
}

+ (void)showInputWithTitle:(NSString *)title
                   message:(NSString *)message
               placeholder:(NSString *)placeholder
                      text:(NSString *)text
              cancelButton:(NSString *)cancelButton
             confirmButton:(NSString *)confirmButton
                   handler:(OTAlertHandler)handler {
    OTAlert *delegate = [[OTAlert alloc] init];
    delegate.handler = handler;
    delegate.inputMode = YES;

    NSString *cancel = OTStringIsEmpty(cancelButton) ? @"Cancel" : cancelButton;
    NSString *confirm = OTStringIsEmpty(confirmButton) ? @"Install" : confirmButton;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                   message:message
                                                  delegate:delegate
                                         cancelButtonTitle:cancel
                                         otherButtonTitles:confirm, nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.placeholder = placeholder;
    field.text = text;
    field.keyboardType = UIKeyboardTypeURL;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    [self attach:delegate toAlert:alert];
}

#pragma mark - UIAlertViewDelegate

- (BOOL)alertViewShouldEnableFirstOtherButton:(UIAlertView *)alertView {
    if (!self.inputMode) {
        return YES;
    }
    UITextField *field = [alertView textFieldAtIndex:0];
    NSString *value = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return value.length > 0;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (self.finished) {
        return;
    }
    self.finished = YES;

    NSString *text = nil;
    if (self.inputMode) {
        text = [[alertView textFieldAtIndex:0] text];
    }

    OTAlertHandler callback = self.handler;
    self.handler = nil;
    if (callback) {
        // With a cancel button title supplied, UIAlertView indexes it as 0 and
        // the remaining buttons as 1..n, which is exactly what callers expect.
        callback(buttonIndex, text);
    }
}

- (void)alertViewCancel:(UIAlertView *)alertView {
    [self alertView:alertView clickedButtonAtIndex:0];
}

@end

UIViewController *OTTopViewController(void) {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (window == nil || !window.isKeyWindow) {
        for (UIWindow *candidate in [[UIApplication sharedApplication] windows]) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
    }

    UIViewController *controller = window.rootViewController;
    NSInteger guard = 0;
    while (controller != nil && guard < 12) {
        guard++;
        UIViewController *presented = controller.presentedViewController;
        if (presented != nil && presented != controller) {
            controller = presented;
            continue;
        }
        if ([controller isKindOfClass:[UITabBarController class]]) {
            UIViewController *selected = [(UITabBarController *)controller selectedViewController];
            if (selected == nil) {
                break;
            }
            controller = selected;
            continue;
        }
        if ([controller isKindOfClass:[UINavigationController class]]) {
            UIViewController *top = [(UINavigationController *)controller topViewController];
            if (top == nil) {
                break;
            }
            controller = top;
            continue;
        }
        break;
    }
    return controller;
}
