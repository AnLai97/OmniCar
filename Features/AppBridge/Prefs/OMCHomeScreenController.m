// "Man chinh CarPlay" (ROADMAP-DEV Muc 2, xem truoc giao dien: tools/preview/home.html). Mo tu trang App tren man xe
// (OMCAppBridgeAppsController, dong "Man chinh CarPlay"). Cac key HS_KEY_* trong ../AppBridge.h; phia xe:
// Features/SplitScreen/SCPHomeScreen.mm ve luoi / dock / hinh nen cua OmniCar len tren cua CarPlay.
//   0 Xem truoc (man xe mo phong, doi theo ngay)   1 Cong tac   2 Ung dung (keo sap xep, an, ghim dock)
//   3 Luoi icon   4 Hinh nen   5 Dock
// Danh sach app: app CarPlay ma xe da doc (SPL_KEY_CARPLAY_APPS, theo thu tu man chinh) + app iPhone (AB_KEY_APPS).
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
enum { OMCHSPreviewSection = 0, OMCHSSwitchSection, OMCHSAppsSection, OMCHSGridSection, OMCHSWallSection, OMCHSDockSection, OMCHSSectionCount };
enum { OMCHSGridSize = 0, OMCHSGridCols, OMCHSGridRows, OMCHSGridGap, OMCHSGridNames, OMCHSGridCount };
enum { OMCHSWallPhotos = 0, OMCHSWallFiles, OMCHSWallBlur, OMCHSWallDim, OMCHSWallRemove };
static char kOMCHSBundleKey;

@interface OMCHomeScreenController () <UITableViewDataSource, UITableViewDelegate, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) OMCHSPreview *preview;
@property (nonatomic, strong) NSMutableArray<NSString *> *order;   // moi app (ca app an), theo thu tu nguoi dung
@property (nonatomic, strong) NSMutableSet<NSString *> *hidden;
@property (nonatomic, strong) NSMutableArray<NSString *> *dock;
@property (nonatomic, strong) NSSet<NSString *> *iphoneApps;
@property (nonatomic, strong) UIImage *wallpaper;
@end

@implementation OMCHomeScreenController

- (void)loadView
{
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.editing = YES;                     // keo sap xep app; o khac khong co nut xoa (editingStyle none)
    _table.allowsSelectionDuringEditing = YES;
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
        case OMCHSAppsSection: return _order.count;
        case OMCHSGridSection: return OMCHSGridCount;
        case OMCHSWallSection: return _wallpaper ? 5 : 2;
        case OMCHSDockSection: return _dock.count + 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s
{
    switch (s) {
        case OMCHSAppsSection: return L(@"HOMESCREEN_APPS");
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
        case OMCHSAppsSection: return _order.count ? L(@"HOMESCREEN_APPS_FOOTER") : L(@"HOMESCREEN_APPS_EMPTY");
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
    return 52;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tv shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip { return NO; }
- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return ip.section == OMCHSAppsSection; }

- (NSIndexPath *)tableView:(UITableView *)tv targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to
{
    if (to.section < OMCHSAppsSection) return [NSIndexPath indexPathForRow:0 inSection:OMCHSAppsSection];
    if (to.section > OMCHSAppsSection) return [NSIndexPath indexPathForRow:_order.count - 1 inSection:OMCHSAppsSection];
    return to;
}

- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to
{
    NSString *b = _order[from.row];
    [_order removeObjectAtIndex:from.row];
    [_order insertObject:b atIndex:to.row];
    OMCHSStore(HS_KEY_ORDER, [_order copy]);
    [self updatePreview];
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
    if (ip.section == OMCHSAppsSection) {
        NSString *bid = _order[ip.row];
        BOOL hid = [_hidden containsObject:bid], docked = [_dock containsObject:bid];
        UITableViewCell *c = [self cellWithId:@"app" inTable:tv];
        c.showsReorderControl = YES;
        c.textLabel.text = OMCHSName(bid);
        c.textLabel.textColor = hid ? [UIColor tertiaryLabelColor] : [UIColor labelColor];
        c.detailTextLabel.text = [_iphoneApps containsObject:bid] ? @"iPhone" : nil;
        c.imageView.image = OMCHSIcon(bid, 32);
        c.imageView.alpha = hid ? 0.35 : 1;
        UIStackView *acc = [[UIStackView alloc] initWithArrangedSubviews:@[
            [self smallButton:docked ? @"pin.fill" : @"pin" tint:docked ? OMCAccentColor() : [UIColor secondaryLabelColor] action:@selector(pinTapped:) bundle:bid],
            [self smallButton:hid ? @"eye.slash" : @"eye" tint:[UIColor secondaryLabelColor] action:@selector(eyeTapped:) bundle:bid]]];
        acc.frame = CGRectMake(0, 0, 76, 36);
        acc.spacing = 4;
        [self setAccessory:acc onCell:c];
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
        UITableViewCell *c = [self cellWithId:@"wall" inTable:tv];
        switch (ip.row) {
            case OMCHSWallPhotos:
            case OMCHSWallFiles:
                c.textLabel.text = L(ip.row == OMCHSWallPhotos ? @"HOMESCREEN_FROM_PHOTOS" : @"HOMESCREEN_FROM_FILES");
                c.imageView.image = OMCIcon(ip.row == OMCHSWallPhotos ? @"photo.fill" : @"folder.fill", OMCColorFromHex(ip.row == OMCHSWallPhotos ? @"#FF9500" : @"#0A84FF"));
                c.selectionStyle = UITableViewCellSelectionStyleDefault;
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                c.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
                if (ip.row == OMCHSWallPhotos && _wallpaper) {   // anh dang dung: thumbnail nho ben phai
                    UIImageView *th = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 54, 32)];
                    th.image = _wallpaper; th.contentMode = UIViewContentModeScaleAspectFill;
                    th.layer.cornerRadius = 6; th.clipsToBounds = YES;
                    [self setAccessory:th onCell:c];
                }
                break;
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
            case OMCHSWallRemove:
                c.textLabel.text = L(@"HOMESCREEN_WALLPAPER_REMOVE");
                c.textLabel.textColor = [UIColor systemRedColor];
                c.imageView.image = OMCIcon(@"trash.fill", [UIColor systemRedColor]);
                c.selectionStyle = UITableViewCellSelectionStyleDefault;
                break;
        }
        return c;
    }
    // Dock: app ghim (cham X de bo), cuoi cung la cong tac goi y cua CarPlay
    UITableViewCell *c = [self cellWithId:@"dock" inTable:tv];
    if (ip.row < (NSInteger)_dock.count) {
        NSString *bid = _dock[ip.row];
        c.textLabel.text = OMCHSName(bid);
        c.imageView.image = OMCHSIcon(bid, 32);
        [self setAccessory:[self smallButton:@"xmark.circle.fill" tint:[UIColor tertiaryLabelColor] action:@selector(pinTapped:) bundle:bid] onCell:c];
    } else {
        c.textLabel.text = L(@"HOMESCREEN_DOCK_SUGGEST");
        c.imageView.image = OMCIcon(@"sparkles", OMCColorFromHex(@"#B7A6FF"));
        [self setAccessory:[self switchFor:HS_KEY_DOCK_SUGGEST def:YES] onCell:c];
    }
    return c;
}

#pragma mark - Actions

- (void)eyeTapped:(UIButton *)b
{
    NSString *bid = objc_getAssociatedObject(b, &kOMCHSBundleKey);
    if ([_hidden containsObject:bid]) [_hidden removeObject:bid]; else [_hidden addObject:bid];
    OMCHSStore(HS_KEY_HIDDEN, _hidden.allObjects);
    [_table reloadSections:[NSIndexSet indexSetWithIndex:OMCHSAppsSection] withRowAnimation:UITableViewRowAnimationNone];
    [self updatePreview];
}

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
    NSMutableIndexSet *secs = [NSMutableIndexSet indexSetWithIndex:OMCHSAppsSection];
    [secs addIndex:OMCHSDockSection];
    [_table reloadSections:secs withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updatePreview];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != OMCHSWallSection) return;
    if (ip.row == OMCHSWallPhotos) {
        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.mediaTypes = @[UTTypeImage.identifier];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (ip.row == OMCHSWallFiles) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (ip.row == OMCHSWallRemove) {
        [[NSFileManager defaultManager] removeItemAtPath:HS_WALLPAPER_PATH error:nil];
        _wallpaper = nil;
        OMCHSStore(HS_KEY_WALLPAPER, @NO);
        [_table reloadSections:[NSIndexSet indexSetWithIndex:OMCHSWallSection] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updatePreview];
    }
}

// Luu anh: thu nho canh dai toi da 1920 px, JPEG, vao HS_WALLPAPER_PATH (xe doc lai khi prefschanged)
- (void)useWallpaper:(UIImage *)img
{
    if (!img) return;
    CGFloat maxSide = 1920, k = MIN(1, maxSide / MAX(img.size.width * img.scale, img.size.height * img.scale));
    CGSize px = CGSizeMake(round(img.size.width * img.scale * k), round(img.size.height * img.scale * k));
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = 1; f.opaque = YES;
    UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:px format:f] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, px.width, px.height)];
    }];
    NSData *jpg = UIImageJPEGRepresentation(small, 0.85);
    NSString *path = HS_WALLPAPER_PATH;
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *err = nil;
    if (![jpg writeToFile:path options:NSDataWritingAtomic error:&err]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:path error:nil];   // CarPlay doc duoc
    _wallpaper = small;
    OMCHSStore(HS_KEY_WALLPAPER, @YES);
    [_table reloadSections:[NSIndexSet indexSetWithIndex:OMCHSWallSection] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updatePreview];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info
{
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{ [self useWallpaper:img]; }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    UIImage *img = url ? [UIImage imageWithContentsOfFile:url.path] : nil;
    if (scoped) [url stopAccessingSecurityScopedResource];
    [self useWallpaper:img];
}

@end
