//
//  OTProgressViewController.m
//  OldTroll
//

#import "OTProgressViewController.h"
#import "OTAlert.h"
#import "OTAppInfo.h"
#import "OTAppManager.h"
#import "OTCompat.h"
#import "OTIPAPackage.h"
#import "OTInstallRequest.h"

#import <QuartzCore/QuartzCore.h>
#import <sys/stat.h>

static NSString *OTSizeStringForFile(NSString *path) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    NSNumber *bytes = attributes[NSFileSize];
    if (bytes == nil) {
        return @"Unknown";
    }
    double value = bytes.doubleValue;
    if (value >= 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f MB", value / (1024.0 * 1024.0)];
    }
    if (value >= 1024.0) {
        return [NSString stringWithFormat:@"%.0f KB", value / 1024.0];
    }
    return [NSString stringWithFormat:@"%.0f B", value];
}

#pragma mark - Refined spinner

@interface OTRingSpinnerView : UIView
@property (nonatomic, strong) CAShapeLayer *trackLayer;
@property (nonatomic, strong) CAShapeLayer *arcLayer;
- (void)startAnimating;
- (void)stopAnimating;
@end

@implementation OTRingSpinnerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;

        _trackLayer = [CAShapeLayer layer];
        _trackLayer.fillColor = [UIColor clearColor].CGColor;
        _trackLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.26].CGColor;
        _trackLayer.lineWidth = 2.0;
        [self.layer addSublayer:_trackLayer];

        _arcLayer = [CAShapeLayer layer];
        _arcLayer.fillColor = [UIColor clearColor].CGColor;
        _arcLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
        _arcLayer.lineWidth = 2.4;
        _arcLayer.lineCap = kCALineCapRound;
        _arcLayer.strokeStart = 0.0;
        _arcLayer.strokeEnd = 0.34;
        _arcLayer.shadowColor = [UIColor whiteColor].CGColor;
        _arcLayer.shadowOpacity = 0.45;
        _arcLayer.shadowRadius = 2.5;
        _arcLayer.shadowOffset = CGSizeZero;
        [self.layer addSublayer:_arcLayer];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect ringRect = CGRectInset(self.bounds, 2.0, 2.0);
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:ringRect];
    self.trackLayer.frame = self.bounds;
    self.trackLayer.path = path.CGPath;
    self.arcLayer.frame = self.bounds;
    self.arcLayer.path = path.CGPath;
    self.arcLayer.shadowPath = path.CGPath;
}

- (void)startAnimating {
    if ([self.arcLayer animationForKey:@"oldtroll.spin"] != nil) {
        return;
    }
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @(0.0);
    spin.toValue = @(M_PI * 2.0);
    spin.duration = 1.05;
    spin.repeatCount = HUGE_VALF;
    spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self.arcLayer addAnimation:spin forKey:@"oldtroll.spin"];
}

- (void)stopAnimating {
    [self.arcLayer removeAnimationForKey:@"oldtroll.spin"];
}

@end

@interface OTProgressViewController () <NSURLConnectionDataDelegate, NSURLConnectionDelegate, UIAlertViewDelegate>

@property (nonatomic, strong) OTInstallRequest *request;
@property (nonatomic, strong) OTIPAPackage *package;
@property (nonatomic, copy) NSString *packageSize;
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableData *downloadData;
@property (nonatomic, copy) NSString *downloadPath;
@property (nonatomic, assign) long long expectedBytes;
@property (nonatomic, assign) long long receivedBytes;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL installing;
@property (nonatomic, assign) NSTimeInterval lastProgressUpdate;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic, assign) BOOL embedded;

@property (nonatomic, strong) UIAlertView *hudAlert;
@property (nonatomic, strong) OTRingSpinnerView *spinner;
@property (nonatomic, strong) UIAlertView *metadataAlert;

@end

@implementation OTProgressViewController

- (instancetype)initWithRequest:(OTInstallRequest *)request {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _request = request;
        _lastProgressUpdate = 0;
        _backgroundTask = UIBackgroundTaskInvalid;
    }
    return self;
}

- (void)dealloc {
    [_connection cancel];
    _hudAlert.delegate = nil;
    _metadataAlert.delegate = nil;
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
    }
}

- (void)presentOverViewController:(UIViewController *)host {
    UIViewController *container = host;
    if (container.tabBarController != nil) {
        container = container.tabBarController;
    }
    if (container == nil) {
        return;
    }
    self.embedded = YES;
    self.view.frame = container.view.bounds;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addChildViewController:self];
    [container.view addSubview:self.view];
    [self didMoveToParentViewController:container];
    [self beginAppearanceTransition:YES animated:NO];
    [self endAppearanceTransition];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.started) {
        return;
    }
    self.started = YES;
    NSString *title = self.request.isRemote ? @"Downloading" : @"Installing";
    [self showHUDWithTitle:title canCancel:self.request.isRemote];
    [self beginInstall];
}

#pragma mark - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return OT_IS_IPAD ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return OT_IS_IPAD ? YES : (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark - Native HUD

- (void)showHUDWithTitle:(NSString *)title canCancel:(BOOL)canCancel {
    [self hideHUD];

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:OTNonEmptyString(title, @"Installing")
                                                    message:nil
                                                   delegate:self
                                          cancelButtonTitle:canCancel ? @"Cancel" : nil
                                          otherButtonTitles:nil];
    alert.tag = 7001;
    [alert show];

    OTRingSpinnerView *spinner = [[OTRingSpinnerView alloc] initWithFrame:CGRectMake(0.0, 0.0, 30.0, 30.0)];
    [alert addSubview:spinner];
    spinner.center = CGPointMake(CGRectGetMidX(alert.bounds),
                                 CGRectGetMaxY(alert.bounds) - (canCancel ? 64.0 : 32.0));
    [spinner startAnimating];

    self.hudAlert = alert;
    self.spinner = spinner;
}

- (void)hideHUD {
    if (self.spinner != nil) {
        [self.spinner stopAnimating];
        [self.spinner removeFromSuperview];
        self.spinner = nil;
    }
    if (self.hudAlert != nil) {
        UIAlertView *alert = self.hudAlert;
        self.hudAlert = nil;
        alert.delegate = nil;
        [alert dismissWithClickedButtonIndex:0 animated:YES];
    }
}

- (void)didPresentAlertView:(UIAlertView *)alertView {
    if (alertView.tag == 7002 && self.package.icon != nil && alertView.subviews.count > 0) {
        UIView *background = alertView.subviews[0];
        CGFloat iconHeight = 64.0;

        // Grow the native alert upward, keeping it centered, then move its
        // labels and buttons down to make room for the app icon.
        CGRect alertFrame = alertView.frame;
        alertFrame.origin.y -= iconHeight / 2.0;
        alertFrame.size.height += iconHeight;
        alertView.frame = alertFrame;
        background.frame = alertView.bounds;

        for (UIView *view in alertView.subviews) {
            if (view == background || view.tag == 9101) {
                continue;
            }
            CGRect frame = view.frame;
            frame.origin.y += iconHeight;
            view.frame = frame;
        }

        UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, 52.0, 52.0)];
        iconView.tag = 9101;
        iconView.image = self.package.icon;
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.backgroundColor = [UIColor clearColor];
        iconView.layer.cornerRadius = 52.0 * 0.30;
        iconView.layer.masksToBounds = YES;
        iconView.center = CGPointMake(CGRectGetMidX(alertView.bounds), 12.0 + 26.0);
        [alertView addSubview:iconView];
    }
    if (alertView == self.hudAlert && self.spinner != nil) {
        BOOL hasCancel = alertView.cancelButtonIndex != -1;
        self.spinner.center = CGPointMake(CGRectGetMidX(alertView.bounds),
                                          CGRectGetMaxY(alertView.bounds) - (hasCancel ? 64.0 : 32.0));
    }
}

#pragma mark - Flow

- (NSString *)installActivityText {
    return self.request.isRemote ? @"Installing from url" : @"Installing";
}

- (void)beginInstall {
    if (self.request.isRemote) {
        [self startDownload];
    } else {
        [self processFileAtPath:self.request.sourceURL.path];
    }
}

- (void)startDownload {
    self.downloadData = [NSMutableData data];
    self.receivedBytes = 0;
    self.expectedBytes = -1;
    self.downloadPath = [NSString stringWithFormat:@"/tmp/oldtroll_download_%ld_%u.ipa",
                         (long)[[NSDate date] timeIntervalSince1970], arc4random()];

    [self updateProgress:0.0 status:@"Downloading"];

    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:self.request.sourceURL
                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                            timeoutInterval:300.0];
    self.connection = [NSURLConnection connectionWithRequest:urlRequest delegate:self];
}

- (void)processFileAtPath:(NSString *)path {
    if (self.cancelled) {
        return;
    }
    [self updateProgress:0.0 status:[self installActivityText]];
    self.packageSize = OTSizeStringForFile(path);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        OTIPAPackage *package = [[OTIPAPackage alloc] initWithIPAPath:path];
        BOOL parsed = [package parseIPAWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.cancelled) {
                [package cleanup];
                return;
            }
            if (!parsed) {
                [package cleanup];
                [self failWithMessage:error.localizedDescription ?: @"Could not read the IPA."];
                return;
            }
            self.package = package;
            [self showInstallConfirmation];
        });
    });
}

- (void)showInstallConfirmation {
    [self hideHUD];

    NSString *message = [NSString stringWithFormat:
        @"Metadata\n\nBundle Identifier: %@\nVersion: %@\nSize: %@",
        OTNonEmptyString(self.package.bundleId, @"unknown"),
        OTNonEmptyString(self.package.version, @"Unknown"),
        OTNonEmptyString(self.packageSize, @"Unknown")];

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:OTNonEmptyString(self.package.appName, @"Install IPA")
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Install", nil];
    alert.tag = 7002;

    [alert show];
    self.metadataAlert = alert;

}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 7002) {
        self.metadataAlert = nil;
        if (buttonIndex == 1) {
            [self showHUDWithTitle:[self installActivityText] canCancel:NO];
            [self installPackage];
        } else {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakSelf cancelWithMessage:nil];
            });
        }
        return;
    }

    if (alertView.tag == 7001 && buttonIndex == alertView.cancelButtonIndex) {
        if (!self.installing) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakSelf cancelWithMessage:nil];
            });
        }
    }
}

- (void)installPackage {
    if (self.cancelled || self.package == nil) {
        return;
    }

    self.installing = YES;
    [self beginBackgroundTaskIfPossible];
    [self updateProgress:0.05 status:[self installActivityText]];

    OTIPAPackage *package = self.package;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(self) strongSelf = self;
        if (strongSelf == nil) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf updateProgress:0.35 status:[strongSelf installActivityText]];
        });

        NSError *error = nil;
        [package installIPAWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error == nil) {
                [strongSelf finishWithSuccess:YES message:@"Installation complete!" appPath:package.installedPath];
            } else {
                [strongSelf failWithMessage:error.localizedDescription ?: @"Installation failed."];
            }
        });
    });
}

#pragma mark - State changes

- (void)updateProgress:(CGFloat)progress status:(NSString *)status {
    if (self.finished) {
        return;
    }
    if (!OTStringIsEmpty(status) && self.hudAlert != nil) {
        self.hudAlert.title = status;
    }
}

- (void)beginBackgroundTaskIfPossible {
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf.backgroundTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:strongSelf.backgroundTask];
            strongSelf.backgroundTask = UIBackgroundTaskInvalid;
        }
    }];
}

- (void)endBackgroundTask {
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
}

- (void)dismissAfterCompletion:(void (^)(void))completion {
    if (self.embedded) {
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
        if (completion != nil) {
            completion();
        }
        return;
    }
    [self dismissViewControllerAnimated:YES completion:completion];
}

- (void)finishWithSuccess:(BOOL)success message:(NSString *)message appPath:(NSString *)appPath {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    [self hideHUD];

    OTAppInfo *app = nil;
    if (success && !OTStringIsEmpty(appPath)) {
        app = [OTAppInfo infoWithAppPath:appPath];
    }

    [self endBackgroundTask];
    if (!success && OTStringIsEmpty(message)) {
        message = @"Installation failed.";
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(success ? 0.65 * NSEC_PER_SEC : 0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (strongSelf.package != nil) {
            [strongSelf.package cleanup];
        }
        if (!OTStringIsEmpty(strongSelf.downloadPath)) {
            [[NSFileManager defaultManager] removeItemAtPath:strongSelf.downloadPath error:NULL];
            strongSelf.downloadPath = nil;
        }
        OTProgressCompletionBlock completion = strongSelf.completionBlock;
        [strongSelf dismissAfterCompletion:^{
            if (completion != nil) {
                completion(success, app, message);
            }
        }];
    });
}

- (void)failWithMessage:(NSString *)message {
    [self finishWithSuccess:NO message:message appPath:nil];
}

- (void)cancelWithMessage:(NSString *)message {
    if (self.finished) {
        return;
    }
    self.cancelled = YES;
    [self.connection cancel];
    self.connection = nil;
    [self hideHUD];

    if (self.downloadPath != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadPath error:NULL];
        self.downloadPath = nil;
    }

    if (self.package != nil) {
        [self.package cleanup];
    }
    self.finished = YES;
    [self endBackgroundTask];

    OTProgressCompletionBlock completion = self.completionBlock;
    __weak typeof(self) weakSelf = self;
    [self dismissAfterCompletion:^{
        if (completion != nil) {
            completion(NO, nil, message);
        }
        (void)weakSelf;
    }];
}

#pragma mark - Download delegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    if (self.finished || self.cancelled) {
        return;
    }
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (statusCode < 200 || statusCode >= 300) {
            [connection cancel];
            [self failWithMessage:[NSString stringWithFormat:@"Download failed (HTTP %ld).", (long)statusCode]];
            return;
        }
    }
    self.expectedBytes = response.expectedContentLength;
    [self updateProgress:0.0 status:@"Downloading"];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (self.finished || self.cancelled) {
        return;
    }
    [self.downloadData appendData:data];
    self.receivedBytes += (long long)data.length;

    CGFloat progress = -1.0;
    if (self.expectedBytes > 0) {
        progress = (CGFloat)self.receivedBytes / (CGFloat)self.expectedBytes;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastProgressUpdate > 0.1) {
        self.lastProgressUpdate = now;
        [self updateProgress:progress status:@"Downloading"];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    self.connection = nil;
    if (self.finished || self.cancelled) {
        return;
    }

    if (self.downloadData.length < 1024) {
        [self failWithMessage:@"The downloaded file is too small to be an IPA."];
        return;
    }

    if (![self.downloadData writeToFile:self.downloadPath atomically:YES]) {
        [self failWithMessage:@"Could not save the downloaded IPA to /tmp."];
        return;
    }

    NSData *prefix = [self.downloadData subdataWithRange:NSMakeRange(0, MIN((NSUInteger)4, self.downloadData.length))];
    const uint8_t *bytes = prefix.bytes;
    if (prefix.length < 2 || bytes[0] != 'P' || bytes[1] != 'K') {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadPath error:NULL];
        [self failWithMessage:@"The downloaded file is not an IPA. The link may have returned an HTML page."];
        return;
    }

    [self updateProgress:1.0 status:[self installActivityText]];
    [self processFileAtPath:self.downloadPath];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    self.connection = nil;
    if (self.cancelled || self.finished) {
        return;
    }
    [self failWithMessage:[NSString stringWithFormat:@"Download failed: %@", error.localizedDescription]];
}

@end
