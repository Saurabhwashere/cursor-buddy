#import "AudioTapInstaller.h"

@implementation AudioTapInstaller

+ (BOOL)installTapOnInputNode:(AVAudioInputNode *)inputNode
                    bufferSize:(AVAudioFrameCount)bufferSize
                        format:(AVAudioFormat *)format
                         block:(AVAudioNodeTapBlock)block
                         error:(NSError **)error {
    @try {
        [inputNode installTapOnBus:0 bufferSize:bufferSize format:format block:block];
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSString *reason = exception.reason ?: @"Audio input format was rejected.";
            *error = [NSError errorWithDomain:@"CodexCursor.AudioTap"
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: reason
            }];
        }
        return NO;
    }
}

@end
