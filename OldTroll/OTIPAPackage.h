//
//  OTIPAPackage.h
//  OldTroll
//
//  Reads an .ipa for display and installs it through the bundled appinst.
//

#import <UIKit/UIKit.h>

typedef void (^OTIPAPackageProgressBlock)(CGFloat progress, NSString *status);

@interface OTIPAPackage : NSObject

@property (nonatomic, copy) NSString *ipaPath;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *appPath;        // source .app inside the extracted IPA
@property (nonatomic, copy) NSString *iconPath;       // source icon inside the .app
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, copy) NSString *installedPath;   // resolved after AppSync installation

- (instancetype)initWithIPAPath:(NSString *)ipaPath;

- (BOOL)parseIPAWithError:(NSError **)error;
- (BOOL)installIPAWithError:(NSError **)error;

- (void)cleanup;

+ (void)clearAllCache;

@end
