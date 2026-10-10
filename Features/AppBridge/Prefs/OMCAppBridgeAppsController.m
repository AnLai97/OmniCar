// "Ung dung" cua trang chinh OmniCar: dong "App tren man xe" (OMCAppBridgeAppsLinkCell, hien so app da chon) mo
// OMCAppBridgeAppsController - trang cua App Bridge: cong tac + co app o tren, roi moi app iPhone host duoc voi cong tac
// (muc "Tren man xe" / "App cua ban" / "App he thong") va o tim. App Bridge khong phai mot tinh nang co trang rieng:
// cac key AB_KEY_* deu dat o day. Bundle id da chon luu thanh mang AB_KEY_APPS trong prefs OmniCar; CarPlay
// (SCPCPhoneAppSet, SCPAppIcons) va bang chon app cua Chia man hinh dung dung danh sach nay.
#import <Preferences/PSViewController.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "OMCTheme.h"
#import "../AppBridge.h"

@interface PSViewController (OMCAppBridgeApps)
- (PSSpecifier *)specifier;
@end

@interface UIImage (OMCAppBridgeAppsPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(double)scale;
@end

static id OMCABPref(NSString *key)
{
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain));
}

static void OMCABStore(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
    CFPreferencesAppSynchronize(kPrefsDomain);
    notify_post("com.anlai.omnicar/prefschanged");
}

static NSArray<NSString *> *OMCABChosenApps(void)
{
    CFPreferencesAppSynchronize(kPrefsDomain);
    id v = OMCABPref(AB_KEY_APPS);
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

static id OMCABGet(id obj, NSString *sel)
{
    if (!obj || ![obj respondsToSelector:NSSelectorFromString(sel)]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel));
}

static BOOL OMCABGetBool(id obj, NSString *sel)
{
    if (!obj || ![obj respondsToSelector:NSSelectorFromString(sel)]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel));
}

// App co giao dien CarPlay rieng thi CarPlay tu hien, khong can App Bridge -> khong dua vao danh sach
static BOOL OMCABHasCarPlayEntitlement(id proxy)
{
    NSDictionary *ent = OMCABGet(proxy, @"entitlements");
    if (![ent isKindOfClass:[NSDictionary class]]) return NO;
    for (NSString *k in ent) {
        if ([k hasPrefix:@"com.apple.developer.carplay"] || [k isEqualToString:@"com.apple.developer.playable-content"]) return YES;
    }
    return NO;
}

// Moi app App Bridge host duoc: app nguoi dung cai + app he thong co icon (khong "hidden", mo duoc), tru app co CarPlay.
// @{id, name, system}, xep theo ten
static NSArray<NSDictionary *> *OMCABHostableApps(void)
{
    NSMutableArray *out = [NSMutableArray array];
    Class WS = objc_getClass("LSApplicationWorkspace");
    NSArray *all = OMCABGet(OMCABGet(WS, @"defaultWorkspace"), @"allInstalledApplications");
    NSSet *skip = [NSSet setWithArray:@[@"com.anlai.omnicar.app", @"com.apple.springboard", @"com.apple.CarPlayApp",
                                        @"com.apple.CarPlaySettings", @"com.apple.CarPlayTemplateUIHost", @"com.apple.webapp"]];
    for (id proxy in all) {
        NSString *bid = OMCABGet(proxy, @"bundleIdentifier");
        if (![bid isKindOfClass:[NSString class]] || !bid.length || [skip containsObject:bid]) continue;
        NSString *type = OMCABGet(proxy, @"applicationType");
        BOOL user = [type isEqualToString:@"User"];
        if (!user && ![type isEqualToString:@"System"]) continue;
        NSArray *tags = OMCABGet(proxy, @"appTags");
        if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) continue;
        if (OMCABGetBool(proxy, @"isLaunchProhibited") || OMCABGetBool(proxy, @"isPlaceholder")) continue;
        if (OMCABHasCarPlayEntitlement(proxy)) continue;
        NSString *name = OMCABGet(proxy, @"localizedName");
        if (![name isKindOfClass:[NSString class]] || !name.length) continue;   // app he thong khong ten = khong phai app co icon
        [out addObject:@{@"id": bid, @"name": name, @"system": @(!user)}];
    }
    [out sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
    return out;
}

static UIImage *OMCABIconImage(NSString *bid)
{
    if (![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
    if (!icon) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(36, 36)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 36, 36) cornerRadius:9] addClip];
        [icon drawInRect:CGRectMake(0, 0, 36, 36)];
    }];
}

// ---------------------------------------------------------------------
//  OMCAppBridgeAppsLinkCell: dong "App tren man xe        3 app >" (trang chinh)
// ---------------------------------------------------------------------
@interface OMCAppBridgeAppsLinkCell : PSTableCell
@end

@implementation OMCAppBridgeAppsLinkCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier specifier:specifier];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier
{
    [super refreshCellContentsWithSpecifier:specifier];
    NSUInteger n = OMCABChosenApps().count;
    self.detailTextLabel.text = n ? [L(@"APPBRIDGE_APPS_COUNT") stringByReplacingOccurrencesOfString:@"%ld" withString:[@(n) stringValue]] : L(@"APPBRIDGE_APPS_NONE");
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

@end

// ---------------------------------------------------------------------
//  OMCAppBridgeAppsController
//    muc 0: cong tac App Bridge, co app (slider)
//    muc 1: Tren man xe (da chon)   muc 2: App cua ban   muc 3: App he thong
// ---------------------------------------------------------------------
static char kOMCABBundleKey;
enum { OMCABSectionSettings = 0, OMCABSectionChosen, OMCABSectionUser, OMCABSectionSystem, OMCABSectionCount };

@interface OMCAppBridgeAppsController : PSViewController <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *apps;                      // moi app host duoc, xep theo ten
@property (nonatomic, strong) NSMutableSet<NSString *> *chosen;                   // bundle id dang bat
@property (nonatomic, strong) NSArray<NSDictionary *> *chosenRows, *userRows, *systemRows;   // sau khi loc theo o tim
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *icons;
@property (nonatomic, strong) UILabel *zoomValue;
@end

@implementation OMCAppBridgeAppsController

- (void)loadView
{
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 56;
    self.view = _table;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    OMCLoadStrings();
    self.title = self.specifier.name;
    self.view.tintColor = OMCAccentColor();
    _table.backgroundColor = OMCBackgroundColor();
    _icons = [NSCache new];

    _apps = OMCABHostableApps();
    _chosen = [NSMutableSet setWithArray:OMCABChosenApps()];
    [self rebuildRows];

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = L(@"APPBRIDGE_APPS_SEARCH");
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (BOOL)searching { return _filter.length > 0; }

- (void)rebuildRows
{
    NSMutableArray *on = [NSMutableArray array], *user = [NSMutableArray array], *sys = [NSMutableArray array];
    NSString *q = _filter.length ? _filter : nil;
    for (NSDictionary *a in _apps) {
        if (q && [a[@"name"] rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound
              && [a[@"id"] rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        if ([_chosen containsObject:a[@"id"]]) [on addObject:a];
        else if ([a[@"system"] boolValue]) [sys addObject:a];
        else [user addObject:a];
    }
    _chosenRows = on;
    _userRows = user;
    _systemRows = sys;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    _filter = searchController.searchBar.text;
    [self rebuildRows];
    [_table reloadData];
}

// Luu: chi giu bundle id cua app con cai (app da go thi rot khoi danh sach o lan doi tiep theo)
- (void)setApp:(NSString *)bid on:(BOOL)on
{
    if (on) [_chosen addObject:bid]; else [_chosen removeObject:bid];
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *a in _apps) if ([_chosen containsObject:a[@"id"]]) [ids addObject:a[@"id"]];
    OMCABStore(AB_KEY_APPS, ids);
    // Doi cong tac chay xong animation roi moi chuyen dong sang muc kia
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self rebuildRows];
        [self.table reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(OMCABSectionChosen, OMCABSectionCount - OMCABSectionChosen)]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
    });
}

- (void)switchChanged:(UISwitch *)sw
{
    NSString *bid = objc_getAssociatedObject(sw, &kOMCABBundleKey);
    if ([bid isKindOfClass:[NSString class]]) [self setApp:bid on:sw.on];
}

- (void)enabledChanged:(UISwitch *)sw
{
    OMCABStore(AB_KEY_ENABLED, @(sw.on));
}

- (void)phoneLayoutChanged:(UISwitch *)sw
{
    OMCABStore(AB_KEY_PHONE_LAYOUT, @(sw.on));
}

// Dong cong tac cua muc cai dat: label, icon, key prefs (mac dinh YES), action
- (UITableViewCell *)switchCellIn:(UITableView *)tv reuse:(NSString *)reuse label:(NSString *)label symbol:(NSString *)symbol
                            color:(NSString *)hex key:(NSString *)key defaultOn:(BOOL)defaultOn action:(SEL)action
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:reuse];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = OMCAccentColor();
        [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    OMCStyleCell(c);
    c.textLabel.text = L(label);
    c.imageView.image = OMCIcon(symbol, OMCColorFromHex(hex));
    id v = OMCABPref(key);
    [(UISwitch *)c.accessoryView setOn:(v ? [v boolValue] : defaultOn) animated:NO];
    return c;
}

- (NSInteger)zoomPercent
{
    id v = OMCABPref(AB_KEY_ZOOM);
    NSInteger z = v ? [v integerValue] : 80;
    return MIN(100, MAX(60, z));
}

- (void)zoomMoved:(UISlider *)slider
{
    NSInteger z = (NSInteger)lround(slider.value / 5.0) * 5;   // buoc 5 %
    slider.value = z;
    _zoomValue.text = [NSString stringWithFormat:@"%ld%%", (long)z];
}

- (void)zoomDone:(UISlider *)slider
{
    [self zoomMoved:slider];
    OMCABStore(AB_KEY_ZOOM, @((NSInteger)slider.value));
}

#pragma mark - Table

- (NSArray<NSDictionary *> *)rowsInSection:(NSInteger)s
{
    if (s == OMCABSectionChosen) return _chosenRows;
    if (s == OMCABSectionUser) return _userRows;
    if (s == OMCABSectionSystem) return _systemRows;
    return @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return OMCABSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
    if (section == OMCABSectionSettings) return [self searching] ? 0 : 3;   // cong tac, co app, giao dien dien thoai
    return [self rowsInSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip
{
    return (ip.section == OMCABSectionSettings && ip.row == 1) ? 72 : 56;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
    if (section == OMCABSectionSettings) return nil;
    if (![self rowsInSection:section].count) return nil;
    if (section == OMCABSectionChosen) return L(@"APPBRIDGE_APPS_ON_CAR");
    if (section == OMCABSectionUser) return L(@"APPBRIDGE_APPS_USER");
    return L(@"APPBRIDGE_APPS_SYSTEM");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
    if (section == OMCABSectionSettings)
        return [self searching] ? nil : [NSString stringWithFormat:@"%@\n\n%@\n\n%@", L(@"APPBRIDGE_FOOTER"), L(@"APPBRIDGE_ZOOM_FOOTER"), L(@"APPBRIDGE_PHONE_LAYOUT_FOOTER")];
    if (section == OMCABSectionChosen) return (_chosenRows.count || [self searching]) ? nil : L(@"APPBRIDGE_APPS_FOOTER");
    if (section != OMCABSectionSystem) return nil;
    if (!_apps.count) return L(@"APPBRIDGE_APPS_EMPTY");
    if (!_chosenRows.count && !_userRows.count && !_systemRows.count) return L(@"APPBRIDGE_APPS_NO_MATCH");
    return L(@"APPBRIDGE_APPS_OTHER_FOOTER");
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, YES); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, NO); }

- (UITableViewCell *)settingsCellForRow:(NSInteger)row inTable:(UITableView *)tv
{
    if (row == 0)
        return [self switchCellIn:tv reuse:@"enable" label:@"APPBRIDGE_ENABLE" symbol:@"power" color:@"#0A59F7"
                              key:AB_KEY_ENABLED defaultOn:YES action:@selector(enabledChanged:)];
    if (row == 2)
        return [self switchCellIn:tv reuse:@"phone" label:@"APPBRIDGE_PHONE_LAYOUT" symbol:@"iphone" color:@"#36B37E"
                              key:AB_KEY_PHONE_LAYOUT defaultOn:NO action:@selector(phoneLayoutChanged:)];
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"zoom"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"zoom"];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        UILabel *value = [UILabel new];
        value.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
        value.textColor = [UIColor secondaryLabelColor];
        value.textAlignment = NSTextAlignmentRight;
        value.tag = 1;
        [c.contentView addSubview:value];
        UISlider *slider = [UISlider new];
        slider.minimumValue = 60;
        slider.maximumValue = 100;
        slider.minimumTrackTintColor = OMCAccentColor();
        slider.tag = 2;
        [slider addTarget:self action:@selector(zoomMoved:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(zoomDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [c.contentView addSubview:slider];
    }
    OMCStyleCell(c);
    c.textLabel.text = L(@"APPBRIDGE_ZOOM");
    c.imageView.image = OMCIcon(@"textformat.size", OMCColorFromHex(@"#8A47E8"));
    UILabel *value = [c.contentView viewWithTag:1];
    UISlider *slider = [c.contentView viewWithTag:2];
    _zoomValue = value;
    NSInteger z = [self zoomPercent];
    slider.value = z;
    value.text = [NSString stringWithFormat:@"%ld%%", (long)z];
    CGFloat w = tv.bounds.size.width - 2 * tv.layoutMargins.left;   // be rong cell inset-grouped
    value.frame = CGRectMake(w - 16 - 56, 10, 56, 24);
    slider.frame = CGRectMake(60, 34, w - 60 - 16, 30);
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    if (ip.section == OMCABSectionSettings) return [self settingsCellForRow:ip.row inTable:tv];
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"app"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = OMCAccentColor();
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    OMCStyleCell(c);
    NSDictionary *a = [self rowsInSection:ip.section][ip.row];
    c.textLabel.text = a[@"name"];
    c.detailTextLabel.text = a[@"id"];
    c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    UIImage *icon = [_icons objectForKey:a[@"id"]];
    if (!icon) {
        icon = OMCABIconImage(a[@"id"]);
        if (icon) [_icons setObject:icon forKey:a[@"id"]];
    }
    c.imageView.image = icon;
    UISwitch *sw = (UISwitch *)c.accessoryView;
    objc_setAssociatedObject(sw, &kOMCABBundleKey, a[@"id"], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw setOn:[_chosen containsObject:a[@"id"]] animated:NO];
    return c;
}

// Cham ca dong cung bat / tat
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == OMCABSectionSettings && ip.row == 1) return;
    UISwitch *sw = (UISwitch *)[tv cellForRowAtIndexPath:ip].accessoryView;
    if (![sw isKindOfClass:[UISwitch class]]) return;
    [sw setOn:!sw.on animated:YES];
    if (ip.section != OMCABSectionSettings) [self switchChanged:sw];
    else if (ip.row == 0) [self enabledChanged:sw];
    else [self phoneLayoutChanged:sw];
}

@end
