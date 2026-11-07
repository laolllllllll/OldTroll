//
//  OTInstallRequest.h
//  OldTroll
//
//  Parses incoming URL-scheme calls into an install request. Kept separate
//  from the UI so the parsing rules can be unit-tested and so both the cold
//  launch path and the running-app path share identical behaviour.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OTInstallRequestOrigin) {
    OTInstallRequestOriginExternalURL = 0,
    OTInstallRequestOriginUserURL,
    OTInstallRequestOriginFile,
    OTInstallRequestOriginLaunch
};

@interface OTInstallRequest : NSObject

// Remote HTTP(S) .ipa URL, or a local file URL.
@property (nonatomic, strong) NSURL *sourceURL;

@property (nonatomic, assign) OTInstallRequestOrigin origin;

// YES means download and install without asking for a second confirmation.
// External URL-scheme calls are automatic; manual picks are not.
@property (nonatomic, assign, getter=isAutomatic) BOOL automatic;

@property (nonatomic, strong) NSDate *createdAt;

@property (nonatomic, readonly, getter=isRemote) BOOL remote;
@property (nonatomic, readonly, getter=isLocalFile) BOOL localFile;
@property (nonatomic, readonly) NSString *displayString;

// Handles cor-oldtroll://install?url=..., cor-oldtroll://?url=...,
// apple-magnifier://install?url=... and percent-encoded variants.
+ (instancetype)requestWithIncomingURL:(NSURL *)url error:(NSString **)error;

// Used by the "Install from URL" text field. Accepts a plain http(s) URL or
// any of the URL-scheme forms above.
+ (instancetype)requestWithURLString:(NSString *)string error:(NSString **)error;

+ (instancetype)requestWithFilePath:(NSString *)path error:(NSString **)error;

@end
