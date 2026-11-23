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

+ (UIImage *)tintedImageWithColor:(UIColor *)color size:(CGFloat)size {
    UIImage *base = [self baseImage];
    if (base == nil || size < 1.0) {
        return nil;
    }

    CGSize targetSize = CGSizeMake(size, size);
    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
    [base drawInRect:CGRectMake(0.0, 0.0, size, size)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (scaled == nil) {
        return nil;
    }

    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        red = OTTrollDefaultRed;
        green = OTTrollDefaultGreen;
        blue = OTTrollDefaultBlue;
    }

    CGImageRef source = scaled.CGImage;
    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0) {
        return scaled;
    }

    uint8_t *pixels = calloc(width * height, 4);
    if (pixels == NULL) {
        return scaled;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4,
                                                 colorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        free(pixels);
        return scaled;
    }

    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), source);
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

        // The Troll base art uses a saturated green field. Recolour only
        // pixels where green clearly dominates, keeping the white face and
        // black line art untouched. The blend keeps anti-aliased edges clean.
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
    UIImage *result = scaled;
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

+ (UIImage *)previewImage {
    return [self imageWithColor:[self currentColor] size:152.0];
}

+ (UIImage *)imageWithColor:(UIColor *)color size:(CGFloat)size {
    return [self tintedImageWithColor:color size:size];
}

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

    NSArray *names = @[
        @"Icon.png", @"Icon@2x.png",
        @"Icon-72.png", @"Icon-72@2x.png",
        @"Icon-76.png", @"Icon-76@2x.png",
        @"Icon-60.png", @"Icon-60@2x.png",
        @"Icon-40.png", @"Icon-40@2x.png",
        @"Icon-Small.png", @"Icon-Small@2x.png",
        @"CydiaIcon.png"
    ];
    NSArray *sizes = @[
        @57, @114,
        @72, @144,
        @76, @152,
        @60, @120,
        @40, @80,
        @29, @58,
        @152
    ];

    UIColor *color = [self currentColor];
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
    return YES;
}

@end
