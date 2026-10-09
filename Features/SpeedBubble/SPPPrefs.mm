#import "SPPPrefs.h"
#import "SpeedBubble.h"
#import "OmniCar.h"

// Reads the OmniCar prefs domain (written by the settings bundle through cfprefsd); every read
// re-synchronizes so changes apply at once.
@implementation SPPPrefs

static id value(NSString *key)
{
    OMCPrefsSync();
    return OMCPref(key, nil);
}

+ (BOOL)enabled    { OMCPrefsSync(); return OMCFeatureEnabled(SB_FEATURE); }
+ (NSInteger)style { id v = value(SB_KEY_STYLE); NSInteger i = v ? [v integerValue] : 0; return (i >= 0 && i < 18) ? i : 0; }

+ (BOOL)showAppIcon { id v = value(SB_KEY_SHOW_APP_ICON); return v ? [v boolValue] : YES; }

// Size: 60..220 (%), separate for iPhone / CarPlay
+ (double)sizePercentForCar:(BOOL)car
{
    id v = value(car ? SB_KEY_SIZE_CAR : SB_KEY_SIZE_PHONE);
    double p = v ? [v doubleValue] : 100;
    return MIN(220, MAX(60, p));
}

+ (void)setSizePercent:(double)pct forCar:(BOOL)car
{
    NSString *key = car ? SB_KEY_SIZE_CAR : SB_KEY_SIZE_PHONE;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)@(round(MIN(220, MAX(60, pct)))), OMC_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

// Keyed by index in SPP_NAV_APPS: Vietmap Live, GOFA
+ (BOOL)appEnabled:(int)appIndex
{
    static NSArray *keys; static dispatch_once_t once;
    dispatch_once(&once, ^{ keys = @[SB_KEY_APP_VIETMAP, SB_KEY_APP_GOFA]; });
    if (appIndex < 0 || appIndex >= (int)keys.count) return NO;
    id v = value(keys[appIndex]);
    return v ? [v boolValue] : YES;
}

@end
