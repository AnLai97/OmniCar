#import "SPPPrefs.h"
#import "common.h"
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
+ (NSInteger)style { id v = value(SB_KEY_STYLE); NSInteger i = v ? [v integerValue] : 0; return (i >= 0 && i < SB_STYLE_COUNT) ? i : 0; }

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

// Canh bao qua toc do: 0 tat, 1 canh bao (vien do, im lang), 2 am thanh (tieng ngan, khong vien), 3 ca hai (mac dinh).
// Gia tri ban cu (chua co SB_KEY_WARN_MODE_V2): 2 = vien + tieng -> 3
+ (NSInteger)warnMode
{
    id v = value(SB_KEY_WARN_MODE);
    NSInteger i = v ? [v integerValue] : 3;
    if (v && i == 2 && ![value(SB_KEY_WARN_MODE_V2) boolValue]) i = 3;
    return (i >= 0 && i <= 3) ? i : 3;
}

static NSInteger ranged(NSString *key, NSInteger def, NSInteger count)
{
    id v = value(key);
    NSInteger i = [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def;
    return (i >= 0 && i < count) ? i : def;
}

+ (NSInteger)warnFx        { return ranged(SB_KEY_WARN_FX, 0, SB_WARN_FX_COUNT); }
+ (BOOL)warnVoice          { return ranged(SB_KEY_WARN_SOUND, 0, 2) == 1; }
+ (NSInteger)warnTone      { return ranged(SB_KEY_WARN_TONE, 0, SB_TONE_COUNT); }
+ (NSInteger)warnVoiceLine { return ranged(SB_KEY_WARN_VOICE, 0, SB_VOICE_CUSTOM + 1); }
+ (NSString *)warnVoiceText { id v = value(SB_KEY_WARN_VOICE_TEXT); return [v isKindOfClass:[NSString class]] ? v : @""; }
+ (NSInteger)color         { return ranged(SB_KEY_COLOR, 0, SB_COLOR_COUNT); }

// Nguong -10..10 km/h (mac dinh 5) so voi gioi han (am = bao tu truoc khi cham gioi han)
+ (double)warnMarginKmh
{
    id v = value(SB_KEY_WARN_OVER);
    double m = v ? round([v doubleValue]) : 5;
    m = MIN(10, MAX(-10, m));
    return m;
}

// Index in SPP_NAV_APPS: Vietmap Live, GOFA, Waze. Chi 1 nguon. Gia tri cua ban 6 nguon (chua co SB_KEY_SOURCE_V2): 4 (Waze)
// -> 2, con lai ngoai 0..1 -> 0 (OMCSpeedBubbleController ghi lai khi mo trang cai dat). Chua chon lan nao: lay tu 2 cong
// tac cu (chi tat Vietmap -> GOFA).
+ (int)source
{
    id v = value(SB_KEY_SOURCE);
    if (v) {
        int i = [v intValue];
        if (![value(SB_KEY_SOURCE_V2) boolValue]) i = (i == 4) ? 2 : (i >= 0 && i <= 1) ? i : 0;
        return (i >= 0 && i < SPP_NAV_APP_COUNT) ? i : 0;
    }
    id vm = value(SB_KEY_APP_VIETMAP), gf = value(SB_KEY_APP_GOFA);
    return (vm && ![vm boolValue] && !(gf && ![gf boolValue])) ? 1 : 0;
}

+ (BOOL)appEnabled:(int)appIndex { return appIndex == [self source]; }

@end
