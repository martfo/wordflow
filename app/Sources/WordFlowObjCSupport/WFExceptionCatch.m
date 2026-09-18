#import "WFExceptionCatch.h"

BOOL WFRunCatchingExceptions(void (NS_NOESCAPE ^block)(void),
                             NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            NSString *reason = exception.reason ?: exception.name ?: @"Objective-C exception";
            info[NSLocalizedDescriptionKey] = reason;
            if (exception.name) {
                info[@"WFExceptionName"] = exception.name;
            }
            *error = [NSError errorWithDomain:@"WordFlow.CaptureException"
                                         code:1
                                     userInfo:info];
        }
        return NO;
    }
}
