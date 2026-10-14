// "Man chinh CarPlay" (ROADMAP-DEV Muc 2, xem truoc giao dien: tools/preview/home.html). Mo tu trang App tren man xe
// (OMCAppBridgeAppsController, dong "Man chinh CarPlay"). Cac key HS_KEY_* trong ../AppBridge.h; phia xe:
// Features/SplitScreen/SCPHomeScreen.mm ve luoi / dock / hinh nen cua OmniCar len tren cua CarPlay.
// Trang nay chi lo GIAO DIEN: 0 Xem truoc (man xe mo phong, doi theo ngay)   1 Cong tac   2 Luoi icon
//   3 Hinh nen (o mau: Mac dinh + 6 hinh dung san + anh tu Anh)   4 Dock (chip app ghim, + Them)
// App nao tren xe, thu tu, an, ghim: chi o trang App tren man xe (OMCAppBridgeAppsController, muc Tren man xe);
// trang nay doc lai cac key do cho xem truoc va chip + Them cua dock.
#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "OMCTheme.h"
#import "OmniCar.h"
#import "../AppBridge.h"
#import "OMCHomeScreenController.h"

#define HS_KEY_CARPLAY_APPS @"splitScreenCarPlayApps"   // = SPL_KEY_CARPLAY_APPS (Split Screen ghi khi cam xe)

@interface UIImage (OMCHomeScreenPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(double)scale;
@end

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

static NSArray *OMCHSArray(NSString *key)
{
    id v = OMCHSPref(key, nil);
    return [v isKindOfClass:[NSArray class]] ? v : @[];
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
//  Controller
// ---------------------------------------------------------------------
enum { OMCHSPreviewSection = 0, OMCHSSwitchSection, OMCHSGridSection, OMCHSWallSection, OMCHSDockSection, OMCHSSectionCount };
enum { OMCHSGridSize = 0, OMCHSGridCols, OMCHSGridRows, OMCHSGridGap, OMCHSGridNames, OMCHSGridCount };
enum { OMCHSWallTiles = 0, OMCHSWallPhotos, OMCHSWallBlur, OMCHSWallDim, OMCHSWallCount };
enum { OMCHSDockChips = 0, OMCHSDockSuggest, OMCHSDockCount };
static char kOMCHSBundleKey;

@interface OMCHomeScreenController () <UITableViewDataSource, UITableViewDelegate, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) OMCHSPreview *preview;
@property (nonatomic, strong) NSMutableArray<NSString *> *order;   // moi app (ca app an), theo thu tu nguoi dung
@property (nonatomic, strong) NSMutableSet<NSString *> *hidden;
@property (nonatomic, strong) NSMutableArray<NSString *> *dock;
@property (nonatomic, strong) NSSet<NSString *> *iphoneApps;
@property (nonatomic, strong) UIImage *wallpaper;
@property (nonatomic) NSInteger wallStyle;          // HS_KEY_WALLPAPER_STYLE
@property (nonatomic, strong) UIImage *photo;       // anh nguoi dung chon gan nhat (o "anh cua ban")
@end

@implementation OMCHomeScreenController

- (void)loadView
{
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    self.view = _table;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    OMCLoadStrings();
    self.title = L(@"HOMESCREEN_TITLE");
    self.view.tintColor = OMCAccentColor();
    OMCStyleTable(_table);
    [self loadState];
}

- (void)loadState
{
    CFPreferencesAppSynchronize(kPrefsDomain);
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *b in OMCHSArray(HS_KEY_CARPLAY_APPS)) if ([b isKindOfClass:[NSString class]] && ![all containsObject:b]) [all addObject:b];
    NSArray *phone = OMCHSArray(AB_KEY_APPS);
    for (NSString *b in phone) if ([b isKindOfClass:[NSString class]] && ![all containsObject:b]) [all addObject:b];
    _iphoneApps = [NSSet setWithArray:phone];
    _order = [NSMutableArray array];
    for (NSString *b in OMCHSArray(HS_KEY_ORDER)) if ([all containsObject:b] && ![_order containsObject:b]) [_order addObject:b];
    for (NSString *b in all) if (![_order containsObject:b]) [_order addObject:b];
    _hidden = [NSMutableSet setWithArray:OMCHSArray(HS_KEY_HIDDEN)];
    _dock = [NSMutableArray array];
    for (NSString *b in OMCHSArray(HS_KEY_DOCK)) if ([all containsObject:b] && _dock.count < HS_DOCK_MAX) [_dock addObject:b];
    _wallpaper = [OMCHSPref(HS_KEY_WALLPAPER, @NO) boolValue] ? [UIImage imageWithContentsOfFile:HS_WALLPAPER_PATH] : nil;
    _photo = [UIImage imageWithContentsOfFile:HS_PHOTO_PATH];
    _wallStyle = _wallpaper ? [self num:HS_KEY_WALLPAPER_STYLE def:OMCHS_STYLE_PHOTO] : 0;
}

- (NSInteger)num:(NSString *)key def:(NSInteger)def
{
    id v = OMCHSPref(key, nil);
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def;
}

- (void)updatePreview
{
    OMCHSPreview *p = self.preview;
    if (!p) return;
    NSMutableArray *shown = [NSMutableArray array];
    for (NSString *b in _order) if (![_hidden containsObject:b]) [shown addObject:b];
    p.apps = shown;
    p.dock = _dock;
    p.wallpaper = _wallpaper;
    p.on = [OMCHSPref(HS_KEY_ENABLED, @NO) boolValue];
    p.size = [self num:HS_KEY_ICON_SIZE def:100]; p.cols = [self num:HS_KEY_COLS def:5]; p.rows = [self num:HS_KEY_ROWS def:2];
    p.gap = [self num:HS_KEY_GAP def:100]; p.blur = [self num:HS_KEY_BLUR def:0]; p.dim = [self num:HS_KEY_DIM def:25];
    p.names = [OMCHSPref(HS_KEY_NAMES, @YES) boolValue];
    p.suggest = [OMCHSPref(HS_KEY_DOCK_SUGGEST, @YES) boolValue];
    [p setNeedsDisplay];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return OMCHSSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s
{
    switch (s) {
        case OMCHSPreviewSection: return 1;
        case OMCHSSwitchSection: return 1;
        case OMCHSGridSection: return OMCHSGridCount;
        case OMCHSWallSection: return OMCHSWallCount;
        case OMCHSDockSection: return OMCHSDockCount;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s
{
    switch (s) {
        case OMCHSGridSection: return L(@"HOMESCREEN_GRID");
        case OMCHSWallSection: return L(@"HOMESCREEN_WALLPAPER");
        case OMCHSDockSection: return L(@"HOMESCREEN_DOCK");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    switch (s) {
        case OMCHSSwitchSection: return L(@"HOMESCREEN_FOOTER");
        case OMCHSGridSection: return L(@"HOMESCREEN_GRID_FOOTER");
        case OMCHSWallSection: return L(@"HOMESCREEN_WALLPAPER_FOOTER");
        case OMCHSDockSection: return L(@"HOMESCREEN_DOCK_FOOTER");
    }
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, YES); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, NO); }

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip
{
    if (ip.section == OMCHSPreviewSection) return floor((tv.bounds.size.width - 60) * 300.0 / 800.0) + 20;   // = khung xem truoc + le 10
    if (ip.section == OMCHSWallSection && ip.row == OMCHSWallTiles) return [self layoutTilesIn:nil width:tv.bounds.size.width - 40];
    if (ip.section == OMCHSWallSection && ip.row == OMCHSWallPhotos) return 58;
    if (ip.section == OMCHSDockSection && ip.row == OMCHSDockChips) return [self layoutChipsIn:nil width:tv.bounds.size.width - 40];
    return 52;
}

// Cell co accessory dung ca khi bang dang o che do sap xep (editingAccessoryView)
- (UITableViewCell *)cellWithId:(NSString *)rid inTable:(UITableView *)tv
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:rid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:rid];
    OMCStyleCell(c);
    c.accessoryView = nil; c.editingAccessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone; c.editingAccessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.imageView.image = nil; c.detailTextLabel.text = nil;
    c.textLabel.textColor = [UIColor labelColor];
    return c;
}

- (void)setAccessory:(UIView *)v onCell:(UITableViewCell *)c { c.accessoryView = v; c.editingAccessoryView = v; }

- (UISwitch *)switchFor:(NSString *)key def:(BOOL)def
{
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = OMCSwitchColor();
    sw.on = [OMCHSPref(key, @(def)) boolValue];
    objc_setAssociatedObject(sw, &kOMCHSBundleKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (void)switchChanged:(UISwitch *)sw
{
    NSString *key = objc_getAssociatedObject(sw, &kOMCHSBundleKey);
    OMCHSStore(key, @(sw.on));
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
    objc_setAssociatedObject(sl, &kOMCHSBundleKey, @[key, unit, v], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sl addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
    [sl addTarget:self action:@selector(sliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [box addSubview:sl];
    [box addSubview:v];
    return box;
}

- (void)sliderMoved:(UISlider *)sl
{
    NSArray *info = objc_getAssociatedObject(sl, &kOMCHSBundleKey);
    ((UILabel *)info[2]).text = [NSString stringWithFormat:@"%ld%@", (long)lround(sl.value), info[1]];
    CFPreferencesSetAppValue((__bridge CFStringRef)info[0], (__bridge CFPropertyListRef)@(lround(sl.value)), kPrefsDomain);   // xem truoc ngay
    [self updatePreview];
}

- (void)sliderDone:(UISlider *)sl
{
    NSArray *info = objc_getAssociatedObject(sl, &kOMCHSBundleKey);
    OMCHSStore(info[0], @(lround(sl.value)));   // tha tay moi bao xe (khong ve lai luoi tren xe moi buoc truot)
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
    objc_setAssociatedObject(st, &kOMCHSBundleKey, @[key, v], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [st addTarget:self action:@selector(stepped:) forControlEvents:UIControlEventValueChanged];
    box.frame = CGRectMake(0, 0, CGRectGetMaxX(st.frame), 32);
    [box addSubview:v];
    [box addSubview:st];
    return box;
}

- (void)stepped:(UIStepper *)st
{
    NSArray *info = objc_getAssociatedObject(st, &kOMCHSBundleKey);
    ((UILabel *)info[1]).text = [@((NSInteger)st.value) stringValue];
    OMCHSStore(info[0], @((NSInteger)st.value));
    [self updatePreview];
}

- (UIButton *)smallButton:(NSString *)symbol tint:(UIColor *)tint action:(SEL)sel bundle:(NSString *)bid
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    b.tintColor = tint;
    b.frame = CGRectMake(0, 0, 36, 36);
    objc_setAssociatedObject(b, &kOMCHSBundleKey, bid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    if (ip.section == OMCHSPreviewSection) {
        UITableViewCell *c = [self cellWithId:@"preview" inTable:tv];
        if (!self.preview || self.preview.superview != c.contentView) {
            [self.preview removeFromSuperview];
            self.preview = [OMCHSPreview new];
            [c.contentView addSubview:self.preview];
        }
        CGFloat w = tv.bounds.size.width - 40 - 20;
        self.preview.frame = CGRectMake(10, 10, w, floor(w * 300.0 / 800.0));
        [self updatePreview];
        return c;
    }
    if (ip.section == OMCHSSwitchSection) {
        UITableViewCell *c = [self cellWithId:@"enable" inTable:tv];
        c.textLabel.text = L(@"HOMESCREEN_ENABLE");
        c.imageView.image = OMCIcon(@"square.grid.3x2.fill", OMCColorFromHex(@"#8B7CFF"));
        [self setAccessory:[self switchFor:HS_KEY_ENABLED def:NO] onCell:c];
        return c;
    }
    if (ip.section == OMCHSGridSection) {
        UITableViewCell *c = [self cellWithId:@"grid" inTable:tv];
        switch (ip.row) {
            case OMCHSGridSize:
                c.textLabel.text = L(@"HOMESCREEN_ICON_SIZE");
                c.imageView.image = OMCIcon(@"plus.magnifyingglass", OMCColorFromHex(@"#8B7CFF"));
                [self setAccessory:[self sliderFor:HS_KEY_ICON_SIZE min:80 max:130 def:100 unit:@"%"] onCell:c];
                break;
            case OMCHSGridCols:
                c.textLabel.text = L(@"HOMESCREEN_COLS");
                c.imageView.image = OMCIcon(@"rectangle.split.3x1", OMCColorFromHex(@"#5AB8FF"));
                [self setAccessory:[self stepperFor:HS_KEY_COLS min:3 max:7 def:5] onCell:c];
                break;
            case OMCHSGridRows:
                c.textLabel.text = L(@"HOMESCREEN_ROWS");
                c.imageView.image = OMCIcon(@"rectangle.split.1x2", OMCColorFromHex(@"#5AB8FF"));
                [self setAccessory:[self stepperFor:HS_KEY_ROWS min:1 max:3 def:2] onCell:c];
                break;
            case OMCHSGridGap:
                c.textLabel.text = L(@"HOMESCREEN_GAP");
                c.imageView.image = OMCIcon(@"arrow.left.and.right", OMCColorFromHex(@"#2BC79A"));
                [self setAccessory:[self sliderFor:HS_KEY_GAP min:60 max:140 def:100 unit:@"%"] onCell:c];
                break;
            case OMCHSGridNames:
                c.textLabel.text = L(@"HOMESCREEN_NAMES");
                c.imageView.image = OMCIcon(@"textformat", OMCColorFromHex(@"#FF7FA8"));
                [self setAccessory:[self switchFor:HS_KEY_NAMES def:YES] onCell:c];
                break;
        }
        return c;
    }
    if (ip.section == OMCHSWallSection) {
        UITableViewCell *c = [self cellWithId:(ip.row == OMCHSWallTiles ? @"tiles" : @"wall") inTable:tv];
        switch (ip.row) {
            case OMCHSWallTiles:
                [self layoutTilesIn:[self boxInCell:c] width:tv.bounds.size.width - 40];
                break;
            case OMCHSWallPhotos: {   // nut xam rong "Tu Anh" (nhu ban xem truoc)
                UIButton *b = (UIButton *)[c.contentView viewWithTag:0x50];
                if (!b) {
                    b = [UIButton buttonWithType:UIButtonTypeSystem];
                    b.tag = 0x50;
                    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
                    [b setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
                    b.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
                    b.layer.cornerRadius = 11;
                    b.layer.cornerCurve = kCACornerCurveContinuous;
                    b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                    [b addTarget:self action:@selector(pickPhoto) forControlEvents:UIControlEventTouchUpInside];
                    [c.contentView addSubview:b];
                }
                [b setTitle:L(@"HOMESCREEN_FROM_PHOTOS") forState:UIControlStateNormal];
                b.frame = CGRectMake(12, 4, tv.bounds.size.width - 40 - 24, 42);
                break;
            }
            case OMCHSWallBlur:
                c.textLabel.text = L(@"HOMESCREEN_BLUR");
                c.imageView.image = OMCIcon(@"drop.fill", OMCColorFromHex(@"#5AB8FF"));
                [self setAccessory:[self sliderFor:HS_KEY_BLUR min:0 max:30 def:0 unit:@""] onCell:c];
                break;
            case OMCHSWallDim:
                c.textLabel.text = L(@"HOMESCREEN_DIM");
                c.imageView.image = OMCIcon(@"moon.fill", OMCColorFromHex(@"#4A4F80"));
                [self setAccessory:[self sliderFor:HS_KEY_DIM min:0 max:70 def:25 unit:@"%"] onCell:c];
                break;
        }
        return c;
    }
    // Dock: chip app ghim (X de bo) + "+ Them", roi cong tac goi y cua CarPlay
    UITableViewCell *c = [self cellWithId:(ip.row == OMCHSDockChips ? @"chips" : @"dock") inTable:tv];
    if (ip.row == OMCHSDockChips) {
        [self layoutChipsIn:[self boxInCell:c] width:tv.bounds.size.width - 40];
    } else {
        c.textLabel.text = L(@"HOMESCREEN_DOCK_SUGGEST");
        c.textLabel.numberOfLines = 2;
        c.imageView.image = OMCIcon(@"sparkles", OMCColorFromHex(@"#B7A6FF"));
        [self setAccessory:[self switchFor:HS_KEY_DOCK_SUGGEST def:YES] onCell:c];
    }
    return c;
}

#pragma mark - Wallpaper tiles / dock chips

// Khung rieng trong cell cho o hinh nen / chip (ve lai thi chi xoa trong khung nay)
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

// O hinh nen: Mac dinh + 6 hinh dung san (+ anh cua ban neu da chon), 4 cot, ti le 1.6; dang chon = vien cau vong.
// view nil: chi tinh chieu cao.
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

// Chip: icon + ten + X (bo ghim); cuoi cung chip "+ Them" (khi chua du 4). Tu xuong dong. view nil: chi tinh chieu cao.
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

// Mac dinh: bo hinh nen (dung lai hinh nen CarPlay); hinh dung san: ve 1920 x 720 roi luu; anh cua ban: dung lai anh do
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
    [_table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:OMCHSWallTiles inSection:OMCHSWallSection]] withRowAnimation:UITableViewRowAnimationNone];
    [self updatePreview];
}

- (void)addDockApp:(UIButton *)sender
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:L(@"HOMESCREEN_DOCK_PICK") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *bid in _order) {
        if ([_dock containsObject:bid] || [_hidden containsObject:bid]) continue;
        [sheet addAction:[UIAlertAction actionWithTitle:OMCHSName(bid) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (self.dock.count >= HS_DOCK_MAX || [self.dock containsObject:bid]) return;
            [self.dock addObject:bid];
            OMCHSStore(HS_KEY_DOCK, [self.dock copy]);
            [self.table reloadSections:[NSIndexSet indexSetWithIndex:OMCHSDockSection] withRowAnimation:UITableViewRowAnimationAutomatic];
            [self updatePreview];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Actions

- (void)pinTapped:(UIButton *)b
{
    NSString *bid = objc_getAssociatedObject(b, &kOMCHSBundleKey);
    if ([_dock containsObject:bid]) [_dock removeObject:bid];
    else if (_dock.count < HS_DOCK_MAX) [_dock addObject:bid];
    else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:L(@"HOMESCREEN_DOCK_FULL") preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    OMCHSStore(HS_KEY_DOCK, [_dock copy]);
    [_table reloadSections:[NSIndexSet indexSetWithIndex:OMCHSDockSection] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updatePreview];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
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

// Ghi JPEG vao path (thu muc HomeScreen, 0644 de CarPlay doc duoc). NO + bao loi neu khong ghi duoc.
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

// Anh tu Anh: thu nho canh dai toi da 1920 px, giu ban sao (o "anh cua ban") roi dung lam hinh nen
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
    [_table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:OMCHSWallTiles inSection:OMCHSWallSection]] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updatePreview];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info
{
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{ [self useWallpaper:img]; }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }

@end
