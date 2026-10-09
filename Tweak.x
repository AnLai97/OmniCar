// OmniCar - unlock every limit of CarPlay.
//
// Core constructor: keeps the prefs domain fresh and logs where we were loaded. Each feature
// under Features/<Name>/ installs its own hooks from its own %ctor and checks
// OMCFeatureEnabled(@"<name>") at the moment it acts, so switches apply without a respring.

#import "OmniCar.h"

static void OMCPrefsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
	OMCPrefsSync();
}

%ctor {
	@autoreleasepool {
		OMCPrefsSync();
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OMCPrefsChanged, OMC_PREFS_CHANGED, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		OMCLog(@"Core", @"loaded into %@ (%@) enabled=%d", [NSBundle mainBundle].bundleIdentifier, [NSProcessInfo processInfo].processName, OMCEnabled());
	}
}
