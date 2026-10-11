#import "OMCSplitScreenController.h"
#import "OMCTheme.h"
#import "../SplitScreen.h"

@implementation OMCSplitScreenController

#pragma mark - Specifiers

static id OMCSplitPref(NSString *key) {
	return key ? (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain) : nil;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		[super specifiers];
		for (PSSpecifier *spec in [_specifiers copy]) {
			// Edit-text placeholders are strings keys too (OMCLocalizeSpecifiers only does labels and footers).
			NSString *placeholder = [spec propertyForKey:@"placeholder"];
			if (placeholder) [spec setProperty:L(placeholder) forKey:@"placeholder"];

			// Favorite rows (OMCSplitFavCell): the saved name, else the suggestion ("Đi làm"...) already in the label.
			id favIndex = [spec propertyForKey:@"favIndex"];
			if (favIndex) {
				NSString *name = OMCSplitPref([NSString stringWithFormat:@"splitScreenFav%ldName", (long)[favIndex integerValue]]);
				if ([name isKindOfClass:[NSString class]] && name.length) spec.name = name;
			}

			// Favorite layouts: the "Box 3" row only shows for 3-box layouts (3 boxes / 1 large + 2 / 2 + 1 large).
			NSString *key = [spec propertyForKey:@"key"];
			if (![key hasPrefix:@"splitScreenFav"] || ![key hasSuffix:@"Third"]) continue;
			NSString *layoutKey = [[key substringToIndex:key.length - @"Third".length] stringByAppendingString:@"Layout"];
			NSInteger layout = [OMCSplitPref(layoutKey) integerValue];
			if (layout != 3 && layout != 13 && layout != 31) [_specifiers removeObject:spec];
		}
	}
	return _specifiers;
}

// Back from a favorite's page: rebuild so its row shows the new name / apps / layout.
- (void)viewWillAppear:(BOOL)animated {
	_specifiers = nil;
	[super viewWillAppear:animated];
}

// Changing a favorite's layout shows / hides its "Box 3" row right away.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
	NSString *key = [specifier propertyForKey:@"key"];
	if (![key hasPrefix:@"splitScreenFav"] || ![key hasSuffix:@"Layout"]) return;
	// Write synchronously so the "Box 3" filter above reads the new value.
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	_specifiers = nil;
	[self reloadSpecifiers];
}

@end
