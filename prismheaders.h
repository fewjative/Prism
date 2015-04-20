@interface SBMediaController
-(CGFloat)volume;
-(void)setVolume:(CGFloat)val;
@end

@interface MPQueuePlayer
-(AVPlayer*)_player;
@end


@interface MusicAVPlayer : AVPlayer
-(MPQueuePlayer*)avPlayer;
+(MusicAVPlayer*)sharedAVPlayer;
@end

@interface MARemoteController
-(MusicAVPlayer*)player;
@end

@interface SBLockScreenManager : NSObject
+ (id)sharedInstance;
- (BOOL)isUILocked;
- (void)unlockUIFromSource:(NSInteger)source withOptions:(id)options;
- (void)_finishUIUnlockFromSource:(NSInteger)source withOptions:(id)options;
@end

@interface MPUSlantedTextPlaceholderArtworkView : UIImageView
-(NSString*)placeholderTitle;
-(NSString*)placeholderSubTitle;
-(void)setPlaceholderTitle:(NSString*)str;
-(void)setPlaceholderSubtitle:(NSString*)str;
@end

@interface MPAVItem
@property AVAsset *asset;
@property AVPlayerItem *playerItem;
@end

@interface MPAVController
-(MPAVItem*)currentItem;
-(void)addAudioTap:(MPAVItem*)item;
@end


@interface _NowPlayingArtView : UIView
-(UIImageView*)artworkView;
@end