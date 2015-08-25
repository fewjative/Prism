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
#import "PrismAudioManager.h"

#define LEFT_CHANNEL (0)
#define RIGHT_CHANNEL (1)
#define MYVolumeUnitMeterView_CALIBRATION 12.0f
#define kDefaultMusicColor [[UIColor alloc] initWithRed:1.0f green:1.0f blue:1.0f alpha:1.0f]
#define kDefaultBlackColor [[UIColor alloc] initWithRed:0.0f green:0.0f blue:0.0f alpha:1.0f]
#define kDefaultRedColor [[UIColor alloc] initWithRed:1.0f green:0.0f blue:0.0f alpha:1.0f]
#define kDefaultCyanColor [[UIColor alloc] initWithRed:0.0f green:1.0f blue:1.0f alpha:1.0f]
#define kDefaultMagenta [[UIColor alloc] initWithRed:1.0f green:0.0f blue:1.0f alpha:1.0f]
#define prefPath @"/User/Library/Preferences/com.joshdoctors.prism.plist"

static BOOL tweakEnabled = NO;
static CGFloat theme = 0.0;
static NSInteger colorStyle = 0;
static BOOL overlayAlbumArt = NO;
static BOOL lyricsVisible = NO;
static BOOL wasVisible = NO;
static BOOL isVisible = NO;
static NSInteger position = 0;
static UIColor * overlayColor;
static UIColor * beatPrimaryColor;
static UIColor * beatSecondaryColor;
static UIColor * spectrumPrimaryColor;
static NSInteger spectrumBarCount = 30;
static NSInteger spectrumStyle = 0;
static float transparency = 100;
static BOOL visualizerVisibile = NO;
static float barHeight = 100;

static UIColor * prismFlowPrimary;
static UIColor * prismFlowSecondary;
static float leftVol = 0.0f;
static float rightVol = 0.0f;
static float avgVol = 0.0;
static float playerVolume = 1.0;
static BOOL shouldUpdatePrismDefaults = YES;
static NSMutableArray * fftData = nil;
static NSMutableArray * lsfftData = nil;
static NSMutableArray * outData = nil;
static NSInteger outDataLength = 1024;
static NSInteger appState = 2;
static double mag = 0;
static BOOL isPaused = NO;
static BOOL pastStatus = NO;
static BOOL isPlaying = false;
static BOOL hasProcessed = false;
static MPAVItem *item = nil;
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

%group NowPlayingArtView

%hook MPAVController

-(void)_itemDidChange:(id)arg1{
	%orig;
	NSLog(@"[Prism]Changing the music item.");

	if(!tweakEnabled)
	{
		NSLog(@"[Prism]Tweak was not enabled, not attempting to tap into the audio stream.");
		return;
	}

	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"didChangeSpectrumData" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeSpectrumData:) name:@"didChangeSpectrumData" object:nil];

	if([self.currentItem playerItem].audioMix == nil)
	{
		//Audio is not coming from the music app if the sharedAVPlayer is nil
		if([%c(MusicAVPlayer) sharedAVPlayer] == nil)
			return;
		else
			[[PrismAudioManager defaultManager] tapStreamFromItem:[self currentItem]];
	}
}

%end

%hook MusicAVPlayer

%new -(void)didChangeSpectrumData:(NSNotification*)notification{

	dispatch_async(dispatch_get_main_queue(), ^ 
	{
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

		appState = [[UIApplication sharedApplication] applicationState];
		if([mp rate]==0)
		{
			if([BeatVisualizerView sharedInstance].alpha==(transparency/100.0))
			{
				[UIView animateWithDuration:.4
					animations:^{
						[BeatVisualizerView sharedInstance].alpha = 0;
					}];
			}
			//If player is paused and audio was going through springboard, stop from sb get audio
			if(appState == 0)
				return;
		}

		if([BeatVisualizerView sharedInstance].alpha==0)
		{
			[UIView animateWithDuration:.4
				animations:^{
					[BeatVisualizerView sharedInstance].alpha = (transparency/100.0);
				}];
		}
		/*if(pastStatus != [mp rate])
		{
			if([mp rate] ==0 )
			{
				NSLog(@"Pause");
				[[BeatVisualizerView sharedInstance] pause];
			}
			else
			{
				NSLog(@"Play");
				[[BeatVisualizerView sharedInstance] play];
			}
		}

		if([mp rate] == 0)
			pastStatus = 0;
		else
			pastStatus = 1;*/
		NSArray * spectrumData = [notification.userInfo objectForKey:@"spectrumData"];
		avgVol = [[notification.userInfo objectForKey:@"avgVol"] floatValue];
		NSInteger length = [[notification.userInfo objectForKey:@"spectrumDataLength"] intValue];
		playerVolume = [[[mp avPlayer] _player] volume];

		//state = 0 -> inside the app
		//state = 1 -> on the springboard
		//state = 2 -> on the lockscreen
		if(appState == 0)
		{
			if(shouldUpdatePrismDefaults)
			{
				[[BeatVisualizerView sharedInstance] setBeatPrimaryColor:beatPrimaryColor];
				[[BeatVisualizerView sharedInstance] setBeatSecondaryColor:beatSecondaryColor];
				[[BeatVisualizerView sharedInstance] setSpectrumPrimaryColor:spectrumPrimaryColor];
				[[BeatVisualizerView sharedInstance] setAlpha:(transparency/100.0)];
				[[BeatVisualizerView sharedInstance] setBarHeight:(barHeight/100.0)];
				[[BeatVisualizerView sharedInstance] setOverlayAlbumArt:overlayAlbumArt];
				[[BeatVisualizerView sharedInstance] setOverlayColor:overlayColor];
				[[BeatVisualizerView sharedInstance] setColorStyle:colorStyle];
				[[BeatVisualizerView sharedInstance] setSpectrumStyle:spectrumStyle];
				[[BeatVisualizerView sharedInstance] setNumBars:spectrumBarCount];
				shouldUpdatePrismDefaults = NO;
			}

			[[BeatVisualizerView sharedInstance] updateWithLevel:avgVol withData:spectrumData withLength:length withVol:playerVolume withType:theme];
		} 
		else if (appState == 2)
		{
			if(!messagingCenter)
			{
				messagingCenter = [CPDistributedMessagingCenter centerNamed:@"com.joshdoctors.prism"];
				rocketbootstrap_distributedmessagingcenter_apply(messagingCenter);
			}

			[messagingCenter sendMessageName:@"getAudioData" userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
					[NSNumber numberWithFloat:avgVol], @"level",
					[NSNumber numberWithFloat:playerVolume], @"playerVolume",
					spectrumData, @"fftData",[NSNumber numberWithInt:length], @"outDataLength", nil]];
		}
	}); 
}

%end

%hook SBMediaController

-(void)setNowPlayingInfo:(id)info{
	%orig;

	if(!tweakEnabled)
	{
		NSLog(@"[Prism]Tweak is not enabled, will not attempt to generate colors.");
		return;
	}

	NSString * ident = [[[%c(SBMediaController) sharedInstance] nowPlayingApplication] bundleIdentifier];

	if(ident)
	{
		if(![ident isEqualToString:@"com.apple.Music"])
		{
			NSLog(@"[Prism]Audio is not from the music app, quitting attempt to generate colors.");
			return;
		}
	}

	/*[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"GeneratedPrismColors" object:nil userInfo:@{
		@"volume" : @"Hi"
	}]];*/

	MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef result)
	{
		//NSLog(@"[Prism]Getting info dictionary");
		NSDictionary * dict = (__bridge NSDictionary*)result;

		if(!dict)
		{
			//NSLog(@"[Prism]Dictionary is nil");
			return;
		}

		NSString * trackTitle = [dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoTitle];

		if(!trackTitle)
		{
			//NSLog(@"[Prism]TrackTitle is nil");
			return;
		}
		
		if(!cachedTitle)
		{
			//NSLog(@"[Prism]Cached is nil");
			cachedTitle = [[NSString alloc] init];
		}
		else
		{
			if([trackTitle isEqualToString:cachedTitle])
			{
				//NSLog(@"[Prism]The track colors have already been generated");
				return;
			}
		}

		UIImage * image = [UIImage imageWithData:[dict objectForKey:(__bridge NSData*)kMRMediaRemoteNowPlayingInfoArtworkData]];

		if(!image)
		{
			//NSLog(@"[Prism]Image is nil");
			return;
		}

		LEColorPicker * colorPicker = [[LEColorPicker alloc] init];
		LEColorScheme *colorScheme = [colorPicker colorSchemeFromImage:image];
		//NSLog(@"[Prism] Valid Image %@ and scheme: %@", image, colorScheme);

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
			//NSLog(@"[Prism]One of the colors is nil");
			return;
		}

		[[BeatVisualizerView sharedInstance] setPrismFlowPrimary:prismFlowPrimary];
		[[BeatVisualizerView sharedInstance] setPrismFlowSecondary:prismFlowSecondary];

		NSInteger ranRed = arc4random()%255;
		NSInteger ranGreen = arc4random()%255;
		NSInteger ranBlue = arc4random()%255;

		UIColor * randColor = [UIColor colorWithRed:ranRed/255.0f green:ranGreen/255.0f blue:ranBlue/255.0f alpha:1.0f];

		[[BeatVisualizerView sharedInstance] setRandomColorPrimary:randColor];

		ranRed = arc4random()%255;
		ranGreen = arc4random()%255;
		ranBlue = arc4random()%255;

		UIColor * randColor2 = [UIColor colorWithRed:ranRed/255.0f green:ranGreen/255.0f blue:ranBlue/255.0f alpha:1.0f];

		[[BeatVisualizerView sharedInstance] setRandomColorSecondary:randColor2];
		//NSLog(@"[Prism]Colors have been generated, reassigning the cache and releasing.");
		if(cachedTitle)cachedTitle = nil;
		cachedTitle = [NSString stringWithFormat:@"%@", trackTitle];
		//NSLog(@"[Prism]cachedTitle is %@ and trackTitle is %@ (should be same)", cachedTitle, trackTitle);
		colorScheme = nil;
		colorPicker = nil;
	});
}

%end

//MusicNowPlayingViewController < 8.4 has artworknotification, didUpdateArtworkImage, etc

%hook MusicNowPlayingViewController

-(void)_updateTitles {
	%orig;

	//NSLog(@"_updateTitles");

	//this utility will only be used for iOS devices on 8.4+
	if(![[[UIDevice currentDevice] systemVersion] isEqualToString:@"8.4"] || !tweakEnabled)
		return;

	UIView *view = [self view];

	if(!view)
		return;

	//NSLog(@"[Prism]Attemtpting to add gesture recognizer from MNPVC.");

	BOOL added = NO;
	for (UIGestureRecognizer * recognizer in view.gestureRecognizers) {
    	if([recognizer isKindOfClass:[%c(UILongPressGestureRecognizer) class]])
    		added = YES;
    }

    if(!added)
    {
    	UIGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    	[view addGestureRecognizer:longPress];
    }
}

%new -(void)longPress:(UILongPressGestureRecognizer*)gesture {
	if(gesture.state == UIGestureRecognizerStateEnded)
	{
		[[BeatVisualizerView sharedInstance] toggleVisibility];
	}
}

%end

%hook MPUSlantedTextPlaceholderArtworkView

- (void)layoutSubviews
{
	%orig;

	if(useDefaultLS || !tweakEnabled)
		return;

	UIView * superview = [self superview];

	if(!superview)
		return;

	UIViewController * vc = MSHookIvar<UIViewController*>(superview,"_viewDelegate");

	if(vc && [vc isKindOfClass:[%c(MusicNowPlayingViewController) class]])
	{
		useDefaultLS = YES;
		BOOL added = NO;
		for (UIGestureRecognizer * recognizer in self.gestureRecognizers) {
			if([recognizer isKindOfClass:[%c(UILongPressGestureRecognizer) class]])
				added = YES;
		}

	    if(!added)
	    {
	    	UIGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
	    	[self addGestureRecognizer:longPress];
	    }

		for (UIView * view in self.subviews) {
	    	if([view isKindOfClass:[%c(BeatVisualizerView) class]])
	    	{
	    		useDefaultLS = NO;
	    		return;
	    	}
	    }

		[[BeatVisualizerView sharedInstance] setFrame:self.bounds];
		NSLog(@"[Prism]Added visualizer to the Music App.: %@", self);
	    [self addSubview:[BeatVisualizerView sharedInstance]];
	    useDefaultLS = NO;		
	}
}

/*-(void)setPlaceholderTitle:(NSString*)title{

	%orig;

	if(!tweakEnabled)
	{
		//NSLog(@"[Prism]Tweak was not enabled, not adding visualizer or gesture recognizers to < 8.4.");
		return;
	}

	UIView * superview = [self superview];

	if(!superview)
		return;

	UIViewController * vc = MSHookIvar<UIViewController*>(superview,"_viewDelegate");

	if(vc && [vc isKindOfClass:[%c(MusicNowPlayingViewController) class]])
	{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			[self generatePrismColors];
		});

		for (UIView * view in self.subviews) {
	    	if([view isKindOfClass:[%c(BeatVisualizerView) class]])
	    		return;
	    }

		[[BeatVisualizerView sharedInstance] setFrame:self.bounds];
		NSLog(@"[Prism]Added visualizer to the Music App.: %@", self);
	    [self addSubview:[BeatVisualizerView sharedInstance]];

		BOOL added = NO;
		for (UIGestureRecognizer * recognizer in self.gestureRecognizers) {
			if([recognizer isKindOfClass:[%c(UILongPressGestureRecognizer) class]])
				added = YES;
		}

	    if(!added)
	    {
	    	UIGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
	    	[self addGestureRecognizer:longPress];
	    }
	}
}*/

%new -(void)longPress:(UILongPressGestureRecognizer*)gesture {
	if(gesture.state == UIGestureRecognizerStateEnded)
	{
		[[BeatVisualizerView sharedInstance] toggleVisibility];
	}
}

-(void)_setTouchHighlighted:(BOOL)b animated:(BOOL)b2 {
	if(!tweakEnabled)
		%orig;
	else
		%orig(NO, NO);
}

%new - (void)generatePrismColors {

	MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef result)
	{
		//NSLog(@"[Prism]Getting info dictionary");
		NSDictionary * dict = (__bridge NSDictionary*)result;

		if(!dict)
		{
			//NSLog(@"[Prism]Dictionary is nil");
			return;
		}

		NSString * trackTitle = [dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoTitle];

		if(!trackTitle)
		{
			//NSLog(@"[Prism]TrackTitle is nil");
			return;
		}
		
		if(!cachedTitle)
		{
			//NSLog(@"[Prism]Cached is nil");
			cachedTitle = [[NSString alloc] init];
		}
		else
		{
			if([trackTitle isEqualToString:cachedTitle])
			{
				//NSLog(@"[Prism]The track colors have already been generated");
				return;
			}
		}

		UIImage * image = [UIImage imageWithData:[dict objectForKey:(__bridge NSData*)kMRMediaRemoteNowPlayingInfoArtworkData]];

		if(!image)
		{
			//NSLog(@"[Prism]Image is nil");
			return;
		}

		LEColorPicker * colorPicker = [[LEColorPicker alloc] init];
		LEColorScheme *colorScheme = [colorPicker colorSchemeFromImage:image];
		//NSLog(@"[Prism] Valid Image %@ and scheme: %@", image, colorScheme);

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
			//NSLog(@"[Prism]One of the colors is nil");
			return;
		}

		[[BeatVisualizerView sharedInstance] setPrismFlowPrimary:prismFlowPrimary];
		[[BeatVisualizerView sharedInstance] setPrismFlowSecondary:prismFlowSecondary];

		NSInteger ranRed = arc4random()%255;
		NSInteger ranGreen = arc4random()%255;
		NSInteger ranBlue = arc4random()%255;

		UIColor * randColor = [UIColor colorWithRed:ranRed/255.0f green:ranGreen/255.0f blue:ranBlue/255.0f alpha:1.0f];

		[[BeatVisualizerView sharedInstance] setRandomColorPrimary:randColor];

		ranRed = arc4random()%255;
		ranGreen = arc4random()%255;
		ranBlue = arc4random()%255;

		UIColor * randColor2 = [UIColor colorWithRed:ranRed/255.0f green:ranGreen/255.0f blue:ranBlue/255.0f alpha:1.0f];

		[[BeatVisualizerView sharedInstance] setRandomColorSecondary:randColor2];

		/*if(!messagingCenter)
		{
			messagingCenter = [CPDistributedMessagingCenter centerNamed:@"com.joshdoctors.prism"];
			rocketbootstrap_distributedmessagingcenter_apply(messagingCenter);
		}

		[messagingCenter sendMessageName:@"getColorData" userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
				prismFlowPrimary, @"prismFlowPrimary",
				prismFlowSecondary, @"prismFlowSecondary",
					randColor, @"randomColorPrimary",randColor2, @"randomColorSecondary", nil]];*/

		//NSLog(@"[Prism]Colors have been generated, reassigning the cache and releasing.");
		if(cachedTitle)cachedTitle = nil;
		cachedTitle = [NSString stringWithFormat:@"%@", trackTitle];
		//NSLog(@"[Prism]cachedTitle is %@ and trackTitle is %@ (should be same)", cachedTitle, trackTitle);
		colorScheme = nil;
		colorPicker = nil;
	});
}

%end

%hook MusicNowPlayingItemViewController

-(id)artworkImage {
	id orig = %orig;

	//NSLog(@"[Prism]Attempting to generate prism colors from the artwork image, %@", orig);

	if(orig && tweakEnabled)
	{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			[self generatePrismColors:orig];
		});
	}

	return orig;
}

%new - (void)generatePrismColors:(UIImage*)image {

		LEColorPicker * colorPicker = [[LEColorPicker alloc] init];
		LEColorScheme *colorScheme = [colorPicker colorSchemeFromImage:image];
		//NSLog(@"[Prism] Valid Image %@ and scheme: %@", image, colorScheme);

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
			//NSLog(@"[Prism]One of the colors is nil");
			return;
		}

		[[BeatVisualizerView sharedInstance] setPrismFlowPrimary:prismFlowPrimary];
		[[BeatVisualizerView sharedInstance] setPrismFlowSecondary:prismFlowSecondary];

		NSInteger ranRed = arc4random()%255;
		NSInteger ranGreen = arc4random()%255;
		NSInteger ranBlue = arc4random()%255;

		UIColor * randColor = [UIColor colorWithRed:ranRed/255.0f green:ranGreen/255.0f blue:ranBlue/255.0f alpha:1.0f];

		[[BeatVisualizerView sharedInstance] setRandomColorPrimary:randColor];

		ranRed = arc4random()%255;
		ranGreen = arc4random()%255;
		ranBlue = arc4random()%255;

		UIColor * randColor2 = [UIColor colorWithRed:ranRed/255.0f green:ranGreen/255.0f blue:ranBlue/255.0f alpha:1.0f];

		[[BeatVisualizerView sharedInstance] setRandomColorSecondary:randColor2];

		/*if(!messagingCenter)
		{
			messagingCenter = [CPDistributedMessagingCenter centerNamed:@"com.joshdoctors.prism"];
			rocketbootstrap_distributedmessagingcenter_apply(messagingCenter);
		}

		[messagingCenter sendMessageName:@"getColorData" userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
				prismFlowPrimary, @"prismFlowPrimary",
				prismFlowSecondary, @"prismFlowSecondary",
					randColor, @"randomColorPrimary",randColor2, @"randomColorSecondary", nil]];*/

		//NSLog(@"[Prism]Colors have been generated.");

		colorScheme = nil;
		colorPicker = nil;
}

%end

%hook MusicArtworkView

- (void)layoutSubviews
{
	//NSLog(@"[Prism]layoutSubviews");

	%orig;

	if(!tweakEnabled)
	{
		//NSLog(@"[Prism]Tweak was not enabled, not adding visualizer from layoutSubviews.");
		return;
	}

	//NSLog(@"Tweak is enabled");

	UIView * superview = [self superview];

	if(!superview)
	{
		//NSLog(@"[Prism]Superview(layoutSubviews) was null.");
		return;
	}

	//NSLog(@"superview: %@", superview);

	UIViewController * vc = MSHookIvar<UIViewController*>(superview,"_viewDelegate");

	if(vc && [vc isKindOfClass:[%c(MusicNowPlayingItemViewController) class]])
	{
		[[BeatVisualizerView sharedInstance] removeFromSuperview];
		[[BeatVisualizerView sharedInstance] setFrame:self.bounds];
		NSLog(@"[Prism]Added visualizer to the Music App, %@", self);
	    [self addSubview:[BeatVisualizerView sharedInstance]];
	}
}

%new - (void)toggleVisualizerVisibility:(UITapGestureRecognizer*)sender {
	[[BeatVisualizerView sharedInstance] toggleVisibility];
}

-(void)_setTouchHighlighted:(BOOL)b animated:(BOOL)b2 {

	if(!tweakEnabled)
		%orig;
	else
		%orig(NO, NO);
}

%end

%hook _NowPlayingArtView

- (id)initWithFrame:(CGRect)frame
{
	//NSLog(@"[Prism]LockScreen initWithFrame");
	id orig = %orig;

	if(!tweakEnabled)
		return orig;

	NSString * ident = [[[%c(SBMediaController) sharedInstance] nowPlayingApplication] bundleIdentifier];

	if(ident)
	{
		if(![ident isEqualToString:@"com.apple.Music"])
		{
			NSLog(@"[Prism]Tweak is enabled but audio is not coming from the stock Music application.");
			return orig;
		}
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
		//[messagingCenter registerForMessageName:@"getColorData" target:self selector:@selector(getColorData:withUserInfo:)];
	}

	BOOL added = NO;
	for (UIGestureRecognizer * recognizer in self.gestureRecognizers) {
		if([recognizer isKindOfClass:[%c(UILongPressGestureRecognizer) class]])
			added = YES;
	}

    if(!added)
    {
    	UIGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    	[self addGestureRecognizer:longPress];
    }

	return orig;
}

%new -(void)longPress:(UILongPressGestureRecognizer*)gesture {
	if(gesture.state == UIGestureRecognizerStateEnded)
	{
		[[BeatVisualizerView sharedInstance] toggleVisibility];
	}
}

/*%new - (void)getColorData:(NSString*)name withUserInfo:(NSDictionary*)dict
{
	NSLog(@"GetColorData");
	[[BeatVisualizerView sharedInstance] setPrismFlowPrimary:dict[@"prismFlowPrimary"]];
	[[BeatVisualizerView sharedInstance] setPrismFlowSecondary:dict[@"prismFlowSecondary"]];
	[[BeatVisualizerView sharedInstance] setRandomColorPrimary:dict[@"randomColorPrimary"]];
	[[BeatVisualizerView sharedInstance] setRandomColorSecondary:dict[@"randomColorSecondary"]];
}*/

%new - (void)getAudioData:(NSString*)name withUserInfo:(NSDictionary*)dict
{
	avgVol = [dict[@"level"] floatValue];
	playerVolume = [dict[@"playerVolume"] floatValue];
	outDataLength = [dict[@"outDataLength"] intValue];
	
	if(dict[@"fftData"] && [dict[@"fftData"] isKindOfClass:[NSMutableArray class]])
		fftData = dict[@"fftData"];

	/*if(pastStatus != [[%c(SBMediaController) sharedInstance] isPaused])
	{
		if([[%c(SBMediaController) sharedInstance] isPaused])
			[[BeatVisualizerView sharedInstance] pause];
		else
			[[BeatVisualizerView sharedInstance] play];
	}

	pastStatus = [[%c(SBMediaController) sharedInstance] isPaused];*/

	if([[%c(SBMediaController) sharedInstance] isPaused])
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

	if(shouldUpdatePrismDefaults)
	{
		[[BeatVisualizerView sharedInstance] setBeatPrimaryColor:beatPrimaryColor];
		[[BeatVisualizerView sharedInstance] setBeatSecondaryColor:beatSecondaryColor];
		[[BeatVisualizerView sharedInstance] setSpectrumPrimaryColor:spectrumPrimaryColor];
		[[BeatVisualizerView sharedInstance] setAlpha:(transparency/100.0)];
		[[BeatVisualizerView sharedInstance] setBarHeight:(barHeight/100.0)];
		[[BeatVisualizerView sharedInstance] setOverlayAlbumArt:overlayAlbumArt];
		[[BeatVisualizerView sharedInstance] setOverlayColor:overlayColor];
		[[BeatVisualizerView sharedInstance] setColorStyle:colorStyle];
		[[BeatVisualizerView sharedInstance] setSpectrumStyle:spectrumStyle];
		[[BeatVisualizerView sharedInstance] setNumBars:spectrumBarCount];
		shouldUpdatePrismDefaults = NO;
	}

	[[BeatVisualizerView sharedInstance] updateWithLevel:avgVol withData:fftData withLength:outDataLength withVol:playerVolume withType:theme];
}

- (void)layoutSubviews
{
	%orig;

	if(useDefaultLS || !tweakEnabled)
		return;

	NSString * ident = [[[%c(SBMediaController) sharedInstance] nowPlayingApplication] bundleIdentifier];

	if(ident)
	{
		if(![ident isEqualToString:@"com.apple.Music"])
			return;
	}

	useDefaultLS = YES;
	[[BeatVisualizerView sharedInstance] removeFromSuperview];
	[[BeatVisualizerView sharedInstance] setFrame:[self artworkView].frame];
	NSLog(@"[Prism]Added visualizer to the LockScreen, %@", self);
    [self addSubview:[BeatVisualizerView sharedInstance]];
    useDefaultLS = NO;
}

%end

%end

static void loadPrefs() 
{
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	NSLog(@"[Prism]Settings: %@", settings);

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

    if([settings objectForKey:@"colorStyle"]) {
		colorStyle = [settings[@"colorStyle"] intValue];
	} else {
		colorStyle = 0;
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
		beatPrimaryColor = kDefaultCyanColor;
	}

	if([settings objectForKey:@"beatSecondaryColor"]) {
		beatSecondaryColor = parseColorFromPreferences(settings[@"beatSecondaryColor"]);
	} else {
		beatSecondaryColor = kDefaultMagenta;
	}

	if([settings objectForKey:@"spectrumPrimaryColor"]) {
		spectrumPrimaryColor = parseColorFromPreferences(settings[@"spectrumPrimaryColor"]);
	} else {
		spectrumPrimaryColor = kDefaultCyanColor;
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

	if([settings objectForKey:@"barHeight"]) {
		barHeight = [settings[@"barHeight"] floatValue];
	} else {
		barHeight = 100;
	}

	shouldUpdatePrismDefaults = YES;
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
	dlopen("/System/Library/SpringBoardPlugins/NowPlayingArtLockScreen.lockbundle/NowPlayingArtLockScreen", 2);
	%init(NowPlayingArtView);
}