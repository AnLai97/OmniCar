#import "OMCSpeedBubbleController.h"
#import "OMCTheme.h"
#import "../SpeedBubble.h"
#import <notify.h>

@interface PSSpecifier (SpeedBubble)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end

@implementation OMCSpeedBubbleController

// Only one speed source now (SB_KEY_SOURCE). First visit after the update: carry over the old
// per-app switches (only Vietmap off -> GOFA), the same rule SPPPrefs uses until this is written.
- (void)viewDidLoad {
	CFPreferencesAppSynchronize(kPrefsDomain);
	CFPropertyListRef cur = CFPreferencesCopyAppValue((__bridge CFStringRef)SB_KEY_SOURCE, kPrefsDomain);
	if (cur) CFRelease(cur);
	else {
		id vm = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)SB_KEY_APP_VIETMAP, kPrefsDomain));
		id gf = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)SB_KEY_APP_GOFA, kPrefsDomain));
		BOOL gofa = vm && ![vm boolValue] && !(gf && ![gf boolValue]);
		CFPreferencesSetAppValue((__bridge CFStringRef)SB_KEY_SOURCE, (__bridge CFPropertyListRef)@(gofa ? 1 : 0), kPrefsDomain);
		CFPreferencesAppSynchronize(kPrefsDomain);
	}
	[super viewDidLoad];
}

// "Source" list from SB_SOURCE_NAMES (index = SPP_NAV_APPS index), so new navigation apps show up here.
- (NSArray *)specifiers {
	if (!_specifiers) {
		[super specifiers];
		for (PSSpecifier *spec in _specifiers) {
			if (![[spec propertyForKey:@"key"] isEqualToString:SB_KEY_SOURCE]) continue;
			NSArray *names = SB_SOURCE_NAMES;
			NSMutableArray *values = [NSMutableArray array];
			for (NSUInteger i = 0; i < names.count; i++) [values addObject:@(i)];
			[spec setValues:values titles:names];
		}
	}
	return _specifiers;
}

#pragma mark - Actions
// Darwin notifications handled by SpringBoard (../SpringBoard.xm).

// Show the bubble for 10 seconds.
- (void)bubbleDemo {
	notify_post(SB_DARWIN_DEMO);
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

// Default position, 100% size. SpringBoard writes the sizes back to 100, so re-read the sliders.
- (void)resetLayout {
	notify_post(SB_DARWIN_RESET);
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		CFPreferencesAppSynchronize(kPrefsDomain);
		[weakSelf reloadSpecifiers];
	});
}

@end
