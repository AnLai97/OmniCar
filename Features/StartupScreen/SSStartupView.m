// Startup Screen renderer (see SSStartupView.h). Built into the tweak and, through
// Prefs/SSStartupViewPrefs.m, into the settings bundle: keep it to UIKit / QuartzCore / Foundation and
// Core/OMCCommon.m (OMCTr, OMCCurrentLanguage), which both binaries have.
//
// Look (DESIGN.md): large rounded white text with a soft shadow, readable at a glance; time-of-day
// gradients behind the greeting and the weather; the weather details sit on a thin dark glass card.

#import "SSStartupView.h"
#import "StartupScreen.h"
#import "OmniCar.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Weather data

static NSNumber *SSNumber(id value) {
	return [value isKindOfClass:[NSNumber class]] ? (NSNumber *)value : nil;
}

static NSNumber *SSFirstNumber(id list) {
	if (![list isKindOfClass:[NSArray class]] || ![(NSArray *)list count]) return nil;
	return SSNumber([(NSArray *)list firstObject]);
}

NSDictionary *SSWeatherParse(id json) {
	if (![json isKindOfClass:[NSDictionary class]]) return nil;
	NSDictionary *root = (NSDictionary *)json;
	NSDictionary *current = root[@"current"];
	NSDictionary *daily = root[@"daily"];
	if (![current isKindOfClass:[NSDictionary class]]) return nil;
	NSNumber *temp = SSNumber(current[@"temperature_2m"]);
	if (!temp) return nil;

	NSMutableDictionary *weather = [NSMutableDictionary dictionary];
	weather[SS_WX_TEMP] = temp;
	weather[SS_WX_CODE] = SSNumber(current[@"weather_code"]) ?: @0;
	weather[SS_WX_DAY]  = SSNumber(current[@"is_day"]) ?: @1;
	if ([daily isKindOfClass:[NSDictionary class]]) {
		NSNumber *high = SSFirstNumber(daily[@"temperature_2m_max"]);
		NSNumber *low  = SSFirstNumber(daily[@"temperature_2m_min"]);
		NSNumber *rain = SSFirstNumber(daily[@"precipitation_probability_max"]);
		if (high) weather[SS_WX_HIGH] = high;
		if (low)  weather[SS_WX_LOW]  = low;
		if (rain) weather[SS_WX_RAIN] = rain;
	}
	weather[SS_WX_DATE] = [NSDate date];
	return weather;
}

static NSString *SSWeatherTempCachePath(void) {
	return [NSTemporaryDirectory() stringByAppendingPathComponent:@"OmniCarStartupWeather.plist"];
}

NSDictionary *SSWeatherLoadCache(NSTimeInterval maxAge) {
	NSDictionary *best = nil;
	NSDate *bestDate = nil;
	for (NSString *path in @[SS_WEATHER_CACHE, SSWeatherTempCachePath()]) {
		NSDictionary *weather = [NSDictionary dictionaryWithContentsOfFile:path];
		NSDate *date = weather[SS_WX_DATE];
		if (![date isKindOfClass:[NSDate class]] || !SSNumber(weather[SS_WX_TEMP])) continue;
		if (maxAge > 0 && -date.timeIntervalSinceNow > maxAge) continue;
		if (!bestDate || [date compare:bestDate] == NSOrderedDescending) {
			best = weather;
			bestDate = date;
		}
	}
	return best;
}

void SSWeatherSaveCache(NSDictionary *weather) {
	if (!weather) return;
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:[SS_WEATHER_CACHE stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
	NSError *error = nil;
	if ([weather writeToURL:[NSURL fileURLWithPath:SS_WEATHER_CACHE] error:&error]) {
		[fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:SS_WEATHER_CACHE error:nil];
		return;
	}
	// CarPlay.app may not be allowed to write the shared folder: keep a private copy instead.
	[weather writeToURL:[NSURL fileURLWithPath:SSWeatherTempCachePath()] error:nil];
}

NSInteger SSPeriodForDate(NSDate *date) {
	NSInteger hour = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:date ?: [NSDate date]];
	if (hour >= 5 && hour < 11) return 0;
	if (hour >= 11 && hour < 17) return 1;
	if (hour >= 17 && hour < 21) return 2;
	return 3;
}

#pragma mark - Text

static NSString *SSGreetingPhrase(NSInteger period) {
	switch (period) {
		case 0:  return OMCTr(@"Chào buổi sáng", @"Good morning");
		case 1:  return OMCTr(@"Chào buổi chiều", @"Good afternoon");
		case 2:  return OMCTr(@"Chào buổi tối", @"Good evening");
		default: return OMCTr(@"Khuya rồi", @"Late night");
	}
}

static NSString *SSGreetingTitle(NSString *name, NSInteger period) {
	NSString *phrase = SSGreetingPhrase(period);
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return trimmed.length ? [NSString stringWithFormat:@"%@, %@", phrase, trimmed] : phrase;
}

static NSLocale *SSLanguageLocale(void) {
	return [NSLocale localeWithLocaleIdentifier:OMCCurrentLanguage()];
}

static NSString *SSDateText(NSDate *date) {
	NSDateFormatter *df = [NSDateFormatter new];
	df.locale = SSLanguageLocale();
	[df setLocalizedDateFormatFromTemplate:@"EEEEdMMMM"];
	return [df stringFromDate:date];
}

// Time in the phone's own 12 / 24 hour setting.
static NSString *SSTimeText(NSDate *date) {
	return [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
}

// "28°" in the region's unit (Celsius, or Fahrenheit in the US).
static NSString *SSTemperatureText(NSNumber *celsius) {
	if (!celsius) return @"--";
	NSMeasurementFormatter *mf = [NSMeasurementFormatter new];
	mf.unitStyle = NSFormattingUnitStyleShort;
	NSNumberFormatter *nf = [NSNumberFormatter new];
	nf.maximumFractionDigits = 0;
	mf.numberFormatter = nf;
	NSMeasurement *m = [[NSMeasurement alloc] initWithDoubleValue:celsius.doubleValue unit:[NSUnitTemperature celsius]];
	return [mf stringFromMeasurement:m];
}

// WMO weather code -> SF Symbol + short description.
static void SSWeatherLook(NSInteger code, BOOL day, NSString **symbol, NSString **text) {
	NSString *s, *t;
	if (code == 0) {
		s = day ? @"sun.max.fill" : @"moon.stars.fill";
		t = OMCTr(@"Trời quang", @"Clear");
	} else if (code <= 2) {
		s = day ? @"cloud.sun.fill" : @"cloud.moon.fill";
		t = OMCTr(@"Ít mây", @"Partly cloudy");
	} else if (code == 3) {
		s = @"cloud.fill";
		t = OMCTr(@"Nhiều mây", @"Cloudy");
	} else if (code == 45 || code == 48) {
		s = @"cloud.fog.fill";
		t = OMCTr(@"Sương mù", @"Fog");
	} else if (code >= 51 && code <= 57) {
		s = @"cloud.drizzle.fill";
		t = OMCTr(@"Mưa phùn", @"Drizzle");
	} else if (code == 65 || code == 67 || code == 82) {
		s = @"cloud.heavyrain.fill";
		t = OMCTr(@"Mưa to", @"Heavy rain");
	} else if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
		s = day ? @"cloud.sun.rain.fill" : @"cloud.rain.fill";
		t = OMCTr(@"Có mưa", @"Rain");
	} else if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
		s = @"cloud.snow.fill";
		t = OMCTr(@"Có tuyết", @"Snow");
	} else if (code >= 95) {
		s = @"cloud.bolt.rain.fill";
		t = OMCTr(@"Dông", @"Thunderstorm");
	} else {
		s = @"cloud.fill";
		t = OMCTr(@"Nhiều mây", @"Cloudy");
	}
	if (symbol) *symbol = s;
	if (text) *text = t;
}

#pragma mark - Look

static UIColor *SSRGB(uint32_t rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

// Background gradient (top left -> bottom right) per time of day.
static NSArray *SSPeriodColors(NSInteger period) {
	switch (period) {
		case 0:  return @[(id)SSRGB(0xFFB36B).CGColor, (id)SSRGB(0xF2665E).CGColor];   // sunrise
		case 1:  return @[(id)SSRGB(0x27B4A4).CGColor, (id)SSRGB(0x1F5F8E).CGColor];   // daylight
		case 2:  return @[(id)SSRGB(0xF08A66).CGColor, (id)SSRGB(0x5C3A92).CGColor];   // dusk
		default: return @[(id)SSRGB(0x1D2547).CGColor, (id)SSRGB(0x04050B).CGColor];   // night
	}
}

static UIFont *SSFont(CGFloat size, UIFontWeight weight) {
	UIFont *font = [UIFont systemFontOfSize:size weight:weight];
	UIFontDescriptor *rounded = [font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
	return rounded ? [UIFont fontWithDescriptor:rounded size:size] : font;
}

static UILabel *SSLabel(NSString *text) {
	UILabel *label = [UILabel new];
	label.text = text;
	label.textColor = [UIColor whiteColor];
	label.textAlignment = NSTextAlignmentCenter;
	label.numberOfLines = 1;
	label.adjustsFontSizeToFitWidth = YES;
	label.minimumScaleFactor = 0.45;
	label.layer.shadowColor = [UIColor blackColor].CGColor;
	label.layer.shadowOpacity = 0.22;
	[label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
	return label;
}

#pragma mark - View

@implementation SSStartupView {
	CGFloat _unit;
	UIStackView *_stack;          // greeting / weather content (centered)
	UIImageView *_logoView;       // logo style
	UIImageView *_posterView;     // video style
	UILabel *_timeLabel, *_titleLabel, *_dateLabel;
	UILabel *_tempLabel, *_condLabel, *_rangeLabel, *_rainLabel, *_updatedLabel;
	UIImageView *_iconView;
	UIStackView *_row, *_cardStack;
	UIVisualEffectView *_card;
	NSLayoutConstraint *_iconW, *_iconH, *_stackMaxWidth;
	NSArray<NSLayoutConstraint *> *_cardInsets;   // leading, trailing, top, bottom
}

+ (Class)layerClass {
	return [CAGradientLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.clipsToBounds = YES;
		self.backgroundColor = [UIColor blackColor];
	}
	return self;
}

- (void)clearContent {
	for (UIView *view in [self.subviews copy]) [view removeFromSuperview];
	_stack = _row = _cardStack = nil;
	_logoView = _posterView = _iconView = nil;
	_timeLabel = _titleLabel = _dateLabel = nil;
	_tempLabel = _condLabel = _rangeLabel = _rainLabel = _updatedLabel = nil;
	_card = nil;
	_iconW = _iconH = _stackMaxWidth = nil;
	_cardInsets = nil;
	_unit = 0;
}

- (void)reload {
	[self clearContent];
	NSDate *date = self.date ?: [NSDate date];
	NSInteger period = SSPeriodForDate(date);
	CAGradientLayer *bg = (CAGradientLayer *)self.layer;
	bg.type = kCAGradientLayerAxial;
	bg.startPoint = CGPointMake(0, 0);
	bg.endPoint = CGPointMake(1, 1);

	NSInteger style = self.style;
	if (style == SS_STYLE_WEATHER && !self.weather) style = SS_STYLE_GREETING;

	if (style == SS_STYLE_VIDEO) {
		bg.colors = @[(id)[UIColor blackColor].CGColor, (id)[UIColor blackColor].CGColor];
		_posterView = [[UIImageView alloc] initWithFrame:self.bounds];
		_posterView.clipsToBounds = YES;
		if (self.image) {
			_posterView.image = self.image;
			_posterView.contentMode = self.imageFits ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
		} else {
			_posterView.image = [UIImage systemImageNamed:@"play.rectangle.fill"];
			_posterView.tintColor = [UIColor colorWithWhite:1 alpha:0.35];
			_posterView.contentMode = UIViewContentModeCenter;
		}
		[self addSubview:_posterView];
	} else if (style == SS_STYLE_LOGO) {
		bg.type = kCAGradientLayerRadial;
		bg.startPoint = CGPointMake(0.5, 0.5);
		bg.endPoint = CGPointMake(1.0, 1.0);
		bg.colors = @[(id)SSRGB(0x1E2646).CGColor, (id)SSRGB(0x05060B).CGColor];
		_logoView = [UIImageView new];
		_logoView.contentMode = UIViewContentModeScaleAspectFit;
		_logoView.image = self.image ?: [UIImage systemImageNamed:@"car.fill"];
		_logoView.tintColor = [UIColor whiteColor];
		[self addSubview:_logoView];
	} else {
		bg.colors = SSPeriodColors(period);
		if (style == SS_STYLE_WEATHER) [self buildWeatherWithPeriod:period];
		else [self buildGreetingWithDate:date period:period];
		_stack.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_stack];
		_stackMaxWidth = [_stack.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor constant:-16];
		[NSLayoutConstraint activateConstraints:@[
			[_stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[_stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
			_stackMaxWidth,
		]];
	}
	[self setNeedsLayout];
}

- (void)buildGreetingWithDate:(NSDate *)date period:(NSInteger)period {
	_timeLabel  = SSLabel(SSTimeText(date));
	_titleLabel = SSLabel(SSGreetingTitle(self.name, period));
	_dateLabel  = SSLabel(SSDateText(date));
	_dateLabel.alpha = 0.85;
	_stack = [[UIStackView alloc] initWithArrangedSubviews:@[_timeLabel, _titleLabel, _dateLabel]];
	_stack.axis = UILayoutConstraintAxisVertical;
	_stack.alignment = UIStackViewAlignmentCenter;
}

- (void)buildWeatherWithPeriod:(NSInteger)period {
	NSDictionary *w = self.weather;
	NSString *symbol = nil, *condition = nil;
	SSWeatherLook([w[SS_WX_CODE] integerValue], [w[SS_WX_DAY] boolValue], &symbol, &condition);

	_titleLabel = SSLabel(SSGreetingTitle(self.name, period));
	_titleLabel.alpha = 0.92;

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:160 weight:UIImageSymbolWeightRegular];
	config = [config configurationByApplyingConfiguration:[UIImageSymbolConfiguration configurationPreferringMulticolor]];
	_iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:config]
		?: [UIImage systemImageNamed:@"cloud.fill" withConfiguration:config]];
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	_iconView.tintColor = [UIColor whiteColor];
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconW = [_iconView.widthAnchor constraintEqualToConstant:30];
	_iconH = [_iconView.heightAnchor constraintEqualToConstant:30];
	[NSLayoutConstraint activateConstraints:@[_iconW, _iconH]];

	_tempLabel = SSLabel(SSTemperatureText(w[SS_WX_TEMP]));
	[_tempLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	// Details on a thin dark glass card: condition, today's high / low, chance of rain.
	_condLabel = SSLabel(condition);
	NSMutableArray *range = [NSMutableArray array];
	if (w[SS_WX_HIGH]) [range addObject:[@"↑ " stringByAppendingString:SSTemperatureText(w[SS_WX_HIGH])]];
	if (w[SS_WX_LOW])  [range addObject:[@"↓ " stringByAppendingString:SSTemperatureText(w[SS_WX_LOW])]];
	_rangeLabel = SSLabel([range componentsJoinedByString:@"   "]);
	_rangeLabel.hidden = !range.count;
	_rainLabel = SSLabel(w[SS_WX_RAIN] ? [NSString stringWithFormat:@"%@ %ld%%", OMCTr(@"Khả năng mưa", @"Chance of rain"), (long)[w[SS_WX_RAIN] integerValue]] : nil);
	_rainLabel.hidden = !w[SS_WX_RAIN];
	_rainLabel.alpha = 0.9;
	for (UILabel *label in @[_condLabel, _rangeLabel, _rainLabel]) label.textAlignment = NSTextAlignmentNatural;

	_cardStack = [[UIStackView alloc] initWithArrangedSubviews:@[_condLabel, _rangeLabel, _rainLabel]];
	_cardStack.axis = UILayoutConstraintAxisVertical;
	_cardStack.alignment = UIStackViewAlignmentLeading;
	_cardStack.translatesAutoresizingMaskIntoConstraints = NO;

	_card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
	_card.clipsToBounds = YES;
	_card.layer.cornerCurve = kCACornerCurveContinuous;
	_card.layer.borderWidth = 0.5;
	_card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
	_card.contentView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
	[_card.contentView addSubview:_cardStack];
	_cardInsets = @[
		[_cardStack.leadingAnchor constraintEqualToAnchor:_card.contentView.leadingAnchor constant:12],
		[_card.contentView.trailingAnchor constraintEqualToAnchor:_cardStack.trailingAnchor constant:12],
		[_cardStack.topAnchor constraintEqualToAnchor:_card.contentView.topAnchor constant:8],
		[_card.contentView.bottomAnchor constraintEqualToAnchor:_cardStack.bottomAnchor constant:8],
	];
	[NSLayoutConstraint activateConstraints:_cardInsets];

	_row = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _tempLabel, _card]];
	_row.axis = UILayoutConstraintAxisHorizontal;
	_row.alignment = UIStackViewAlignmentCenter;

	// "Updated 07:42" (with the day when it is not today), so offline values are never mistaken for live ones.
	NSDate *fetched = w[SS_WX_DATE];
	NSString *when = nil;
	if ([fetched isKindOfClass:[NSDate class]]) {
		when = [[NSCalendar currentCalendar] isDateInToday:fetched] ? SSTimeText(fetched)
			: [NSDateFormatter localizedStringFromDate:fetched dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
	}
	_updatedLabel = SSLabel(when ? [NSString stringWithFormat:OMCTr(@"Cập nhật lúc %@", @"Updated %@"), when] : nil);
	_updatedLabel.alpha = 0.65;
	_updatedLabel.hidden = !when;

	_stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _row, _updatedLabel]];
	_stack.axis = UILayoutConstraintAxisVertical;
	_stack.alignment = UIStackViewAlignmentCenter;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGSize size = self.bounds.size;
	CGFloat u = MIN(size.height / 100.0, size.width / 260.0);
	if (u <= 0) return;

	_posterView.frame = self.bounds;
	if (_posterView.contentMode == UIViewContentModeCenter) {
		_posterView.image = [_posterView.image imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28 * u]];
	}
	if (_logoView) {
		CGFloat side = MIN(size.width * 0.5, size.height * 0.62);
		_logoView.bounds = CGRectMake(0, 0, side, side);
		_logoView.center = CGPointMake(size.width / 2, size.height / 2);
		_logoView.layer.shadowRadius = 7 * u;
	}
	if (fabs(u - _unit) < 0.01) return;
	_unit = u;
	[self applyUnit:u];
}

// Font sizes, spacing and shadows in units of the view size.
- (void)applyUnit:(CGFloat)u {
	UILabel *labels[] = {_timeLabel, _titleLabel, _dateLabel, _tempLabel, _condLabel, _rangeLabel, _rainLabel, _updatedLabel};
	for (size_t i = 0; i < sizeof(labels) / sizeof(labels[0]); i++) {
		UILabel *label = labels[i];
		if (!label) continue;
		label.layer.shadowRadius = 1.5 * u;
		label.layer.shadowOffset = CGSizeMake(0, 0.5 * u);
	}
	_stackMaxWidth.constant = -12 * u;

	if (_timeLabel) {
		// Greeting: big clock, greeting, date.
		_timeLabel.font  = SSFont(30 * u, UIFontWeightLight);
		_titleLabel.font = SSFont(10 * u, UIFontWeightSemibold);
		_dateLabel.font  = SSFont(6 * u, UIFontWeightMedium);
		_stack.spacing = 1.5 * u;
	} else if (_tempLabel) {
		// Weather: greeting on top, icon + temperature + glass card, "updated" below.
		_titleLabel.font   = SSFont(7 * u, UIFontWeightSemibold);
		_tempLabel.font    = SSFont(30 * u, UIFontWeightMedium);
		_condLabel.font    = SSFont(7.5 * u, UIFontWeightSemibold);
		_rangeLabel.font   = SSFont(6 * u, UIFontWeightMedium);
		_rainLabel.font    = SSFont(5.5 * u, UIFontWeightMedium);
		_updatedLabel.font = SSFont(4.2 * u, UIFontWeightRegular);
		_iconW.constant = _iconH.constant = 32 * u;
		_row.spacing = 4 * u;
		[_row setCustomSpacing:6 * u afterView:_tempLabel];
		_cardStack.spacing = 1.2 * u;
		_card.layer.cornerRadius = 5.5 * u;
		_cardInsets[0].constant = _cardInsets[1].constant = 5 * u;
		_cardInsets[2].constant = _cardInsets[3].constant = 3.5 * u;
		_stack.spacing = 3 * u;
	}
}

- (void)playIntro {
	[self layoutIfNeeded];
	CGFloat u = MAX(_unit, 1);

	if (_logoView) {
		UIImageView *logo = _logoView;
		[logo.layer removeAllAnimations];
		logo.layer.shadowOpacity = 0;
		logo.alpha = 0;
		if (self.logoEffect == SS_EFFECT_ZOOM) {
			logo.transform = CGAffineTransformMakeScale(0.5, 0.5);
			[UIView animateWithDuration:1.1 delay:0.1 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{
				logo.alpha = 1;
				logo.transform = CGAffineTransformIdentity;
			} completion:nil];
		} else if (self.logoEffect == SS_EFFECT_GLOW) {
			// White halo that keeps breathing (DESIGN.md: "active" = bright white with a white glow).
			logo.transform = CGAffineTransformIdentity;
			logo.layer.shadowColor = [UIColor whiteColor].CGColor;
			logo.layer.shadowOffset = CGSizeZero;
			logo.layer.shadowRadius = 7 * u;
			logo.layer.shadowOpacity = 0.6;
			CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
			pulse.fromValue = @0.0;
			pulse.toValue = @0.95;
			pulse.duration = 1.2;
			pulse.autoreverses = YES;
			pulse.repeatCount = HUGE_VALF;
			pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
			[logo.layer addAnimation:pulse forKey:@"ssGlow"];
			[UIView animateWithDuration:0.9 animations:^{ logo.alpha = 1; }];
		} else {
			logo.transform = CGAffineTransformMakeScale(0.96, 0.96);
			[UIView animateWithDuration:1.2 delay:0.05 options:UIViewAnimationOptionCurveEaseInOut animations:^{
				logo.alpha = 1;
				logo.transform = CGAffineTransformIdentity;
			} completion:nil];
		}
		return;
	}

	// Greeting / weather / poster: fade in while rising a little (spring, damping 0.86).
	UIView *content = _stack ?: _posterView;
	if (!content) return;
	[content.layer removeAllAnimations];
	content.alpha = 0;
	content.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, 6 * u), 0.92, 0.92);
	[UIView animateWithDuration:0.9 delay:0.05 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:0 animations:^{
		content.alpha = 1;
		content.transform = CGAffineTransformIdentity;
	} completion:nil];
}

@end
