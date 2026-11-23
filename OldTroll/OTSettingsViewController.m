//
//  OTSettingsViewController.m
//  OldTroll
//

#import "OTSettingsViewController.h"
#import "OTAlert.h"
#import "OTAppManager.h"
#import "OTCompat.h"
#import "OTDonateViewController.h"
#import "OTIPAPackage.h"
#import "OTProcessRunner.h"
#import "OTTrollColor.h"
#import "OTTrollColorViewController.h"

#import <sys/stat.h>
#import <math.h>

@interface OTSettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *urlSchemeSwitch;

@end

@implementation OTSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.urlSchemeSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [self.urlSchemeSwitch addTarget:self action:@selector(urlSchemeChanged:) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:OTURLSchemeEnabledKey];
    [self.urlSchemeSwitch setOn:enabled animated:NO];
    [self.tableView reloadData];
}

- (void)urlSchemeChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:OTURLSchemeEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 4: return 2;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Actions";
        case 1: return @"Appearance";
        case 2: return @"Security";
        case 3: return @"Support";
        default: return @"About";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 2) {
        return nil;
    }
    return @"When enabled, OldTroll accepts external URL calls and installs the IPA automatically:\n\n"
            "apple-magnifier://install?url=<IPA URL>\n\n"
            "Percent-encoded links are supported. Leave this on if you use OldTroll from Safari or other apps.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 4) {
        return indexPath.row == 0 ? 64.0 : 46.0;
    }
    return 46.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"SettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
        cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    }

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    // Gray exists on iOS 6 where UITableViewCellSelectionStyleDefault does not.
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.textColor = [UIColor blackColor];

    if (indexPath.section == 0) {
        cell.textLabel.text = indexPath.row == 0 ? @"Respring" : @"Clear Cache";
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"Troll Color";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"R%d G%d B%d",
                                     (int)lround([OTTrollColor redComponent] * 255.0),
                                     (int)lround([OTTrollColor greenComponent] * 255.0),
                                     (int)lround([OTTrollColor blueComponent] * 255.0)];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"URL Scheme Enabled";
        cell.accessoryView = self.urlSchemeSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 3) {
        cell.textLabel.text = @"Donate";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.row == 0) {
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.textColor = [UIColor colorWithWhite:0.32 alpha:1.0];
        cell.textLabel.font = [UIFont systemFontOfSize:14.0];
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        cell.textLabel.text = [NSString stringWithFormat:
            @"OldTroll v%@\nAuthor: Cor",
            OTNonEmptyString(version, OT_VERSION_STRING)];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.numberOfLines = 1;
        cell.textLabel.textColor = [UIColor colorWithWhite:0.20 alpha:1.0];
        cell.textLabel.font = [UIFont systemFontOfSize:14.0];
        cell.textLabel.text = @"https://github.com/laolllllllll/OldTroll/";
        cell.imageView.image = [UIImage imageNamed:@"github.png"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0 && indexPath.row == 0) {
        [self confirmRespring];
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        [self clearCache];
    } else if (indexPath.section == 1) {
        OTTrollColorViewController *color = [[OTTrollColorViewController alloc] init];
        [self.navigationController pushViewController:color animated:YES];
    } else if (indexPath.section == 3) {
        OTDonateViewController *donate = [[OTDonateViewController alloc] init];
        [self.navigationController pushViewController:donate animated:YES];
    } else if (indexPath.section == 4 && indexPath.row == 1) {
        [self openGitHubPage];
    }
}

#pragma mark - Actions

- (void)confirmRespring {
    [OTAlert showWithTitle:@"Respring"
                   message:@"Restart SpringBoard now?"
              cancelButton:@"Cancel"
                   buttons:@[@"Respring"]
                   handler:^(NSInteger buttonIndex, NSString *text) {
        if (buttonIndex != 1) {
            return;
        }
        struct stat info;
        if (stat("/usr/bin/oldtroll_helper", &info) != 0 || (info.st_mode & S_ISUID) == 0) {
            [OTAlert showWithTitle:@"Failed"
                           message:@"The privileged helper is missing. Reinstall OldTroll."
                      cancelButton:@"OK"
                           buttons:nil
                           handler:nil];
            return;
        }
        [OTProcessRunner run:@"/usr/bin/oldtroll_helper" arguments:@[@"respring"]];
    }];
}

- (void)clearCache {
    [OTAppManager clearCache];
    [OTIPAPackage clearAllCache];
    [OTAlert showWithTitle:@"Cache Cleared"
                   message:@"All temporary files have been removed."
              cancelButton:@"OK"
                   buttons:nil
                   handler:nil];
}

- (void)openGitHubPage {
    NSURL *url = [NSURL URLWithString:@"https://github.com/laolllllllll/OldTroll/"];
    if (url == nil || ![[UIApplication sharedApplication] openURL:url]) {
        [OTAlert showWithTitle:@"Notice"
                       message:@"Cannot open the browser."
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
    }
}

@end
