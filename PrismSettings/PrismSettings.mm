#import <Preferences/Preferences.h>
#import <Social/SLComposeViewController.h>
#import <Social/SLServiceTypes.h>
#import <UIKit/UIKit.h>
#import "libcolorpicker.h"
#define prefPath @"/User/Library/Preferences/com.joshdoctors.prism.plist"
#define kRespringAlertTag 854

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

static void writeAndPost(NSString* key, NSString * value) {
	NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
	[defaults addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:prefPath]];
	[defaults setObject:value forKey:key];
	[defaults writeToFile:prefPath atomically:YES];

	CFStringRef toPost = (CFStringRef)@"com.joshdoctors.prism/settingschanged";
	if(toPost) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), toPost, NULL, NULL, YES);
}

@interface PrismSettingsListController: PSEditableListController {
}
@end

static PrismSettingsListController * pslc = nil;

@interface ViewController : UIViewController <UIImagePickerControllerDelegate,UINavigationControllerDelegate>
@end

@implementation PrismSettingsListController
- (id)specifiers {
	if(_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"PrismSettings" target:self] retain];
	}
	return _specifiers;
}

-(void)twitter {

	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://mobile.twitter.com/Fewjative"]];
}

-(id)_editButtonBarItem{
	return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(composeTweet:)];
}

-(void)composeTweet:(id)sender
{
	SLComposeViewController * composeController = [SLComposeViewController composeViewControllerForServiceType:SLServiceTypeTwitter];
	[composeController setInitialText:@"I'm rocking out with the visualizers in #Prism by @Fewjative!"];
	[self presentViewController:composeController animated:YES completion:nil];
}

-(void)save
{
    [self.view endEditing:YES];
}

-(void)respring
{
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Restart Music App"
		message:@"Are you sure you want to restart the Music app? This only needs to be done after you have enabled or disabled the tweak."
		delegate:self     
		cancelButtonTitle:@"No" 
		otherButtonTitles:@"Yes", nil];
	alert.tag = kRespringAlertTag;
	[alert show];
	[alert release];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
    	if (alertView.tag == kRespringAlertTag) {
    		system("killall Music");
    	}
    }
}

-(void)selectOverlayColor {

	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	UIColor * startColor = nil;

	if([settings objectForKey:@"overlayColor"]) {
		startColor = parseColorFromPreferences(settings[@"overlayColor"]);
	} else {
		startColor = [UIColor colorWithRed:0.769 green:0.286 blue:0.008 alpha:0.75];;
	}

	PFColorAlert * alert = [PFColorAlert colorAlertWithStartColor:startColor showAlpha:YES];

	[alert displayWithCompletion:^void(UIColor *pickedColor) {
		NSString * hexString = [UIColor hexFromColor:pickedColor];
		hexString = [NSString stringWithFormat:@"%@:%g", hexString, pickedColor.alpha];

		writeAndPost(@"overlayColor", hexString);
	}];
}

-(id) readPreferenceValue:(PSSpecifier*)specifier {
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	if (!settings[specifier.properties[@"key"]]) {
		return specifier.properties[@"default"];
	}
	return settings[specifier.properties[@"key"]];
}
 
-(void) setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier {
	NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
	[defaults addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:prefPath]];
	[defaults setObject:value forKey:specifier.properties[@"key"]];
	[defaults writeToFile:prefPath atomically:YES];
	CFStringRef toPost = (CFStringRef)specifier.properties[@"PostNotification"];
	if(toPost) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), toPost, NULL, NULL, YES);
}

@end

@interface BeatSettingsListController: PSListController {
}
@end

@implementation BeatSettingsListController
- (id)specifiers {
    if(_specifiers == nil) {
     
            _specifiers = [[self loadSpecifiersFromPlistName:@"BeatSettings" target:self] retain];    
    }
    return _specifiers;
}

-(void)save
{
    [self.view endEditing:YES];
}

-(void)selectPrimaryColor {

	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	UIColor * startColor = nil;

	if([settings objectForKey:@"beatPrimaryColor"]) {
		startColor = parseColorFromPreferences(settings[@"beatPrimaryColor"]);
	} else {
		startColor = [UIColor colorWithRed:0.769 green:0.286 blue:0.008 alpha:0.75];;
	}

	PFColorAlert * alert = [PFColorAlert colorAlertWithStartColor:startColor showAlpha:YES];

	[alert displayWithCompletion:^void(UIColor *pickedColor) {
		NSString * hexString = [UIColor hexFromColor:pickedColor];
		hexString = [NSString stringWithFormat:@"%@:%g", hexString, pickedColor.alpha];

		writeAndPost(@"beatPrimaryColor", hexString);
	}];
}

-(void)selectSecondaryColor {

	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	UIColor * startColor = nil;

	if([settings objectForKey:@"beatSecondaryColor"]) {
		startColor = parseColorFromPreferences(settings[@"beatSecondaryColor"]);
	} else {
		startColor = [UIColor colorWithRed:0.769 green:0.286 blue:0.008 alpha:0.75];;
	}

	PFColorAlert * alert = [PFColorAlert colorAlertWithStartColor:startColor showAlpha:YES];

	[alert displayWithCompletion:^void(UIColor *pickedColor) {
		NSString * hexString = [UIColor hexFromColor:pickedColor];
		hexString = [NSString stringWithFormat:@"%@:%g", hexString, pickedColor.alpha];

		writeAndPost(@"beatSecondaryColor", hexString);
	}];
}

-(id) readPreferenceValue:(PSSpecifier*)specifier {
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	if (!settings[specifier.properties[@"key"]]) {
		return specifier.properties[@"default"];
	}
	return settings[specifier.properties[@"key"]];
}
 
-(void) setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier {
	NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
	[defaults addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:prefPath]];
	[defaults setObject:value forKey:specifier.properties[@"key"]];
	[defaults writeToFile:prefPath atomically:YES];
	CFStringRef toPost = (CFStringRef)specifier.properties[@"PostNotification"];
	if(toPost) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), toPost, NULL, NULL, YES);
}

@end

@interface SpectrumSettingsListController: PSListController {
}
@end

@implementation SpectrumSettingsListController
- (id)specifiers {
    if(_specifiers == nil) {
     
            _specifiers = [[self loadSpecifiersFromPlistName:@"SpectrumSettings" target:self] retain];    

    }
    return _specifiers;
}

-(void)save
{
    [self.view endEditing:YES];
}

-(void)selectPrimaryColor {

	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	UIColor * startColor = nil;

	if([settings objectForKey:@"spectrumPrimaryColor"]) {
		startColor = parseColorFromPreferences(settings[@"spectrumPrimaryColor"]);
	} else {
		startColor = [UIColor colorWithRed:0.769 green:0.286 blue:0.008 alpha:0.75];;
	}

	PFColorAlert * alert = [PFColorAlert colorAlertWithStartColor:startColor showAlpha:YES];

	[alert displayWithCompletion:^void(UIColor *pickedColor) {
		NSString * hexString = [UIColor hexFromColor:pickedColor];
		hexString = [NSString stringWithFormat:@"%@:%g", hexString, pickedColor.alpha];

		writeAndPost(@"spectrumPrimaryColor", hexString);
	}];
}

-(id) readPreferenceValue:(PSSpecifier*)specifier {
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	if (!settings[specifier.properties[@"key"]]) {
		return specifier.properties[@"default"];
	}
	return settings[specifier.properties[@"key"]];
}
 
-(void) setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier {
	NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
	[defaults addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:prefPath]];
	[defaults setObject:value forKey:specifier.properties[@"key"]];
	[defaults writeToFile:prefPath atomically:YES];
	CFStringRef toPost = (CFStringRef)specifier.properties[@"PostNotification"];
	if(toPost) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), toPost, NULL, NULL, YES);
}

@end