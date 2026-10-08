// OmniCar - unlock every limit of CarPlay.
// Skeleton: reads the prefs and reloads them live; features are added later.

#import <UIKit/UIKit.h>

#define kPrefsDomain CFSTR("com.anlai.omnicar")
#define kPrefsChanged CFSTR("com.anlai.omnicar/prefschanged")

static BOOL gEnabled = YES;

static id OMCPref(NSString *key, id fallback) {
	id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain);
	return value ?: fallback;
}

static void OMCLoadPrefs(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	gEnabled = [OMCPref(@"enabled", @YES) boolValue];
}

static void OMCPrefsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
	OMCLoadPrefs();
}

%ctor {
	@autoreleasepool {
		OMCLoadPrefs();
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMCPrefsChanged, kPrefsChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		if (!gEnabled) return;
		// Feature hooks go here (%init(GroupName) per feature).
	}
}
