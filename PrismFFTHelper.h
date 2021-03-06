#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioServices.h>

typedef void(^PrismFFTHelperCompletionBlock)(NSArray *fftData, float avgVol, NSInteger length);

@interface PrismFFTHelper : NSObject

@property (nonatomic, assign) BOOL screenIsBlack;

- (instancetype)initWithNumberOfSamples:(UInt32)numberOfSamples;
-(void)performComputation:(AudioBufferList *)bufferListInOut numberFrames:(CMItemCount)numberFrames isNonInterleaved:(BOOL)isNonInterleaved completionHandler:(PrismFFTHelperCompletionBlock)completion;

@end

@interface SBUserAgent
-(BOOL)isScreenOn;
+(id)sharedUserAgent;
@end