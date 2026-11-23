//
//  OTDonateViewController.m
//  OldTroll
//

#import "OTDonateViewController.h"
#import "OTCompat.h"

#import <QuartzCore/QuartzCore.h>

@interface OTDonateViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *introLabel;
@property (nonatomic, strong) UIView *qrCard;
@property (nonatomic, strong) UIImageView *qrView;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIView *thankView;

@end

@implementation OTDonateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Donate";
    self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.scrollView];

    self.introLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.introLabel.backgroundColor = [UIColor clearColor];
    self.introLabel.font = [UIFont systemFontOfSize:15.0];
    self.introLabel.textColor = [UIColor colorWithWhite:0.28 alpha:1.0];
    self.introLabel.textAlignment = NSTextAlignmentCenter;
    self.introLabel.numberOfLines = 0;
    self.introLabel.text = @"Thanks for donating.";
    [self.scrollView addSubview:self.introLabel];

    self.qrCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.qrCard.backgroundColor = [UIColor whiteColor];
    self.qrCard.layer.cornerRadius = 12.0;
    self.qrCard.layer.masksToBounds = YES;
    [self.scrollView addSubview:self.qrCard];

    self.qrView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.qrView.image = [UIImage imageNamed:@"DonateQR.jpg"];
    self.qrView.contentMode = UIViewContentModeScaleAspectFit;
    self.qrView.userInteractionEnabled = YES;
    [self.qrCard addSubview:self.qrView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(qrTapped:)];
    [self.qrCard addGestureRecognizer:tap];

    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hintLabel.backgroundColor = [UIColor clearColor];
    self.hintLabel.font = [UIFont systemFontOfSize:13.0];
    self.hintLabel.textColor = [UIColor colorWithWhite:0.48 alpha:1.0];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.text = @"WeChat Pay QR Code";
    [self.scrollView addSubview:self.hintLabel];

    [self buildThankView];
}

- (void)buildThankView {
    self.thankView = [[UIView alloc] initWithFrame:CGRectZero];
    self.thankView.backgroundColor = [UIColor whiteColor];
    self.thankView.hidden = YES;
    [self.view addSubview:self.thankView];

    UILabel *check = [[UILabel alloc] initWithFrame:CGRectZero];
    check.tag = 2001;
    check.backgroundColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.28 alpha:1.0];
    check.textColor = [UIColor whiteColor];
    check.font = [UIFont boldSystemFontOfSize:42.0];
    check.textAlignment = NSTextAlignmentCenter;
    check.layer.cornerRadius = 34.0;
    check.layer.masksToBounds = YES;
    check.text = @"✓";
    [self.thankView addSubview:check];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.tag = 2002;
    title.backgroundColor = [UIColor clearColor];
    title.font = [UIFont boldSystemFontOfSize:26.0];
    title.textColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = @"Thank you!";
    [self.thankView addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitle.tag = 2003;
    subtitle.backgroundColor = [UIColor clearColor];
    subtitle.font = [UIFont systemFontOfSize:16.0];
    subtitle.textColor = [UIColor colorWithWhite:0.40 alpha:1.0];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 0;
    subtitle.text = @"感谢你的支持！\nYour support keeps OldTroll alive.";
    [self.thankView addSubview:subtitle];

    UIButton *back = [UIButton buttonWithType:UIButtonTypeCustom];
    back.tag = 2004;
    [back setTitle:@"Back" forState:UIControlStateNormal];
    [back setTitleColor:[UIColor colorWithRed:0.0 green:0.45 blue:0.90 alpha:1.0]
                 forState:UIControlStateNormal];
    back.titleLabel.font = [UIFont systemFontOfSize:18.0];
    [back addTarget:self action:@selector(closeThankView:) forControlEvents:UIControlEventTouchUpInside];
    [self.thankView addSubview:back];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    self.scrollView.frame = self.view.bounds;

    CGFloat contentWidth = MIN(width, 620.0);
    CGFloat left = (width - contentWidth) / 2.0;
    self.introLabel.frame = CGRectMake(left + 24.0, 22.0, contentWidth - 48.0, 54.0);

    CGFloat cardWidth = MIN(contentWidth - 64.0, 380.0);
    CGFloat qrHeight = cardWidth * 1.08;
    self.qrCard.frame = CGRectMake((width - cardWidth) / 2.0, 88.0, cardWidth, qrHeight);
    self.qrView.frame = CGRectMake(10.0, 10.0, cardWidth - 20.0, qrHeight - 20.0);
    self.hintLabel.frame = CGRectMake(left, CGRectGetMaxY(self.qrCard.frame) + 14.0,
                                      contentWidth, 22.0);
    self.scrollView.contentSize = CGSizeMake(width, CGRectGetMaxY(self.hintLabel.frame) + 24.0);

    self.thankView.frame = self.view.bounds;
    UIView *check = [self.thankView viewWithTag:2001];
    check.frame = CGRectMake((width - 68.0) / 2.0, height * 0.26, 68.0, 68.0);
    UIView *title = [self.thankView viewWithTag:2002];
    title.frame = CGRectMake(20.0, CGRectGetMaxY(check.frame) + 22.0, width - 40.0, 34.0);
    UIView *subtitle = [self.thankView viewWithTag:2003];
    subtitle.frame = CGRectMake(30.0, CGRectGetMaxY(title.frame) + 10.0, width - 60.0, 60.0);
    UIView *back = [self.thankView viewWithTag:2004];
    back.frame = CGRectMake((width - 160.0) / 2.0, CGRectGetMaxY(subtitle.frame) + 26.0, 160.0, 44.0);
}

- (void)qrTapped:(id)sender {
    self.thankView.hidden = NO;
}

- (void)closeThankView:(id)sender {
    self.thankView.hidden = YES;
}

@end
