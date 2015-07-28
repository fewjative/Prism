#import <substrate.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSDistributedNotificationCenter.h>
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
#define prefPath @"/User/Library/Preferences/com.joshdoctors.prism.plist"

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
static float transparency = 100;
static BOOL visualizerVisibile = NO;

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

	//If the sharedAVPlayer is null, audio is not coming from the Music App.
	if([%c(MusicAVPlayer) sharedAVPlayer]==nil)
		return;

	AVAssetTrack * audioTrack;

	if([[[[item playerItem] asset] tracks] count] == 0 )
		return;

	audioTrack = [[[[item playerItem] asset] tracks] objectAtIndex:0];

	AVMutableAudioMixInputParameters *inputParams = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioTrack];

	NSLog(@"[Prism]Creating the audio tap");
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

	MusicAVPlayer * mp  = NULL;
	if( [[[UIDevice currentDevice] systemVersion] isEqualToString:@"8.4"])
	{
		MusicApplicationDelegate * del = (MusicApplicationDelegate*)[[UIApplication sharedApplication] delegate];
		MusicRemoteController * rc = [del remoteController];
		mp = [rc player];
	}
	else
	{
		MARemoteController * rc = [[UIApplication sharedApplication] remoteController];
		mp = [rc player];
	}

	if([mp rate]==0)
	{
		if([BeatVisualizerView sharedInstance].alpha==(transparency/100.0))
		{
			[UIView animateWithDuration:.4
				animations:^{
					[BeatVisualizerView sharedInstance].alpha = 0;
				}];
		}
		return;
	}

	if([BeatVisualizerView sharedInstance].alpha==0)
	{
		[UIView animateWithDuration:.4
			animations:^{
				[BeatVisualizerView sharedInstance].alpha = (transparency/100.0);
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

		int appState = [[UIApplication sharedApplication] applicationState];

		//state = 0 -> inside the app
		//state = 1 -> on the springboard
		//state = 2 -> on the lockscreen
		if(appState!=2)//appState = 0 when we are in the app, thus update
		{
			[[BeatVisualizerView sharedInstance] setAlpha:(transparency/100.0)];
			[[BeatVisualizerView sharedInstance] setOverlayAlbumArt:overlayAlbumArt];
			[[BeatVisualizerView sharedInstance] setOverlayColor:overlayColor];
			[[BeatVisualizerView sharedInstance] setUseColorFlow:useColorFlow];
			[[BeatVisualizerView sharedInstance] setUsePrismFlow:usePrismFlow];
			[[BeatVisualizerView sharedInstance] setSpectrumStyle:spectrumStyle];
			[[BeatVisualizerView sharedInstance] setNumBars:spectrumBarCount];
			[[BeatVisualizerView sharedInstance] updateWithLevel:avgVol withData:fftData withMag:mag withVol:playerVolume withType:theme];
		}
	}
}

-(void)_itemDidChange:(id)arg1{
	%orig;
	NSLog(@"[Prism]Changing the item.");

	if(!tweakEnabled)
	{
		NSLog(@"[Prism]Tweak was not enabled, not tapping into the audio stream.");
		return;
	}

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

%hook MPUSlantedTextPlaceholderArtworkView

-(void)setPlaceholderTitle:(NSString*)title{

	%orig;

	if(!tweakEnabled)
	{
		NSLog(@"[Prism]Tweak was not enabled, not adding Visualizer.");
		return;
	}

	UIView * superview = [self superview];

	if(!superview)
		return;

	UIViewController * vc = MSHookIvar<UIViewController*>(superview,"_viewDelegate");

	if(vc && [vc isKindOfClass:[%c(MusicNowPlayingViewController) class]])
	{
		[self generatePrismColors];

		NSLog(@"[Prism]setPlaceholderTitle");
		for (UIView * view in self.subviews) {
	    	if([view isKindOfClass:[%c(BeatVisualizerView) class]])
	    		return;
	    }

		[[BeatVisualizerView sharedInstance] setFrame:self.bounds];
		NSLog(@"[Prism]Added BeatVisualizerView to the Music App");
	    [self addSubview:[BeatVisualizerView sharedInstance]];

	    for (UIGestureRecognizer * recognizer in self.gestureRecognizers) {
	    	[self removeGestureRecognizer:recognizer];
	    }

	    UIGestureRecognizer * tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleVisualizerVisibility:)];
	    [self setUserInteractionEnabled:YES];
	    [self addGestureRecognizer:tap];
	}
}

%new - (void)toggleVisualizerVisibility:(UITapGestureRecognizer*)sender {
	[[BeatVisualizerView sharedInstance] toggleVisibility];
}

-(void)_setTouchHighlighted:(BOOL)b animated:(BOOL)b2 {
	%orig(NO, NO);
}

%new - (void)generatePrismColors {

	[[BeatVisualizerView sharedInstance] setBeatPrimaryColor:beatPrimaryColor];
	[[BeatVisualizerView sharedInstance] setBeatSecondaryColor:beatSecondaryColor];
	[[BeatVisualizerView sharedInstance] setSpectrumPrimaryColor:spectrumPrimaryColor];

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

		[[BeatVisualizerView sharedInstance] setPrismFlowPrimary:prismFlowPrimary];
		[[BeatVisualizerView sharedInstance] setPrismFlowSecondary:prismFlowSecondary];

		NSLog(@"[Prism]Colors have been generated, reassigning the cache and releasing.");
		if(cachedTitle)cachedTitle = nil;
		cachedTitle = [NSString stringWithFormat:@"%@", trackTitle];
		NSLog(@"[Prism]cachedTitle is %@ and trackTitle is %@ (should be same)", cachedTitle, trackTitle);
		colorScheme = nil;
		colorPicker = nil;
	});
}

%end

%hook MPUVibrantContentEffectView

-(void)setBlurImageView:(UIImageView*)view{
	NSLog(@"[Prism]Setting blur view.");
	%orig;
}

%end

%hook MusicArtworkView

- (id)layoutSubviews
{
	id orig = %orig;

	if(!tweakEnabled)
	{
		NSLog(@"[Prism]Tweak was not enabled, not adding Visualizer.");
		return orig;
	}

	UIView * superview = [self superview];

	if(!superview)
	{
		NSLog(@"[Prism]Superview was null.");
		return orig;
	}

	UIViewController * vc = MSHookIvar<UIViewController*>(superview,"_viewDelegate");

	if(vc && [vc isKindOfClass:[%c(MusicNowPlayingItemViewController) class]])
	{
		[[BeatVisualizerView sharedInstance] removeFromSuperview];
		[[BeatVisualizerView sharedInstance] setFrame:self.bounds];
		NSLog(@"[Prism]Added BeatVisualizerView to the Music App");
	    [self addSubview:[BeatVisualizerView sharedInstance]];

	    for (UIGestureRecognizer * recognizer in self.gestureRecognizers) {
	    	[self removeGestureRecognizer:recognizer];
	    }

	    UIGestureRecognizer * tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleVisualizerVisibility:)];
	    [self setUserInteractionEnabled:YES];
	    [self addGestureRecognizer:tap];
	}

	return orig;
}

%new - (void)toggleVisualizerVisibility:(UITapGestureRecognizer*)sender {
	[[BeatVisualizerView sharedInstance] toggleVisibility];
}

-(void)_setTouchHighlighted:(BOOL)b animated:(BOOL)b2 {
	%orig(NO, NO);
}

-(void)setImage:(UIImage*)img {
	%orig;

	if(!tweakEnabled)
	{
		NSLog(@"[Prism]Tweak was not enabled, not generating colors from image.");
		return;
	}

	UIView * superview = [self superview];

	if(!superview)
	{
		NSLog(@"[Prism]Superview is null");
		return;
	}
	
	UIViewController * vc = MSHookIvar<UIViewController*>(superview,"_viewDelegate");

	if(vc && [vc isKindOfClass:[%c(MusicNowPlayingItemViewController) class]])
	{

		[self generatePrismColors];
	}
}

%new - (void)generatePrismColors {

	[[BeatVisualizerView sharedInstance] setBeatPrimaryColor:beatPrimaryColor];
	[[BeatVisualizerView sharedInstance] setBeatSecondaryColor:beatSecondaryColor];
	[[BeatVisualizerView sharedInstance] setSpectrumPrimaryColor:spectrumPrimaryColor];

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

		[[BeatVisualizerView sharedInstance] setPrismFlowPrimary:prismFlowPrimary];
		[[BeatVisualizerView sharedInstance] setPrismFlowSecondary:prismFlowSecondary];

		NSLog(@"[Prism]Colors have been generated, reassigning the cache and releasing.");
		if(cachedTitle)cachedTitle = nil;
		cachedTitle = [NSString stringWithFormat:@"%@", trackTitle];
		NSLog(@"[Prism]cachedTitle is %@ and trackTitle is %@ (should be same)", cachedTitle, trackTitle);
		colorScheme = nil;
		colorPicker = nil;
	});
}

%end

%end

static void loadPrefs() 
{
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	NSLog(@"Settings: %@", settings);

	if([settings objectForKey:@"enableTweak"]) {
		tweakEnabled = [settings[@"enableTweak"] boolValue];
	} else {
		tweakEnabled = NO;
	}

	if (tweakEnabled) {
        NSLog(@"[Prism]is enabled");
    } else {
        NSLog(@"[Prism]is NOT enabled");
    }

	if([settings objectForKey:@"useColorFlow"]) {
		useColorFlow = [settings[@"useColorFlow"] boolValue];
	} else {
		useColorFlow = NO;
	}

	if([settings objectForKey:@"usePrismFlow"]) {
		usePrismFlow = [settings[@"usePrismFlow"] boolValue];
	} else {
		usePrismFlow = NO;
	}

	if([settings objectForKey:@"overlayAlbumArt"]) {
		overlayAlbumArt = [settings[@"overlayAlbumArt"] boolValue];
	} else {
		overlayAlbumArt = NO;
	}

	if([settings objectForKey:@"theme"]) {
		theme = [settings[@"theme"] floatValue];
	} else {
		theme = 0.0;
	}

	if([settings objectForKey:@"overlayColor"]) {
		overlayColor = parseColorFromPreferences(settings[@"overlayColor"]);
	} else {
		overlayColor = kDefaultMusicColor;
	}

	if([settings objectForKey:@"beatPrimaryColor"]) {
		beatPrimaryColor = parseColorFromPreferences(settings[@"beatPrimaryColor"]);
	} else {
		beatPrimaryColor = kDefaultRedColor;
	}

	if([settings objectForKey:@"beatSecondaryColor"]) {
		beatSecondaryColor = parseColorFromPreferences(settings[@"beatSecondaryColor"]);
	} else {
		beatSecondaryColor = kDefaultBlackColor;
	}

	if([settings objectForKey:@"spectrumPrimaryColor"]) {
		spectrumPrimaryColor = parseColorFromPreferences(settings[@"spectrumPrimaryColor"]);
	} else {
		spectrumPrimaryColor = kDefaultRedColor;
	}

	if([settings objectForKey:@"spectrumStyle"]) {
		spectrumStyle = [settings[@"spectrumStyle"] intValue];
	} else {
		spectrumStyle = 0;
	}

	if([settings objectForKey:@"spectrumBarCount"]) {
		NSString * temp = settings[@"spectrumBarCount"];
		spectrumBarCount = isNumeric(temp) ? [temp intValue] : 30;
		spectrumBarCount = spectrumBarCount > 0 ? spectrumBarCount : 30;
	} else {
		spectrumBarCount = 30;
	}

	if([settings objectForKey:@"transparency"]) {
		transparency = [settings[@"transparency"] floatValue];
	} else {
		transparency = 100;
	}
}

%ctor
{
	NSLog(@"[Prism]Loading Prism");
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                NULL,
                                (CFNotificationCallback)loadPrefs,
                                CFSTR("com.joshdoctors.prism/settingschanged"),
                                NULL,
                                CFNotificationSuspensionBehaviorCoalesce);
	loadPrefs();

	%init(NowPlayingArtView);
}