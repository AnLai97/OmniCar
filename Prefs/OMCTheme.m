#import "OMCTheme.h"
#import <Preferences/PSTableCell.h>

#pragma mark - Localization

static NSDictionary<NSString *, NSString *> *sStrings;

NSArray<NSString *> *OMCLanguages(void) {
	return @[@"vi", @"en"];
}

NSString *OMCLanguageName(NSString *lang) {
	return [lang isEqualToString:@"vi"] ? @"Tiếng Việt" : @"English";
}

NSString *OMCLanguage(void) {
	NSString *lang = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(kLanguageKey, kPrefsDomain);
	if (lang && [OMCLanguages() containsObject:lang]) return lang;
	return [[NSLocale preferredLanguages].firstObject hasPrefix:@"vi"] ? @"vi" : @"en";
}

// Merges every table in <lang>.lproj: Localizable.strings (core) plus one <Feature>.strings per
// feature (keys are prefixed with the feature name, so tables never collide).
void OMCLoadStrings(void) {
	NSString *bundlePath = [NSBundle bundleForClass:NSClassFromString(@"OMCRootListController")].bundlePath;
	NSString *lproj = [bundlePath stringByAppendingFormat:@"/%@.lproj", OMCLanguage()];
	NSMutableDictionary *all = [NSMutableDictionary dictionary];
	for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:lproj error:nil]) {
		if (![file.pathExtension isEqualToString:@"strings"]) continue;
		NSDictionary *table = [NSDictionary dictionaryWithContentsOfFile:[lproj stringByAppendingPathComponent:file]];
		if (table) [all addEntriesFromDictionary:table];
	}
	sStrings = all;
}

NSString *L(NSString *key) {
	return sStrings[key] ?: key;
}

#pragma mark - HarmonyOS theme

static UIColor *OMCDynamicColor(UInt32 light, UInt32 dark) {
	UIColor *(^rgb)(UInt32) = ^(UInt32 v) {
		return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
	};
	UIColor *l = rgb(light), *d = rgb(dark);
	return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
		return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? d : l;
	}];
}

UIColor *OMCAccentColor(void)     { return OMCDynamicColor(0x0A59F7, 0x317AF7); }
UIColor *OMCBackgroundColor(void) { return OMCDynamicColor(0xF1F3F5, 0x000000); }
UIColor *OMCCardColor(void)       { return OMCDynamicColor(0xFFFFFF, 0x202224); }

UIColor *OMCColorFromHex(NSString *hex) {
	unsigned int v = 0;
	[[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&v];
	return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

UIImage *OMCIcon(NSString *symbol, UIColor *color) {
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
	UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
	if (!glyph) return nil;

	const CGFloat side = 29;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		CGRect rect = CGRectMake(0, 0, side, side);
		UIBezierPath *tile = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:8.5];
		[color setFill];
		[tile fill];

		[tile addClip];
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		NSArray *colors = @[(id)[UIColor colorWithWhite:1 alpha:0.22].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
		CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
		CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(0, side), 0);
		CGGradientRelease(gradient);
		CGColorSpaceRelease(space);

		CGSize s = glyph.size;
		[glyph drawInRect:CGRectMake((side - s.width) / 2, (side - s.height) / 2, s.width, s.height)];
	}];
}

BOOL OMCEnabled(void) {
	id value = (__bridge_transfer id)CFPreferencesCopyAppValue(kEnabledKey, kPrefsDomain);
	return value ? [value boolValue] : YES;
}

#pragma mark - Specifiers and cells

void OMCLocalizeSpecifiers(NSArray<PSSpecifier *> *specifiers) {
	for (PSSpecifier *spec in specifiers) {
		if (spec.name.length) spec.name = L(spec.name);
		NSString *footer = [spec propertyForKey:@"footerText"];
		if (footer) [spec setProperty:L(footer) forKey:@"footerText"];

		// Lists filled at runtime (file names etc.) set "dynamicTitles" so they are left alone.
		if (spec.titleDictionary.count && ![[spec propertyForKey:@"dynamicTitles"] boolValue]) {
			NSMutableDictionary *titles = [NSMutableDictionary dictionary];
			[spec.titleDictionary enumerateKeysAndObjectsUsingBlock:^(id value, NSString *title, BOOL *stop) {
				titles[value] = L(title);
			}];
			spec.titleDictionary = titles;
		}

		NSString *symbol = [spec propertyForKey:@"symbol"];
		if (symbol) {
			UIImage *icon = OMCIcon(symbol, OMCColorFromHex([spec propertyForKey:@"symbolColor"] ?: @"#0A59F7"));
			if (icon) [spec setProperty:icon forKey:@"iconImage"];
		} else {
			// "icon": a 29pt image in the bundle (features may ship their own drawn tile).
			id name = [spec propertyForKey:@"icon"];
			if ([name isKindOfClass:[NSString class]]) {
				NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(@"OMCRootListController")];
				UIImage *icon = [UIImage imageNamed:[(NSString *)name stringByDeletingPathExtension] inBundle:bundle compatibleWithTraitCollection:nil];
				if (icon) [spec setProperty:icon forKey:@"iconImage"];
			}
		}
	}
}

void OMCStyleCell(UITableViewCell *cell) {
	cell.backgroundColor = OMCCardColor();
	cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

	// Action rows read as regular navigation rows; only destructive ones stay red.
	PSSpecifier *spec = [cell isKindOfClass:[PSTableCell class]] ? ((PSTableCell *)cell).specifier : nil;
	if (spec.cellType == PSButtonCell) {
		BOOL destructive = [[spec propertyForKey:@"isDestructive"] boolValue];
		cell.textLabel.textColor = destructive ? [UIColor systemRedColor] : [UIColor labelColor];
		cell.accessoryType = destructive ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
	}
}

void OMCStyleHeaderFooter(UIView *view, BOOL isHeader) {
	if (![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
	UILabel *label = ((UITableViewHeaderFooterView *)view).textLabel;
	label.font = isHeader ? [UIFont systemFontOfSize:14 weight:UIFontWeightMedium] : [UIFont systemFontOfSize:12];
	label.textColor = [UIColor secondaryLabelColor];
}
