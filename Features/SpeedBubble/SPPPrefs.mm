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

// Index in SPP_NAV_APPS: Vietmap Live, GOFA. Chi 1 nguon. Chua chon lan nao: lay tu 2 cong tac cu
// (chi tat Vietmap -> GOFA), giong OMCSpeedBubbleController ghi lai khi mo trang cai dat.
+ (int)source
{
    id v = value(SB_KEY_SOURCE);
    if (v) { int i = [v intValue]; return (i >= 0 && i < SPP_NAV_APP_COUNT) ? i : 0; }
    id vm = value(SB_KEY_APP_VIETMAP), gf = value(SB_KEY_APP_GOFA);
    return (vm && ![vm boolValue] && !(gf && ![gf boolValue])) ? 1 : 0;
}

+ (BOOL)appEnabled:(int)appIndex { return appIndex == [self source]; }

// Ma vung hien tai (vd "VN", "US"); rong neu khong biet
static NSString *regionCode(void)
{
    NSString *cc = [[NSLocale currentLocale] countryCode];
    return cc ? cc.uppercaseString : @"";
}

// Don vi: 0 tu dong (mph khi vung khong dung he met, hoac US/GB/LR/MM - Anh dung he met nhung bien duong ghi mph),
// 1 km/h, 2 mph
+ (BOOL)useMph
{
    id v = value(SB_KEY_UNIT);
    NSInteger i = v ? [v integerValue] : 0;
    if (i == 1) return NO;
    if (i == 2) return YES;
    if (![[NSLocale currentLocale] usesMetricSystem]) return YES;
    return [@[@"US", @"GB", @"LR", @"MM"] containsObject:regionCode()];
}

// Bien gioi han: 0 tu dong (kieu My o US/PR/LR/MM, con lai Vienna), 1 Vienna, 2 My
+ (BOOL)usSign
{
    id v = value(SB_KEY_SIGN);
    NSInteger i = v ? [v integerValue] : 0;
    if (i == 1) return NO;
    if (i == 2) return YES;
    return [@[@"US", @"PR", @"LR", @"MM"] containsObject:regionCode()];
}

@end
