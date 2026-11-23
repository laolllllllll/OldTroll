//
//  OTTrollColor.m
//  OldTroll
//

#import "OTTrollColor.h"
#import <math.h>

static NSString * const OTTrollColorRedKey = @"trollColorRed";
static NSString * const OTTrollColorGreenKey = @"trollColorGreen";
static NSString * const OTTrollColorBlueKey = @"trollColorBlue";

static const CGFloat OTTrollDefaultRed = 97.0 / 255.0;
static const CGFloat OTTrollDefaultGreen = 228.0 / 255.0;
static const CGFloat OTTrollDefaultBlue = 10.0 / 255.0;

static NSArray *OTIconNames(void) {
    return @[
        @"Icon.png", @"Icon@2x.png",
        @"Icon-72.png", @"Icon-72@2x.png",
        @"Icon-76.png", @"Icon-76@2x.png",
        @"Icon-60.png", @"Icon-60@2x.png",
        @"Icon-40.png", @"Icon-40@2x.png",
        @"Icon-Small.png", @"Icon-Small@2x.png",
        @"CydiaIcon.png"
    ];
}

static NSArray *OTIconSizes(void) {
    return @[@57, @114, @72, @144, @76, @152, @60, @120, @40, @80, @29, @58, @152];
}

static NSArray *OTSplashNames(void) {
    return @[
        @"Default.png",
        @"Default@2x.png",
        @"Default-568h@2x.png",
        @"Default-Portrait.png",
        @"Default-Portrait@2x.png",
        @"Default-Landscape.png",
        @"Default-Landscape@2x.png"
    ];
}

@implementation OTTrollColor

+ (CGFloat)componentForKey:(NSString *)key fallback:(CGFloat)fallback {
    NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (number == nil) {
        return fallback;
    }
    return MAX(0.0, MIN(1.0, number.doubleValue));
}

+ (UIColor *)currentColor {
    return [UIColor colorWithRed:[self redComponent]
                           green:[self greenComponent]
                            blue:[self blueComponent]
                           alpha:1.0];
}

+ (CGFloat)redComponent {
    return [self componentForKey:OTTrollColorRedKey fallback:OTTrollDefaultRed];
}

+ (CGFloat)greenComponent {
    return [self componentForKey:OTTrollColorGreenKey fallback:OTTrollDefaultGreen];
}

+ (CGFloat)blueComponent {
    return [self componentForKey:OTTrollColorBlueKey fallback:OTTrollDefaultBlue];
}

+ (void)saveRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:MAX(0.0, MIN(1.0, red)) forKey:OTTrollColorRedKey];
    [defaults setDouble:MAX(0.0, MIN(1.0, green)) forKey:OTTrollColorGreenKey];
    [defaults setDouble:MAX(0.0, MIN(1.0, blue)) forKey:OTTrollColorBlueKey];
    [defaults synchronize];
}

+ (void)resetToDefault {
    [self saveRed:OTTrollDefaultRed green:OTTrollDefaultGreen blue:OTTrollDefaultBlue];
}

+ (UIImage *)baseImage {
    UIImage *image = [UIImage imageNamed:@"TrollBase.png"];
    if (image == nil) {
        image = [UIImage imageNamed:@"Icon-76@2x.png"];
    }
    return image;
}

#pragma mark - Tinting

+ (UIImage *)applyTintToImage:(UIImage *)source color:(UIColor *)color {
    if (source == nil) {
        return nil;
    }

    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        red = OTTrollDefaultRed;
        green = OTTrollDefaultGreen;
        blue = OTTrollDefaultBlue;
    }

    CGImageRef sourceImage = source.CGImage;
    size_t width = CGImageGetWidth(sourceImage);
    size_t height = CGImageGetHeight(sourceImage);
    if (width == 0 || height == 0) {
        return source;
    }

    uint8_t *pixels = calloc(width * height, 4);
    if (pixels == NULL) {
        return source;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4,
                                                 colorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        free(pixels);
        return source;
    }

    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), sourceImage);
    CGContextRelease(context);

    CGFloat targetRed = red * 255.0;
    CGFloat targetGreen = green * 255.0;
    CGFloat targetBlue = blue * 255.0;
    size_t count = width * height;
    for (size_t index = 0; index < count; index++) {
        uint8_t *pixel = pixels + index * 4;
        uint8_t r = pixel[0];
        uint8_t g = pixel[1];
        uint8_t b = pixel[2];
        uint8_t a = pixel[3];
        if (a == 0) {
            continue;
        }

        // The Troll art uses a saturated green field. Recolour only pixels
        // where green clearly dominates, keeping the white face, black line
        // art and the white launch-screen background untouched.
        CGFloat bias = ((CGFloat)g - MAX((CGFloat)r, (CGFloat)b)) / 48.0;
        if (bias <= 0.0) {
            continue;
        }
        CGFloat factor = MIN(1.0, bias);
        pixel[0] = (uint8_t)lround(r + (targetRed - r) * factor);
        pixel[1] = (uint8_t)lround(g + (targetGreen - g) * factor);
        pixel[2] = (uint8_t)lround(b + (targetBlue - b) * factor);
    }

    CGColorSpaceRef outputSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef output = CGBitmapContextCreate(pixels, width, height, 8, width * 4,
                                                outputSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(outputSpace);
    UIImage *result = source;
    if (output != NULL) {
        CGImageRef tinted = CGBitmapContextCreateImage(output);
        CGContextRelease(output);
        if (tinted != NULL) {
            result = [UIImage imageWithCGImage:tinted];
            CGImageRelease(tinted);
        }
    }
    free(pixels);
    return result;
}

+ (UIImage *)glossedImage:(UIImage *)source {
    if (source == nil) {
        return nil;
    }
    CGSize size = source.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return source;
    }

    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    [source drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];

    CGContextRef context = UIGraphicsGetCurrentContext();
    UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, size.width, size.height)
                                                      cornerRadius:size.width * 0.225];
    [clip addClip];

    CGFloat locations[2] = {0.0, 1.0};
    CGFloat components[8] = {1.0, 1.0, 1.0, 0.74, 1.0, 1.0, 1.0, 0.0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, components, locations, 2);
    CGContextDrawLinearGradient(context, gradient,
                                CGPointMake(0.0, 0.0),
                                CGPointMake(0.0, size.height * 0.55), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: source;
}

+ (UIImage *)tintedImageWithColor:(UIColor *)color size:(CGFloat)size {
    UIImage *base = [self baseImage];
    if (base == nil || size < 1.0) {
        return nil;
    }

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 1.0);
    [base drawInRect:CGRectMake(0.0, 0.0, size, size)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (scaled == nil) {
        return nil;
    }
    UIImage *tinted = [self applyTintToImage:scaled color:color];
    return [self glossedImage:tinted];
}

+ (UIImage *)tintedSplashNamed:(NSString *)name color:(UIColor *)color {
    NSString *resource = [name stringByDeletingPathExtension];
    NSString *path = [[NSBundle mainBundle] pathForResource:resource ofType:@"png"];
    UIImage *image = path == nil ? nil : [UIImage imageWithContentsOfFile:path];
    if (image == nil) {
        return nil;
    }
    return [self applyTintToImage:image color:color];
}

+ (UIImage *)previewImage {
    return [self imageWithColor:[self currentColor] size:152.0];
}

+ (UIImage *)imageWithColor:(UIColor *)color size:(CGFloat)size {
    return [self tintedImageWithColor:color size:size];
}

#pragma mark - Icon set

+ (BOOL)writeIconSetToDirectory:(NSString *)directory error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *directoryError = nil;
    if (![fileManager createDirectoryAtPath:directory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&directoryError]) {
        if (error != NULL) {
            *error = directoryError;
        }
        return NO;
    }

    UIColor *color = [self currentColor];
    NSArray *names = OTIconNames();
    NSArray *sizes = OTIconSizes();
    for (NSUInteger index = 0; index < names.count; index++) {
        CGFloat size = [sizes[index] doubleValue];
        UIImage *image = [self tintedImageWithColor:color size:size];
        NSData *png = image == nil ? nil : UIImagePNGRepresentation(image);
        if (png == nil) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:@"OTTrollColor"
                                              code:1
                                          userInfo:@{NSLocalizedDescriptionKey: @"Could not render the Troll icon."}];
            }
            return NO;
        }
        NSString *path = [directory stringByAppendingPathComponent:names[index]];
        if (![png writeToFile:path atomically:YES]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:@"OTTrollColor"
                                              code:2
                                          userInfo:@{NSLocalizedDescriptionKey: @"Could not write the Troll icon."}];
            }
            return NO;
        }
    }

    // Recolour the static launch images as well. Without this the first
    // second of every launch still shows the original green Troll.
    for (NSString *name in OTSplashNames()) {
        UIImage *image = [self tintedSplashNamed:name color:color];
        NSData *png = image == nil ? nil : UIImagePNGRepresentation(image);
        if (png == nil) {
            continue;
        }
        NSString *path = [directory stringByAppendingPathComponent:name];
        [png writeToFile:path atomically:YES];
    }
    return YES;
}

@end
