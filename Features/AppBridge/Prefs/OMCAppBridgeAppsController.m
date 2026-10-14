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
#import "OMCHomeScreenController.h"

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
//  OMCAppBridgeAppsController - noi DUY NHAT quyet dinh app nao tren xe va thu tu
//    muc 0: cong tac App Bridge, Che do lai, Khung hinh app, Man chinh CarPlay > (chi giao dien: luoi, hinh nen, dock)
//    muc 1: Tren man xe = app CarPlay (xe da doc) + app iPhone da chon, theo thu tu HS_KEY_ORDER: keo de sap xep,
//           mat = an (HS_KEY_HIDDEN), ghim = dock (HS_KEY_DOCK), "-" do = bo app iPhone khoi xe (AB_KEY_APPS)
//    muc 2: App cua ban   muc 3: App he thong (cong tac = dua app iPhone len xe)
//  Sap xep / an / ghim chi co tac dung khi bat Man chinh CarPlay (OmniCar ve luoi icon).
// ---------------------------------------------------------------------
#define OMCAB_KEY_CARPLAY_APPS @"splitScreenCarPlayApps"   // = SPL_KEY_CARPLAY_APPS (Split Screen ghi khi cam xe)

static NSArray *OMCABArray(NSString *key)
{
    id v = OMCABPref(key);
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

static NSString *OMCABAppName(NSString *bid)
{
    Class lp = objc_getClass("LSApplicationProxy");
    SEL forId = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id p = [lp respondsToSelector:forId] ? ((id (*)(id, SEL, id))objc_msgSend)(lp, forId, bid) : nil;
    NSString *n = OMCABGet(p, @"localizedName");
    return [n isKindOfClass:[NSString class]] && n.length ? n : bid;
}
static char kOMCABBundleKey;
enum { OMCABSectionSettings = 0, OMCABSectionChosen, OMCABSectionUser, OMCABSectionSystem, OMCABSectionCount };

@interface OMCAppBridgeAppsController : PSViewController <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *apps;                      // moi app host duoc, xep theo ten
@property (nonatomic, strong) NSMutableSet<NSString *> *chosen;                   // bundle id dang bat
@property (nonatomic, strong) NSArray<NSDictionary *> *chosenRows, *userRows, *systemRows;   // sau khi loc theo o tim
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *icons;
@property (nonatomic, strong) NSArray<NSString *> *carplayApps;                  // app CarPlay xe da doc (theo thu tu CarPlay)
@property (nonatomic, strong) NSMutableArray<NSString *> *order;                 // thu tu muc Tren man xe (HS_KEY_ORDER)
@property (nonatomic, strong) NSMutableSet<NSString *> *hidden;                  // HS_KEY_HIDDEN
@property (nonatomic, strong) NSMutableArray<NSString *> *dock;                  // HS_KEY_DOCK
@end

@implementation OMCAppBridgeAppsController

- (void)loadView
{
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 56;
    _table.editing = YES;                     // muc Tren man xe keo duoc; muc khac giu nut (editingAccessoryView)
    _table.allowsSelectionDuringEditing = YES;
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
    _carplayApps = OMCABArray(OMCAB_KEY_CARPLAY_APPS);
    _order = [NSMutableArray array];
    for (NSString *b in OMCABArray(HS_KEY_ORDER)) if ([b isKindOfClass:[NSString class]]) [_order addObject:b];
    _hidden = [NSMutableSet setWithArray:OMCABArray(HS_KEY_HIDDEN)];
    _dock = [NSMutableArray arrayWithArray:OMCABArray(HS_KEY_DOCK)];
    [self rebuildRows];

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = L(@"APPBRIDGE_APPS_SEARCH");
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // Ve tu trang Man chinh CarPlay: dong do hien Bat / Tat moi, dock co the da doi (chip o trang kia)
    CFPreferencesAppSynchronize(kPrefsDomain);
    _dock = [NSMutableArray arrayWithArray:OMCABArray(HS_KEY_DOCK)];
    [self rebuildRows];
    [_table reloadData];
}

- (BOOL)searching { return _filter.length > 0; }

- (BOOL)matches:(NSDictionary *)a
{
    NSString *q = _filter.length ? _filter : nil;
    return !q || [a[@"name"] rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound
              || [a[@"id"] rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// Moi app tren xe theo thu tu nguoi dung: app trong HS_KEY_ORDER truoc, app moi (CarPlay roi iPhone) noi sau
- (NSArray<NSDictionary *> *)onCarApps
{
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (NSString *b in _carplayApps) if ([b isKindOfClass:[NSString class]] && !byId[b]) byId[b] = @{@"id": b, @"name": OMCABAppName(b), @"iphone": @NO};
    for (NSDictionary *a in _apps) if ([_chosen containsObject:a[@"id"]] && !byId[a[@"id"]]) byId[a[@"id"]] = @{@"id": a[@"id"], @"name": a[@"name"], @"iphone": @YES};
    for (NSString *b in _order) if (byId[b] && ![ids containsObject:b]) [ids addObject:b];
    for (NSString *b in _carplayApps) if (byId[b] && ![ids containsObject:b]) [ids addObject:b];
    for (NSDictionary *a in _apps) if (byId[a[@"id"]] && ![ids containsObject:a[@"id"]]) [ids addObject:a[@"id"]];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *b in ids) [out addObject:byId[b]];
    return out;
}

- (void)rebuildRows
{
    NSMutableArray *on = [NSMutableArray array], *user = [NSMutableArray array], *sys = [NSMutableArray array];
    for (NSDictionary *a in [self onCarApps]) if ([self matches:a]) [on addObject:a];
    for (NSDictionary *a in _apps) {
        if (![self matches:a] || [_chosen containsObject:a[@"id"]]) continue;
        if ([a[@"system"] boolValue]) [sys addObject:a];
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
    OMCABStore(sw.tag == 1 ? AB_KEY_DRIVE_MODE : AB_KEY_ENABLED, @(sw.on));
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
    if (section == OMCABSectionSettings) return [self searching] ? 0 : 4;
    return [self rowsInSection:section].count;
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
    if (section == OMCABSectionSettings) return [self searching] ? nil : [NSString stringWithFormat:@"%@\n%@\n%@", L(@"APPBRIDGE_FOOTER"), L(@"APPBRIDGE_DRIVE_FOOTER"), L(@"APPBRIDGE_FPS_FOOTER")];
    if (section == OMCABSectionChosen) return [self searching] ? nil : (_chosenRows.count ? L(@"APPBRIDGE_ONCAR_FOOTER") : L(@"APPBRIDGE_APPS_FOOTER"));
    if (section != OMCABSectionSystem) return nil;
    if (!_apps.count) return L(@"APPBRIDGE_APPS_EMPTY");
    if (!_chosenRows.count && !_userRows.count && !_systemRows.count) return L(@"APPBRIDGE_APPS_NO_MATCH");
    return L(@"APPBRIDGE_APPS_OTHER_FOOTER");
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, YES); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, NO); }

// Khung hinh app iPhone tren xe (AB_KEY_FPS): Toi da / 30 / 24
static NSArray<NSNumber *> *OMCABFpsSteps(void) { return @[@0, @30, @24]; }

- (void)fpsChanged:(UISegmentedControl *)seg
{
    OMCABStore(AB_KEY_FPS, OMCABFpsSteps()[MAX(0, seg.selectedSegmentIndex)]);
}

- (UITableViewCell *)fpsCellInTable:(UITableView *)tv
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"fps"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"fps"];
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[L(@"APPBRIDGE_FPS_MAX"), @"30", @"24"]];
        [seg addTarget:self action:@selector(fpsChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = seg;
        c.editingAccessoryView = seg;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    OMCStyleCell(c);
    c.textLabel.text = L(@"APPBRIDGE_FPS");
    c.textLabel.adjustsFontSizeToFitWidth = YES;
    c.imageView.image = OMCIcon(@"speedometer", OMCColorFromHex(@"#34C759"));
    UISegmentedControl *seg = (UISegmentedControl *)c.accessoryView;
    [seg setTitle:L(@"APPBRIDGE_FPS_MAX") forSegmentAtIndex:0];
    [seg sizeToFit];
    NSUInteger i = [OMCABFpsSteps() indexOfObject:@([OMCABPref(AB_KEY_FPS) intValue])];
    seg.selectedSegmentIndex = i == NSNotFound ? 0 : (NSInteger)i;
    return c;
}

- (UITableViewCell *)settingsCellForRow:(NSInteger)row inTable:(UITableView *)tv
{
    if (row == 2) return [self fpsCellInTable:tv];
    if (row == 3) {   // Man chinh CarPlay: trang rieng (OMCHomeScreenController)
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"home"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"home"];
        OMCStyleCell(c);
        c.textLabel.text = L(@"HOMESCREEN_TITLE");
        c.detailTextLabel.text = L([OMCABPref(HS_KEY_ENABLED) boolValue] ? @"HOMESCREEN_ON" : @"HOMESCREEN_OFF");
        c.imageView.image = OMCIcon(@"square.grid.3x2.fill", OMCColorFromHex(@"#8B7CFF"));
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:row ? @"drive" : @"enable"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:row ? @"drive" : @"enable"];
        UISwitch *sw = [UISwitch new];
        sw.tag = row;   // 0 App Bridge, 1 che do lai
        sw.onTintColor = OMCSwitchColor();
        [sw addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.editingAccessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    OMCStyleCell(c);
    c.textLabel.text = L(row ? @"APPBRIDGE_DRIVE_MODE" : @"APPBRIDGE_ENABLE");
    c.imageView.image = OMCIcon(row ? @"car.fill" : @"power", OMCColorFromHex(row ? @"#FF9500" : @"#0A59F7"));
    id v = OMCABPref(row ? AB_KEY_DRIVE_MODE : AB_KEY_ENABLED);
    [(UISwitch *)c.accessoryView setOn:(v ? [v boolValue] : YES) animated:NO];
    return c;
}

- (UIImage *)iconFor:(NSString *)bid
{
    UIImage *icon = [_icons objectForKey:bid];
    if (!icon) {
        icon = OMCABIconImage(bid);
        if (icon) [_icons setObject:icon forKey:bid];
    }
    return icon;
}

- (UIButton *)rowButton:(NSString *)symbol tint:(UIColor *)tint action:(SEL)sel bundle:(NSString *)bid
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    b.tintColor = tint;
    b.frame = CGRectMake(0, 0, 36, 36);
    objc_setAssociatedObject(b, &kOMCABBundleKey, bid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// Tren man xe: ghim (dock) + mat (an); keo de sap xep; app iPhone co "-" de bo khoi xe
- (UITableViewCell *)onCarCellFor:(NSDictionary *)a inTable:(UITableView *)tv
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"oncar"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"oncar"];
    OMCStyleCell(c);
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    NSString *bid = a[@"id"];
    BOOL hid = [_hidden containsObject:bid], docked = [_dock containsObject:bid];
    c.textLabel.text = a[@"name"];
    c.textLabel.textColor = hid ? [UIColor tertiaryLabelColor] : [UIColor labelColor];
    c.detailTextLabel.text = [a[@"iphone"] boolValue] ? @"iPhone · App Bridge" : @"CarPlay";
    c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    c.imageView.image = [self iconFor:bid];
    c.imageView.alpha = hid ? 0.35 : 1;
    c.showsReorderControl = ![self searching];
    UIStackView *acc = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self rowButton:docked ? @"pin.fill" : @"pin" tint:docked ? OMCAccentColor() : [UIColor secondaryLabelColor] action:@selector(pinTapped:) bundle:bid],
        [self rowButton:hid ? @"eye.slash" : @"eye" tint:[UIColor secondaryLabelColor] action:@selector(eyeTapped:) bundle:bid]]];
    acc.frame = CGRectMake(0, 0, 76, 36);
    acc.spacing = 4;
    c.accessoryView = acc;
    c.editingAccessoryView = acc;
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    if (ip.section == OMCABSectionSettings) return [self settingsCellForRow:ip.row inTable:tv];
    if (ip.section == OMCABSectionChosen) return [self onCarCellFor:_chosenRows[ip.row] inTable:tv];
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"app"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = OMCSwitchColor();
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.editingAccessoryView = sw;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    OMCStyleCell(c);
    NSDictionary *a = [self rowsInSection:ip.section][ip.row];
    c.textLabel.text = a[@"name"];
    c.detailTextLabel.text = a[@"id"];
    c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    c.imageView.image = [self iconFor:a[@"id"]];
    UISwitch *sw = (UISwitch *)c.accessoryView;
    objc_setAssociatedObject(sw, &kOMCABBundleKey, a[@"id"], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw setOn:[_chosen containsObject:a[@"id"]] animated:NO];
    return c;
}

#pragma mark - Tren man xe: sap xep / an / ghim / bo

- (BOOL)isRemovable:(NSIndexPath *)ip
{
    return ip.section == OMCABSectionChosen && ip.row < (NSInteger)_chosenRows.count && [_chosenRows[ip.row][@"iphone"] boolValue];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip
{
    return [self isRemovable:ip] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tv shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip { return [self isRemovable:ip]; }

- (NSString *)tableView:(UITableView *)tv titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip { return L(@"APPBRIDGE_REMOVE"); }

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip
{
    if (style != UITableViewCellEditingStyleDelete || ![self isRemovable:ip]) return;
    [self setApp:_chosenRows[ip.row][@"id"] on:NO];   // ve lai muc App cua ban / App he thong
}

- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return ip.section == OMCABSectionChosen && ![self searching]; }

- (NSIndexPath *)tableView:(UITableView *)tv targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to
{
    if (to.section < OMCABSectionChosen) return [NSIndexPath indexPathForRow:0 inSection:OMCABSectionChosen];
    if (to.section > OMCABSectionChosen) return [NSIndexPath indexPathForRow:_chosenRows.count - 1 inSection:OMCABSectionChosen];
    return to;
}

- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to
{
    NSMutableArray *rows = [_chosenRows mutableCopy];
    NSDictionary *a = rows[from.row];
    [rows removeObjectAtIndex:from.row];
    [rows insertObject:a atIndex:to.row];
    _chosenRows = rows;
    _order = [NSMutableArray array];
    for (NSDictionary *r in rows) [_order addObject:r[@"id"]];
    OMCABStore(HS_KEY_ORDER, [_order copy]);
}

- (void)reloadOnCar
{
    [self rebuildRows];
    [_table reloadSections:[NSIndexSet indexSetWithIndex:OMCABSectionChosen] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)eyeTapped:(UIButton *)b
{
    NSString *bid = objc_getAssociatedObject(b, &kOMCABBundleKey);
    if ([_hidden containsObject:bid]) [_hidden removeObject:bid]; else [_hidden addObject:bid];
    OMCABStore(HS_KEY_HIDDEN, _hidden.allObjects);
    [self reloadOnCar];
}

- (void)pinTapped:(UIButton *)b
{
    NSString *bid = objc_getAssociatedObject(b, &kOMCABBundleKey);
    if ([_dock containsObject:bid]) [_dock removeObject:bid];
    else if (_dock.count < HS_DOCK_MAX) [_dock addObject:bid];
    else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:L(@"HOMESCREEN_DOCK_FULL") preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    OMCABStore(HS_KEY_DOCK, [_dock copy]);
    [self reloadOnCar];
}

// Cham dong co cong tac cung bat / tat; dong Man chinh CarPlay mo trang giao dien
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == OMCABSectionSettings && ip.row == 3) {
        [self.navigationController pushViewController:[OMCHomeScreenController new] animated:YES];
        return;
    }
    if (ip.section == OMCABSectionChosen) return;
    UISwitch *sw = (UISwitch *)[tv cellForRowAtIndexPath:ip].accessoryView;
    if (![sw isKindOfClass:[UISwitch class]]) return;
    [sw setOn:!sw.on animated:YES];
    if (ip.section == OMCABSectionSettings) [self enabledChanged:sw];
    else [self switchChanged:sw];
}

@end
