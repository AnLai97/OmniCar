#import "OMCTikTokController.h"
#import "OMCTheme.h"
#import "../TikTok.h"

@implementation OMCTikTokController

#pragma mark - Talking to TikTok

static BOOL TTKPrefBool(NSString *key, BOOL fallback) {
	id obj = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain);
	return [obj respondsToSelector:@selector(boolValue)] ? [obj boolValue] : fallback;
}

// Current values (master switch included) -> notification state -> TikTok.
static void TTKPublishPrefs(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	BOOL enabled = OMCEnabled() && TTKPrefBool(TTK_KEY_ENABLED, TTK_DEFAULT_ENABLED);
	TTKPublishState(TTKStateFromValues(enabled,
		TTKPrefBool(TTK_KEY_BACKGROUND_AUDIO, TTK_DEFAULT_BACKGROUND_AUDIO),
		TTKPrefBool(TTK_KEY_AUTO_NEXT, TTK_DEFAULT_AUTO_NEXT),
		TTKPrefBool(TTK_KEY_REMOTE_SCROLL, TTK_DEFAULT_REMOTE_SCROLL),
		TTKPrefBool(TTK_KEY_CLEAR_DISPLAY, TTK_DEFAULT_CLEAR_DISPLAY)));
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
	TTKPublishPrefs();
	[[UISelectionFeedbackGenerator new] selectionChanged];
}

// Publish once when the page opens too, so a fresh install has a valid state before any toggle.
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	TTKPublishPrefs();
}

@end
