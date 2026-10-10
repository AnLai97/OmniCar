// "Apps on the car screen" of the App Bridge page: a link row (OMCAppBridgeAppsLinkCell, shows how many apps
// are chosen) that opens OMCAppBridgeAppsController, every iPhone app App Bridge can host with a switch and a
// search field. The chosen bundle ids are stored as an array under AB_KEY_APPS in the OmniCar prefs domain;
// the CarPlay side (SCPCPhoneAppSet in SCPCarSplit.mm) and the Split Screen box picker list exactly these apps.
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

static NSArray<NSString *> *OMCABChosenApps(void)
{
    CFPreferencesAppSynchronize(kPrefsDomain);
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)AB_KEY_APPS, kPrefsDomain));
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

static void OMCABStoreChosenApps(NSArray<NSString *> *ids)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)AB_KEY_APPS, (__bridge CFPropertyListRef)ids, kPrefsDomain);
    CFPreferencesAppSynchronize(kPrefsDomain);
    notify_post("com.anlai.omnicar/prefschanged");
}

static id OMCABGet(id obj, NSString *sel)
{
    if (!obj || ![obj respondsToSelector:NSSelectorFromString(sel)]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel));
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

// Moi app App Bridge host duoc: app nguoi dung cai + vai app Apple (AB_APPLE_PHONE_APPS), tru app co CarPlay. @{id, name}, xep theo ten
static NSArray<NSDictionary *> *OMCABHostableApps(void)
{
    NSMutableArray *out = [NSMutableArray array];
    Class WS = objc_getClass("LSApplicationWorkspace");
    NSArray *all = OMCABGet(OMCABGet(WS, @"defaultWorkspace"), @"allInstalledApplications");
    NSSet *apple = [NSSet setWithArray:AB_APPLE_PHONE_APPS];
    for (id proxy in all) {
        NSString *bid = OMCABGet(proxy, @"bundleIdentifier");
        if (![bid isKindOfClass:[NSString class]] || !bid.length || [bid isEqualToString:@"com.anlai.omnicar.app"]) continue;
        NSString *type = OMCABGet(proxy, @"applicationType");
        if (![type isEqualToString:@"User"] && ![apple containsObject:bid]) continue;
        if (OMCABHasCarPlayEntitlement(proxy)) continue;
        NSString *name = OMCABGet(proxy, @"localizedName");
        [out addObject:@{@"id": bid, @"name": ([name isKindOfClass:[NSString class]] && name.length) ? name : bid}];
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
//  OMCAppBridgeAppsLinkCell: dong "App tren man xe        3 app >"
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
//  OMCAppBridgeAppsController: danh sach app iPhone voi cong tac, muc "Tren man xe" roi "App khac"
// ---------------------------------------------------------------------
static char kOMCABBundleKey;

@interface OMCAppBridgeAppsController : PSViewController <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *apps;                      // moi app host duoc, xep theo ten
@property (nonatomic, strong) NSMutableSet<NSString *> *chosen;                   // bundle id dang bat
@property (nonatomic, strong) NSArray<NSDictionary *> *chosenRows, *otherRows;    // sau khi loc theo o tim
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *icons;
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

- (void)rebuildRows
{
    NSMutableArray *on = [NSMutableArray array], *off = [NSMutableArray array];
    NSString *q = _filter.length ? _filter : nil;
    for (NSDictionary *a in _apps) {
        if (q && [a[@"name"] rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound
              && [a[@"id"] rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        [[_chosen containsObject:a[@"id"]] ? on : off addObject:a];
    }
    _chosenRows = on;
    _otherRows = off;
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
    OMCABStoreChosenApps(ids);
    // Doi cong tac chay xong animation roi moi chuyen dong sang muc kia
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self rebuildRows];
        [self.table reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationAutomatic];
    });
}

- (void)switchChanged:(UISwitch *)sw
{
    NSString *bid = objc_getAssociatedObject(sw, &kOMCABBundleKey);
    if ([bid isKindOfClass:[NSString class]]) [self setApp:bid on:sw.on];
}

#pragma mark - Table

- (NSArray<NSDictionary *> *)rowsInSection:(NSInteger)s { return s == 0 ? _chosenRows : _otherRows; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return [self rowsInSection:section].count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
    if (![self rowsInSection:section].count) return nil;
    return L(section == 0 ? @"APPBRIDGE_APPS_ON_CAR" : @"APPBRIDGE_APPS_OTHER");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
    if (section != 1) return nil;
    if (!_apps.count) return L(@"APPBRIDGE_APPS_EMPTY");
    if (!_chosenRows.count && !_otherRows.count) return L(@"APPBRIDGE_APPS_NO_MATCH");
    return L(@"APPBRIDGE_APPS_OTHER_FOOTER");
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, YES); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, NO); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
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
    UISwitch *sw = (UISwitch *)[tv cellForRowAtIndexPath:ip].accessoryView;
    if (![sw isKindOfClass:[UISwitch class]]) return;
    [sw setOn:!sw.on animated:YES];
    [self switchChanged:sw];
}

@end
