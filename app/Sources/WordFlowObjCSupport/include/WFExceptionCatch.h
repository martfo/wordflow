#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, turning any Objective-C exception it raises into a Swift-
/// catchable error. AVAudioEngine's `installTapOnBus:` and `startAndReturnError:`
/// raise NSExceptions (not NSErrors) when the input device is in a bad state,
/// and a raised Objective-C exception passing through Swift frames calls
/// `abort()` — crashing the whole app. Wrapping the call lets a mic failure be
/// reported instead of fatal.
///
/// Returns YES if `block` ran to completion, NO if it raised; on NO, `error`
/// (when non-NULL) is populated from the exception's name and reason.
BOOL WFRunCatchingExceptions(void (NS_NOESCAPE ^block)(void),
                             NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
