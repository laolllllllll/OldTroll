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
#import "OTInstallMetadataViewController.h"
#import "OTInstallRequest.h"

#import <QuartzCore/QuartzCore.h>
#import <sys/stat.h>

static UIImage *OTWindowSnapshot(void) {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (window == nil || window.bounds.size.width < 1.0 || window.bounds.size.height < 1.0) {
        return nil;
    }
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 1.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context != NULL) {
        [window.layer renderInContext:context];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

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

@interface OTProgressViewController () <NSURLConnectionDataDelegate, NSURLConnectionDelegate>

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

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImage *backgroundSnapshot;
@property (nonatomic, assign) BOOL embedded;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *cancelButton;

@end

@implementation OTProgressViewController

- (instancetype)initWithRequest:(OTInstallRequest *)request {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _request = request;
        _lastProgressUpdate = 0;
        _backgroundTask = UIBackgroundTaskInvalid;
        _backgroundSnapshot = OTWindowSnapshot();
    }
    return self;
}

- (void)dealloc {
    [_connection cancel];
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

    self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    if (!self.embedded && self.backgroundSnapshot != nil) {
        UIImageView *backgroundView = [[UIImageView alloc] initWithFrame:self.view.bounds];
        backgroundView.image = self.backgroundSnapshot;
        backgroundView.contentMode = UIViewContentModeScaleToFill;
        backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:backgroundView];
    }
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    self.cardView = [[UIView alloc] initWithFrame:CGRectZero];
    self.cardView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.97];
    self.cardView.layer.cornerRadius = 14.0;
    self.cardView.layer.masksToBounds = YES;
    [self.view addSubview:self.cardView];

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.hidden = YES;
    [self.cardView addSubview:self.iconView];

    // Keep these views for state updates, but the TrollStore-style HUD only
    // shows the spinner and the current activity text.
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.hidden = YES;
    [self.cardView addSubview:self.titleLabel];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progress = 0.0;
    self.progressView.hidden = YES;
    [self.cardView addSubview:self.progressView];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:17.0];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.text = @"Installing";
    [self.cardView addSubview:self.statusLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.transform = CGAffineTransformMakeScale(1.45, 1.45);
    [self.cardView addSubview:self.spinner];

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:15.0];
    self.cancelButton.hidden = YES;
    [self.cancelButton addTarget:self action:@selector(cancelTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.cancelButton];

    [self.view setNeedsLayout];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.started) {
        self.started = YES;
        [self beginInstall];
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self layoutContent];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration {
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
    [self.view setNeedsLayout];
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

#pragma mark - Layout

- (void)layoutContent {
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat cardWidth = MIN(OT_IS_IPAD ? 300.0 : 250.0, width - 40.0);
    BOOL showsCancel = !self.cancelButton.hidden;
    CGFloat cardHeight = showsCancel ? 178.0 : 136.0;

    self.cardView.frame = CGRectMake((width - cardWidth) / 2.0,
                                     (height - cardHeight) / 2.0,
                                     cardWidth,
                                     cardHeight);

    self.spinner.frame = CGRectMake((cardWidth - 24.0) / 2.0, 26.0, 24.0, 24.0);
    self.statusLabel.frame = CGRectMake(14.0, 66.0, cardWidth - 28.0, 44.0);
    self.cancelButton.frame = CGRectMake((cardWidth - 120.0) / 2.0, 122.0, 120.0, 40.0);
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

    self.cancelButton.hidden = NO;
    [self updateProgress:0.0 status:@"Downloading"];
    [self.spinner startAnimating];
    [self.view setNeedsLayout];

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
    [self.spinner startAnimating];
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
            if (package.icon != nil) {
                self.iconView.image = package.icon;
                self.iconView.hidden = NO;
            }
            self.titleLabel.text = package.appName;
            [self.spinner stopAnimating];
            [self.view setNeedsLayout];
            [self showInstallConfirmation];
        });
    });
}

- (void)showInstallConfirmation {
    self.spinner.hidden = YES;
    self.cardView.hidden = YES;
    self.view.backgroundColor = [UIColor clearColor];

    OTInstallMetadataViewController *metadata =
        [[OTInstallMetadataViewController alloc] initWithName:self.package.appName
                                                     bundleId:self.package.bundleId
                                                      version:self.package.version
                                                         size:self.packageSize
                                                         icon:self.package.icon];
    metadata.modalPresentationStyle = UIModalPresentationCurrentContext;

    __weak typeof(self) weakSelf = self;
    metadata.cancelBlock = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf cancelWithMessage:nil];
        }
    };
    metadata.installBlock = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.cardView.hidden = NO;
        strongSelf.spinner.hidden = NO;
        strongSelf.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
        [strongSelf installPackage];
    };
    [self presentViewController:metadata animated:YES completion:nil];
}

- (void)installPackage {
    if (self.cancelled || self.package == nil) {
        return;
    }

    self.installing = YES;
    self.cancelButton.hidden = YES;
    self.cancelButton.enabled = NO;
    [self.view setNeedsLayout];
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
    if (status.length > 0) {
        self.statusLabel.text = status;
    }
    if (progress >= 0.0) {
        self.progressView.progress = MAX(0.0, MIN(1.0, progress));
    }
    [self.view setNeedsLayout];
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
    self.cancelButton.hidden = YES;
    [self.spinner stopAnimating];

    OTAppInfo *app = nil;
    if (success && !OTStringIsEmpty(appPath)) {
        app = [OTAppInfo infoWithAppPath:appPath];
    }
    if (success) {
        self.statusLabel.text = @"Installation complete!";
        self.progressView.progress = 1.0;
    } else {
        self.statusLabel.text = @"Installation Failed";
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
    [self.spinner stopAnimating];

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

- (void)cancelTapped:(id)sender {
    if (self.installing) {
        return;
    }
    [self cancelWithMessage:nil];
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
    [self.spinner stopAnimating];

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
