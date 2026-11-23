//
//  OTTrollColorViewController.m
//  OldTroll
//

#import "OTTrollColorViewController.h"
#import "OTAlert.h"
#import "OTCompat.h"
#import "OTProcessRunner.h"
#import "OTTrollColor.h"
#import <math.h>

@interface OTTrollColorViewController ()

@property (nonatomic, strong) UIImageView *previewView;
@property (nonatomic, strong) UISlider *redSlider;
@property (nonatomic, strong) UISlider *greenSlider;
@property (nonatomic, strong) UISlider *blueSlider;
@property (nonatomic, strong) UILabel *redValueLabel;
@property (nonatomic, strong) UILabel *greenValueLabel;
@property (nonatomic, strong) UILabel *blueValueLabel;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *resetButton;

@end

@implementation OTTrollColorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Troll Color";
    self.view.backgroundColor = [UIColor whiteColor];

    self.previewView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.previewView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:self.previewView];

    self.redSlider = [self makeSliderWithTag:0];
    self.greenSlider = [self makeSliderWithTag:1];
    self.blueSlider = [self makeSliderWithTag:2];

    self.redValueLabel = [self makeValueLabel];
    self.greenValueLabel = [self makeValueLabel];
    self.blueValueLabel = [self makeValueLabel];

    self.applyButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.applyButton setTitle:@"Apply Color" forState:UIControlStateNormal];
    self.applyButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [self.applyButton addTarget:self action:@selector(applyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.applyButton];

    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [resetButton setTitle:@"Reset Green" forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont systemFontOfSize:15.0];
    [resetButton addTarget:self action:@selector(resetTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:resetButton];
    self.resetButton = resetButton;

    [self loadCurrentColor];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat contentWidth = MIN(OT_IS_IPAD ? 440.0 : 340.0, width - 32.0);
    CGFloat left = (width - contentWidth) / 2.0;
    CGFloat top = 24.0;

    self.previewView.frame = CGRectMake((width - 120.0) / 2.0, top, 120.0, 120.0);
    top += 120.0 + 24.0;

    CGFloat sliderLeft = left + 52.0;
    CGFloat sliderWidth = contentWidth - 52.0 - 54.0;
    for (NSUInteger index = 0; index < 3; index++) {
        UILabel *letter = [self.view viewWithTag:100 + (NSInteger)index];
        UISlider *slider = index == 0 ? self.redSlider : (index == 1 ? self.greenSlider : self.blueSlider);
        UILabel *value = index == 0 ? self.redValueLabel : (index == 1 ? self.greenValueLabel : self.blueValueLabel);
        letter.frame = CGRectMake(left, top + 12.0, 28.0, 26.0);
        slider.frame = CGRectMake(sliderLeft, top + 6.0, sliderWidth, 32.0);
        value.frame = CGRectMake(left + contentWidth - 46.0, top + 12.0, 46.0, 26.0);
        top += 52.0;
    }

    self.applyButton.frame = CGRectMake(left, top + 12.0, contentWidth, 44.0);
    self.resetButton.frame = CGRectMake(left, top + 64.0, contentWidth, 36.0);

    CGFloat bottom = top + 64.0 + 36.0;
    if (bottom > height - 16.0) {
        // A 3.5-inch iPhone in landscape can be tight; keep the controls reachable.
        self.applyButton.frame = CGRectMake(left, MAX(top + 4.0, height - 96.0), contentWidth, 40.0);
        self.resetButton.frame = CGRectMake(left, MAX(top + 48.0, height - 52.0), contentWidth, 32.0);
    }
}

- (UISlider *)makeSliderWithTag:(NSInteger)tag {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
    slider.minimumValue = 0.0;
    slider.maximumValue = 1.0;
    slider.continuous = YES;
    slider.tag = tag;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:slider];

    UILabel *letter = [[UILabel alloc] initWithFrame:CGRectZero];
    letter.backgroundColor = [UIColor clearColor];
    letter.font = [UIFont boldSystemFontOfSize:17.0];
    letter.textAlignment = NSTextAlignmentCenter;
    letter.text = tag == 0 ? @"R" : (tag == 1 ? @"G" : @"B");
    letter.tag = 100 + tag;
    [self.view addSubview:letter];
    return slider;
}

- (UILabel *)makeValueLabel {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:13.0];
    label.textColor = [UIColor colorWithWhite:0.42 alpha:1.0];
    label.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:label];
    return label;
}

- (void)loadCurrentColor {
    self.redSlider.value = [OTTrollColor redComponent];
    self.greenSlider.value = [OTTrollColor greenComponent];
    self.blueSlider.value = [OTTrollColor blueComponent];
    [self updatePreview];
}

- (void)sliderChanged:(UISlider *)sender {
    [self updatePreview];
}

- (void)updatePreview {
    self.redValueLabel.text = [NSString stringWithFormat:@"%d", (int)lround(self.redSlider.value * 255.0)];
    self.greenValueLabel.text = [NSString stringWithFormat:@"%d", (int)lround(self.greenSlider.value * 255.0)];
    self.blueValueLabel.text = [NSString stringWithFormat:@"%d", (int)lround(self.blueSlider.value * 255.0)];

    UIColor *color = [UIColor colorWithRed:self.redSlider.value
                                     green:self.greenSlider.value
                                      blue:self.blueSlider.value
                                     alpha:1.0];
    self.previewView.image = [OTTrollColor imageWithColor:color size:120.0];
}

- (void)resetTapped:(id)sender {
    [OTTrollColor resetToDefault];
    [self loadCurrentColor];
}

- (void)applyTapped:(id)sender {
    self.applyButton.enabled = NO;

    CGFloat red = self.redSlider.value;
    CGFloat green = self.greenSlider.value;
    CGFloat blue = self.blueSlider.value;
    [OTTrollColor saveRed:red green:green blue:blue];

    NSString *workDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"oldtroll_icons"];
    [[NSFileManager defaultManager] removeItemAtPath:workDirectory error:NULL];
    NSError *error = nil;
    if (![OTTrollColor writeIconSetToDirectory:workDirectory error:&error]) {
        self.applyButton.enabled = YES;
        [OTAlert showWithTitle:@"Color Failed"
                        message:error.localizedDescription ?: @"Could not render the icons."
                   cancelButton:@"OK"
                        buttons:nil
                        handler:nil];
        return;
    }

    OTProcessResult *result = [OTProcessRunner run:@"/usr/bin/oldtroll_helper"
                                         arguments:@[@"set-icons", workDirectory]];
    if (!result.succeeded) {
        self.applyButton.enabled = YES;
        [OTAlert showWithTitle:@"Color Failed"
                        message:OTNonEmptyString(result.output, @"Could not update the installed icons.")
                   cancelButton:@"OK"
                        buttons:nil
                        handler:nil];
        return;
    }

    [OTProcessRunner run:@"/usr/bin/oldtroll_helper" arguments:@[@"uicache"]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [OTProcessRunner run:@"/usr/bin/oldtroll_helper" arguments:@[@"respring"]];
    });
}

@end
