//
//  OTInstallRequest.m
//  OldTroll
//

#import "OTInstallRequest.h"
#import "OTCompat.h"

static NSString * const OTURLSchemePrimary = @"cor-oldtroll";
static NSString * const OTURLSchemeAlias = @"apple-magnifier";

static void OTSetError(NSString **target, NSString *message) {
    if (target != NULL) {
        *target = message;
    }
}

static NSString *OTTrimmedString(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *OTPercentDecode(NSString *value) {
    if (OTStringIsEmpty(value)) {
        return value;
    }

    // iOS 7+ has the modern API; iOS 6 only has the older one. Both return
    // nil for malformed input, in which case we keep the original string.
    if ([value respondsToSelector:@selector(stringByRemovingPercentEncoding)]) {
        NSString *decoded = [value stringByRemovingPercentEncoding];
        if (decoded != nil) {
            return decoded;
        }
    }
    NSString *legacy = [value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return legacy != nil ? legacy : value;
}

static BOOL OTIsHTTPURL(NSURL *url, NSString **reason) {
    NSString *scheme = [url.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        OTSetError(reason, @"Only HTTP and HTTPS links are supported.");
        return NO;
    }
    if (OTStringIsEmpty(url.host)) {
        OTSetError(reason, @"The link does not contain a valid host.");
        return NO;
    }
    NSString *extension = [[[url path] pathExtension] lowercaseString];
    if (![extension isEqualToString:@"ipa"]) {
        OTSetError(reason, @"The link must point to an .ipa file.");
        return NO;
    }
    return YES;
}

static BOOL OTIsLocalIPA(NSURL *url, NSString **reason) {
    if (!url.isFileURL) {
        OTSetError(reason, @"The link must be a local .ipa file.");
        return NO;
    }
    NSString *path = url.path;
    if (OTStringIsEmpty(path)) {
        OTSetError(reason, @"The file path is empty.");
        return NO;
    }
    if (![[[path pathExtension] lowercaseString] isEqualToString:@"ipa"]) {
        OTSetError(reason, @"The selected file is not an .ipa file.");
        return NO;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        OTSetError(reason, @"The selected .ipa file does not exist.");
        return NO;
    }
    return YES;
}

static NSURL *OTURLFromDecodedCandidate(NSString *candidate, NSString **error) {
    NSString *trimmed = OTTrimmedString(candidate);
    if (OTStringIsEmpty(trimmed)) {
        return nil;
    }

    // Strip a fragment that belongs to the outer wrapper URL (for example
    // cor-oldtroll://install?url=https://host/app.ipa#fragment).
    NSRange hash = [trimmed rangeOfString:@"#"];
    if (hash.location != NSNotFound) {
        trimmed = [trimmed substringToIndex:hash.location];
    }

    // URLs are sometimes double-encoded by the calling app. Try once, then
    // once more, before giving up.
    NSString *decoded = OTPercentDecode(trimmed);
    for (NSInteger attempt = 0; attempt < 2; attempt++) {
        NSURL *url = [NSURL URLWithString:decoded];
        NSString *reason = nil;
        if (url != nil && OTIsHTTPURL(url, &reason)) {
            return url;
        }
        NSString *again = OTPercentDecode(decoded);
        if (again == nil || [again isEqualToString:decoded]) {
            break;
        }
        decoded = again;
    }

    if (error != NULL) {
        *error = @"The link must point to a valid .ipa file.";
    }
    return nil;
}

static NSString *OTRawQuery(NSURL *url) {
    NSString *absolute = url.absoluteString;
    if (OTStringIsEmpty(absolute)) {
        return nil;
    }
    NSRange fragment = [absolute rangeOfString:@"#"];
    if (fragment.location != NSNotFound) {
        absolute = [absolute substringToIndex:fragment.location];
    }
    NSRange question = [absolute rangeOfString:@"?"];
    if (question.location == NSNotFound) {
        return nil;
    }
    return [absolute substringFromIndex:question.location + 1];
}

@implementation OTInstallRequest

- (instancetype)init {
    self = [super init];
    if (self) {
        _createdAt = [NSDate date];
    }
    return self;
}

- (BOOL)isRemote {
    NSString *scheme = [self.sourceURL.scheme lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

- (BOOL)isLocalFile {
    return self.sourceURL.isFileURL;
}

- (NSString *)displayString {
    return self.sourceURL.absoluteString ?: @"";
}

+ (instancetype)requestWithFilePath:(NSString *)path error:(NSString **)error {
    if (OTStringIsEmpty(path)) {
        OTSetError(error, @"The file path is empty.");
        return nil;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    if (!OTIsLocalIPA(url, error)) {
        return nil;
    }
    OTInstallRequest *request = [[OTInstallRequest alloc] init];
    request.sourceURL = url;
    request.origin = OTInstallRequestOriginFile;
    request.automatic = NO;
    return request;
}

+ (instancetype)requestWithURLString:(NSString *)string error:(NSString **)error {
    NSString *trimmed = OTTrimmedString(string);
    if (OTStringIsEmpty(trimmed)) {
        OTSetError(error, @"Enter an IPA download link first.");
        return nil;
    }

    NSString *scheme = [[[[NSURL URLWithString:trimmed] scheme] lowercaseString] copy];
    if ([scheme isEqualToString:OTURLSchemePrimary] || [scheme isEqualToString:OTURLSchemeAlias]) {
        NSURL *url = [NSURL URLWithString:trimmed];
        OTInstallRequest *request = [self requestWithIncomingURL:url error:error];
        if (request != nil) {
            // A URL typed by the user should show the confirmation screen,
            // while a URL opened by another app installs in one tap.
            request.origin = OTInstallRequestOriginUserURL;
            request.automatic = NO;
        }
        return request;
    }

    NSURL *url = [NSURL URLWithString:trimmed];
    if (url == nil) {
        OTSetError(error, @"That is not a valid URL.");
        return nil;
    }

    if (url.isFileURL) {
        return [self requestWithFilePath:url.path error:error];
    }
    if (!OTIsHTTPURL(url, error)) {
        return nil;
    }

    OTInstallRequest *request = [[OTInstallRequest alloc] init];
    request.sourceURL = url;
    request.origin = OTInstallRequestOriginUserURL;
    request.automatic = NO;
    return request;
}

+ (instancetype)requestWithIncomingURL:(NSURL *)url error:(NSString **)error {
    if (url == nil) {
        OTSetError(error, @"The application received an empty URL.");
        return nil;
    }

    NSString *scheme = [url.scheme lowercaseString];
    if ([scheme isEqualToString:@"file"]) {
        return [self requestWithFilePath:url.path error:error];
    }
    if (![scheme isEqualToString:OTURLSchemePrimary] && ![scheme isEqualToString:OTURLSchemeAlias]) {
        OTSetError(error, [NSString stringWithFormat:@"Unsupported URL scheme \"%@\".", OTNonEmptyString(url.scheme, @"?")]);
        return nil;
    }

    NSString *query = OTRawQuery(url);
    NSString *failureReason = nil;

    if (!OTStringIsEmpty(query)) {
        NSRange searchRange = NSMakeRange(0, query.length);
        NSInteger keyLocation = NSNotFound;
        while (searchRange.length > 0) {
            NSRange found = [query rangeOfString:@"url=" options:NSCaseInsensitiveSearch range:searchRange];
            if (found.location == NSNotFound) {
                break;
            }
            BOOL boundary = found.location == 0;
            if (!boundary) {
                unichar previous = [query characterAtIndex:found.location - 1];
                boundary = previous == '&' || previous == '?';
            }
            if (boundary) {
                keyLocation = found.location;
                break;
            }
            NSUInteger next = NSMaxRange(found);
            searchRange = NSMakeRange(next, query.length - next);
        }

        NSString *payload = nil;
        if (keyLocation != NSNotFound) {
            payload = [query substringFromIndex:keyLocation + 4];
        } else {
            // Some callers omit the key entirely:
            //   cor-oldtroll://?https%3A%2F%2Fhost%2Fapp.ipa
            payload = query;
        }

        if ([payload hasPrefix:@"?"]) {
            payload = [payload substringFromIndex:1];
        }

        // Try the longest candidate first, then progressively cut at '&' so
        // an unencoded inner query string still survives. Percent-encoded
        // payloads never contain a literal '&' and are handled by the first
        // candidate.
        NSMutableArray *candidates = [NSMutableArray arrayWithObject:payload];
        for (NSInteger index = (NSInteger)payload.length - 1; index >= 0; index--) {
            if ([payload characterAtIndex:index] == '&') {
                [candidates addObject:[payload substringToIndex:index]];
            }
        }

        NSString *candidateError = nil;
        for (NSString *candidate in candidates) {
            NSString *candidateReason = nil;
            NSURL *resolved = OTURLFromDecodedCandidate(candidate, &candidateReason);
            if (resolved != nil) {
                OTInstallRequest *request = [[OTInstallRequest alloc] init];
                request.sourceURL = resolved;
                request.origin = OTInstallRequestOriginExternalURL;
                request.automatic = YES;
                return request;
            }
            if (candidateError == nil) {
                candidateError = candidateReason;
            }
        }
        failureReason = candidateError;

        // Allow a local file path wrapped in the scheme as well:
        //   cor-oldtroll:///var/mobile/Documents/app.ipa
        NSString *candidatePath = [url path];
        NSURL *fileURL = OTStringIsEmpty(candidatePath) ? nil : [NSURL fileURLWithPath:candidatePath];
        if (fileURL != nil && OTIsLocalIPA(fileURL, NULL)) {
            OTInstallRequest *request = [[OTInstallRequest alloc] init];
            request.sourceURL = fileURL;
            request.origin = OTInstallRequestOriginFile;
            request.automatic = NO;
            return request;
        }
    }

    // No usable query. Accept a plain file URL path as a last resort.
    NSString *candidatePath = [url path];
    NSURL *fileURL = OTStringIsEmpty(candidatePath) ? nil : [NSURL fileURLWithPath:candidatePath];
    if (fileURL != nil && OTIsLocalIPA(fileURL, NULL)) {
        OTInstallRequest *request = [[OTInstallRequest alloc] init];
        request.sourceURL = fileURL;
        request.origin = OTInstallRequestOriginFile;
        request.automatic = NO;
        return request;
    }

    OTSetError(error, failureReason ?: @"No IPA link was found. Use cor-oldtroll://install?url=<IPA URL>.");
    return nil;
}

@end
