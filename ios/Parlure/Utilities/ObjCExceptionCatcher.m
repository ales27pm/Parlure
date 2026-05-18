#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)tryBlock:(void(NS_NOESCAPE ^)(void))tryBlock error:(NSError * _Nullable * _Nullable)error {
    @try {
        tryBlock();
        return YES;
    } @catch (NSException *exception) {
        if (error != nil) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: exception.reason ?: @"Objective-C exception",
                @"exception_name": exception.name
            };
            *error = [NSError errorWithDomain:@"ObjCExceptionCatcher" code:1 userInfo:userInfo];
        }
        return NO;
    }
}

@end
