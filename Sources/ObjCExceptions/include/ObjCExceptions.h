#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs Objective-C code that can raise an NSException (which Swift can't catch, so the app aborts) and turns the
/// exception into an error. AVFoundation raises on audio-device changes, e.g. `installTap` with a stale format.
@interface ObjCExceptions : NSObject
+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
