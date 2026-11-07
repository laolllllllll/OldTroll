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

@interface OTProgressViewController () <NSURLConnectionDataDelegate, NSURLConnectionDelegate>

@property (nonatomic, strong) OTInstallRequest *request;
@property (nonatomic, strong) OTIPAPackage *package;
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
    }
    return self;
}

- (void)dealloc {
    [_connection cancel];
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
    }
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    self.cardView = [[UIView alloc] initWithFrame:CGRectZero];
    self.cardView.backgroundColor = [UIColor whiteColor];
    self.cardView.layer.cornerRadius = 12.0;
    self.cardView.layer.borderWidth = 1.0;
    self.cardView.layer.borderColor = [UIColor colorWithWhite:0.88 alpha:1.0].CGColor;
    self.cardView.layer.masksToBounds = YES;
    [self.view addSubview:self.cardView];

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.hidden = YES;
    [self.cardView addSubview:self.iconView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
    self.titleLabel.textColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.text = @"Config IPA...";
    [self.cardView addSubview:self.titleLabel];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progress = 0.0;
    [self.cardView addSubview:self.progressView];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14.0];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 3;
    self.statusLabel.text = @"Preparing...";
    [self.cardView addSubview:self.statusLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.cardView addSubview:self.spinner];

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:17.0];
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
    CGFloat horizontalMargin = OT_IS_IPAD ? 60.0 : 20.0;
    CGFloat cardWidth = MIN(OT_IS_IPAD ? 500.0 : 380.0, width - horizontalMargin * 2.0);
    if (cardWidth < 240.0) {
        cardWidth = width - 16.0;
    }
    CGFloat innerWidth = cardWidth - 48.0;

    BOOL showsIcon = !self.iconView.hidden;
    CGFloat titleHeight = 32.0;
    CGFloat progressHeight = 8.0;
    CGFloat statusHeight = 54.0;
    CGFloat spinnerHeight = 20.0;
    CGFloat buttonHeight = 40.0;
    CGFloat verticalPadding = 28.0;
    CGFloat iconBlock = showsIcon ? (72.0 + 12.0) : 0.0;

    CGFloat totalHeight = verticalPadding + iconBlock + titleHeight + 22.0 +
                          progressHeight + 14.0 + statusHeight + 12.0 + spinnerHeight + 18.0 +
                          buttonHeight + verticalPadding;
    CGFloat cardY = MAX(24.0, (height - totalHeight) / 2.0);
    CGFloat cardX = (width - cardWidth) / 2.0;
    self.cardView.frame = CGRectMake(cardX, cardY, cardWidth, totalHeight);

    CGFloat cursor = verticalPadding;
    if (showsIcon) {
        self.iconView.frame = CGRectMake((cardWidth - 72.0) / 2.0, cursor, 72.0, 72.0);
        cursor += 72.0 + 12.0;
    }

    self.titleLabel.frame = CGRectMake(24.0, cursor, innerWidth, titleHeight);
    cursor += titleHeight + 22.0;

    self.progressView.frame = CGRectMake(24.0, cursor, innerWidth, progressHeight);
    cursor += progressHeight + 14.0;

    self.statusLabel.frame = CGRectMake(24.0, cursor, innerWidth, statusHeight);
    cursor += statusHeight + 12.0;

    self.spinner.frame = CGRectMake((cardWidth - spinnerHeight) / 2.0, cursor, spinnerHeight, spinnerHeight);
    cursor += spinnerHeight + 18.0;

    self.cancelButton.frame = CGRectMake((cardWidth - 130.0) / 2.0, cursor, 130.0, buttonHeight);
}

#pragma mark - Flow

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

    [self updateProgress:0.0 status:@"Downloading..."];
    [self.spinner startAnimating];

    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:self.request.sourceURL
                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                            timeoutInterval:300.0];
    self.connection = [NSURLConnection connectionWithRequest:urlRequest delegate:self];
}

- (void)processFileAtPath:(NSString *)path {
    if (self.cancelled) {
        return;
    }
    [self updateProgress:0.0 status:@"Config IPA..."];
    [self.spinner startAnimating];

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

            if (self.request.isAutomatic) {
                [self buildAndInstall];
            } else {
                [self showInstallConfirmation];
            }
        });
    });
}

- (void)showInstallConfirmation {
    NSString *message = [NSString stringWithFormat:@"Name: %@\nVersion: %@\nBundle ID: %@",
                         self.package.appName, self.package.version, self.package.bundleId];
    __weak typeof(self) weakSelf = self;
    [OTAlert showWithTitle:@"Confirm Install"
                   message:message
              cancelButton:@"Cancel"
                   buttons:@[@"Install"]
                   handler:^(NSInteger buttonIndex, NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (buttonIndex == 1) {
            [strongSelf buildAndInstall];
        } else {
            [strongSelf cancelWithMessage:nil];
        }
    }];
}

- (void)buildAndInstall {
    if (self.cancelled || self.package == nil) {
        return;
    }

    self.installing = YES;
    self.cancelButton.enabled = NO;
    self.cancelButton.alpha = 0.4;
    [self beginBackgroundTaskIfPossible];
    [self updateProgress:0.05 status:@"Preparing..."];

    OTIPAPackage *package = self.package;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSError *error = nil;
        BOOL built = [package buildDebWithProgress:^(CGFloat progress, NSString *status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) innerSelf = weakSelf;
                if (innerSelf == nil || innerSelf.cancelled) {
                    return;
                }
                CGFloat mapped = 0.05 + (progress * 0.80);
                [innerSelf updateProgress:mapped status:status];
            });
        } error:&error];

        if (!built) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf failWithMessage:error.localizedDescription ?: @"Could not build the installation package."];
            });
            return;
        }
        if (strongSelf.cancelled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf cancelWithMessage:nil];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf updateProgress:0.90 status:@"Installing package..."];
            [strongSelf.spinner startAnimating];
        });

        NSError *installError = nil;
        BOOL installed = [package installDebWithError:&installError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (installed) {
                [strongSelf finishWithSuccess:YES message:@"Installation complete!" appPath:package.installPath];
            } else {
                [strongSelf failWithMessage:installError.localizedDescription ?: @"Installation failed."];
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
        [strongSelf dismissViewControllerAnimated:YES completion:^{
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
    [self dismissViewControllerAnimated:YES completion:^{
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
    [self updateProgress:0.0 status:@"Downloading..."];
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
        if (self.expectedBytes > 0) {
            NSString *status = [NSString stringWithFormat:@"Downloading... %ld%%",
                                (long)((self.receivedBytes * 100) / self.expectedBytes)];
            [self updateProgress:progress status:status];
        } else {
            [self updateProgress:-1.0 status:@"Downloading..."];
        }
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

    [self updateProgress:1.0 status:@"Config IPA..."];
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
