// App picker for the favorite layouts of the Split Screen page: a "Box 1: Maps >" row
// (OMCSplitScreenAppLinkCell) that opens a list of the apps a box can show (real CarPlay apps, then
// iPhone apps through App Bridge), OMCSplitScreenAppPickerController. The chosen bundle id is stored
// under the row's key (splitScreenFav<n>Left / Right / Third) in the OmniCar prefs domain.
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

static NSArray *OMCSplitInstalledProxies(void)
{
    Class WS = objc_getClass("LSApplicationWorkspace");
    id ws = WS ? ((id (*)(id, SEL))objc_msgSend)(WS, NSSelectorFromString(@"defaultWorkspace")) : nil;
    return ws ? ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"allInstalledApplications")) : nil;
}

// Chua cam xe lan nao (CarPlay chua ghi danh sach): tam doan app co CarPlay theo entitlement
static NSArray<NSString *> *OMCSplitGuessCarPlayApps(void)
{
    NSSet *apple = [NSSet setWithArray:@[@"com.apple.Maps", @"com.apple.Music", @"com.apple.podcasts", @"com.apple.mobilephone",
                                         @"com.apple.MobileSMS", @"com.apple.iBooks", @"com.apple.news", @"com.apple.mobilecal"]];
    NSMutableArray *out = [NSMutableArray array];
    for (id proxy in OMCSplitInstalledProxies()) {
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

// App iPhone App Bridge dua len xe: danh sach chon trong App Bridge > App tren man xe (AB_KEY_APPS), chi app con cai
static NSArray<NSString *> *OMCSplitChosenPhoneApps(void)
{
    id chosen = OMCSplitPrefValue(AB_KEY_APPS);
    if (![chosen isKindOfClass:[NSArray class]] || ![chosen count]) return @[];
    NSSet *want = [NSSet setWithArray:chosen];
    NSMutableArray *out = [NSMutableArray array];
    for (id proxy in OMCSplitInstalledProxies()) {
        NSString *bid = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleIdentifier"));
        if (bid.length && [want containsObject:bid]) [out addObject:bid];
    }
    return out;
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
//  OMCSplitFavCell: dong 1 bo cuc yeu thich tren trang Chia man hinh - ten (hoac goi y), cac app, hinh bo
//  cuc nho co icon app trong tung o (bo cuc + app doc tu splitScreenFav<n>Layout / Left / Right / Third)
// ---------------------------------------------------------------------
static UIImage *OMCSplitLayoutPicture(NSInteger layout, NSArray *apps)
{
    const CGFloat w = 46, h = 29, g = 2;
    NSMutableArray<NSValue *> *boxes = [NSMutableArray array];
    if (layout == 13 || layout == 31) {
        CGFloat mw = floor((w - g) / 2), th = floor((h - g) / 2);
        [boxes addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, mw, h)]];
        [boxes addObject:[NSValue valueWithCGRect:CGRectMake(mw + g, 0, w - mw - g, th)]];
        [boxes addObject:[NSValue valueWithCGRect:CGRectMake(mw + g, th + g, w - mw - g, h - th - g)]];
        if (layout == 31) for (NSUInteger i = 0; i < boxes.count; i++) {
            CGRect b = boxes[i].CGRectValue; b.origin.x = w - CGRectGetMaxX(b); boxes[i] = [NSValue valueWithCGRect:b];
        }
    } else {
        NSInteger n = layout == 3 ? 3 : 2;
        CGFloat bw = (w - g * (n - 1)) / n;
        for (NSInteger i = 0; i < n; i++) [boxes addObject:[NSValue valueWithCGRect:CGRectMake(i * (bw + g), 0, bw, h)]];
    }
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w, h)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        for (NSUInteger i = 0; i < boxes.count; i++) {
            CGRect b = boxes[i].CGRectValue;
            [[UIColor colorWithWhite:0.5 alpha:0.2] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:4] fill];
            NSString *bid = i < apps.count ? apps[i] : nil;
            UIImage *icon = [bid isKindOfClass:[NSString class]] && [bid length] ? OMCSplitAppIconImage(bid) : nil;
            if (!icon) continue;
            CGFloat s = MIN(15, MIN(b.size.width, b.size.height) - 3);
            CGRect ir = CGRectMake(CGRectGetMidX(b) - s / 2, CGRectGetMidY(b) - s / 2, s, s);
            CGContextSaveGState(ctx.CGContext);
            [[UIBezierPath bezierPathWithRoundedRect:ir cornerRadius:s * 0.27] addClip];
            [icon drawInRect:ir];
            CGContextRestoreGState(ctx.CGContext);
        }
    }];
}

@interface OMCSplitFavCell : PSTableCell
@end

@implementation OMCSplitFavCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier
{
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier specifier:specifier];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier
{
    [super refreshCellContentsWithSpecifier:specifier];
    NSInteger n = [[specifier propertyForKey:@"favIndex"] integerValue];
    NSString *prefix = [NSString stringWithFormat:@"splitScreenFav%ld", (long)n];
    id layoutValue = OMCSplitPrefValue([prefix stringByAppendingString:@"Layout"]);
    NSInteger layout = layoutValue ? [layoutValue integerValue] : 2;
    NSInteger count = (layout == 3 || layout == 13 || layout == 31) ? 3 : 2;
    NSMutableArray *apps = [NSMutableArray array], *names = [NSMutableArray array];
    NSArray *suffixes = @[@"Left", @"Right", @"Third"];
    for (NSInteger i = 0; i < count; i++) {
        id bid = OMCSplitPrefValue([prefix stringByAppendingString:suffixes[i]]);
        BOOL has = [bid isKindOfClass:[NSString class]] && [bid length];
        [apps addObject:has ? bid : [NSNull null]];
        if (has) [names addObject:OMCSplitAppName(bid)];
    }
    self.textLabel.text = specifier.name;
    self.detailTextLabel.text = names.count ? [names componentsJoinedByString:@" + "] : L(@"SPLITSCREEN_APP_NOT_SET");
    self.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    self.imageView.image = OMCSplitLayoutPicture(layout, apps);
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

@end

// ---------------------------------------------------------------------
//  OMCSplitScreenAppPickerController: app CarPlay that + app iPhone (App Bridge)
// ---------------------------------------------------------------------
@interface OMCSplitScreenAppPickerController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *carPlayApps, *phoneApps;   // @{id, name}
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

    CFPreferencesAppSynchronize(kPrefsDomain);
    NSArray *carIDs = OMCSplitPrefValue(SPL_KEY_CARPLAY_APPS);
    _fromCar = [carIDs isKindOfClass:[NSArray class]] && carIDs.count;
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *native = [NSMutableArray array];
    if (_fromCar) [native addObjectsFromArray:carIDs];
    [native addObjectsFromArray:OMCSplitGuessCarPlayApps()];
    _carPlayApps = OMCSplitAppRows(native, seen);

    // App iPhone: dung danh sach nguoi dung chon trong App Bridge (cung nguon voi bang chon tren xe)
    _phoneApps = OMCSplitAppRows(OMCSplitChosenPhoneApps(), seen);
}

- (NSString *)currentValue
{
    id v = OMCSplitPrefValue([self.specifier propertyForKey:@"key"]);
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

- (NSArray<NSDictionary *> *)rowsInSection:(NSInteger)s { return s == 1 ? _carPlayApps : _phoneApps; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 1 : [self rowsInSection:section].count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
    if (section == 1) return L(@"SPLITSCREEN_PICKER_CARPLAY_APPS");
    if (section == 2) return L(@"SPLITSCREEN_PICKER_PHONE_APPS");
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
    if (section == 1 && !_fromCar)
        return L(@"SPLITSCREEN_PICKER_GUESS_FOOTER");
    if (section == 2)
        return L(_phoneApps.count ? @"SPLITSCREEN_PICKER_PHONE_FOOTER" : @"SPLITSCREEN_PICKER_NO_PHONE_FOOTER");
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
