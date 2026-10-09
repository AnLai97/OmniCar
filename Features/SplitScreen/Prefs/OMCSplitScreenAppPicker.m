// App picker for the favorite layouts of the Split Screen page: a "Box 1: Maps >" row
// (OMCSplitScreenAppLinkCell) that opens a list of the apps shown on CarPlay (real CarPlay apps
// plus CarBridge apps), OMCSplitScreenAppPickerController. The chosen bundle id is stored under
// the row's key (splitScreenFav<n>Left / Right / Third) in the OmniCar prefs domain.
#import <Preferences/PSViewController.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "OMCTheme.h"
#import "../SplitScreen.h"

@interface PSViewController (OMCSplitPicker)
- (PSSpecifier *)specifier;
@end

@interface UIImage (OMCSplitPickerPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(double)scale;
@end

static id OMCSplitPrefValue(NSString *key)
{
    if (![key isKindOfClass:[NSString class]]) return nil;
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain);
    return v ? CFBridgingRelease(v) : nil;
}

static void OMCSplitSetPrefValue(NSString *key, id value)
{
    if (![key isKindOfClass:[NSString class]]) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
    CFPreferencesAppSynchronize(kPrefsDomain);
}

static NSString *OMCSplitAppName(NSString *bid)
{
    Class LSProxy = objc_getClass("LSApplicationProxy");
    id proxy = LSProxy ? ((id (*)(id, SEL, id))objc_msgSend)(LSProxy, NSSelectorFromString(@"applicationProxyForIdentifier:"), bid) : nil;
    NSString *name = proxy ? ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"localizedName")) : nil;
    return name.length ? name : bid;
}

static UIImage *OMCSplitAppIconImage(NSString *bid)
{
    if (![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
    return [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
}

// Chua cam xe lan nao (CarPlay chua ghi danh sach): tam doan app co CarPlay theo entitlement
static NSArray<NSString *> *OMCSplitGuessCarPlayApps(void)
{
    NSSet *apple = [NSSet setWithArray:@[@"com.apple.Maps", @"com.apple.Music", @"com.apple.podcasts", @"com.apple.mobilephone",
                                         @"com.apple.MobileSMS", @"com.apple.iBooks", @"com.apple.news", @"com.apple.mobilecal"]];
    NSMutableArray *out = [NSMutableArray array];
    Class WS = objc_getClass("LSApplicationWorkspace");
    id ws = WS ? ((id (*)(id, SEL))objc_msgSend)(WS, NSSelectorFromString(@"defaultWorkspace")) : nil;
    NSArray *all = ws ? ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"allInstalledApplications")) : nil;
    for (id proxy in all) {
        NSString *bid = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleIdentifier"));
        if (!bid.length) continue;
        if ([apple containsObject:bid]) { [out addObject:bid]; continue; }
        if (![proxy respondsToSelector:NSSelectorFromString(@"entitlements")]) continue;
        NSDictionary *ent = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"entitlements"));
        for (NSString *k in ent) {
            if ([k hasPrefix:@"com.apple.developer.carplay"] || [k isEqualToString:@"com.apple.developer.playable-content"]) {
                [out addObject:bid];
                break;
            }
        }
    }
    return out;
}

// App bat trong CarBridge: CarBridge luu cau hinh trong 1 file plist co "carbridge" trong ten.
// Khong biet chinh xac dinh dang -> lay moi chuoi la bundle id cua app da cai (khoa co gia tri bat, hoac phan tu mang).
static void OMCSplitCollectBundleIDs(id obj, NSSet *installed, NSMutableOrderedSet *out, int depth)
{
    if (depth > 6 || !obj) return;
    if ([obj isKindOfClass:[NSString class]]) {
        if ([installed containsObject:obj]) [out addObject:obj];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id o in obj) OMCSplitCollectBundleIDs(o, installed, out, depth + 1);
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        [obj enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            BOOL off = [v isKindOfClass:[NSNumber class]] && ![v boolValue];
            if (!off) OMCSplitCollectBundleIDs(k, installed, out, depth + 1);
            OMCSplitCollectBundleIDs(v, installed, out, depth + 1);
        }];
    }
}

static NSArray<NSString *> *OMCSplitCarBridgeApps(void)
{
    NSMutableSet *installed = [NSMutableSet set];
    Class WS = objc_getClass("LSApplicationWorkspace");
    id ws = WS ? ((id (*)(id, SEL))objc_msgSend)(WS, NSSelectorFromString(@"defaultWorkspace")) : nil;
    NSArray *all = ws ? ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"allInstalledApplications")) : nil;
    for (id proxy in all) {
        NSString *bid = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleIdentifier"));
        if (bid.length) [installed addObject:bid];
    }
    NSMutableOrderedSet *out = [NSMutableOrderedSet orderedSet];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in @[@"/var/mobile/Library/Preferences", @"/var/jb/var/mobile/Library/Preferences"]) {
        for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            if (![f.lowercaseString containsString:@"carbridge"] || ![f hasSuffix:@".plist"]) continue;
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
            if (!d) {
                // cfprefsd co the chua ghi file -> doc qua CFPreferences theo ten domain
                NSString *dom = [f stringByDeletingPathExtension];
                CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                if (keys) {
                    d = CFBridgingRelease(CFPreferencesCopyMultiple(keys, (__bridge CFStringRef)dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
                    CFRelease(keys);
                }
            }
            OMCSplitCollectBundleIDs(d, installed, out, 0);
        }
    }
    return out.array;
}

// ---------------------------------------------------------------------
//  OMCSplitScreenAppLinkCell: dong "O 1: Vietmap >" (ten app dang chon o ben phai)
// ---------------------------------------------------------------------
@interface OMCSplitScreenAppLinkCell : PSTableCell
@end

@implementation OMCSplitScreenAppLinkCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier specifier:specifier];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier
{
    [super refreshCellContentsWithSpecifier:specifier];
    NSString *bid = OMCSplitPrefValue([specifier propertyForKey:@"key"]);
    BOOL has = [bid isKindOfClass:[NSString class]] && bid.length;
    self.detailTextLabel.text = has ? OMCSplitAppName(bid) : L(@"SPLITSCREEN_APP_NOT_SET");
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

@end

// ---------------------------------------------------------------------
//  OMCSplitScreenAppPickerController: chi liet ke app hien tren CarPlay (app CarPlay that + app CarBridge)
// ---------------------------------------------------------------------
@interface OMCSplitScreenAppPickerController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *carPlayApps, *bridgeApps;   // @{id, name}
@property (nonatomic, readwrite) BOOL fromCar;   // da co danh sach do CarPlay ghi lai (da cam xe)
@end

@implementation OMCSplitScreenAppPickerController

- (void)loadView
{
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 56;
    self.view = _table;
}

static NSArray<NSDictionary *> *OMCSplitAppRows(NSArray *ids, NSMutableSet *seen)
{
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *bid in ids) {
        if (![bid isKindOfClass:[NSString class]] || [seen containsObject:bid]) continue;
        [seen addObject:bid];
        [rows addObject:@{@"id": bid, @"name": OMCSplitAppName(bid)}];
    }
    [rows sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
    return rows;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    OMCLoadStrings();
    self.title = self.specifier.name;
    self.view.tintColor = OMCAccentColor();
    _table.backgroundColor = OMCBackgroundColor();

    // CarBridge: danh sach CarPlay ghi lai (chinh xac) + doc thang cau hinh CarBridge (chua cam xe van co)
    CFPreferencesAppSynchronize(kPrefsDomain);
    NSArray *carIDs = OMCSplitPrefValue(SPL_KEY_CARPLAY_APPS), *carBridge = OMCSplitPrefValue(SPL_KEY_CARBRIDGE_APPS);
    _fromCar = [carIDs isKindOfClass:[NSArray class]] && carIDs.count;
    NSMutableArray *bridge = [NSMutableArray array];
    if ([carBridge isKindOfClass:[NSArray class]]) [bridge addObjectsFromArray:carBridge];
    [bridge addObjectsFromArray:OMCSplitCarBridgeApps()];
    NSMutableSet *seen = [NSMutableSet set];
    _bridgeApps = OMCSplitAppRows(bridge, seen);

    NSMutableArray *native = [NSMutableArray array];
    if (_fromCar) [native addObjectsFromArray:carIDs];
    [native addObjectsFromArray:OMCSplitGuessCarPlayApps()];
    _carPlayApps = OMCSplitAppRows(native, seen);
}

- (NSString *)currentValue
{
    id v = OMCSplitPrefValue([self.specifier propertyForKey:@"key"]);
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

- (NSArray<NSDictionary *> *)rowsInSection:(NSInteger)s { return s == 1 ? _carPlayApps : _bridgeApps; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 1 : [self rowsInSection:section].count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
    if (section == 1) return L(@"SPLITSCREEN_PICKER_CARPLAY_APPS");
    if (section == 2) return L(@"SPLITSCREEN_PICKER_CARBRIDGE_APPS");
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
    if (section == 1 && !_fromCar)
        return L(@"SPLITSCREEN_PICKER_GUESS_FOOTER");
    if (section == 2)
        return L(_bridgeApps.count ? @"SPLITSCREEN_PICKER_BRIDGE_FOOTER" : @"SPLITSCREEN_PICKER_NO_BRIDGE_FOOTER");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"app"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    c.backgroundColor = OMCCardColor();
    NSString *cur = [self currentValue];
    if (ip.section == 0) {
        c.textLabel.text = L(@"SPLITSCREEN_PICKER_NONE");
        c.detailTextLabel.text = nil;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
        c.imageView.image = [[UIImage systemImageNamed:@"nosign" withConfiguration:cfg] imageWithTintColor:[UIColor tertiaryLabelColor]
                                                                                             renderingMode:UIImageRenderingModeAlwaysOriginal];
        c.accessoryType = cur ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
        return c;
    }
    NSDictionary *a = [self rowsInSection:ip.section][ip.row];
    c.textLabel.text = a[@"name"];
    c.detailTextLabel.text = a[@"id"];
    c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    UIImage *icon = OMCSplitAppIconImage(a[@"id"]);
    if (icon) {
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(36, 36)];
        icon = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 36, 36) cornerRadius:9] addClip];
            [icon drawInRect:CGRectMake(0, 0, 36, 36)];
        }];
    }
    c.imageView.image = icon;
    c.accessoryType = [cur isEqualToString:a[@"id"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSString *key = [self.specifier propertyForKey:@"key"];
    if (![key isKindOfClass:[NSString class]]) return;
    if (ip.section == 0) {
        OMCSplitSetPrefValue(key, nil);
    } else {
        OMCSplitSetPrefValue(key, [self rowsInSection:ip.section][ip.row][@"id"]);
    }
    notify_post("com.anlai.omnicar/prefschanged");
    [tv reloadData];
    id parent = [self respondsToSelector:NSSelectorFromString(@"parentController")] ? ((id (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"parentController")) : nil;
    if ([parent respondsToSelector:@selector(reloadSpecifier:)]) [parent reloadSpecifier:self.specifier];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

@end
