//
//  OTAppInfo.m
//  OldTroll
//

#import "OTAppInfo.h"
#import "OTCompat.h"

@implementation OTAppInfo

+ (instancetype)infoWithAppPath:(NSString *)appPath {
    if (OTStringIsEmpty(appPath)) {
        return nil;
    }
    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (![info isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    OTAppInfo *app = [[OTAppInfo alloc] init];
    app.appPath = appPath;
    app.name = OTNonEmptyString(info[@"CFBundleDisplayName"],
                                OTNonEmptyString(info[@"CFBundleName"],
                                                 [[appPath lastPathComponent] stringByDeletingPathExtension]));
    app.bundleId = OTNonEmptyString(info[@"CFBundleIdentifier"], @"unknown");
    app.version = OTNonEmptyString(info[@"CFBundleShortVersionString"],
                                   OTNonEmptyString(info[@"CFBundleVersion"], @"Unknown"));
    app.icon = [self iconForAppPath:appPath info:info];
    return app;
}

+ (NSArray *)iconNamesFromInfo:(NSDictionary *)info {
    NSMutableArray *names = [NSMutableArray array];
    if (![info isKindOfClass:[NSDictionary class]]) {
        return names;
    }

    NSArray *keys = @[@"CFBundleIcons~ipad", @"CFBundleIcons"];
    for (NSString *key in keys) {
        NSDictionary *icons = info[key];
        if (![icons isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *primary = icons[@"CFBundlePrimaryIcon"];
        if (![primary isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSArray *files = primary[@"CFBundleIconFiles"];
        if ([files isKindOfClass:[NSArray class]]) {
            [names addObjectsFromArray:files];
        }
    }

    id legacyFiles = info[@"CFBundleIconFiles"];
    if ([legacyFiles isKindOfClass:[NSArray class]]) {
        [names addObjectsFromArray:legacyFiles];
    } else if ([legacyFiles isKindOfClass:[NSString class]]) {
        [names addObject:legacyFiles];
    }

    id legacyFile = info[@"CFBundleIconFile"];
    if ([legacyFile isKindOfClass:[NSString class]]) {
        [names addObject:legacyFile];
    }
    return names;
}

+ (NSString *)iconPathForAppPath:(NSString *)appPath info:(NSDictionary *)info {
    if (OTStringIsEmpty(appPath)) {
        return nil;
    }

    NSMutableArray *candidatePaths = [NSMutableArray array];
    for (id rawName in [self iconNamesFromInfo:info]) {
        if (![rawName isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *name = rawName;
        if (name.length == 0) {
            continue;
        }
        NSMutableArray *variants = [NSMutableArray arrayWithObject:name];
        if ([[name pathExtension] length] == 0) {
            [variants addObject:[name stringByAppendingString:@".png"]];
            [variants addObject:[name stringByAppendingString:@"@2x.png"]];
            [variants addObject:[name stringByAppendingString:@"~ipad.png"]];
            [variants addObject:[name stringByAppendingString:@"~ipad@2x.png"]];
        } else {
            [variants addObject:[[name stringByDeletingPathExtension] stringByAppendingString:@"@2x.png"]];
        }
        for (NSString *variant in variants) {
            NSString *path = [appPath stringByAppendingPathComponent:variant];
            NSString *standardPath = [path stringByStandardizingPath];
            NSString *standardAppPath = [appPath stringByStandardizingPath];
            if (![standardPath hasPrefix:[standardAppPath stringByAppendingString:@"/"]]) {
                continue;
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [candidatePaths addObject:path];
            }
        }
    }

    // Legacy bundles often ship icons without declaring them in Info.plist.
    if (candidatePaths.count == 0) {
        NSArray *children = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appPath error:NULL];
        for (NSString *child in children) {
            NSString *lower = [child lowercaseString];
            if ([lower hasPrefix:@"icon"] && [lower hasSuffix:@".png"]) {
                [candidatePaths addObject:[appPath stringByAppendingPathComponent:child]];
            }
        }
    }

    NSString *bestPath = nil;
    CGFloat bestArea = 0;
    for (NSString *path in candidatePaths) {
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (image == nil) {
            continue;
        }
        CGFloat area = image.size.width * image.size.height;
        if (area > bestArea) {
            bestArea = area;
            bestPath = path;
        }
    }
    return bestPath;
}

+ (UIImage *)iconForAppPath:(NSString *)appPath info:(NSDictionary *)info {
    NSString *iconPath = [self iconPathForAppPath:appPath info:info];
    if (iconPath != nil) {
        UIImage *icon = [UIImage imageWithContentsOfFile:iconPath];
        if (icon != nil) {
            return icon;
        }
    }
    NSString *name = OTNonEmptyString(info[@"CFBundleDisplayName"],
                                      OTNonEmptyString(info[@"CFBundleName"],
                                                       [[appPath lastPathComponent] stringByDeletingPathExtension]));
    return [self placeholderIconWithName:name size:60.0];
}

+ (UIImage *)placeholderIconWithName:(NSString *)name size:(CGFloat)size {
    CGFloat length = size > 0 ? size : 60.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(length, length), NO, 0);

    CGRect rect = CGRectMake(0, 0, length, length);
    [[UIColor colorWithWhite:0.86 alpha:1.0] setFill];
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:length * 0.22];
    [path fill];

    NSString *letter = @"?";
    if (name.length > 0) {
        letter = [[name substringToIndex:1] uppercaseString];
    }
    CGSize letterSize = [letter sizeWithFont:[UIFont boldSystemFontOfSize:length * 0.5]
                           constrainedToSize:CGSizeMake(length, length)];
    [[UIColor colorWithWhite:0.42 alpha:1.0] setFill];
    [letter drawInRect:CGRectMake((length - letterSize.width) / 2.0,
                                  (length - letterSize.height) / 2.0,
                                  letterSize.width,
                                  letterSize.height)
              withFont:[UIFont boldSystemFontOfSize:length * 0.5]];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image ?: [UIImage new];
}

@end
