#import <substrate.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioServices.h>
#import <Accelerate/Accelerate.h>
#import <AppSupport/AppSupport.h>
#import "MediaRemote.h"
#import <UIKit/UIKit.h>
#import "BeatVisualizerView.h"
#import "rocketbootstrap.h"
#import "prismheaders.h"
#import "LEColorPicker.h"

#define LEFT_CHANNEL (0)
#define RIGHT_CHANNEL (1)
#define MYVolumeUnitMeterView_CALIBRATION 12.0f
#define kDefaultMusicColor [[UIColor alloc] initWithRed:1.0f green:1.0f blue:1.0f alpha:1.0f]
#define kDefaultBlackColor [[UIColor alloc] initWithRed:0.0f green:0.0f blue:0.0f alpha:1.0f]
#define kDefaultRedColor [[UIColor alloc] initWithRed:1.0f green:0.0f blue:0.0f alpha:1.0f]

typedef struct AVAudioTapProcessorContext {
    Boolean supportedTapProcessingFormat;
    Boolean isNonInterleaved;
    Float64 sampleRate;
    AudioUnit audioUnit;
    Float64 sampleCount;
    float leftChannelVolume;
    float rightChannelVolume;
    void *self;
    float  * window;
    float * inReal;
    UInt32 numSamples;
    COMPLEX_SPLIT split;
    FFTSetup fftSetup;
} AVAudioTapProcessorContext;

static BOOL tweakEnabled = NO;
static CGFloat theme = 0.0;
static BOOL useColorFlow = NO;
static BOOL usePrismFlow = NO;
static BOOL overlayAlbumArt = NO;
static UIColor * overlayColor;
static UIColor * beatPrimaryColor;
static UIColor * beatSecondaryColor;
static UIColor * spectrumPrimaryColor;
static NSInteger spectrumBarCount = 30;
static NSInteger spectrumStyle = 0;

static UIColor * prismFlowPrimary;
static UIColor * prismFlowSecondary;
static float leftVol = 0.0f;
static float rightVol = 0.0f;
static float avgVol = 0.0;
static float playerVolume = 1.0;
static NSMutableArray * fftData = nil;
static NSMutableArray * lsfftData = nil;
static NSMutableArray * outData = nil;
static double mag = 0;
static BOOL isPlaying = false;
static BOOL hasProcessed = false;
static MPAVItem *item = nil;
static CADisplayLink  * displayLink = nil;
static bool useDefaultLS = NO;
static CPDistributedMessagingCenter * messagingCenter = nil;
static MPAVItem *itemWithTap = nil;
static NSString * cachedTitle = nil;

static UIColor* parseColorFromPreferences(NSString* string) {
	NSArray *prefsarray = [string componentsSeparatedByString: @":"];
	NSString *hexString = [prefsarray objectAtIndex:0];
	double alpha = [[prefsarray objectAtIndex:1] doubleValue];

	unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [[UIColor alloc] initWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:alpha];
}

static bool isNumeric(NSString* checkText)
{
	return [[NSScanner scannerWithString:checkText] scanFloat:NULL];
}

static NSString* stringFromColor(UIColor* color)
{
	const CGFloat * components = CGColorGetComponents([color CGColor]);
	return [NSString stringWithFormat:@"{%0.3f, %0.3f, %0.3f, %0.3f}", components[0], components[1], components[2], components[3]];
}

static UIColor* colorWithString(NSString * stringToConvert)
{
	NSString *cString = [stringToConvert stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	// Proper color strings are denoted with braces
	if (![cString hasPrefix:@"{"]) return nil;
	if (![cString hasSuffix:@"}"]) return nil;
	
	// Remove braces	
	cString = [cString substringFromIndex:1];
	cString = [cString substringToIndex:([cString length] - 1)];
	
	// Separate into components by removing commas and spaces
	NSArray *components = [cString componentsSeparatedByString:@", "];
	if ([components count] != 4) return nil;
	
	// Create the color
	return [UIColor colorWithRed:[[components objectAtIndex:0] floatValue]
						   green:[[components objectAtIndex:1] floatValue] 
							blue:[[components objectAtIndex:2] floatValue]
						   alpha:[[components objectAtIndex:3] floatValue]];
}

void init(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut)
{
   NSLog(@"[Prism]Initialising the Audio Tap Processor");
   AVAudioTapProcessorContext * context = (AVAudioTapProcessorContext*)calloc(1, sizeof(AVAudioTapProcessorContext));
   context->self = clientInfo;
   context->sampleRate = NAN;
   context->numSamples = 2048;

   vDSP_Length log2n = log2f((float)context->numSamples);
   int nOver2 = context->numSamples/2;

   context->inReal = (float*)malloc(context->numSamples * sizeof(float));
   context->split.realp = (float*)malloc(nOver2*sizeof(float));
   context->split.imagp = (float*)malloc(nOver2*sizeof(float));

   context->fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
   context->window = (float*)malloc(context->numSamples * sizeof(float));
   vDSP_hann_window(context->window, context->numSamples, vDSP_HANN_DENORM);

   *tapStorageOut = context;
}
 
void finalize(MTAudioProcessingTapRef tap)
{
    NSLog(@"[Prism]Finalizing the Audio Tap Processor, %@", tap);
    AVAudioTapProcessorContext * context = (AVAudioTapProcessorContext*)MTAudioProcessingTapGetStorage(tap);
    free(context->split.realp);
    free(context->split.imagp);
    free(context->inReal);
    free(context->window);

    context->fftSetup = nil;
    context->self = nil;
    free(context);

    outData = nil;
}

void prepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *processingFormat)
{
    NSLog(@"[Prism]Preparing the Audio Tap Processor");
    AVAudioTapProcessorContext * context = (AVAudioTapProcessorContext*)MTAudioProcessingTapGetStorage(tap);
    context->sampleRate = processingFormat->mSampleRate;
}

void unprepare(MTAudioProcessingTapRef tap)
{
    NSLog(@"[Prism]Unpreparing the Audio Tap Processor");
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
 
 	AVAudioTapProcessorContext * context = (AVAudioTapProcessorContext*)MTAudioProcessingTapGetStorage(tap);

 	for (UInt32 i = 0; i < bufferListInOut->mNumberBuffers; i++)
    {
        AudioBuffer *pBuffer = &bufferListInOut->mBuffers[i];
        UInt32 cSamples = numberFrames * (context->isNonInterleaved ? 1 : pBuffer->mNumberChannels);
        
        float *pData = (float *)pBuffer->mData;
        
        float rms = 0.0f;
        for (UInt32 j = 0; j < cSamples; j++)
        {
            rms += pData[j] * pData[j];
        }
        if (cSamples > 0)
        {
            rms = sqrtf(rms / cSamples);
        }
        
        if (0 == i)
        {
            leftVol = rms;
        }
        if (1 == i || (0 == i && 1 == bufferListInOut->mNumberBuffers))
        {
        	rightVol = rms;
        }
    }

    AudioBuffer * firstBuffer = &bufferListInOut->mBuffers[1];
    float * bufferData = (float*)firstBuffer->mData;
    vDSP_vmul(bufferData, 1 , context->window, 1, context->inReal, 1, context->numSamples);
    vDSP_ctoz((COMPLEX*)context->inReal, 2, &context->split, 1, context->numSamples/2);
    vDSP_Length log2n = log2f((float)context->numSamples);
    vDSP_fft_zrip(context->fftSetup, &context->split, 1, log2n, FFT_FORWARD);
    context->split.imagp[0] = 0.0;

    UInt32 i;
    if(outData)
    	outData = nil;

    outData = [[NSMutableArray alloc] init];
    [outData addObject:[NSNumber numberWithFloat:0]];

    for(i=1; i < context->numSamples/2; i++)//originally context->numSamples
    {
    	float power = sqrtf(context->split.realp[i] * context->split.realp[i] + context->split.imagp[i] * context->split.imagp[i]);   	
    	[outData addObject:[NSNumber numberWithFloat:power]];
    }
    hasProcessed = true;
}

%group NowPlayingArtView

%hook SBMediaController

-(void)setNowPlayingInfo:(id)info{
	%orig;
	NSLog(@"[Prism]setNowPlayingInfo");

	NSString * ident = [[[%c(SBMediaController) sharedInstance] nowPlayingApplication] bundleIdentifier];

	if(ident)
	{
		if(![ident isEqualToString:@"com.apple.Music"])
		{
			NSLog(@"[Prism]Audio is not from the music app, exiting.");
			return;
		}
	}

	MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef result)
	{
		NSLog(@"[Prism]Getting info dictionary");
		NSDictionary * dict = (__bridge NSDictionary*)result;

		if(!dict)
		{
			NSLog(@"[Prism]Dictionary is nil");
			return;
		}

		NSString * trackTitle = [dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoTitle];

		if(!trackTitle)
		{
			NSLog(@"[Prism]TrackTitle is nil");
			return;
		}
		
		if(!cachedTitle)
		{
			NSLog(@"[Prism]Cached is nil");
			cachedTitle = [[NSString alloc] init];
		}
		else
		{
			if([trackTitle isEqualToString:cachedTitle])
			{
				NSLog(@"[Prism]The track colors have already been generated");
				return;
			}
		}

		UIImage * image = [UIImage imageWithData:[dict objectForKey:(__bridge NSData*)kMRMediaRemoteNowPlayingInfoArtworkData]];

		if(!image)
		{
			NSLog(@"[Prism]Image is nil");
			return;
		}

		LEColorPicker * colorPicker = [[LEColorPicker alloc] init];
		LEColorScheme *colorScheme = [colorPicker colorSchemeFromImage:image];
		NSLog(@"[Prism] Valid Image %@ and scheme: %@", image, colorScheme);

		int numComponents = CGColorGetNumberOfComponents([[colorScheme backgroundColor] CGColor]);
		if(numComponents==4)
		{
			const CGFloat * components = CGColorGetComponents([[colorScheme backgroundColor] CGColor]);
			prismFlowPrimary = [UIColor colorWithRed:components[0] green:components[1] blue:components[2] alpha:components[3]];
		}
		numComponents = CGColorGetNumberOfComponents([[colorScheme primaryTextColor] CGColor]);
		if(numComponents==4)
		{
			const CGFloat * components = CGColorGetComponents([[colorScheme primaryTextColor] CGColor]);
			prismFlowSecondary = [UIColor colorWithRed:components[0] green:components[1] blue:components[2] alpha:components[3]];
		}

		if(!prismFlowPrimary || !prismFlowSecondary)
		{
			NSLog(@"[Prism]One of the colors is nil");
			return;
		}

		NSUserDefaults * prefs = [NSUserDefaults standardUserDefaults];
		[prefs setPersistentDomain:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects: stringFromColor(prismFlowPrimary),stringFromColor(prismFlowSecondary),nil] forKeys:[NSArray arrayWithObjects:@"prismFlowPrimary",@"prismFlowSecondary",nil]] forName:@"com.joshdoctors.prismpersistent"];

		NSLog(@"[Prism]Colors have been generated, reassigning the cache and releasing.");
		if(cachedTitle)cachedTitle = nil;
		cachedTitle = [NSString stringWithFormat:@"%@", trackTitle];
		NSLog(@"[Prism]cachedTitle is %@ and trackTitle is %@ (should be same)", cachedTitle, trackTitle);
		colorScheme = nil;
		colorPicker = nil;
	});
}

%end

%hook MPAVController

%new -(void)addAudioTap:(MPAVItem*)item
{
	if(itemWithTap)
	{
		MTAudioProcessingTapRef tap2 = ((AVMutableAudioMixInputParameters*)itemWithTap.playerItem.audioMix.inputParameters[0]).audioTapProcessor;
		itemWithTap.playerItem.audioMix = nil;

		if(tap2)
			CFRelease(tap2);
	}

	//This goes after so that we release the tapped item and then return out of the method
	if(!tweakEnabled)
		return;

	//If the sharedAVPlayer is null, audio is not coming from the Music App.
	if([%c(MusicAVPlayer) sharedAVPlayer]==nil)
		return;

	AVAssetTrack * audioTrack = [[[[item playerItem] asset] tracks] objectAtIndex:0];
	AVMutableAudioMixInputParameters *inputParams = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioTrack];

	// Create a processing tap for the input parameters
	MTAudioProcessingTapCallbacks callbacks;
	callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
	callbacks.clientInfo = (__bridge void *)(self);
	callbacks.init = init;
	callbacks.prepare = prepare;
	callbacks.process = process;
	callbacks.unprepare = unprepare;
	callbacks.finalize = finalize;
	
	MTAudioProcessingTapRef tap;
	// The create function makes a copy of our callbacks struct
	OSStatus err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
	 kMTAudioProcessingTapCreationFlag_PostEffects, &tap);
	if (err || !tap) {
	    NSLog(@"[Prism]Unable to create the Audio Processing Tap");
	    return;
	}
	assert(tap);

	inputParams.audioTapProcessor = tap;
	AVMutableAudioMix * audioMix = [AVMutableAudioMix audioMix];
	audioMix.inputParameters = @[inputParams];
	[item playerItem].audioMix = audioMix;
	itemWithTap = item;

	if(!displayLink)
	{
		displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateMusicMeters)];
		[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	}
}

%new - (void)updateMusicMeters
{
	if(!tweakEnabled)
		return;

	MARemoteController * rc = [[UIApplication sharedApplication] remoteController];
	MusicAVPlayer * mp = [rc player];

	if([mp rate]==0)
	{
		if([BeatVisualizerView sharedInstance].alpha==1)
		{
			[UIView animateWithDuration:.4
				animations:^{
					[BeatVisualizerView sharedInstance].alpha = 0;
				}];
		}
		return;
	}

	int appState = [[UIApplication sharedApplication] applicationState];

	if([BeatVisualizerView sharedInstance].alpha==0)
	{
		[UIView animateWithDuration:.4
			animations:^{
				[BeatVisualizerView sharedInstance].alpha = 1;
			}];
	}

	avgVol = (leftVol + rightVol)/2.0;
	playerVolume = [[[mp avPlayer] _player] volume];

	if(outData)
	{
		if(hasProcessed)
		{
			if(fftData)
			{
				fftData = nil;
			}
			fftData = [[NSMutableArray alloc] initWithArray:outData copyItems:YES];
			hasProcessed = !hasProcessed;
		}

		if(appState!=2)//appState = 0 when we are in the app, thus update
		{
			[[BeatVisualizerView sharedInstance] setOverlayAlbumArt:(int)overlayAlbumArt];
			[[BeatVisualizerView sharedInstance] setOverlayColor:overlayColor];
			[[BeatVisualizerView sharedInstance] setUseColorFlow:useColorFlow];
			[[BeatVisualizerView sharedInstance] setUsePrismFlow:usePrismFlow];
			[[BeatVisualizerView sharedInstance] setSpectrumStyle:spectrumStyle];
			[[BeatVisualizerView sharedInstance] setNumBars:spectrumBarCount];
			[[BeatVisualizerView sharedInstance] updateWithLevel:avgVol withData:fftData withMag:mag withVol:playerVolume withType:theme];
		}
	}

	if(appState!=0)//appState 2 when it is in the background, don't know what state=1 is.
	{
		if(!messagingCenter)
		{
			messagingCenter = [CPDistributedMessagingCenter centerNamed:@"com.joshdoctors.prism"];
		}

		[messagingCenter sendMessageName:@"getAudioData" userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithFloat:avgVol], @"level",
				[NSNumber numberWithFloat:playerVolume], @"playerVolume",
				fftData, @"fftData",nil]];
	}
}

-(void)_prepareToPlayItem:(id)arg1{
	%orig;
	item = self.currentItem;

	if([item playerItem].audioMix==nil)
	{
		[self addAudioTap:item];
	}
}

-(void)_itemDidChange:(id)arg1{
	%orig;
	item = self.currentItem;

	if([item playerItem].audioMix==nil)
	{
		[self addAudioTap:item];
	}
}

-(id)currentItem
{
	item = %orig;
	return item;
}

%end

/*
%hook SBLockScreenViewController

-(void)finishUIUnlockFromSource:(int)source{
	NSLog(@"Unlocked from source");
	%orig;
}

%end
*/

%hook MPUSlantedTextPlaceholderArtworkView

-(void)_updateEffectiveImage{
	NSLog(@"[Prism]_updateEffectiveImage");
	%orig;

	if(!tweakEnabled)
		return;

	if(self.frame.size.width >=320)
	{
		[[BeatVisualizerView sharedInstance] removeFromSuperview];
		[[BeatVisualizerView sharedInstance] setFrame:self.bounds];
		NSLog(@"[Prism]Added BeatVisualizerView to the Music App");
	    [self addSubview:[BeatVisualizerView sharedInstance]];
	}
}

%end

%hook _NowPlayingArtView

- (id)initWithFrame:(CGRect)frame
{
	NSLog(@"[Prism]LockScreen initWithFrame");
	id orig = %orig;

	if(!tweakEnabled)
		return orig;

	NSString * ident = [[[%c(SBMediaController) sharedInstance] nowPlayingApplication] bundleIdentifier];

	if(ident)
	{
		if(![ident isEqualToString:@"com.apple.Music"])
			return orig;
	}

	NSLog(@"[Prism]Tweak is enabled and audio coming from stock Music");
	
	if(!displayLink)
	{
		displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateMusicMeters)];
		[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	}

	if(!messagingCenter)
	{
		messagingCenter = [CPDistributedMessagingCenter centerNamed:@"com.joshdoctors.prism"];
	}

	if(![messagingCenter doesServerExist])
	{
		rocketbootstrap_distributedmessagingcenter_apply(messagingCenter);
		[messagingCenter runServerOnCurrentThread];
		[messagingCenter registerForMessageName:@"getAudioData" target:self selector:@selector(getAudioData:withUserInfo:)]; 
	}

	return orig;
}

%new - (void)getAudioData:(NSString*)name withUserInfo:(NSDictionary*)dict
{
	if([[%c(SBMediaController) sharedInstance] isPaused])
		return;

	avgVol = [dict[@"level"] floatValue];
	playerVolume = [dict[@"playerVolume"] floatValue];
	
	if(dict[@"fftData"])
		fftData = [[NSMutableArray alloc] initWithArray:dict[@"fftData"] copyItems:YES];
}

- (void)layoutSubviews
{
	NSLog(@"[Prism]LockScreen layoutSubviews");
	%orig;

	if(useDefaultLS || !tweakEnabled)
		return;

	NSString * ident = [[[%c(SBMediaController) sharedInstance] nowPlayingApplication] bundleIdentifier];

	if(ident)
	{
		if(![ident isEqualToString:@"com.apple.Music"])
			return;
	}

	NSLog(@"[Prism]Tweak is enabled and audio coming from stock Music");

	if(!displayLink)
	{
		displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateMusicMeters)];
		[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	}

	useDefaultLS = YES;
	[[BeatVisualizerView sharedInstance] removeFromSuperview];
	[[BeatVisualizerView sharedInstance] setFrame:[self artworkView].frame];
	[[BeatVisualizerView sharedInstance] setOverlayAlbumArt:(int)overlayAlbumArt];
	[[BeatVisualizerView sharedInstance] setOverlayColor:overlayColor];
	[[BeatVisualizerView sharedInstance] setUseColorFlow:useColorFlow];
	[[BeatVisualizerView sharedInstance] setUsePrismFlow:usePrismFlow];
	[[BeatVisualizerView sharedInstance] setSpectrumStyle:spectrumStyle];
	[[BeatVisualizerView sharedInstance] setNumBars:spectrumBarCount];
	NSLog(@"[Prism]Added BeatVisualizerView to the LockScreen");
    [self addSubview:[BeatVisualizerView sharedInstance]];
    useDefaultLS = NO;
}

%new - (void)updateMusicMeters
{
	if([[%c(SBMediaController) sharedInstance] isPaused])
	{
		if([BeatVisualizerView sharedInstance].alpha==1)
		{
			[UIView animateWithDuration:.4
				animations:^{
					[BeatVisualizerView sharedInstance].alpha = 0;
				}];
		}
	}
	else
	{
		if([BeatVisualizerView sharedInstance].alpha==0)
		{
			[UIView animateWithDuration:.4
				animations:^{
					[BeatVisualizerView sharedInstance].alpha = 1;
				}];
		}
	}

	/*if(fftData)
	{
		NSLog(@"Releasing FFT");
		[fftData release];
		NSLog(@"Released.");
	}*/

	[[BeatVisualizerView sharedInstance] updateWithLevel:avgVol withData:fftData withMag:mag withVol:playerVolume withType:theme];
}

%end

%end

static void loadPrefs() 
{
    CFPreferencesAppSynchronize(CFSTR("com.joshdoctors.prism"));

    tweakEnabled = !CFPreferencesCopyAppValue(CFSTR("enableTweak"), CFSTR("com.joshdoctors.prism")) ? NO : [(__bridge id)CFPreferencesCopyAppValue(CFSTR("enableTweak"), CFSTR("com.joshdoctors.prism")) boolValue];

    if (tweakEnabled) {
        NSLog(@"[Prism]is enabled");
    } else {
        NSLog(@"[Prism]is NOT enabled");
    }

    useColorFlow = !CFPreferencesCopyAppValue(CFSTR("useColorFlow"), CFSTR("com.joshdoctors.prism")) ? NO : [(__bridge id)CFPreferencesCopyAppValue(CFSTR("useColorFlow"), CFSTR("com.joshdoctors.prism")) boolValue];
    usePrismFlow = !CFPreferencesCopyAppValue(CFSTR("usePrismFlow"), CFSTR("com.joshdoctors.prism")) ? NO : [(__bridge id)CFPreferencesCopyAppValue(CFSTR("usePrismFlow"), CFSTR("com.joshdoctors.prism")) boolValue];
    overlayAlbumArt = !CFPreferencesCopyAppValue(CFSTR("overlayAlbumArt"), CFSTR("com.joshdoctors.prism")) ? NO : [(__bridge id)CFPreferencesCopyAppValue(CFSTR("overlayAlbumArt"), CFSTR("com.joshdoctors.prism")) boolValue];
    theme = !CFPreferencesCopyAppValue(CFSTR("theme"), CFSTR("com.joshdoctors.prism")) ? 0.0 : [(__bridge id)CFPreferencesCopyAppValue(CFSTR("theme"), CFSTR("com.joshdoctors.prism")) floatValue];
    overlayColor = !CFPreferencesCopyAppValue(CFSTR("overlayColor"), CFSTR("com.joshdoctors.prism")) ? kDefaultMusicColor : parseColorFromPreferences((__bridge id)CFPreferencesCopyAppValue(CFSTR("overlayColor"), CFSTR("com.joshdoctors.prism")));
    beatPrimaryColor = !CFPreferencesCopyAppValue(CFSTR("beatPrimaryColor"), CFSTR("com.joshdoctors.prism")) ? kDefaultBlackColor : parseColorFromPreferences((__bridge id)CFPreferencesCopyAppValue(CFSTR("beatPrimaryColor"), CFSTR("com.joshdoctors.prism")));
    beatSecondaryColor = !CFPreferencesCopyAppValue(CFSTR("beatSecondaryColor"), CFSTR("com.joshdoctors.prism")) ? kDefaultRedColor : parseColorFromPreferences((__bridge id)CFPreferencesCopyAppValue(CFSTR("beatSecondaryColor"), CFSTR("com.joshdoctors.prism")));
	spectrumPrimaryColor = !CFPreferencesCopyAppValue(CFSTR("spectrumPrimaryColor"), CFSTR("com.joshdoctors.prism")) ? kDefaultRedColor : parseColorFromPreferences((__bridge id)CFPreferencesCopyAppValue(CFSTR("spectrumPrimaryColor"), CFSTR("com.joshdoctors.prism")));
	spectrumStyle = !CFPreferencesCopyAppValue(CFSTR("spectrumStyle"), CFSTR("com.joshdoctors.prism")) ? 0 : [(__bridge id)CFPreferencesCopyAppValue(CFSTR("spectrumStyle"), CFSTR("com.joshdoctors.prism")) intValue];

	NSString * tempS = (__bridge NSString*)CFPreferencesCopyAppValue(CFSTR("spectrumBarCount"), CFSTR("com.joshdoctors.prism")) ?: @"30";
    spectrumBarCount = isNumeric(tempS) ? [tempS intValue] : 30;
    spectrumBarCount = spectrumBarCount > 0 ? spectrumBarCount : 30;
}

%ctor
{
	NSLog(@"[Prism]Loading Prism");
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                NULL,
                                (CFNotificationCallback)loadPrefs,
                                CFSTR("com.joshdoctors.prism/settingschanged"),
                                NULL,
                                CFNotificationSuspensionBehaviorDeliverImmediately);
	loadPrefs();

	dlopen("/System/Library/SpringBoardPlugins/NowPlayingArtLockScreen.lockbundle/NowPlayingArtLockScreen", 2);
	%init(NowPlayingArtView);
}