// Startup Screen renderer (see SSStartupView.h). Built into the tweak and, through
// Prefs/SSStartupViewPrefs.m, into the settings bundle: keep it to UIKit / QuartzCore / Foundation and
// Core/OMCCommon.m (OMCTr, OMCCurrentLanguage), which both binaries have.
//
// Look (DESIGN.md): large rounded white text with a soft shadow, readable at a glance; time-of-day
// gradients behind the greeting and the weather; the weather details sit on a thin dark glass card.
//
// Animated styles (Weather sky, Engine, Welcome, Particles, HUD, Briefing, Festive) follow the approved mockup
// tools/preview/startup.html: each scene is a function of the time t in seconds since -playIntro
// (-ss_applyTime:), laid out on the mockup's 1600 x 600 canvas scaled to the view (letterboxed, one canvas pixel
// = _k points, _k = unit / 6). Layers are built once per size; a display link (only while playing and on screen)
// moves them. Particles and fireworks are drawn into one low-resolution canvas view; everything else is layers.

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

static NSString *SSTrimmed(NSString *text) {
	return [text isKindOfClass:[NSString class]] ? [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
}

static NSString *SSGreetingTitle(NSString *name, NSInteger period) {
	NSString *phrase = SSGreetingPhrase(period);
	NSString *trimmed = SSTrimmed(name);
	return trimmed.length ? [NSString stringWithFormat:@"%@, %@", phrase, trimmed] : phrase;
}

// "<withName>" formatted with the name, or "<without>" when there is no name.
static NSString *SSWithName(NSString *withName, NSString *without, NSString *name) {
	NSString *trimmed = SSTrimmed(name);
	return trimmed.length ? [NSString stringWithFormat:withName, trimmed] : without;
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

// The animated sky behind the Weather style (and the Briefing weather card's emoji).
typedef NS_ENUM(NSInteger, SSSky) {
	SSSkyClearDay, SSSkyClearNight, SSSkyPartlyDay, SSSkyPartlyNight, SSSkyCloudy, SSSkyFog,
	SSSkyDrizzle, SSSkyRain, SSSkyThunder, SSSkySnow,
};

static SSSky SSSkyFor(NSInteger code, BOOL day) {
	if (code == 0) return day ? SSSkyClearDay : SSSkyClearNight;
	if (code <= 2) return day ? SSSkyPartlyDay : SSSkyPartlyNight;
	if (code == 45 || code == 48) return SSSkyFog;
	if (code >= 51 && code <= 57) return SSSkyDrizzle;
	if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return SSSkyRain;
	if ((code >= 71 && code <= 77) || code == 85 || code == 86) return SSSkySnow;
	if (code >= 95) return SSSkyThunder;
	return SSSkyCloudy;
}

static NSString *SSSkyEmoji(SSSky sky) {
	switch (sky) {
		case SSSkyClearDay:    return @"☀️";
		case SSSkyClearNight:  return @"🌙";
		case SSSkyPartlyDay:   return @"⛅";
		case SSSkyFog:         return @"🌫";
		case SSSkyDrizzle:     return @"🌦";
		case SSSkyRain:        return @"🌧";
		case SSSkyThunder:     return @"⛈";
		case SSSkySnow:        return @"🌨";
		default:               return @"☁️";
	}
}

#pragma mark - Look

static UIColor *SSRGB(uint32_t rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

static UIColor *SSRGBA(uint32_t rgb, CGFloat alpha) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:alpha];
}

static NSArray *SSPair(uint32_t top, uint32_t bottom) {
	return @[(id)SSRGB(top).CGColor, (id)SSRGB(bottom).CGColor];
}

// Background gradient (top left -> bottom right) per time of day.
static NSArray *SSPeriodColors(NSInteger period) {
	switch (period) {
		case 0:  return SSPair(0xFFB36B, 0xF2665E);   // sunrise
		case 1:  return SSPair(0x27B4A4, 0x1F5F8E);   // daylight
		case 2:  return SSPair(0xF08A66, 0x5C3A92);   // dusk
		default: return SSPair(0x1D2547, 0x04050B);   // night
	}
}

// Weather style background (top -> bottom), as in the mockup.
static NSArray *SSSkyColors(SSSky sky, BOOL day) {
	switch (sky) {
		case SSSkyClearDay: case SSSkyPartlyDay:     return SSPair(0x2A7FD8, 0x9FD3FF);
		case SSSkyClearNight: case SSSkyPartlyNight: return SSPair(0x02030A, 0x0B1230);
		case SSSkyFog:                               return SSPair(0x5F6670, 0x9AA1AA);
		case SSSkyDrizzle: case SSSkyRain: case SSSkyThunder: return SSPair(0x1C2633, 0x33404F);
		case SSSkySnow:   return day ? SSPair(0x5D6E86, 0xB4C2D3) : SSPair(0x141B2A, 0x38445A);
		default:          return day ? SSPair(0x4A5B70, 0x8D9BAD) : SSPair(0x10141F, 0x2A3243);
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

#pragma mark - Motion helpers (the mockup's clamp / span / ease / out)

static inline CGFloat SSClamp01(CGFloat x) {
	return x < 0 ? 0 : (x > 1 ? 1 : x);
}

static inline CGFloat SSSpan(CGFloat t, CGFloat a, CGFloat b) {
	return SSClamp01((t - a) / (b - a));
}

static inline CGFloat SSEase(CGFloat x) {
	x = SSClamp01(x);
	return x < 0.5 ? 4 * x * x * x : 1 - (CGFloat)pow(-2 * x + 2, 3) / 2;
}

static inline CGFloat SSOut(CGFloat x) {
	x = SSClamp01(x);
	return 1 - (CGFloat)pow(1 - x, 3);
}

// Positive modulo: a value moving forever, wrapped into 0..m.
static inline CGFloat SSWrap(CGFloat a, CGFloat m) {
	return m > 0 ? a - m * (CGFloat)floor(a / m) : a;
}

static inline CGFloat SSSpike(CGFloat t, CGFloat at, CGFloat width) {
	return SSClamp01(1 - (CGFloat)fabs(t - at) / width);
}

static CGFloat SSRand(CGFloat a, CGFloat b) {
	return a + (b - a) * (CGFloat)arc4random_uniform(1000001) / (CGFloat)1000000.0;
}

// HSL (hue in degrees, s / l 0-1) -> RGB 0-1, as CSS hsl().
static void SSHSL(CGFloat h, CGFloat s, CGFloat l, CGFloat rgb[3]) {
	CGFloat c = (1 - (CGFloat)fabs(2 * l - 1)) * s;
	CGFloat hp = SSWrap(h, 360) / 60;
	CGFloat x = c * (1 - (CGFloat)fabs(fmod(hp, 2.0) - 1));
	CGFloat r = 0, g = 0, b = 0;
	if (hp < 1)      { r = c; g = x; }
	else if (hp < 2) { r = x; g = c; }
	else if (hp < 3) { g = c; b = x; }
	else if (hp < 4) { g = x; b = c; }
	else if (hp < 5) { r = x; b = c; }
	else             { r = c; b = x; }
	CGFloat m = l - c / 2;
	rgb[0] = SSClamp01(r + m);
	rgb[1] = SSClamp01(g + m);
	rgb[2] = SSClamp01(b + m);
}

static UIImage *SSRender(CGSize size, void (^draw)(CGContextRef ctx)) {
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.opaque = NO;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { draw(context.CGContext); }];
}

// Radial glow (the mockup's radial()): inner color at the center fading to outer at radius.
static CAGradientLayer *SSGlow(CGPoint center, CGFloat radius, UIColor *inner, UIColor *outer) {
	CAGradientLayer *g = [CAGradientLayer layer];
	g.type = kCAGradientLayerRadial;
	g.colors = @[(id)inner.CGColor, (id)outer.CGColor];
	g.startPoint = CGPointMake(0.5, 0.5);
	g.endPoint = CGPointMake(1, 1);
	g.frame = CGRectMake(center.x - radius, center.y - radius, 2 * radius, 2 * radius);
	return g;
}

// A raindrop on the glass: a light ellipse, brighter at the top left.
static UIImage *SSDropImage(void) {
	return SSRender(CGSizeMake(32, 40), ^(CGContextRef ctx) {
		CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, 32, 40));
		CGContextClip(ctx);
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		CGFloat comps[] = {1, 1, 1, 0.75,   180 / 255.0, 200 / 255.0, 220 / 255.0, 0.15};
		CGFloat locs[] = {0, 1};
		CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, locs, 2);
		CGContextDrawRadialGradient(ctx, gradient, CGPointMake(11, 14), 0, CGPointMake(16, 20), 22, kCGGradientDrawsAfterEndLocation);
		CGGradientRelease(gradient);
		CGColorSpaceRelease(space);
	});
}

// Apricot blossom (Tet): five yellow petals around an orange heart.
static UIImage *SSBlossomImage(void) {
	return SSRender(CGSizeMake(48, 48), ^(CGContextRef ctx) {
		CGContextTranslateCTM(ctx, 24, 24);
		CGContextSetFillColorWithColor(ctx, SSRGB(0xFFD43B).CGColor);
		for (int i = 0; i < 5; i++) {
			CGContextRotateCTM(ctx, (CGFloat)(M_PI * 2 / 5));
			CGContextFillEllipseInRect(ctx, CGRectMake(-7, -22, 14, 22));
		}
		CGContextSetFillColorWithColor(ctx, SSRGB(0xE8590C).CGColor);
		CGContextFillEllipseInRect(ctx, CGRectMake(-4.5, -4.5, 9, 9));
	});
}

static UIImage *SSCloudImage(UIColor *color) {
	UIImage *symbol = [[UIImage systemImageNamed:@"cloud.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:120]]
		imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
	if (!symbol) return nil;
	CGSize size = symbol.size;
	return SSRender(size, ^(CGContextRef ctx) { [symbol drawInRect:CGRectMake(0, 0, size.width, size.height)]; });
}

#pragma mark - Scene parts

// A view whose alpha (and vertical offset) follows the timeline: in over [inA, inB], out over [outA, outB].
@interface SSFade : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) CGFloat inA, inB, outA, outB, alpha, rise;
@property (nonatomic, assign) BOOL outEase;   // alpha follows out() (cards, festive icons)
@end

@implementation SSFade
- (void)applyTime:(CGFloat)t {
	CGFloat s = SSSpan(t, self.inA, self.inB);
	CGFloat a = self.alpha * (self.outEase ? SSOut(s) : s);
	if (self.outB > self.outA) a *= 1 - SSSpan(t, self.outA, self.outB);
	self.view.alpha = a;
	if (self.rise != 0) self.view.transform = CGAffineTransformMakeTranslation(0, self.rise * (1 - SSOut(s)));
}
@end

// Engine start dial.
@interface SSGauge : NSObject
@property (nonatomic, strong) CAShapeLayer *arc;       // mask of the lit arc (strokeEnd = value)
@property (nonatomic, strong) CAGradientLayer *fill;
@property (nonatomic, strong) CALayer *needle;
@property (nonatomic, strong) UILabel *number;
@property (nonatomic, assign) CGFloat max, red;
@property (nonatomic, assign) NSInteger shown;
@property (nonatomic, assign) BOOL hot;
@end

@implementation SSGauge
@end

// Things that move by a formula of t (one layer each).
typedef NS_ENUM(NSInteger, SSMoteKind) {
	SSMoteDrop, SSMoteStar, SSMoteFog, SSMoteCloud, SSMoteSnow, SSMotePetal, SSMoteConfetti, SSMoteLantern,
};

typedef struct {
	NSInteger kind;
	CGFloat x, y;   // start position (points)
	CGFloat v;      // speed (points / s; drops: 0-1 factor)
	CGFloat r;      // radius / half size
	CGFloat s;      // sway speed (petals), width (clouds)
	CGFloat p;      // phase
} SSMote;

typedef struct { CGFloat tx, ty, sx, sy, d, hue; } SSParticle;
typedef struct { CGFloat x, y, t, hue; } SSBurst;

enum { kSSBurstCount = 7 };
static const CGFloat kSSBurstPeriod = 3.85;   // 7 bursts 0.55 s apart, then again

// HUD lines for the settings preview (and when the tweak passes none).
static NSArray<NSDictionary *> *SSSampleHud(NSString *carName) {
	NSString *car = SSTrimmed(carName).length ? SSTrimmed(carName) : @"OmniCar";
	return @[
		@{@"text": OMCTr(@"Kết nối CarPlay", @"CarPlay connected"), @"ok": @YES},
		@{@"text": OMCTr(@"Pin iPhone 82% · đang sạc", @"iPhone battery 82% · charging"), @"ok": @YES},
		@{@"text": OMCTr(@"Nhiệt độ máy: ổn", @"Phone temperature: OK"), @"ok": @YES},
		@{@"text": OMCTr(@"Chế độ nhẹ: tự động", @"Lite mode: auto"), @"ok": @YES},
		@{@"text": [NSString stringWithFormat:OMCTr(@"Hồ sơ xe: %@", @"Car profile: %@"), car], @"ok": @YES},
	];
}

@interface SSStartupView ()
- (void)ss_step;
- (void)ss_drawCanvas:(CGContextRef)ctx size:(CGSize)size;
@end

// Display link target that does not keep the view alive.
@interface SSLinkTarget : NSObject
@property (nonatomic, weak) SSStartupView *owner;
@end

@implementation SSLinkTarget
- (void)step:(CADisplayLink *)link {
	SSStartupView *owner = self.owner;
	if (!owner) {
		[link invalidate];
		return;
	}
	[owner ss_step];
}
@end

// Particles / fireworks, redrawn every frame at 1x (soft dots; cheap to upload).
@interface SSCanvasView : UIView
@property (nonatomic, weak) SSStartupView *owner;
@end

@implementation SSCanvasView
- (void)drawRect:(CGRect)rect {
	[self.owner ss_drawCanvas:UIGraphicsGetCurrentContext() size:self.bounds.size];
}
@end

#pragma mark - View

// Mockup canvas point (1600 x 600) -> view point.
#define SSPT(x, y) CGPointMake(_ox + (x) * _k, _oy + (y) * _k)

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

	// Animated scenes
	NSInteger _sceneStyle;        // style drawn as a scene (-1 = none)
	SSSky _sky;
	CGSize _sceneSize;
	BOOL _sceneBuilt;
	CGFloat _k, _ox, _oy;         // canvas scale and letterbox offset
	CGFloat _restTime;            // pose shown when not playing (settings preview before a tap)
	CGFloat _linkEnd;             // nothing moves after this (the display link stops)
	CGFloat _tempoScale;          // Welcome: 1.4 / 1 / 0.7
	CFTimeInterval _t0;
	BOOL _playing;
	CADisplayLink *_link;
	UIView *_scene;               // below the greeting / weather stack
	UIView *_glass;               // above it (rain on the windscreen)
	SSCanvasView *_canvas;
	NSMutableArray<SSFade *> *_fades;
	NSMutableData *_motes;
	NSMutableArray<CALayer *> *_moteLayers;
	NSMutableArray<SSGauge *> *_gauges;
	NSMutableData *_particles;
	CGFloat _dot;
	NSMutableData *_bursts;
	CAShapeLayer *_outline, *_wheels;
	CALayer *_flash, *_horizon, *_rays, *_wiper, *_lightning, *_radar;
	CAShapeLayer *_wetMask;
	CGFloat _wiperLength, _cleared;
	CGPoint _wiperPivot;
	NSMutableArray<CAShapeLayer *> *_rings;
	UILabel *_percentLabel;
	NSInteger _percentShown;
}

+ (Class)layerClass {
	return [CAGradientLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.clipsToBounds = YES;
		self.backgroundColor = [UIColor blackColor];
		_batteryPercent = -1;
		_tempo = 1;
		_sceneStyle = -1;
	}
	return self;
}

- (void)dealloc {
	[_link invalidate];
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
	[self ss_clearScene];
	_sceneStyle = -1;
	_sceneSize = CGSizeZero;
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
	if (style == SS_STYLE_FESTIVE && (self.occasion < SS_OCCASION_TET || self.occasion > SS_OCCASION_NEWYEAR)) style = SS_STYLE_GREETING;
	// Random is resolved by the tweak before it gets here; anything unknown shows the greeting.
	if (style < SS_STYLE_VIDEO || style > SS_STYLE_FESTIVE || style == SS_STYLE_RANDOM) style = SS_STYLE_GREETING;

	_tempoScale = self.tempo <= 0 ? 1.4 : (self.tempo >= 2 ? 0.7 : 1.0);
	_linkEnd = INFINITY;
	switch (style) {
		case SS_STYLE_WEATHER:   _restTime = 3.0; break;
		case SS_STYLE_ENGINE:    _restTime = 4.0; _linkEnd = 3.8; break;
		case SS_STYLE_WELCOME:   _restTime = 4.0 * _tempoScale; _linkEnd = 3.6 * _tempoScale; break;
		case SS_STYLE_PARTICLES: _restTime = 3.0; break;
		case SS_STYLE_HUD:       _restTime = 3.4; break;
		case SS_STYLE_BRIEFING:  _restTime = 2.6; _linkEnd = 2.5; break;
		case SS_STYLE_LIQUID:    _restTime = 2.8; _linkEnd = 2.6; break;
		default:                 _restTime = 2.5; break;
	}

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
	} else if (style == SS_STYLE_GREETING || style == SS_STYLE_WEATHER) {
		bg.colors = SSPeriodColors(period);
		if (style == SS_STYLE_WEATHER) {
			// Animated sky behind the data (built for the view size in -layoutSubviews).
			BOOL day = [self.weather[SS_WX_DAY] boolValue];
			_sky = SSSkyFor([self.weather[SS_WX_CODE] integerValue], day);
			bg.colors = SSSkyColors(_sky, day);
			bg.startPoint = CGPointMake(0.5, 0);
			bg.endPoint = CGPointMake(0.5, 1);
			_sceneStyle = SS_STYLE_WEATHER;
			[self buildWeatherWithPeriod:period];
		} else {
			[self buildGreetingWithDate:date period:period];
		}
		_stack.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_stack];
		_stackMaxWidth = [_stack.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor constant:-16];
		[NSLayoutConstraint activateConstraints:@[
			[_stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[_stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
			_stackMaxWidth,
		]];
	} else {
		// Engine / Welcome / Particles / HUD / Briefing / Festive: a scene, top -> bottom background.
		_sceneStyle = style;
		bg.startPoint = CGPointMake(0.5, 0);
		bg.endPoint = CGPointMake(0.5, 1);
		bg.colors = [self ss_sceneColors];
	}
	[self setNeedsLayout];
}

- (NSArray *)ss_sceneColors {
	switch (_sceneStyle) {
		case SS_STYLE_ENGINE:    return SSPair(0x05070C, 0x000000);
		case SS_STYLE_WELCOME:   return SSPair(0x020308, 0x06070D);
		case SS_STYLE_PARTICLES: return SSPair(0x020309, 0x070A18);
		case SS_STYLE_HUD:       return SSPair(0x01050C, 0x04121E);
		case SS_STYLE_BRIEFING:  return SSPair(0x0C1A33, 0x1F3A66);
		case SS_STYLE_LIQUID:    return SSPair(0xEEF0FB, 0xF4F5FB);   // sang; mau chat long la cac lop glow trong canh
		default: break;
	}
	switch (self.occasion) {
		case SS_OCCASION_TET:       return SSPair(0x5A0006, 0xA3000F);
		case SS_OCCASION_BIRTHDAY:  return SSPair(0x1B0B3A, 0x3B1A78);
		case SS_OCCASION_XMAS:      return SSPair(0x04121F, 0x0B2A3D);
		case SS_OCCASION_MIDAUTUMN: return SSPair(0x0A0A24, 0x1D1446);
		default:                    return SSPair(0x020A24, 0x0B1D4A);   // New Year: dark blue
	}
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

	if (_sceneStyle >= 0 && !CGSizeEqualToSize(size, _sceneSize)) [self ss_buildScene];

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

	// Scenes: restart the timeline from 0 (also when the content has none yet: a Weather screen that gets its
	// data later joins the timeline where it is).
	_t0 = CACurrentMediaTime();
	_playing = YES;
	if (_sceneStyle >= 0) {
		[self ss_applyTime:0];
		[self ss_startLink];
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

#pragma mark - Timeline

- (CGFloat)ss_now {
	return _playing ? (CGFloat)(CACurrentMediaTime() - _t0) : _restTime;
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window) [self ss_startLink];
	else [self ss_stopLink];
}

- (void)ss_startLink {
	if (_link || !_playing || !self.window || _sceneStyle < 0) return;
	if ([self ss_now] > _linkEnd) return;
	SSLinkTarget *target = [SSLinkTarget new];
	target.owner = self;
	UIScreen *screen = self.window.screen;
	_link = screen ? [screen displayLinkWithTarget:target selector:@selector(step:)]
		: [CADisplayLink displayLinkWithTarget:target selector:@selector(step:)];
	_link.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
	[_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)ss_stopLink {
	[_link invalidate];
	_link = nil;
}

- (void)ss_step {
	CGFloat t = [self ss_now];
	if (_sceneStyle < 0 || !self.window) {
		[self ss_stopLink];
		return;
	}
	[self ss_applyTime:t];
	if (t > _linkEnd) [self ss_stopLink];
}

- (void)ss_applyTime:(CGFloat)t {
	if (!_sceneBuilt) return;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for (SSFade *fade in _fades) [fade applyTime:t];
	[self ss_applyMotes:t];
	switch (_sceneStyle) {
		case SS_STYLE_WEATHER: [self ss_applySky:t]; break;
		case SS_STYLE_ENGINE:  [self ss_applyEngine:t]; break;
		case SS_STYLE_WELCOME: [self ss_applyWelcome:t]; break;
		case SS_STYLE_HUD:     [self ss_applyHud:t]; break;
		default: break;
	}
	[_canvas setNeedsDisplay];
	[CATransaction commit];
}

#pragma mark - Scene building

- (void)ss_clearScene {
	[self ss_stopLink];
	[_scene removeFromSuperview];
	[_glass removeFromSuperview];
	_scene = _glass = nil;
	_canvas = nil;
	_fades = [NSMutableArray array];
	_motes = [NSMutableData data];
	_moteLayers = [NSMutableArray array];
	_gauges = [NSMutableArray array];
	_rings = [NSMutableArray array];
	_particles = nil;
	_bursts = nil;
	_outline = _wheels = nil;
	_flash = _horizon = _rays = _wiper = _lightning = _radar = nil;
	_wetMask = nil;
	_cleared = -1;
	_percentLabel = nil;
	_percentShown = -1;
	_sceneBuilt = NO;
}

- (void)ss_buildScene {
	BOOL playing = _playing;
	[self ss_clearScene];
	CGSize size = self.bounds.size;
	_sceneSize = size;
	CGFloat u = MIN(size.height / 100.0, size.width / 260.0);
	if (_sceneStyle < 0 || u <= 0) return;
	_k = u / 6.0;
	_ox = (size.width - 1600 * _k) / 2;
	_oy = (size.height - 600 * _k) / 2;

	_scene = [[UIView alloc] initWithFrame:self.bounds];
	_scene.userInteractionEnabled = NO;
	[self insertSubview:_scene atIndex:0];

	switch (_sceneStyle) {
		case SS_STYLE_WEATHER:   [self ss_buildSky]; break;
		case SS_STYLE_ENGINE:    [self ss_buildEngine]; break;
		case SS_STYLE_WELCOME:   [self ss_buildWelcome]; break;
		case SS_STYLE_PARTICLES: [self ss_buildParticles]; break;
		case SS_STYLE_HUD:       [self ss_buildHud]; break;
		case SS_STYLE_BRIEFING:  [self ss_buildBriefing]; break;
		case SS_STYLE_LIQUID:    [self ss_buildLiquid]; break;
		case SS_STYLE_FESTIVE:   [self ss_buildFestive]; break;
		default: break;
	}
	_sceneBuilt = YES;
	[self ss_applyTime:[self ss_now]];
	if (playing) [self ss_startLink];
}

// A full-size layer holder inside the scene, stacked in creation order.
- (UIView *)ss_host {
	UIView *host = [[UIView alloc] initWithFrame:_scene.bounds];
	host.userInteractionEnabled = NO;
	[_scene addSubview:host];
	return host;
}

- (void)ss_addCanvas {
	_canvas = [[SSCanvasView alloc] initWithFrame:_scene.bounds];
	_canvas.owner = self;
	_canvas.opaque = NO;
	_canvas.backgroundColor = [UIColor clearColor];
	_canvas.userInteractionEnabled = NO;
	_canvas.contentScaleFactor = 1;
	_canvas.contentMode = UIViewContentModeRedraw;
	[_scene addSubview:_canvas];
}

// Text at a point: size is in canvas pixels, center (or left edge, left = YES) in view points of parent.
- (UILabel *)ss_label:(NSString *)text at:(CGPoint)p size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color
                 left:(BOOL)left in:(UIView *)parent maxWidth:(CGFloat)maxWidth {
	UILabel *label = SSLabel(text);
	label.font = SSFont(MAX(1, size * _k), weight);
	label.textColor = color ?: [UIColor whiteColor];
	label.textAlignment = left ? NSTextAlignmentLeft : NSTextAlignmentCenter;
	label.layer.shadowOpacity = 0.4;
	label.layer.shadowRadius = MAX(1, 7 * _k);
	label.layer.shadowOffset = CGSizeZero;
	CGFloat scale = self.traitCollection.displayScale;
	label.layer.shouldRasterize = YES;
	label.layer.rasterizationScale = scale > 0 ? scale : 2;
	CGSize fit = [label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
	CGFloat limit = maxWidth > 0 ? maxWidth : (left ? parent.bounds.size.width - p.x - 6 * _k : parent.bounds.size.width - 12 * _k);
	CGFloat width = MIN(ceil(fit.width), MAX(limit, 10));
	label.bounds = CGRectMake(0, 0, width, ceil(fit.height));
	label.center = left ? CGPointMake(p.x + width / 2, p.y) : p;
	[parent addSubview:label];
	return label;
}

- (SSFade *)ss_fade:(UIView *)view from:(CGFloat)a to:(CGFloat)b alpha:(CGFloat)alpha {
	SSFade *fade = [SSFade new];
	fade.view = view;
	fade.inA = a;
	fade.inB = b;
	fade.alpha = alpha;
	[_fades addObject:fade];
	return fade;
}

- (void)ss_addMote:(SSMote)mote layer:(CALayer *)layer to:(CALayer *)parent {
	[_motes appendBytes:&mote length:sizeof(mote)];
	[_moteLayers addObject:layer];
	[parent addSublayer:layer];
}

- (void)ss_applyMotes:(CGFloat)t {
	NSUInteger count = _moteLayers.count;
	if (!count) return;
	const SSMote *motes = (const SSMote *)_motes.bytes;
	CGFloat k = _k, w = _sceneSize.width, h = _sceneSize.height;
	for (NSUInteger i = 0; i < count; i++) {
		SSMote m = motes[i];
		CALayer *layer = _moteLayers[i];
		switch (m.kind) {
			case SSMoteDrop:   // slow trickle down the glass
				layer.position = CGPointMake(m.x, SSWrap(m.y + t * 60 * m.v * k, h));
				break;
			case SSMoteStar:
				layer.opacity = (float)(0.4 + 0.6 * fabs(sin(t * 2 + m.p)));
				break;
			case SSMoteFog:
				layer.position = CGPointMake(SSWrap(m.x + t * m.v, w + 600 * k) - 300 * k, m.y);
				break;
			case SSMoteCloud:
				layer.position = CGPointMake(SSWrap(m.x + t * m.v, w + m.s) - m.s / 2, m.y);
				break;
			case SSMoteSnow:
				layer.position = CGPointMake(m.x + (CGFloat)sin(t + m.p) * 10 * k, SSWrap(m.y + t * m.v, h + 4 * m.r) - 2 * m.r);
				break;
			case SSMotePetal:
				layer.position = CGPointMake(m.x + (CGFloat)sin(t * m.s + m.p) * 30 * k, SSWrap(m.y + t * m.v, h + 40 * k) - 20 * k);
				layer.transform = CATransform3DMakeRotation(t + m.p, 0, 0, 1);
				break;
			case SSMoteConfetti:
				layer.position = CGPointMake(m.x + (CGFloat)sin(t * 2 + m.p) * 20 * k, SSWrap(m.y + t * m.v, h + 30 * k) - 15 * k);
				layer.transform = CATransform3DMakeRotation(t * 3 + m.p, 0, 0, 1);
				break;
			case SSMoteLantern:   // rises from below, again and again
				layer.position = CGPointMake(m.x, h - SSWrap(t * 50 * k + m.p, h + 120 * k) + 60 * k);
				break;
			default:
				break;
		}
	}
}

#pragma mark Weather sky

- (void)ss_buildSky {
	CGFloat k = _k, w = _sceneSize.width, h = _sceneSize.height;
	SSSky sky = _sky;
	BOOL day = [self.weather[SS_WX_DAY] boolValue];
	CALayer *back = [self ss_host].layer;

	// Sun: 12 soft rays turning slowly + a warm glow.
	if (sky == SSSkyClearDay || sky == SSSkyPartlyDay) {
		CGPoint c = SSPT(1340, 150);
		_rays = [CALayer layer];
		_rays.bounds = CGRectZero;
		_rays.position = c;
		for (int i = 0; i < 12; i++) {
			CALayer *ray = [CALayer layer];
			ray.backgroundColor = SSRGBA(0xFFF0B4, 0.18).CGColor;
			ray.anchorPoint = CGPointMake(0, 0.5);
			ray.bounds = CGRectMake(0, 0, 520 * k, 28 * k);
			ray.position = CGPointZero;
			ray.transform = CATransform3DMakeRotation((CGFloat)((i + 1) * M_PI / 6), 0, 0, 1);
			[_rays addSublayer:ray];
		}
		[back addSublayer:_rays];
		[back addSublayer:SSGlow(c, 180 * k, SSRGBA(0xFFFADC, 1), SSRGBA(0xFFDC78, 0))];
	}
	// Night: twinkling stars + moon glow.
	if (sky == SSSkyClearNight || sky == SSSkyPartlyNight) {
		for (int i = 0; i < 110; i++) {
			CGFloat r = MAX(0.5, SSRand(0.6, 2) * k);
			CALayer *star = [CALayer layer];
			star.backgroundColor = [UIColor whiteColor].CGColor;
			star.bounds = CGRectMake(0, 0, 2 * r, 2 * r);
			star.cornerRadius = r;
			star.position = CGPointMake(SSRand(0, w), SSRand(0, h * 0.7));
			SSMote m = {SSMoteStar, 0, 0, 0, r, 0, SSRand(0, 6)};
			[self ss_addMote:m layer:star to:back];
		}
		[back addSublayer:SSGlow(SSPT(1340, 140), 120 * k, SSRGBA(0xFFFFE6, 0.95), SSRGBA(0xFFFFE6, 0))];
	}
	// Clouds drifting across.
	if (sky == SSSkyPartlyDay || sky == SSSkyPartlyNight || sky == SSSkyCloudy || sky == SSSkySnow) {
		UIImage *cloud = SSCloudImage(day ? [UIColor whiteColor] : SSRGB(0xB4BED2));
		NSInteger n = sky == SSSkyCloudy ? 5 : 3;
		for (NSInteger i = 0; cloud && i < n; i++) {
			CGFloat cw = SSRand(260, 420) * k;
			CALayer *layer = [CALayer layer];
			layer.contents = (__bridge id)cloud.CGImage;
			layer.contentsGravity = kCAGravityResizeAspect;
			layer.bounds = CGRectMake(0, 0, cw, cw * cloud.size.height / MAX(cloud.size.width, 1));
			layer.opacity = (float)SSRand(0.35, 0.6);
			CGFloat y = SSRand(0.1, 0.5) * h;
			layer.position = CGPointMake(0, y);
			SSMote m = {SSMoteCloud, SSRand(0, w + cw), y, SSRand(8, 22) * k, 0, cw, 0};
			[self ss_addMote:m layer:layer to:back];
		}
	}
	// Fog banks drifting by.
	if (sky == SSSkyFog) {
		for (int i = 0; i < 6; i++) {
			CAGradientLayer *bank = [CAGradientLayer layer];
			bank.type = kCAGradientLayerRadial;
			bank.colors = @[(id)SSRGBA(0xFFFFFF, 0.3).CGColor, (id)SSRGBA(0xFFFFFF, 0.14).CGColor, (id)SSRGBA(0xFFFFFF, 0).CGColor];
			bank.locations = @[@0, @0.6, @1];
			bank.startPoint = CGPointMake(0.5, 0.5);
			bank.endPoint = CGPointMake(1, 1);
			bank.bounds = CGRectMake(0, 0, 840 * k, 110 * k);
			CGFloat y = SSPT(0, 120 + i * 80).y;
			SSMote m = {SSMoteFog, SSRand(0, w), y, SSRand(20, 60) * 3 * k, 0, 0, 0};
			[self ss_addMote:m layer:bank to:back];
		}
	}
	// Snow.
	if (sky == SSSkySnow) {
		for (int i = 0; i < 100; i++) {
			CGFloat r = SSRand(1.5, 4.5) * k;
			CALayer *flake = [CALayer layer];
			flake.backgroundColor = SSRGBA(0xFFFFFF, 0.85).CGColor;
			flake.bounds = CGRectMake(0, 0, 2 * r, 2 * r);
			flake.cornerRadius = r;
			SSMote m = {SSMoteSnow, SSRand(0, w), SSRand(0, h), SSRand(30, 70) * k, r, 0, SSRand(0, 6)};
			[self ss_addMote:m layer:flake to:back];
		}
	}
	// Thunder: the sky lights up now and then.
	if (sky == SSSkyThunder) {
		_lightning = [CALayer layer];
		_lightning.frame = _scene.bounds;
		_lightning.backgroundColor = SSRGBA(0xDDE6FF, 1).CGColor;
		_lightning.opacity = 0;
		[back addSublayer:_lightning];
	}
	// Rain: drops on a fogged windscreen in front of the data, and a wiper that clears it (stays clear).
	if (sky == SSSkyRain || sky == SSSkyDrizzle || sky == SSSkyThunder) {
		_glass = [[UIView alloc] initWithFrame:self.bounds];
		_glass.userInteractionEnabled = NO;
		[self addSubview:_glass];
		CALayer *wet = [CALayer layer];
		wet.frame = _glass.bounds;
		CALayer *mist = [CALayer layer];
		mist.frame = wet.bounds;
		mist.backgroundColor = SSRGBA(0x1E2837, 0.55).CGColor;
		[wet addSublayer:mist];
		UIImage *drop = SSDropImage();
		NSInteger n = sky == SSSkyDrizzle ? 70 : 120;
		for (NSInteger i = 0; i < n; i++) {
			CGFloat r = SSRand(3, 9) * k;
			CALayer *layer = [CALayer layer];
			layer.contents = (__bridge id)drop.CGImage;
			layer.bounds = CGRectMake(0, 0, 1.6 * r, 2 * r);
			SSMote m = {SSMoteDrop, SSRand(0, w), SSRand(0, h), SSRand(0, 1), r, 0, 0};
			[self ss_addMote:m layer:layer to:wet];
		}
		_wetMask = [CAShapeLayer layer];
		_wetMask.frame = wet.bounds;
		_wetMask.fillRule = kCAFillRuleEvenOdd;
		_wetMask.fillColor = [UIColor blackColor].CGColor;
		wet.mask = _wetMask;
		[_glass.layer addSublayer:wet];

		_wiperPivot = CGPointMake(w / 2, h + 80 * k);
		_wiperLength = MAX(980 * k, w * 0.6125);
		_wiper = [CALayer layer];
		_wiper.bounds = CGRectZero;
		_wiper.position = _wiperPivot;
		CAShapeLayer *blade = [CAShapeLayer layer];
		UIBezierPath *bladePath = [UIBezierPath bezierPath];
		[bladePath moveToPoint:CGPointZero];
		[bladePath addLineToPoint:CGPointMake(_wiperLength, 0)];
		blade.path = bladePath.CGPath;
		blade.strokeColor = SSRGB(0x0B0B0D).CGColor;
		blade.lineWidth = MAX(2, 16 * k);
		blade.lineCap = kCALineCapRound;
		[_wiper addSublayer:blade];
		CAShapeLayer *shine = [CAShapeLayer layer];
		UIBezierPath *shinePath = [UIBezierPath bezierPath];
		[shinePath moveToPoint:CGPointMake(60 * k, -6 * k)];
		[shinePath addLineToPoint:CGPointMake(_wiperLength, -6 * k)];
		shine.path = shinePath.CGPath;
		shine.strokeColor = SSRGBA(0xFFFFFF, 0.15).CGColor;
		shine.lineWidth = MAX(1, 3 * k);
		[_wiper addSublayer:shine];
		[_glass.layer addSublayer:_wiper];
	}
}

- (void)ss_applySky:(CGFloat)t {
	if (_rays) _rays.transform = CATransform3DMakeRotation(t * 0.25, 0, 0, 1);
	if (_lightning) {
		CGFloat tt = SSWrap(t, 7);
		CGFloat flash = MAX(SSSpike(tt, 0.35, 0.08), MAX(0.6 * SSSpike(tt, 0.55, 0.06), SSSpike(tt, 4.2, 0.1)));
		_lightning.opacity = (float)(0.55 * flash);
	}
	if (_wiper) {
		// 1.0-1.9 s forward, back by 2.6 s; the swept area stays clear.
		CGFloat wipe = t < 1.0 ? 0 : t < 1.9 ? SSEase(SSSpan(t, 1.0, 1.9)) : t < 2.6 ? 1 - SSEase(SSSpan(t, 1.9, 2.6)) : 0;
		CGFloat cleared = t < 1.0 ? 0 : t < 1.9 ? wipe : 1;
		_wiper.transform = CATransform3DMakeRotation((CGFloat)(-M_PI + wipe * M_PI), 0, 0, 1);
		if (fabs(cleared - _cleared) > 0.0005) {
			_cleared = cleared;
			CGMutablePathRef path = CGPathCreateMutable();
			CGPathAddRect(path, NULL, _wetMask.bounds);
			if (cleared > 0) {
				CGPathMoveToPoint(path, NULL, _wiperPivot.x, _wiperPivot.y);
				CGPathAddArc(path, NULL, _wiperPivot.x, _wiperPivot.y, _wiperLength, (CGFloat)M_PI, (CGFloat)(M_PI + cleared * M_PI), false);
				CGPathCloseSubpath(path);
			}
			_wetMask.path = path;
			CGPathRelease(path);
		}
	}
}

#pragma mark Engine start

- (SSGauge *)ss_gaugeAt:(CGPoint)c radius:(CGFloat)R label:(NSString *)label unit:(NSString *)unit max:(CGFloat)max red:(CGFloat)red in:(UIView *)parent {
	CGFloat k = _k, lw = MAX(2, 10 * k);
	CGFloat a0 = (CGFloat)(M_PI * 0.75), a1 = (CGFloat)(M_PI * 2.25);
	CGFloat side = 2 * R + 4 * lw;
	CGRect box = CGRectMake(c.x - side / 2, c.y - side / 2, side, side);
	CGPoint m = CGPointMake(side / 2, side / 2);
	UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:m radius:R startAngle:a0 endAngle:a1 clockwise:YES];
	CALayer *host = parent.layer;
	SSGauge *gauge = [SSGauge new];
	gauge.max = max;
	gauge.red = red;
	gauge.shown = -1;

	CAShapeLayer *track = [CAShapeLayer layer];
	track.frame = box;
	track.path = arcPath.CGPath;
	track.fillColor = nil;
	track.strokeColor = SSRGBA(0xFFFFFF, 0.1).CGColor;
	track.lineWidth = lw;
	track.lineCap = kCALineCapRound;
	[host addSublayer:track];

	// Lit arc: a cyan -> white gradient masked by the arc, glowing.
	CALayer *glow = [CALayer layer];
	glow.frame = box;
	glow.shadowColor = [UIColor whiteColor].CGColor;
	glow.shadowOpacity = 0.6;
	glow.shadowRadius = 8 * k;
	glow.shadowOffset = CGSizeZero;
	CAGradientLayer *fill = [CAGradientLayer layer];
	fill.frame = glow.bounds;
	fill.startPoint = CGPointMake(0, 0.5);
	fill.endPoint = CGPointMake(1, 0.5);
	fill.colors = SSPair(0x7FD3FF, 0xFFFFFF);
	CAShapeLayer *arc = [CAShapeLayer layer];
	arc.frame = fill.bounds;
	arc.path = arcPath.CGPath;
	arc.fillColor = nil;
	arc.strokeColor = [UIColor blackColor].CGColor;
	arc.lineWidth = lw;
	arc.lineCap = kCALineCapRound;
	arc.strokeEnd = 0;
	fill.mask = arc;
	[glow addSublayer:fill];
	[host addSublayer:glow];
	gauge.arc = arc;
	gauge.fill = fill;

	// 11 ticks, the red zone in red.
	UIBezierPath *white = [UIBezierPath bezierPath], *redTicks = [UIBezierPath bezierPath];
	for (int i = 0; i <= 10; i++) {
		CGFloat a = a0 + (a1 - a0) * i / 10, inR = R - 26 * k, outR = R - 14 * k;
		UIBezierPath *p = i / 10.0 >= red - 0.0001 ? redTicks : white;
		[p moveToPoint:CGPointMake(m.x + (CGFloat)cos(a) * inR, m.y + (CGFloat)sin(a) * inR)];
		[p addLineToPoint:CGPointMake(m.x + (CGFloat)cos(a) * outR, m.y + (CGFloat)sin(a) * outR)];
	}
	for (int i = 0; i < 2; i++) {
		CAShapeLayer *ticks = [CAShapeLayer layer];
		ticks.frame = box;
		ticks.path = (i ? redTicks : white).CGPath;
		ticks.strokeColor = (i ? SSRGBA(0xFF5C54, 0.9) : SSRGBA(0xFFFFFF, 0.55)).CGColor;
		ticks.lineWidth = MAX(1, 3 * k);
		[host addSublayer:ticks];
	}

	// Needle (drawn pointing right, turned by the value) and hub.
	CAShapeLayer *needle = [CAShapeLayer layer];
	needle.frame = box;
	UIBezierPath *needlePath = [UIBezierPath bezierPath];
	[needlePath moveToPoint:m];
	[needlePath addLineToPoint:CGPointMake(m.x + R - 30 * k, m.y)];
	needle.path = needlePath.CGPath;
	needle.strokeColor = SSRGB(0xFF5C54).CGColor;
	needle.lineWidth = MAX(1.5, 5 * k);
	needle.lineCap = kCALineCapRound;
	needle.shadowColor = SSRGB(0xFF5C54).CGColor;
	needle.shadowOpacity = 1;
	needle.shadowRadius = 6 * k;
	needle.shadowOffset = CGSizeZero;
	[host addSublayer:needle];
	gauge.needle = needle;
	CAShapeLayer *hub = [CAShapeLayer layer];
	hub.frame = box;
	hub.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(m.x - 14 * k, m.y - 14 * k, 28 * k, 28 * k)].CGPath;
	hub.fillColor = SSRGB(0x111111).CGColor;
	[host addSublayer:hub];

	UILabel *number = [self ss_label:@"888" at:CGPointMake(c.x, c.y + R * 0.45) size:46 weight:UIFontWeightBold color:nil left:NO in:parent maxWidth:0];
	number.text = @"0";
	gauge.number = number;
	UILabel *unitLabel = [self ss_label:unit at:CGPointMake(c.x, c.y + R * 0.45 + 38 * k) size:20 weight:UIFontWeightSemibold color:nil left:NO in:parent maxWidth:2 * R];
	unitLabel.alpha = 0.55;
	UILabel *title = [self ss_label:label at:CGPointMake(c.x, c.y - R * 0.35) size:18 weight:UIFontWeightSemibold color:nil left:NO in:parent maxWidth:2 * R];
	title.alpha = 0.45;
	[_gauges addObject:gauge];
	return gauge;
}

- (void)ss_buildEngine {
	CGFloat k = _k;
	UIView *host = [self ss_host];
	[host.layer addSublayer:SSGlow(CGPointMake(_sceneSize.width / 2, _sceneSize.height / 2), _sceneSize.width * 0.5,
		SSRGBA(0x283C6E, 0.35), SSRGBA(0x000000, 0))];

	BOOL metric = [NSLocale currentLocale].usesMetricSystem;
	[self ss_gaugeAt:SSPT(330, 320) radius:210 * k label:OMCTr(@"VÒNG TUA", @"RPM") unit:@"x1000 rpm" max:8 red:0.8 in:host];
	[self ss_gaugeAt:SSPT(1270, 320) radius:210 * k label:OMCTr(@"TỐC ĐỘ", @"SPEED") unit:(metric ? @"km/h" : @"mph")
		max:(metric ? 220 : 140) red:0.9 in:host];

	// Warning lights: all on, then off one by one (the bulb check when the key turns).
	NSArray *lights = @[
		@[@[@"fuelpump.fill"], @0xFFB400],
		@[@[@"minus.plus.batteryblock.fill", @"minus.plus.batteryblock", @"bolt.fill"], @0xFF5C54],
		@[@[@"exclamationmark.triangle.fill"], @0xFFB400],
		@[@[], @0xFFB400],   // ABS
		@[@[@"engine.combustion.fill", @"exclamationmark.circle.fill"], @0xFFB400],
		@[@[@"headlight.high.beam.fill", @"light.max"], @0x50C8FF],
	];
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:MAX(6, 30 * k) weight:UIImageSymbolWeightBold];
	for (NSUInteger i = 0; i < lights.count; i++) {
		NSArray *names = lights[i][0];
		UIColor *color = SSRGB([lights[i][1] unsignedIntValue]);
		CGPoint p = SSPT(600 + i * 80, 120);
		UIImage *image = nil;
		for (NSString *name in names) {
			image = [UIImage systemImageNamed:name withConfiguration:config];
			if (image) break;
		}
		UIView *light;
		if (image) {
			UIImageView *iv = [[UIImageView alloc] initWithImage:image];
			iv.tintColor = color;
			iv.contentMode = UIViewContentModeScaleAspectFit;
			[iv sizeToFit];
			iv.center = p;
			iv.layer.shadowColor = color.CGColor;
			iv.layer.shadowOpacity = 0.7;
			iv.layer.shadowRadius = 5 * k;
			iv.layer.shadowOffset = CGSizeZero;
			[host addSubview:iv];
			light = iv;
		} else {
			light = [self ss_label:@"ABS" at:p size:26 weight:UIFontWeightHeavy color:color left:NO in:host maxWidth:0];
		}
		SSFade *fade = [self ss_fade:light from:0 to:0.3 alpha:0.95];
		fade.outA = 1.4 + i * 0.12;
		fade.outB = 1.7 + i * 0.12;
	}

	NSString *car = SSTrimmed(self.carName).length ? SSTrimmed(self.carName) : @"OmniCar";
	NSInteger period = SSPeriodForDate(self.date ?: [NSDate date]);
	CGFloat between = (1270 - 330 - 2 * 210 + 120) * k;   // the room between the dials (they overlap a little)
	UILabel *name = [self ss_label:car at:SSPT(800, 300) size:70 weight:UIFontWeightHeavy color:nil left:NO in:host maxWidth:between];
	[self ss_fade:name from:2.2 to:2.9 alpha:1].rise = -10 * k;
	UILabel *greet = [self ss_label:SSGreetingTitle(self.name, period) at:SSPT(800, 380) size:30 weight:UIFontWeightSemibold color:nil
		left:NO in:host maxWidth:between];
	[self ss_fade:greet from:2.6 to:3.3 alpha:1];
	UILabel *clock = [self ss_label:SSTimeText(self.date ?: [NSDate date]) at:SSPT(800, 450) size:24 weight:UIFontWeightMedium color:nil
		left:NO in:host maxWidth:between];
	[self ss_fade:clock from:2.9 to:3.6 alpha:0.7];
}

- (void)ss_setGauge:(SSGauge *)g value:(CGFloat)value {
	CGFloat a0 = (CGFloat)(M_PI * 0.75), a1 = (CGFloat)(M_PI * 2.25);
	g.arc.strokeEnd = SSClamp01(value);
	g.needle.transform = CATransform3DMakeRotation(a0 + (a1 - a0) * value, 0, 0, 1);
	BOOL hot = value > g.red;
	if (hot != g.hot) {
		g.hot = hot;
		g.fill.colors = SSPair(0x7FD3FF, hot ? 0xFF5C54 : 0xFFFFFF);
	}
	NSInteger shown = (NSInteger)lround(value * g.max);
	if (shown != g.shown) {
		g.shown = shown;
		g.number.text = [NSString stringWithFormat:@"%ld", (long)shown];
	}
}

- (void)ss_applyEngine:(CGFloat)t {
	if (_gauges.count < 2) return;
	CGFloat sweep = t < 0.4 ? 0 : t < 1.3 ? SSEase(SSSpan(t, 0.4, 1.3)) : t < 2.3 ? 1 - SSEase(SSSpan(t, 1.3, 2.3)) : 0;
	CGFloat idle = t > 2.3 ? 0.08 + (CGFloat)sin(t * 9) * 0.004 : 0;
	[self ss_setGauge:_gauges[0] value:MAX(sweep, idle)];
	[self ss_setGauge:_gauges[1] value:sweep];
}

#pragma mark Welcome light

- (void)ss_buildWelcome {
	CGFloat k = _k, kt = _tempoScale;
	static const CGFloat car[][2] = {{0, .78}, {.05, .74}, {.12, .7}, {.22, .62}, {.36, .44}, {.52, .40}, {.66, .44}, {.8, .58}, {.94, .62}, {1, .7}, {1, .78}};
	const int n = (int)(sizeof(car) / sizeof(car[0]));
	CGPoint pts[sizeof(car) / sizeof(car[0])];
	for (int i = 0; i < n; i++) pts[i] = SSPT(350 + car[i][0] * 900, 40 + car[i][1] * 420);
	// The mockup's polyline, corners rounded (quadratic through the midpoints).
	UIBezierPath *outline = [UIBezierPath bezierPath];
	[outline moveToPoint:pts[0]];
	for (int i = 1; i < n - 1; i++) {
		CGPoint mid = CGPointMake((pts[i].x + pts[i + 1].x) / 2, (pts[i].y + pts[i + 1].y) / 2);
		[outline addQuadCurveToPoint:mid controlPoint:pts[i]];
	}
	[outline addLineToPoint:pts[n - 1]];

	UIView *host = [self ss_host];
	CGFloat horizonY = SSPT(0, 40 + 0.78 * 420 + 56).y;
	_horizon = [CALayer layer];
	_horizon.frame = CGRectMake(0, horizonY, _sceneSize.width, MAX(1, 2 * k));
	_horizon.backgroundColor = SSRGB(0xA0D2FF).CGColor;
	_horizon.opacity = 0;
	[host.layer addSublayer:_horizon];

	CAShapeLayer *(^line)(UIBezierPath *) = ^CAShapeLayer *(UIBezierPath *path) {
		CAShapeLayer *layer = [CAShapeLayer layer];
		layer.frame = host.bounds;
		layer.path = path.CGPath;
		layer.fillColor = nil;
		layer.strokeColor = [UIColor whiteColor].CGColor;
		layer.lineWidth = MAX(1.5, 6 * k);
		layer.lineCap = kCALineCapRound;
		layer.lineJoin = kCALineJoinRound;
		layer.shadowColor = SSRGB(0xA0D2FF).CGColor;
		layer.shadowOpacity = 0.95;
		layer.shadowRadius = 15 * k;
		layer.shadowOffset = CGSizeZero;
		[host.layer addSublayer:layer];
		return layer;
	};
	_outline = line(outline);
	_outline.strokeStart = _outline.strokeEnd = 0.5;

	UIBezierPath *wheels = [UIBezierPath bezierPath];
	for (int i = 0; i < 2; i++) {
		CGPoint c = SSPT(350 + (i ? 0.78 : 0.22) * 900, 40 + 0.78 * 420);
		[wheels moveToPoint:CGPointMake(c.x - 55 * k, c.y)];
		[wheels addArcWithCenter:c radius:55 * k startAngle:(CGFloat)M_PI endAngle:0 clockwise:YES];
	}
	_wheels = line(wheels);
	_wheels.opacity = 0;

	_flash = SSGlow(SSPT(350 + 0.96 * 900, 40 + 0.66 * 420), 260 * k, SSRGBA(0xFFFFFF, 0.95), SSRGBA(0xFFFFFF, 0));
	_flash.opacity = 0;
	[host.layer addSublayer:_flash];

	NSInteger period = SSPeriodForDate(self.date ?: [NSDate date]);
	UILabel *greet = [self ss_label:SSGreetingTitle(self.name, period) at:SSPT(800, 545) size:44 weight:UIFontWeightBold color:nil left:NO in:host maxWidth:0];
	[self ss_fade:greet from:2.7 * kt to:3.4 * kt alpha:1];
}

- (void)ss_applyWelcome:(CGFloat)t {
	CGFloat kt = _tempoScale;
	CGFloat p = SSEase(SSSpan(t, 0.2 * kt, 1.8 * kt));
	_outline.strokeStart = 0.5 - p / 2;
	_outline.strokeEnd = 0.5 + p / 2;
	_wheels.opacity = (float)SSSpan(t, 1.6 * kt, 2.2 * kt);
	BOOL flash = (t > 2.2 * kt && t < 2.35 * kt) || (t > 2.5 * kt && t < 2.65 * kt);
	_flash.opacity = flash ? 1 : 0;
	_horizon.opacity = (float)(0.25 * SSSpan(t, 1.2 * kt, 2 * kt));
}

#pragma mark Particles

- (void)ss_buildParticles {
	CGFloat k = _k, w = _sceneSize.width, h = _sceneSize.height;
	UIView *host = [self ss_host];
	[host.layer addSublayer:SSGlow(CGPointMake(w / 2, h / 2), w * 0.45, SSRGBA(0x3C5AC8, 0.25), SSRGBA(0x000000, 0))];
	[self ss_addCanvas];

	// Sample the text into points: render it to an 8-bit alpha bitmap, keep a grid of the inked pixels.
	NSString *text = SSTrimmed(self.name).length ? SSTrimmed(self.name) : @"OmniCar";
	UIFont *font = SSFont(180 * k, UIFontWeightHeavy);
	CGSize ts = [text sizeWithAttributes:@{NSFontAttributeName: font}];
	if (ts.width > w * 0.9 && ts.width > 0) {
		font = SSFont(180 * k * w * 0.9 / ts.width, UIFontWeightHeavy);
		ts = [text sizeWithAttributes:@{NSFontAttributeName: font}];
	}
	size_t bw = (size_t)ceil(ts.width), bh = (size_t)ceil(ts.height);
	if (bw < 2 || bh < 2 || bw > 4096 || bh > 4096) return;
	CGContextRef bitmap = CGBitmapContextCreate(NULL, bw, bh, 8, 0, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
	if (!bitmap) return;
	CGContextTranslateCTM(bitmap, 0, bh);
	CGContextScaleCTM(bitmap, 1, -1);
	UIGraphicsPushContext(bitmap);
	[text drawAtPoint:CGPointZero withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor whiteColor]}];
	UIGraphicsPopContext();
	const uint8_t *pixels = (const uint8_t *)CGBitmapContextGetData(bitmap);
	size_t rowBytes = CGBitmapContextGetBytesPerRow(bitmap);
	NSUInteger inked = 0;
	for (size_t y = 0; pixels && y < bh; y++)
		for (size_t x = 0; x < bw; x++) if (pixels[y * rowBytes + x] > 128) inked++;
	CGFloat step = MAX(1, sqrt(inked / 800.0));
	NSMutableData *points = [NSMutableData data];
	for (CGFloat y = step / 2; pixels && y < bh; y += step) {
		for (CGFloat x = step / 2; x < bw; x += step) {
			if (pixels[(size_t)y * rowBytes + (size_t)x] <= 128) continue;
			CGPoint p = CGPointMake(x, y);
			[points appendBytes:&p length:sizeof(p)];
		}
	}
	CGContextRelease(bitmap);

	NSUInteger found = points.length / sizeof(CGPoint), keep = MIN(found, (NSUInteger)900);
	const CGPoint *pts = (const CGPoint *)points.bytes;
	CGFloat ox = w / 2 - bw / 2.0, oy = h / 2 - 20 * k - bh / 2.0;
	_particles = [NSMutableData dataWithLength:keep * sizeof(SSParticle)];
	SSParticle *parts = (SSParticle *)_particles.mutableBytes;
	for (NSUInteger i = 0; i < keep; i++) {
		CGPoint p = pts[i * found / keep];
		parts[i] = (SSParticle){ox + p.x, oy + p.y, SSRand(-200 * k, w + 200 * k), SSRand(-200 * k, h + 200 * k), SSRand(0, 0.5), SSRand(190, 230)};
	}
	_dot = MAX(1.5, step * 0.55);

	NSInteger period = SSPeriodForDate(self.date ?: [NSDate date]);
	UILabel *greet = [self ss_label:SSGreetingPhrase(period) at:SSPT(800, 500) size:32 weight:UIFontWeightSemibold color:nil left:NO in:_scene maxWidth:0];
	SSFade *fade = [self ss_fade:greet from:2.0 to:2.6 alpha:1];
	if (self.duration > 1.5) {
		fade.outA = self.duration - 0.9;
		fade.outB = self.duration - 0.4;
	}
}

- (void)ss_drawParticles:(CGContextRef)ctx t:(CGFloat)t {
	NSUInteger count = _particles.length / sizeof(SSParticle);
	if (!count) return;
	const SSParticle *parts = (const SSParticle *)_particles.bytes;
	CGFloat k = _k, h = _sceneSize.height, dot = _dot;
	CGFloat leave = self.duration > 1.5 ? SSEase(SSSpan(t, self.duration - 0.9, self.duration - 0.1)) : 0;
	if (leave >= 1) return;
	CGContextSetBlendMode(ctx, kCGBlendModePlusLighter);
	CGFloat rgb[3];
	for (NSUInteger i = 0; i < count; i++) {
		SSParticle p = parts[i];
		CGFloat g = SSOut(SSSpan(t, 0.2 + p.d, 1.8 + p.d));
		CGFloat x = p.sx + (p.tx - p.sx) * g, y = p.sy + (p.ty - p.sy) * g;
		x += (CGFloat)sin(t * 3 + p.tx / k * 0.02) * 1.5 * k * g;
		y += leave * (p.ty - h / 2) * 0.6 - leave * 140 * k;
		CGFloat a = (1 - leave) * (0.35 + 0.65 * g);
		SSHSL(p.hue, 1, 0.70 + 0.30 * (CGFloat)sin(t * 4 + p.tx), rgb);
		CGContextSetRGBFillColor(ctx, rgb[0], rgb[1], rgb[2], a);
		CGContextFillRect(ctx, CGRectMake(x, y, dot, dot));
	}
}

#pragma mark HUD

- (void)ss_buildHud {
	CGFloat k = _k;
	UIView *host = [self ss_host];
	CGPoint c = SSPT(400, 300);
	UIColor *cyan = SSRGBA(0x78DCFF, 0.55);
	const CGFloat radii[] = {210, 170, 130};
	for (int i = 0; i < 3; i++) {
		CGFloat r = radii[i] * k;
		CAShapeLayer *ring = [CAShapeLayer layer];
		ring.bounds = CGRectMake(0, 0, 2 * r, 2 * r);
		ring.position = c;
		ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(r, r) radius:r startAngle:0 endAngle:(CGFloat)(M_PI * 2) clockwise:YES].CGPath;
		ring.fillColor = nil;
		ring.strokeColor = cyan.CGColor;
		ring.lineWidth = MAX(1, (i == 0 ? 3 : 2) * k);
		if (i == 1) ring.lineDashPattern = @[@(6 * k), @(10 * k)];
		if (i == 2) ring.lineDashPattern = @[@(40 * k), @(16 * k)];
		[host.layer addSublayer:ring];
		[_rings addObject:ring];
	}
	// Radar sweep: a conic wedge, bright at its leading edge, turning.
	CGFloat rr = 205 * k;
	CAGradientLayer *radar = [CAGradientLayer layer];
	radar.type = kCAGradientLayerConic;
	radar.bounds = CGRectMake(0, 0, 2 * rr, 2 * rr);
	radar.position = c;
	radar.cornerRadius = rr;
	radar.masksToBounds = YES;
	radar.startPoint = CGPointMake(0.5, 0.5);
	radar.endPoint = CGPointMake(1, 0.5);
	radar.colors = @[(id)SSRGBA(0x78DCFF, 0).CGColor, (id)SSRGBA(0x78DCFF, 0).CGColor, (id)SSRGBA(0x78DCFF, 0.45).CGColor];
	radar.locations = @[@0, @0.88, @1];
	[host.layer addSublayer:radar];
	_radar = radar;

	UIColor *ice = SSRGB(0xAAEBFF);
	_percentLabel = [self ss_label:@"100%" at:c size:64 weight:UIFontWeightHeavy color:ice left:NO in:host maxWidth:0];
	_percentLabel.text = @"0%";

	NSArray<NSDictionary *> *lines = self.hud.count ? self.hud : SSSampleHud(self.carName);
	NSUInteger n = MIN(lines.count, (NSUInteger)5);
	for (NSUInteger i = 0; i < n; i++) {
		NSDictionary *line = [lines[i] isKindOfClass:[NSDictionary class]] ? lines[i] : @{};
		BOOL ok = line[@"ok"] ? [line[@"ok"] boolValue] : YES;
		NSString *text = [line[@"text"] isKindOfClass:[NSString class]] ? line[@"text"] : @"";
		CGFloat y = 150 + i * 62 + (5 - n) * 31;
		UILabel *mark = [self ss_label:(ok ? @"✓" : @"!") at:SSPT(800, y) size:30 weight:UIFontWeightHeavy color:(ok ? SSRGB(0x78FFAA) : SSRGB(0xFFAA3C))
			left:YES in:host maxWidth:0];
		UILabel *label = [self ss_label:text at:SSPT(850, y) size:30 weight:UIFontWeightMedium color:SSRGB(0xDCF0FF) left:YES in:host maxWidth:0];
		[self ss_fade:mark from:0.5 + i * 0.38 to:0.8 + i * 0.38 alpha:1];
		[self ss_fade:label from:0.5 + i * 0.38 to:0.8 + i * 0.38 alpha:1];
	}
	UILabel *ready = [self ss_label:OMCTr(@"SẴN SÀNG", @"READY") at:SSPT(1060, 500) size:56 weight:UIFontWeightHeavy color:ice left:NO in:host maxWidth:0];
	[self ss_fade:ready from:2.6 to:3.1 alpha:1];
}

- (void)ss_applyHud:(CGFloat)t {
	CGFloat grow = MAX(0.001, SSOut(SSSpan(t, 0, 0.8)));
	for (NSUInteger i = 0; i < _rings.count; i++) {
		CAShapeLayer *ring = _rings[i];
		CGFloat angle = (i % 2 ? -1 : 1) * t * (0.6 + i * 0.3);
		ring.transform = CATransform3DScale(CATransform3DMakeRotation(angle, 0, 0, 1), grow, grow, 1);
		ring.strokeEnd = SSOut(SSSpan(t, 0, 1));
	}
	_radar.transform = CATransform3DMakeRotation(t * 3, 0, 0, 1);
	NSInteger percent = (NSInteger)lround(SSOut(SSSpan(t, 0.3, 2.6)) * 100);
	if (percent != _percentShown) {
		_percentShown = percent;
		_percentLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
	}
}

#pragma mark Briefing

- (void)ss_buildBriefing {
	CGFloat k = _k;
	UIView *host = [self ss_host];
	[host.layer addSublayer:SSGlow(SSPT(200, 80), 600 * k, SSRGBA(0xFFBE78, 0.25), SSRGBA(0xFFBE78, 0))];

	NSDate *now = self.date ?: [NSDate date];
	NSInteger period = SSPeriodForDate(now);
	NSMutableArray<NSArray<NSString *> *> *cards = [NSMutableArray array];   // title, subtitle, icon
	[cards addObject:@[SSGreetingTitle(self.name, period), [NSString stringWithFormat:@"%@ · %@", SSTimeText(now), SSDateText(now)], @"👋"]];

	NSDictionary *w = self.weather;
	if (w) {
		NSString *condition = nil;
		NSInteger code = [w[SS_WX_CODE] integerValue];
		BOOL day = [w[SS_WX_DAY] boolValue];
		SSWeatherLook(code, day, NULL, &condition);
		NSMutableArray *detail = [NSMutableArray array];
		if (w[SS_WX_HIGH] && w[SS_WX_LOW])
			[detail addObject:[NSString stringWithFormat:@"↑ %@  ↓ %@", SSTemperatureText(w[SS_WX_HIGH]), SSTemperatureText(w[SS_WX_LOW])]];
		if (w[SS_WX_RAIN])
			[detail addObject:[NSString stringWithFormat:OMCTr(@"%ld%% khả năng mưa", @"%ld%% chance of rain"), (long)[w[SS_WX_RAIN] integerValue]]];
		[cards addObject:@[[NSString stringWithFormat:@"%@ · %@", SSTemperatureText(w[SS_WX_TEMP]), condition],
			detail.count ? [detail componentsJoinedByString:@" · "] : OMCTr(@"Thời tiết hôm nay", @"Today's weather"), SSSkyEmoji(SSSkyFor(code, day))]];
	} else if (self.batteryPercent >= 0) {
		BOOL low = self.batteryPercent < 20;
		[cards addObject:@[[NSString stringWithFormat:OMCTr(@"Pin iPhone %ld%%", @"iPhone battery %ld%%"), (long)self.batteryPercent],
			low ? OMCTr(@"Nhớ cắm sạc trên xe", @"Plug it in on the way") : OMCTr(@"Đủ pin cho chuyến đi", @"Enough for the trip"),
			low ? @"🪫" : @"🔋"]];
	}

	NSDictionary *event = self.nextEvent;
	NSString *eventTitle = [event[@"title"] isKindOfClass:[NSString class]] ? event[@"title"] : nil;
	NSDate *eventDate = [event[@"date"] isKindOfClass:[NSDate class]] ? event[@"date"] : nil;
	if (eventTitle.length) {
		NSString *title = eventDate ? [NSString stringWithFormat:@"%@ %@", eventTitle, SSTimeText(eventDate)] : eventTitle;
		NSString *when = OMCTr(@"Lịch hẹn kế tiếp", @"Next on your calendar");
		if (eventDate) {
			NSInteger minutes = (NSInteger)ceil([eventDate timeIntervalSinceDate:now] / 60.0);
			if (minutes <= 0) when = OMCTr(@"Đang diễn ra", @"Happening now");
			else if (minutes < 60) when = [NSString stringWithFormat:OMCTr(@"Còn %ld phút", @"In %ld min"), (long)minutes];
			else when = [NSString stringWithFormat:OMCTr(@"Còn %ld giờ %ld phút", @"In %ld h %ld min"), (long)(minutes / 60), (long)(minutes % 60)];
		}
		NSString *place = [event[@"location"] isKindOfClass:[NSString class]] ? SSTrimmed(event[@"location"]) : @"";
		if (place.length) when = [NSString stringWithFormat:@"%@ · %@", when, place];
		[cards addObject:@[title, when, @"📅"]];
	}
	[cards addObject:@[OMCTr(@"Thắt dây an toàn", @"Buckle up"), OMCTr(@"Chúc bạn thượng lộ bình an", @"Have a safe trip"), @"🛡"]];

	NSUInteger n = cards.count;
	for (NSUInteger i = 0; i < n; i++) {
		CGFloat x = 70 + (i % 2) * 740, y = 70 + (i / 2) * 240;
		if (n == 3 && i == 2) x = 450;        // last card centered under the first two
		if (n == 2) y = 195;                  // one row, vertically centered
		UIView *card = [[UIView alloc] initWithFrame:CGRectMake(_ox + x * k, _oy + y * k, 700 * k, 210 * k)];
		card.backgroundColor = SSRGBA(0xFFFFFF, 0.08);
		card.layer.cornerRadius = 34 * k;
		card.layer.cornerCurve = kCACornerCurveContinuous;
		card.layer.borderWidth = MAX(0.5, 1.2 * k);
		card.layer.borderColor = SSRGBA(0xFFFFFF, 0.22).CGColor;
		[host addSubview:card];
		[self ss_label:cards[i][2] at:CGPointMake(90 * k, 105 * k) size:70 weight:UIFontWeightRegular color:nil left:NO in:card maxWidth:150 * k];
		[self ss_label:cards[i][0] at:CGPointMake(170 * k, 85 * k) size:40 weight:UIFontWeightBold color:nil left:YES in:card maxWidth:500 * k];
		UILabel *sub = [self ss_label:cards[i][1] at:CGPointMake(170 * k, 140 * k) size:26 weight:UIFontWeightMedium color:nil left:YES in:card maxWidth:500 * k];
		sub.alpha = 0.7;
		SSFade *fade = [self ss_fade:card from:0.3 + i * 0.45 to:0.9 + i * 0.45 alpha:1];
		fade.outEase = YES;
		fade.rise = 40 * k;
	}
}

#pragma mark Liquid (the OmniCar look)

// tools/preview/theme.html part 6: four pastel blobs drifting slowly (lavender, sky, mint, peach), the glass logo rising
// on a spring and breathing, "OmniCar" in the violet -> sky gradient, the slogan under it, a thin loading bar.
- (void)ss_buildLiquid {
	CGFloat k = _k;
	UIView *host = [self ss_host];
	// Blobs: radial glows that drift back and forth (14 s, offset per blob) like the preview's "drift" keyframes
	NSArray *blobs = @[@[@0xB7A6FF, @260, @120, @700], @[@0x8FD3FF, @1350, @170, @650], @[@0x9DF2D8, @1250, @560, @600], @[@0xFFC2D6, @320, @540, @560]];
	NSInteger i = 0;
	for (NSArray *b in blobs) {
		uint32_t rgb = (uint32_t)[b[0] unsignedIntValue];
		CGPoint c = CGPointMake(_ox + [b[1] doubleValue] * k, _oy + [b[2] doubleValue] * k);
		CAGradientLayer *glow = SSGlow(c, [b[3] doubleValue] * k, SSRGBA(rgb, 0.85), SSRGBA(rgb, 0));
		[host.layer addSublayer:glow];
		CABasicAnimation *drift = [CABasicAnimation animationWithKeyPath:@"position"];
		drift.fromValue = [NSValue valueWithCGPoint:c];
		drift.toValue = [NSValue valueWithCGPoint:CGPointMake(c.x + (i % 2 ? -60 : 60) * k, c.y + (i < 2 ? 40 : -40) * k)];
		drift.duration = 14; drift.autoreverses = YES; drift.repeatCount = HUGE_VALF;
		drift.timeOffset = i * 3.5;
		drift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
		[glow addAnimation:drift forKey:@"ssDrift"];
		i++;
	}

	// Logo: the package icon from the settings bundle (same image Settings shows), 300 units, soft violet shadow
	UIImage *logo = [UIImage imageWithContentsOfFile:ROOT_PATH_NS(@"/Library/PreferenceBundles/OmniCarPrefs.bundle/PackageIcon.png")]
		?: [UIImage imageWithContentsOfFile:ROOT_PATH_NS(@"/Library/PreferenceBundles/OmniCarPrefs.bundle/logo@3x.png")];
	CGFloat side = 300 * k;
	UIImageView *logoView = [[UIImageView alloc] initWithImage:logo];
	logoView.contentMode = UIViewContentModeScaleAspectFit;
	logoView.bounds = CGRectMake(0, 0, side, side);
	logoView.center = CGPointMake(_ox + 560 * k, _oy + 300 * k);
	logoView.layer.shadowColor = SSRGB(0x5A50AA).CGColor;
	logoView.layer.shadowOpacity = 0.35; logoView.layer.shadowRadius = 26 * k; logoView.layer.shadowOffset = CGSizeMake(0, 14 * k);
	[host addSubview:logoView];
	SSFade *lf = [self ss_fade:logoView from:0.1 to:0.9 alpha:1];
	lf.rise = 40 * k;
	CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];   // floats +-4 units
	breathe.fromValue = @(4 * k); breathe.toValue = @(-4 * k);
	breathe.duration = 2.4; breathe.autoreverses = YES; breathe.repeatCount = HUGE_VALF; breathe.additive = YES;
	breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	[logoView.layer addAnimation:breathe forKey:@"ssBreathe"];

	// "OmniCar" in the accent gradient: a gradient view masked by the label
	UILabel *name = SSLabel(@"OmniCar");
	name.font = SSFont(110 * k, UIFontWeightHeavy);
	name.textColor = [UIColor blackColor];
	CGSize ns = [name sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
	UIView *nameView = [[UIView alloc] initWithFrame:CGRectMake(_ox + 780 * k, _oy + 215 * k, ceil(ns.width), ceil(ns.height))];
	CAGradientLayer *ink = [CAGradientLayer layer];
	ink.frame = nameView.bounds;
	ink.colors = @[(id)SSRGB(0x6F5CF6).CGColor, (id)SSRGB(0x3B9CF0).CGColor];
	ink.startPoint = CGPointMake(0, 0.5); ink.endPoint = CGPointMake(1, 0.5);
	[nameView.layer addSublayer:ink];
	name.frame = nameView.bounds;
	nameView.maskView = name;
	[host addSubview:nameView];
	SSFade *nf = [self ss_fade:nameView from:0.45 to:1.15 alpha:1];
	nf.rise = 30 * k;

	UILabel *slogan = [self ss_label:OMCTr(@"Sức mạnh của CarPlay", @"The power of CarPlay") at:CGPointMake(_ox + 784 * k, _oy + 355 * k)
	                            size:40 weight:UIFontWeightMedium color:SSRGB(0x6B7090) left:YES in:host maxWidth:700 * k];
	slogan.layer.shadowOpacity = 0;
	SSFade *sf = [self ss_fade:slogan from:0.7 to:1.4 alpha:1];
	sf.rise = 30 * k;

	// Loading bar: thin track, a short accent segment sweeping across (1.6 s, repeats)
	CGFloat bw = 240 * k, bh = MAX(2, 8 * k);
	UIView *track = [[UIView alloc] initWithFrame:CGRectMake(_ox + 680 * k, _oy + 540 * k, bw, bh)];
	track.backgroundColor = SSRGBA(0x1F2233, 0.1);
	track.layer.cornerRadius = bh / 2;
	track.clipsToBounds = YES;
	[host addSubview:track];
	CAGradientLayer *seg = [CAGradientLayer layer];
	seg.frame = CGRectMake(0, 0, bw * 0.4, bh);
	seg.cornerRadius = bh / 2;
	seg.colors = @[(id)SSRGB(0x8B7CFF).CGColor, (id)SSRGB(0x5AB8FF).CGColor];
	seg.startPoint = CGPointMake(0, 0.5); seg.endPoint = CGPointMake(1, 0.5);
	[track.layer addSublayer:seg];
	CABasicAnimation *sweep = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
	sweep.fromValue = @(-bw * 0.4); sweep.toValue = @(bw * 1.04);
	sweep.duration = 1.6; sweep.repeatCount = HUGE_VALF;
	sweep.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0 :0.2 :1];
	[seg addAnimation:sweep forKey:@"ssSweep"];
	[self ss_fade:track from:1.0 to:1.5 alpha:1];
}

#pragma mark Festive

- (void)ss_buildFestive {
	CGFloat k = _k, w = _sceneSize.width, h = _sceneSize.height;
	NSInteger occasion = self.occasion;
	NSString *name = self.name;
	UIView *back = [self ss_host];
	NSString *title = nil, *subtitle = nil, *icon = nil;
	UIColor *titleColor = nil, *subColor = nil;
	CGFloat titleY = 250, titleSize = 96, subY = 360, subSize = 32;

	if (occasion == SS_OCCASION_TET || occasion == SS_OCCASION_NEWYEAR) {
		if (occasion == SS_OCCASION_TET)
			[back.layer addSublayer:SSGlow(CGPointMake(w / 2, h / 2), w * 0.5, SSRGBA(0xFFC83C, 0.25), SSRGBA(0xFFC83C, 0))];
		else
			[back.layer addSublayer:SSGlow(CGPointMake(w / 2, h * 0.35), w * 0.5, SSRGBA(0x3C5AC8, 0.3), SSRGBA(0x3C5AC8, 0))];
		[self ss_addCanvas];   // fireworks
		static const CGFloat hues[kSSBurstCount] = {0, 45, 55, 330, 20, 200, 120};
		_bursts = [NSMutableData dataWithLength:kSSBurstCount * sizeof(SSBurst)];
		SSBurst *bursts = (SSBurst *)_bursts.mutableBytes;
		for (NSInteger i = 0; i < kSSBurstCount; i++)
			bursts[i] = (SSBurst){SSRand(0.125, 0.875) * w, SSRand(0.13, 0.5) * h, 0.3 + i * 0.55, hues[i]};
	}

	switch (occasion) {
		case SS_OCCASION_TET: {
			UIView *front = [self ss_host];
			UIImage *blossom = SSBlossomImage();
			for (int i = 0; i < 36; i++) {
				CGFloat s = SSRand(10, 18) * k;
				CALayer *petal = [CALayer layer];
				petal.contents = (__bridge id)blossom.CGImage;
				petal.bounds = CGRectMake(0, 0, 2.2 * s, 2.2 * s);
				SSMote m = {SSMotePetal, SSRand(0, w), SSRand(-h, 0), SSRand(60, 120) * k, s, SSRand(1, 3), SSRand(0, 6)};
				[self ss_addMote:m layer:petal to:front.layer];
			}
			title = OMCTr(@"Chúc Mừng Năm Mới", @"Happy Lunar New Year");
			subtitle = SSWithName(OMCTr(@"An khang thịnh vượng · thượng lộ bình an, %@", @"Health, luck and safe travels, %@"),
				OMCTr(@"An khang thịnh vượng · thượng lộ bình an", @"Health, luck and safe travels"), name);
			titleColor = SSRGB(0xFFD65C);
			subColor = SSRGB(0xFFECBE);
			break;
		}
		case SS_OCCASION_BIRTHDAY: {
			for (int i = 0; i < 100; i++) {
				CGFloat rgb[3];
				SSHSL(SSRand(0, 360), 0.9, 0.6, rgb);
				CALayer *bit = [CALayer layer];
				bit.backgroundColor = [UIColor colorWithRed:rgb[0] green:rgb[1] blue:rgb[2] alpha:1].CGColor;
				bit.bounds = CGRectMake(0, 0, SSRand(8, 16) * k, 6 * k);
				SSMote m = {SSMoteConfetti, SSRand(0, w), SSRand(-h, 0), SSRand(120, 260) * k, 0, 0, SSRand(0, 6)};
				[self ss_addMote:m layer:bit to:back.layer];
			}
			icon = @"🎂";
			title = SSWithName(OMCTr(@"Chúc mừng sinh nhật, %@!", @"Happy birthday, %@!"), OMCTr(@"Chúc mừng sinh nhật!", @"Happy birthday!"), name);
			subtitle = OMCTr(@"Hôm nay lái xe vui nhé", @"Enjoy the drive today");
			subColor = SSRGB(0xE6DCFF);
			titleY = 330; titleSize = 72; subY = 420; subSize = 30;
			break;
		}
		case SS_OCCASION_XMAS: {
			for (int i = 0; i < 120; i++) {
				CGFloat r = SSRand(1.5, 4.5) * k;
				CALayer *flake = [CALayer layer];
				flake.backgroundColor = SSRGBA(0xFFFFFF, 0.85).CGColor;
				flake.bounds = CGRectMake(0, 0, 2 * r, 2 * r);
				flake.cornerRadius = r;
				SSMote m = {SSMoteSnow, SSRand(0, w), SSRand(0, h), SSRand(30, 70) * k, r, 0, SSRand(0, 6)};
				[self ss_addMote:m layer:flake to:back.layer];
			}
			icon = @"🎄";
			title = OMCTr(@"Giáng Sinh An Lành", @"Merry Christmas");
			subtitle = SSWithName(OMCTr(@"Merry Christmas, %@", @"Happy holidays, %@"), OMCTr(@"Merry Christmas", @"Happy holidays"), name);
			subColor = SSRGB(0xC8E6FF);
			titleY = 340; titleSize = 80; subY = 425; subSize = 30;
			break;
		}
		case SS_OCCASION_MIDAUTUMN: {
			[back.layer addSublayer:SSGlow(SSPT(1300, 160), 160 * k, SSRGBA(0xFFF0BE, 1), SSRGBA(0xFFDC78, 0))];
			for (int i = 0; i < 6; i++) {
				CALayer *lantern = [CALayer layer];
				lantern.bounds = CGRectZero;
				CAGradientLayer *halo = SSGlow(CGPointZero, 90 * k, SSRGBA(0xFFAA50, 0.35), SSRGBA(0xFFAA50, 0));
				[lantern addSublayer:halo];
				CAShapeLayer *body = [CAShapeLayer layer];
				body.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-34 * k, -44 * k, 68 * k, 88 * k)].CGPath;
				body.fillColor = SSRGBA(0xFF7828, 0.9).CGColor;
				[lantern addSublayer:body];
				SSMote m = {SSMoteLantern, SSPT(200 + i * 230, 0).x, 0, 0, 0, 0, i * 90 * k};
				[self ss_addMote:m layer:lantern to:back.layer];
			}
			title = OMCTr(@"Trung Thu Vui Vẻ", @"Happy Mid-Autumn Festival");
			subtitle = SSWithName(OMCTr(@"Trăng tròn, đường thông, %@ nhé", @"Full moon and clear roads, %@"),
				OMCTr(@"Trăng tròn, đường thông", @"Full moon and clear roads"), name);
			titleColor = SSRGB(0xFFE2A0);
			titleY = 300; titleSize = 84; subY = 400; subSize = 30;
			break;
		}
		default: {   // New Year
			NSInteger year = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] component:NSCalendarUnitYear fromDate:self.date ?: [NSDate date]];
			title = [NSString stringWithFormat:OMCTr(@"Chúc mừng năm mới %ld", @"Happy New Year %ld"), (long)year];
			subtitle = SSWithName(OMCTr(@"Thượng lộ bình an, %@", @"Safe travels, %@"), OMCTr(@"Thượng lộ bình an", @"Safe travels"), name);
			titleColor = SSRGB(0xFFE08C);
			subColor = SSRGB(0xDCE6FF);
			titleY = 270; titleSize = 90; subY = 375; subSize = 32;
			break;
		}
	}

	UIView *text = [self ss_host];
	if (icon) {
		UILabel *iconLabel = [self ss_label:icon at:SSPT(800, occasion == SS_OCCASION_XMAS ? 190 : 180) size:120 weight:UIFontWeightRegular color:nil
			left:NO in:text maxWidth:0];
		[self ss_fade:iconLabel from:0.3 to:1 alpha:1].outEase = YES;
	}
	UILabel *titleLabel = [self ss_label:title at:SSPT(800, titleY) size:titleSize weight:UIFontWeightHeavy color:titleColor left:NO in:text maxWidth:0];
	[self ss_fade:titleLabel from:0.8 to:(occasion == SS_OCCASION_TET ? 1.6 : 1.5) alpha:1];
	UILabel *subLabel = [self ss_label:subtitle at:SSPT(800, subY) size:subSize weight:UIFontWeightSemibold color:subColor left:NO in:text maxWidth:0];
	[self ss_fade:subLabel from:(occasion == SS_OCCASION_TET ? 1.4 : 1.3) to:(occasion == SS_OCCASION_TET ? 2.1 : 2.0) alpha:1];
}

- (void)ss_drawFireworks:(CGContextRef)ctx t:(CGFloat)t {
	NSUInteger count = _bursts.length / sizeof(SSBurst);
	if (!count) return;
	const SSBurst *bursts = (const SSBurst *)_bursts.bytes;
	CGFloat k = _k, w = _sceneSize.width, h = _sceneSize.height, dot = MAX(1.5, 3.4 * k);
	CGContextSetBlendMode(ctx, kCGBlendModePlusLighter);
	CGFloat rgb[3];
	for (NSUInteger i = 0; i < count; i++) {
		SSBurst b = bursts[i];
		if (t < b.t) continue;
		CGFloat cycle = (CGFloat)floor((t - b.t) / kSSBurstPeriod);
		CGFloat age = t - b.t - cycle * kSSBurstPeriod;
		if (age > 2) continue;
		if (cycle > 0) {   // a new spot each round
			CGFloat seed = (CGFloat)sin((i + 1) * 12.9898 + cycle * 78.233) * 43758.5453;
			seed -= (CGFloat)floor(seed);
			b.x = (0.125 + 0.75 * seed) * w;
			b.y = (0.13 + 0.37 * SSWrap(seed * 7.31, 1)) * h;
		}
		if (age < 0.4) {   // the rocket going up
			CGFloat y = h - (h - b.y) * SSOut(age / 0.4);
			CGContextSetRGBFillColor(ctx, 1, 240 / 255.0, 200 / 255.0, 0.9);
			CGContextFillRect(ctx, CGRectMake(b.x - 2 * k, y, 4 * k, 14 * k));
			continue;
		}
		CGFloat g = (age - 0.4) / 1.6, r = SSOut(g) * 190 * k;
		SSHSL(b.hue, 1, 0.65, rgb);
		CGContextSetRGBFillColor(ctx, rgb[0], rgb[1], rgb[2], 1 - g);
		for (int j = 0; j < 70; j++) {
			CGFloat a = (CGFloat)(j / 70.0 * M_PI * 2);
			CGFloat x = b.x + (CGFloat)cos(a) * r, y = b.y + (CGFloat)sin(a) * r + g * g * 60 * k;
			CGContextFillEllipseInRect(ctx, CGRectMake(x - dot, y - dot, 2 * dot, 2 * dot));
		}
	}
}

- (void)ss_drawCanvas:(CGContextRef)ctx size:(CGSize)size {
	if (!ctx || !_sceneBuilt) return;
	CGFloat t = [self ss_now];
	if (_particles) [self ss_drawParticles:ctx t:t];
	if (_bursts) [self ss_drawFireworks:ctx t:t];
}

@end

#pragma mark - Settings preview

void SSApplySampleData(SSStartupView *v) {
	if (!v) return;
	if (!v.hud) v.hud = SSSampleHud(v.carName);
	if (!v.nextEvent) v.nextEvent = @{@"title": OMCTr(@"Họp nhóm", @"Team meeting"), @"date": [NSDate dateWithTimeIntervalSinceNow:45 * 60]};
	if (v.batteryPercent < 0) v.batteryPercent = 82;
	if (!v.weather) {
		v.weather = @{SS_WX_TEMP: @24, SS_WX_HIGH: @27, SS_WX_LOW: @22, SS_WX_RAIN: @80, SS_WX_CODE: @61, SS_WX_DAY: @1,
			SS_WX_DATE: [NSDate date]};
	}
}
