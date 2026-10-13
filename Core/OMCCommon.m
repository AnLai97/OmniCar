// Shared by every dylib and the settings bundle: languages (OMCCurrentLanguage, OMCTr). Only CFPreferences
// directly: the settings bundle does not have Core/OmniCar.m.
#import "OmniCar.h"

#pragma mark - Car profiles

// What a car profile keeps: split layout and side, Speed Bubble on the car, startup screen, iPhone app zoom
NSArray<NSString *> *OMCProfileKeys(void) {
	return @[@"splitScreenLastLeft", @"splitScreenLastRight", @"splitScreenSplitRatio", @"splitScreenSplitDirection",
		@"splitScreenPaneOrientation", @"splitScreenDriverSide", @"splitScreenAutoLaunch", @"splitScreenPinnedApp",
		@"speedBubbleSizeCar", @"speedBubbleStyle", @"startupScreenVideoName", @"startupScreenStyle", @"startupScreenCarName",
		@"startupScreenTempo", @"appBridgeZoom"];
}

#pragma mark - Languages

NSArray<NSString *> *OMCSupportedLanguages(void) {
	return @[@"vi", @"en", @"es", @"pt-BR", @"de", @"fr", @"it", @"ru", @"zh-Hans", @"ja", @"ko", @"ar", @"th", @"id"];
}

// The "language" pref, else the first device language OmniCar has (pt-PT -> pt-BR, zh-Hans-CN -> zh-Hans), else English
NSString *OMCCurrentLanguage(void) {
	NSArray<NSString *> *supported = OMCSupportedLanguages();
	NSString *chosen = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("language"), OMC_PREFS_DOMAIN));
	if ([chosen isKindOfClass:[NSString class]] && [supported containsObject:chosen]) return chosen;
	for (NSString *pref in [NSLocale preferredLanguages]) {
		for (NSString *lang in supported)
			if ([pref isEqualToString:lang] || [pref hasPrefix:[lang stringByAppendingString:@"-"]]) return lang;
		NSString *code = [pref componentsSeparatedByString:@"-"].firstObject;
		if ([code isEqualToString:@"zh"]) continue;   // zh-Hant: not translated, keep looking
		for (NSString *lang in supported)
			if ([[lang componentsSeparatedByString:@"-"].firstObject isEqualToString:code]) return lang;
	}
	return @"en";
}

// <lang>.lproj/Car.strings of the settings bundle (readable from SpringBoard and CarPlay), keyed by the English text
static NSDictionary<NSString *, NSString *> *OMCCarTable(NSString *lang) {
	static NSMutableDictionary *tables;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ tables = [NSMutableDictionary dictionary]; });
	@synchronized (tables) {
		NSDictionary *t = tables[lang];
		if (!t) {
			NSString *path = [NSString stringWithFormat:@"%@/%@.lproj/Car.strings", ROOT_PATH_NS(@"/Library/PreferenceBundles/OmniCarPrefs.bundle"), lang];
			t = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
			tables[lang] = t;
		}
		return t;
	}
}

NSString *OMCTr(NSString *vi, NSString *en) {
	NSString *lang = OMCCurrentLanguage();
	if ([lang isEqualToString:@"vi"]) return vi;
	if ([lang isEqualToString:@"en"] || !en) return en;
	return OMCCarTable(lang)[en] ?: en;
}
