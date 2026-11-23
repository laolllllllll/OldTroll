//
//  OTAppDetailViewController.m
//  OldTroll
//

#import "OTAppDetailViewController.h"
#import "OTAlert.h"
#import "OTAppInfo.h"
#import "OTAppManager.h"
#import "OTCompat.h"
#import "OTProcessRunner.h"

#import <QuartzCore/QuartzCore.h>

static NSArray *OTAppIconNames(void) {
    return @[
        @"Icon.png", @"Icon@2x.png",
        @"Icon-72.png", @"Icon-72@2x.png",
        @"Icon-76.png", @"Icon-76@2x.png",
        @"Icon-60.png", @"Icon-60@2x.png",
        @"Icon-40.png", @"Icon-40@2x.png",
        @"Icon-Small.png", @"Icon-Small@2x.png"
    ];
}

static NSArray *OTAppIconSizes(void) {
    return @[@57, @114, @72, @144, @76, @152, @60, @120, @40, @80, @29, @58];
}

@interface OTAppDetailViewController () <UITableViewDataSource, UITableViewDelegate,
                                        UIImagePickerControllerDelegate, UINavigationControllerDelegate,
                                        UITextFieldDelegate>

@property (nonatomic, strong) OTAppInfo *appInfo;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *versionField;
@property (nonatomic, strong) UITextField *bundleField;
@property (nonatomic, strong) UIImage *selectedIcon;
@property (nonatomic, strong) UIPopoverController *iconPopover;

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

    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 170.0)];
    self.headerView.backgroundColor = [UIColor clearColor];

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.layer.cornerRadius = 14.0;
    self.iconView.layer.masksToBounds = YES;
    self.iconView.image = self.appInfo.icon;
    self.iconView.userInteractionEnabled = YES;
    [self.headerView addSubview:self.iconView];

    UITapGestureRecognizer *iconTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(iconTapped:)];
    [self.iconView addGestureRecognizer:iconTap];

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
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@  •  Tap the icon to change it",
                               self.appInfo.bundleId];
    [self.headerView addSubview:self.subtitleLabel];

    self.tableView.tableHeaderView = self.headerView;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (self.headerView.frame.size.width != width) {
        self.headerView.frame = CGRectMake(0, 0, width, 170.0);
        self.tableView.tableHeaderView = self.headerView;
    }

    CGFloat iconSize = 76.0;
    self.iconView.frame = CGRectMake((width - iconSize) / 2.0, 12.0, iconSize, iconSize);
    self.nameLabel.frame = CGRectMake(20.0, 96.0, width - 40.0, 26.0);
    self.subtitleLabel.frame = CGRectMake(20.0, 124.0, width - 40.0, 20.0);
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 3;
    }
    if (section == 1) {
        return 3;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Actions";
        case 1: return @"Information";
        default: return @"Path";
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        return 56.0;
    }
    return 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *actionIdentifier = @"ActionCell";
    static NSString *fieldIdentifier = @"FieldCell";
    static NSString *pathIdentifier = @"PathCell";

    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actionIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:actionIdentifier];
            cell.textLabel.font = [UIFont systemFontOfSize:16.0];
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Apply Changes";
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.42 blue:0.86 alpha:1.0];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Open";
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.35 blue:0.85 alpha:1.0];
            cell.textLabel.textAlignment = NSTextAlignmentLeft;
        } else {
            cell.textLabel.text = @"Uninstall";
            cell.textLabel.textColor = [UIColor redColor];
            cell.textLabel.textAlignment = NSTextAlignmentLeft;
        }
        return cell;
    }

    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:fieldIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:fieldIdentifier];
            cell.textLabel.font = [UIFont systemFontOfSize:16.0];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(120.0, 6.0,
                                                                              cell.contentView.bounds.size.width - 132.0, 32.0)];
            field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            field.font = [UIFont systemFontOfSize:15.0];
            field.textColor = [UIColor colorWithWhite:0.32 alpha:1.0];
            field.textAlignment = NSTextAlignmentRight;
            field.borderStyle = UITextBorderStyleNone;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            field.returnKeyType = UIReturnKeyDone;
            field.delegate = self;
            field.tag = 4100;
            [cell.contentView addSubview:field];
        }
        UITextField *field = (UITextField *)[cell.contentView viewWithTag:4100];
        NSArray *titles = @[@"Name", @"Version", @"Bundle ID"];
        NSArray *values = @[OTNonEmptyString(self.appInfo.name, @"Unknown"),
                            OTNonEmptyString(self.appInfo.version, @"Unknown"),
                            OTNonEmptyString(self.appInfo.bundleId, @"Unknown")];
        cell.textLabel.text = titles[(NSUInteger)indexPath.row];
        field.text = values[(NSUInteger)indexPath.row];
        field.keyboardType = indexPath.row == 2 ? UIKeyboardTypeURL : UIKeyboardTypeDefault;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        if (indexPath.row == 0) {
            self.nameField = field;
        } else if (indexPath.row == 1) {
            self.versionField = field;
        } else {
            self.bundleField = field;
        }
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:pathIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:pathIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.textLabel.text = @"Path";
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = OTNonEmptyString(self.appInfo.appPath, @"Unknown");
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        UITextField *field = indexPath.row == 0 ? self.nameField :
                             indexPath.row == 1 ? self.versionField : self.bundleField;
        [field becomeFirstResponder];
        return;
    }
    if (indexPath.section != 0) {
        return;
    }
    if (indexPath.row == 0) {
        [self applyChanges];
    } else if (indexPath.row == 1) {
        [self openApp];
    } else {
        [self confirmUninstall];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Icon picker

- (void)iconTapped:(id)sender {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [OTAlert showWithTitle:@"Photos Unavailable"
                       message:@"This device does not provide a photo library."
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.allowsEditing = YES;

    if (OT_IS_IPAD) {
        self.iconPopover = [[UIPopoverController alloc] initWithContentViewController:picker];
        CGRect rect = [self.iconView convertRect:self.iconView.bounds toView:self.view];
        [self.iconPopover presentPopoverFromRect:rect
                                          inView:self.view
                        permittedArrowDirections:UIPopoverArrowDirectionAny
                                        animated:YES];
    } else {
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    if ([self.iconPopover isPopoverVisible]) {
        [self.iconPopover dismissPopoverAnimated:YES];
    } else {
        [picker dismissViewControllerAnimated:YES completion:nil];
    }
    self.iconPopover = nil;
    if (image == nil) {
        return;
    }
    self.selectedIcon = image;
    self.iconView.image = image;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    if ([self.iconPopover isPopoverVisible]) {
        [self.iconPopover dismissPopoverAnimated:YES];
    } else {
        [picker dismissViewControllerAnimated:YES completion:nil];
    }
    self.iconPopover = nil;
}

#pragma mark - Apply

- (void)applyChanges {
    [self.view endEditing:YES];

    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *version = [self.versionField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *bundleId = [self.bundleField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0 || version.length == 0 || bundleId.length == 0) {
        [OTAlert showWithTitle:@"Missing Information"
                       message:@"Name, version and bundle identifier cannot be empty."
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        return;
    }
    if ([bundleId rangeOfString:@" "].location != NSNotFound) {
        [OTAlert showWithTitle:@"Invalid Bundle ID"
                       message:@"The bundle identifier cannot contain spaces."
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        return;
    }

    NSString *infoPath = [self.appInfo.appPath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (info == nil) {
        [OTAlert showWithTitle:@"Cannot Read Info.plist"
                       message:@"The app bundle could not be read."
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        return;
    }

    NSString *metaDirectory = @"/private/var/tmp/oldtroll_appmeta";
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:metaDirectory error:NULL];
    if (![fileManager createDirectoryAtPath:metaDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:NULL]) {
        [OTAlert showWithTitle:@"Apply Failed"
                       message:@"Could not create a temporary directory."
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        return;
    }

    info[@"CFBundleDisplayName"] = name;
    info[@"CFBundleName"] = name;
    info[@"CFBundleShortVersionString"] = version;
    info[@"CFBundleVersion"] = version;
    info[@"CFBundleIdentifier"] = bundleId;

    if (self.selectedIcon != nil) {
        NSArray *names = OTAppIconNames();
        NSArray *sizes = OTAppIconSizes();
        for (NSUInteger index = 0; index < names.count; index++) {
            CGFloat size = [sizes[index] doubleValue];
            UIImage *icon = [self squareIconFromImage:self.selectedIcon size:size];
            NSData *png = icon == nil ? nil : UIImagePNGRepresentation(icon);
            if (png == nil) {
                continue;
            }
            [png writeToFile:[metaDirectory stringByAppendingPathComponent:names[index]] atomically:YES];
        }
        info[@"CFBundleIconFiles"] = names;
        info[@"CFBundleIcons"] = @{@"CFBundlePrimaryIcon": @{@"CFBundleIconFiles": names}};
    }

    NSString *newInfoPath = [metaDirectory stringByAppendingPathComponent:@"Info.plist"];
    if (![info writeToFile:newInfoPath atomically:YES]) {
        [OTAlert showWithTitle:@"Apply Failed"
                       message:@"Could not write the new Info.plist."
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        return;
    }

    NSString *oldBundleId = self.appInfo.bundleId;
    NSString *iconArgument = self.selectedIcon != nil ? metaDirectory : @"-";
    OTProcessResult *result = [OTProcessRunner run:@"/usr/bin/oldtroll_helper"
                                         arguments:@[@"set-app-info", self.appInfo.appPath, newInfoPath, iconArgument]];
    if (!result.succeeded) {
        [OTAlert showWithTitle:@"Apply Failed"
                       message:OTNonEmptyString(result.output, @"The privileged helper could not update the app.")
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        return;
    }

    self.appInfo.name = name;
    self.appInfo.version = version;
    self.appInfo.bundleId = bundleId;
    if (self.selectedIcon != nil) {
        self.appInfo.icon = self.selectedIcon;
    }
    self.title = name;
    self.nameLabel.text = name;
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@  •  Tap the icon to change it", bundleId];

    [[OTAppManager sharedManager] updateInstalledAppFromBundleId:oldBundleId
                                                      toBundleId:bundleId
                                                            path:self.appInfo.appPath];
    [[OTAppManager sharedManager] refreshIconCache];
    [self.tableView reloadData];

    [OTAlert showWithTitle:@"Changes Applied"
                   message:@"SpringBoard will restart to refresh the app icon."
              cancelButton:@"Later"
                   buttons:@[@"Respring"]
                   handler:^(NSInteger buttonIndex, NSString *text) {
        if (buttonIndex == 1) {
            [OTProcessRunner run:@"/usr/bin/oldtroll_helper" arguments:@[@"respring"]];
        }
    }];
}

- (UIImage *)squareIconFromImage:(UIImage *)image size:(CGFloat)size {
    if (image == nil || size < 1.0) {
        return nil;
    }
    CGFloat sourceWidth = image.size.width;
    CGFloat sourceHeight = image.size.height;
    if (sourceWidth <= 0.0 || sourceHeight <= 0.0) {
        return nil;
    }

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 1.0);
    CGFloat scale = size / MIN(sourceWidth, sourceHeight);
    CGRect drawRect = CGRectMake((size - sourceWidth * scale) / 2.0,
                                 (size - sourceHeight * scale) / 2.0,
                                 sourceWidth * scale,
                                 sourceHeight * scale);
    [image drawInRect:drawRect];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
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
