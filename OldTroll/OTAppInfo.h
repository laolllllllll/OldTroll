//
//  OTAppInfo.h
//  OldTroll
//

#import <UIKit/UIKit.h>

@interface OTAppInfo : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *appPath;
@property (nonatomic, strong) UIImage *icon;

+ (instancetype)infoWithAppPath:(NSString *)appPath;

// Returns the largest usable icon inside an .app bundle, or nil.
+ (NSString *)iconPathForAppPath:(NSString *)appPath info:(NSDictionary *)info;
+ (UIImage *)iconForAppPath:(NSString *)appPath info:(NSDictionary *)info;

// Gray tile with the app's initial, used when an IPA ships no icon.
+ (UIImage *)placeholderIconWithName:(NSString *)name size:(CGFloat)size;

@end
