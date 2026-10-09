#import "SCPPrefs.h"
#import "common.h"

// Reads the OmniCar prefs domain (written by the settings bundle through cfprefsd); every read
// re-synchronizes so changes apply at once. Values the tweak writes itself (recent layouts, pair
// ratios, app lists) go through CFPreferences into the same domain.
@implementation SCPPrefs

// CarDuo (com.anlai97.carduo) -> OmniCar: the first time the feature runs, copy the old favorites,
// recent layouts, ratios and switches over so nothing is lost by the upgrade.
static void migrateFromCarDuo(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        OMCPrefsSync();
        if (OMCPref(@"splitScreenMigrated", nil)) return;
        CFStringRef old = CFSTR("com.anlai97.carduo");
        CFArrayRef keys = CFPreferencesCopyKeyList(old, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSDictionary *values = keys ? CFBridgingRelease(CFPreferencesCopyMultiple(keys, old, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) : nil;
        if (keys) CFRelease(keys);
        NSDictionary *map = @{
            @"Enabled": SPL_KEY_ENABLED, @"AutoLaunch": SPL_KEY_AUTO_LAUNCH, @"ShowRecent": SPL_KEY_SHOW_RECENT,
            @"ShowFavorites": SPL_KEY_SHOW_FAVORITES, @"TipCount": SPL_KEY_TIP_COUNT, @"SplitRatio": SPL_KEY_SPLIT_RATIO,
            @"SplitDirection": SPL_KEY_SPLIT_DIRECTION, @"PaneOrientation": SPL_KEY_PANE_ORIENTATION,
            @"LastLeft": SPL_KEY_LAST_LEFT, @"LastRight": SPL_KEY_LAST_RIGHT, @"CarPlayApps": SPL_KEY_CARPLAY_APPS,
            @"CarBridgeApps": SPL_KEY_CARBRIDGE_APPS, @"RecentLayouts": SPL_KEY_RECENT_LAYOUTS, @"PairRatios": SPL_KEY_PAIR_RATIOS,
        };
        NSUInteger copied = 0;
        for (NSString *k in values) {
            NSString *target = map[k];
            if (!target && [k hasPrefix:@"Fav"] && k.length > 4) target = [@"splitScreen" stringByAppendingString:k];   // Fav1Left -> splitScreenFav1Left
            if (!target || OMCPref(target, nil)) continue;
            CFPreferencesSetAppValue((__bridge CFStringRef)target, (__bridge CFPropertyListRef)values[k], OMC_PREFS_DOMAIN);
            copied++;
        }
        CFPreferencesSetAppValue(CFSTR("splitScreenMigrated"), kCFBooleanTrue, OMC_PREFS_DOMAIN);
        CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
        if (copied) SCPLog("prefs: chep %lu khoa tu CarDuo", (unsigned long)copied);
    });
}

static id value(NSString *key)
{
    migrateFromCarDuo();
    OMCPrefsSync();
    return OMCPref(key, nil);
}

static void store(NSString *key, id v)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)v, OMC_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

static NSString *str(NSString *key)
{
    id v = value(key);
    return ([v isKindOfClass:[NSString class]] && [v length]) ? v : nil;
}

+ (BOOL)enabled { migrateFromCarDuo(); OMCPrefsSync(); return OMCFeatureEnabled(SPL_FEATURE); }

+ (NSInteger)tipCount            { return [value(SPL_KEY_TIP_COUNT) integerValue]; }
+ (void)setTipCount:(NSInteger)n { store(SPL_KEY_TIP_COUNT, @(n)); }

// Same "language" key as the settings bundle (OMCLanguage); unset -> device language
+ (BOOL)english
{
    NSString *lang = str(@"language");
    if ([lang isEqualToString:@"vi"]) return NO;
    if ([lang isEqualToString:@"en"]) return YES;
    return ![[NSLocale preferredLanguages].firstObject hasPrefix:@"vi"];
}
+ (NSString *)lastLeftApp  { return str(SPL_KEY_LAST_LEFT); }
+ (NSString *)lastRightApp { return str(SPL_KEY_LAST_RIGHT); }
+ (BOOL)autoLaunch         { id v = value(SPL_KEY_AUTO_LAUNCH);    return v ? [v boolValue] : NO; }
+ (BOOL)showRecent         { id v = value(SPL_KEY_SHOW_RECENT);    return v ? [v boolValue] : YES; }
+ (BOOL)showFavorites      { id v = value(SPL_KEY_SHOW_FAVORITES); return v ? [v boolValue] : YES; }
+ (NSInteger)paneOrientation {
    id v = value(SPL_KEY_PANE_ORIENTATION);
    NSInteger o = v ? [v integerValue] : 1;
    return (o == 3 || o == 4) ? 3 : 1;
}
+ (CGFloat)splitRatio {
    id v = value(SPL_KEY_SPLIT_RATIO);
    CGFloat r = v ? [v doubleValue] : 0.5;
    return MIN(0.8, MAX(0.2, r));
}
+ (NSInteger)splitDirection{ id v = value(SPL_KEY_SPLIT_DIRECTION); return v ? [v integerValue] : 0; }
+ (NSArray<NSString *> *)carPlayApps { id v = value(SPL_KEY_CARPLAY_APPS); return [v isKindOfClass:[NSArray class]] ? v : nil; }
+ (void)setCarPlayApps:(NSArray<NSString *> *)ids
{
    if ([[self carPlayApps] isEqualToArray:ids]) return;
    store(SPL_KEY_CARPLAY_APPS, ids);
}
+ (void)setCarBridgeApps:(NSArray<NSString *> *)ids
{
    id old = value(SPL_KEY_CARBRIDGE_APPS);
    if ([old isKindOfClass:[NSArray class]] && [old isEqualToArray:ids]) return;
    store(SPL_KEY_CARBRIDGE_APPS, ids);
}

+ (NSDictionary *)favorite:(NSInteger)index
{
    NSString *left = str(SPL_KEY_FAV(index, @"Left"));
    NSString *right = str(SPL_KEY_FAV(index, @"Right"));
    NSString *third = str(SPL_KEY_FAV(index, @"Third"));
    NSInteger layout = [value(SPL_KEY_FAV(index, @"Layout")) integerValue];
    if (layout != 3 && layout != 13 && layout != 31) { layout = 2; third = nil; }
    if (!left && !right && !third) return nil;
    NSString *name = str(SPL_KEY_FAV(index, @"Name")) ?: [NSString stringWithFormat:@"%@ %ld", [self english] ? @"Layout" : @"Bố cục", (long)index];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObject:name forKey:@"name"];
    if (left) d[@"left"] = left;
    if (right) d[@"right"] = right;
    if (third) d[@"third"] = third;
    d[@"layout"] = @(layout);
    return d;
}

static NSString *pairKey(NSString *left, NSString *right)
{
    return [NSString stringWithFormat:@"%@|%@", left ?: @"-", right ?: @"-"];
}

+ (NSArray<NSDictionary *> *)recentLayouts
{
    NSArray *a = value(SPL_KEY_RECENT_LAYOUTS);
    if (![a isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in a) {
        if (![d isKindOfClass:[NSDictionary class]] || ![d[@"apps"] isKindOfClass:[NSArray class]] || !d[@"layout"]) continue;
        [out addObject:d];
    }
    return out;
}

+ (void)addRecentLayout:(NSInteger)layout apps:(NSArray<NSString *> *)apps
{
    if (apps.count < 2) return;
    NSDictionary *entry = @{@"layout": @(layout), @"apps": apps};
    NSMutableArray *list = [[self recentLayouts] mutableCopy];
    if (list.count && [list[0] isEqualToDictionary:entry]) return;   // khong doi -> khong ghi lai
    // Cung bo cuc + cung bo app (chi khac thu tu, vd vua doi cho 2 o) = 1 cach chia: cap nhat thu tu, khong them muc
    NSSet *set = [NSSet setWithArray:apps];
    for (NSDictionary *d in [list copy])
        if ([d[@"layout"] integerValue] == layout && [[NSSet setWithArray:d[@"apps"]] isEqualToSet:set]) [list removeObject:d];
    [list insertObject:entry atIndex:0];
    while (list.count > 3) [list removeLastObject];
    store(SPL_KEY_RECENT_LAYOUTS, list);
}

+ (CGFloat)ratioForPairLeft:(NSString *)left right:(NSString *)right
{
    NSDictionary *d = value(SPL_KEY_PAIR_RATIOS);
    if (![d isKindOfClass:[NSDictionary class]]) return 0;
    id v = d[pairKey(left, right)];
    return v ? [v doubleValue] : 0;
}

+ (void)setRatio:(CGFloat)ratio forPairLeft:(NSString *)left right:(NSString *)right
{
    NSDictionary *old = value(SPL_KEY_PAIR_RATIOS);
    NSMutableDictionary *d = [old isKindOfClass:[NSDictionary class]] ? [old mutableCopy] : [NSMutableDictionary dictionary];
    d[pairKey(left, right)] = @(ratio);
    store(SPL_KEY_PAIR_RATIOS, d);
}

+ (void)setSplitRatio:(CGFloat)r { store(SPL_KEY_SPLIT_RATIO, @(r)); }
+ (void)setLastPairLeft:(NSString *)left right:(NSString *)right
{
    if (!left.length || !right.length) return;
    if ([left isEqualToString:str(SPL_KEY_LAST_LEFT)] && [right isEqualToString:str(SPL_KEY_LAST_RIGHT)]) return;
    store(SPL_KEY_LAST_LEFT, left);
    store(SPL_KEY_LAST_RIGHT, right);
}

@end
