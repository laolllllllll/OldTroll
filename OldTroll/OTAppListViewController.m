//
//  OTAppListViewController.m
//  OldTroll
//

#import "OTAppListViewController.h"
#import "OTAlert.h"
#import "OTAppDelegate.h"
#import "OTAppDetailViewController.h"
#import "OTAppInfo.h"
#import "OTAppManager.h"
#import "OTCompat.h"
#import "OTFilePickerViewController.h"
#import "OTInstallRequest.h"
#import "OTNavigationController.h"
#import "OTProgressViewController.h"

#import <QuartzCore/QuartzCore.h>

@interface OTAppListViewController () <UITableViewDataSource, UITableViewDelegate, OTFilePickerViewControllerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray *apps;
@property (nonatomic, assign) NSInteger consumeRetryCount;

@end

@implementation OTAppListViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"OldTroll";

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                           target:self
                                                                                           action:@selector(addButtonTapped:)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64.0;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    self.emptyLabel.font = [UIFont systemFontOfSize:16.0];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.text = @"No apps installed yet\n\nTap + to install an IPA";
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(installRequestReceived:) name:OTInstallRequestReceivedNotification object:nil];
    [center addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshApps];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self consumePendingRequestIfNeeded];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    self.tableView.frame = self.view.bounds;
    CGFloat labelWidth = MIN(width - 60.0, 320.0);
    CGSize fitted = [self.emptyLabel sizeThatFits:CGSizeMake(labelWidth, height)];
    self.emptyLabel.frame = CGRectMake((width - labelWidth) / 2.0,
                                       MAX(80.0, (height - fitted.height) / 2.0 - 40.0),
                                       labelWidth,
                                       fitted.height);
}

#pragma mark - Data

- (void)refreshApps {
    self.apps = [[OTAppManager sharedManager] installedApps];
    self.emptyLabel.hidden = self.apps.count > 0;
    [self.tableView reloadData];
}

- (void)installRequestReceived:(NSNotification *)notification {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self consumePendingRequestIfNeeded];
    });
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self consumePendingRequestIfNeeded];
    });
}

- (void)consumePendingRequestIfNeeded {
    OTAppDelegate *delegate = (OTAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (![delegate respondsToSelector:@selector(takePendingRequest)]) {
        return;
    }

    if (self.presentedViewController != nil) {
        if (self.consumeRetryCount < 8) {
            self.consumeRetryCount++;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self consumePendingRequestIfNeeded];
            });
        }
        return;
    }

    OTInstallRequest *request = [delegate takePendingRequest];
    if (request == nil) {
        self.consumeRetryCount = 0;
        return;
    }
    self.consumeRetryCount = 0;
    [self presentInstallRequest:request];
}

#pragma mark - Add flow

- (void)addButtonTapped:(id)sender {
    __weak typeof(self) weakSelf = self;
    [OTAlert showWithTitle:@"Install"
                   message:nil
              cancelButton:@"Cancel"
                   buttons:@[@"Install IPA File", @"Install from URL"]
                   handler:^(NSInteger buttonIndex, NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (buttonIndex == 1) {
            [strongSelf showFilePicker];
        } else if (buttonIndex == 2) {
            [strongSelf showURLInput];
        }
    }];
}

- (void)showFilePicker {
    OTFilePickerViewController *picker = [[OTFilePickerViewController alloc] initWithPath:@"/"];
    picker.delegate = self;
    OTNavigationController *navigation = [[OTNavigationController alloc] initWithRootViewController:picker];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)showURLInput {
    NSString *prefill = @"";
    NSString *pasteboard = [[UIPasteboard generalPasteboard] string];
    NSString *trimmed = [pasteboard stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0 && ([trimmed hasPrefix:@"http://"] || [trimmed hasPrefix:@"https://"] ||
                               [trimmed hasPrefix:@"cor-oldtroll://"] || [trimmed hasPrefix:@"apple-magnifier://"])) {
        prefill = trimmed;
    }

    __weak typeof(self) weakSelf = self;
    [OTAlert showInputWithTitle:@"Install from URL"
                        message:@"Paste a direct link to an .ipa file."
                    placeholder:@"https://example.com/app.ipa"
                           text:prefill
                   cancelButton:@"Cancel"
                  confirmButton:@"Install"
                        handler:^(NSInteger buttonIndex, NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || buttonIndex != 1) {
            return;
        }
        NSString *reason = nil;
        OTInstallRequest *request = [OTInstallRequest requestWithURLString:text error:&reason];
        if (request == nil) {
            [OTAlert showWithTitle:@"Invalid URL"
                           message:reason ?: @"That link is not a valid IPA download URL."
                      cancelButton:@"OK"
                           buttons:nil
                           handler:nil];
            return;
        }
        [strongSelf presentInstallRequest:request];
    }];
}

- (void)filePicker:(OTFilePickerViewController *)picker didSelectFileAtPath:(NSString *)path {
    NSString *reason = nil;
    OTInstallRequest *request = [OTInstallRequest requestWithFilePath:path error:&reason];
    if (request == nil) {
        [OTAlert showWithTitle:@"Invalid File"
                       message:reason ?: @"The selected file is not an .ipa file."
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        return;
    }
    [self presentInstallRequest:request];
}

- (void)presentInstallRequest:(OTInstallRequest *)request {
    // A picker (or another sheet) may still be on screen. Let it go first so
    // the progress screen is not presented behind a modal.
    if (self.presentedViewController != nil) {
        [self dismissViewControllerAnimated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self presentInstallRequest:request];
            });
        }];
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.presentedViewController != nil) {
            return;
        }

        OTProgressViewController *progress = [[OTProgressViewController alloc] initWithRequest:request];
        progress.completionBlock = ^(BOOL success, OTAppInfo *app, NSString *message) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }
            [innerSelf refreshApps];
            if (success) {
                NSString *title = app.name ?: request.displayString;
                [OTAlert showWithTitle:@"Installation Complete"
                               message:[NSString stringWithFormat:@"Do you want to open %@?", title]
                          cancelButton:@"Close"
                               buttons:@[@"Open"]
                               handler:^(NSInteger buttonIndex, NSString *text) {
                    if (buttonIndex == 1 && app != nil) {
                        if (![[OTAppManager sharedManager] openAppWithBundleId:app.bundleId]) {
                            [OTAlert showWithTitle:@"Failed"
                                           message:[NSString stringWithFormat:@"Could not open %@.", title]
                                      cancelButton:@"OK"
                                           buttons:nil
                                           handler:nil];
                        }
                    }
                }];
            } else if (!OTStringIsEmpty(message)) {
                [OTAlert showWithTitle:@"Installation Failed"
                               message:message
                          cancelButton:@"OK"
                               buttons:nil
                               handler:nil];
            }
        };
        [progress presentOverViewController:strongSelf];
    });
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.layer.cornerRadius = 10.0;
        cell.imageView.layer.masksToBounds = YES;
    }

    OTAppInfo *app = self.apps[(NSUInteger)indexPath.row];
    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@", app.version, app.bundleId];
    cell.imageView.image = app.icon;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    OTAppInfo *app = self.apps[(NSUInteger)indexPath.row];
    OTAppDetailViewController *detail = [[OTAppDetailViewController alloc] initWithAppInfo:app];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
