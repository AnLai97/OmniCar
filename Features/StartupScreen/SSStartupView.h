// Startup Screen renderer - draws one startup style (StartupScreen.h SS_STYLE_*) into a view of any size.
// Built into the tweak (Features/StartupScreen/*.m, shown full screen on the car) and into the settings
// bundle (Prefs/SSStartupViewPrefs.m #imports SSStartupView.m, the live preview card), so the preview
// is exactly what the car shows. Everything scales with the view: one unit = MIN(height / 100, width / 260).
// No CoreLocation / networking here: the weather is fetched by StartupScreen.x and handed in as a dictionary.

#import <UIKit/UIKit.h>

// Weather dictionary (SSWeatherParse, SS_WEATHER_CACHE). Temperatures in degrees Celsius.
#define SS_WX_TEMP  @"temp"     // NSNumber, current temperature
#define SS_WX_HIGH  @"high"     // NSNumber, today's high (may be missing)
#define SS_WX_LOW   @"low"      // NSNumber, today's low (may be missing)
#define SS_WX_RAIN  @"rain"     // NSNumber, today's max chance of rain in % (may be missing)
#define SS_WX_CODE  @"code"     // NSNumber, WMO weather code
#define SS_WX_DAY   @"isDay"    // NSNumber BOOL
#define SS_WX_DATE  @"date"     // NSDate, when it was fetched

#ifdef __cplusplus
extern "C" {
#endif

// Open-Meteo /v1/forecast JSON (current=temperature_2m,weather_code,is_day and
// daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max) -> weather dictionary, nil if unusable.
NSDictionary *SSWeatherParse(id json);
// Newest cached result no older than maxAge seconds (0 = any age), nil when there is none.
NSDictionary *SSWeatherLoadCache(NSTimeInterval maxAge);
// Writes SS_WEATHER_CACHE (or a copy in this process's tmp folder when that is not writable).
void SSWeatherSaveCache(NSDictionary *weather);
// 0 morning (5-11 h), 1 afternoon (11-17 h), 2 evening (17-21 h), 3 night.
NSInteger SSPeriodForDate(NSDate *date);

#ifdef __cplusplus
}
#endif

@interface SSStartupView : UIView
@property (nonatomic, assign) NSInteger style;          // SS_STYLE_*
// Logo style: the logo (nil = a car glyph). Video style (settings preview only): the poster frame.
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, assign) BOOL imageFits;           // Video poster: aspect fit instead of fill
@property (nonatomic, assign) NSInteger logoEffect;     // SS_EFFECT_*
@property (nonatomic, copy) NSString *name;             // greeting name, nil / "" = none
@property (nonatomic, copy) NSDictionary *weather;      // Weather style; nil = draw the greeting instead
@property (nonatomic, strong) NSDate *date;             // clock shown (nil = now)
@property (nonatomic, copy) NSString *carName;          // Engine start / HUD title (nil = "OmniCar")
@property (nonatomic, assign) NSInteger tempo;          // Welcome light: 0 slow, 1 normal, 2 fast
@property (nonatomic, assign) NSInteger occasion;       // SS_OCCASION_* for SS_STYLE_FESTIVE
// HUD lines, in order: @[@{@"text": @"CarPlay connected", @"ok": @YES}] (built by StartupScreen.x from real state;
// nil = sample lines in the settings preview)
@property (nonatomic, copy) NSArray<NSDictionary *> *hud;
// Briefing: next calendar event @{@"title", @"date"} (nil = card left out)
@property (nonatomic, copy) NSDictionary *nextEvent;
@property (nonatomic, assign) NSInteger batteryPercent; // Briefing / HUD (-1 = unknown)
// How long the screen stays up (SS_KEY_DURATION); Particles scatter in its last second. 0 = unknown (no scatter).
@property (nonatomic, assign) NSTimeInterval duration;
// Rebuilds the content for the properties above (call after changing them). Before -playIntro an animated
// style shows a still of its finished scene.
- (void)reload;
// Entrance animation: the logo effect, or the text rising in; animated styles (re)start their timeline from 0.
// Animations only run while the view is in a window.
- (void)playIntro;
@end

#ifdef __cplusplus
extern "C" {
#endif

// Settings preview: fills hud, nextEvent, batteryPercent (when < 0) and weather with sample values where they are
// nil, so every style has something to show. Call before -reload.
void SSApplySampleData(SSStartupView *v);

#ifdef __cplusplus
}
#endif
