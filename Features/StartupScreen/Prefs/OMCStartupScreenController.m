#import "OMCStartupScreenController.h"
#import "OMCTheme.h"
#import "../StartupScreen.h"
#import "../SSStartupView.h"
#import <Preferences/PSTableCell.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

// AVFoundation can't load media inside CarPlay.app, so each video is extracted here into JPEG
// frames under Videos/.frames/<video>/ that the tweak plays as a flipbook.
static const int32_t kFrameRate     = 24;
static const double kMaxFrameSeconds = 60.0;
static const CGFloat kMaxFrameSide   = 1920.0;
// Bump when the extraction output changes so existing videos are re-extracted.
static const NSInteger kFramesVersion = 2;
// The logo is re-encoded to a PNG no larger than this (CarPlay decodes it while starting up).
static const CGFloat kMaxLogoSide    = 1024.0;
// Preview card: the car screen shape (wide CarPlay displays are about 16:6), at most this wide on iPad.
static const CGFloat kPreviewAspect  = 6.0 / 16.0;
static const CGFloat kPreviewMaxWidth = 560.0;
// Style gallery under the preview: one tile = a rounded symbol card + the name below.
static const CGFloat kTileWidth      = 78.0;
static const CGFloat kTileHeight     = 108.0;
static const CGFloat kTileCard       = 62.0;
static const CGFloat kTileCardTop    = 10.0;

// Same declaration as SSStartupView.h (the renderer fills the HUD lines / next event / battery with sample
// values for the preview); repeated here so this file builds against either version of the header.
void SSApplySampleData(SSStartupView *v);

// What the shared photo / file pickers are choosing.
typedef NS_ENUM(NSInteger, SSPickKind) {
	SSPickVideo,
	SSPickLogo,
	SSPickSound,
};

@interface PSSpecifier (StartupScreen)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end

#pragma mark - Pref helpers

static id SSPrefValue(NSString *key) {
	return key ? (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain) : nil;
}

static void SSSetPrefValue(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.anlai.omnicar/prefschanged"), NULL, NULL, YES);
}

static NSString *SSPrefString(NSString *key) {
	id value = SSPrefValue(key);
	return [value isKindOfClass:[NSString class]] ? value : nil;
}

// The car's own name from the last CarPlay connection (OMC_KEY_DIAG_CAR, written by CarPlay), nil when unknown.
static NSString *SSPDetectedCarName(void) {
	NSDictionary *car = SSPrefValue(@"diagCar");
	if (![car isKindOfClass:[NSDictionary class]]) return nil;
	for (NSString *group in @[@"configuration", @"session"]) {
		NSDictionary *props = car[group];
		if (![props isKindOfClass:[NSDictionary class]]) continue;
		for (NSString *field in @[@"modelName", @"name", @"vehicleName", @"accessoryName", @"model"]) {
			NSString *v = props[field];
			if ([v isKindOfClass:[NSString class]] && v.length && ![v isEqualToString:@"nil"] && ![v isEqualToString:@"(null)"]) return v;
		}
	}
	return nil;
}

#pragma mark - Styles and occasions

// String key of a style's name (SS_STYLE_* order, also the gallery order).
static NSString *SSPStyleTitleKey(NSInteger style) {
	NSArray *keys = @[@"STARTUPSCREEN_STYLE_VIDEO", @"STARTUPSCREEN_STYLE_LOGO", @"STARTUPSCREEN_STYLE_GREETING",
		@"STARTUPSCREEN_STYLE_WEATHER", @"STARTUPSCREEN_STYLE_ENGINE", @"STARTUPSCREEN_STYLE_WELCOME",
		@"STARTUPSCREEN_STYLE_PARTICLES", @"STARTUPSCREEN_STYLE_HUD", @"STARTUPSCREEN_STYLE_BRIEFING", @"STARTUPSCREEN_STYLE_LIQUID",
		@"STARTUPSCREEN_STYLE_RANDOM"];
	return (style >= 0 && style < (NSInteger)keys.count) ? keys[style] : keys[0];
}

// Gallery symbol: the first name this iOS has (some are iOS 16+, the last one of each list is iOS 15).
static UIImage *SSPStyleSymbol(NSInteger style, CGFloat pointSize) {
	NSArray *names = @[@[@"film"], @[@"seal.fill", @"seal"], @[@"hand.wave.fill", @"hand.wave"], @[@"cloud.sun.rain.fill"],
		@[@"gauge.with.dots.needle.67percent", @"speedometer"], @[@"car.side.fill", @"car.fill"], @[@"sparkles"],
		@[@"scope"], @[@"rectangle.grid.2x2.fill"], @[@"drop.fill", @"drop"], @[@"shuffle"]];
	if (style < 0 || style >= (NSInteger)names.count) return nil;
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
	for (NSString *name in names[style]) {
		UIImage *image = [UIImage systemImageNamed:name withConfiguration:config];
		if (image) return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	}
	return nil;
}

// Gallery card color per style (SS_STYLE_* order).
static UIColor *SSPStyleColor(NSInteger style) {
	NSArray *hex = @[@"#E11D48", @"#7C3AED", @"#F59E0B", @"#0EA5E9", @"#EA580C", @"#0D9488", @"#C026D3", @"#16A34A", @"#4F46E5", @"#8B7CFF", @"#475569"];
	return OMCColorFromHex((style >= 0 && style < (NSInteger)hex.count) ? hex[style] : hex[0]);
}

static NSString *SSPOccasionTitleKey(NSInteger occasion) {
	switch (occasion) {
		case SS_OCCASION_BIRTHDAY:  return @"STARTUPSCREEN_OCC_BIRTHDAY";
		case SS_OCCASION_XMAS:      return @"STARTUPSCREEN_OCC_XMAS";
		case SS_OCCASION_MIDAUTUMN: return @"STARTUPSCREEN_OCC_MIDAUTUMN";
		case SS_OCCASION_NEWYEAR:   return @"STARTUPSCREEN_OCC_NEWYEAR";
		default:                    return @"STARTUPSCREEN_OCC_TET";
	}
}

static NSDateFormatter *SSPPosixFormatter(NSString *format) {
	NSDateFormatter *df = [NSDateFormatter new];
	df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	df.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	df.timeZone = [NSTimeZone localTimeZone];
	df.dateFormat = format;
	return df;
}

// SS_KEY_BIRTHDAY ("MM-dd") as a date in the year 2000 (a leap year, so 02-29 works), nil when not set.
static NSDate *SSPBirthdayDate(NSString *monthDay) {
	if (![monthDay isKindOfClass:[NSString class]] || monthDay.length != 5) return nil;
	return [SSPPosixFormatter(@"yyyy-MM-dd") dateFromString:[@"2000-" stringByAppendingString:monthDay]];
}

// The next special day from today (today included), as SS_OCCASION_*; Tet when none is found within a year.
// Lunar dates use the Vietnamese calendar (the Chinese one at UTC+7).
static NSInteger SSPNextOccasion(NSString *birthday) {
	NSCalendar *gregorian = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	NSCalendar *lunar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierChinese];
	lunar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:7 * 3600];
	NSDate *noon = [gregorian dateBySettingHour:12 minute:0 second:0 ofDate:[NSDate date] options:0] ?: [NSDate date];
	NSString *birthdayKey = [birthday isKindOfClass:[NSString class]] && birthday.length == 5 ? birthday : nil;
	for (NSInteger i = 0; i < 400; i++) {
		NSDate *day = [gregorian dateByAddingUnit:NSCalendarUnitDay value:i toDate:noon options:0];
		if (!day) break;
		NSDateComponents *g = [gregorian components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day];
		NSDateComponents *l = [lunar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day];
		if (!l.leapMonth && l.month == 1 && l.day <= 3) return SS_OCCASION_TET;
		if (birthdayKey && [birthdayKey isEqualToString:[NSString stringWithFormat:@"%02ld-%02ld", (long)g.month, (long)g.day]]) return SS_OCCASION_BIRTHDAY;
		if (g.month == 1 && g.day == 1) return SS_OCCASION_NEWYEAR;
		if (g.month == 12 && (g.day == 24 || g.day == 25)) return SS_OCCASION_XMAS;
		if (!l.leapMonth && l.month == 8 && l.day == 15) return SS_OCCASION_MIDAUTUMN;
	}
	return SS_OCCASION_TET;
}

#pragma mark - Gallery tile

// One style in the gallery: colored rounded card with a white symbol, name below. The chosen one turns
// the violet -> sky accent gradient with a violet glow (DESIGN.md).
@interface OMCSSStyleTileCell : UICollectionViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) CAGradientLayer *fill;
@property (nonatomic, copy) NSArray *styleColors;   // the style's own gradient (shown when not chosen)
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UILabel *title;
- (void)showStyle:(NSInteger)style chosen:(BOOL)chosen dark:(BOOL)dark;
- (void)setChosen:(BOOL)chosen dark:(BOOL)dark;
@end

@implementation OMCSSStyleTileCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		CGFloat width = frame.size.width;
		self.card = [[UIView alloc] initWithFrame:CGRectMake(round((width - kTileCard) / 2), kTileCardTop, kTileCard, kTileCard)];
		self.card.layer.cornerRadius = 18;
		self.card.layer.cornerCurve = kCACornerCurveContinuous;
		self.card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.card.bounds cornerRadius:18].CGPath;
		[self.contentView addSubview:self.card];

		self.fill = [CAGradientLayer layer];
		self.fill.frame = self.card.bounds;
		self.fill.cornerRadius = 18;
		self.fill.cornerCurve = kCACornerCurveContinuous;
		self.fill.masksToBounds = YES;
		self.fill.startPoint = CGPointMake(0, 0);
		self.fill.endPoint = CGPointMake(1, 1);
		[self.card.layer addSublayer:self.fill];

		self.glyph = [[UIImageView alloc] initWithFrame:self.card.bounds];
		self.glyph.contentMode = UIViewContentModeCenter;
		[self.card addSubview:self.glyph];

		self.title = [[UILabel alloc] initWithFrame:CGRectMake(0, kTileCardTop + kTileCard + 6, width, kTileHeight - kTileCardTop - kTileCard - 6)];
		self.title.textAlignment = NSTextAlignmentCenter;
		self.title.numberOfLines = 2;
		self.title.adjustsFontSizeToFitWidth = YES;
		self.title.minimumScaleFactor = 0.8;
		self.title.lineBreakMode = NSLineBreakByWordWrapping;
		[self.contentView addSubview:self.title];

		self.isAccessibilityElement = YES;
	}
	return self;
}

- (void)showStyle:(NSInteger)style chosen:(BOOL)chosen dark:(BOOL)dark {
	UIColor *color = SSPStyleColor(style);
	CGFloat h = 0, s = 0, b = 0, a = 1;
	[color getHue:&h saturation:&s brightness:&b alpha:&a];
	UIColor *light = [UIColor colorWithHue:h saturation:s * 0.75 brightness:MIN(1.0, b * 1.15) alpha:1];
	self.styleColors = @[(id)light.CGColor, (id)color.CGColor];
	self.glyph.image = SSPStyleSymbol(style, 28);
	self.title.text = L(SSPStyleTitleKey(style));
	self.accessibilityLabel = self.title.text;
	[self setChosen:chosen dark:dark];
}

- (void)setChosen:(BOOL)chosen dark:(BOOL)dark {
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	// Chosen: the accent gradient (violet -> sky) with a violet glow; others keep their own colour
	self.fill.colors = chosen ? @[(id)OMCColorFromHex(@"#8B7CFF").CGColor, (id)OMCColorFromHex(@"#5AB8FF").CGColor] : self.styleColors;
	[CATransaction commit];
	self.card.backgroundColor = [UIColor clearColor];
	self.glyph.tintColor = [UIColor whiteColor];
	self.card.layer.shadowColor = chosen ? OMCColorFromHex(@"#6E78FF").CGColor : [UIColor colorWithRed:70 / 255.0 green:60 / 255.0 blue:140 / 255.0 alpha:1].CGColor;
	self.card.layer.shadowOpacity = chosen ? 0.5 : 0.14;
	self.card.layer.shadowRadius = chosen ? 12 : 5;
	self.card.layer.shadowOffset = CGSizeMake(0, chosen ? 5 : 2);
	self.card.layer.borderWidth = 0.5;
	self.card.layer.borderColor = [UIColor colorWithWhite:1 alpha:chosen ? 0.6 : 0.3].CGColor;
	self.card.transform = chosen ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity;
	self.title.font = [UIFont systemFontOfSize:11 weight:chosen ? UIFontWeightSemibold : UIFontWeightMedium];
	self.title.textColor = chosen ? [UIColor labelColor] : [UIColor secondaryLabelColor];
	self.accessibilityTraits = chosen ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

@end

#pragma mark - Controller

@interface OMCStartupScreenController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate,
	UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, assign) BOOL extracting;
@property (nonatomic, assign) SSPickKind pickKind;
@property (nonatomic, strong) UIView *previewHeader;
@property (nonatomic, strong) UIView *previewShadow;
@property (nonatomic, strong) SSStartupView *preview;
@property (nonatomic, assign) CGFloat previewWidth;
@property (nonatomic, strong) UILabel *galleryTitle;
@property (nonatomic, strong) UILabel *galleryHint;
@property (nonatomic, strong) UICollectionView *gallery;
@property (nonatomic, strong) UIStackView *birthdayView;
@property (nonatomic, strong) UIDatePicker *birthdayPicker;
@property (nonatomic, strong) UIButton *birthdayClear;
@property (nonatomic, strong) AVAudioPlayer *soundPlayer;
@end

@implementation OMCStartupScreenController

- (NSInteger)currentStyle {
	id value = SSPrefValue(SS_KEY_STYLE);
	NSInteger style = value ? [value integerValue] : SS_STYLE_VIDEO;
	return (style >= SS_STYLE_VIDEO && style < SS_STYLE_COUNT) ? style : SS_STYLE_VIDEO;
}

// The startup sound file name, when the file is still there.
- (NSString *)currentSound {
	NSString *name = SSPrefString(SS_KEY_SOUND_FILE);
	if (!name.length) return nil;
	return [[NSFileManager defaultManager] fileExistsAtPath:[SS_SOUNDS_DIR stringByAppendingPathComponent:name]] ? name : nil;
}

// SS_KEY_RANDOM_SET as the styles the Random style picks from (missing / empty = all of them).
- (NSArray<NSNumber *> *)randomSet {
	NSMutableArray<NSNumber *> *set = [NSMutableArray array];
	id stored = SSPrefValue(SS_KEY_RANDOM_SET);
	if ([stored isKindOfClass:[NSArray class]]) {
		for (id value in (NSArray *)stored) {
			if (![value isKindOfClass:[NSNumber class]]) continue;
			NSInteger style = [value integerValue];
			if (style >= SS_STYLE_VIDEO && style < SS_STYLE_RANDOM && ![set containsObject:@(style)]) [set addObject:@(style)];
		}
	}
	if (!set.count) for (NSInteger style = SS_STYLE_VIDEO; style < SS_STYLE_RANDOM; style++) [set addObject:@(style)];
	return set;
}

- (NSString *)occasionPreviewTitle {
	return [NSString stringWithFormat:L(@"STARTUPSCREEN_OCCASION_PREVIEW"), L(SSPOccasionTitleKey(SSPNextOccasion(SSPrefString(SS_KEY_BIRTHDAY))))];
}

#pragma mark - Specifiers

- (NSArray *)specifiers {
	if (!_specifiers) {
		[super specifiers];
		NSInteger style = [self currentStyle];
		for (PSSpecifier *spec in [_specifiers copy]) {
			// Rows that belong to other styles (plist "ssStyles") are left out.
			NSArray *styles = [spec propertyForKey:@"ssStyles"];
			if ([styles isKindOfClass:[NSArray class]] && ![styles containsObject:@(style)]) {
				[_specifiers removeObject:spec];
				continue;
			}
			// Edit-text placeholders are string keys too (OMCLocalizeSpecifiers only does labels and footers).
			NSString *placeholder = [spec propertyForKey:@"placeholder"];
			if (placeholder) [spec setProperty:L(placeholder) forKey:@"placeholder"];

			NSString *ident = spec.identifier;
			if ([ident isEqualToString:@"soundGroup"]) {
				NSString *sound = [self currentSound];
				NSString *status = sound ? [NSString stringWithFormat:L(@"STARTUPSCREEN_SOUND_CURRENT"), sound] : L(@"STARTUPSCREEN_SOUND_NONE");
				[spec setProperty:[NSString stringWithFormat:@"%@\n%@", status, L(@"STARTUPSCREEN_STARTUP_SOUND_FOOTER")] forKey:@"footerText"];
			} else if ([ident isEqualToString:@"nameGroup"]) {
				// One group for every style that shows the name: titled with the style, one footer each.
				spec.name = L(SSPStyleTitleKey(style));
				[spec setProperty:[self nameFooterForStyle:style] forKey:@"footerText"];
			} else if ([ident isEqualToString:@"carGroup"] || [ident isEqualToString:@"tempoGroup"]) {
				spec.name = L(SSPStyleTitleKey(style));
			} else if ([ident isEqualToString:@"carName"]) {
				// Empty field = the car's own name, so that is what the placeholder shows.
				[spec setProperty:SSPDetectedCarName() ?: @"OmniCar" forKey:@"placeholder"];
			} else if ([ident isEqualToString:@"occasionPreview"]) {
				spec.name = [self occasionPreviewTitle];
			}
		}
		[self refreshVideoList];
	}
	return _specifiers;
}

- (NSString *)nameFooterForStyle:(NSInteger)style {
	switch (style) {
		case SS_STYLE_WEATHER: {
			// Weather: say plainly that it uses the network, and when the last numbers came in.
			NSDictionary *cached = SSWeatherLoadCache(0);
			NSString *last = L(@"STARTUPSCREEN_WEATHER_NONE");
			NSDate *date = cached[SS_WX_DATE];
			if ([date isKindOfClass:[NSDate class]]) {
				last = [NSString stringWithFormat:L(@"STARTUPSCREEN_WEATHER_LAST"),
					[NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
			}
			return [NSString stringWithFormat:@"%@\n%@", L(@"STARTUPSCREEN_WEATHER_FOOTER"), last];
		}
		case SS_STYLE_PARTICLES: return L(@"STARTUPSCREEN_PARTICLES_FOOTER");
		case SS_STYLE_BRIEFING:  return L(@"STARTUPSCREEN_BRIEFING_FOOTER");
		default:                 return L(@"STARTUPSCREEN_GREETING_FOOTER");
	}
}

// The preview follows every setting it draws.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
	NSString *key = [specifier propertyForKey:@"key"];
	if (!key) return;
	NSArray *previewKeys = @[SS_KEY_GREET_NAME, SS_KEY_CAR_NAME, SS_KEY_TEMPO, SS_KEY_LOGO_EFFECT, SS_KEY_VIDEO_NAME, SS_KEY_SCALE_MODE];
	if (![previewKeys containsObject:key]) return;
	// Write synchronously so the preview reads the new value.
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self updatePreview];
}

#pragma mark - Cells

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	[self decorateCell:cell];
	return cell;
}

// Random checklist ticks and the birthday date picker (done after OMCStyleCell, which gives button rows a chevron).
- (void)decorateCell:(UITableViewCell *)cell {
	PSSpecifier *spec = [cell isKindOfClass:[PSTableCell class]] ? ((PSTableCell *)cell).specifier : nil;
	BOOL isBirthday = [spec.identifier isEqualToString:@"birthday"];
	if (!isBirthday && self.birthdayView && cell.accessoryView == self.birthdayView) cell.accessoryView = nil;

	id random = [spec propertyForKey:@"ssRandomStyle"];
	if ([random isKindOfClass:[NSNumber class]]) {
		BOOL on = [[self randomSet] containsObject:@([random integerValue])];
		cell.tintColor = [UIColor labelColor];
		cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		cell.textLabel.textColor = on ? [UIColor labelColor] : [UIColor secondaryLabelColor];
	} else if (isBirthday) {
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryView = [self birthdayAccessory];
	} else if ([spec.identifier isEqualToString:@"occasionPreview"]) {
		cell.textLabel.text = spec.name;
	}
}

- (void)redecorateVisibleCells {
	for (UITableViewCell *cell in self.table.visibleCells) [self decorateCell:cell];
}

#pragma mark - Preview and style gallery

- (void)viewDidLoad {
	[super viewDidLoad];
	self.previewHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 280)];

	// Soft shadow on a wrapper, rounded clipped card inside (DESIGN.md: large continuous corners).
	self.previewShadow = [UIView new];
	self.previewShadow.layer.shadowColor = [UIColor blackColor].CGColor;
	self.previewShadow.layer.shadowOpacity = 0.22;
	self.previewShadow.layer.shadowRadius = 12;
	self.previewShadow.layer.shadowOffset = CGSizeMake(0, 6);
	[self.previewHeader addSubview:self.previewShadow];

	self.preview = [[SSStartupView alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
	self.preview.layer.cornerRadius = 20;
	self.preview.layer.cornerCurve = kCACornerCurveContinuous;
	self.preview.layer.borderWidth = 0.5;
	self.preview.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
	self.preview.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.preview addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self.preview action:@selector(playIntro)]];
	[self.previewShadow addSubview:self.preview];

	// "Startup style" on the left, the replay hint on the right, then the tiles.
	self.galleryTitle = [UILabel new];
	self.galleryTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
	self.galleryTitle.textColor = [UIColor secondaryLabelColor];
	[self.previewHeader addSubview:self.galleryTitle];

	self.galleryHint = [UILabel new];
	self.galleryHint.font = [UIFont systemFontOfSize:12];
	self.galleryHint.textColor = [UIColor tertiaryLabelColor];
	self.galleryHint.textAlignment = NSTextAlignmentRight;
	self.galleryHint.adjustsFontSizeToFitWidth = YES;
	self.galleryHint.minimumScaleFactor = 0.8;
	[self.previewHeader addSubview:self.galleryHint];

	UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
	layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
	layout.itemSize = CGSizeMake(kTileWidth, kTileHeight);
	layout.minimumLineSpacing = 4;
	layout.minimumInteritemSpacing = 0;
	layout.sectionInset = UIEdgeInsetsMake(0, 14, 0, 14);
	self.gallery = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 320, kTileHeight) collectionViewLayout:layout];
	self.gallery.backgroundColor = [UIColor clearColor];
	self.gallery.showsHorizontalScrollIndicator = NO;
	self.gallery.alwaysBounceHorizontal = YES;
	self.gallery.clipsToBounds = NO;   // room for the chosen tile's glow
	self.gallery.dataSource = self;
	self.gallery.delegate = self;
	[self.gallery registerClass:[OMCSSStyleTileCell class] forCellWithReuseIdentifier:@"tile"];
	[self.previewHeader addSubview:self.gallery];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.galleryTitle.text = L(@"STARTUPSCREEN_STYLE_GROUP");
	self.galleryHint.text = L(@"STARTUPSCREEN_REPLAY_HINT");
	[self.gallery reloadData];
	[self updatePreview];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.soundPlayer stop];
	self.soundPlayer = nil;
}

// The header is sized from the table width (re-set so the table picks up the new height).
- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat width = self.table.bounds.size.width;
	if (width <= 0 || fabs(width - self.previewWidth) < 0.5) return;
	self.previewWidth = width;

	CGFloat cardWidth = MIN(kPreviewMaxWidth, width - 40);
	CGFloat cardHeight = round(cardWidth * kPreviewAspect);
	self.previewShadow.frame = CGRectMake(round((width - cardWidth) / 2), 18, cardWidth, cardHeight);
	self.preview.frame = self.previewShadow.bounds;
	self.previewShadow.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.previewShadow.bounds cornerRadius:20].CGPath;

	CGFloat y = CGRectGetMaxY(self.previewShadow.frame) + 20;
	CGFloat half = floor((width - 40) / 2);
	self.galleryTitle.frame = CGRectMake(20, y, half, 18);
	self.galleryHint.frame = CGRectMake(20 + half, y, width - 40 - half, 18);
	y += 20;
	self.gallery.frame = CGRectMake(0, y, width, kTileHeight);
	self.previewHeader.frame = CGRectMake(0, 0, width, y + kTileHeight + 2);
	self.table.tableHeaderView = self.previewHeader;
	[self scrollGalleryToStyle:[self currentStyle] animated:NO];
}

- (void)scrollGalleryToStyle:(NSInteger)style animated:(BOOL)animated {
	if (self.gallery.bounds.size.width <= 0) return;
	[self.gallery layoutIfNeeded];
	[self.gallery scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:style inSection:0]
	                     atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:animated];
}

- (BOOL)pageIsDark {
	return self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return SS_STYLE_COUNT;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	OMCSSStyleTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"tile" forIndexPath:indexPath];
	[cell showStyle:indexPath.item chosen:indexPath.item == [self currentStyle] dark:[self pageIsDark]];
	return cell;
}

// Picking a tile saves the style, shows only its rows and draws it in the preview (tapping the chosen one replays it).
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	NSInteger style = indexPath.item;
	if (style == [self currentStyle]) {
		[self updatePreview];
		return;
	}
	SSSetPrefValue(SS_KEY_STYLE, @(style));
	[[UISelectionFeedbackGenerator new] selectionChanged];
	BOOL dark = [self pageIsDark];
	[UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
		for (NSIndexPath *path in collectionView.indexPathsForVisibleItems) {
			OMCSSStyleTileCell *tile = (OMCSSStyleTileCell *)[collectionView cellForItemAtIndexPath:path];
			if ([tile isKindOfClass:[OMCSSStyleTileCell class]]) [tile setChosen:path.item == style dark:dark];
		}
	} completion:nil];
	[self scrollGalleryToStyle:style animated:YES];
	_specifiers = nil;
	[self reloadSpecifiers];
	[self updatePreview];
}

// Random: a style from its set for the preview (Video only when there is a video).
- (NSInteger)randomPreviewStyle {
	NSMutableArray<NSNumber *> *set = [[self randomSet] mutableCopy];
	if (![self selectedVideo]) [set removeObject:@(SS_STYLE_VIDEO)];
	if (!set.count) return SS_STYLE_GREETING;
	return [set[arc4random_uniform((uint32_t)set.count)] integerValue];
}

- (void)updatePreview {
	[self showPreviewStyle:[self currentStyle] occasion:SS_OCCASION_NONE];
}

// Draws the settings with the car's renderer: the user's name, car name, tempo, logo, video poster and the
// last cached weather (else a sample, since the settings page never goes online); SSApplySampleData fills the
// HUD lines, next event and battery.
- (void)showPreviewStyle:(NSInteger)style occasion:(NSInteger)occasion {
	SSStartupView *preview = self.preview;
	if (!preview) return;
	NSInteger shown = style == SS_STYLE_RANDOM ? [self randomPreviewStyle] : style;
	preview.image = nil;
	preview.weather = nil;
	preview.hud = nil;
	preview.nextEvent = nil;
	preview.style = shown;
	preview.occasion = occasion;
	SSApplySampleData(preview);

	// The user's own values win over the samples.
	preview.occasion = occasion;
	preview.name = SSPrefString(SS_KEY_GREET_NAME);
	NSString *carName = SSPrefString(SS_KEY_CAR_NAME);
	preview.carName = carName.length ? carName : SSPDetectedCarName();
	id tempo = SSPrefValue(SS_KEY_TEMPO);
	preview.tempo = tempo ? MAX(0, MIN(2, [tempo integerValue])) : 1;
	preview.logoEffect = [SSPrefValue(SS_KEY_LOGO_EFFECT) integerValue];
	id duration = SSPrefValue(SS_KEY_DURATION);   // Particles scatter at the end of it, as on the car
	preview.duration = duration ? MAX(1.0, MIN(30.0, [duration doubleValue])) : 5.0;
	preview.date = [NSDate date];
	if (shown == SS_STYLE_LOGO) {
		preview.image = [UIImage imageWithContentsOfFile:SS_LOGO_PATH];
	} else if (shown == SS_STYLE_VIDEO) {
		NSString *video = [self selectedVideo];
		if (video) preview.image = [UIImage imageWithContentsOfFile:[SS_FRAMES_DIR(video) stringByAppendingPathComponent:@"00000.jpg"]];
		preview.imageFits = [SSPrefValue(SS_KEY_SCALE_MODE) integerValue] == 1;
	} else if (shown == SS_STYLE_WEATHER || shown == SS_STYLE_BRIEFING) {
		preview.weather = SSWeatherLoadCache(0) ?: preview.weather
			?: @{SS_WX_TEMP: @28, SS_WX_HIGH: @31, SS_WX_LOW: @24, SS_WX_RAIN: @40, SS_WX_CODE: @2, SS_WX_DAY: @YES};
	}
	[preview reload];
	[preview playIntro];
}

#pragma mark - Random set

- (void)toggleRandomStyle:(PSSpecifier *)specifier {
	id value = [specifier propertyForKey:@"ssRandomStyle"];
	if (![value isKindOfClass:[NSNumber class]]) return;
	NSNumber *style = @([value integerValue]);
	NSMutableArray<NSNumber *> *set = [[self randomSet] mutableCopy];
	if ([set containsObject:style]) {
		if (set.count <= 1) { [self showMessage:L(@"STARTUPSCREEN_RANDOM_KEEP_ONE")]; return; }
		[set removeObject:style];
	} else {
		[set addObject:style];
	}
	[set sortUsingSelector:@selector(compare:)];
	SSSetPrefValue(SS_KEY_RANDOM_SET, set);
	[[UISelectionFeedbackGenerator new] selectionChanged];
	[self redecorateVisibleCells];
}

#pragma mark - Special days

// Birthday row accessory: a compact date picker (date only, the year is ignored) and a red clear button.
- (UIView *)birthdayAccessory {
	if (!self.birthdayView) {
		UIDatePicker *picker = [UIDatePicker new];
		picker.datePickerMode = UIDatePickerModeDate;
		picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
		picker.locale = [NSLocale localeWithLocaleIdentifier:OMCLanguage()];
		picker.tintColor = [UIColor labelColor];
		[picker addTarget:self action:@selector(birthdayChanged:) forControlEvents:UIControlEventValueChanged];

		UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
		[clear setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
		clear.tintColor = OMCColorFromHex(@"#FF5C54");
		clear.accessibilityLabel = L(@"STARTUPSCREEN_BIRTHDAY_CLEAR");
		[clear addTarget:self action:@selector(clearBirthday) forControlEvents:UIControlEventTouchUpInside];
		[clear.widthAnchor constraintEqualToConstant:28].active = YES;

		UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[picker, clear]];
		stack.axis = UILayoutConstraintAxisHorizontal;
		stack.alignment = UIStackViewAlignmentCenter;
		stack.spacing = 4;
		self.birthdayPicker = picker;
		self.birthdayClear = clear;
		self.birthdayView = stack;
	}
	[self updateBirthdayAccessory];
	return self.birthdayView;
}

// Not set: the picker shows 1 January dimmed and the clear button is hidden.
- (void)updateBirthdayAccessory {
	NSDate *date = SSPBirthdayDate(SSPrefString(SS_KEY_BIRTHDAY));
	self.birthdayPicker.date = date ?: (SSPBirthdayDate(@"01-01") ?: [NSDate date]);
	self.birthdayPicker.alpha = date ? 1 : 0.4;
	self.birthdayClear.alpha = date ? 1 : 0;
	self.birthdayClear.enabled = date != nil;
	CGSize size = [self.birthdayView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
	self.birthdayView.frame = CGRectMake(0, 0, ceil(size.width), MAX(36.0, ceil(size.height)));
}

- (void)birthdayChanged:(UIDatePicker *)picker {
	SSSetPrefValue(SS_KEY_BIRTHDAY, [SSPPosixFormatter(@"MM-dd") stringFromDate:picker.date]);
	[self birthdayDidChange];
}

- (void)clearBirthday {
	SSSetPrefValue(SS_KEY_BIRTHDAY, @"");
	[self birthdayDidChange];
}

// The next occasion may now be the birthday: relabel the preview row too.
- (void)birthdayDidChange {
	[self updateBirthdayAccessory];
	for (PSSpecifier *spec in _specifiers) {
		if ([spec.identifier isEqualToString:@"occasionPreview"]) spec.name = [self occasionPreviewTitle];
	}
	[self redecorateVisibleCells];
}

// Plays the festive screen of the next special day in the preview card (scrolled into view).
- (void)previewOccasion {
	[self.table setContentOffset:CGPointMake(0, -self.table.adjustedContentInset.top) animated:YES];
	[self showPreviewStyle:SS_STYLE_FESTIVE occasion:SSPNextOccasion(SSPrefString(SS_KEY_BIRTHDAY))];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	// Videos added before frame extraction existed (or copied in by hand) still need converting.
	NSMutableArray *missing = [NSMutableArray array];
	for (NSString *file in [self videoFiles]) {
		if (![self hasFramesForVideo:file]) [missing addObject:file];
	}
	[self extractFramesForVideos:missing completion:nil];
}

- (NSArray<NSString *> *)videoFiles {
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:SS_VIDEOS_DIR withIntermediateDirectories:YES attributes:nil error:nil];
	NSMutableArray *files = [NSMutableArray array];
	for (NSString *file in [fm contentsOfDirectoryAtPath:SS_VIDEOS_DIR error:nil]) {
		if (![file hasPrefix:@"."]) [files addObject:file];
	}
	return [files sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

// The "current video" list shows the files in the videos folder (row id = videoName).
- (void)refreshVideoList {
	PSSpecifier *spec = nil;
	for (PSSpecifier *s in _specifiers) {
		if ([s.identifier isEqualToString:@"videoName"]) { spec = s; break; }
	}
	if (!spec) return;

	NSArray *files = [self videoFiles];
	if (files.count) {
		NSMutableArray *titles = [NSMutableArray array];
		for (NSString *file in files) [titles addObject:[file stringByDeletingPathExtension]];
		[spec setValues:files titles:titles];
	} else {
		[spec setValues:@[@""] titles:@[L(@"STARTUPSCREEN_NO_VIDEO")]];
	}
}

#pragma mark - Pref helpers

- (NSString *)selectedVideo {
	NSString *name = (__bridge_transfer NSString *)CFPreferencesCopyAppValue((__bridge CFStringRef)SS_KEY_VIDEO_NAME, kPrefsDomain);
	NSArray *files = [self videoFiles];
	if (name.length && [files containsObject:name]) return name;
	return files.firstObject;
}

- (void)setSelectedVideo:(NSString *)name {
	CFPreferencesSetAppValue((__bridge CFStringRef)SS_KEY_VIDEO_NAME, (__bridge CFStringRef)name, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self reloadSpecifiers];
}

#pragma mark - Frames

- (BOOL)hasFramesForVideo:(NSString *)name {
	NSString *path = [SS_FRAMES_DIR(name) stringByAppendingPathComponent:@"info.plist"];
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:path];
	return [info[@"version"] integerValue] >= kFramesVersion;
}

// Exports the soundtrack to audio.m4a for SpringBoard to play. Returns NO only on a real failure;
// a video without audio is fine.
- (BOOL)extractAudioFromAsset:(AVAsset *)asset seconds:(double)seconds toDir:(NSString *)dir {
	if (![asset tracksWithMediaType:AVMediaTypeAudio].count) return YES;
	AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
	if (!export) return NO;
	export.outputURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"audio.m4a"]];
	export.outputFileType = AVFileTypeAppleM4A;
	export.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(seconds, 600));
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	[export exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
	return export.status == AVAssetExportSessionStatusCompleted;
}

- (void)extractFramesForVideos:(NSArray<NSString *> *)names completion:(void (^)(void))completion {
	if (!names.count || self.extracting) {
		if (completion) completion();
		return;
	}
	self.extracting = YES;

	UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"OmniCar"
	                                                                  message:[L(@"STARTUPSCREEN_PREPARING") stringByAppendingString:@"…"]
	                                                           preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:progress animated:YES completion:nil];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSMutableArray *failed = [NSMutableArray array];
		[names enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
			NSString *label = names.count > 1 ? [NSString stringWithFormat:@" (%lu/%lu)", (unsigned long)idx + 1, (unsigned long)names.count] : @"";
			NSError *error = nil;
			BOOL ok = [self extractFramesForVideo:name error:&error progress:^(double fraction) {
				dispatch_async(dispatch_get_main_queue(), ^{
					progress.message = [NSString stringWithFormat:@"%@%@… %d%%", L(@"STARTUPSCREEN_PREPARING"), label, (int)(fraction * 100)];
				});
			}];
			if (!ok) [failed addObject:[NSString stringWithFormat:@"%@: %@", name, error.localizedDescription ?: @"?"]];
		}];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.extracting = NO;
			[progress dismissViewControllerAnimated:YES completion:^{
				if (failed.count) [self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_PROCESS_FAILED"), [failed componentsJoinedByString:@"\n"]]];
				if (completion) completion();
			}];
		});
	});
}

static CGImagePropertyOrientation SSOrientationForTransform(CGAffineTransform t) {
	if (t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0) return kCGImagePropertyOrientationRight;
	if (t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0) return kCGImagePropertyOrientationLeft;
	if (t.a == -1 && t.d == -1) return kCGImagePropertyOrientationDown;
	return kCGImagePropertyOrientationUp;
}

// Decodes the video sequentially and writes one JPEG per 1/kFrameRate seconds, plus info.plist.
- (BOOL)extractFramesForVideo:(NSString *)name error:(NSError **)error progress:(void (^)(double fraction))progress {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dir = SS_FRAMES_DIR(name);
	[fm removeItemAtPath:dir error:nil];
	if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:error]) return NO;

	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name]] options:nil];
	AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
	AVAssetReader *reader = track ? [AVAssetReader assetReaderWithAsset:asset error:error] : nil;
	if (!reader) {
		[fm removeItemAtPath:dir error:nil];
		return NO;
	}

	NSDictionary *settings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
	AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
	output.alwaysCopiesSampleData = NO;
	[reader addOutput:output];
	double seconds = MIN(CMTimeGetSeconds(asset.duration), kMaxFrameSeconds);
	reader.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(seconds, 600));
	if (![reader startReading]) {
		if (error) *error = reader.error;
		[fm removeItemAtPath:dir error:nil];
		return NO;
	}

	CIContext *context = [CIContext contextWithOptions:nil];
	CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGImagePropertyOrientation orientation = SSOrientationForTransform(track.preferredTransform);
	NSDictionary *jpegOptions = @{(id)kCGImageDestinationLossyCompressionQuality: @0.9};
	NSUInteger count = 0;
	double nextTime = 0;

	CMSampleBufferRef sample;
	while ((sample = [output copyNextSampleBuffer])) {
		@autoreleasepool {
			double time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
			CVImageBufferRef pixels = CMSampleBufferGetImageBuffer(sample);
			// Keep only the frames that land on our output frame rate.
			if (pixels && time + 0.001 >= nextTime) {
				CIImage *image = [[CIImage imageWithCVPixelBuffer:pixels] imageByApplyingCGOrientation:orientation];
				CGFloat scale = MIN(1.0, kMaxFrameSide / MAX(image.extent.size.width, image.extent.size.height));
				image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
				NSData *jpeg = [context JPEGRepresentationOfImage:image colorSpace:sRGB options:jpegOptions];
				NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%05lu.jpg", (unsigned long)count]];
				if ([jpeg writeToFile:path atomically:NO]) count++;
				nextTime += 1.0 / kFrameRate;
				if (seconds > 0) progress(MIN(1.0, time / seconds));
			}
			CFRelease(sample);
		}
	}
	CGColorSpaceRelease(sRGB);

	if (reader.status == AVAssetReaderStatusFailed || !count) {
		if (error) *error = reader.error;
		[fm removeItemAtPath:dir error:nil];
		return NO;
	}
	// info.plist is written last: its presence marks the frames as complete.
	if (![self extractAudioFromAsset:asset seconds:seconds toDir:dir]) {
		// Keep the frames; the splash just plays silently.
		NSLog(@"[OmniCar/StartupScreen] audio export failed for %@", name);
	}
	NSDictionary *info = @{@"fps": @(kFrameRate), @"count": @(count), @"version": @(kFramesVersion)};
	return [info writeToURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"info.plist"]] error:error];
}

#pragma mark - Actions

- (void)importFromPhotos {
	self.pickKind = SSPickVideo;
	UIImagePickerController *picker = [UIImagePickerController new];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.mediaTypes = @[UTTypeMovie.identifier];
	picker.videoExportPreset = AVAssetExportPresetPassthrough;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
	if (self.pickKind == SSPickLogo) {
		// The file URL keeps a PNG's transparency; the decoded image is the fallback.
		NSURL *imageURL = info[UIImagePickerControllerImageURL];
		UIImage *image = imageURL ? [UIImage imageWithContentsOfFile:imageURL.path] : nil;
		if (!image) image = info[UIImagePickerControllerOriginalImage];
		[picker dismissViewControllerAnimated:YES completion:^{ [self saveLogoImage:image]; }];
		return;
	}
	NSURL *url = info[UIImagePickerControllerMediaURL];
	[picker dismissViewControllerAnimated:YES completion:^{
		if (!url) return;
		NSDateFormatter *df = [NSDateFormatter new];
		df.dateFormat = @"yyyyMMdd-HHmmss";
		NSString *ext = url.pathExtension.length ? url.pathExtension : @"mov";
		NSString *name = [NSString stringWithFormat:@"Video %@.%@", [df stringFromDate:[NSDate date]], ext];
		[self copyVideoAtURL:url name:name];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)importFromFiles {
	self.pickKind = SSPickVideo;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeMovie] asCopy:YES];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *url = urls.firstObject;
	if (!url) return;
	switch (self.pickKind) {
		case SSPickLogo:  [self saveLogoImage:[UIImage imageWithContentsOfFile:url.path]]; break;
		case SSPickSound: [self copySoundAtURL:url]; break;
		case SSPickVideo: [self copyVideoAtURL:url name:url.lastPathComponent]; break;
	}
}

- (void)copyVideoAtURL:(NSURL *)source name:(NSString *)name {
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:SS_VIDEOS_DIR withIntermediateDirectories:YES attributes:nil error:nil];

	// Avoid overwriting an existing video with the same name.
	NSString *base = [name stringByDeletingPathExtension];
	NSString *ext = name.pathExtension;
	NSString *dest = [SS_VIDEOS_DIR stringByAppendingPathComponent:name];
	for (int i = 2; [fm fileExistsAtPath:dest]; i++) {
		dest = [SS_VIDEOS_DIR stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d.%@", base, i, ext]];
	}

	NSError *error = nil;
	if (![fm copyItemAtPath:source.path toPath:dest error:&error]) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SAVE_FAILED"), error.localizedDescription]];
		return;
	}
	[fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:dest error:nil];
	[self setSelectedVideo:dest.lastPathComponent];
	__weak typeof(self) weakSelf = self;
	[self extractFramesForVideos:@[dest.lastPathComponent] completion:^{ [weakSelf updatePreview]; }];
}

// "Add video": one row, then Photos or Files.
- (void)addVideo {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_FROM_PHOTOS") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf importFromPhotos]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_FROM_FILES") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf importFromFiles]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.view;   // iPad
	sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)previewVideo {
	NSString *name = [self selectedVideo];
	if (!name) { [self showMessage:L(@"STARTUPSCREEN_NO_VIDEO_PREVIEW")]; return; }

	AVPlayerViewController *vc = [AVPlayerViewController new];
	vc.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name]]];
	[self presentViewController:vc animated:YES completion:^{ [vc.player play]; }];
}

- (void)deleteVideo {
	NSString *name = [self selectedVideo];
	if (!name) { [self showMessage:L(@"STARTUPSCREEN_NO_VIDEO_DELETE")]; return; }

	NSString *message = [NSString stringWithFormat:L(@"STARTUPSCREEN_DELETE_CONFIRM"), [name stringByDeletingPathExtension]];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"STARTUPSCREEN_DELETE_TITLE") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_DELETE_ACTION") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[[NSFileManager defaultManager] removeItemAtPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name] error:nil];
		[[NSFileManager defaultManager] removeItemAtPath:SS_FRAMES_DIR(name) error:nil];
		[self setSelectedVideo:[self videoFiles].firstObject];
		[self updatePreview];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Logo

// "Choose logo": Photos or Files (a PNG with transparency looks best on the dark background).
- (void)chooseLogo {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_FROM_PHOTOS") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf logoFromPhotos]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_FROM_FILES") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf logoFromFiles]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.view;   // iPad
	sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)logoFromPhotos {
	self.pickKind = SSPickLogo;
	UIImagePickerController *picker = [UIImagePickerController new];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.mediaTypes = @[UTTypeImage.identifier];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)logoFromFiles {
	self.pickKind = SSPickLogo;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

// Redraws the image into a transparent sRGB PNG of at most kMaxLogoSide px (orientation applied) at SS_LOGO_PATH.
- (void)saveLogoImage:(UIImage *)image {
	if (!image || image.size.width <= 0 || image.size.height <= 0) {
		[self showMessage:L(@"STARTUPSCREEN_LOGO_FAILED")];
		return;
	}
	CGFloat pixelWidth = image.size.width * image.scale, pixelHeight = image.size.height * image.scale;
	CGFloat scale = MIN(1.0, kMaxLogoSide / MAX(pixelWidth, pixelHeight));
	CGSize size = CGSizeMake(MAX(1.0, round(pixelWidth * scale)), MAX(1.0, round(pixelHeight * scale)));
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.scale = 1;
	format.opaque = NO;
	format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
	UIImage *output = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[image drawInRect:CGRectMake(0, 0, size.width, size.height)];
	}];
	NSData *png = UIImagePNGRepresentation(output);

	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:[SS_LOGO_PATH stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
	NSError *error = nil;
	if (!png || ![png writeToFile:SS_LOGO_PATH options:NSDataWritingAtomic error:&error]) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SAVE_FAILED"), error.localizedDescription ?: @"PNG"]];
		return;
	}
	[fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:SS_LOGO_PATH error:nil];
	[self updatePreview];
}

- (void)deleteLogo {
	if (![[NSFileManager defaultManager] fileExistsAtPath:SS_LOGO_PATH]) { [self showMessage:L(@"STARTUPSCREEN_LOGO_NONE")]; return; }
	[[NSFileManager defaultManager] removeItemAtPath:SS_LOGO_PATH error:nil];
	[self updatePreview];
}

#pragma mark - Startup sound

- (void)chooseSound {
	self.pickKind = SSPickSound;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

// Keeps one sound: the old one is removed, the new one copied into SS_SOUNDS_DIR under its own name.
- (void)copySoundAtURL:(NSURL *)source {
	NSError *error = nil;
	AVAudioPlayer *check = [[AVAudioPlayer alloc] initWithContentsOfURL:source error:&error];
	if (!check) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SOUND_FAILED"), error.localizedDescription ?: source.lastPathComponent]];
		return;
	}
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:SS_SOUNDS_DIR error:nil];
	[fm createDirectoryAtPath:SS_SOUNDS_DIR withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *name = source.lastPathComponent;
	NSString *dest = [SS_SOUNDS_DIR stringByAppendingPathComponent:name];
	if (![fm copyItemAtPath:source.path toPath:dest error:&error]) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SAVE_FAILED"), error.localizedDescription]];
		return;
	}
	[fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:dest error:nil];
	SSSetPrefValue(SS_KEY_SOUND_FILE, name);
	_specifiers = nil;
	[self reloadSpecifiers];
}

// Plays the sound here at the chosen volume (the car plays it through SpringBoard the same way).
- (void)previewSound {
	NSString *name = [self currentSound];
	if (!name) { [self showMessage:L(@"STARTUPSCREEN_SOUND_NONE")]; return; }
	[self.soundPlayer stop];
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];
	NSError *error = nil;
	self.soundPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[SS_SOUNDS_DIR stringByAppendingPathComponent:name]] error:&error];
	if (!self.soundPlayer) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SOUND_FAILED"), error.localizedDescription ?: name]];
		return;
	}
	id volume = SSPrefValue(SS_KEY_SOUND_VOLUME);
	self.soundPlayer.volume = (float)(MAX(0.0, MIN(100.0, volume ? [volume doubleValue] : 100.0)) / 100.0);
	[self.soundPlayer play];
}

- (void)deleteSound {
	if (![self currentSound]) { [self showMessage:L(@"STARTUPSCREEN_SOUND_NONE")]; return; }
	[self.soundPlayer stop];
	self.soundPlayer = nil;
	[[NSFileManager defaultManager] removeItemAtPath:SS_SOUNDS_DIR error:nil];
	SSSetPrefValue(SS_KEY_SOUND_FILE, nil);
	_specifiers = nil;
	[self reloadSpecifiers];
}

@end
