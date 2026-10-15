#import "OMCTheme.h"
#import "OmniCar.h"
#import <Preferences/PSTableCell.h>

#pragma mark - Localization

static NSDictionary<NSString *, NSString *> *sStrings;

NSArray<NSString *> *OMCLanguages(void) {
	return OMCSupportedLanguages();
}

// Each language in its own name (the picker lists them so)
NSString *OMCLanguageName(NSString *lang) {
	NSDictionary *names = @{@"vi": @"Tiếng Việt", @"en": @"English", @"es": @"Español", @"pt-BR": @"Português (Brasil)",
		@"de": @"Deutsch", @"fr": @"Français", @"it": @"Italiano", @"ru": @"Русский", @"zh-Hans": @"简体中文",
		@"ja": @"日本語", @"ko": @"한국어", @"ar": @"العربية", @"th": @"ไทย", @"id": @"Bahasa Indonesia"};
	return names[lang] ?: lang;
}

NSString *OMCLanguage(void) {
	return OMCCurrentLanguage();
}

// Merges every table in <lang>.lproj: Localizable.strings (core) plus one <Feature>.strings per
// feature (keys are prefixed with the feature name, so tables never collide).
void OMCLoadStrings(void) {
	NSString *bundlePath = [NSBundle bundleForClass:NSClassFromString(@"OMCRootListController")].bundlePath;
	NSString *lproj = [bundlePath stringByAppendingFormat:@"/%@.lproj", OMCLanguage()];
	NSMutableDictionary *all = [NSMutableDictionary dictionary];
	NSMutableArray *dirs = [NSMutableArray array];
	if (![OMCLanguage() isEqualToString:@"en"] && ![OMCLanguage() isEqualToString:@"vi"])
		[dirs addObject:[bundlePath stringByAppendingString:@"/en.lproj"]];   // English under a partial translation
	[dirs addObject:lproj];
	for (NSString *dir in dirs) for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
		if (![file.pathExtension isEqualToString:@"strings"] || [file isEqualToString:@"Car.strings"]) continue;
		NSDictionary *table = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:file]];
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

// Kieu OmniCar (DESIGN.md, tools/preview/index.html#overview): HarmonyOS sang + kinh chat long. Nhan tim, the kinh trang hoi
// trong (nhin thay nen chat long o dau trang), cong tac bat xanh la.
UIColor *OMCAccentColor(void)     { return OMCDynamicColor(0x7B6CF6, 0xA89BFF); }
UIColor *OMCSwitchColor(void)     { return UIColor.systemGreenColor; }
UIColor *OMCBackgroundColor(void) { return OMCDynamicColor(0xF4F5FB, 0x0E0F16); }
UIColor *OMCCardColor(void) {
	return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
		return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:0x1C / 255.0 green:0x1D / 255.0 blue:0x26 / 255.0 alpha:0.86]
		                                                        : [UIColor colorWithWhite:1 alpha:0.78];
	}];
}

UIColor *OMCColorFromHex(NSString *hex) {
	unsigned int v = 0;
	[[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&v];
	return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

// 4 cap mau pastel cua nen chat long (sang -> dam), dung cho o icon dong
static NSArray<UIColor *> *OMCPastelPair(UIColor *color) {
	CGFloat h = 0, s = 0, b = 0, a = 0;
	[color getHue:&h saturation:&s brightness:&b alpha:&a];
	NSString *lo = @"#FFC2D6", *hi = @"#FF7FA8";                                          // dao (do, cam, vang, hong)
	if (h >= 0.13 && h < 0.45) { lo = @"#9DF2D8"; hi = @"#2BC79A"; }                       // bac ha (xanh la)
	else if (h >= 0.45 && h < 0.66) { lo = @"#8FD3FF"; hi = @"#5AB8FF"; }                  // xanh troi
	else if (h >= 0.66 && h < 0.85) { lo = @"#B7A6FF"; hi = @"#8B7CFF"; }                  // oai huong (tim)
	if (s < 0.15) { lo = @"#B7A6FF"; hi = @"#8B7CFF"; }                                    // xam -> oai huong
	return @[OMCColorFromHex(lo), OMCColorFromHex(hi)];
}

// Row icon: SF Symbol trang tren o gradient pastel (theo mau goc cua dong: xanh duong -> xanh troi, xanh la -> bac ha,
// tim -> oai huong, do / cam -> dao), vet sang tren, bong mau nhe.
UIImage *OMCIcon(NSString *symbol, UIColor *color) {
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
	UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
	if (!glyph) return nil;

	const CGFloat side = 29;
	NSArray<UIColor *> *pair = OMCPastelPair(color ?: OMCAccentColor());
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		CGRect rect = CGRectMake(0, 0, side, side);
		UIBezierPath *tile = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:8.5];
		CGContextSaveGState(ctx.CGContext);
		[tile addClip];
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		NSArray *bg = @[(id)pair[0].CGColor, (id)pair[1].CGColor];
		CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)bg, NULL);
		CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(side, side), 0);
		CGGradientRelease(gradient);
		NSArray *sheen = @[(id)[UIColor colorWithWhite:1 alpha:0.35].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
		gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)sheen, NULL);
		CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(0, side / 2), 0);
		CGGradientRelease(gradient);
		CGColorSpaceRelease(space);
		CGContextRestoreGState(ctx.CGContext);

		UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 0.25, 0.25) cornerRadius:8.25];
		rim.lineWidth = 0.5;
		[[UIColor colorWithWhite:1 alpha:0.6] setStroke];
		[rim stroke];

		CGSize s = glyph.size;
		[glyph drawInRect:CGRectMake((side - s.width) / 2, (side - s.height) / 2, s.width, s.height)];
	}];
}

// Nen chat long pastel o dau trang (oai huong, xanh troi, bac ha, dao lam mo roi mo dan xuong mau nen), ve 1 lan
// cho moi kieu sang / toi. Toi: cung mau nhung nhat hon tren nen toi.
static UIImage *OMCLiquidImage(BOOL dark) {
	static UIImage *cache[2];
	if (cache[dark]) return cache[dark];
	const CGSize size = CGSizeMake(400, 340);
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
	UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		CGContextRef c = ctx.CGContext;
		[OMCColorFromHex(dark ? @"#0E0F16" : @"#F4F5FB") setFill];
		CGContextFillRect(c, CGRectMake(0, 0, size.width, size.height));
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		NSArray *blobs = @[@[@"#B7A6FF", @60, @20, @230], @[@"#8FD3FF", @340, @40, @220], @[@"#9DF2D8", @300, @230, @190], @[@"#FFC2D6", @70, @220, @180]];
		for (NSArray *bl in blobs) {
			UIColor *col = OMCColorFromHex(bl[0]);
			NSArray *cols = @[(id)[col colorWithAlphaComponent:dark ? 0.35 : 0.9].CGColor, (id)[col colorWithAlphaComponent:0].CGColor];
			CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)cols, NULL);
			CGPoint p = CGPointMake([bl[1] doubleValue], [bl[2] doubleValue]);
			CGContextDrawRadialGradient(c, g, p, 0, p, [bl[3] doubleValue], 0);
			CGGradientRelease(g);
		}
		UIColor *bg = OMCColorFromHex(dark ? @"#0E0F16" : @"#F4F5FB");
		NSArray *fade = @[(id)[bg colorWithAlphaComponent:0].CGColor, (id)bg.CGColor];
		CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)fade, NULL);
		CGContextDrawLinearGradient(c, g, CGPointMake(0, size.height * 0.45), CGPointMake(0, size.height), 0);
		CGGradientRelease(g);
		CGColorSpaceRelease(space);
	}];
	cache[dark] = img;
	return img;
}

void OMCStyleTable(UITableView *table) {
	table.backgroundColor = OMCBackgroundColor();
	table.tintColor = OMCAccentColor();
	BOOL dark = table.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
	UIView *bg = [UIView new];
	bg.backgroundColor = OMCBackgroundColor();
	UIImageView *liquid = [[UIImageView alloc] initWithImage:OMCLiquidImage(dark)];
	liquid.frame = CGRectMake(0, 0, MAX(table.bounds.size.width, 400), 340);
	liquid.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	liquid.contentMode = UIViewContentModeScaleToFill;
	[bg addSubview:liquid];
	table.backgroundView = bg;
}

// The kinh: vien sang manh, bong tim nhat (bo goc do noi goi dat)
void OMCStyleGlassCard(UIView *card) {
	card.backgroundColor = OMCCardColor();
	card.layer.borderWidth = 0.5;
	card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.7].CGColor;
	card.layer.shadowColor = [UIColor colorWithRed:70 / 255.0 green:60 / 255.0 blue:140 / 255.0 alpha:1].CGColor;
	card.layer.shadowOpacity = 0.16;
	card.layer.shadowRadius = 14;
	card.layer.shadowOffset = CGSizeMake(0, 6);
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
