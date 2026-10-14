// Shared by every dylib and the settings bundle: languages (OMCCurrentLanguage, OMCTr). Only CFPreferences
// directly: the settings bundle does not have Core/OmniCar.m.
#import "OmniCar.h"
#import <UIKit/UIKit.h>

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

#pragma mark - Logo colors

UIImage *OMCLogoMeshImage(BOOL solid) {
	static UIImage *cache[2];
	static dispatch_once_t once[2];
	int i = solid ? 1 : 0;
	dispatch_once(&once[i], ^{
		// Corners sampled from assets/icon-1024.png; each a radial gradient to clear at 70% of the diagonal, like the CSS
		const CGFloat side = 96, a = solid ? 1 : 0.95;
		UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
		f.scale = 1;
		f.opaque = solid;
		UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:f];
		cache[i] = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
			CGContextRef c = rc.CGContext;
			// Arrays live inside the block: a block cannot capture a C array
			const uint32_t corners[4] = {0xA0F1D9, 0xFEC4D8, 0xA6DDFD, 0xC9BAFC};   // drawn bottom-up: TL lavender ends on top
			const CGPoint at[4] = {{side, side}, {0, side}, {side, 0}, {0, 0}};
			UIColor *base = solid ? [UIColor colorWithRed:0xE2 / 255.0 green:0xE4 / 255.0 blue:0xF6 / 255.0 alpha:1]
			                      : [UIColor colorWithRed:0xE8 / 255.0 green:0xEA / 255.0 blue:0xFA / 255.0 alpha:0.8];
			[base setFill];
			CGContextFillRect(c, CGRectMake(0, 0, side, side));
			CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
			for (int k = 0; k < 4; k++) {
				uint32_t v = corners[k];
				CGFloat R = ((v >> 16) & 0xFF) / 255.0, G = ((v >> 8) & 0xFF) / 255.0, B = (v & 0xFF) / 255.0;
				CGFloat comps[8] = {R, G, B, a, R, G, B, 0};
				CGFloat locs[2] = {0, 1};
				CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
				CGContextDrawRadialGradient(c, g, at[k], 0, at[k], side * M_SQRT2 * 0.7, 0);
				CGGradientRelease(g);
			}
			CGColorSpaceRelease(cs);
		}];
	});
	return cache[i];
}
