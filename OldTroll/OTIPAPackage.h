//
//  OTIPAPackage.h
//  OldTroll
//
//  Converts an .ipa into a Cydia-compatible .deb entirely on-device:
//  extract -> ldid pseudo-sign -> build DEBIAN package -> dpkg install.
//

#import <UIKit/UIKit.h>

typedef void (^OTIPAPackageProgressBlock)(CGFloat progress, NSString *status);

@interface OTIPAPackage : NSObject

@property (nonatomic, copy) NSString *ipaPath;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *packageIdentifier;
@property (nonatomic, copy) NSString *safeName;
@property (nonatomic, copy) NSString *appPath;        // source .app inside the extracted IPA
@property (nonatomic, copy) NSString *iconPath;       // source icon inside the .app
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, copy) NSString *outputDebPath;
@property (nonatomic, copy) NSString *installPath;    // /Applications/<safeName>.app

- (instancetype)initWithIPAPath:(NSString *)ipaPath;

- (BOOL)parseIPAWithError:(NSError **)error;
- (BOOL)buildDebWithProgress:(OTIPAPackageProgressBlock)progress error:(NSError **)error;
- (BOOL)installDebWithError:(NSError **)error;

- (void)cleanup;

+ (void)clearAllCache;

@end
