#import <AVFoundation/AVFoundation.h>

@interface PrismAudioManager : NSObject

@property (nonatomic, strong, readonly) MPAVItem * itemWithTap;

+ (PrismAudioManager*)defaultManager;
- (void)tapStreamFromItem:(MPAVItem *)item;
- (void)beginRecordingAudioFromTrack:(AVAssetTrack*)audioTrack;
- (void)removeTap;
- (void)updateSpectrumDataWithData:(NSArray *)data withVol:(float)avgVol withLength:(NSInteger)length;

@end