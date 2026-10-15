// "Man xe" cua trang chinh OmniCar, hai dong (xem truoc: tools/preview/index.html#home):
//  - "App tren man xe" (OMCAppBridgeAppsLinkCell, hien so app da chon) mo OMCAppBridgeAppsController: tren la cac app dang
//    hien tren xe, duoi 2 tab App CarPlay (cong tac = hien / an icon, HS_KEY_HIDDEN_APPS) / App OmniCar = app iPhone nao len xe (AB_KEY_APPS; CarPlay
//    (SCPCPhoneAppSet, SCPAppIcons) va bang chon app cua Chia man hinh dung dung danh sach nay)
//  - "Man chinh CarPlay" mo OMCHomeScreenController (cung lop, chi hien phan con lai): xem truoc, luoi icon (so cot
//    HS_KEY_COLS, so hang HS_KEY_ROWS, co icon HS_KEY_ICON_SIZE, ten app HS_KEY_NAMES) va hinh nen (HS_KEY_WALLPAPER*). Man chinh CarPlay giu nguyen: Features/SplitScreen/SCPHomeScreen.mm
//    chi chen hinh nen duoi luoi icon va doi co icon qua layout cua CarPlay.
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
// Doc qua entitlements (dict), khong co thi hoi tung key qua entitlementValueForKey:ofClass: (Preferences thuong khong
// duoc tra ca dict entitlements cua app khac)
static BOOL OMCABHasCarPlayEntitlement(id proxy)
{
    NSDictionary *ent = OMCABGet(proxy, @"entitlements");
    if ([ent isKindOfClass:[NSDictionary class]] && ent.count) {
        for (NSString *k in ent) {
            if ([k hasPrefix:@"com.apple.developer.carplay"] || [k isEqualToString:@"com.apple.developer.playable-content"]) return YES;
        }
        return NO;
    }
    SEL one = NSSelectorFromString(@"entitlementValueForKey:ofClass:");
    if (![proxy respondsToSelector:one]) return NO;
    for (NSString *k in @[@"com.apple.developer.carplay-audio", @"com.apple.developer.carplay-communication", @"com.apple.developer.carplay-messaging",
                          @"com.apple.developer.carplay-calling", @"com.apple.developer.carplay-maps", @"com.apple.developer.carplay-charging",
                          @"com.apple.developer.carplay-parking", @"com.apple.developer.carplay-fueling", @"com.apple.developer.carplay-quick-ordering",
                          @"com.apple.developer.carplay-driving-task", @"com.apple.developer.carplay-public-safety", @"com.apple.developer.playable-content"]) {
        id v = nil;
        @try { v = ((id (*)(id, SEL, id, Class))objc_msgSend)(proxy, one, k, [NSObject class]); } @catch (NSException *e) {}
        if (v && ![v isEqual:@NO]) return YES;
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

// Chua cam xe lan nao (CarPlay chua ghi danh sach): doan app CarPlay = app Apple co tren xe + app co entitlement CarPlay
static NSArray<NSString *> *OMCABGuessCarPlayApps(void)
{
    NSArray *apple = @[@"com.apple.Maps", @"com.apple.Music", @"com.apple.mobilephone", @"com.apple.MobileSMS", @"com.apple.podcasts",
                       @"com.apple.iBooks", @"com.apple.news", @"com.apple.mobilecal"];
    NSMutableArray *out = [NSMutableArray array], *third = [NSMutableArray array];
    NSMutableSet *installed = [NSMutableSet set];
    Class WS = objc_getClass("LSApplicationWorkspace");
    for (id proxy in OMCABGet(OMCABGet(WS, @"defaultWorkspace"), @"allInstalledApplications")) {
        NSString *bid = OMCABGet(proxy, @"bundleIdentifier");
        if (![bid isKindOfClass:[NSString class]] || !bid.length) continue;
        [installed addObject:bid];
        if (![apple containsObject:bid] && OMCABHasCarPlayEntitlement(proxy)) [third addObject:bid];
    }
    for (NSString *bid in apple) if ([installed containsObject:bid]) [out addObject:bid];
    [out addObjectsFromArray:third];
    return out;
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

static NSDictionary<NSString *, NSString *> *sOMCHSCarNames;   // ten do xe ghi (HS_KEY_CAR_APPS): app rieng cua CarPlay

static NSString *OMCHSName(NSString *bid)
{
    NSString *car = sOMCHSCarNames[bid];
    if (car.length && ![car isEqualToString:bid]) return car;
    Class lp = objc_getClass("LSApplicationProxy");
    SEL forId = NSSelectorFromString(@"applicationProxyForIdentifier:"), name = NSSelectorFromString(@"localizedName");
    id proxy = [lp respondsToSelector:forId] ? ((id (*)(id, SEL, id))objc_msgSend)(lp, forId, bid) : nil;
    NSString *n = [proxy respondsToSelector:name] ? ((id (*)(id, SEL))objc_msgSend)(proxy, name) : nil;
    return [n isKindOfClass:[NSString class]] && n.length ? n : bid;
}

// Icon app bo tron nhu CarPlay
static UIImage *OMCHSIcon(NSString *bid, CGFloat side)
{
    static NSCache *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@/%.0f", bid, side];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    UIImage *icon = nil;
    // App khong cai tren iPhone thi ham nay tra icon trang mac dinh chu khong phai nil -> chi hoi khi co app that
    Class lp = objc_getClass("LSApplicationProxy");
    SEL forId = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy = [lp respondsToSelector:forId] ? ((id (*)(id, SEL, id))objc_msgSend)(lp, forId, bid) : nil;
    id state = OMCABGet(proxy, @"appState");
    BOOL installed = proxy && (!state || OMCABGetBool(state, @"isInstalled"));
    if (installed && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
    if (!icon) {   // app rieng cua CarPlay (Dang phat, Cai dat, app Xe) khong co icon tren iPhone: o bo tron + bieu tuong
        NSString *sym = [bid rangeOfString:@"NowPlaying" options:NSCaseInsensitiveSearch].location != NSNotFound ? @"play.fill"
                      : [bid rangeOfString:@"Settings"].location != NSNotFound ? @"gearshape.fill"
                      : [bid hasPrefix:@"com.apple.CarPlay"] ? @"car.fill" : @"app.fill";
        UIColor *top = [sym isEqualToString:@"play.fill"] ? OMCColorFromHex(@"#FF8A65") : [sym isEqualToString:@"car.fill"] ? OMCColorFromHex(@"#5AB8FF") : OMCColorFromHex(@"#9AA0A8");
        UIColor *bottom = [sym isEqualToString:@"play.fill"] ? OMCColorFromHex(@"#FF3D71") : [sym isEqualToString:@"car.fill"] ? OMCColorFromHex(@"#2E7CF6") : OMCColorFromHex(@"#636A73");
        UIImage *glyph = [[UIImage systemImageNamed:sym withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:side * 0.42 weight:UIImageSymbolWeightSemibold]]
                          imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        UIImage *out = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.225] addClip];
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)@[(id)top.CGColor, (id)bottom.CGColor], (CGFloat[]){0, 1});
            CGContextDrawLinearGradient(ctx.CGContext, g, CGPointZero, CGPointMake(0, side), 0);
            CGGradientRelease(g); CGColorSpaceRelease(cs);
            [glyph drawInRect:CGRectMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2, glyph.size.width, glyph.size.height)];
        }];
        [cache setObject:out forKey:key];
        return out;
    }
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *out = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.225] addClip];
        [icon drawInRect:CGRectMake(0, 0, side, side)];
    }];
    [cache setObject:out forKey:key];
    return out;
}

// ---------------------------------------------------------------------
//  Hinh nen dung san: 6 mau gradient giong tools/preview/index.html#home (WALLS 1..6). Ve bang Core Graphics theo cach CSS:
//  linear-gradient(<goc>deg) va radial-gradient(circle at x y, mau, trong suot R%) (ban kinh = goc xa nhat).
// ---------------------------------------------------------------------
#define OMCHS_PRESETS 6
#define OMCHS_STYLE_PHOTO 7   // HS_KEY_WALLPAPER_STYLE: 0 mac dinh, 1..6 hinh dung san, 7 anh, 8 video
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
//  Xem truoc: man xe mo phong theo kieu man chinh CarPlay (dock trai, luoi 5 x 2 cua CarPlay) voi co icon + hinh nen da chon
// ---------------------------------------------------------------------
@interface OMCHSPreview : UIView
@property (nonatomic, copy) NSArray<NSString *> *items;   // app CarPlay theo thu tu xe + app iPhone da chon
@property (nonatomic, strong) UIImage *wallpaper;
@property (nonatomic) NSInteger size, blur, dim, cols, rows;   // cols / rows 0 = Tu dong (5 x 2 nhu CarPlay)
@property (nonatomic) BOOL names;
@property (nonatomic) BOOL video;
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
- (void)drawIcon:(NSString *)bid in:(CGRect)ir
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat side = ir.size.width;
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 3), 6, [UIColor colorWithWhite:0 alpha:0.3].CGColor);
    UIImage *ic = OMCHSIcon(bid, side);
    if (ic) [ic drawInRect:ir];
    else { [[UIColor colorWithWhite:1 alpha:0.2] setFill]; [[UIBezierPath bezierPathWithRoundedRect:ir cornerRadius:side * 0.225] fill]; }
    CGContextRestoreGState(c);
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
    if (self.wallpaper) {
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
    // dock cua CarPlay (goi y cua xe)
    [[UIColor colorWithRed:0.06 green:0.07 blue:0.08 alpha:1] setFill]; UIRectFill(CGRectMake(0, 0, dockW, H));
    NSDictionary *ta = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:12], NSForegroundColorAttributeName: [UIColor whiteColor]};
    [@"9:41" drawAtPoint:CGPointMake(17, 8) withAttributes:ta];
    CGFloat dy = 34;
    for (NSString *b in @[@"com.apple.Maps", @"com.apple.Music"]) { [self drawIcon:b in:CGRectMake(11, dy, 42, 42)]; dy += 50; }
    for (int i = 0; i < 6; i++) {   // nut Home: luoi 3 x 2
        [[UIColor colorWithWhite:0.8 alpha:1] setFill];
        UIRectFill(CGRectMake(18 + (i % 3) * 10, H - 30 + (i / 3) * 9, 7, 6));
    }
    // luoi cua CarPlay (Tu dong = 5 x 2) hoac so cot / hang da chon; icon to / nho trong o (nhu hook iconImageInfo)
    NSInteger cols = self.cols > 0 ? self.cols : 5, rows = self.rows > 0 ? self.rows : 2, per = cols * rows;
    CGFloat cellW = (area.size.width - 24) / cols, cellH = (H - 30) / rows, side = round(64 * self.size / 100.0);
    NSInteger pages = MAX(1, ((NSInteger)self.items.count + per - 1) / per);
    NSDictionary *na = @{NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor whiteColor]};
    for (NSInteger i = 0; i < MIN(per, (NSInteger)self.items.count); i++) {
        NSString *bid = self.items[i];
        NSInteger r = i / cols, col = i % cols;
        CGFloat cx = CGRectGetMinX(area) + 12 + col * cellW + cellW / 2, cy = 6 + r * cellH + cellH / 2 - (self.names ? 10 : 0);
        [self drawIcon:bid in:CGRectMake(cx - side / 2, cy - side / 2, side, side)];
        if (!self.names) continue;
        NSString *n = OMCHSName(bid);
        CGSize ns = [n sizeWithAttributes:na];
        CGFloat w = MIN(ns.width, cellW - 6);
        [n drawWithRect:CGRectMake(cx - w / 2, cy + side / 2 + 4, w, 16) options:NSStringDrawingTruncatesLastVisibleLine attributes:na context:nil];
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
//  OMCAppBridgeAppsController - "App tren man xe" / OMCHomeScreenController - "Man chinh CarPlay" (tools/preview/index.html#home)
//    0 Xem truoc man xe                                                                                      (bo cuc)
//    1 Tren xe: luoi icon app CarPlay + app iPhone da chon (dau iPhone)                                      (app)
//    2 Tab App CarPlay / App OmniCar, o tim + danh sach CUON RIENG: CarPlay = app co giao dien CarPlay, cong tac = hien
//      icon tren man chinh (HS_KEY_HIDDEN_APPS; xe chua cam thi doan theo entitlement); OmniCar = moi app iPhone host duoc, cong tac = dua len xe (AB_KEY_APPS)  (app)
//    3 Luoi icon: so cot / so hang (Tu dong = nhu CarPlay), co icon (HS_KEY_ICON_SIZE, 60..130 %), ten app       (man chinh)
//    4 Hinh nen (the gap): hinh dung san, anh hoac video, do mo, do toi                                      (bo cuc)
//  Moi trang chi hien the cua minh (the cua trang kia 0 dong, khong khoang trong).
//  Cai dat App Bridge khac (cong tac, Khung hinh) khong con tren trang: ve mac dinh mot lan (OMCAB_KEY_RESET).
// ---------------------------------------------------------------------
#define OMCAB_KEY_CARPLAY_APPS @"splitScreenCarPlayApps"   // = SPL_KEY_CARPLAY_APPS (Split Screen ghi khi cam xe)
#define OMCAB_KEY_RESET        @"appBridgeAdvancedReset"   // da dua cong tac / Khung hinh ve mac dinh
#define OMCAB_LIST_ROWS        6                           // danh sach app cao toi da 6 dong, cuon ben trong
#define OMCAB_ROW_H            52.0
#define OMCAB_GRID_ICON        44.0                        // luoi "Tren xe"
#define OMCAB_GRID_ROW         62.0
enum { OMCABPreview = 0, OMCABOnCar, OMCABApps, OMCABGrid, OMCABWall, OMCABSectionCount };
enum { OMCABGridCols = 0, OMCABGridRows, OMCABGridSize, OMCABGridNames, OMCABGridCount };
enum { OMCABTabCarPlay = 0, OMCABTabOmniCar };
static char kOMCABKey;

static NSArray *OMCABArray(NSString *key)
{
    id v = OMCABPref(key);
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

@interface OMCAppBridgeAppsController : PSViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITableView *list;                          // danh sach app trong the App iPhone (cuon rieng)
@property (nonatomic, strong) OMCHSPreview *preview;
@property (nonatomic, strong) NSArray<NSDictionary *> *phoneApps;         // moi app iPhone host duoc (OMCABHostableApps)
@property (nonatomic, strong) NSArray<NSString *> *carplayApps;           // app CarPlay xe da doc (cho xem truoc)
@property (nonatomic, strong) NSArray<NSString *> *guessApps;             // xe chua doc: app CarPlay doan (OMCABGuessCarPlayApps)
@property (nonatomic) NSInteger tab;                                      // OMCABTabCarPlay / OMCABTabOmniCar
@property (nonatomic, strong) NSMutableSet<NSString *> *chosen;           // AB_KEY_APPS
@property (nonatomic, strong) NSMutableSet<NSString *> *hidden;           // HS_KEY_HIDDEN_APPS (app CarPlay an khoi man chinh)
@property (nonatomic, strong) NSMutableSet<NSNumber *> *open;             // the dang mo
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;              // dong cua danh sach sau khi tim
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) UIImage *wallpaper, *photo, *videoThumb;
@property (nonatomic) NSInteger wallStyle;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *icons;
@end

@implementation OMCAppBridgeAppsController

- (BOOL)layoutPage { return NO; }   // OMCHomeScreenController: YES
- (BOOL)shows:(NSInteger)card { return (card == OMCABOnCar || card == OMCABApps) != [self layoutPage]; }

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
    self.title = self.specifier.name ?: L([self layoutPage] ? @"HOME_SCREEN" : @"APPS_TITLE");
    self.view.tintColor = OMCAccentColor();
    OMCStyleTable(_table);
    _icons = [NSCache new];
    _open = [NSMutableSet setWithObject:@(OMCABWall)];
    _tab = OMCABTabOmniCar;
    [self resetAdvancedOnce];
    [self loadState];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self loadState];   // Siri co the da doi
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
    // Uu tien danh sach man chinh xe ghi (HS_KEY_CAR_APPS: dung thu tu, co app rieng cua CarPlay + ten); ban cu chua co
    // thi danh sach Chia man hinh (chi app chia man duoc); chua cam xe lan nao thi doan (OMCABGuessCarPlayApps)
    NSMutableArray *ids = [NSMutableArray array];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (NSDictionary *a in OMCABArray(HS_KEY_CAR_APPS)) {
        if (![a isKindOfClass:[NSDictionary class]] || ![a[@"id"] isKindOfClass:[NSString class]]) continue;
        [ids addObject:a[@"id"]];
        if ([a[@"name"] isKindOfClass:[NSString class]]) names[a[@"id"]] = a[@"name"];
    }
    sOMCHSCarNames = names;
    _carplayApps = ids.count ? ids : OMCABArray(OMCAB_KEY_CARPLAY_APPS);
    if (!_carplayApps.count && !_guessApps) _guessApps = OMCABGuessCarPlayApps();
    _chosen = [NSMutableSet setWithArray:OMCABChosenApps()];
    _hidden = [NSMutableSet set];
    for (NSString *bid in OMCABArray(HS_KEY_HIDDEN_APPS)) if (!HSIsLockedCarPlayApp(bid)) [_hidden addObject:bid];   // app CarPlay khoa: luon hien
    _photo = [UIImage imageWithContentsOfFile:HS_PHOTO_PATH];
    _videoThumb = [[NSFileManager defaultManager] fileExistsAtPath:HS_VIDEO_PATH] ? [UIImage imageWithContentsOfFile:HS_VIDEO_THUMB_PATH] : nil;
    BOOL on = [OMCHSPref(HS_KEY_WALLPAPER, @NO) boolValue];
    _wallStyle = on ? [self num:HS_KEY_WALLPAPER_STYLE def:OMCHS_STYLE_PHOTO] : 0;
    _wallpaper = !on ? nil : _wallStyle == OMCHS_STYLE_VIDEO ? _videoThumb : [UIImage imageWithContentsOfFile:HS_WALLPAPER_PATH];
    if (!_wallpaper) _wallStyle = 0;
    [self rebuildRows];
}

#pragma mark - App iPhone

// App CarPlay (xe da doc, khong thi doan) + app da an (xe chi ghi app dang hien nen app an phai them lai), bo app iPhone
// da chon (CarPlay ghi ca app App Bridge)
- (BOOL)carplayGuessed { return !_carplayApps.count; }
- (NSArray<NSString *> *)carplayIDs
{
    NSMutableArray *ids = [NSMutableArray array];
    NSArray *hidden = [[_hidden allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [OMCHSName(a) localizedCaseInsensitiveCompare:OMCHSName(b)];
    }];
    for (NSString *bid in [([self carplayGuessed] ? _guessApps : _carplayApps) arrayByAddingObjectsFromArray:hidden])
        if ([bid isKindOfClass:[NSString class]] && ![_chosen containsObject:bid] && ![ids containsObject:bid]) [ids addObject:bid];
    return ids;
}

// Luoi "Tren xe": app CarPlay roi app iPhone da chon (theo ten) - @[bid, la app iPhone]
- (NSArray<NSArray *> *)onCarItems
{
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *bid in [self carplayIDs]) if (![_hidden containsObject:bid]) [items addObject:@[bid, @NO]];
    for (NSDictionary *a in _phoneApps) if ([_chosen containsObject:a[@"id"]]) [items addObject:@[a[@"id"], @YES]];
    return items;
}

// Danh sach cua tab dang chon (theo ten), loc theo o tim
- (void)rebuildRows
{
    NSString *q = _query.length ? _query : nil;
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *source = _phoneApps;
    if (_tab == OMCABTabCarPlay) {
        NSMutableArray *cp = [NSMutableArray array];
        for (NSString *bid in [self carplayIDs]) [cp addObject:@{@"id": bid, @"name": OMCHSName(bid), @"carplay": @YES}];
        source = cp;
    }
    for (NSDictionary *a in source) {
        if (q && [a[@"name"] rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
        [rows addObject:a];
    }
    _rows = rows;
}

- (UIImage *)iconFor:(NSString *)bid
{
    UIImage *icon = [_icons objectForKey:bid];
    if (!icon) { icon = OMCHSIcon(bid, 36); if (icon) [_icons setObject:icon forKey:bid]; }
    return icon;
}

- (void)alert:(NSString *)text
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// Cong tac "len xe" cua mot app iPhone
- (void)appSwitched:(UISwitch *)sw
{
    NSString *bid = objc_getAssociatedObject(sw, &kOMCABKey);
    if (sw.on) [_chosen addObject:bid]; else [_chosen removeObject:bid];
    NSMutableArray *ids = [NSMutableArray array];   // giu thu tu theo ten
    for (NSDictionary *a in _phoneApps) if ([_chosen containsObject:a[@"id"]]) [ids addObject:a[@"id"]];
    OMCABStore(AB_KEY_APPS, ids);
    [_table reloadSections:[NSIndexSet indexSetWithIndex:OMCABOnCar] withRowAnimation:UITableViewRowAnimationNone];
    [self updatePreview];
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text
{
    _query = text;
    [self rebuildRows];
    [_list reloadData];
    [_table beginUpdates]; [_table endUpdates];
    [self layoutListCell];
}

// Cong tac cua mot app CarPlay: tat = an icon khoi man chinh CarPlay
- (void)carplaySwitched:(UISwitch *)sw
{
    NSString *bid = objc_getAssociatedObject(sw, &kOMCABKey);
    if (sw.on) [_hidden removeObject:bid]; else [_hidden addObject:bid];
    OMCABStore(HS_KEY_HIDDEN_APPS, [[_hidden allObjects] sortedArrayUsingSelector:@selector(compare:)]);
    [_table reloadSections:[NSIndexSet indexSetWithIndex:OMCABOnCar] withRowAnimation:UITableViewRowAnimationNone];
    [self updatePreview];
}

- (void)tabPicked:(UISegmentedControl *)seg
{
    _tab = seg.selectedSegmentIndex;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self rebuildRows];
    [_list reloadData];
    [_list setContentOffset:CGPointZero animated:NO];
    [_table reloadSections:[NSIndexSet indexSetWithIndex:OMCABApps] withRowAnimation:UITableViewRowAnimationNone];   // footer theo tab
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
    NSMutableArray *items = [NSMutableArray arrayWithArray:_carplayApps];
    [items removeObjectsInArray:_hidden.allObjects];
    for (NSDictionary *a in _phoneApps) if ([_chosen containsObject:a[@"id"]] && ![items containsObject:a[@"id"]]) [items addObject:a[@"id"]];
    if (!items.count) items = [@[@"com.apple.Maps", @"com.apple.Music", @"com.apple.mobilephone", @"com.apple.MobileSMS", @"com.apple.podcasts"] mutableCopy];
    p.items = items;
    p.wallpaper = _wallpaper;
    p.video = _wallStyle == OMCHS_STYLE_VIDEO;
    p.size = [self num:HS_KEY_ICON_SIZE def:100]; p.blur = [self num:HS_KEY_BLUR def:0]; p.dim = [self num:HS_KEY_DIM def:25];
    p.cols = [self num:HS_KEY_COLS def:0]; p.rows = [self num:HS_KEY_ROWS def:0]; p.names = [OMCHSPref(HS_KEY_NAMES, @YES) boolValue];
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
        case OMCABWall: return [self wallName:_wallStyle];
    }
    return nil;
}

- (void)updateHeaders
{
    for (NSNumber *card in @[@(OMCABWall)]) {
        UITableViewCell *c = [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:card.integerValue]];
        c.detailTextLabel.text = [self summaryFor:card.integerValue];
    }
}

- (UITableViewCell *)headerCellFor:(NSInteger)card inTable:(UITableView *)tv
{
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"head"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"head"];
    OMCStyleCell(c);
    NSArray *info = @{@(OMCABWall): @[@"HOMESCREEN_WALLPAPER", @"photo.fill", @"#FF8A65"]}[@(card)];
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
    if (![self shows:s]) return 0;
    BOOL o = [self isOpen:s];
    switch (s) {
        case OMCABPreview: return 1;
        case OMCABOnCar: return 1;            // luoi icon
        case OMCABApps: return 3;             // tab, o tim, danh sach
        case OMCABGrid: return OMCABGridCount;
        case OMCABWall: return o ? 5 : 1;     // dau the, o hinh, Tu Anh, do mo, do toi
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    if (tv == _list || ![self shows:s]) return nil;
    switch (s) {
        case OMCABOnCar: return [self carplayGuessed] ? [NSString stringWithFormat:@"%@ %@", L(@"APPS_ON_CAR_FOOTER"), L(@"APPS_CARPLAY_GUESS_FOOTER")] : L(@"APPS_ON_CAR_FOOTER");
        case OMCABApps: return _tab == OMCABTabCarPlay ? L(@"APPS_CARPLAY_FOOTER")
                                                       : [NSString stringWithFormat:@"%@ %@", L(@"APPBRIDGE_APPS_FOOTER"), L(@"APPBRIDGE_APPS_OTHER_FOOTER")];
        case OMCABGrid: return L(@"HOMESCREEN_ICON_SIZE_FOOTER");
        case OMCABWall: return [self isOpen:s] ? L(@"APPS_WALL_FOOTER") : nil;
    }
    return nil;
}

// The cua trang kia: khong chua khoang dau / cuoi
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s
{
    if (tv == _list || ![self shows:s]) return nil;
    if (s == OMCABOnCar) return [NSString stringWithFormat:@"%@ · %lu", L(@"APPS_ON_CAR"), (unsigned long)[self onCarItems].count];
    if (s == OMCABApps) return L(@"APPS_ALL");
    if (s == OMCABGrid) return L(@"HOMESCREEN_GRID");
    return nil;
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { if (tv != _list) OMCStyleHeaderFooter(view, YES); }

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return tv != _list && ![self shows:s] ? CGFLOAT_MIN : UITableViewAutomaticDimension; }
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s { return tv != _list && ![self shows:s] ? CGFLOAT_MIN : UITableViewAutomaticDimension; }

- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { if (tv != _list) OMCStyleHeaderFooter(view, NO); }

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip
{
    if (tv == _list) return OMCAB_ROW_H;
    CGFloat w = tv.bounds.size.width - 40;
    if (ip.section == OMCABPreview) return floor((tv.bounds.size.width - 60) * 300.0 / 800.0) + 20;
    if (ip.section == OMCABOnCar) return [self gridIn:nil width:w];
    if (ip.section == OMCABApps && ip.row < 2) return 50;
    if (ip.section == OMCABApps && ip.row == 2) return [self listHeight];
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
    if (ip.row == 0 && ip.section == OMCABWall) return [self headerCellFor:ip.section inTable:tv];
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
        case OMCABOnCar: {
            UITableViewCell *c = [self cellWithId:@"oncar" inTable:tv];
            [self gridIn:[self boxInCell:c] width:w];
            return c;
        }
        case OMCABApps: {
            if (ip.row == 0) {   // tab App CarPlay / App OmniCar
                UITableViewCell *c = [self cellWithId:@"tabs" inTable:tv];
                UIView *box = [self boxInCell:c];
                UISegmentedControl *seg = (UISegmentedControl *)[box viewWithTag:3];
                if (!seg) {
                    seg = [[UISegmentedControl alloc] initWithItems:@[L(@"APPS_TAB_CARPLAY"), L(@"APPS_TAB_OMNICAR")]];
                    seg.tag = 3;
                    [seg addTarget:self action:@selector(tabPicked:) forControlEvents:UIControlEventValueChanged];
                    [box addSubview:seg];
                }
                seg.selectedSegmentIndex = _tab;
                seg.frame = CGRectMake(12, 9, w - 24, 32);
                return c;
            }
            if (ip.row == 1) {   // o tim
                UITableViewCell *c = [self cellWithId:@"tools" inTable:tv];
                UIView *box = [self boxInCell:c];
                UISearchBar *bar = (UISearchBar *)[box viewWithTag:2];
                if (!bar) {
                    bar = [UISearchBar new];
                    bar.tag = 2;
                    bar.searchBarStyle = UISearchBarStyleMinimal;
                    bar.placeholder = L(@"APPBRIDGE_APPS_SEARCH");
                    bar.delegate = self;
                    [box addSubview:bar];
                }
                bar.text = _query;
                bar.frame = CGRectMake(8, 3, w - 16, 44);
                return c;
            }
            UITableViewCell *c = [self cellWithId:@"list" inTable:tv];   // danh sach cuon rieng
            if (!_list) {
                _list = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
                _list.dataSource = self;
                _list.delegate = self;
                _list.backgroundColor = [UIColor clearColor];
                _list.rowHeight = OMCAB_ROW_H;
                _list.allowsSelection = NO;
                _list.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
            }
            if (_list.superview != c.contentView) { [_list removeFromSuperview]; [c.contentView addSubview:_list]; }
            _list.frame = CGRectMake(0, 0, w, [self listHeight]);
            return c;
        }
        case OMCABGrid: {   // so cot, so hang, co icon, ten app
            NSArray *info = @[@[@"HOMESCREEN_COLS", @"rectangle.split.3x1.fill", @"#5AB8FF"], @[@"HOMESCREEN_ROWS", @"rectangle.split.1x2.fill", @"#2BC79A"],
                              @[@"HOMESCREEN_ICON_SIZE", @"plus.magnifyingglass", @"#8B7CFF"], @[@"HOMESCREEN_NAMES", @"textformat", @"#FF7FA8"]][ip.row];
            UITableViewCell *c = [self cellWithId:[NSString stringWithFormat:@"grid%ld", (long)ip.row] inTable:tv];
            c.textLabel.text = L(info[0]);
            c.imageView.image = OMCIcon(info[1], OMCColorFromHex(info[2]));
            UIView *acc = nil;
            switch (ip.row) {
                case OMCABGridCols: acc = [self stepperFor:HS_KEY_COLS values:HS_COLS_VALUES]; break;
                case OMCABGridRows: acc = [self stepperFor:HS_KEY_ROWS values:HS_ROWS_VALUES]; break;
                case OMCABGridSize: acc = [self sliderFor:HS_KEY_ICON_SIZE min:60 max:130 def:100 unit:@"%"]; break;
                default: {
                    UISwitch *sw = [UISwitch new];
                    sw.onTintColor = OMCSwitchColor();
                    sw.on = [OMCHSPref(HS_KEY_NAMES, @YES) boolValue];
                    [sw addTarget:self action:@selector(namesSwitched:) forControlEvents:UIControlEventValueChanged];
                    acc = sw;
                }
            }
            [self setAccessory:acc onCell:c];
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
        [b setTitle:L(@"APPS_FROM_PHOTOS") forState:UIControlStateNormal];
        b.frame = CGRectMake(12, 4, w - 24, 42);
        return c;
    }
    BOOL blur = ip.row == 3;
    c.textLabel.text = L(blur ? @"HOMESCREEN_BLUR" : @"HOMESCREEN_DIM");
    c.imageView.image = OMCIcon(blur ? @"drop.fill" : @"moon.fill", OMCColorFromHex(blur ? @"#5AB8FF" : @"#4A4F80"));
    [self setAccessory:blur ? [self sliderFor:HS_KEY_BLUR min:0 max:30 def:0 unit:@""] : [self sliderFor:HS_KEY_DIM min:0 max:70 def:25 unit:@"%"] onCell:c];
    return c;
}

// Dong app iPhone: icon, ten (+ "He thong"), cong tac len xe
- (UITableViewCell *)appCellAt:(NSInteger)row
{
    UITableViewCell *c = [self cellWithId:@"app" inTable:_list];
    c.backgroundColor = [UIColor clearColor];
    if (!_rows.count) {
        c.textLabel.text = L(@"APPBRIDGE_APPS_NO_MATCH");
        c.textLabel.textColor = [UIColor secondaryLabelColor];
        return c;
    }
    NSDictionary *a = _rows[row];
    NSString *bid = a[@"id"];
    c.textLabel.text = a[@"name"];
    if ([a[@"carplay"] boolValue]) {   // app CarPlay: cong tac = hien icon tren man chinh CarPlay
        c.detailTextLabel.text = nil;
        c.imageView.image = [self iconFor:bid];
        if (HSIsLockedCarPlayApp(bid)) {   // CarPlay khong cho an (Dien thoai, Nhac, Ban do, Tin nhan...): khoa
            c.detailTextLabel.text = L(@"APPS_CARPLAY_LOCKED");
            c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            c.detailTextLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
            UIImageView *lock = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
            lock.tintColor = [UIColor tertiaryLabelColor];
            [self setAccessory:lock onCell:c];
            return c;
        }
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = OMCSwitchColor();
        sw.on = ![_hidden containsObject:bid];
        objc_setAssociatedObject(sw, &kOMCABKey, bid, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [sw addTarget:self action:@selector(carplaySwitched:) forControlEvents:UIControlEventValueChanged];
        [self setAccessory:sw onCell:c];
        return c;
    }
    c.detailTextLabel.text = [a[@"system"] boolValue] ? L(@"APPS_SYSTEM") : nil;
    c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    c.imageView.image = [self iconFor:bid];
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = OMCSwitchColor();
    sw.on = [_chosen containsObject:bid];
    objc_setAssociatedObject(sw, &kOMCABKey, bid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(appSwitched:) forControlEvents:UIControlEventValueChanged];
    [self setAccessory:sw onCell:c];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (tv == _list || ip.row != 0 || ip.section != OMCABWall) return;
    // dau the: mo / dong
    NSNumber *card = @(ip.section);
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

// O chon so cot / hang: "Tu dong" (0) hoac so, nut - / + di qua danh sach gia tri (HS_COLS_VALUES / HS_ROWS_VALUES)
- (UIView *)stepperFor:(NSString *)key values:(NSArray<NSNumber *> *)values
{
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 170, 32)];
    UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 64, 32)];
    v.textAlignment = NSTextAlignmentRight;
    v.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    v.textColor = [UIColor secondaryLabelColor];
    v.adjustsFontSizeToFitWidth = YES;
    UIStepper *st = [UIStepper new];
    st.frame = CGRectMake(170 - st.frame.size.width, (32 - st.frame.size.height) / 2, st.frame.size.width, st.frame.size.height);
    st.minimumValue = 0; st.maximumValue = values.count - 1; st.stepValue = 1;
    NSUInteger idx = [values indexOfObject:@([self num:key def:0])];
    st.value = idx == NSNotFound ? 0 : idx;
    objc_setAssociatedObject(st, &kOMCABKey, @[key, values, v], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [st addTarget:self action:@selector(stepped:) forControlEvents:UIControlEventValueChanged];
    [self showStep:st];
    [box addSubview:v];
    [box addSubview:st];
    return box;
}

- (void)showStep:(UIStepper *)st
{
    NSArray *info = objc_getAssociatedObject(st, &kOMCABKey);
    NSInteger n = [info[1][(NSUInteger)st.value] integerValue];
    ((UILabel *)info[2]).text = n ? [@(n) stringValue] : L(@"HOMESCREEN_AUTO");
}

- (void)stepped:(UIStepper *)st
{
    NSArray *info = objc_getAssociatedObject(st, &kOMCABKey);
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self showStep:st];
    OMCHSStore(info[0], info[1][(NSUInteger)st.value]);
    [self updatePreview];
}

- (void)namesSwitched:(UISwitch *)sw
{
    OMCHSStore(HS_KEY_NAMES, @(sw.on));
    [self updatePreview];
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
    OMCHSStore(info[0], @(lround(sl.value)));   // tha tay moi bao xe (khong xep lai icon tren xe moi buoc truot)
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

#pragma mark - Tren xe

// Luoi icon + ten cua app dang hien tren xe; app iPhone (OmniCar dua len) co dau iPhone o goc. v = nil: chi tinh chieu cao
- (CGFloat)gridIn:(UIView *)v width:(CGFloat)w
{
    NSArray<NSArray *> *items = [self onCarItems];
    CGFloat pad = 12, gap = 10;
    NSInteger cols = MAX(1, (NSInteger)floor((w - pad * 2) / 68)), n = MAX(1, (NSInteger)items.count), rows = (n + cols - 1) / cols;
    CGFloat cellW = (w - pad * 2) / cols, h = pad * 2 + rows * OMCAB_GRID_ROW + (rows - 1) * gap;
    if (!v) return h;
    for (UIView *old in [v.subviews copy]) [old removeFromSuperview];
    if (!items.count) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(pad, pad, w - pad * 2, OMCAB_GRID_ROW)];
        l.text = L(@"APPBRIDGE_APPS_NONE");
        l.textColor = [UIColor secondaryLabelColor];
        l.textAlignment = NSTextAlignmentCenter;
        [v addSubview:l];
        return h;
    }
    for (NSUInteger i = 0; i < items.count; i++) {
        NSString *bid = items[i][0];
        CGFloat x = pad + (i % cols) * cellW, y = pad + (i / cols) * (OMCAB_GRID_ROW + gap);
        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(x + (cellW - OMCAB_GRID_ICON) / 2, y, OMCAB_GRID_ICON, OMCAB_GRID_ICON)];
        icon.image = OMCHSIcon(bid, OMCAB_GRID_ICON);
        [v addSubview:icon];
        if ([items[i][1] boolValue]) {   // dau iPhone: app OmniCar dua len
            UIImage *glyph = [UIImage systemImageNamed:@"iphone" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightBold]];
            UIImageView *badge = [[UIImageView alloc] initWithImage:glyph];
            badge.frame = CGRectMake(CGRectGetMaxX(icon.frame) - 13, CGRectGetMinY(icon.frame) - 5, 18, 18);
            badge.contentMode = UIViewContentModeCenter;
            badge.tintColor = [UIColor whiteColor];
            badge.backgroundColor = OMCAccentColor();
            badge.layer.cornerRadius = 9;
            badge.layer.borderWidth = 1.5;
            badge.layer.borderColor = [UIColor secondarySystemGroupedBackgroundColor].CGColor;
            [v addSubview:badge];
        }
        UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(x + 2, y + OMCAB_GRID_ICON + 4, cellW - 4, 14)];
        name.text = OMCHSName(bid);
        name.font = [UIFont systemFontOfSize:10.5];
        name.textColor = [UIColor secondaryLabelColor];
        name.textAlignment = NSTextAlignmentCenter;
        [v addSubview:name];
    }
    return h;
}

#pragma mark - Hinh nen

- (CGFloat)layoutTilesIn:(UIView *)v width:(CGFloat)w
{
    NSMutableArray *styles = [NSMutableArray array];
    for (NSInteger i = 0; i <= OMCHS_PRESETS; i++) [styles addObject:@(i)];
    if (_photo) [styles addObject:@(OMCHS_STYLE_PHOTO)];
    if (_videoThumb) [styles addObject:@(OMCHS_STYLE_VIDEO)];
    NSInteger n = styles.count, cols = 4, selected = _wallStyle;
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
            [b setTitle:L(@"HOMESCREEN_WALLPAPER_DEFAULT") forState:UIControlStateNormal];
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

- (void)tileTapped:(UIButton *)b
{
    [self useStyle:b.tag];
}

// Chon hinh nen. 0 = hinh nen CarPlay; 1..7 ghi JPEG; 8 = video
- (void)useStyle:(NSInteger)style
{
    if (style == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:HS_WALLPAPER_PATH error:nil];
        _wallpaper = nil; _wallStyle = 0;
        OMCHSStore(HS_KEY_WALLPAPER_STYLE, @0); OMCHSStore(HS_KEY_WALLPAPER, @NO);
    } else {
        UIImage *img = style == OMCHS_STYLE_VIDEO ? _videoThumb : style == OMCHS_STYLE_PHOTO ? _photo : OMCHSPresetImage(style, CGSizeMake(1920, 720), 1);
        if (!img) return;
        if (style != OMCHS_STYLE_VIDEO && ![self writeJPEG:img to:HS_WALLPAPER_PATH]) return;
        _wallpaper = img; _wallStyle = style;
        OMCHSStore(HS_KEY_WALLPAPER_STYLE, @(style)); OMCHSStore(HS_KEY_WALLPAPER, @YES);
    }
    [self reloadCard:OMCABWall];
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

// "Man chinh CarPlay": cung trang, chi xem truoc + luoi icon + hinh nen
@interface OMCHomeScreenController : OMCAppBridgeAppsController
@end

@implementation OMCHomeScreenController
- (BOOL)layoutPage { return YES; }
@end
