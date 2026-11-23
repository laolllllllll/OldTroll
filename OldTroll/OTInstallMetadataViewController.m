//
//  OTInstallMetadataViewController.m
//  OldTroll
//

#import "OTInstallMetadataViewController.h"
#import "OTCompat.h"

#import <QuartzCore/QuartzCore.h>

@interface OTInstallMetadataViewController ()

@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *size;
@property (nonatomic, strong) UIImage *icon;

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *metadataTitleLabel;
@property (nonatomic, strong) UILabel *fieldsLabel;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *installButton;

@end

@implementation OTInstallMetadataViewController

- (instancetype)initWithName:(NSString *)name
                    bundleId:(NSString *)bundleId
                     version:(NSString *)version
                        size:(NSString *)size
                        icon:(UIImage *)icon {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _appName = [name copy];
        _bundleId = [bundleId copy];
        _version = [version copy];
        _size = [size copy];
        _icon = icon;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];

    self.cardView = [[UIView alloc] initWithFrame:CGRectZero];
    self.cardView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.98];
    self.cardView.layer.cornerRadius = 14.0;
    self.cardView.layer.masksToBounds = YES;
    [self.view addSubview:self.cardView];

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.image = self.icon;
    [self.cardView addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.backgroundColor = [UIColor clearColor];
    self.nameLabel.font = [UIFont systemFontOfSize:20.0];
    self.nameLabel.textColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.text = OTNonEmptyString(self.appName, @"Unknown App");
    [self.cardView addSubview:self.nameLabel];

    self.metadataTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.metadataTitleLabel.backgroundColor = [UIColor clearColor];
    self.metadataTitleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    self.metadataTitleLabel.textColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    self.metadataTitleLabel.text = @"Metadata";
    [self.cardView addSubview:self.metadataTitleLabel];

    self.fieldsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.fieldsLabel.backgroundColor = [UIColor clearColor];
    self.fieldsLabel.font = [UIFont systemFontOfSize:15.0];
    self.fieldsLabel.textColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    self.fieldsLabel.numberOfLines = 0;
    self.fieldsLabel.text = [NSString stringWithFormat:
        @"Bundle Identifier: %@\nVersion: %@\nSize: %@",
        OTNonEmptyString(self.bundleId, @"unknown"),
        OTNonEmptyString(self.version, @"Unknown"),
        OTNonEmptyString(self.size, @"Unknown")];
    [self.cardView addSubview:self.fieldsLabel];

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.cancelButton setTitleColor:[UIColor colorWithRed:0.0 green:0.45 blue:0.90 alpha:1.0]
                             forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:18.0];
    [self.cancelButton addTarget:self action:@selector(cancelTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.cancelButton];

    self.installButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.installButton setTitle:@"Install" forState:UIControlStateNormal];
    [self.installButton setTitleColor:[UIColor colorWithRed:0.0 green:0.45 blue:0.90 alpha:1.0]
                              forState:UIControlStateNormal];
    self.installButton.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    [self.installButton addTarget:self action:@selector(installTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.installButton];

    [self.view setNeedsLayout];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat cardWidth = MIN(OT_IS_IPAD ? 440.0 : 330.0, width - 32.0);
    CGFloat cardHeight = 360.0;
    self.cardView.frame = CGRectMake((width - cardWidth) / 2.0,
                                     (height - cardHeight) / 2.0,
                                     cardWidth,
                                     cardHeight);

    CGFloat innerLeft = 24.0;
    CGFloat innerWidth = cardWidth - innerLeft * 2.0;
    self.iconView.frame = CGRectMake((cardWidth - 64.0) / 2.0, 18.0, 64.0, 64.0);
    self.nameLabel.frame = CGRectMake(innerLeft, 88.0, innerWidth, 28.0);
    self.metadataTitleLabel.frame = CGRectMake(innerLeft, 132.0, innerWidth, 24.0);
    self.fieldsLabel.frame = CGRectMake(innerLeft, 160.0, innerWidth, 124.0);

    CGFloat footerY = cardHeight - 52.0;
    UIView *divider = [self.cardView viewWithTag:9001];
    if (divider == nil) {
        divider = [[UIView alloc] initWithFrame:CGRectZero];
        divider.tag = 9001;
        divider.backgroundColor = [UIColor colorWithWhite:0.82 alpha:1.0];
        [self.cardView addSubview:divider];
    }
    divider.frame = CGRectMake(0.0, footerY, cardWidth, 0.5);
    self.cancelButton.frame = CGRectMake(0.0, footerY, cardWidth / 2.0, 52.0);
    self.installButton.frame = CGRectMake(cardWidth / 2.0, footerY, cardWidth / 2.0, 52.0);

    UIView *vertical = [self.cardView viewWithTag:9002];
    if (vertical == nil) {
        vertical = [[UIView alloc] initWithFrame:CGRectZero];
        vertical.tag = 9002;
        vertical.backgroundColor = [UIColor colorWithWhite:0.82 alpha:1.0];
        [self.cardView addSubview:vertical];
    }
    vertical.frame = CGRectMake(cardWidth / 2.0, footerY, 0.5, 52.0);
}

- (void)cancelTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:^{
        if (self.cancelBlock != nil) {
            self.cancelBlock();
        }
    }];
}

- (void)installTapped:(id)sender {
    self.installButton.enabled = NO;
    [self dismissViewControllerAnimated:YES completion:^{
        if (self.installBlock != nil) {
            self.installBlock();
        }
    }];
}

@end
