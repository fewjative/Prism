#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioServices.h>
#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#import <AppSupport/AppSupport.h>
#import "MediaRemote.h"
#import "prismheaders.h"
#import "PrismAudioManager.h"
#import "PrismFFTHelper.h"

@implementation PrismAudioManager

+ (PrismAudioManager* )defaultManager 
{
    static dispatch_once_t pred;
    static PrismAudioManager *shared = nil;
     
    dispatch_once(&pred, ^
    {
        shared = [self new];
    });

    return shared;
}

-(void)tapStreamFromItem:(MPAVItem*)item
{
    NSLog(@"[PrismAudioManager]tapStreamFromItem: %@", item);
    [self removeTap];
    _itemWithTap = item;

    if([[[[_itemWithTap playerItem] asset] tracks] count] == 0 )
    {
        NSLog(@"[PrismAudioManager]Not attempting to tap into the stream.");
        return;
    }

    AVAssetTrack * audioTrack = [[[[_itemWithTap playerItem] asset] tracks] objectAtIndex:0];
    [self beginRecordingAudioFromTrack:audioTrack];
}


-(void)beginRecordingAudioFromTrack:(AVAssetTrack*)audioTrack
{
    MTAudioProcessingTapRef tap;
    MTAudioProcessingTapCallbacks callbacks;
    callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
    callbacks.clientInfo = (__bridge void *)(self);
    callbacks.init = init;
    callbacks.prepare = prepare;
    callbacks.process = process;
    callbacks.unprepare = unprepare;
    callbacks.finalize = finalize;
    
    OSStatus err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
     kMTAudioProcessingTapCreationFlag_PostEffects, &tap);

    if (err) {
        NSLog(@"[PrismAudioManager]Unable to create the Audio Processing Tap : %ld", err);
        return;
    }

    AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
    AVMutableAudioMixInputParameters *inputParams = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioTrack];
        
    inputParams.audioTapProcessor = tap;
    audioMix.inputParameters = @[inputParams];
    [_itemWithTap playerItem].audioMix = audioMix;
}

- (void)updateSpectrumDataWithData:(NSArray *)data withVol:(float)avgVol withLength:(NSInteger)length{
    dispatch_async(dispatch_get_main_queue(), ^ 
    {
        NSDictionary * userInfo = nil;
        if( data )
        {
            userInfo = @{@"spectrumData" : data , @"avgVol" : [NSNumber numberWithFloat:avgVol], @"spectrumDataLength" : [NSNumber numberWithInt:length] };
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:@"didChangeSpectrumData" object:nil userInfo: userInfo];
    });
}

- (void)removeTap
{
    NSLog(@"[PrismAudioManager]removing tap from: %@", _itemWithTap);

    if(_itemWithTap && _itemWithTap.playerItem.audioMix != nil)
    {
        AVMutableAudioMixInputParameters *params= ((AVMutableAudioMixInputParameters*)_itemWithTap.playerItem.audioMix.inputParameters[0]);
        MTAudioProcessingTapRef tap = params.audioTapProcessor;
        _itemWithTap.playerItem.audioMix = nil;
        CFRelease(tap);
    }
}

static PrismFFTHelper * fftHelper = nil;
static BOOL isNonInterleaved = NO;

void init(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut)
{
   NSLog(@"[PrismAudioManager]Initialising the Audio Tap Processor");
   *tapStorageOut = clientInfo;
}
 
void finalize(MTAudioProcessingTapRef tap)
{
    NSLog(@"[PrismAudioManager]Finalizing the Audio Tap Processor");  
}

void prepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *processingFormat)
{
    NSLog(@"[PrismAudioManager]Preparing the Audio Tap Processor");
    if(processingFormat->mFormatFlags && kAudioFormatFlagIsNonInterleaved)
        isNonInterleaved = YES;
    else
        isNonInterleaved = NO;
}

void unprepare(MTAudioProcessingTapRef tap)
{
    NSLog(@"[PrismAudioManager]Unpreparing the Audio Tap Processor");
}

void process(MTAudioProcessingTapRef tap, CMItemCount numberFrames,
 MTAudioProcessingTapFlags flags, AudioBufferList *bufferListInOut,
 CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut)
{   
    OSStatus err = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut,
                   flagsOut, NULL, numberFramesOut);
    if (err)
    {
        NSLog(@"[Prism]Error from GetSourceAudio: %ld", err);
        return;
    }

    if( !fftHelper )
    {
        fftHelper = [PrismFFTHelper new];
    }

    [fftHelper performComputation:bufferListInOut numberFrames:numberFrames isNonInterleaved:isNonInterleaved completionHandler:^(NSArray *fftData, float avgVol, NSInteger length)
    {
        [[PrismAudioManager defaultManager] updateSpectrumDataWithData:fftData withVol:avgVol withLength:length];
    }];
}
                        
@end