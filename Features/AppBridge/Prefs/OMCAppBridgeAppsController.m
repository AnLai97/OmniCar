// "Ung dung" cua trang chinh OmniCar: dong "App tren man xe" (OMCAppBridgeAppsLinkCell, hien so app da chon) mo
// OMCAppBridgeAppsController - MOT trang cho App Bridge + man chinh CarPlay (xem truoc: tools/preview/home.html): app nao
// tren xe (ca app he thong cua CarPlay), thu tu, dock, bo cuc icon, hinh nen. Bundle id app iPhone da chon luu o
// AB_KEY_APPS; CarPlay (SCPCPhoneAppSet, SCPAppIcons) va bang chon app cua Chia man hinh dung dung danh sach nay. Giao
// dien man chinh tren xe: Features/SplitScreen/SCPHomeScreen.mm (HS_KEY_*). ROADMAP-DEV 3.1: thu muc, trang app iPhone,
// hinh dang / goi icon, widget, hinh nen ngay / dem va video.
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
#import <AVFoundation/AVFoundation.h>
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

// Hinh dang + goi icon dang chon (cung cach SCPHomeScreen.mm): icon trong xem truoc / chip ve theo day
static NSString *sOMCHSTheme = @"";
static NSInteger sOMCHSShape;

static CGFloat OMCHSCorner(CGFloat side)
{
    return sOMCHSShape == 1 ? side * 0.12 : sOMCHSShape == 2 ? side / 2 : side * 0.225;
}

// Goi icon IconBundles: <HS_THEMES_DIR>/<goi>/IconBundles/<bundle id>-large.png (hoac <bundle id>.png, @2x / @3x)
static UIImage *OMCHSThemeIcon(NSString *bid)
{
    if (!sOMCHSTheme.length) return nil;
    NSString *dir = [[HS_THEMES_DIR stringByAppendingPathComponent:sOMCHSTheme] stringByAppendingPathComponent:@"IconBundles"];
    for (NSString *base in @[[bid stringByAppendingString:@"-large"], bid])
        for (NSString *sfx in @[@"@3x.png", @"@2x.png", @".png"]) {
            UIImage *img = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:[base stringByAppendingString:sfx]]];
            if (img) return img;
        }
    return nil;
}

// Goi icon da cai (thu muc *.theme co IconBundles), theo ten
static NSArray<NSString *> *OMCHSThemes(void)
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:HS_THEMES_DIR error:nil]) {
        BOOL dir = NO;
        NSString *icons = [[HS_THEMES_DIR stringByAppendingPathComponent:n] stringByAppendingPathComponent:@"IconBundles"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:icons isDirectory:&dir] && dir) [out addObject:n];
    }
    return [out sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSString *OMCHSThemeName(NSString *theme)
{
    return [theme hasSuffix:@".theme"] ? [theme substringToIndex:theme.length - 6] : theme;
}

static UIImage *OMCHSIcon(NSString *bid, CGFloat side)
{
    static NSCache *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@/%.0f/%@/%ld", bid, side, sOMCHSTheme, (long)sOMCHSShape];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    UIImage *icon = OMCHSThemeIcon(bid);
    if (!icon && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
    if (!icon) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *out = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:OMCHSCorner(side)] addClip];
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
#define OMCHS_STYLE_PHOTO 7   // HS_KEY_WALLPAPER_STYLE / HS_KEY_NIGHT_STYLE: 0 mac dinh, 1..6 hinh dung san, 7 anh, 8 video
#define OMCHS_STYLE_VIDEO 8
#define OMCHS_VIDEO_MAX   20.0   // giay

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
//  Xem truoc: man xe mo phong (dock trai, widget, luoi icon / thu muc, hinh nen, cham trang) - cung cach tinh luoi voi
//  SCPHomeScreen.mm
// ---------------------------------------------------------------------
@interface OMCHSPreview : UIView
@property (nonatomic, copy) NSArray *items;                // app (NSString) / thu muc @{name, apps}, da sap xep, da bo app an
@property (nonatomic, copy) NSSet<NSString *> *phoneApps;  // app iPhone (trang rieng)
@property (nonatomic, copy) NSArray<NSString *> *dock, *widgets;
@property (nonatomic, strong) UIImage *wallpaper;
@property (nonatomic) NSInteger size, cols, rows, gap, blur, dim;
@property (nonatomic) BOOL names, suggest, on, glass, shadow, phonePage, video;
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
- (void)drawIcon:(id)item in:(CGRect)ir
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat side = ir.size.width, corner = OMCHSCorner(side);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:ir cornerRadius:corner];
    CGContextSaveGState(c);
    if (self.shadow) CGContextSetShadowWithColor(c, CGSizeMake(0, 3), 6, [UIColor colorWithWhite:0 alpha:0.3].CGColor);
    if ([item isKindOfClass:[NSDictionary class]]) {   // thu muc: nen kinh + 4 icon nho
        [[UIColor colorWithWhite:1 alpha:0.26] setFill]; [shape fill];
        CGContextSetShadowWithColor(c, CGSizeZero, 0, NULL);
        NSArray *apps = item[@"apps"];
        CGFloat pad = side * 0.14, g = side * 0.08, mini = (side - pad * 2 - g) / 2;
        for (NSInteger i = 0; i < MIN(4, (NSInteger)apps.count); i++) {
            UIImage *m = OMCHSIcon(apps[i], mini);
            if (m) [m drawInRect:CGRectMake(ir.origin.x + pad + (i % 2) * (mini + g), ir.origin.y + pad + (i / 2) * (mini + g), mini, mini)];
        }
    } else {
        UIImage *ic = OMCHSIcon(item, side);
        if (ic) [ic drawInRect:ir];
        else { [[UIColor colorWithWhite:1 alpha:0.2] setFill]; [shape fill]; }
    }
    CGContextRestoreGState(c);
    if (self.glass) {
        [[UIColor colorWithWhite:1 alpha:0.55] setStroke];
        UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(ir, 0.5, 0.5) cornerRadius:corner];
        rim.lineWidth = 1; [rim stroke];
    }
}
- (void)drawWidgets:(CGRect)col
{
    NSInteger n = self.widgets.count;
    CGFloat gap = 10, h = (col.size.height - gap * (n - 1)) / n;
    NSDictionary *big = @{NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:MIN(40, h * 0.4) weight:UIFontWeightSemibold], NSForegroundColorAttributeName: [UIColor whiteColor]};
    NSDictionary *small = @{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.7]};
    for (NSInteger i = 0; i < n; i++) {
        CGRect r = CGRectMake(col.origin.x, col.origin.y + i * (h + gap), col.size.width, h);
        [[UIColor colorWithWhite:0.08 alpha:0.55] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:20] fill];
        NSString *k = self.widgets[i], *top, *bottom;
        if ([k isEqualToString:@"clock"]) { top = @"9:41"; bottom = L(@"APPS_WIDGET_CLOCK"); }
        else if ([k isEqualToString:@"weather"]) { top = @"☀︎ 31°"; bottom = @"↑33°  ↓25°"; }
        else { top = @"♫"; bottom = L(@"APPS_WIDGET_MUSIC"); }
        CGFloat bh = [big[NSFontAttributeName] lineHeight];
        [top drawAtPoint:CGPointMake(r.origin.x + 16, CGRectGetMidY(r) - bh * 0.75) withAttributes:big];
        [bottom drawAtPoint:CGPointMake(r.origin.x + 16, CGRectGetMidY(r) + bh * 0.3) withAttributes:small];
    }
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
        if (self.blur > 0 && !self.video) { [[UIColor colorWithWhite:1 alpha:MIN(0.25, self.blur / 120.0)] setFill]; UIRectFillUsingBlendMode(area, kCGBlendModeNormal); }
        [[UIColor colorWithWhite:0 alpha:self.dim / 100.0] setFill]; UIRectFillUsingBlendMode(area, kCGBlendModeNormal);
        CGContextRestoreGState(c);
        if (self.video) {   // dau hieu video
            NSDictionary *va = @{NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold], NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.85]};
            [@"▶︎ video" drawAtPoint:CGPointMake(W - 70, H - 20) withAttributes:va];
        }
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
        if (self.on) [self drawIcon:b in:CGRectMake(11, dy, 42, 42)];
        else { UIImage *ic = OMCHSIcon(b, 42); if (ic) [ic drawInRect:CGRectMake(11, dy, 42, 42)]; }
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
    // widget: cot ben trai (= SCPHomeApply)
    if (self.widgets.count) {
        CGFloat ww = MIN(280, MAX(200, floor(area.size.width * 0.32)));
        [self drawWidgets:CGRectMake(area.origin.x + 14, 14, ww, H - 28)];
        area.origin.x += ww + 14; area.size.width -= ww + 14;
    }
    // luoi: giong SCPHomeGridView
    CGFloat side = round(64 * self.size / 100.0), gapX = 26 * self.gap / 100.0, gapY = 14 * self.gap / 100.0;
    CGFloat cellW = side + gapX, cellH = side + (self.names ? 20 : 0), usableH = H - 18;
    NSInteger maxCols = MAX(1, (NSInteger)floor((area.size.width - 16) / cellW)), maxRows = MAX(1, (NSInteger)floor((usableH - 8 + gapY) / (cellH + gapY)));
    NSInteger cols = MIN(self.cols, maxCols), rows = MIN(self.rows, maxRows), per = MAX(1, cols * rows);
    NSMutableArray *slots = [NSMutableArray array];
    if (self.phonePage) {
        NSMutableArray *phone = [NSMutableArray array];
        for (id it in self.items) [([it isKindOfClass:[NSString class]] && [self.phoneApps containsObject:it] ? phone : slots) addObject:it];
        if (phone.count && slots.count) while (slots.count % per) [slots addObject:[NSNull null]];
        [slots addObjectsFromArray:phone];
    } else [slots addObjectsFromArray:self.items];
    NSInteger pages = MAX(1, ((NSInteger)slots.count + per - 1) / per);
    CGFloat gridW = cols * cellW, gridH = rows * cellH + (rows - 1) * gapY;
    NSDictionary *na = @{NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor whiteColor]};
    for (NSInteger i = 0; i < MIN(per, (NSInteger)slots.count); i++) {
        id item = slots[i];
        if (item == [NSNull null]) continue;
        NSInteger r = i / cols, col = i % cols;
        CGFloat x = CGRectGetMinX(area) + (area.size.width - gridW) / 2 + col * cellW, y = (usableH - gridH) / 2 + r * (cellH + gapY);
        [self drawIcon:item in:CGRectMake(x + gapX / 2, y, side, side)];
        if (self.names) {
            NSString *n = [item isKindOfClass:[NSDictionary class]] ? item[@"name"] : OMCHSName(item);
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
//  Chon app cho thu muc: danh sach co dau tich, Xong / Huy
// ---------------------------------------------------------------------
@interface OMCHSAppPicker : UITableViewController
@property (nonatomic, copy) NSArray<NSString *> *apps;
@property (nonatomic, strong) NSMutableArray<NSString *> *picked;
@property (nonatomic, copy) void (^done)(NSArray<NSString *> *picked);
@end

@implementation OMCHSAppPicker
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.tintColor = OMCAccentColor();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finish)];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)finish
{
    NSMutableArray *ordered = [NSMutableArray array];   // theo thu tu tren xe
    for (NSString *b in self.apps) if ([self.picked containsObject:b]) [ordered addObject:b];
    void (^done)(NSArray *) = self.done;
    [self dismissViewControllerAnimated:YES completion:^{ if (done) done(ordered); }];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.apps.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"a"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"a"];
    NSString *bid = self.apps[ip.row];
    c.textLabel.text = OMCHSName(bid);
    c.imageView.image = OMCHSIcon(bid, 30);
    c.accessoryType = [self.picked containsObject:bid] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSString *bid = self.apps[ip.row];
    if ([self.picked containsObject:bid]) [self.picked removeObject:bid]; else [self.picked addObject:bid];
    [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}
@end

// ---------------------------------------------------------------------
//  OMCAppBridgeAppsController - "App tren man xe": MOT trang cho App Bridge + man chinh CarPlay (tools/preview/home.html)
//    0 Xem truoc man xe   1 Man chinh OmniCar (cong tac)
//    2 Ung dung (the gap): loc Tat ca / CarPlay / iPhone, o tim, danh sach CUON RIENG (bang con) moi app - app he thong
//      cua CarPlay, app CarPlay, app iPhone; con mat = hien / an tren xe (app CarPlay: HS_KEY_HIDDEN; app iPhone: AB_KEY_APPS),
//      keo de sap xep (HS_KEY_ORDER), ghim dock (HS_KEY_DOCK)
//    3 Thu muc (HS_KEY_FOLDERS) + trang rieng cho app iPhone   4 Dock
//    5 Bo cuc icon (co, cot, hang, khoang cach, ten, hinh dang, vien kinh, bong, goi icon)   6 Widget   7 Hinh nen (ngay / dem,
//      anh hoac video) - the gap, dong thi hien tom tat
//  An / sap xep app CarPlay, thu muc can OmniCar ve man chinh: Man chinh OmniCar dang tat thi tu bat + bao.
//  Cai dat App Bridge khac (cong tac, Khung hinh) khong con tren trang: ve mac dinh mot lan (OMCAB_KEY_RESET).
// ---------------------------------------------------------------------
#define OMCAB_KEY_CARPLAY_APPS @"splitScreenCarPlayApps"   // = SPL_KEY_CARPLAY_APPS (Split Screen ghi khi cam xe)
#define OMCAB_KEY_RESET        @"appBridgeAdvancedReset"   // da dua cong tac / Khung hinh ve mac dinh
#define OMCAB_LIST_ROWS        6                           // danh sach app cao toi da 6 dong, cuon ben trong
#define OMCAB_ROW_H            52.0
enum { OMCABPreview = 0, OMCABHome, OMCABApps, OMCABFolders, OMCABDock, OMCABLayout, OMCABWidgets, OMCABWall, OMCABSectionCount };
enum { OMCABKindSystem = 0, OMCABKindCarPlay, OMCABKindPhone };
static char kOMCABKey;
static NSArray<NSString *> *OMCABWidgetKinds(void) { return @[@"clock", @"weather", @"music"]; }

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
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *folders;    // HS_KEY_FOLDERS
@property (nonatomic, strong) NSMutableArray<NSString *> *widgets;        // HS_KEY_WIDGETS
@property (nonatomic, strong) NSMutableSet<NSNumber *> *open;             // the dang mo
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;              // dong cua danh sach sau khi loc
@property (nonatomic) NSInteger filter;                                   // 0 tat ca, 1 CarPlay, 2 iPhone
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) UIImage *wallpaper, *nightWallpaper, *photo, *videoThumb;
@property (nonatomic) NSInteger wallStyle, nightStyle, wallSlot;          // wallSlot: 0 dang chinh hinh nen ngay, 1 dem
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
    _folders = [NSMutableArray array];
    for (NSDictionary *f in OMCABArray(HS_KEY_FOLDERS))
        if ([f isKindOfClass:[NSDictionary class]] && [f[@"apps"] isKindOfClass:[NSArray class]])
            [_folders addObject:@{@"name": [f[@"name"] isKindOfClass:[NSString class]] ? f[@"name"] : L(@"APPS_FOLDER_DEFAULT_NAME"), @"apps": f[@"apps"]}];
    _widgets = [NSMutableArray array];
    for (NSString *w in OMCABArray(HS_KEY_WIDGETS)) if ([OMCABWidgetKinds() containsObject:w] && ![_widgets containsObject:w] && _widgets.count < HS_WIDGETS_MAX) [_widgets addObject:w];
    _photo = [UIImage imageWithContentsOfFile:HS_PHOTO_PATH];
    _videoThumb = [[NSFileManager defaultManager] fileExistsAtPath:HS_VIDEO_PATH] ? [UIImage imageWithContentsOfFile:HS_VIDEO_THUMB_PATH] : nil;
    BOOL day = [OMCHSPref(HS_KEY_WALLPAPER, @NO) boolValue];
    _wallStyle = day ? [self num:HS_KEY_WALLPAPER_STYLE def:OMCHS_STYLE_PHOTO] : 0;
    _wallpaper = !day ? nil : _wallStyle == OMCHS_STYLE_VIDEO ? _videoThumb : [UIImage imageWithContentsOfFile:HS_WALLPAPER_PATH];
    if (!_wallpaper) _wallStyle = 0;
    _nightStyle = [self num:HS_KEY_NIGHT_STYLE def:0];
    _nightWallpaper = _nightStyle == OMCHS_STYLE_VIDEO ? _videoThumb : _nightStyle > 0 ? [UIImage imageWithContentsOfFile:HS_NIGHT_PATH] : nil;
    if (!_nightWallpaper) _nightStyle = 0;
    id theme = OMCHSPref(HS_KEY_ICON_THEME, @"");
    sOMCHSTheme = [theme isKindOfClass:[NSString class]] ? theme : @"";
    sOMCHSShape = [self num:HS_KEY_ICON_SHAPE def:0];
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

// O tren luoi (= SCPHItems): app, hoac thu muc o cho app dau tien cua no; thu muc khong con app hien thi bo
- (NSArray *)gridItems
{
    NSArray *apps = [self visibleApps];
    NSMutableDictionary *folderOf = [NSMutableDictionary dictionary];
    for (NSDictionary *f in _folders) {
        NSMutableArray *in = [NSMutableArray array];
        for (NSString *b in f[@"apps"]) if ([apps containsObject:b] && !folderOf[b]) [in addObject:b];
        if (!in.count) continue;
        NSDictionary *folder = @{@"name": f[@"name"], @"apps": in};
        for (NSString *b in in) folderOf[b] = folder;
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *b in apps) {
        NSDictionary *f = folderOf[b];
        if (!f) [out addObject:b];
        else if (![out containsObject:f]) [out addObject:f];
    }
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

// An / sap xep app CarPlay, thu muc, widget chi co tac dung khi OmniCar ve man chinh: tu bat + bao 1 dong
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

- (void)alert:(NSString *)text
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
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
    p.items = [self gridItems];
    NSMutableSet *phone = [NSMutableSet set];
    for (NSDictionary *a in _phoneApps) if (![self isCarPlayApp:a[@"id"]]) [phone addObject:a[@"id"]];
    p.phoneApps = phone;
    p.phonePage = [OMCHSPref(HS_KEY_PHONE_PAGE, @NO) boolValue];
    NSMutableArray *dock = [NSMutableArray array];
    for (NSString *b in _dock) if ([self isVisible:b]) [dock addObject:b];
    p.dock = dock;
    p.widgets = _widgets;
    // dang chinh hinh nen dem (da chon): xem truoc hinh dem
    BOOL night = _wallSlot == 1 && _nightStyle > 0;
    p.wallpaper = night ? _nightWallpaper : _wallpaper;
    p.video = (night ? _nightStyle : _wallStyle) == OMCHS_STYLE_VIDEO;
    p.on = [OMCHSPref(HS_KEY_ENABLED, @NO) boolValue];
    p.size = [self num:HS_KEY_ICON_SIZE def:100]; p.cols = [self num:HS_KEY_COLS def:5]; p.rows = [self num:HS_KEY_ROWS def:2];
    p.gap = [self num:HS_KEY_GAP def:100]; p.blur = [self num:HS_KEY_BLUR def:0]; p.dim = [self num:HS_KEY_DIM def:25];
    p.names = [OMCHSPref(HS_KEY_NAMES, @YES) boolValue];
    p.suggest = [OMCHSPref(HS_KEY_DOCK_SUGGEST, @YES) boolValue];
    p.glass = [OMCHSPref(HS_KEY_ICON_GLASS, @NO) boolValue];
    p.shadow = [OMCHSPref(HS_KEY_ICON_SHADOW, @YES) boolValue];
    [p setNeedsDisplay];
}

#pragma mark - The gap

- (BOOL)isOpen:(NSInteger)card { return [_open containsObject:@(card)]; }

- (void)reloadCard:(NSInteger)card
{
    [_table reloadSections:[NSIndexSet indexSetWithIndex:card] withRowAnimation:UITableViewRowAnimationNone];
    if (card != OMCABPreview) [self updatePreview];
}

- (NSString *)wallName:(NSInteger)style
{
    return L([NSString stringWithFormat:@"APPS_WALL_%ld", (long)MIN(OMCHS_STYLE_VIDEO, MAX(0, style))]);
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
        case OMCABFolders:
            return _folders.count ? [NSString stringWithFormat:L(@"APPS_FOLDERS_COUNT"), (long)_folders.count] : L(@"APPS_NONE");
        case OMCABDock: {
            NSUInteger n = 0;
            for (NSString *b in _dock) if ([self isVisible:b]) n++;
            if (n) return [NSString stringWithFormat:L(@"APPS_DOCK_PINNED"), (long)n];
            return L([OMCHSPref(HS_KEY_DOCK_SUGGEST, @YES) boolValue] ? @"APPS_DOCK_SUGGEST_SHORT" : @"APPS_DOCK_EMPTY");
        }
        case OMCABLayout:
            return [NSString stringWithFormat:@"%ld × %ld · %ld%%", (long)[self num:HS_KEY_COLS def:5], (long)[self num:HS_KEY_ROWS def:2], (long)[self num:HS_KEY_ICON_SIZE def:100]];
        case OMCABWidgets: {
            if (!_widgets.count) return L(@"APPS_NONE");
            NSMutableArray *names = [NSMutableArray array];
            for (NSString *w in _widgets) [names addObject:L([@"APPS_WIDGET_" stringByAppendingString:w.uppercaseString])];
            return [names componentsJoinedByString:@", "];
        }
        case OMCABWall: {
            NSString *day = [self wallName:_wallStyle];
            return _nightStyle > 0 ? [NSString stringWithFormat:@"%@ · %@", day, [NSString stringWithFormat:L(@"APPS_WALL_NIGHT_SUMMARY"), [self wallName:_nightStyle]]] : day;
        }
    }
    return nil;
}

- (void)updateHeaders
{
    for (NSNumber *card in @[@(OMCABApps), @(OMCABFolders), @(OMCABDock), @(OMCABLayout), @(OMCABWidgets), @(OMCABWall)]) {
        UITableViewCell *c = [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:card.integerValue]];
        c.detailTextLabel.text = [self summaryFor:card.integerValue];
    }
}

- (UITableViewCell *)headerCellFor:(NSInteger)card inTable:(UITableView *)tv
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"head"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"head"];
    OMCStyleCell(c);
    NSArray *info = @{@(OMCABApps): @[@"APPS_CARD", @"square.grid.2x2.fill", @"#5AB8FF"],
                      @(OMCABFolders): @[@"APPS_FOLDERS", @"folder.fill", @"#FFB340"],
                      @(OMCABDock): @[@"HOMESCREEN_DOCK", @"dock.rectangle", @"#8B7CFF"],
                      @(OMCABLayout): @[@"APPS_LAYOUT", @"square.grid.3x2.fill", @"#2BC79A"],
                      @(OMCABWidgets): @[@"APPS_WIDGETS", @"rectangle.3.group.fill", @"#FF7FA8"],
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
        case OMCABFolders: return o ? 3 + (NSInteger)_folders.count : 1;   // dau the, tung thu muc, Thu muc moi, trang app iPhone
        case OMCABDock: return o ? 3 : 1;     // dau the, chip, goi y CarPlay
        case OMCABLayout: return o ? 10 : 1;  // dau the, co icon, cot, hang, khoang cach, ten, hinh dang, vien kinh, bong, goi icon
        case OMCABWidgets: return o ? 1 + (NSInteger)OMCABWidgetKinds().count : 1;
        case OMCABWall: return o ? 7 : 1;     // dau the, ngay / dem, o hinh, Tu Anh, doi sang dem, do mo, do toi
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    if (tv == _list || ![self isOpen:s]) return nil;
    switch (s) {
        case OMCABFolders: return L(@"APPS_FOLDERS_FOOTER");
        case OMCABDock: return L(@"HOMESCREEN_DOCK_FOOTER");
        case OMCABLayout: return L(@"APPS_LAYOUT_FOOTER");
        case OMCABWidgets: return L(@"APPS_WIDGETS_FOOTER");
        case OMCABWall: return L(@"APPS_WALL_FOOTER");
    }
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
    if (ip.section == OMCABFolders && ip.row == 2 + (NSInteger)_folders.count) return 60;
    if (ip.section == OMCABDock && ip.row == 1) return [self layoutChipsIn:nil width:w];
    if (ip.section == OMCABWall && ip.row == 1) return 50;
    if (ip.section == OMCABWall && ip.row == 2) return [self layoutTilesIn:nil width:w];
    if (ip.section == OMCABWall && ip.row == 3) return 58;
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

- (UISegmentedControl *)segmentIn:(UITableViewCell *)c items:(NSArray *)items selected:(NSInteger)sel action:(SEL)action width:(CGFloat)w
{
    UIView *box = [self boxInCell:c];
    UISegmentedControl *seg = (UISegmentedControl *)[box viewWithTag:0x53];
    if (!seg || seg.numberOfSegments != (NSInteger)items.count) {
        [seg removeFromSuperview];
        seg = [[UISegmentedControl alloc] initWithItems:items];
        seg.tag = 0x53;
        [box addSubview:seg];
    }
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) [seg setTitle:items[i] forSegmentAtIndex:i];
    [seg removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
    [seg addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    seg.selectedSegmentIndex = sel;
    seg.frame = CGRectMake(12, 9, w - 24, 32);
    return seg;
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
        case OMCABFolders: {
            NSInteger n = _folders.count;
            UITableViewCell *c = [self cellWithId:@"folder" inTable:tv];
            if (ip.row <= n) {   // mot thu muc: icon 4 app nho, ten, so app
                NSDictionary *f = _folders[ip.row - 1];
                c.textLabel.text = f[@"name"];
                c.detailTextLabel.text = [NSString stringWithFormat:L(@"APPS_FOLDER_APPS"), (long)[f[@"apps"] count]];
                c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
                c.imageView.image = [self folderThumb:f[@"apps"]];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                c.selectionStyle = UITableViewCellSelectionStyleDefault;
            } else if (ip.row == n + 1) {
                c.textLabel.text = L(@"APPS_FOLDER_NEW");
                c.textLabel.textColor = OMCAccentColor();
                c.imageView.image = OMCIcon(@"folder.badge.plus", OMCColorFromHex(@"#FFB340"));
                c.selectionStyle = UITableViewCellSelectionStyleDefault;
            } else {
                c.textLabel.text = L(@"APPS_PHONE_PAGE");
                c.detailTextLabel.text = L(@"APPS_PHONE_PAGE_SUB");
                c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
                c.detailTextLabel.numberOfLines = 2;
                c.imageView.image = OMCIcon(@"iphone", OMCColorFromHex(@"#5B6CF0"));
                [self setAccessory:[self switchFor:HS_KEY_PHONE_PAGE def:NO] onCell:c];
            }
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
            if (ip.row == 6) {   // hinh dang icon
                UITableViewCell *c = [self cellWithId:@"shape" inTable:tv];
                [self segmentIn:c items:@[L(@"APPS_SHAPE_0"), L(@"APPS_SHAPE_1"), L(@"APPS_SHAPE_2")] selected:sOMCHSShape action:@selector(shapeChanged:) width:w];
                return c;
            }
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
                case 5: c.textLabel.text = L(@"HOMESCREEN_NAMES"); c.imageView.image = OMCIcon(@"textformat", OMCColorFromHex(@"#FF7FA8"));
                        [self setAccessory:[self switchFor:HS_KEY_NAMES def:YES] onCell:c]; break;
                case 7: c.textLabel.text = L(@"APPS_ICON_GLASS"); c.imageView.image = OMCIcon(@"circle.dashed.inset.filled", OMCColorFromHex(@"#5AB8FF"));
                        [self setAccessory:[self switchFor:HS_KEY_ICON_GLASS def:NO] onCell:c]; break;
                case 8: c.textLabel.text = L(@"APPS_ICON_SHADOW"); c.imageView.image = OMCIcon(@"shadow", OMCColorFromHex(@"#4A4F80"));
                        [self setAccessory:[self switchFor:HS_KEY_ICON_SHADOW def:YES] onCell:c]; break;
                default: {   // goi icon
                    UITableViewCell *v = [tv dequeueReusableCellWithIdentifier:@"pack"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"pack"];
                    OMCStyleCell(v);
                    v.textLabel.text = L(@"APPS_ICON_PACK");
                    v.imageView.image = OMCIcon(@"paintpalette.fill", OMCColorFromHex(@"#FF8A65"));
                    v.detailTextLabel.text = sOMCHSTheme.length ? OMCHSThemeName(sOMCHSTheme) : L(@"APPS_ICON_PACK_NONE");
                    v.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    v.selectionStyle = UITableViewCellSelectionStyleDefault;
                    return v;
                }
            }
            return c;
        }
        case OMCABWidgets: {
            UITableViewCell *c = [self cellWithId:@"widget" inTable:tv];
            NSString *kind = OMCABWidgetKinds()[ip.row - 1];
            NSDictionary *look = @{@"clock": @[@"clock.fill", @"#8B7CFF"], @"weather": @[@"cloud.sun.fill", @"#5AB8FF"], @"music": @[@"music.note", @"#FF5A7A"]}[kind];
            c.textLabel.text = L([@"APPS_WIDGET_" stringByAppendingString:kind.uppercaseString]);
            c.imageView.image = OMCIcon(look[0], OMCColorFromHex(look[1]));
            UISwitch *sw = [UISwitch new];
            sw.onTintColor = OMCSwitchColor();
            sw.on = [_widgets containsObject:kind];
            objc_setAssociatedObject(sw, &kOMCABKey, kind, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [sw addTarget:self action:@selector(widgetSwitched:) forControlEvents:UIControlEventValueChanged];
            [self setAccessory:sw onCell:c];
            return c;
        }
    }
    // Hinh nen: ngay / dem, o hinh, Tu Anh, doi sang dem, do mo, do toi
    if (ip.row == 1) {
        UITableViewCell *c = [self cellWithId:@"slot" inTable:tv];
        [self segmentIn:c items:@[L(@"APPS_WALL_DAY"), L(@"APPS_WALL_NIGHT")] selected:_wallSlot action:@selector(slotChanged:) width:w];
        return c;
    }
    UITableViewCell *c = [self cellWithId:(ip.row == 2 ? @"tiles" : @"wall") inTable:tv];
    if (ip.row == 2) { [self layoutTilesIn:[self boxInCell:c] width:w]; return c; }
    if (ip.row == 3) {
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
        [b setTitle:L(@"APPS_FROM_PHOTOS") forState:UIControlStateNormal];
        b.frame = CGRectMake(12, 4, w - 24, 42);
        return c;
    }
    if (ip.row == 4) {   // doi sang dem: theo xe / mat troi
        UITableViewCell *v = [tv dequeueReusableCellWithIdentifier:@"nightby"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"nightby"];
        OMCStyleCell(v);
        v.textLabel.text = L(@"APPS_NIGHT_BY");
        v.imageView.image = OMCIcon(@"sunset.fill", OMCColorFromHex(@"#FFB340"));
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[L(@"APPS_NIGHT_BY_CAR"), L(@"APPS_NIGHT_BY_SUN")]];
        seg.selectedSegmentIndex = [self num:HS_KEY_NIGHT_BY def:0];
        [seg addTarget:self action:@selector(nightByChanged:) forControlEvents:UIControlEventValueChanged];
        [seg sizeToFit];
        v.accessoryView = seg;
        v.selectionStyle = UITableViewCellSelectionStyleNone;
        v.textLabel.alpha = v.imageView.alpha = _nightStyle > 0 ? 1 : 0.4;
        seg.enabled = _nightStyle > 0;
        return v;
    }
    BOOL blur = ip.row == 5;
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
    if (tv == _list || ip.section < OMCABApps) return;
    if (ip.row == 0) {   // dau the: mo / dong
        NSNumber *card = @(ip.section);
        if ([_open containsObject:card]) [_open removeObject:card]; else [_open addObject:card];
        [self.view endEditing:YES];
        [_table reloadSections:[NSIndexSet indexSetWithIndex:ip.section] withRowAnimation:UITableViewRowAnimationFade];
        return;
    }
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    if (ip.section == OMCABFolders && ip.row <= (NSInteger)_folders.count) [self editFolder:ip.row - 1 from:cell];
    else if (ip.section == OMCABFolders && ip.row == (NSInteger)_folders.count + 1) [self newFolder];
    else if (ip.section == OMCABLayout && ip.row == 9) [self pickIconPack:cell];
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
    if (sw.on && [key isEqualToString:HS_KEY_PHONE_PAGE]) [self ensureHomeOn];
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

#pragma mark - Hinh dang, goi icon

- (void)shapeChanged:(UISegmentedControl *)seg
{
    sOMCHSShape = seg.selectedSegmentIndex;
    OMCHSStore(HS_KEY_ICON_SHAPE, @(sOMCHSShape));
    [self reloadCard:OMCABDock];
    [self reloadCard:OMCABFolders];
}

- (void)pickIconPack:(UIView *)from
{
    NSArray *themes = OMCHSThemes();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:L(@"APPS_ICON_PACK") message:themes.count ? nil : L(@"APPS_ICON_PACK_EMPTY")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    void (^use)(NSString *) = ^(NSString *theme) {
        sOMCHSTheme = theme;
        OMCHSStore(HS_KEY_ICON_THEME, theme);
        [self reloadCard:OMCABLayout];
        [self reloadCard:OMCABDock];
        [self reloadCard:OMCABFolders];
    };
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"APPS_ICON_PACK_NONE") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { use(@""); }]];
    for (NSString *t in themes)
        [sheet addAction:[UIAlertAction actionWithTitle:OMCHSThemeName(t) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { use(t); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = from;
    sheet.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Thu muc

- (UIImage *)folderThumb:(NSArray<NSString *> *)apps
{
    CGFloat side = 29, pad = 3, gap = 2, mini = (side - pad * 2 - gap) / 2;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)] imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        [[UIColor colorWithWhite:0.5 alpha:0.18] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:OMCHSCorner(side)] fill];
        for (NSInteger i = 0; i < MIN(4, (NSInteger)apps.count); i++) {
            UIImage *m = OMCHSIcon(apps[i], mini);
            [m drawInRect:CGRectMake(pad + (i % 2) * (mini + gap), pad + (i / 2) * (mini + gap), mini, mini)];
        }
    }];
}

- (void)saveFolders
{
    OMCHSStore(HS_KEY_FOLDERS, [_folders copy]);
    [self reloadCard:OMCABFolders];
    [self updatePreview];
}

// App chon duoc cho thu muc: app dang hien tren xe, tru app da o thu muc khac
- (void)pickAppsForFolder:(NSInteger)index title:(NSString *)title done:(void (^)(NSArray<NSString *> *))done
{
    NSMutableSet *taken = [NSMutableSet set];
    for (NSInteger i = 0; i < (NSInteger)_folders.count; i++) if (i != index) [taken addObjectsFromArray:_folders[i][@"apps"]];
    NSMutableArray *apps = [NSMutableArray array];
    for (NSString *b in [self visibleApps]) if (![taken containsObject:b]) [apps addObject:b];
    OMCHSAppPicker *picker = [[OMCHSAppPicker alloc] initWithStyle:UITableViewStyleInsetGrouped];
    picker.title = title;
    picker.apps = apps;
    picker.picked = [NSMutableArray arrayWithArray:index >= 0 ? _folders[index][@"apps"] : @[]];
    picker.done = done;
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}

- (void)askName:(NSString *)current done:(void (^)(NSString *))done
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:L(@"APPS_FOLDER_NAME") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = current;
        tf.placeholder = L(@"APPS_FOLDER_DEFAULT_NAME");
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    }];
    [a addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *n = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        done(n.length ? n : L(@"APPS_FOLDER_DEFAULT_NAME"));
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)newFolder
{
    [self askName:@"" done:^(NSString *name) {
        [self pickAppsForFolder:-1 title:name done:^(NSArray<NSString *> *apps) {
            if (!apps.count) return;
            [self.folders addObject:@{@"name": name, @"apps": apps}];
            [self ensureHomeOn];
            [self saveFolders];
        }];
    }];
}

- (void)editFolder:(NSInteger)index from:(UIView *)from
{
    NSDictionary *f = _folders[index];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:f[@"name"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"APPS_FOLDER_PICK") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self pickAppsForFolder:index title:f[@"name"] done:^(NSArray<NSString *> *apps) {
            if (apps.count) self.folders[index] = @{@"name": f[@"name"], @"apps": apps};
            else [self.folders removeObjectAtIndex:index];
            [self saveFolders];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"APPS_FOLDER_RENAME") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self askName:f[@"name"] done:^(NSString *name) {
            self.folders[index] = @{@"name": name, @"apps": f[@"apps"]};
            [self saveFolders];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"APPS_FOLDER_DELETE") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self.folders removeObjectAtIndex:index];
        [self saveFolders];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = from;
    sheet.popoverPresentationController.sourceRect = from.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Widget

- (void)widgetSwitched:(UISwitch *)sw
{
    NSString *kind = objc_getAssociatedObject(sw, &kOMCABKey);
    if (sw.on && _widgets.count >= HS_WIDGETS_MAX) {
        [sw setOn:NO animated:YES];
        [self alert:L(@"APPS_WIDGETS_MAX")];
        return;
    }
    if (sw.on) [_widgets addObject:kind]; else [_widgets removeObject:kind];
    OMCHSStore(HS_KEY_WIDGETS, [_widgets copy]);
    if (sw.on) [self ensureHomeOn];
    [self updateHeaders];
    [self updatePreview];
}

#pragma mark - Hinh nen

- (void)slotChanged:(UISegmentedControl *)seg
{
    _wallSlot = seg.selectedSegmentIndex;
    [self reloadCard:OMCABWall];
}

- (void)nightByChanged:(UISegmentedControl *)seg
{
    OMCHSStore(HS_KEY_NIGHT_BY, @(seg.selectedSegmentIndex));
}

- (CGFloat)layoutTilesIn:(UIView *)v width:(CGFloat)w
{
    NSMutableArray *styles = [NSMutableArray array];
    for (NSInteger i = 0; i <= OMCHS_PRESETS; i++) [styles addObject:@(i)];
    if (_photo) [styles addObject:@(OMCHS_STYLE_PHOTO)];
    if (_videoThumb) [styles addObject:@(OMCHS_STYLE_VIDEO)];
    NSInteger n = styles.count, cols = 4, selected = _wallSlot ? _nightStyle : _wallStyle;
    CGFloat pad = 12, gap = 8, tw = floor((w - pad * 2 - gap * (cols - 1)) / cols), th = floor(tw / 1.6);
    NSInteger rows = (n + cols - 1) / cols;
    CGFloat h = pad * 2 + rows * th + (rows - 1) * gap;
    if (!v) return h;
    for (UIView *old in [v.subviews copy]) [old removeFromSuperview];
    for (NSInteger k = 0; k < n; k++) {
        NSInteger style = [styles[k] integerValue];
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
            [b setTitle:L(_wallSlot ? @"APPS_WALL_SAME" : @"HOMESCREEN_WALLPAPER_DEFAULT") forState:UIControlStateNormal];
            [b setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:12];
            b.titleLabel.adjustsFontSizeToFitWidth = YES;
            b.titleLabel.textAlignment = NSTextAlignmentCenter;
            b.titleLabel.numberOfLines = 2;
        } else {
            UIImage *img = style == OMCHS_STYLE_PHOTO ? _photo : style == OMCHS_STYLE_VIDEO ? _videoThumb : OMCHSPresetImage(style, CGSizeMake(tw, th), [UIScreen mainScreen].scale);
            [b setBackgroundImage:img forState:UIControlStateNormal];
            b.imageView.contentMode = UIViewContentModeScaleAspectFill;
            b.contentMode = UIViewContentModeScaleAspectFill;
            if (style == OMCHS_STYLE_VIDEO) {   // dau phat
                [b setImage:[UIImage systemImageNamed:@"play.circle.fill"] forState:UIControlStateNormal];
                b.tintColor = [UIColor whiteColor];
            }
        }
        [b addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:b];
        if (style == selected) {   // vien cau vong 4 mau logo quanh o dang chon (nam ngoai o 3pt)
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
    [self useStyle:b.tag];
}

// Chon hinh nen cho o dang chinh (ngay / dem). 0: ngay = hinh nen CarPlay, dem = nhu ban ngay; 1..7 ghi JPEG; 8 = video
- (void)useStyle:(NSInteger)style
{
    BOOL night = _wallSlot == 1;
    NSString *path = night ? HS_NIGHT_PATH : HS_WALLPAPER_PATH;
    if (style == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        if (night) { _nightWallpaper = nil; _nightStyle = 0; OMCHSStore(HS_KEY_NIGHT_STYLE, @0); }
        else { _wallpaper = nil; _wallStyle = 0; OMCHSStore(HS_KEY_WALLPAPER_STYLE, @0); OMCHSStore(HS_KEY_WALLPAPER, @NO); }
    } else {
        UIImage *img = style == OMCHS_STYLE_VIDEO ? _videoThumb : style == OMCHS_STYLE_PHOTO ? _photo : OMCHSPresetImage(style, CGSizeMake(1920, 720), 1);
        if (!img) return;
        if (style != OMCHS_STYLE_VIDEO && ![self writeJPEG:img to:path]) return;
        if (night) { _nightWallpaper = img; _nightStyle = style; OMCHSStore(HS_KEY_NIGHT_STYLE, @(style)); }
        else { _wallpaper = img; _wallStyle = style; OMCHSStore(HS_KEY_WALLPAPER_STYLE, @(style)); OMCHSStore(HS_KEY_WALLPAPER, @YES); }
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
    else { [self alert:L(@"HOMESCREEN_DOCK_FULL")]; return; }
    OMCHSStore(HS_KEY_DOCK, [_dock copy]);
    [self reloadCard:OMCABDock]; [self.list reloadData];
    [self updatePreview];
}

// Tu Anh: anh hoac video (video: cat 20 giay dau, 1280 px, bo tieng)
- (void)pickPhoto
{
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[UTTypeImage.identifier, UTTypeMovie.identifier];
    picker.videoExportPreset = AVAssetExportPresetPassthrough;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (BOOL)writeJPEG:(UIImage *)img to:(NSString *)path
{
    NSData *jpg = UIImageJPEGRepresentation(img, 0.85);
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *err = nil;
    if (!jpg || ![jpg writeToFile:path options:NSDataWritingAtomic error:&err]) {
        [self alert:err.localizedDescription ?: @"JPEG"];
        return NO;
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:path error:nil];
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
    [self useStyle:OMCHS_STYLE_PHOTO];
}

// Video tu Anh -> HS_VIDEO_PATH (mp4 1280 px, khong tieng, toi da OMCHS_VIDEO_MAX giay) + khung dau HS_VIDEO_THUMB_PATH
- (void)useVideo:(NSURL *)url
{
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!track) { [self alert:L(@"APPS_VIDEO_FAILED")]; return; }
    AVMutableComposition *comp = [AVMutableComposition composition];
    AVMutableCompositionTrack *vt = [comp addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    CMTime length = CMTimeMinimum(asset.duration, CMTimeMakeWithSeconds(OMCHS_VIDEO_MAX, 600));
    NSError *err = nil;
    if (![vt insertTimeRange:CMTimeRangeMake(kCMTimeZero, length) ofTrack:track atTime:kCMTimeZero error:&err]) { [self alert:err.localizedDescription ?: L(@"APPS_VIDEO_FAILED")]; return; }
    vt.preferredTransform = track.preferredTransform;
    AVAssetExportSession *ex = [AVAssetExportSession exportSessionWithAsset:comp presetName:AVAssetExportPreset1280x720];
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"omnicar-wallpaper.mp4"];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
    ex.outputURL = [NSURL fileURLWithPath:tmp];
    ex.outputFileType = AVFileTypeMPEG4;
    ex.shouldOptimizeForNetworkUse = YES;
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:nil message:L(@"APPS_VIDEO_WORKING") preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:nil];
    [ex exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [wait dismissViewControllerAnimated:YES completion:^{
                if (ex.status != AVAssetExportSessionStatusCompleted) { [self alert:ex.error.localizedDescription ?: L(@"APPS_VIDEO_FAILED")]; return; }
                NSFileManager *fm = [NSFileManager defaultManager];
                [fm createDirectoryAtPath:HS_VIDEO_PATH.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                [fm removeItemAtPath:HS_VIDEO_PATH error:nil];
                NSError *mv = nil;
                if (![fm moveItemAtPath:tmp toPath:HS_VIDEO_PATH error:&mv]) { [self alert:mv.localizedDescription ?: L(@"APPS_VIDEO_FAILED")]; return; }
                [fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:HS_VIDEO_PATH error:nil];
                AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:HS_VIDEO_PATH] options:nil]];
                gen.appliesPreferredTrackTransform = YES;
                CGImageRef cg = [gen copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
                UIImage *thumb = cg ? [UIImage imageWithCGImage:cg] : nil;
                if (cg) CGImageRelease(cg);
                if (!thumb || ![self writeJPEG:thumb to:HS_VIDEO_THUMB_PATH]) return;
                self.videoThumb = thumb;
                [self useStyle:OMCHS_STYLE_VIDEO];
                [self ensureHomeOn];
            }];
        });
    }];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info
{
    NSURL *movie = info[UIImagePickerControllerMediaURL];
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (movie) [self useVideo:movie];
        else [self useWallpaper:img];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }

@end
