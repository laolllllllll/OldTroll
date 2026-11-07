//
//  OTAppDetailViewController.m
//  OldTroll
//

#import "OTAppDetailViewController.h"
#import "OTAlert.h"
#import "OTAppInfo.h"
#import "OTAppManager.h"
#import "OTCompat.h"

#import <QuartzCore/QuartzCore.h>

@interface OTAppDetailViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) OTAppInfo *appInfo;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation OTAppDetailViewController

- (instancetype)initWithAppInfo:(OTAppInfo *)appInfo {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _appInfo = appInfo;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.appInfo.name;
    self.view.backgroundColor = [UIColor whiteColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 160.0)];
    self.headerView.backgroundColor = [UIColor clearColor];

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.layer.cornerRadius = 14.0;
    self.iconView.layer.masksToBounds = YES;
    self.iconView.image = self.appInfo.icon;
    [self.headerView addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.backgroundColor = [UIColor clearColor];
    self.nameLabel.font = [UIFont boldSystemFontOfSize:20.0];
    self.nameLabel.textColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.text = self.appInfo.name;
    [self.headerView addSubview:self.nameLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    self.subtitleLabel.font = [UIFont systemFontOfSize:13.0];
    self.subtitleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@ - %@", self.appInfo.version, self.appInfo.bundleId];
    [self.headerView addSubview:self.subtitleLabel];

    self.tableView.tableHeaderView = self.headerView;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (self.headerView.frame.size.width != width) {
        self.headerView.frame = CGRectMake(0, 0, width, 160.0);
        self.tableView.tableHeaderView = self.headerView;
    }

    CGFloat iconSize = 72.0;
    self.iconView.frame = CGRectMake((width - iconSize) / 2.0, 12.0, iconSize, iconSize);
    self.nameLabel.frame = CGRectMake(20.0, 92.0, width - 40.0, 26.0);
    self.subtitleLabel.frame = CGRectMake(20.0, 120.0, width - 40.0, 20.0);
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Actions" : @"Information";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && indexPath.row == 3) {
        return 56.0;
    }
    return 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *actionIdentifier = @"ActionCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actionIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:actionIdentifier];
            cell.textLabel.font = [UIFont systemFontOfSize:16.0];
        }
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Open";
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.35 blue:0.85 alpha:1.0];
        } else {
            cell.textLabel.text = @"Uninstall";
            cell.textLabel.textColor = [UIColor redColor];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    static NSString *infoIdentifier = @"InfoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:infoIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:infoIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSArray *titles = @[@"Name", @"Version", @"Bundle ID", @"Path"];
    NSArray *values = @[OTNonEmptyString(self.appInfo.name, @"Unknown"),
                        OTNonEmptyString(self.appInfo.version, @"Unknown"),
                        OTNonEmptyString(self.appInfo.bundleId, @"Unknown"),
                        OTNonEmptyString(self.appInfo.appPath, @"Unknown")];
    cell.textLabel.text = titles[(NSUInteger)indexPath.row];
    cell.detailTextLabel.text = values[(NSUInteger)indexPath.row];
    if (indexPath.row == 3) {
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) {
        return;
    }
    if (indexPath.row == 0) {
        [self openApp];
    } else {
        [self confirmUninstall];
    }
}

#pragma mark - Actions

- (void)openApp {
    if ([[OTAppManager sharedManager] openAppWithBundleId:self.appInfo.bundleId]) {
        return;
    }
    [OTAlert showWithTitle:@"Failed"
                   message:[NSString stringWithFormat:@"Could not open %@.", self.appInfo.name]
              cancelButton:@"OK"
                   buttons:nil
                   handler:nil];
}

- (void)confirmUninstall {
    __weak typeof(self) weakSelf = self;
    [OTAlert showWithTitle:@"Confirm Uninstall"
                   message:[NSString stringWithFormat:@"Are you sure you want to uninstall %@?", self.appInfo.name]
              cancelButton:@"Cancel"
                   buttons:@[@"Uninstall"]
                   handler:^(NSInteger buttonIndex, NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || buttonIndex != 1) {
            return;
        }

        NSString *error = nil;
        BOOL removed = [[OTAppManager sharedManager] uninstallAppAtPath:strongSelf.appInfo.appPath
                                                               bundleId:strongSelf.appInfo.bundleId
                                                                  error:&error];
        if (!removed) {
            [OTAlert showWithTitle:@"Uninstall failed"
                           message:error ?: @"The app could not be removed."
                      cancelButton:@"OK"
                           buttons:nil
                           handler:nil];
            return;
        }
        [strongSelf.navigationController popViewControllerAnimated:YES];
    }];
}

@end
