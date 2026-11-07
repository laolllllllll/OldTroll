//
//  OTProcessRunner.h
//  OldTroll
//
//  Small posix_spawn-based command runner. NSTask is private on iOS and
//  system() forces everything through a shell, which is both fragile and
//  injectable. Arguments are passed directly to the child instead.
//

#import <Foundation/Foundation.h>

@interface OTProcessResult : NSObject
@property (nonatomic, assign) int exitCode;
@property (nonatomic, copy) NSString *output;
@property (nonatomic, readonly) BOOL succeeded;
@end

@interface OTProcessRunner : NSObject

// Synchronous. Captures combined stdout/stderr. A missing or non-executable
// program is reported as exit code 127.
+ (OTProcessResult *)run:(NSString *)executable arguments:(NSArray *)arguments;

// Returns the first executable path that exists, or nil.
+ (NSString *)findExecutable:(NSArray *)candidates;

@end
