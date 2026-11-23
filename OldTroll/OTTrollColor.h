//
//  OTTrollColor.h
//  OldTroll
//
//  Shared Troll Face tint setting and icon rendering.
//

#import <UIKit/UIKit.h>

@interface OTTrollColor : NSObject

// Current color from NSUserDefaults. Defaults to the original Troll green.
+ (UIColor *)currentColor;
+ (CGFloat)redComponent;
+ (CGFloat)greenComponent;
+ (CGFloat)blueComponent;

+ (void)saveRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue;
+ (void)resetToDefault;

// Renders a tinted preview from the pristine bundled base image.
+ (UIImage *)previewImage;
+ (UIImage *)imageWithColor:(UIColor *)color size:(CGFloat)size;

// Writes every SpringBoard and Cydia icon into a temporary directory.
+ (BOOL)writeIconSetToDirectory:(NSString *)directory error:(NSError **)error;

@end
