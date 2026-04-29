#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioTapInstaller : NSObject

+ (BOOL)installTapOnInputNode:(AVAudioInputNode *)inputNode
                    bufferSize:(AVAudioFrameCount)bufferSize
                        format:(nullable AVAudioFormat *)format
                         block:(AVAudioNodeTapBlock)block
                         error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
