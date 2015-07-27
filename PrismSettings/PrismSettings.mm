#import <Preferences/Preferences.h>
#import <Social/SLComposeViewController.h>
#import <Social/SLServiceTypes.h>
#import <UIKit/UIKit.h>
#define prefPath @"/User/Library/Preferences/com.joshdoctors.prism.plist"
#define kRespringAlertTag 854

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
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Respring"
		message:@"Are you sure you want to respring?"
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
    		system("killall backboardd");
    	}
    }
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
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
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
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
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
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:prefPath];
	CFStringRef toPost = (CFStringRef)specifier.properties[@"PostNotification"];
	if(toPost) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), toPost, NULL, NULL, YES);
}

@end