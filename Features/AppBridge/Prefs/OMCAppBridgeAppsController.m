// "Ung dung" cua trang chinh OmniCar: dong "App tren man xe" (OMCAppBridgeAppsLinkCell, hien so app da chon) mo
// OMCAppBridgeAppsController - MOT trang cho App Bridge + man chinh CarPlay (xem truoc: tools/preview/home.html): app nao
// tren xe (ca app he thong cua CarPlay), thu tu, dock, bo cuc icon, hinh nen. Bundle id app iPhone da chon luu o
// AB_KEY_APPS; CarPlay (SCPCPhoneAppSet, SCPAppIcons) va bang chon app cua Chia man hinh dung dung danh sach nay. Giao
// dien man chinh tren xe: Features/SplitScreen/SCPHomeScreen.mm (HS_KEY_*).
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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "OmniCar.h"

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
//  Dung chung: pref, ten / icon app, hinh nen dung san, xem truoc man xe
// ---------------------------------------------------------------------
static id OMCHSPref(NSString *key, id fallback)
{
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain));
    return v ?: fallback;
}

static void OMCHSStore(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
    CFPreferencesAppSynchronize(kPrefsDomain);
    notify_post("com.anlai.omnicar/prefschanged");
}

static NSString *OMCHSName(NSString *bid)
{
    Class lp = objc_getClass("LSApplicationProxy");
    SEL forId = NSSelectorFromString(@"applicationProxyForIdentifier:"), name = NSSelectorFromString(@"localizedName");
    id proxy = [lp respondsToSelector:forId] ? ((id (*)(id, SEL, id))objc_msgSend)(lp, forId, bid) : nil;
    NSString *n = [proxy respondsToSelector:name] ? ((id (*)(id, SEL))objc_msgSend)(proxy, name) : nil;
    return [n isKindOfClass:[NSString class]] && n.length ? n : bid;
}

static UIImage *OMCHSIcon(NSString *bid, CGFloat side)
{
    static NSCache *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@/%.0f", bid, side];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    if (![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
    if (!icon) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *out = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.225] addClip];
        [icon drawInRect:CGRectMake(0, 0, side, side)];
    }];
    [cache setObject:out forKey:key];
    return out;
}

// ---------------------------------------------------------------------
//  Hinh nen dung san: 6 mau gradient giong tools/preview/home.html (WALLS 1..6). Ve bang Core Graphics theo cach CSS:
//  linear-gradient(<goc>deg) va radial-gradient(circle at x y, mau, trong suot R%) (ban kinh = goc xa nhat).
// ---------------------------------------------------------------------
#define OMCHS_PRESETS 6
#define OMCHS_STYLE_PHOTO 7   // HS_KEY_WALLPAPER_STYLE: 0 mac dinh, 1..6 hinh dung san, 7 anh nguoi dung

static UIColor *OMCHSHex(uint32_t v, CGFloat a) { return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:a]; }

static void OMCHSLinear(CGContextRef c, CGSize s, CGFloat deg, NSArray<UIColor *> *colors, const CGFloat *locs)
{
    CGFloat a = deg * M_PI / 180.0, dx = sin(a), dy = -cos(a);   // CSS: 0deg huong len, 90deg sang phai
    CGFloat len = fabs(s.width * dx) + fabs(s.height * dy);
    CGPoint mid = CGPointMake(s.width / 2, s.height / 2);
    NSMutableArray *cg = [NSMutableArray array];
    for (UIColor *col in colors) [cg addObject:(id)col.CGColor];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cg, locs);
    CGContextDrawLinearGradient(c, g, CGPointMake(mid.x - dx * len / 2, mid.y + dy * len / 2), CGPointMake(mid.x + dx * len / 2, mid.y - dy * len / 2),
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}

static void OMCHSRadial(CGContextRef c, CGSize s, CGFloat fx, CGFloat fy, uint32_t color, CGFloat stop)
{
    CGPoint at = CGPointMake(s.width * fx, s.height * fy);
    CGFloat far = 0;
    for (int i = 0; i < 4; i++) far = MAX(far, hypot(at.x - (i & 1 ? s.width : 0), at.y - (i & 2 ? s.height : 0)));
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)@[(id)OMCHSHex(color, 1).CGColor, (id)OMCHSHex(color, 0).CGColor], (CGFloat[]){0, 1});
    CGContextDrawRadialGradient(c, g, at, 0, at, far * stop, 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}

static UIImage *OMCHSPresetImage(NSInteger i, CGSize size, CGFloat scale)
{
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = scale; f.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:f] imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef c = rc.CGContext;
        switch (i) {
            case 1: OMCHSLinear(c, size, 160, @[OMCHSHex(0x1e3c72, 1), OMCHSHex(0x2a5298, 1), OMCHSHex(0x6dd5ed, 1)], (CGFloat[]){0, 0.45, 1}); break;
            case 2: OMCHSLinear(c, size, 160, @[OMCHSHex(0xff9a8b, 1), OMCHSHex(0xa18cd1, 1), OMCHSHex(0x2b1055, 1)], (CGFloat[]){0, 0.55, 1});
                    OMCHSRadial(c, size, 0.3, 0.2, 0xf9d29d, 0.5); break;
            case 3: OMCHSLinear(c, size, 135, @[OMCHSHex(0xa6ddfd, 1), OMCHSHex(0xfec4d8, 1)], (CGFloat[]){0, 1});
                    OMCHSRadial(c, size, 0.2, 0.8, 0xa0f1d9, 0.45); OMCHSRadial(c, size, 0.7, 0.3, 0xc9baff, 0.45); break;
            case 4: OMCHSLinear(c, size, 180, @[OMCHSHex(0x0f2027, 1), OMCHSHex(0x203a43, 1), OMCHSHex(0x2c5364, 1)], (CGFloat[]){0, 0.5, 1}); break;
            case 5: OMCHSLinear(c, size, 180, @[OMCHSHex(0x0b1026, 1), OMCHSHex(0x2a1a4a, 1)], (CGFloat[]){0, 1});
                    OMCHSRadial(c, size, 0.5, 1.2, 0xff7e5f, 0.55); break;
            default: OMCHSLinear(c, size, 160, @[OMCHSHex(0x134e5e, 1), OMCHSHex(0x71b280, 1)], (CGFloat[]){0, 1}); break;
        }
    }];
}

// ---------------------------------------------------------------------
//  Xem truoc: man xe mo phong (dock trai, luoi icon, hinh nen, cham trang) - cung cach tinh luoi voi SCPHomeScreen.mm
// ---------------------------------------------------------------------
@interface OMCHSPreview : UIView
@property (nonatomic, copy) NSArray<NSString *> *apps;     // da sap xep, da bo app an
@property (nonatomic, copy) NSArray<NSString *> *dock;
@property (nonatomic, strong) UIImage *wallpaper;
@property (nonatomic) NSInteger size, cols, rows, gap, blur, dim;
@property (nonatomic) BOOL names, suggest, on;
@end

@implementation OMCHSPreview
- (instancetype)initWithFrame:(CGRect)f
{
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor blackColor];
        self.layer.cornerRadius = 12;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}
- (void)drawRect:(CGRect)rect
{
    // Man xe 800 x 300 thu nho vua khung
    CGSize s = self.bounds.size;
    CGFloat k = s.width / 800.0;
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(c, k, k);
    CGFloat W = 800, H = s.height / k, dockW = 64;
    CGRect area = CGRectMake(dockW, 0, W - dockW, H);
    if (self.on && self.wallpaper) {
        CGSize is = self.wallpaper.size;
        CGFloat sc = MAX(area.size.width / is.width, area.size.height / is.height);
        CGRect d = CGRectMake(CGRectGetMidX(area) - is.width * sc / 2, CGRectGetMidY(area) - is.height * sc / 2, is.width * sc, is.height * sc);
        CGContextSaveGState(c); CGContextClipToRect(c, area);
        [self.wallpaper drawInRect:d];
        if (self.blur > 0) { [[UIColor colorWithWhite:1 alpha:MIN(0.25, self.blur / 120.0)] setFill]; UIRectFillUsingBlendMode(area, kCGBlendModeNormal); }
        [[UIColor colorWithWhite:0 alpha:self.dim / 100.0] setFill]; UIRectFillUsingBlendMode(area, kCGBlendModeNormal);
        CGContextRestoreGState(c);
    } else {
        [[UIColor colorWithRed:0.1 green:0.11 blue:0.14 alpha:1] setFill]; UIRectFill(area);
    }
    // dock
    [[UIColor colorWithRed:0.06 green:0.07 blue:0.08 alpha:1] setFill]; UIRectFill(CGRectMake(0, 0, dockW, H));
    NSDictionary *ta = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:12], NSForegroundColorAttributeName: [UIColor whiteColor]};
    [@"9:41" drawAtPoint:CGPointMake(17, 8) withAttributes:ta];
    NSArray *dockApps = (self.on && (self.dock.count || !self.suggest)) ? self.dock : @[@"com.apple.Maps", @"com.apple.Music"];
    CGFloat dy = 34;
    for (NSString *b in dockApps) {
        UIImage *ic = OMCHSIcon(b, 42);
        if (ic) [ic drawInRect:CGRectMake(11, dy, 42, 42)];
        dy += 50;
        if (dy > H - 80) break;
    }
    for (int i = 0; i < 6; i++) {   // nut Home: luoi 3 x 2
        [[UIColor colorWithWhite:0.8 alpha:1] setFill];
        UIRectFill(CGRectMake(18 + (i % 3) * 10, H - 30 + (i / 3) * 9, 7, 6));
    }
    if (!self.on) {
        NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:15], NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.6]};
        NSString *t = L(@"HOMESCREEN_PREVIEW_OFF");
        CGSize ts = [t sizeWithAttributes:a];
        [t drawAtPoint:CGPointMake(CGRectGetMidX(area) - ts.width / 2, CGRectGetMidY(area) - ts.height / 2) withAttributes:a];
        return;
    }
    // luoi: giong SCPHomeGridView
    CGFloat side = round(64 * self.size / 100.0), gapX = 26 * self.gap / 100.0, gapY = 14 * self.gap / 100.0;
    CGFloat cellW = side + gapX, cellH = side + (self.names ? 20 : 0), usableH = H - 18;
    NSInteger maxCols = MAX(1, (NSInteger)floor((area.size.width - 16) / cellW)), maxRows = MAX(1, (NSInteger)floor((usableH - 8 + gapY) / (cellH + gapY)));
    NSInteger cols = MIN(self.cols, maxCols), rows = MIN(self.rows, maxRows), per = MAX(1, cols * rows);
    NSInteger pages = MAX(1, ((NSInteger)self.apps.count + per - 1) / per);
    CGFloat gridW = cols * cellW, gridH = rows * cellH + (rows - 1) * gapY;
    NSDictionary *na = @{NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor whiteColor]};
    for (NSInteger i = 0; i < MIN(per, (NSInteger)self.apps.count); i++) {
        NSInteger r = i / cols, col = i % cols;
        CGFloat x = CGRectGetMinX(area) + (area.size.width - gridW) / 2 + col * cellW, y = (usableH - gridH) / 2 + r * (cellH + gapY);
        UIImage *ic = OMCHSIcon(self.apps[i], side);
        CGRect ir = CGRectMake(x + gapX / 2, y, side, side);
        if (ic) [ic drawInRect:ir];
        else { [[UIColor colorWithWhite:1 alpha:0.2] setFill]; [[UIBezierPath bezierPathWithRoundedRect:ir cornerRadius:side * 0.225] fill]; }
        if (self.names) {
            NSString *n = OMCHSName(self.apps[i]);
            CGSize ns = [n sizeWithAttributes:na];
            CGFloat w = MIN(ns.width, cellW);
            [n drawWithRect:CGRectMake(x + (cellW - w) / 2, y + side + 4, w, 16) options:NSStringDrawingTruncatesLastVisibleLine attributes:na context:nil];
        }
    }
    if (pages > 1) {
        CGFloat total = 16 + (pages - 1) * 12, x = CGRectGetMidX(area) - total / 2;
        for (NSInteger p = 0; p < pages; p++) {
            CGFloat w = p == 0 ? 16 : 6;
            [[UIColor colorWithWhite:1 alpha:p == 0 ? 1 : 0.4] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, H - 12, w, 6) cornerRadius:3] fill];
            x += w + 6;
        }
    }
}
@end

// ---------------------------------------------------------------------
//  OMCAppBridgeAppsController - "App tren man xe": MOT trang cho App Bridge + man chinh CarPlay (tools/preview/home.html)
//    0 Xem truoc man xe   1 Man chinh OmniCar (cong tac)
//    2 Ung dung (the gap): loc Tat ca / CarPlay / iPhone, o tim, danh sach CUON RIENG (bang con) moi app - app he thong
//      cua CarPlay, app CarPlay, app iPhone; con mat = hien / an tren xe (app CarPlay: HS_KEY_HIDDEN; app iPhone: AB_KEY_APPS),
//      keo de sap xep (HS_KEY_ORDER), ghim dock (HS_KEY_DOCK)
//    3 Dock   4 Bo cuc icon   5 Hinh nen (the gap, dong thi hien tom tat)
//  An / sap xep app CarPlay can OmniCar ve man chinh: Man chinh OmniCar dang tat thi tu bat + bao.
//  Cai dat App Bridge khac (cong tac, Khung hinh) khong con tren trang: ve mac dinh mot lan (OMCAB_KEY_RESET).
// ---------------------------------------------------------------------
#define OMCAB_KEY_CARPLAY_APPS @"splitScreenCarPlayApps"   // = SPL_KEY_CARPLAY_APPS (Split Screen ghi khi cam xe)
#define OMCAB_KEY_RESET        @"appBridgeAdvancedReset"   // da dua cong tac / Khung hinh ve mac dinh
#define OMCAB_LIST_ROWS        6                           // danh sach app cao toi da 6 dong, cuon ben trong
#define OMCAB_ROW_H            52.0
enum { OMCABPreview = 0, OMCABHome, OMCABApps, OMCABDock, OMCABLayout, OMCABWall, OMCABSectionCount };
enum { OMCABKindSystem = 0, OMCABKindCarPlay, OMCABKindPhone };
static char kOMCABKey;

static NSArray *OMCABArray(NSString *key)
{
    id v = OMCABPref(key);
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

@interface OMCAppBridgeAppsController : PSViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITableView *list;                          // danh sach app trong the Ung dung (cuon rieng)
@property (nonatomic, strong) OMCHSPreview *preview;
@property (nonatomic, strong) NSArray<NSDictionary *> *phoneApps;         // moi app iPhone host duoc (OMCABHostableApps)
@property (nonatomic, strong) NSArray<NSString *> *carplayApps;           // app CarPlay xe da doc (ca app he thong cua Apple)
@property (nonatomic, strong) NSMutableSet<NSString *> *chosen;           // AB_KEY_APPS
@property (nonatomic, strong) NSMutableSet<NSString *> *hidden;           // HS_KEY_HIDDEN
@property (nonatomic, strong) NSMutableArray<NSString *> *order;          // HS_KEY_ORDER
@property (nonatomic, strong) NSMutableArray<NSString *> *dock;           // HS_KEY_DOCK
@property (nonatomic, strong) NSMutableSet<NSNumber *> *open;             // the dang mo
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;              // dong cua danh sach sau khi loc
@property (nonatomic) NSInteger filter;                                   // 0 tat ca, 1 CarPlay, 2 iPhone
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) UIImage *wallpaper, *photo;
@property (nonatomic) NSInteger wallStyle;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *icons;
@end

@implementation OMCAppBridgeAppsController

- (void)loadView
{
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.view = _table;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    OMCLoadStrings();
    self.title = self.specifier.name ?: L(@"APPS_TITLE");
    self.view.tintColor = OMCAccentColor();
    OMCStyleTable(_table);
    _icons = [NSCache new];
    _open = [NSMutableSet setWithObject:@(OMCABApps)];
    [self resetAdvancedOnce];
    [self loadState];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self loadState];   // Siri / sao luu co the da doi
    [_table reloadData];
}

// Cong tac App Bridge, Khung hinh app da bo khoi trang: dua ve mac dinh (bat, toi da) mot lan,
// khong thi ai da tat truoc day se ket o trang thai tat ma khong con cho bat lai
- (void)resetAdvancedOnce
{
    if ([OMCABPref(OMCAB_KEY_RESET) boolValue]) return;
    for (NSString *k in @[AB_KEY_ENABLED, AB_KEY_FPS]) CFPreferencesSetAppValue((__bridge CFStringRef)k, NULL, kPrefsDomain);
    OMCABStore(OMCAB_KEY_RESET, @YES);
}

- (void)loadState
{
    CFPreferencesAppSynchronize(kPrefsDomain);
    if (!_phoneApps) _phoneApps = OMCABHostableApps();
    _carplayApps = OMCABArray(OMCAB_KEY_CARPLAY_APPS);
    _chosen = [NSMutableSet setWithArray:OMCABChosenApps()];
    _hidden = [NSMutableSet setWithArray:OMCABArray(HS_KEY_HIDDEN)];
    _order = [NSMutableArray arrayWithArray:OMCABArray(HS_KEY_ORDER)];
    _dock = [NSMutableArray array];
    for (NSString *b in OMCABArray(HS_KEY_DOCK)) if (_dock.count < HS_DOCK_MAX) [_dock addObject:b];
    _wallpaper = [OMCHSPref(HS_KEY_WALLPAPER, @NO) boolValue] ? [UIImage imageWithContentsOfFile:HS_WALLPAPER_PATH] : nil;
    _photo = [UIImage imageWithContentsOfFile:HS_PHOTO_PATH];
    _wallStyle = _wallpaper ? [self num:HS_KEY_WALLPAPER_STYLE def:7] : 0;
    [self rebuildRows];
}

#pragma mark - App

- (BOOL)isCarPlayApp:(NSString *)bid { return [_carplayApps containsObject:bid]; }
- (BOOL)isVisible:(NSString *)bid { return [self isCarPlayApp:bid] ? ![_hidden containsObject:bid] : [_chosen containsObject:bid]; }

- (NSString *)nameFor:(NSString *)bid
{
    for (NSDictionary *a in _phoneApps) if ([a[@"id"] isEqualToString:bid]) return a[@"name"];
    return OMCHSName(bid);
}

// App dang hien tren xe theo thu tu nguoi dung (dung cho xem truoc, dock, keo sap xep)
- (NSArray<NSString *> *)visibleApps
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *b in _order) if ([b isKindOfClass:[NSString class]] && [self isVisible:b] && ![out containsObject:b]) [out addObject:b];
    for (NSString *b in _carplayApps) if ([self isVisible:b] && ![out containsObject:b]) [out addObject:b];
    for (NSDictionary *a in _phoneApps) if ([self isVisible:a[@"id"]] && ![out containsObject:a[@"id"]]) [out addObject:a[@"id"]];
    return out;
}

// Danh sach: app dang hien (thu tu nguoi dung) -> app CarPlay dang an -> app iPhone chua dua len xe (theo ten); roi loc + tim
- (void)rebuildRows
{
    NSMutableArray *all = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    void (^add)(NSString *) = ^(NSString *b) {
        if (!b.length || [seen containsObject:b]) return;
        [seen addObject:b];
        NSInteger kind = [self isCarPlayApp:b] ? ([b hasPrefix:@"com.apple."] ? OMCABKindSystem : OMCABKindCarPlay) : OMCABKindPhone;
        [all addObject:@{@"id": b, @"name": [self nameFor:b], @"kind": @(kind), @"visible": @([self isVisible:b])}];
    };
    for (NSString *b in [self visibleApps]) add(b);
    for (NSString *b in _order) if ([self isCarPlayApp:b]) add(b);
    for (NSString *b in _carplayApps) add(b);
    for (NSDictionary *a in _phoneApps) add(a[@"id"]);
    NSString *q = _query.length ? _query : nil;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *r in all) {
        NSInteger kind = [r[@"kind"] integerValue];
        if (_filter == 1 && kind == OMCABKindPhone) continue;
        if (_filter == 2 && kind != OMCABKindPhone) continue;
        if (q && [r[@"name"] rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
        [rows addObject:r];
    }
    _rows = rows;
}

- (BOOL)canSort { return _filter == 0 && !_query.length; }   // keo sap xep chi khi xem du danh sach

- (UIImage *)iconFor:(NSString *)bid
{
    UIImage *icon = [_icons objectForKey:bid];
    if (!icon) { icon = OMCABIconImage(bid); if (icon) [_icons setObject:icon forKey:bid]; }
    return icon;
}

// An / sap xep app CarPlay chi co tac dung khi OmniCar ve man chinh: tu bat + bao 1 dong
- (void)ensureHomeOn
{
    if ([OMCHSPref(HS_KEY_ENABLED, @NO) boolValue]) return;
    OMCHSStore(HS_KEY_ENABLED, @YES);
    [self toast:L(@"APPS_AUTO_HOME")];
    [self reloadCard:OMCABHome];
}

- (void)toast:(NSString *)text
{
    UIView *host = self.navigationController.view ?: self.view;
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    l.textColor = [UIColor whiteColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 2;
    l.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    l.layer.cornerRadius = 16;
    l.clipsToBounds = YES;
    CGSize fit = [l sizeThatFits:CGSizeMake(host.bounds.size.width - 64, 60)];
    l.frame = CGRectMake((host.bounds.size.width - fit.width - 28) / 2, host.bounds.size.height - host.safeAreaInsets.bottom - fit.height - 40,
                         fit.width + 28, fit.height + 14);
    [host addSubview:l];
    [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) { [l removeFromSuperview]; }];
}

- (void)eyeTapped:(UIButton *)b
{
    NSString *bid = objc_getAssociatedObject(b, &kOMCABKey);
    BOOL wasVisible = [self isVisible:bid];
    if ([self isCarPlayApp:bid]) {
        if (wasVisible) [_hidden addObject:bid]; else [_hidden removeObject:bid];
        OMCHSStore(HS_KEY_HIDDEN, _hidden.allObjects);
        if (wasVisible) [self ensureHomeOn];
    } else {
        if (wasVisible) [_chosen removeObject:bid]; else [_chosen addObject:bid];
        NSMutableArray *ids = [NSMutableArray array];   // giu thu tu theo ten nhu truoc
        for (NSDictionary *a in _phoneApps) if ([_chosen containsObject:a[@"id"]]) [ids addObject:a[@"id"]];
        OMCABStore(AB_KEY_APPS, ids);
    }
    if (wasVisible && [_dock containsObject:bid]) { [_dock removeObject:bid]; OMCHSStore(HS_KEY_DOCK, [_dock copy]); }
    [self appsChanged];
}

- (void)resetTapped
{
    [_order removeAllObjects];
    [_hidden removeAllObjects];
    OMCHSStore(HS_KEY_ORDER, @[]);
    OMCHSStore(HS_KEY_HIDDEN, @[]);
    [self appsChanged];
}

// Danh sach / so app hien doi: ve lai danh sach, chieu cao the, tom tat, xem truoc
- (void)appsChanged
{
    [self rebuildRows];
    [_list reloadData];
    [_table reloadData];
}

- (void)filterChanged:(UISegmentedControl *)seg
{
    _filter = seg.selectedSegmentIndex;
    [self rebuildRows];
    [_list reloadData];
    [_table beginUpdates]; [_table endUpdates];   // chieu cao danh sach doi, khong ve lai o tim
    [self layoutListCell];
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text
{
    _query = text;
    [self rebuildRows];
    [_list reloadData];
    [_table beginUpdates]; [_table endUpdates];
    [self layoutListCell];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar { [bar resignFirstResponder]; }

- (CGFloat)listHeight { return MAX(1, MIN((NSInteger)_rows.count, OMCAB_LIST_ROWS)) * OMCAB_ROW_H; }

- (void)layoutListCell
{
    CGRect f = _list.frame;
    f.size.height = [self listHeight];
    _list.frame = f;
}

#pragma mark - Xem truoc

- (void)updatePreview
{
    OMCHSPreview *p = self.preview;
    if (!p) return;
    p.apps = [self visibleApps];
    NSMutableArray *dock = [NSMutableArray array];
    for (NSString *b in _dock) if ([self isVisible:b]) [dock addObject:b];
    p.dock = dock;
    p.wallpaper = _wallpaper;
    p.on = [OMCHSPref(HS_KEY_ENABLED, @NO) boolValue];
    p.size = [self num:HS_KEY_ICON_SIZE def:100]; p.cols = [self num:HS_KEY_COLS def:5]; p.rows = [self num:HS_KEY_ROWS def:2];
    p.gap = [self num:HS_KEY_GAP def:100]; p.blur = [self num:HS_KEY_BLUR def:0]; p.dim = [self num:HS_KEY_DIM def:25];
    p.names = [OMCHSPref(HS_KEY_NAMES, @YES) boolValue];
    p.suggest = [OMCHSPref(HS_KEY_DOCK_SUGGEST, @YES) boolValue];
    [p setNeedsDisplay];
}

#pragma mark - The gap

- (BOOL)isOpen:(NSInteger)card { return [_open containsObject:@(card)]; }

- (void)reloadCard:(NSInteger)card
{
    [_table reloadSections:[NSIndexSet indexSetWithIndex:card] withRowAnimation:UITableViewRowAnimationNone];
    if (card != OMCABPreview) [self updatePreview];
}

// Tom tat tren dau the dong (doi khi chinh trong the)
- (NSString *)summaryFor:(NSInteger)card
{
    switch (card) {
        case OMCABApps: {
            NSUInteger total = 0, shown = 0;
            NSMutableSet *ids = [NSMutableSet setWithArray:_carplayApps];
            for (NSDictionary *a in _phoneApps) [ids addObject:a[@"id"]];
            total = ids.count;
            for (NSString *b in ids) if ([self isVisible:b]) shown++;
            return [NSString stringWithFormat:L(@"APPS_SUMMARY"), (long)shown, (long)total];
        }
        case OMCABDock: {
            NSUInteger n = 0;
            for (NSString *b in _dock) if ([self isVisible:b]) n++;
            if (n) return [NSString stringWithFormat:L(@"APPS_DOCK_PINNED"), (long)n];
            return L([OMCHSPref(HS_KEY_DOCK_SUGGEST, @YES) boolValue] ? @"APPS_DOCK_SUGGEST_SHORT" : @"APPS_DOCK_EMPTY");
        }
        case OMCABLayout:
            return [NSString stringWithFormat:@"%ld × %ld · %ld%%", (long)[self num:HS_KEY_COLS def:5], (long)[self num:HS_KEY_ROWS def:2], (long)[self num:HS_KEY_ICON_SIZE def:100]];
        case OMCABWall:
            return L([NSString stringWithFormat:@"APPS_WALL_%ld", (long)MIN(7, MAX(0, _wallStyle))]);
    }
    return nil;
}

- (void)updateHeaders
{
    for (NSNumber *card in @[@(OMCABApps), @(OMCABDock), @(OMCABLayout), @(OMCABWall)]) {
        UITableViewCell *c = [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:card.integerValue]];
        c.detailTextLabel.text = [self summaryFor:card.integerValue];
    }
}

- (UITableViewCell *)headerCellFor:(NSInteger)card inTable:(UITableView *)tv
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"head"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"head"];
    OMCStyleCell(c);
    NSArray *info = @{@(OMCABApps): @[@"APPS_CARD", @"square.grid.2x2.fill", @"#5AB8FF"],
                           @(OMCABDock): @[@"HOMESCREEN_DOCK", @"dock.rectangle", @"#8B7CFF"],
                           @(OMCABLayout): @[@"APPS_LAYOUT", @"square.grid.3x2.fill", @"#2BC79A"],
                           @(OMCABWall): @[@"HOMESCREEN_WALLPAPER", @"photo.fill", @"#FF8A65"]}[@(card)];
    c.textLabel.text = L(info[0]);
    c.imageView.image = OMCIcon(info[1], OMCColorFromHex(info[2]));
    c.detailTextLabel.text = [self summaryFor:card];
    UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self isOpen:card] ? @"chevron.down" : @"chevron.right"]];
    chev.tintColor = [UIColor tertiaryLabelColor];
    c.accessoryView = chev;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    return c;
}

#pragma mark - Bang

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return tv == _list ? 1 : OMCABSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s
{
    if (tv == _list) return MAX(1, (NSInteger)_rows.count);   // 1 dong "khong co app nao khop"
    BOOL o = [self isOpen:s];
    switch (s) {
        case OMCABPreview: case OMCABHome: return 1;
        case OMCABApps: return o ? 4 : 1;     // dau the, loc + tim, danh sach, goi y + Mac dinh
        case OMCABDock: return o ? 3 : 1;     // dau the, chip, goi y CarPlay
        case OMCABLayout: return o ? 6 : 1;   // dau the, co icon, cot, hang, khoang cach, ten
        case OMCABWall: return o ? 5 : 1;     // dau the, o hinh, Tu Anh, do mo, do toi
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    if (tv == _list) return nil;
    if (s == OMCABDock && [self isOpen:s]) return L(@"HOMESCREEN_DOCK_FOOTER");
    if (s == OMCABLayout && [self isOpen:s]) return L(@"HOMESCREEN_GRID_FOOTER");
    if (s == OMCABWall && [self isOpen:s]) return L(@"HOMESCREEN_WALLPAPER_FOOTER");
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { if (tv != _list) OMCStyleHeaderFooter(view, NO); }

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip
{
    if (tv == _list) return OMCAB_ROW_H;
    CGFloat w = tv.bounds.size.width - 40;
    if (ip.section == OMCABPreview) return floor((tv.bounds.size.width - 60) * 300.0 / 800.0) + 20;
    if (ip.section == OMCABHome) return 60;
    if (ip.section == OMCABApps && ip.row == 1) return 50;
    if (ip.section == OMCABApps && ip.row == 2) return [self listHeight];
    if (ip.section == OMCABApps && ip.row == 3) return 40;
    if (ip.section == OMCABDock && ip.row == 1) return [self layoutChipsIn:nil width:w];
    if (ip.section == OMCABWall && ip.row == 1) return [self layoutTilesIn:nil width:w];
    if (ip.section == OMCABWall && ip.row == 2) return 58;
    return 52;
}

- (UITableViewCell *)cellWithId:(NSString *)rid inTable:(UITableView *)tv
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:rid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
    OMCStyleCell(c);
    c.accessoryView = nil; c.editingAccessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.imageView.image = nil; c.detailTextLabel.text = nil;
    c.textLabel.textColor = [UIColor labelColor];
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    if (tv == _list) return [self appCellAt:ip.row];
    if (ip.row == 0 && ip.section >= OMCABApps) return [self headerCellFor:ip.section inTable:tv];
    CGFloat w = tv.bounds.size.width - 40;
    switch (ip.section) {
        case OMCABPreview: {
            UITableViewCell *c = [self cellWithId:@"preview" inTable:tv];
            if (!self.preview || self.preview.superview != c.contentView) {
                [self.preview removeFromSuperview];
                self.preview = [OMCHSPreview new];
                [c.contentView addSubview:self.preview];
            }
            CGFloat pw = tv.bounds.size.width - 60;
            self.preview.frame = CGRectMake(10, 10, pw, floor(pw * 300.0 / 800.0));
            [self updatePreview];
            return c;
        }
        case OMCABHome: {
            UITableViewCell *c = [self cellWithId:@"home" inTable:tv];
            c.textLabel.text = L(@"APPS_HOME");
            c.detailTextLabel.text = L(@"APPS_HOME_SUB");
            c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            c.detailTextLabel.numberOfLines = 2;
            c.imageView.image = OMCIcon(@"square.grid.3x2.fill", OMCColorFromHex(@"#8B7CFF"));
            [self setAccessory:[self switchFor:HS_KEY_ENABLED def:NO] onCell:c];
            return c;
        }
        case OMCABApps: {
            if (ip.row == 1) {   // loc + tim
                UITableViewCell *c = [self cellWithId:@"tools" inTable:tv];
                UIView *box = [self boxInCell:c];
                if (!box.subviews.count) {
                    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[L(@"APPS_ALL"), @"CarPlay", @"iPhone"]];
                    seg.tag = 1;
                    [seg addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
                    [box addSubview:seg];
                    UISearchBar *bar = [UISearchBar new];
                    bar.tag = 2;
                    bar.searchBarStyle = UISearchBarStyleMinimal;
                    bar.placeholder = L(@"APPBRIDGE_APPS_SEARCH");
                    bar.delegate = self;
                    [box addSubview:bar];
                }
                UISegmentedControl *seg = (UISegmentedControl *)[box viewWithTag:1];
                seg.selectedSegmentIndex = _filter;
                [seg sizeToFit];
                seg.frame = CGRectMake(12, 10, seg.bounds.size.width, 30);
                UISearchBar *bar = (UISearchBar *)[box viewWithTag:2];
                bar.text = _query;
                bar.frame = CGRectMake(CGRectGetMaxX(seg.frame) + 2, 3, w - CGRectGetMaxX(seg.frame) - 6, 44);
                return c;
            }
            if (ip.row == 2) {   // danh sach cuon rieng
                UITableViewCell *c = [self cellWithId:@"list" inTable:tv];
                if (!_list) {
                    _list = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
                    _list.dataSource = self;
                    _list.delegate = self;
                    _list.editing = YES;                     // keo sap xep (chi khi xem du danh sach)
                    _list.allowsSelectionDuringEditing = YES;
                    _list.backgroundColor = [UIColor clearColor];
                    _list.rowHeight = OMCAB_ROW_H;
                    _list.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
                }
                if (_list.superview != c.contentView) { [_list removeFromSuperview]; [c.contentView addSubview:_list]; }
                _list.frame = CGRectMake(0, 0, w, [self listHeight]);
                return c;
            }
            UITableViewCell *c = [self cellWithId:@"hint" inTable:tv];   // goi y + Mac dinh
            UIView *box = [self boxInCell:c];
            for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, w - 120, 40)];
            l.text = L(@"APPS_HINT");
            l.font = [UIFont systemFontOfSize:12];
            l.textColor = [UIColor secondaryLabelColor];
            l.adjustsFontSizeToFitWidth = YES;
            [box addSubview:l];
            UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
            [reset setTitle:L(@"APPS_RESET") forState:UIControlStateNormal];
            reset.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            reset.frame = CGRectMake(w - 104, 0, 92, 40);
            reset.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
            [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
            [box addSubview:reset];
            return c;
        }
        case OMCABDock: {
            UITableViewCell *c = [self cellWithId:(ip.row == 1 ? @"chips" : @"dock") inTable:tv];
            if (ip.row == 1) [self layoutChipsIn:[self boxInCell:c] width:w];
            else {
                c.textLabel.text = L(@"HOMESCREEN_DOCK_SUGGEST");
                c.imageView.image = OMCIcon(@"sparkles", OMCColorFromHex(@"#B7A6FF"));
                [self setAccessory:[self switchFor:HS_KEY_DOCK_SUGGEST def:YES] onCell:c];
            }
            return c;
        }
        case OMCABLayout: {
            UITableViewCell *c = [self cellWithId:@"grid" inTable:tv];
            switch (ip.row) {
                case 1: c.textLabel.text = L(@"HOMESCREEN_ICON_SIZE"); c.imageView.image = OMCIcon(@"plus.magnifyingglass", OMCColorFromHex(@"#8B7CFF"));
                        [self setAccessory:[self sliderFor:HS_KEY_ICON_SIZE min:80 max:130 def:100 unit:@"%"] onCell:c]; break;
                case 2: c.textLabel.text = L(@"HOMESCREEN_COLS"); c.imageView.image = OMCIcon(@"rectangle.split.3x1", OMCColorFromHex(@"#5AB8FF"));
                        [self setAccessory:[self stepperFor:HS_KEY_COLS min:3 max:7 def:5] onCell:c]; break;
                case 3: c.textLabel.text = L(@"HOMESCREEN_ROWS"); c.imageView.image = OMCIcon(@"rectangle.split.1x2", OMCColorFromHex(@"#5AB8FF"));
                        [self setAccessory:[self stepperFor:HS_KEY_ROWS min:1 max:3 def:2] onCell:c]; break;
                case 4: c.textLabel.text = L(@"HOMESCREEN_GAP"); c.imageView.image = OMCIcon(@"arrow.left.and.right", OMCColorFromHex(@"#2BC79A"));
                        [self setAccessory:[self sliderFor:HS_KEY_GAP min:60 max:140 def:100 unit:@"%"] onCell:c]; break;
                default: c.textLabel.text = L(@"HOMESCREEN_NAMES"); c.imageView.image = OMCIcon(@"textformat", OMCColorFromHex(@"#FF7FA8"));
                        [self setAccessory:[self switchFor:HS_KEY_NAMES def:YES] onCell:c]; break;
            }
            return c;
        }
    }
    // Hinh nen: o hinh, Tu Anh, do mo, do toi
    UITableViewCell *c = [self cellWithId:(ip.row == 1 ? @"tiles" : @"wall") inTable:tv];
    if (ip.row == 1) { [self layoutTilesIn:[self boxInCell:c] width:w]; return c; }
    if (ip.row == 2) {
        UIButton *b = (UIButton *)[c.contentView viewWithTag:0x50];
        if (!b) {
            b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.tag = 0x50;
            b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            [b setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
            b.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
            b.layer.cornerRadius = 11;
            b.layer.cornerCurve = kCACornerCurveContinuous;
            [b addTarget:self action:@selector(pickPhoto) forControlEvents:UIControlEventTouchUpInside];
            [c.contentView addSubview:b];
        }
        [b setTitle:L(@"HOMESCREEN_FROM_PHOTOS") forState:UIControlStateNormal];
        b.frame = CGRectMake(12, 4, w - 24, 42);
        return c;
    }
    BOOL blur = ip.row == 3;
    c.textLabel.text = L(blur ? @"HOMESCREEN_BLUR" : @"HOMESCREEN_DIM");
    c.imageView.image = OMCIcon(blur ? @"drop.fill" : @"moon.fill", OMCColorFromHex(blur ? @"#5AB8FF" : @"#4A4F80"));
    [self setAccessory:blur ? [self sliderFor:HS_KEY_BLUR min:0 max:30 def:0 unit:@""] : [self sliderFor:HS_KEY_DIM min:0 max:70 def:25 unit:@"%"] onCell:c];
    return c;
}

// Dong app: keo (khi xem du), icon, ten + loai (He thong / CarPlay / iPhone), ghim dock (app dang hien), con mat
- (UITableViewCell *)appCellAt:(NSInteger)row
{
    UITableViewCell *c = [self cellWithId:@"app" inTable:_list];
    c.backgroundColor = [UIColor clearColor];
    if (!_rows.count) {
        c.textLabel.text = L(@"APPBRIDGE_APPS_NO_MATCH");
        c.textLabel.textColor = [UIColor secondaryLabelColor];
        c.showsReorderControl = NO;
        return c;
    }
    NSDictionary *r = _rows[row];
    NSString *bid = r[@"id"];
    BOOL vis = [r[@"visible"] boolValue], docked = [_dock containsObject:bid];
    NSInteger kind = [r[@"kind"] integerValue];
    c.textLabel.text = r[@"name"];
    c.textLabel.textColor = vis ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
    c.detailTextLabel.text = kind == OMCABKindPhone ? @"iPhone" : kind == OMCABKindSystem ? L(@"APPS_SYSTEM") : @"CarPlay";
    c.detailTextLabel.textColor = kind == OMCABKindPhone ? OMCColorFromHex(@"#5B6CF0") : kind == OMCABKindSystem ? [UIColor secondaryLabelColor] : OMCColorFromHex(@"#1F9D6A");
    c.detailTextLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    c.imageView.image = [self iconFor:bid];
    c.imageView.alpha = vis ? 1 : 0.35;
    c.showsReorderControl = vis && [self canSort];
    NSMutableArray *btns = [NSMutableArray array];
    if (vis) [btns addObject:[self smallButton:docked ? @"pin.fill" : @"pin" tint:docked ? OMCAccentColor() : [UIColor secondaryLabelColor] action:@selector(pinTapped:) bundle:bid]];
    [btns addObject:[self smallButton:vis ? @"eye" : @"eye.slash" tint:vis ? OMCAccentColor() : [UIColor tertiaryLabelColor] action:@selector(eyeTapped:) bundle:bid]];
    UIStackView *acc = [[UIStackView alloc] initWithArrangedSubviews:btns];
    acc.frame = CGRectMake(0, 0, 40 * btns.count, 36);
    acc.spacing = 4;
    acc.alignment = UIStackViewAlignmentCenter;
    [self setAccessory:acc onCell:c];
    return c;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tv shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip { return NO; }

- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip
{
    return tv == _list && [self canSort] && ip.row < (NSInteger)_rows.count && [_rows[ip.row][@"visible"] boolValue];
}

// Chi keo trong khoi app dang hien (o dau danh sach)
- (NSIndexPath *)tableView:(UITableView *)tv targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to
{
    NSInteger lastVisible = 0;
    for (NSInteger i = 0; i < (NSInteger)_rows.count; i++) if ([_rows[i][@"visible"] boolValue]) lastVisible = i;
    return [NSIndexPath indexPathForRow:MIN(to.row, lastVisible) inSection:0];
}

- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to
{
    NSMutableArray *rows = [_rows mutableCopy];
    NSDictionary *r = rows[from.row];
    [rows removeObjectAtIndex:from.row];
    [rows insertObject:r atIndex:to.row];
    _rows = rows;
    _order = [NSMutableArray array];
    for (NSDictionary *x in rows) if ([x[@"visible"] boolValue]) [_order addObject:x[@"id"]];
    OMCHSStore(HS_KEY_ORDER, [_order copy]);
    [self ensureHomeOn];
    [self updatePreview];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (tv == _list || ip.row != 0 || ip.section < OMCABApps) return;
    NSNumber *card = @(ip.section);   // dau the: mo / dong
    if ([_open containsObject:card]) [_open removeObject:card]; else [_open addObject:card];
    [self.view endEditing:YES];
    [_table reloadSections:[NSIndexSet indexSetWithIndex:ip.section] withRowAnimation:UITableViewRowAnimationFade];
}

- (NSInteger)num:(NSString *)key def:(NSInteger)def
{
    id v = OMCHSPref(key, nil);
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def;
}

- (void)setAccessory:(UIView *)v onCell:(UITableViewCell *)c { c.accessoryView = v; c.editingAccessoryView = v; }

- (UISwitch *)switchFor:(NSString *)key def:(BOOL)def
{
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = OMCSwitchColor();
    sw.on = [OMCHSPref(key, @(def)) boolValue];
    objc_setAssociatedObject(sw, &kOMCABKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (void)switchChanged:(UISwitch *)sw
{
    NSString *key = objc_getAssociatedObject(sw, &kOMCABKey);
    OMCHSStore(key, @(sw.on));
    if ([key isEqualToString:HS_KEY_ENABLED]) [self reloadCard:OMCABPreview];
    [self updatePreview];
}

- (UIView *)sliderFor:(NSString *)key min:(NSInteger)mn max:(NSInteger)mx def:(NSInteger)def unit:(NSString *)unit
{
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 32)];
    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 32)];
    sl.minimumValue = mn; sl.maximumValue = mx; sl.value = [self num:key def:def];
    sl.minimumTrackTintColor = OMCAccentColor();
    UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(154, 0, 46, 32)];
    v.textAlignment = NSTextAlignmentRight;
    v.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    v.textColor = [UIColor secondaryLabelColor];
    v.text = [NSString stringWithFormat:@"%ld%@", (long)sl.value, unit];
    objc_setAssociatedObject(sl, &kOMCABKey, @[key, unit, v], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sl addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
    [sl addTarget:self action:@selector(sliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [box addSubview:sl];
    [box addSubview:v];
    return box;
}

- (void)sliderMoved:(UISlider *)sl
{
    NSArray *info = objc_getAssociatedObject(sl, &kOMCABKey);
    ((UILabel *)info[2]).text = [NSString stringWithFormat:@"%ld%@", (long)lround(sl.value), info[1]];
    CFPreferencesSetAppValue((__bridge CFStringRef)info[0], (__bridge CFPropertyListRef)@(lround(sl.value)), kPrefsDomain);   // xem truoc ngay
    [self updatePreview];
}

- (void)sliderDone:(UISlider *)sl
{
    NSArray *info = objc_getAssociatedObject(sl, &kOMCABKey);
    OMCHSStore(info[0], @(lround(sl.value)));   // tha tay moi bao xe (khong ve lai luoi tren xe moi buoc truot)
    [self updateHeaders];
}

- (UIView *)stepperFor:(NSString *)key min:(NSInteger)mn max:(NSInteger)mx def:(NSInteger)def
{
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 130, 32)];
    UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 28, 32)];
    v.textAlignment = NSTextAlignmentCenter;
    v.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightSemibold];
    v.text = [@([self num:key def:def]) stringValue];
    UIStepper *st = [UIStepper new];
    st.minimumValue = mn; st.maximumValue = mx; st.value = [self num:key def:def];
    st.frame = CGRectMake(34, 0, st.frame.size.width, 32);
    objc_setAssociatedObject(st, &kOMCABKey, @[key, v], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [st addTarget:self action:@selector(stepped:) forControlEvents:UIControlEventValueChanged];
    box.frame = CGRectMake(0, 0, CGRectGetMaxX(st.frame), 32);
    [box addSubview:v];
    [box addSubview:st];
    return box;
}

- (void)stepped:(UIStepper *)st
{
    NSArray *info = objc_getAssociatedObject(st, &kOMCABKey);
    ((UILabel *)info[1]).text = [@((NSInteger)st.value) stringValue];
    OMCHSStore(info[0], @((NSInteger)st.value));
    [self updateHeaders];
    [self updatePreview];
}

- (UIButton *)smallButton:(NSString *)symbol tint:(UIColor *)tint action:(SEL)sel bundle:(NSString *)bid
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    b.tintColor = tint;
    b.frame = CGRectMake(0, 0, 36, 36);
    objc_setAssociatedObject(b, &kOMCABKey, bid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)boxInCell:(UITableViewCell *)c
{
    UIView *box = [c.contentView viewWithTag:0x4258];
    if (!box) {
        box = [[UIView alloc] initWithFrame:c.contentView.bounds];
        box.tag = 0x4258;
        box.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [c.contentView addSubview:box];
    }
    return box;
}

- (CGFloat)layoutTilesIn:(UIView *)v width:(CGFloat)w
{
    NSInteger n = 1 + OMCHS_PRESETS + (_photo ? 1 : 0), cols = 4;
    CGFloat pad = 12, gap = 8, tw = floor((w - pad * 2 - gap * (cols - 1)) / cols), th = floor(tw / 1.6);
    NSInteger rows = (n + cols - 1) / cols;
    CGFloat h = pad * 2 + rows * th + (rows - 1) * gap;
    if (!v) return h;
    for (UIView *old in [v.subviews copy]) [old removeFromSuperview];
    for (NSInteger k = 0; k < n; k++) {
        NSInteger style = k <= OMCHS_PRESETS ? k : OMCHS_STYLE_PHOTO;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(pad + (k % cols) * (tw + gap), pad + (k / cols) * (th + gap), tw, th);
        b.tag = style;
        b.layer.cornerRadius = 10;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        b.clipsToBounds = YES;
        if (style == 0) {
            b.backgroundColor = [UIColor systemBackgroundColor];
            b.layer.borderWidth = 1;
            b.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.2].CGColor;
            [b setTitle:L(@"HOMESCREEN_WALLPAPER_DEFAULT") forState:UIControlStateNormal];
            [b setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:12];
            b.titleLabel.adjustsFontSizeToFitWidth = YES;
        } else {
            UIImage *img = style == OMCHS_STYLE_PHOTO ? _photo : OMCHSPresetImage(style, CGSizeMake(tw, th), [UIScreen mainScreen].scale);
            [b setBackgroundImage:img forState:UIControlStateNormal];
            b.imageView.contentMode = UIViewContentModeScaleAspectFill;
            b.contentMode = UIViewContentModeScaleAspectFill;
        }
        [b addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:b];
        if (style == _wallStyle) {   // vien cau vong 4 mau logo quanh o dang chon (nam ngoai o 3pt)
            CGRect r = CGRectInset(b.frame, -3, -3);
            CAGradientLayer *g = [CAGradientLayer layer];
            g.type = kCAGradientLayerConic;
            g.frame = r;
            g.startPoint = CGPointMake(0.5, 0.5); g.endPoint = CGPointMake(0, 1);
            g.colors = @[(id)OMCHSHex(0xA78BFA, 1).CGColor, (id)OMCHSHex(0x60C5FA, 1).CGColor, (id)OMCHSHex(0x5EDDB6, 1).CGColor,
                         (id)OMCHSHex(0xF59AC0, 1).CGColor, (id)OMCHSHex(0xA78BFA, 1).CGColor];
            CAShapeLayer *m = [CAShapeLayer layer];
            m.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectMake(0, 0, r.size.width, r.size.height), 1, 1) cornerRadius:12].CGPath;
            m.fillColor = nil; m.strokeColor = [UIColor blackColor].CGColor; m.lineWidth = 2;
            g.mask = m;
            UIView *ring = [[UIView alloc] initWithFrame:r];
            ring.userInteractionEnabled = NO;
            g.frame = ring.bounds;
            [ring.layer addSublayer:g];
            [v addSubview:ring];
        }
    }
    return h;
}

- (CGFloat)layoutChipsIn:(UIView *)v width:(CGFloat)w
{
    CGFloat pad = 12, gap = 8, ch = 30, x = pad, y = pad;
    UIFont *font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    if (v) for (UIView *old in [v.subviews copy]) [old removeFromSuperview];
    NSMutableArray *items = [_dock mutableCopy];
    if (_dock.count < HS_DOCK_MAX) [items addObject:[NSNull null]];
    for (id it in items) {
        BOOL add = ![it isKindOfClass:[NSString class]];
        NSString *title = add ? L(@"HOMESCREEN_DOCK_ADD") : OMCHSName(it);
        CGFloat tw = MIN(140, ceil([title sizeWithAttributes:@{NSFontAttributeName: font}].width));
        CGFloat cw = add ? tw + 24 : 4 + 22 + 6 + tw + 4 + 22;
        if (x + cw > w - pad && x > pad) { x = pad; y += ch + gap; }
        if (v) {
            UIView *chip = [[UIView alloc] initWithFrame:CGRectMake(x, y, cw, ch)];
            chip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.7];
            chip.layer.cornerRadius = 12;
            chip.layer.borderWidth = 1;
            chip.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.95].CGColor;
            UIButton *tap = [UIButton buttonWithType:UIButtonTypeSystem];
            tap.frame = chip.bounds;
            if (add) {
                [tap setTitle:title forState:UIControlStateNormal];
                tap.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
                [tap addTarget:self action:@selector(addDockApp:) forControlEvents:UIControlEventTouchUpInside];
                [chip addSubview:tap];
            } else {
                UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(4, 4, 22, 22)];
                iv.image = OMCHSIcon(it, 22);
                [chip addSubview:iv];
                UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(32, 0, tw, ch)];
                l.text = title; l.font = font; l.textColor = [UIColor labelColor];
                [chip addSubview:l];
                UIButton *rm = [self smallButton:@"xmark" tint:[UIColor secondaryLabelColor] action:@selector(pinTapped:) bundle:it];
                rm.frame = CGRectMake(cw - 26, 0, 26, ch);
                [rm setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold] forImageInState:UIControlStateNormal];
                [chip addSubview:rm];
            }
            [v addSubview:chip];
        }
        x += cw + gap;
    }
    return y + ch + pad;
}

- (void)tileTapped:(UIButton *)b
{
    NSInteger style = b.tag;
    if (style == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:HS_WALLPAPER_PATH error:nil];
        _wallpaper = nil;
        _wallStyle = 0;
        OMCHSStore(HS_KEY_WALLPAPER_STYLE, @0);
        OMCHSStore(HS_KEY_WALLPAPER, @NO);
    } else {
        UIImage *img = style == OMCHS_STYLE_PHOTO ? _photo : OMCHSPresetImage(style, CGSizeMake(1920, 720), 1);
        if (![self saveWallpaper:img style:style]) return;
    }
    [self reloadCard:OMCABWall];
    [self updatePreview];
}

- (void)addDockApp:(UIButton *)sender
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:L(@"HOMESCREEN_DOCK_PICK") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *bid in [self visibleApps]) {
        if ([_dock containsObject:bid] || ![self isVisible:bid]) continue;
        [sheet addAction:[UIAlertAction actionWithTitle:OMCHSName(bid) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (self.dock.count >= HS_DOCK_MAX || [self.dock containsObject:bid]) return;
            [self.dock addObject:bid];
            OMCHSStore(HS_KEY_DOCK, [self.dock copy]);
            [self reloadCard:OMCABDock];
            [self updatePreview];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pinTapped:(UIButton *)b
{
    NSString *bid = objc_getAssociatedObject(b, &kOMCABKey);
    if ([_dock containsObject:bid]) [_dock removeObject:bid];
    else if (_dock.count < HS_DOCK_MAX) [_dock addObject:bid];
    else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:L(@"HOMESCREEN_DOCK_FULL") preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    OMCHSStore(HS_KEY_DOCK, [_dock copy]);
    [self reloadCard:OMCABDock]; [self.list reloadData];
    [self updatePreview];
}

- (void)pickPhoto
{
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[UTTypeImage.identifier];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (BOOL)writeJPEG:(UIImage *)img to:(NSString *)path
{
    NSData *jpg = UIImageJPEGRepresentation(img, 0.85);
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *err = nil;
    if (!jpg || ![jpg writeToFile:path options:NSDataWritingAtomic error:&err]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:err.localizedDescription ?: @"JPEG" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return NO;
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:path error:nil];
    return YES;
}

- (BOOL)saveWallpaper:(UIImage *)img style:(NSInteger)style
{
    if (!img || ![self writeJPEG:img to:HS_WALLPAPER_PATH]) return NO;
    _wallpaper = img;
    _wallStyle = style;
    OMCHSStore(HS_KEY_WALLPAPER_STYLE, @(style));
    OMCHSStore(HS_KEY_WALLPAPER, @YES);
    return YES;
}

- (void)useWallpaper:(UIImage *)img
{
    if (!img) return;
    CGFloat k = MIN(1, 1920 / MAX(img.size.width * img.scale, img.size.height * img.scale));
    CGSize px = CGSizeMake(round(img.size.width * img.scale * k), round(img.size.height * img.scale * k));
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1; f.opaque = YES;
    UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:px format:f] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, px.width, px.height)];
    }];
    if (![self writeJPEG:small to:HS_PHOTO_PATH]) return;
    _photo = small;
    if (![self saveWallpaper:small style:OMCHS_STYLE_PHOTO]) return;
    [self reloadCard:OMCABWall];
    [self updatePreview];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info
{
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{ [self useWallpaper:img]; }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }

@end
