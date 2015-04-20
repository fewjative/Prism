#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>

@interface PrismSettingsListController: PSListController {
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

-(void)save
{
    [self.view endEditing:YES];
}

-(void)setPreferenceValue:(id)value specifier:(id)spec{
	[super setPreferenceValue:value specifier:spec];
	if([[spec name] isEqualToString:@"ColorFlow Generated Colors"])
	{
		bool b = [value boolValue];
		if(!b)
			return;

		PSSpecifier * PFspec = [self specifierForID:@"prismFlowSwitch"];
		b = !CFPreferencesCopyAppValue(CFSTR("usePrismFlow"), CFSTR("com.joshdoctors.prism")) ? NO : [(id)CFPreferencesCopyAppValue(CFSTR("usePrismFlow"), CFSTR("com.joshdoctors.prism")) boolValue];
    
		if(!b)
			return;

		[super setPreferenceValue:@(NO) specifier:PFspec];
		[self reloadSpecifier:PFspec animated:YES];

    	CFPreferencesSetAppValue(CFSTR("prismFlowSwitch"), CFSTR("0"), CFSTR("com.joshdoctors.prism"));

    	CFPreferencesAppSynchronize(CFSTR("com.joshdoctors.prism"));
    		CFNotificationCenterPostNotification(
    			CFNotificationCenterGetDarwinNotifyCenter(),
    			CFSTR("com.joshdoctors.prism/settingschanged"),
    			NULL,
    			NULL,
    			YES
    			);
	}
	else if([[spec name] isEqualToString:@"Prism Generated Colors"])
	{
		bool b = [value boolValue];

		if(!b)
			return;

		PSSpecifier * CFspec = [self specifierForID:@"colorFlowSwitch"];
		b = !CFPreferencesCopyAppValue(CFSTR("useColorFlow"), CFSTR("com.joshdoctors.prism")) ? NO : [(id)CFPreferencesCopyAppValue(CFSTR("useColorFlow"), CFSTR("com.joshdoctors.prism")) boolValue];
    
		if(!b)
			return;

		[super setPreferenceValue:@(NO) specifier:CFspec];
		[self reloadSpecifier:CFspec animated:YES];

		CFPreferencesSetAppValue(CFSTR("colorFlowSwitch"), CFSTR("0"), CFSTR("com.joshdoctors.prism"));

		CFPreferencesAppSynchronize(CFSTR("com.joshdoctors.prism"));
    		CFNotificationCenterPostNotification(
    			CFNotificationCenterGetDarwinNotifyCenter(),
    			CFSTR("com.joshdoctors.prism/settingschanged"),
    			NULL,
    			NULL,
    			YES
    			);
	}
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

@end

@interface SiriSettingsListController: PSListController {
}
@end

@implementation SiriSettingsListController
- (id)specifiers {
    if(_specifiers == nil) {
     
            _specifiers = [[self loadSpecifiersFromPlistName:@"SiriSettings" target:self] retain];    

    }
    return _specifiers;
}

-(void)save
{
    [self.view endEditing:YES];
}

@end