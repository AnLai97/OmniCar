#import "SCPCarSplit.h"
#import "SCPPrefs.h"
#import "SCPAppIcons.h"
#import <notify.h>

// =====================================================================
//  SCPCarSplit - split CarPlay "that": moi ngan la scene CarPlay cua app (giao dien CarPlay/template),
//  chay trong process CarPlay (DashBoard.framework, iOS 16.5).
//
//  Luong mo 1 app vao ngan:
//    1. Ghi nho bundle -> ngan (pending), gui [DBDashboard handleEvent:[DBEvent eventWithType:4 context:launchInfo]]
//       = dung duong DashBoard mo app khi cham icon.
//    2. DashBoard tao DBApplicationSceneViewController (app template: proxy qua CarPlayTemplateUIHost),
//       foreground scene. Kich thuoc scene lay tu -[DBDashboard sceneFrameForAppInfo:proxyAppInfo:]
//       -> hook tra ve kich thuoc ngan.
//    3. DashBoard goi -[DBDashboardRootViewController presentBaseViewController:...] -> hook dua VC vao ngan.
//  Scene cua ngan duoc giu foreground: hook chan backgroundScene/deactivateScene cho VC dang nam trong ngan.
// =====================================================================

// Kieu HyperOS: cac o cach nhau 1 khe den mong, giua khe la tay nam vien thuoc trang (keo = doi ti le,
// cham 2 lan = doi cho, keo sat mep = dong app bi ep). Dau moi o co thanh "•••": cham -> thanh nut,
// keo tha len o khac -> doi cho.
#define SCPC_GAP          1.0     // vach mong giua 2 o nhu cua so Windows (vung cham rong SCPC_DIVIDER_HIT, cham tron de keo)
#define SCPC_INSET        0.0     // o sat dock va mep man nhu app toan man -> khong phi cho
#define SCPC_RADIUS       6.0     // bo goc nhe o goc giap o khac; goc ngay cham tron (1 lon + 2) de vuong cho cham tron ngoi sat
#define SCPC_BTN          34.0    // nut trong thanh vien thuoc
#define SCPC_PILL         42.0    // be day thanh vien thuoc
#define SCPC_HANDLE_W     34.0    // thanh "•••" o dau moi o
#define SCPC_HANDLE_H     12.0
#define SCPC_HANDLE_Y     6.0     // khoang tu mep tren o toi thanh "•••"
#define SCPC_KNOB_DOT     14.0    // tay nam tron giua vach (va o giao 2 vach khi 1 lon + 2); cham vao phong to SCPC_KNOB_GROW de keo
#define SCPC_KNOB_GROW    1.6
#define SCPC_DIVIDER_HIT  26.0
#define SCPC_DISMISS      0.12    // keo vach cho 1 o con duoi ti le nay -> dong o do (HyperOS: keo sat mep)
#define SCPC_MIN_FRAC     0.2     // o nho nhat sau khi tha tay
#define SCPC_PENDING_TTL  12.0    // giay: qua thoi gian ma DashBoard chua trinh bay app thi bo pending
#define SCPC_HOME_SETTLE  0.5     // giay: cho DashBoard ve Home truoc khi mo app vao ngan
#define SCPC_LAUNCH_GAP   1.2     // giay: khoang cach toi thieu giua 2 lan mo app
#define SCPC_MAX_PANES    3       // bo cuc toi da 3 o
// Bo cuc: 2 = 2 o, 3 = 3 o deu theo 1 chieu, 13 = 1 o lon + 2 o nho xep chong (o lon ben trai / tren)
#define SCPC_LAYOUT_MAIN_STACK 13
#define SCPC_LAYOUT_MAIN_RIGHT 31   // 2 + 1 lon: ban lat cua 13, o lon ben phai (man doc: o lon duoi)
#define SCPC_FLOAT_SLOT        9    // so o gia cua cua so noi (pending / openApp / closeSlot)
#define SCPC_BG_TOAST_TAG      0x5C9B   // thong bao "dang chay nen" (chi 1 cai mot luc)
typedef NS_ENUM(NSInteger, SCPCLayoutKind) { SCPCLayoutColumns = 0, SCPCLayoutMainStack = 1, SCPCLayoutMainRight = 2 };

static BOOL SCPCIsStackLayout(int layoutID) { return layoutID == SCPC_LAYOUT_MAIN_STACK || layoutID == SCPC_LAYOUT_MAIN_RIGHT; }
static int SCPCPanesForLayout(int layoutID)
{
    if (SCPCIsStackLayout(layoutID)) return 3;
    // Bo cuc la (vd 70 / 30 da bo, con trong Gan day / Yeu thich cu): coi nhu 2 o
    return (layoutID >= 2 && layoutID <= SCPC_MAX_PANES) ? layoutID : 2;
}
static NSInteger SCPCKindForLayout(int layoutID)
{
    if (layoutID == SCPC_LAYOUT_MAIN_STACK) return SCPCLayoutMainStack;
    if (layoutID == SCPC_LAYOUT_MAIN_RIGHT) return SCPCLayoutMainRight;
    return SCPCLayoutColumns;
}

// Lat goc bo: man ngang doi trai <-> phai, man doc doi tren <-> duoi
static CACornerMask SCPCMirrorMask(CACornerMask m, BOOL vertical)
{
    CACornerMask a = vertical ? kCALayerMinXMinYCorner : kCALayerMinXMinYCorner, b = vertical ? kCALayerMinXMaxYCorner : kCALayerMaxXMinYCorner;
    CACornerMask c = vertical ? kCALayerMaxXMinYCorner : kCALayerMinXMaxYCorner, d = vertical ? kCALayerMaxXMaxYCorner : kCALayerMaxXMaxYCorner;
    CACornerMask r = 0;
    if (m & a) r |= b;
    if (m & b) r |= a;
    if (m & c) r |= d;
    if (m & d) r |= c;
    return r;
}

@interface UIImage (SCPCarPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(double)scale;
@end

NSString *SCPRealBundleForInfos(id info, id proxyInfo)
{
    NSString *a = info ? objcInvoke(info, @"bundleIdentifier") : nil;
    NSString *b = proxyInfo ? objcInvoke(proxyInfo, @"bundleIdentifier") : nil;
    if (a.length && ![a isEqualToString:SCP_TEMPLATE_HOST]) return a;
    if (b.length && ![b isEqualToString:SCP_TEMPLATE_HOST]) return b;
    return a ?: b;
}

// Moi tac vu hen gio / chay sau cua tweak deu qua day: loi (vd chi so o sai vi o vua bi dong) chi ghi log,
// khong lam sap CarPlay. delay <= 0 = chay o vong lap ke tiep.
static void SCPCAfter(double delay, dispatch_block_t block)
{
    dispatch_block_t safe = ^{
        @try { block(); }
        @catch (NSException *e) { SCPLog("CarSplit: LOI trong tac vu chay sau: %@\n%@", e, e.callStackSymbols); }
    };
    if (delay <= 0) dispatch_async(dispatch_get_main_queue(), safe);
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), safe);
}

// Chu tren man xe: tieng Viet / tieng Anh theo Cai dat > OmniCar > ngon ngu
static NSString *SCPCT(NSString *vi, NSString *en) { return OMCTr(vi, en); }   // ngon ngu khac: Car.strings

// Bao SpringBoard (OMC_DARWIN_CAR_BUSY): dang chia man / bang bo cuc dang mo -> lop phu tren man xe (bong bong
// toc do) tam an de khong de len cho dang cham. Chi gui khi trang thai doi.
static void SCPCPublishBusy(BOOL busy)
{
    static int token = 0, last = -1;
    if (!token) notify_register_check(OMC_DARWIN_CAR_BUSY, &token);
    if (last == (int)busy) return;
    last = busy;
    notify_set_state(token, busy ? 1 : 0);
    notify_post(OMC_DARWIN_CAR_BUSY);
    SCPLog("CarSplit: man xe %@", busy ? @"ban (an lop phu)" : @"ranh");
}

static id SCPCDashboard(void)
{
    UIApplication *app = [UIApplication sharedApplication];
    if (![app respondsToSelector:NSSelectorFromString(@"_currentDashboard")]) return nil;
    return objcInvoke(app, @"_currentDashboard");
}

static UIViewController *SCPCRootVC(void)
{
    id d = SCPCDashboard();
    return d ? objcInvoke(d, @"rootViewController") : nil;
}

static id SCPCLibrary(void)
{
    UIApplication *app = [UIApplication sharedApplication];
    if (![app respondsToSelector:NSSelectorFromString(@"sharedApplicationLibrary")]) return nil;
    return objcInvoke(app, @"sharedApplicationLibrary");
}

static id SCPCAppInfo(NSString *bid)
{
    id lib = SCPCLibrary();
    return (lib && bid) ? objcInvoke_1(lib, @"applicationInfoForBundleIdentifier:", bid) : nil;
}

static BOOL SCPCBool(id obj, NSString *sel)
{
    return obj && [obj respondsToSelector:NSSelectorFromString(sel)] && objcInvokeT(obj, sel, BOOL);
}

// App co giao dien CarPlay (DashBoard hien duoc) va khong phai app he thong cua chinh CarPlay
static BOOL SCPCInfoIsCarPlayApp(id info)
{
    if (!info) return NO;
    NSString *bid = objcInvoke(info, @"bundleIdentifier");
    if (!bid.length || [bid isEqualToString:SCP_TEMPLATE_HOST] || [bid isEqualToString:@"com.apple.CarPlayApp"]
        || [bid isEqualToString:@"com.apple.CarPlaySettings"]
        || [bid isEqualToString:@"com.apple.InCallService"]) return NO;   // man goi dien: DashBoard khong tao scene VC -> khong vao ngan duoc
    if (SCPIsInjectedPhoneApp(bid)) return NO;   // declaration gia do SCPAppIcons gan: app iPhone, di qua App Bridge
    if (![info respondsToSelector:NSSelectorFromString(@"carPlayDeclaration")]) return NO;
    if (!objcInvoke(info, @"carPlayDeclaration")) return NO;
    if (SCPCBool(info, @"isHidden") || SCPCBool(info, @"presentsFullScreen")) return NO;
    return YES;
}

static void SCPCSendEvent(unsigned long long type, id context)
{
    id d = SCPCDashboard();
    if (!d) return;
    id ev = objcInvoke_2(OMCCarClass("DBEvent"), @"eventWithType:context:", type, context);
    if (ev) objcCall_1(d, @"handleEvent:", ev);
}

static id SCPCTry(id obj, NSString *sel)
{
    if (!obj || ![obj respondsToSelector:NSSelectorFromString(sel)]) return nil;
    @try { return objcInvoke(obj, sel); } @catch (NSException *e) { return nil; }
}

static NSString *SCPCIconBundle(id icon)
{
    for (NSString *k in @[@"applicationBundleID", @"leafIdentifier"]) {
        id v = SCPCTry(icon, k);
        if ([v isKindOfClass:[NSString class]] && [v length]) return v;
    }
    return nil;
}

static void SCPCAddIcons(NSArray *icons, NSMutableOrderedSet *out)
{
    if (![icons isKindOfClass:[NSArray class]]) return;
    for (id icon in icons) { NSString *b = SCPCIconBundle(icon); if (b) [out addObject:b]; }
}

// Tim cac SBIconListView (man chinh, co the ca dock) -> moi cai lay icon cua ca thu muc chua no (moi trang).
// Giu bo lon nhat = man chinh.
static void SCPCCollectHomeIcons(UIView *v, NSMutableOrderedSet *__strong *best, int depth)
{
    if (!v || depth > 14) return;
    if ([NSStringFromClass([v class]) hasSuffix:@"IconListView"]) {
        NSMutableOrderedSet *got = [NSMutableOrderedSet orderedSet];
        id model = SCPCTry(v, @"model");
        NSArray *lists = SCPCTry(SCPCTry(model, @"folder"), @"lists");
        if ([lists isKindOfClass:[NSArray class]] && lists.count) for (id l in lists) SCPCAddIcons(SCPCTry(l, @"icons"), got);
        else SCPCAddIcons(SCPCTry(model, @"icons"), got);   // khong lay duoc thu muc: it nhat trang nay
        if (got.count > (*best).count) *best = got;
    }
    for (UIView *c in v.subviews) SCPCCollectHomeIcons(c, best, depth + 1);
}

// Bundle cua cac app dang hien tren man chinh CarPlay (theo thu tu), nho lai lan doc duoc gan nhat
// (man chinh co the khong nam trong cay view khi app dang mo). nil = chua doc duoc lan nao.
static NSArray<NSString *> *SCPCHomeScreenBundles(void)
{
    static NSArray<NSString *> *cached;
    NSMutableOrderedSet *found = [NSMutableOrderedSet orderedSet];
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) SCPCCollectHomeIcons(w, &found, 0);
    }
    if (found.count >= 2 && ![found.array isEqualToArray:cached]) {
        cached = found.array;
        SCPLog("CarSplit: man chinh CarPlay co %lu app: %@", (unsigned long)cached.count, [cached componentsJoinedByString:@", "]);
    }
    return cached;
}

// Danh sach app CarPlay: @{ id, name } - chi app dang hien tren man chinh CarPlay (bo app da an trong
// Cai dat > CarPlay > Tuy chinh), cung thu tu nhu man chinh
static NSArray<NSDictionary *> *SCPCCarPlayApps(void)
{
    NSMutableArray *out = [NSMutableArray array];
    id lib = SCPCLibrary();
    NSArray *all = lib ? objcInvoke(lib, @"allInstalledApplications") : nil;
    NSArray<NSString *> *home = SCPCHomeScreenBundles();
    for (id info in all) {
        if (!SCPCInfoIsCarPlayApp(info)) continue;
        NSString *name = objcInvoke(info, @"displayName");
        NSString *bid = objcInvoke(info, @"bundleIdentifier");
        if (home && ![home containsObject:bid]) continue;
        [out addObject:@{@"id": bid, @"name": name.length ? name : bid}];
    }
    if (home) {
        [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSUInteger ia = [home indexOfObject:a[@"id"]], ib = [home indexOfObject:b[@"id"]];
            return ia < ib ? NSOrderedAscending : (ia > ib ? NSOrderedDescending : NSOrderedSame);
        }];
    } else {
        [out sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
    }
    return out;
}

static UIImage *SCPCAppIcon(NSString *bid)
{
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        UIImage *img = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:2.0];
        // Chan doan icon khac kieu giua app (icon YouTube trong bang bo cuc): log 1 lan moi app kich thuoc tra ve
        static NSMutableSet *seen;
        if (!seen) seen = [NSMutableSet set];
        if (bid && ![seen containsObject:bid]) {
            [seen addObject:bid];
            SCPLog("DIAG icon %@: %@ scale %.0f (%.0fx%.0f px)", bid, img ? NSStringFromCGSize(img.size) : @"nil", img.scale,
                   img.size.width * img.scale, img.size.height * img.scale);
        }
        return img;
    }
    return nil;
}

// Cho man chinh CarPlay cua OmniCar (SCPHomeScreen.mm)
NSArray<NSString *> *SCPCarHomeBundles(void) { return SCPCHomeScreenBundles(); }
UIImage *SCPCarAppIcon(NSString *bundleID) { return SCPCAppIcon(bundleID); }
NSString *SCPCarAppName(NSString *bundleID)
{
    id info = SCPCAppInfo(bundleID);
    NSString *n = info ? objcInvoke(info, @"displayName") : nil;
    if (!n.length && bundleID.length) {   // app iPhone (khong co trong thu vien CarPlay)
        Class lp = objc_getClass("LSApplicationProxy");
        id proxy = lp ? objcInvoke_1(lp, @"applicationProxyForIdentifier:", bundleID) : nil;
        n = proxy ? objcInvoke(proxy, @"localizedName") : nil;
    }
    return n.length ? n : bundleID;
}
void SCPCarLaunchApp(NSString *bundleID)
{
    if (!bundleID.length) return;
    if ([[SCPCarSplit shared] launchPhoneAppIfNeeded:bundleID]) return;   // app iPhone: App Bridge
    id info = SCPCAppInfo(bundleID), d = SCPCDashboard();
    if (info && d) objcCall_2(d, @"_launchAppWithInfo:forURL:", info, (id)nil);
    else SCPLog("HomeScreen: khong mo duoc %@ (info %@, dashboard %@)", bundleID, info, d);
}

// ---------------------------------------------------------------------
//  Kieu HyperOS: icon net tron deu tu ve (khong can asset), nen "kinh toi" bo goc lien tuc,
//  nut gom trong thanh vien thuoc, cham thi nut lun nhe.
// ---------------------------------------------------------------------
// Giao dien moi (DESIGN.md, tools/preview/theme.html): cac bang tren man xe nen phoi 4 mau nhu nen logo
// (OMCLogoMeshImage), o kinh trang vien trang nhu dia trong logo, icon / chu mau cham diu, khong vien den;
// dang chon = vien cau vong 4 mau logo (nen van trong), nut chinh = gradient tim -> xanh troi, dau X do.
static UIColor *SCPCInk(void) { return [UIColor colorWithRed:0x4A / 255.0 green:0x4F / 255.0 blue:0x80 / 255.0 alpha:1]; }
static UIColor *SCPCInk2(void) { return [SCPCInk() colorWithAlphaComponent:0.55]; }   // chu / icon phu
static UIColor *SCPCDanger(void) { return [UIColor colorWithRed:1.0 green:0x5A / 255.0 blue:0x5F / 255.0 alpha:1]; }  // nut dong
static UIColor *SCPCAccent(void) { return [UIColor colorWithRed:0x9B / 255.0 green:0x87 / 255.0 blue:0xF8 / 255.0 alpha:1]; }   // tim (dau gradient)
static UIColor *SCPCAccent2(void) { return [UIColor colorWithRed:0x5D / 255.0 green:0xB4 / 255.0 blue:0xF6 / 255.0 alpha:1]; }  // xanh troi (cuoi gradient)
static UIColor *SCPCShadow(void) { return [UIColor colorWithRed:110 / 255.0 green:100 / 255.0 blue:200 / 255.0 alpha:1]; }  // bong tim nhat
static UIColor *SCPCPastel(void) { return [UIColor colorWithRed:0xEE / 255.0 green:0xF0 / 255.0 blue:0xFB / 255.0 alpha:1]; } // nen o cho

// O lua chon trong cac bang (bo cuc trong khay): nen trong suot cung mau bang, chi khung trang manh tach tung o, bo 14.
static void SCPCOptionTile(UIView *v)
{
    v.layer.cornerRadius = 14;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.backgroundColor = [UIColor clearColor];
    v.layer.borderWidth = 1;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.75].CGColor;
}

// O kinh trang nho (nut X, nut cua thanh •••): trang trong + vien trang 1pt nhu dia trong logo, bong tim rat nhat
static void SCPCTile(UIView *v, CGFloat radius)
{
    v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.5];
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.borderWidth = 1;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    v.layer.shadowColor = SCPCShadow().CGColor;
    v.layer.shadowOpacity = 0.12; v.layer.shadowRadius = 3; v.layer.shadowOffset = CGSizeMake(0, 2);
}

// Dang chon (bo cuc dang dung, ti le dang dung): nen giu trong, chi vien cau vong 2pt 4 mau logo (tim, xanh troi,
// bac ha, hong) + quang tim nhat. Goi lai sau khi doi kich thuoc view.
static void SCPCSelectRing(UIView *v, BOOL on)
{
    CAGradientLayer *g = nil;
    for (CALayer *l in v.layer.sublayers) if ([l.name isEqualToString:@"omcRing"]) g = (CAGradientLayer *)l;
    if (!on) { [g removeFromSuperlayer]; v.layer.shadowOpacity = 0; return; }
    if (!g) {
        g = [CAGradientLayer layer];
        g.name = @"omcRing";
        g.type = kCAGradientLayerConic;
        g.startPoint = CGPointMake(0.5, 0.5); g.endPoint = CGPointMake(0, 1);
        UIColor *(^hex)(uint32_t) = ^(uint32_t x) { return [UIColor colorWithRed:((x >> 16) & 0xFF) / 255.0 green:((x >> 8) & 0xFF) / 255.0 blue:(x & 0xFF) / 255.0 alpha:1]; };
        g.colors = @[(id)hex(0xA78BFA).CGColor, (id)hex(0x60C5FA).CGColor, (id)hex(0x5EDDB6).CGColor, (id)hex(0xF59AC0).CGColor, (id)hex(0xA78BFA).CGColor];
        CAShapeLayer *m = [CAShapeLayer layer];
        m.fillColor = nil; m.strokeColor = [UIColor blackColor].CGColor; m.lineWidth = 2;
        g.mask = m;
        [v.layer insertSublayer:g atIndex:0];
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    g.frame = v.bounds;
    ((CAShapeLayer *)g.mask).path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(v.bounds, 1, 1) cornerRadius:MAX(0, v.layer.cornerRadius - 1)].CGPath;
    [CATransaction commit];
    v.layer.borderWidth = 0;
    v.layer.shadowColor = SCPCAccent().CGColor;
    v.layer.shadowOpacity = 0.3; v.layer.shadowRadius = 8; v.layer.shadowOffset = CGSizeMake(0, 4);
}

// Nen bang tren man xe = nen logo 4 mau trai len lop kinh mo (thay lop trang mo cu), vien trang 1pt
static void SCPCMesh(UIVisualEffectView *glass)
{
    glass.contentView.backgroundColor = [UIColor clearColor];
    UIImageView *mesh = [[UIImageView alloc] initWithImage:OMCLogoMeshImage(NO)];
    mesh.frame = glass.contentView.bounds;
    mesh.contentMode = UIViewContentModeScaleToFill;
    mesh.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    mesh.userInteractionEnabled = NO;
    [glass.contentView insertSubview:mesh atIndex:0];
    glass.layer.borderWidth = 1;
    glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
}

// Dang chon / nut chinh: lop gradient tim -> xanh troi (bo goc theo view) + quang mau tim; on = NO go ra.
// Goi lai sau khi doi kich thuoc view de lop gradient theo kip.
static void SCPCAccentFill(UIView *v, BOOL on)
{
    CAGradientLayer *g = nil;
    for (CALayer *l in v.layer.sublayers) if ([l.name isEqualToString:@"omcAccent"]) g = (CAGradientLayer *)l;
    if (!on) { [g removeFromSuperlayer]; v.layer.shadowColor = SCPCShadow().CGColor; v.layer.shadowOpacity = 0; return; }
    if (!g) {
        g = [CAGradientLayer layer];
        g.name = @"omcAccent";
        g.colors = @[(id)SCPCAccent().CGColor, (id)SCPCAccent2().CGColor];
        g.startPoint = CGPointZero; g.endPoint = CGPointMake(1, 1);
        [v.layer insertSublayer:g atIndex:0];
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    g.frame = v.bounds;
    g.cornerRadius = v.layer.cornerRadius;
    g.cornerCurve = kCACornerCurveContinuous;
    [CATransaction commit];
    v.layer.shadowColor = [UIColor colorWithRed:110 / 255.0 green:120 / 255.0 blue:1.0 alpha:1].CGColor;
    v.layer.shadowOpacity = 0.45; v.layer.shadowRadius = 9; v.layer.shadowOffset = CGSizeMake(0, 4);
}

// Icon kieu HyperOS: luoi 24x24, net 1.8 deu, dau net va goc bo tron; phan to dac (fill) ve rieng.
// rot: xoay 90 do (trai -> tren) cho kieu chia tren/duoi
static UIImage *SCPCDraw(CGFloat pt, BOOL rot, void (^draw)(UIBezierPath *p, UIBezierPath *fill))
{
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(pt, pt)];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef c = rc.CGContext;
        CGContextScaleCTM(c, pt / 24.0, pt / 24.0);
        if (rot) { CGContextTranslateCTM(c, 24, 0); CGContextRotateCTM(c, M_PI_2); }
        [[UIColor blackColor] set];
        UIBezierPath *p = [UIBezierPath bezierPath], *f = [UIBezierPath bezierPath];
        p.lineWidth = 1.8; p.lineCapStyle = kCGLineCapRound; p.lineJoinStyle = kCGLineJoinRound;
        draw(p, f);
        [p stroke];
        [f fill];
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#define SCPC_M(x, y) [p moveToPoint:CGPointMake(x, y)]
#define SCPC_L(x, y) [p addLineToPoint:CGPointMake(x, y)]
#define SCPC_RR(x, y, w, h, r) [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, w, h) cornerRadius:r]]

// fullscreen (thoat chia, app nay toan man) / replace (doi app trong o) / close / swap
static UIImage *SCPCGlyph(NSString *name, CGFloat pt, BOOL rot)
{
    // relayout dat lai icon -> cache, khong ve lai moi lan
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@/%.0f/%d", name, pt, rot];
    UIImage *hit = cache[key];
    if (hit) return hit;
    UIImage *img = SCPCDraw(pt, rot, ^(UIBezierPath *p, UIBezierPath *f) {
        if ([name isEqualToString:@"fullscreen"]) {      // 2 mui ten cheo ra 2 goc
            SCPC_M(13.5, 4); SCPC_L(20, 4); SCPC_L(20, 10.5);
            SCPC_M(20, 4); SCPC_L(14, 10);
            SCPC_M(10.5, 20); SCPC_L(4, 20); SCPC_L(4, 13.5);
            SCPC_M(4, 20); SCPC_L(10, 14);
        } else if ([name isEqualToString:@"replace"]) {  // 3 o app + dau cong o goc (chon app khac cho o)
            SCPC_RR(3.5, 3.5, 7.5, 7.5, 2.4); SCPC_RR(13, 3.5, 7.5, 7.5, 2.4);
            SCPC_RR(3.5, 13, 7.5, 7.5, 2.4);
            SCPC_M(16.75, 13.5); SCPC_L(16.75, 20); SCPC_M(13.5, 16.75); SCPC_L(20, 16.75);
        } else if ([name isEqualToString:@"close"]) {
            SCPC_M(7, 7); SCPC_L(17, 17); SCPC_M(17, 7); SCPC_L(7, 17);
        } else if ([name isEqualToString:@"layouts"]) {  // muc bo cuc: 2 o canh nhau
            SCPC_RR(3.5, 5, 9, 14, 2.6); SCPC_RR(14, 5, 6.5, 14, 2.6);
        } else if ([name isEqualToString:@"recent"]) {   // muc gan day: dong ho
            [p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(3.75, 3.75, 16.5, 16.5)]];
            SCPC_M(12, 7.5); SCPC_L(12, 12); SCPC_L(15, 14);
        } else if ([name isEqualToString:@"favorite"]) { // muc yeu thich: ngoi sao
            for (int k = 0; k < 10; k++) {
                CGFloat r = (k % 2) ? 3.9 : 8.6, a = -M_PI_2 + k * M_PI / 5;
                CGPoint q = CGPointMake(12 + r * cos(a), 12.6 + r * sin(a));
                if (k == 0) [p moveToPoint:q]; else [p addLineToPoint:q];
            }
            [p closePath];
        } else if ([name isEqualToString:@"exit"]) {     // thoat chia man: khung cua + mui ten ra ngoai
            SCPC_M(10, 4); SCPC_L(6.5, 4); [p addArcWithCenter:CGPointMake(6.5, 6.5) radius:2.5 startAngle:-M_PI_2 endAngle:-M_PI clockwise:NO];
            SCPC_L(4, 17.5); [p addArcWithCenter:CGPointMake(6.5, 17.5) radius:2.5 startAngle:M_PI endAngle:M_PI_2 clockwise:NO];
            SCPC_L(10, 20);
            SCPC_M(10, 12); SCPC_L(20, 12); SCPC_M(16.5, 8.5); SCPC_L(20, 12); SCPC_L(16.5, 15.5);
        } else if ([name isEqualToString:@"float"]) {    // cua so noi: khung + o nho to dac goc duoi phai
            SCPC_RR(3.5, 4.5, 17, 15, 3);
            [f appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(11.5, 11, 6.5, 6) cornerRadius:1.6]];
        } else if ([name isEqualToString:@"dock"]) {     // dua ve o (HyperOS "chia man hinh"): khung chia doi, nua trai to dac
            SCPC_RR(3.5, 4.5, 17, 15, 3);
            SCPC_M(12, 4.5); SCPC_L(12, 19.5);
            [f appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(5.6, 6.6, 4.6, 10.8) cornerRadius:1.4]];
        } else if ([name isEqualToString:@"check"]) {    // dau tich (app dang mo o o khac)
            SCPC_M(6, 12.5); SCPC_L(10, 16.5); SCPC_L(18, 8);
        } else if ([name isEqualToString:@"swap"]) {     // 2 mui ten nguoc chieu
            SCPC_M(4.5, 8.5); SCPC_L(19, 8.5); SCPC_M(15.5, 5); SCPC_L(19, 8.5); SCPC_L(15.5, 12);
            SCPC_M(19.5, 15.5); SCPC_L(5, 15.5); SCPC_M(8.5, 12); SCPC_L(5, 15.5); SCPC_L(8.5, 19);
        } else if ([name hasPrefix:@"hm_"]) {             // thanh ••• kieu HarmonyOS Symbol: net 1.5 (tools/preview/theme.html)
            p.lineWidth = 1.5;
            if ([name isEqualToString:@"hm_apps"]) {          // chon app moi: 4 o vuong bo tron
                SCPC_RR(4, 4, 7, 7, 2.2); SCPC_RR(13, 4, 7, 7, 2.2); SCPC_RR(4, 13, 7, 7, 2.2); SCPC_RR(13, 13, 7, 7, 2.2);
            } else if ([name isEqualToString:@"hm_full"]) {   // chay 1 man hinh: 4 goc khung bo tron
                SCPC_M(4, 9.5); SCPC_L(4, 7.5); [p addArcWithCenter:CGPointMake(7.5, 7.5) radius:3.5 startAngle:M_PI endAngle:-M_PI_2 clockwise:YES]; SCPC_L(9.5, 4);
                SCPC_M(14.5, 4); SCPC_L(16.5, 4); [p addArcWithCenter:CGPointMake(16.5, 7.5) radius:3.5 startAngle:-M_PI_2 endAngle:0 clockwise:YES]; SCPC_L(20, 9.5);
                SCPC_M(20, 14.5); SCPC_L(20, 16.5); [p addArcWithCenter:CGPointMake(16.5, 16.5) radius:3.5 startAngle:0 endAngle:M_PI_2 clockwise:YES]; SCPC_L(14.5, 20);
                SCPC_M(9.5, 20); SCPC_L(7.5, 20); [p addArcWithCenter:CGPointMake(7.5, 16.5) radius:3.5 startAngle:M_PI_2 endAngle:M_PI clockwise:YES]; SCPC_L(4, 14.5);
            } else if ([name isEqualToString:@"hm_split"]) {  // chia man hinh: 2 khung dung canh nhau
                SCPC_RR(3.5, 4.5, 7.5, 15, 2.5); SCPC_RR(13, 4.5, 7.5, 15, 2.5);
            } else if ([name isEqualToString:@"hm_float"]) {  // anh trong anh: khung + o nho to dac goc duoi phai
                SCPC_RR(3.5, 4.5, 17, 15, 3);
                [f appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(11.5, 11.5, 6.5, 5.5) cornerRadius:1.6]];
            } else if ([name isEqualToString:@"hm_min"]) {    // chay nen: gach ngang (thu nho cua so)
                SCPC_M(5.5, 12); SCPC_L(18.5, 12);
            } else if ([name isEqualToString:@"hm_close"]) {  // tat han app
                SCPC_M(6.5, 6.5); SCPC_L(17.5, 17.5); SCPC_M(17.5, 6.5); SCPC_L(6.5, 17.5);
            }
        }
    });
    cache[key] = img;
    return img;
}

// Khung cac o cua 1 bo cuc (2 o / 3 o / 1 lon + 2 nho) trong hinh minh hoa co kich thuoc size
static NSArray<NSValue *> *SCPCLayoutBoxes(int layoutID, BOOL vertical, CGSize size)
{
    CGFloat gap = 2.5;
    NSMutableArray<NSValue *> *boxes = [NSMutableArray array];
    if (SCPCIsStackLayout(layoutID)) {
        if (vertical) {
            CGFloat mh = floor((size.height - gap) / 2), bw = floor((size.width - gap) / 2);
            [boxes addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, size.width, mh)]];
            [boxes addObject:[NSValue valueWithCGRect:CGRectMake(0, mh + gap, bw, size.height - mh - gap)]];
            [boxes addObject:[NSValue valueWithCGRect:CGRectMake(bw + gap, mh + gap, size.width - bw - gap, size.height - mh - gap)]];
        } else {
            CGFloat mw = floor((size.width - gap) / 2), th = floor((size.height - gap) / 2);
            [boxes addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, mw, size.height)]];
            [boxes addObject:[NSValue valueWithCGRect:CGRectMake(mw + gap, 0, size.width - mw - gap, th)]];
            [boxes addObject:[NSValue valueWithCGRect:CGRectMake(mw + gap, th + gap, size.width - mw - gap, size.height - th - gap)]];
        }
        if (layoutID == SCPC_LAYOUT_MAIN_RIGHT) {   // lat theo chieu chia: o lon sang phai (man doc: xuong duoi)
            for (NSUInteger i = 0; i < boxes.count; i++) {
                CGRect b = boxes[i].CGRectValue;
                if (vertical) b.origin.y = size.height - CGRectGetMaxY(b); else b.origin.x = size.width - CGRectGetMaxX(b);
                boxes[i] = [NSValue valueWithCGRect:b];
            }
        }
        return boxes;
    }
    int n = SCPCPanesForLayout(layoutID);
    CGFloat len = (vertical ? size.height : size.width) - gap * (n - 1), pos = 0;
    for (int i = 0; i < n; i++) {
        CGFloat w = (i == n - 1) ? len - floor(len / n) * (n - 1) : floor(len / n);
        [boxes addObject:[NSValue valueWithCGRect:vertical ? CGRectMake(0, pos, size.width, w) : CGRectMake(pos, 0, w, size.height)]];
        pos += w + gap;
    }
    return boxes;
}

// apps = nil: hinh bo cuc mac dinh (o dau xanh = cho app dang mo). apps != nil: hinh "gan day / yeu thich",
// moi o la icon cua app trong o do.
// Hinh 1 bo cuc trong bang nut Split Screen. apps[i] = bundle cua app trong o i -> o hien icon app do;
// NSNull / thieu (apps = nil: moi o) -> o trong vien mo + dau cong = cho chon app.
// selected: bo cuc dang dung (o vien cau vong) -> o sang hon mot chut. Moi o: kinh trang trong + vien trang 1.5pt
// (nhu vanh trang cua logo), dau cong mau cham nhat; khong vien den / tim.
static UIImage *SCPCLayoutImage(int layoutID, BOOL vertical, CGSize size, NSArray *apps, BOOL selected)
{
    NSArray<NSValue *> *boxes = SCPCLayoutBoxes(layoutID, vertical, size);
    UIColor *box = [UIColor colorWithWhite:1 alpha:selected ? 0.75 : 0.45];
    UIColor *edgeColor = [UIColor colorWithWhite:1 alpha:0.95];
    UIColor *plusColor = SCPCInk2();
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        for (NSUInteger i = 0; i < boxes.count; i++) {
            CGRect b = boxes[i].CGRectValue;
            NSString *bid = (i < apps.count && [apps[i] isKindOfClass:[NSString class]]) ? apps[i] : nil;
            UIImage *icon = bid ? SCPCAppIcon(bid) : nil;
            if (icon) {
                [box setFill];
                [[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:5] fill];
                [edgeColor setStroke];
                UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 0.75, 0.75) cornerRadius:4.4];
                rim.lineWidth = 1.5;
                [rim stroke];
                CGFloat side = floor(MIN(b.size.width, b.size.height) - 4);
                CGRect ir = CGRectMake(CGRectGetMidX(b) - side / 2, CGRectGetMidY(b) - side / 2, side, side);
                CGContextSaveGState(rc.CGContext);
                [[UIBezierPath bezierPathWithRoundedRect:ir cornerRadius:side * 0.27] addClip];
                [icon drawInRect:ir];
                CGContextRestoreGState(rc.CGContext);
                continue;
            }
            [box setFill];
            [[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:5] fill];
            [edgeColor setStroke];
            UIBezierPath *edge = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 0.75, 0.75) cornerRadius:4.4];
            edge.lineWidth = 1.5;
            [edge stroke];
            CGFloat arm = MIN(4, floor(MIN(b.size.width, b.size.height) / 4));
            UIBezierPath *plus = [UIBezierPath bezierPath];
            plus.lineWidth = 1.4; plus.lineCapStyle = kCGLineCapRound;
            [plus moveToPoint:CGPointMake(CGRectGetMidX(b) - arm, CGRectGetMidY(b))];
            [plus addLineToPoint:CGPointMake(CGRectGetMidX(b) + arm, CGRectGetMidY(b))];
            [plus moveToPoint:CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b) - arm)];
            [plus addLineToPoint:CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b) + arm)];
            [plusColor setStroke];
            [plus stroke];
        }
    }];
}

// Nen kinh trang dac (khong blur): vien sang manh, bo goc lien tuc (squircle), bong tim nhat
static void SCPCChrome(UIView *v, CGFloat radius)
{
    v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.borderWidth = 0.5;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
    v.layer.shadowColor = SCPCShadow().CGColor;
    v.layer.shadowOpacity = 0.25; v.layer.shadowRadius = 10; v.layer.shadowOffset = CGSizeMake(0, 4);
}

// Icon app: squircle kieu HarmonyOS
static void SCPCStyleIcon(UIImageView *iv)
{
    iv.layer.cornerRadius = iv.bounds.size.width * 0.27;
    iv.layer.cornerCurve = kCACornerCurveContinuous;
    iv.clipsToBounds = YES;
    iv.backgroundColor = iv.image ? [UIColor clearColor] : SCPCPastel();
}

// Nut cham thi lun nhe
@interface SCPCButton : UIButton
@end
@implementation SCPCButton
// Nut nho (34pt, nut x 34pt...) van nhan cham trong vung toi thieu 44 x 44pt (dung tay khi lai xe)
- (BOOL)pointInside:(CGPoint)pt withEvent:(UIEvent *)e
{
    CGFloat dx = MIN(0, (self.bounds.size.width - 44) / 2), dy = MIN(0, (self.bounds.size.height - 44) / 2);
    return CGRectContainsPoint(CGRectInset(self.bounds, dx, dy), pt);
}

- (void)setHighlighted:(BOOL)h
{
    BOOL changed = (h != self.highlighted);
    [super setHighlighted:h];
    if (!changed) return;
    [UIView animateWithDuration:h ? 0.12 : 0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = h ? CGAffineTransformMakeScale(0.9, 0.9) : CGAffineTransformIdentity; }
                     completion:nil];
}
@end

// Nut trong suot, dat trong thanh vien thuoc
static UIButton *SCPCRoundButton(UIImage *img, id target, SEL action)
{
    UIButton *b = [SCPCButton buttonWithType:UIButtonTypeCustom];
    b.bounds = CGRectMake(0, 0, SCPC_BTN, SCPC_BTN);
    b.layer.cornerRadius = SCPC_BTN / 2;
    b.tintColor = SCPCInk();
    [b setImage:img forState:UIControlStateNormal];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// Nut tron dung rieng (nen kinh trang)
static UIButton *SCPCCircleButton(UIImage *img, CGFloat size, id target, SEL action)
{
    UIButton *b = SCPCRoundButton(img, target, action);
    b.bounds = CGRectMake(0, 0, size, size);
    SCPCChrome(b, size / 2);
    return b;
}

// Kinh trang mo cho thanh nut / bang; che do nhe (OMCLiteActive): nen trang dac, khong blur (blur tren ban do dang
// chay ton GPU tung khung hinh)
static UIVisualEffectView *SCPCGlassView(void)
{
    if (!OMCLiteActive())
        return [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight]];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:nil];
    v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.92];
    return v;
}

// Nen bang nho (thanh •••, thanh ti le, thong bao): kinh mo + nen logo 4 mau, vien trang, bong tim nhat
static void SCPCGlass(UIView *v, CGFloat radius)
{
    v.backgroundColor = [UIColor clearColor];
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.shadowColor = SCPCShadow().CGColor;
    v.layer.shadowOpacity = 0.3; v.layer.shadowRadius = 14; v.layer.shadowOffset = CGSizeMake(0, 6);
    UIVisualEffectView *glass = SCPCGlassView();
    glass.frame = v.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    SCPCMesh(glass);
    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    glass.userInteractionEnabled = NO;
    [v insertSubview:glass atIndex:0];
}

// O kinh mo nho (nut dock, cham tron keo vach): chi lop mo + trang 35% + vien sang, khong bong; lop nam duoi moi thu
// da co trong view (nut dock: duoi hinh; cham tron: duoi cham giua)
static void SCPCGlassFill(UIView *v, CGFloat radius)
{
    v.backgroundColor = [UIColor clearColor];
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    UIVisualEffectView *glass = SCPCGlassView();
    glass.frame = v.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.borderWidth = 0.5;
    glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
    glass.clipsToBounds = YES;
    glass.userInteractionEnabled = NO;
    [v insertSubview:glass atIndex:0];
}

// Thanh vien thuoc chua cac nut (ngang hoac doc). [NSNull null] = vach ngan cach (truoc nut tat / dong)
static UIView *SCPCPill(NSArray *items, BOOL vertical)
{
    CGFloat pad = (SCPC_PILL - SCPC_BTN) / 2, step = SCPC_BTN + 2, sep = 9;
    CGFloat len = pad * 2 - 2;
    for (id it in items) len += [it isKindOfClass:[UIButton class]] ? step : sep;
    UIView *v = [[UIView alloc] initWithFrame:vertical ? CGRectMake(0, 0, SCPC_PILL, len) : CGRectMake(0, 0, len, SCPC_PILL)];
    SCPCGlass(v, SCPC_PILL / 2);
    CGFloat o = pad;
    for (id it in items) {
        if (![it isKindOfClass:[UIButton class]]) {
            UIView *line = [[UIView alloc] init];
            line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.95];
            line.userInteractionEnabled = NO;
            CGFloat c = o - 1 + sep / 2;   // giua khe (2pt sau nut truoc + sep)
            line.frame = vertical ? CGRectMake((SCPC_PILL - 18) / 2, c, 18, 1) : CGRectMake(c, (SCPC_PILL - 18) / 2, 1, 18);
            [v addSubview:line];
            o += sep;
            continue;
        }
        UIButton *b = it;
        b.center = vertical ? CGPointMake(SCPC_PILL / 2, o + SCPC_BTN / 2) : CGPointMake(o + SCPC_BTN / 2, SCPC_PILL / 2);
        o += step;
        [v addSubview:b];
    }
    return v;
}

// Nut cua thanh •••: o kinh tron 30pt (nhu nut X cua khay) + nhan ngan ben duoi - man xe nhin luot, chi icon de nham
// Chay nen / Cua so noi. tint: mau icon + nhan (nut Tat: do).
#define SCPC_ACT_W     50.0
#define SCPC_ACT_BAR   58.0    // be day thanh •••
#define SCPC_ACT_DISC  7301
#define SCPC_ACT_ICON  7302
#define SCPC_ACT_LABEL 7303
static void SCPCActionSet(UIButton *b, NSString *glyph, NSString *title)
{
    ((UIImageView *)[b viewWithTag:SCPC_ACT_ICON]).image = SCPCGlyph(glyph, 18, NO);
    UILabel *l = (UILabel *)[b viewWithTag:SCPC_ACT_LABEL];
    l.text = title;
    l.textColor = b.tintColor;
    b.accessibilityLabel = title;
}

static UIButton *SCPCActionButton(NSString *glyph, NSString *title, UIColor *tint, id target, SEL action)
{
    UIButton *b = [SCPCButton buttonWithType:UIButtonTypeCustom];
    b.bounds = CGRectMake(0, 0, SCPC_ACT_W, 50);
    b.tintColor = tint;
    UIView *disc = [[UIView alloc] initWithFrame:CGRectMake((SCPC_ACT_W - 30) / 2, 3, 30, 30)];
    disc.tag = SCPC_ACT_DISC;
    disc.userInteractionEnabled = NO;
    SCPCTile(disc, 15);
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectInset(disc.bounds, 6, 6)];
    iv.tag = SCPC_ACT_ICON;
    iv.contentMode = UIViewContentModeCenter;
    [disc addSubview:iv];
    [b addSubview:disc];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(-3, 36, SCPC_ACT_W + 6, 11)];
    l.tag = SCPC_ACT_LABEL;
    l.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    l.textAlignment = NSTextAlignmentCenter;
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.75;
    l.userInteractionEnabled = NO;
    [b addSubview:l];
    SCPCActionSet(b, glyph, title);
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// Thanh •••: vien thuoc nen logo, cac nut sat nhau; [NSNull null] = vach trang tach nut Tat khoi cac nut con lai
static UIView *SCPCActionBar(NSArray *items)
{
    CGFloat pad = 6, sep = 7, len = pad * 2;
    for (id it in items) len += [it isKindOfClass:[UIButton class]] ? SCPC_ACT_W : sep;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, len, SCPC_ACT_BAR)];
    SCPCGlass(v, 22);
    CGFloat o = pad;
    for (id it in items) {
        if (![it isKindOfClass:[UIButton class]]) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(o + (sep - 1) / 2, (SCPC_ACT_BAR - 30) / 2, 1, 30)];
            line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.95];
            line.layer.cornerRadius = 0.5;
            line.userInteractionEnabled = NO;
            [v addSubview:line];
            o += sep;
            continue;
        }
        UIButton *b = it;
        b.center = CGPointMake(o + SCPC_ACT_W / 2, SCPC_ACT_BAR / 2);
        o += SCPC_ACT_W;
        [v addSubview:b];
    }
    return v;
}

// Hien kieu HarmonyOS: mo dan + troi xuong nhe tu tren + phong tu 0.9, lo xo em (khong nay)
static void SCPCDropIn(UIView *v)
{
    CGAffineTransform target = v.transform;   // giu ti le thu nho (thanh nut trong o hep)
    v.alpha = 0; v.transform = CGAffineTransformConcat(CGAffineTransformScale(target, 0.9, 0.9), CGAffineTransformMakeTranslation(0, -8));
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ v.alpha = 1; v.transform = target; } completion:nil];
}

// ---------------------------------------------------------------------
//  View
// ---------------------------------------------------------------------
@interface SCPCarSplitView : UIView
@property (nonatomic, copy) void (^touched)(CGPoint p);
@end
@implementation SCPCarSplitView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e
{
    UIView *v = [super hitTest:p withEvent:e];
    if (v && self.touched && e.type == UIEventTypeTouches) self.touched(p);
    return v;
}
@end

// Duong ranh mong nhung vung cham rong. Vach thu `index` nam giua o index va index + 1.
@interface SCPCarDividerView : UIView
@property (nonatomic) int index;
@property (nonatomic, strong) UIView *knob;
@end
static void SCPCKnobActive(UIView *knob, BOOL on);
// O khong vien (vien xanh khi chon / keo tha chi tam, xong thi bo)
static void SCPCFrame(UIView *v) { v.layer.borderWidth = 0; }

@implementation SCPCarDividerView
// Ngon tay vua cham vao cham tron -> phong to ngay (chua can keo), nhac tay -> thu lai
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e
{
    [super touchesBegan:touches withEvent:e];
    if (self.knob && !self.knob.hidden) SCPCKnobActive(self.knob, YES);
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e
{
    [super touchesEnded:touches withEvent:e];
    if (self.knob) SCPCKnobActive(self.knob, NO);
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e
{
    [super touchesCancelled:touches withEvent:e];
    if (self.knob) SCPCKnobActive(self.knob, NO);
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e
{
    // Quanh tay nam: vung cham rong de de keo / cham. Doc phan con lai cua vach: hep (+-6) de khong che
    // thanh "•••" cua o ngay sat vach (vach ngang nam ngay tren thanh "•••" cua o duoi).
    if (self.knob && !self.knob.hidden && CGRectContainsPoint(CGRectInset(self.knob.frame, -SCPC_DIVIDER_HIT, -SCPC_DIVIDER_HIT), p)) return YES;
    return CGRectContainsPoint(CGRectInset(self.bounds, -6, -6), p);
}
@end

@interface SCPCarTabView : UIView
@end
@implementation SCPCarTabView
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e { return CGRectContainsPoint(CGRectInset(self.bounds, -18, -14), p); }
@end

@interface SCPCarPane : NSObject
@property (nonatomic) int slot;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) UIViewController *vc;   // DBApplicationSceneViewController
@property (nonatomic, strong) UIView *view;           // khung ngan (bo goc)
@property (nonatomic, strong) UIView *host;           // chua view cua app
@property (nonatomic, strong) UIView *handle;         // thanh "•••" giua mep tren
@property (nonatomic, strong) UIView *bar;            // hang nut cua ngan
@property (nonatomic, strong) UIView *cover;          // the toi + icon app luc keo vach / keo doi cho (HyperOS)
@property (nonatomic, strong) UIView *loader;         // the "dang mo app" (icon phong ra + nhip tho) cho toi khi app hien
@property (nonatomic, strong) UIButton *popButton;    // nut "dua ra cua so noi" tren thanh nut
@property (nonatomic, strong) UIButton *soloButton;   // nut "chay 1 man hinh" / "chia man hinh" (dang chay 1 man hinh)
@property (nonatomic, strong) NSTimer *barTimer;
@property (nonatomic, strong) UIView *picker;         // bang chon app cho ngan nay
@property (nonatomic) CGRect hostFrame;               // khung cua so host (App Bridge) da gui lan cuoi
@property (nonatomic) BOOL hostHandle;                // lan gui gan nhat co thanh "•••" do SpringBoard ve khong
@property (nonatomic) BOOL hostBar;                   // lan gui gan nhat co thanh nut do SpringBoard ve de len app khong
@property (nonatomic) CGSize sceneSize;               // kich thuoc da bao cho scene lan cuoi
@end
@implementation SCPCarPane
@end

// VC gia dai dien app iPhone do SpringBoard host (App Bridge) trong o: tra loi cac selector ma split goi tren
// VC cua DashBoard (background / foreground scene, applicationInfo...) de bo cuc dung chung, khong lam gi.
@interface SCPHostedAppVC : UIViewController
@property (nonatomic, copy) NSString *bundleID;
@end
@implementation SCPHostedAppVC
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1]; }
- (void)backgroundSceneWithCompletion:(id)completion { if (completion) ((void (^)(void))completion)(); }
- (void)foregroundSceneWithSettings:(id)settings completion:(id)completion { if (completion) ((void (^)(void))completion)(); }
- (id)applicationInfo { return nil; }
- (id)proxyApplicationInfo { return nil; }
- (id)sceneHostView { return nil; }
@end

static BOOL SCPCIsHostedVC(UIViewController *vc) { return [vc isKindOfClass:[SCPHostedAppVC class]]; }
static BOOL SCPCIsBridgedApp(NSString *bid);

@interface SCPCarSplit () <UIScrollViewDelegate>
@property (nonatomic, readwrite) BOOL active;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *cancelledLaunches;   // app bi huy luc dang mo
@property (nonatomic, strong) UIView *soloCover;      // the icon app che luc ve man chinh roi mo lai app toan man
@property (nonatomic, strong) UIView *trayCover;      // the icon app che vung app toan man (App Bridge) khi bang bo cuc mo (cua so host an)
@property (nonatomic, strong) UIWindow *trayWindow;    // cua so rieng cua bang bo cuc (tren cua so App Bridge), giu lai giua cac lan mo
@property (nonatomic) BOOL trayOverlay;                // bang dang nam trong trayWindow (de len o app iPhone, khong can an o)
@property (nonatomic, strong) NSNumber *zoomedSlot;    // phong to tam 1 o (cham dup "•••"): o do phu ca vung app, cac o khac an
                                                       // nhung giu nguyen kich thuoc scene; nil = binh thuong
@property (nonatomic, copy) NSString *lastBridgeTapBundle;   // cham "•••" cua app iPhone (SpringBoard ve) lan truoc ...
@property (nonatomic) CFAbsoluteTime lastBridgeTapAt;        // ... va luc nao: 2 lan lien = cham dup
@property (nonatomic, strong) UIView *pickerSheet;     // bang chon app toan man (trong trayWindow, hoac container neu khong tao duoc)
@property (nonatomic, strong) UIView *pickerShield;    // lop phu duoi bang chon app
@property (nonatomic, weak) SCPCarPane *pickerSheetPane;   // o dang chon app trong bang
@property (nonatomic, copy) NSString *pickerSheetKey;  // o / bo cuc bang dang ve (khac -> ve lai)
@property (nonatomic) BOOL pickerSheetOverlay;         // bang nam trong trayWindow
@property (nonatomic) BOOL pickerSheetQueued;
@property (nonatomic, weak) UIView *pickerDots;        // cham trang cua popup chon app (nhieu trang)
@property (nonatomic, strong) SCPCarSplitView *container;
@property (nonatomic, strong) NSMutableArray<SCPCarPane *> *slots;        // cac o theo thu tu (1..3)
@property (nonatomic, strong) NSMutableArray<NSNumber *> *fractions;      // ti le tung o, tong = 1
                                                                          // (1 lon + 2 nho: [ti le o lon, ti le o nho tren])
@property (nonatomic) NSInteger layoutKind;                              // SCPCLayoutColumns / SCPCLayoutMainStack
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray *> *pending;   // bundle -> @[slot, NSDate]
@property (nonatomic) int focusedSlot;
@property (nonatomic) NSInteger allowBackground;
@property (nonatomic, strong) NSMutableArray<SCPCarDividerView *> *dividers;   // vach giua o i va i + 1
@property (nonatomic) BOOL loggedArea;
@property (nonatomic) CFAbsoluteTime nextLaunchAt;   // lan mo app ke tiep som nhat (DashBoard can xong lan truoc)
@property (nonatomic, copy) NSString *soloHostedBundle;   // app iPhone dang hien toan man qua App Bridge (khong chia)
@property (nonatomic) CGRect soloHostedFrame;
@property (nonatomic) BOOL ignoreHomeOnce;                // su kien Home do chinh split gui (tat split) -> khong dong app toan man
@property (nonatomic, weak) UIViewController *soloReturnedVC;   // VC split vua tra DashBoard trinh bay toan man (Home sau do co the ket)
@property (nonatomic) BOOL resizing;                 // dang keo vach / keo doi cho: moi o phu the icon, CBWindow an
@property (nonatomic, strong) UIView *dragGhost;     // the icon theo tay khi keo "•••" de doi cho
@property (nonatomic) int dragTarget;                // o dang duoc tha vao (-1 = khong)
@property (nonatomic, strong) UIView *ratioMenu;     // cham tay nam: thanh chon ti le mac dinh
@property (nonatomic, weak) UIView *ratioKnob;       // tay nam dang mo thanh ti le (to xanh)
@property (nonatomic, strong) NSTimer *ratioTimer;
@property (nonatomic) BOOL ratioOverlay;              // thanh ti le nam tren trayWindow (de len o App Bridge, khong an o)
@property (nonatomic) BOOL ratioHidesBridge;          // thanh ti le de len o CarBridge -> CBWindow tam an
// Cua so noi kieu HyperOS: 1 o rieng nam tren cac o chia, keo "•••" de di chuyen, tha ra hit sat canh
@property (nonatomic, strong) SCPCarPane *floatPane;
@property (nonatomic) CGRect floatFrame;             // khung cua so noi (toa do container)
@property (nonatomic) BOOL floatClosing;             // da hen dong cua so noi (bi app CarBridge che)
@property (nonatomic) BOOL floatLarge;               // cua so noi co lon (cham 2 lan "•••" de doi)
// Bo cuc truoc khi dua app ra hinh trong hinh -> nut "dua ve o" tra app ve dung cho cu
@property (nonatomic) int floatReturnLayout;          // ma bo cuc luc do (2 / 3 / 13 / 31), 0 = khong co
@property (nonatomic) int floatReturnSlot;            // o cua app luc do
@property (nonatomic, copy) NSArray<NSNumber *> *floatReturnFractions;
// Tab tren app CarPlay dang mo toan man (chua split): cham / vuot xuong -> hang icon app CarPlay
@property (nonatomic, strong) UIView *tray;
@property (nonatomic, strong) UIView *trayShield;
@property (nonatomic) BOOL trayHidesBridge;           // bang bo cuc dang mo tren app iPhone toan man -> cua so host tam an
@property (nonatomic, strong) NSTimer *trayTimer;
@property (nonatomic, copy) NSString *layoutApp;      // app vao o 1 khi chon bo cuc (nil = cap lan truoc)
@property (nonatomic, strong) NSArray<NSDictionary *> *panelChoices;   // cac lua chon trong bang (tag nut = chi so)
@property (nonatomic) BOOL suppressReopen;           // bat split ma KHONG mo lai app dang toan man vao o 1
// Chua split: nut Split Screen tren dock CarPlay (tren nut Home) + giu icon app tren man chinh de chia man
@property (nonatomic, strong) UIButton *homeButton;
@property (nonatomic, weak) UIView *launcherHost;      // view dang chua nut Split Screen (view dai dock hoac tabParent)
@property (nonatomic) BOOL dockTreeLogged;             // da ghi cay view dai dock (1 lan / tien trinh)
@property (nonatomic, copy) NSString *launcherWhere;  // vi tri nut Split Screen lan truoc (chi de ghi log khi doi)
@property (nonatomic, strong) UIColor *homeInk;       // mau luoi app cua nut Home dock (nut Split Screen ve cung mau)
@property (nonatomic) BOOL launcherBare;              // nut Split Screen dang la hinh tran (tren dock) hay nut tron kinh (goc vung app)
@property (nonatomic) CFAbsoluteTime lastLauncherCalc;  // lan do dock gan nhat (do lai toi da 1 lan / giay)
@property (nonatomic) CFAbsoluteTime lastIconScan;
@property (nonatomic) BOOL autoLaunchDone;           // da tu mo split cho lan cam xe nay
@end

@implementation SCPCarSplit

+ (instancetype)shared
{
    static SCPCarSplit *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SCPCarSplit new]; });
    return s;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _pending = [NSMutableDictionary dictionary];
        _cancelledLaunches = [NSMutableDictionary dictionary];
        _dragTarget = -1;
    }
    return self;
}

- (BOOL)isCarPlayApp:(NSString *)bundleID { return SCPCInfoIsCarPlayApp(SCPCAppInfo(bundleID)) || SCPCIsBridgedApp(bundleID); }

- (NSString *)displayNameFor:(NSString *)bid
{
    id info = SCPCAppInfo(bid);
    NSString *n = info ? objcInvoke(info, @"displayName") : nil;
    if (!n.length && bid.length) {   // app iPhone (khong co trong thu vien CarPlay)
        Class lp = objc_getClass("LSApplicationProxy");
        id proxy = lp ? objcInvoke_1(lp, @"applicationProxyForIdentifier:", bid) : nil;
        n = proxy ? objcInvoke(proxy, @"localizedName") : nil;
    }
    return n.length ? n : bid;
}

// Huong chia tu theo man xe: man ngang -> trai / phai, man doc (cao hon rong) -> tren / duoi
- (BOOL)vertical
{
    CGSize sz = self.container ? self.container.bounds.size : CGSizeZero;
    if (sz.width < 1) {
        UIView *parent = [self tabParent];
        if (parent) sz = [self appAreaInParent:parent].size;
    }
    return sz.width > 1 && sz.height > sz.width;
}

// Cac o chia + cua so noi (neu co)
- (NSArray<SCPCarPane *> *)allPanes
{
    if (!self.floatPane) return [self.slots copy] ?: @[];
    return [(self.slots ?: @[]) arrayByAddingObject:self.floatPane];
}

// O theo so: 0..n-1 = o chia, SCPC_FLOAT_SLOT = cua so noi; nil neu khong co
- (SCPCarPane *)paneAtSlot:(int)s
{
    if (s == SCPC_FLOAT_SLOT) return self.floatPane;
    return (s >= 0 && s < (int)self.slots.count) ? self.slots[s] : nil;
}

- (BOOL)validSlot:(int)s { return [self paneAtSlot:s] != nil; }

- (SCPCarPane *)paneForBundle:(NSString *)bid
{
    if (!bid) return nil;
    for (SCPCarPane *p in [self allPanes]) if (p.vc && [p.bundleID isEqualToString:bid]) return p;
    return nil;
}

- (void)purgePending
{
    NSDate *now = [NSDate date];
    for (NSString *bid in self.pending.allKeys) {
        if ([now timeIntervalSinceDate:self.pending[bid][1]] > SCPC_PENDING_TTL) {
            SCPLog("CarSplit: het han cho %@ (DashBoard khong trinh bay app)", bid);
            [self.pending removeObjectForKey:bid];
        }
    }
}

- (int)pendingSlotForBundle:(NSString *)bid
{
    NSArray *v = bid ? self.pending[bid] : nil;
    if (!v || [[NSDate date] timeIntervalSinceDate:v[1]] > SCPC_PENDING_TTL) return -1;
    return [v[0] intValue];
}

- (BOOL)slotOccupied:(int)s
{
    SCPCarPane *p = [self paneAtSlot:s];
    if (!p) return NO;
    if (p.vc || p.picker) return YES;
    for (NSString *bid in self.pending) if ([self pendingSlotForBundle:bid] == s) return YES;
    return NO;
}

- (int)paneCount { return (int)self.slots.count; }

// 1 lon + 2 nho (o lon trai) hoac 2 + 1 lon (o lon phai): cung hinh hoc, chi lat theo chieu chia
- (BOOL)mainStack
{
    return (self.layoutKind == SCPCLayoutMainStack || self.layoutKind == SCPCLayoutMainRight) && [self paneCount] == 3;
}

- (BOOL)mainRight { return [self mainStack] && self.layoutKind == SCPCLayoutMainRight; }

// Ma bo cuc hien tai (2 / 3 / 13 / 31)
- (int)layoutID
{
    if ([self mainRight]) return SCPC_LAYOUT_MAIN_RIGHT;
    return [self mainStack] ? SCPC_LAYOUT_MAIN_STACK : [self paneCount];
}

// Vach i nam ngang (chia theo chieu doc)? 3 cot: theo kieu chia; 1 lon + 2 nho: vach 1 vuong goc vach 0
- (BOOL)dividerRunsHorizontally:(int)i
{
    BOOL v = [self vertical];
    return ([self mainStack] && i == 1) ? !v : v;
}

// 1 lon + 2 nho; 2 + 1 lon = lat theo chieu chia (ngang: o lon sang phai, doc: o lon xuong duoi)
- (CGRect)mainStackFrameForSlot:(int)s inArea:(CGRect)a
{
    CGRect r = [self leftMainStackFrameForSlot:s inArea:a];
    if (![self mainRight]) return r;
    if ([self vertical]) r.origin.y = CGRectGetMinY(a) + CGRectGetMaxY(a) - CGRectGetMaxY(r);
    else r.origin.x = CGRectGetMinX(a) + CGRectGetMaxX(a) - CGRectGetMaxX(r);
    return r;
}

// 1 lon + 2 nho. Ngang: o lon ben trai, 2 o nho chong len nhau ben phai. Doc: o lon tren, 2 o nho canh nhau duoi.
- (CGRect)leftMainStackFrameForSlot:(int)s inArea:(CGRect)a
{
    BOOL v = [self vertical];
    CGFloat mainLen = floor(((v ? a.size.height : a.size.width) - SCPC_GAP) * [self fractionAt:0]);
    CGRect main = v ? CGRectMake(a.origin.x, a.origin.y, a.size.width, mainLen)
                    : CGRectMake(a.origin.x, a.origin.y, mainLen, a.size.height);
    if (s == 0) return main;
    CGRect rest = v ? CGRectMake(a.origin.x, a.origin.y + mainLen + SCPC_GAP, a.size.width, a.size.height - mainLen - SCPC_GAP)
                    : CGRectMake(a.origin.x + mainLen + SCPC_GAP, a.origin.y, a.size.width - mainLen - SCPC_GAP, a.size.height);
    CGFloat first = floor(((v ? rest.size.width : rest.size.height) - SCPC_GAP) * [self fractionAt:1]);
    if (v) {
        if (s == 1) return CGRectMake(rest.origin.x, rest.origin.y, first, rest.size.height);
        return CGRectMake(rest.origin.x + first + SCPC_GAP, rest.origin.y, rest.size.width - first - SCPC_GAP, rest.size.height);
    }
    if (s == 1) return CGRectMake(rest.origin.x, rest.origin.y, rest.size.width, first);
    return CGRectMake(rest.origin.x, rest.origin.y + first + SCPC_GAP, rest.size.width, rest.size.height - first - SCPC_GAP);
}

- (CGFloat)fractionAt:(int)i
{
    int n = [self paneCount];
    if (i < 0 || i >= (int)self.fractions.count || n <= 0) return n > 0 ? 1.0 / n : 1;
    return self.fractions[i].doubleValue;
}

// Ngan cho app moi khi khong chi dinh: ngan trong truoc, het cho thi ngan dang duoc cham gan nhat
// App ghim (SPL_KEY_PINNED_APP): o chua no khong bi thay / bo khi doi bo cuc hay chon app
static NSString *SCPCPinnedApp(void)
{
    NSString *bid = OMCPref(SPL_KEY_PINNED_APP, nil);
    return [bid isKindOfClass:[NSString class]] && bid.length ? bid : nil;
}

- (BOOL)slotIsPinned:(int)s
{
    NSString *pin = SCPCPinnedApp();
    SCPCarPane *p = [self paneAtSlot:s];
    return pin && p && [p.bundleID isEqualToString:pin];
}

- (int)autoSlot
{
    for (int s = 0; s < [self paneCount]; s++) if (![self slotOccupied:s]) return s;
    int s = MIN(self.focusedSlot, MAX(0, [self paneCount] - 1));
    if ([self slotIsPinned:s])   // o dang chon la o ghim -> o khac
        for (int t = 0; t < [self paneCount]; t++) if (![self slotIsPinned:t]) return t;
    return s;
}

// ---------------------------------------------------------------------
//  Hinh hoc
// ---------------------------------------------------------------------
- (CGRect)frameForSlot:(int)s
{
    CGRect b = self.container.bounds;
    CGRect a = CGRectInset(b, SCPC_INSET, SCPC_INSET);
    CGRect none = CGRectMake(a.origin.x, a.origin.y, 0, 0);
    if (s == SCPC_FLOAT_SLOT) return self.floatPane ? self.floatFrame : none;
    int n = [self paneCount];
    if (s < 0 || s >= n) return none;
    if (n == 1) return a;
    if (self.zoomedSlot && self.zoomedSlot.intValue == s) return a;   // o dang phong to tam
    if ([self mainStack]) return [self mainStackFrameForSlot:s inArea:a];
    BOOL v = [self vertical];
    CGFloat len = (v ? a.size.height : a.size.width) - SCPC_GAP * (n - 1);
    CGFloat used = 0, size = 0;
    for (int i = 0; i <= s; i++) {
        size = (i == n - 1) ? len - used : floor(len * [self fractionAt:i]);
        if (i < s) used += size;
    }
    CGFloat start = used + SCPC_GAP * s;
    return v ? CGRectMake(a.origin.x, a.origin.y + start, a.size.width, size)
             : CGRectMake(a.origin.x + start, a.origin.y, size, a.size.height);
}

// Goc duoc bo tron cua o: goc giap o ben canh + 2 goc ben trai cua o sat mep trai (canh dock CarPlay).
// Goc sat mep man con lai / con 1 o thi vuong.
- (CACornerMask)innerCornersForSlot:(int)s
{
    if (self.zoomedSlot) return 0;   // o phong to phu ca vung app nhu 1 o
    CACornerMask m = [self neighbourCornersForSlot:s];
    if (!m) return 0;
    CGRect f = [self frameForSlot:s], a = CGRectInset(self.container.bounds, SCPC_INSET, SCPC_INSET);
    if (CGRectGetMinX(f) <= CGRectGetMinX(a) + 0.5) m |= kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    return m;
}

- (CACornerMask)neighbourCornersForSlot:(int)s
{
    int n = [self paneCount];
    if (n < 2 || s < 0 || s >= n) return 0;
    BOOL v = [self vertical];
    CACornerMask top = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner, bottom = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    CACornerMask left = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner, right = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    if ([self mainStack]) {
        // O lon: canh giap 2 o nho. O nho: canh giap o lon + canh giap nhau. 2 + 1 lon: lat goc theo chieu chia.
        CACornerMask m;
        if (s == 0) m = v ? bottom : right;
        else {
            m = v ? top : left;
            if (s == 1) m |= v ? right : bottom;
            else m |= v ? left : top;
            // Goc cua o nho ngay cho giao 2 vach (cham tron ngoi do) de vuong: giao cua 2 canh giap
            m &= ~((v ? top : left) & (s == 1 ? (v ? right : bottom) : (v ? left : top)));
        }
        return [self mainRight] ? SCPCMirrorMask(m, v) : m;
    }
    CACornerMask before = v ? top : left, after = v ? bottom : right;
    CACornerMask m = 0;
    if (s > 0) m |= before;
    if (s < n - 1) m |= after;
    return m;
}

- (BOOL)dividersVisible
{
    return [self paneCount] >= 2 && !self.zoomedSlot;
}

- (CGRect)dividerFrameAt:(int)i
{
    CGRect a = CGRectInset(self.container.bounds, SCPC_INSET, SCPC_INSET);
    if ([self mainStack] && i == 1) {
        CGRect t = [self frameForSlot:1];   // vach giua 2 o nho
        if ([self dividerRunsHorizontally:1]) return CGRectMake(t.origin.x, CGRectGetMaxY(t), t.size.width, SCPC_GAP);
        return CGRectMake(CGRectGetMaxX(t), t.origin.y, SCPC_GAP, t.size.height);
    }
    CGRect l = [self frameForSlot:i];
    // 1 lon + 2 / 2 + 1 lon: vach 0 nam sau khoi dung truoc (o lon hoac cum 2 o nho, tuy ben)
    if ([self mainStack]) {
        CGRect rest = CGRectUnion([self frameForSlot:1], [self frameForSlot:2]);
        if ([self vertical] ? CGRectGetMinY(rest) < CGRectGetMinY(l) : CGRectGetMinX(rest) < CGRectGetMinX(l)) l = rest;
    }
    if ([self vertical]) return CGRectMake(a.origin.x, CGRectGetMaxY(l), a.size.width, SCPC_GAP);
    return CGRectMake(CGRectGetMaxX(l), a.origin.y, SCPC_GAP, a.size.height);
}

// Vung danh cho app tren man xe (toa do cua view cha cua container): contentView cua DashBoard
// tru phan dock/status bar (o canh tai xe). Tim thay view dock thi cat dung phan dock; khong thi dung statusBarInsets.
- (CGRect)appAreaInParent:(UIView *)parent
{
    UIViewController *root = SCPCRootVC();
    UIView *content = objcInvoke(root, @"contentView") ?: root.view;
    CGRect area = [parent convertRect:content.bounds fromView:content];

    UIView *dock = nil;
    @try { id dockVC = objcInvoke(root, @"appDockViewController"); dock = dockVC ? objcInvoke(dockVC, @"view") : nil; } @catch (NSException *e) {}
    CGRect dockRect = CGRectNull;
    if (dock.window && !dock.hidden && parent.window) {
        UIScreen *screen = parent.window.screen ?: dock.window.screen;
        if (screen) {
            CGRect inScreen = [dock convertRect:dock.bounds toCoordinateSpace:screen.coordinateSpace];
            dockRect = [parent convertRect:inScreen fromCoordinateSpace:screen.coordinateSpace];
        }
    }
    CGRect inter = CGRectIsNull(dockRect) ? CGRectNull : CGRectIntersection(area, dockRect);
    UIEdgeInsets ins = UIEdgeInsetsZero;
    id d = SCPCDashboard();
    if ([d respondsToSelector:NSSelectorFromString(@"statusBarInsets")]) {
        ins = ((UIEdgeInsets (*)(id, SEL))objc_msgSend)(d, NSSelectorFromString(@"statusBarInsets"));
    }
    // View dock chi bao khung cum icon (vd {{0,64.5},{45,111}}), khong phai ca thanh dock cao het man.
    // Xac dinh huong dock theo hinh dang cua chinh no va mep no bam vao, roi cat het chieu doc/ngang
    // o mep do. Gop voi statusBarInsets (lay max tung canh) de khong cat trung 2 lan.
    UIEdgeInsets cut = ins;
    if (!CGRectIsNull(inter) && inter.size.width > 1 && inter.size.height > 1) {
        if (inter.size.height >= inter.size.width) {          // dock doc o mep trai/phai
            CGFloat leftGap = inter.origin.x - area.origin.x, rightGap = CGRectGetMaxX(area) - CGRectGetMaxX(inter);
            if (leftGap <= rightGap) cut.left = MAX(cut.left, CGRectGetMaxX(inter) - area.origin.x);
            else cut.right = MAX(cut.right, CGRectGetMaxX(area) - inter.origin.x);
        } else {                                              // dock ngang o mep tren/duoi
            CGFloat topGap = inter.origin.y - area.origin.y, botGap = CGRectGetMaxY(area) - CGRectGetMaxY(inter);
            if (topGap <= botGap) cut.top = MAX(cut.top, CGRectGetMaxY(inter) - area.origin.y);
            else cut.bottom = MAX(cut.bottom, CGRectGetMaxY(area) - inter.origin.y);
        }
    }
    CGRect result = UIEdgeInsetsInsetRect(area, cut);
    if (result.size.width < area.size.width * 0.5 || result.size.height < area.size.height * 0.5) {
        result = UIEdgeInsetsInsetRect(area, ins);            // cat qua tay -> chi dung statusBarInsets
    }
    if (!self.loggedArea) {
        self.loggedArea = YES;
        SCPLog("CarSplit: content=%@ dock=%@ statusBarInsets={%.0f,%.0f,%.0f,%.0f} -> vung app=%@",
               NSStringFromCGRect(area), NSStringFromCGRect(dockRect), ins.top, ins.left, ins.bottom, ins.right, NSStringFromCGRect(result));
    }
    return result;
}

// ---------------------------------------------------------------------
//  Tao / dat container vao cay view cua DashBoard
// ---------------------------------------------------------------------
- (BOOL)ensureContainer
{
    if (self.container.superview) return YES;
    UIViewController *root = SCPCRootVC();
    if (!root) { SCPLog("CarSplit: chua co DBDashboardRootViewController (xe chua ket noi?)"); return NO; }
    UIView *base = objcInvoke(root, @"baseContainerView");
    UIView *parent = base.superview ?: root.view;

    SCPCarSplitView *c = [[SCPCarSplitView alloc] initWithFrame:parent.bounds];
    c.backgroundColor = [UIColor blackColor];
    c.clipsToBounds = YES;
    __weak SCPCarSplit *weakSelf = self;
    c.touched = ^(CGPoint p) {
        SCPCarSplit *me = weakSelf;
        SCPCarPane *fp = me.floatPane;
        if (fp && fp.view.alpha > 0 && CGRectContainsPoint(fp.view.frame, p)) return;   // cham vao cua so noi
        for (SCPCarPane *pane in me.slots) {
            if (pane.view.alpha <= 0 || !CGRectContainsPoint(pane.view.frame, p)) continue;
            if (me.focusedSlot != pane.slot && [me paneCount] > 1) {
                SCPCarPane *fpane = pane;
                SCPCAfter(0, ^{ [me flashFocusOnPane:fpane]; });
            }
            me.focusedSlot = pane.slot;
        }
    };
    self.container = c;
    self.slots = [NSMutableArray array];
    self.fractions = [NSMutableArray array];
    self.dividers = [NSMutableArray array];

    [parent addSubview:c];
    [self raise];
    self.loggedArea = NO;
    c.frame = [self appAreaInParent:parent];
    SCPLog("CarSplit: container trong %@ frame=%@", NSStringFromClass([parent class]), NSStringFromCGRect(c.frame));
    return YES;
}

- (SCPCarPane *)newPane
{
    SCPCarPane *p = [SCPCarPane new];
    p.view = [[UIView alloc] initWithFrame:CGRectZero];
    p.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    p.view.layer.cornerRadius = SCPC_RADIUS;
    p.view.layer.cornerCurve = kCACornerCurveContinuous;
    p.view.clipsToBounds = YES;
    SCPCFrame(p.view);
    p.host = [[UIView alloc] initWithFrame:CGRectZero];
    p.host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [p.view addSubview:p.host];
    [self setupBarForPane:p];
    return p;
}

// O vua thanh "o dang chon" (app tu dock / nut thoat dung o nay): vien tim sang loe len 1 giay
- (void)flashFocusOnPane:(SCPCarPane *)p
{
    if (!p.view || self.dragGhost) return;
    p.view.layer.borderColor = SCPCAccent().CGColor;   // mau nhan (gradient tim -> xanh troi)
    p.view.layer.borderWidth = 2.5;
    __weak SCPCarPane *weakPane = p;
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(1.0, ^{
        SCPCarPane *pp = weakPane;
        if (pp && !weakSelf.dragGhost) SCPCFrame(pp.view);
    });
}

// Danh lai so o sau khi them / bot / doi cho
// Them 1 o trong vao vi tri i (0..n): app dang cho mo o cac o phia sau doi so theo
- (SCPCarPane *)insertPaneAt:(int)i
{
    int n = [self paneCount];
    if (!self.container || n >= SCPC_MAX_PANES) return nil;
    i = MAX(0, MIN(n, i));
    SCPCarPane *p = [self newPane];
    [self.container addSubview:p.view];
    [self.slots insertObject:p atIndex:i];
    for (NSString *bid in self.pending.allKeys) {
        NSArray *v = self.pending[bid];
        int ps = [v[0] intValue];
        if (ps != SCPC_FLOAT_SLOT && ps >= i) self.pending[bid] = @[@(ps + 1), v[1]];
    }
    if (self.focusedSlot >= i) self.focusedSlot++;
    [self reindexPanes];
    return p;
}

// Nut "dua ve o" cua cua so noi: tra app ve dung o / bo cuc / ti le truoc khi dua ra hinh trong hinh.
// Bo cuc da doi tu luc do -> them 1 o o cuoi, chia deu.
- (void)floatDockBack
{
    @try {
        SCPCarPane *fp = self.floatPane;
        int n = [self paneCount];
        if (!fp.vc || !fp.bundleID) return;
        if (n >= SCPC_MAX_PANES) { [self toast:SCPCT(@"Đã đủ 3 ô, không đưa về được", @"Already 3 panes, can't dock back")]; return; }
        int saved = self.floatReturnLayout;
        BOOL same = saved && SCPCPanesForLayout(saved) == n + 1;
        int at = (same && self.floatReturnSlot >= 0 && self.floatReturnSlot <= n) ? self.floatReturnSlot : n;
        [self setBarVisible:NO forPane:fp];
        SCPCarPane *p = [self insertPaneAt:at];
        if (!p) return;
        self.layoutKind = same ? SCPCKindForLayout(saved) : SCPCLayoutColumns;
        NSUInteger want = (self.layoutKind != SCPCLayoutColumns) ? 2 : (NSUInteger)(n + 1);
        if (same && self.floatReturnFractions.count == want) self.fractions = [self.floatReturnFractions mutableCopy];
        else [self resetFractions];
        [self rebuildDividers];
        // Chuyen view app tu cua so noi vao o moi (cung VC, cung scene -> chi doi kich thuoc)
        UIViewController *vc = fp.vc;
        NSString *bid = fp.bundleID;
        [vc.view removeFromSuperview];
        vc.view.frame = p.host.bounds;
        [p.host addSubview:vc.view];
        p.vc = vc; p.bundleID = bid; p.sceneSize = CGSizeZero;
        fp.vc = nil; fp.bundleID = nil;
        [fp.barTimer invalidate]; fp.barTimer = nil;
        self.floatPane = nil;
        self.floatClosing = NO;
        self.floatReturnLayout = 0; self.floatReturnFractions = nil;
        UIView *v = fp.view;
        [UIView animateWithDuration:0.2 animations:^{ v.alpha = 0; v.transform = CGAffineTransformMakeScale(0.8, 0.8); }
                         completion:^(BOOL f) { [v removeFromSuperview]; }];
        self.focusedSlot = p.slot;
        SCPLog("CarSplit: dua %@ tu cua so noi ve o %d (bo cuc %d%@)", bid, p.slot, [self layoutID], same ? @", nhu truoc" : @"");
        [self rememberPair];
        [self rememberRecent];
        [self relayoutAnimated:YES];
    } @catch (NSException *e) { SCPLog("CarSplit: loi dua ve o %@\n%@", e, e.callStackSymbols); }
}

- (void)reindexPanes
{
    for (int i = 0; i < [self paneCount]; i++) self.slots[i].slot = i;
}

- (void)resetFractions
{
    int n = [self paneCount];
    if ((self.layoutKind == SCPCLayoutMainStack || self.layoutKind == SCPCLayoutMainRight) && n == 3) {
        self.fractions = [NSMutableArray arrayWithObjects:@0.5, @0.5, nil];   // o lon 1/2, 2 o nho chia doi
        return;
    }
    self.fractions = [NSMutableArray array];
    for (int i = 0; i < n; i++) [self.fractions addObject:@(1.0 / MAX(1, n))];
}

- (void)normalizeFractions
{
    double sum = 0;
    for (NSNumber *f in self.fractions) sum += f.doubleValue;
    if ((int)self.fractions.count != [self paneCount] || sum <= 0.01) { [self resetFractions]; return; }
    for (NSUInteger i = 0; i < self.fractions.count; i++) self.fractions[i] = @(self.fractions[i].doubleValue / sum);
}

// Moi cap o ke nhau co 1 vach (keo doi ti le, cham mo menu)
- (void)rebuildDividers
{
    [self hideRatioMenu];
    // Vach dang keo bi go giua chung -> gesture khong bao Ended nua: tha the icon / CBWindow ngay
    [self cancelPaneDrag];
    [self endResize];
    for (SCPCarDividerView *d in self.dividers) [d removeFromSuperview];
    self.dividers = [NSMutableArray array];
    for (int i = 0; i + 1 < [self paneCount]; i++) [self.dividers addObject:[self newDividerAt:i]];
}

// Dat so o cua bo cuc (1..3): them o trong o cuoi, hoac bo o cuoi (app trong do ve nen)
- (void)setPaneCount:(int)n
{
    n = MAX(1, MIN(SCPC_MAX_PANES, n));
    if (n != 3) self.layoutKind = SCPCLayoutColumns;
    if (n == [self paneCount]) return;
    while ([self paneCount] > n) [self removePaneAt:[self paneCount] - 1 background:YES];
    while ([self paneCount] < n) {
        SCPCarPane *p = [self newPane];
        [self.container addSubview:p.view];
        [self.slots addObject:p];
    }
    [self reindexPanes];
    [self resetFractions];
    [self rebuildDividers];
    SCPLog("CarSplit: bo cuc %d o", n);
}

// Go 1 o khoi bo cuc: app trong o ve nen, o phia sau don len, cac app dang cho mo doi so o theo
- (void)removePaneAt:(int)i background:(BOOL)background
{
    if (i < 0 || i >= [self paneCount]) return;
    SCPCarPane *p = self.slots[i];
    if (SCPCIsHostedVC(p.vc)) [self hostClose:p.bundleID terminate:NO];   // app iPhone: SpringBoard bo o
    [p.barTimer invalidate]; p.barTimer = nil;
    [self removePickerFromPane:p];
    if (p.vc) [self detachVC:p.vc background:background];
    p.vc = nil; p.bundleID = nil;
    [p.view removeFromSuperview];
    if (self.layoutKind != SCPCLayoutColumns) {   // ti le cua 1 lon + 2 nho khong theo tung o -> chia deu lai
        self.layoutKind = SCPCLayoutColumns;
        [self.fractions removeAllObjects];
    }
    [self.slots removeObjectAtIndex:i];
    if (i < (int)self.fractions.count) [self.fractions removeObjectAtIndex:i];
    [self normalizeFractions];
    for (NSString *bid in self.pending.allKeys) {
        NSArray *v = self.pending[bid];
        int ps = [v[0] intValue];
        if (ps == SCPC_FLOAT_SLOT) continue;
        if (ps == i) [self.pending removeObjectForKey:bid];
        else if (ps > i) self.pending[bid] = @[@(ps - 1), v[1]];
    }
    if (self.focusedSlot > i) self.focusedSlot--;
    if (self.focusedSlot >= [self paneCount]) self.focusedSlot = MAX(0, [self paneCount] - 1);
    [self reindexPanes];
    [self rebuildDividers];
}

// Doi bo cuc khi dang chia: giu app theo thu tu o; nhieu o hon -> o moi hien bang chon,
// it o hon -> app o cac o cuoi ve nen
- (void)switchToLayout:(int)layoutID
{
    int n = SCPCPanesForLayout(layoutID);
    NSInteger kind = SCPCKindForLayout(layoutID);
    if (n == [self paneCount] && kind == self.layoutKind) return;
    SCPLog("CarSplit: doi bo cuc %d -> %d", [self layoutID], layoutID);
    // Bot o: bo o trong truoc, roi o cuoi (de doan; app chinh nhu ban do thuong o o 1 va it khi duoc cham nen khong
    // dua theo lan cham), va bao app nao ve nen
    NSMutableArray *dropped = [NSMutableArray array];
    while ([self paneCount] > n) {
        SCPCarPane *drop = nil;
        for (SCPCarPane *q in self.slots) {
            BOOL waiting = NO;
            for (NSString *b in self.pending) if ([self pendingSlotForBundle:b] == q.slot) waiting = YES;
            if (!q.vc && !waiting) { drop = q; break; }
        }
        if (!drop)   // o cuoi, tru o ghim
            for (SCPCarPane *q in [self.slots reverseObjectEnumerator]) if (![self slotIsPinned:q.slot]) { drop = q; break; }
        if (!drop) drop = self.slots.lastObject;
        if (drop.bundleID) [dropped addObject:[self displayNameFor:drop.bundleID]];
        [self removePaneAt:drop.slot background:YES];
    }
    if (dropped.count) [self toast:[NSString stringWithFormat:SCPCT(@"%@ về nền", @"%@ moved to the background"),
                                    [dropped componentsJoinedByString:@", "]]];
    [self setPaneCount:n];
    self.layoutKind = kind;
    [self resetFractions];
    [self rebuildDividers];
    [self showPickersForEmptySlots];
    [self relayoutAnimated:YES];
}

// Hien bang chon app o moi o con trong
- (void)showPickersForEmptySlots
{
    for (int s = 0; s < [self paneCount]; s++) if (![self slotOccupied:s]) [self showPickerForSlot:s];
}

// Container nam tren app/home cua DashBoard nhung duoi Siri (stackedContainerView)
- (void)raise
{
    UIView *parent = self.container.superview;
    if (!parent) return;
    [parent bringSubviewToFront:self.container];
    UIView *stacked = objcInvoke(SCPCRootVC(), @"stackedContainerView");
    if (stacked.superview == parent) [parent insertSubview:self.container belowSubview:stacked];
}

// Man xe dang "ban" (bong bong toc do tam an): dang chia man hoac bang bo cuc dang mo (bang chon app chi co khi dang chia)
- (void)publishBusy
{
    SCPCPublishBusy(self.active || self.tray != nil);
}

- (void)rootDidLayout
{
    [self publishBusy];
    if (!self.active) { [self refreshAppTab]; return; }
    if (!self.container.superview) return;
    [self refreshHomeButton];   // nut Split Screen tren dock van hien khi dang chia (doi bo cuc)
    CGRect f = [self appAreaInParent:self.container.superview];
    if (!CGRectEqualToRect(f, self.container.frame)) {
        SCPLog("CarSplit: vung app doi %@ -> %@", NSStringFromCGRect(self.container.frame), NSStringFromCGRect(f));
        self.container.frame = f;
        [self relayoutAnimated:NO];
    }
}

- (BOOL)activate
{
    return [self activateWithCount:2];
}

// Bat split theo ma bo cuc (2 / 3 / 13 / 31)
- (BOOL)activateWithLayout:(int)layoutID
{
    if (self.active) { [self switchToLayout:layoutID]; return YES; }
    if (![self activateWithCount:SCPCPanesForLayout(layoutID)]) return NO;
    if (SCPCIsStackLayout(layoutID)) {
        self.layoutKind = SCPCKindForLayout(layoutID);
        [self resetFractions];
        [self rebuildDividers];
        [self relayoutAnimated:NO];
    }
    return YES;
}

// Bat split voi n o (dang bat thi giu bo cuc hien tai)
- (BOOL)activateWithCount:(int)n
{
    if (![SCPPrefs enabled]) return NO;
    [self removeAppTab];
    if (self.active && self.container.superview) { [self raise]; return YES; }
    UIViewController *root = SCPCRootVC();
    UIViewController *cur = objcInvoke(root, @"currentBaseViewController");
    // App dang mo toan man: KHONG nhet VC cua no vao ngan tai cho (DashBoard van tuong app dang toan man
    // -> scene khong doi kich thuoc, nut Home ve man chinh bi ket). Ve Home truoc roi mo lai app do vao
    // ngan trai qua duong mo app binh thuong.
    NSString *reopen = (!self.suppressReopen && cur && [self isAdoptableViewController:cur])
        ? SCPRealBundleForInfos(objcInvoke(cur, @"applicationInfo"), objcInvoke(cur, @"proxyApplicationInfo")) : nil;
    if (self.soloHostedBundle) {   // app iPhone dang toan man qua App Bridge -> vao o 1
        if (!reopen && !self.suppressReopen) reopen = self.soloHostedBundle;
        [self endHostedSolo];
    }
    if (cur) {
        SCPLog("CarSplit: dang mo %@ toan man -> ve man chinh truoc%@", cur, reopen ? [NSString stringWithFormat:@", mo lai %@ vao ngan trai", reopen] : @"");
        SCPCSendEvent(1, @"SplitScreen: mo split");
        [self dismissStuckBaseSoon];
        self.nextLaunchAt = CFAbsoluteTimeGetCurrent() + SCPC_HOME_SETTLE;   // cho DashBoard ve Home xong
    }
    if (![self ensureContainer]) return NO;
    self.active = YES;
    self.focusedSlot = 0;
    [self publishBusy];
    [self.pending removeAllObjects];
    self.layoutKind = SCPCLayoutColumns;
    [self setPaneCount:n];   // moi lan chia luon bat dau chia deu (keo vach chia van doi duoc)
    SCPLog("CarSplit: bat split CarPlay (%d o)", [self paneCount]);
    [self showTipSoon];

    [self relayoutAnimated:NO];
    self.container.alpha = 0;
    self.container.transform = CGAffineTransformMakeScale(0.97, 0.97);
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.3 options:0
                     animations:^{ self.container.alpha = 1; self.container.transform = CGAffineTransformIdentity; } completion:nil];
    if (reopen) [self openApp:reopen slot:0];
    return YES;
}

// ---------------------------------------------------------------------
//  Mo app
// ---------------------------------------------------------------------
- (void)openApp:(NSString *)bid slot:(int)slot
{
    if (!bid.length) return;
    if (![self isCarPlayApp:bid]) {
        SCPLog("CarSplit: %@ khong co giao dien CarPlay -> bo qua", bid);
        [self toast:SCPCT(@"App này không hỗ trợ CarPlay", @"This app doesn't support CarPlay")];
        return;
    }
    BOOL wasActive = self.active;
    if (![self activate]) return;
    [self purgePending];
    BOOL autoSlotRequested = ![self validSlot:slot];
    SCPCarPane *existing = [self paneForBundle:bid];
    if (autoSlotRequested) slot = existing ? existing.slot : [self autoSlot];
    if (!existing && slot != SCPC_FLOAT_SLOT && [self slotIsPinned:slot]) {   // o ghim giu nguyen app cua no
        int other = [self autoSlot];
        if ([self slotIsPinned:other]) { [self toast:SCPCT(@"Ô này đang ghim", @"This pane is pinned")]; return; }
        SCPLog("CarSplit: o %d dang ghim -> mo %@ vao o %d", slot, bid, other);
        slot = other;
    }
    // App dang o cua so noi ma chon cho o chia (hoac nguoc lai): khong doi cho giua 2 loai o
    if (existing && existing.slot != slot && (existing.slot == SCPC_FLOAT_SLOT || slot == SCPC_FLOAT_SLOT)) {
        [self toast:[NSString stringWithFormat:SCPCT(@"%@ đang mở ở %@", @"%@ is already open in %@"), [self displayNameFor:bid],
                     existing.slot == SCPC_FLOAT_SLOT ? SCPCT(@"cửa sổ nổi", @"the floating window") : SCPCT(@"ô khác", @"another pane")]];
        return;
    }

    SCPCarPane *target = [self paneAtSlot:slot];
    if (!target) return;
    [self removePickerFromPane:target];

    if (existing) {
        if (existing.slot != slot) [self swapSlot:existing.slot with:slot];
        if (!wasActive && autoSlotRequested) [self showPickersForEmptySlots];
        [self relayoutAnimated:YES];
        if (SCPCIsHostedVC(target.vc)) [self sendHostFrameForPane:target live:NO];   // chon lai app iPhone dang o o: gui lai khung
        return;
    }

    // Dang cho chinh app nay vao dung ngan nay (vd activate vua mo lai app toan man) -> khong mo lan nua
    if ([self pendingSlotForBundle:bid] == slot) { [self relayoutAnimated:YES]; return; }

    // App iPhone: SpringBoard host (App Bridge), khong qua DashBoard
    if (SCPCIsBridgedApp(bid)) {
        [self hostApp:bid inPane:target];
        if (!wasActive && autoSlotRequested) [self showPickersForEmptySlots];
        return;
    }

    self.pending[bid] = @[@(slot), [NSDate date]];
    [self showLoaderInPane:target bundle:bid];   // app mo cham (CarBridge 2-6s) -> co hieu ung, khong thay dung hinh
    // Vua mo split tu 1 app: cac o con lai hien bang chon app CarPlay.
    // Dat bang chon TRUOC khi DashBoard tao scene de scene nhan ngay kich thuoc o.
    if (!wasActive && autoSlotRequested) [self showPickersForEmptySlots];
    [self relayoutAnimated:YES];

    id info = SCPCAppInfo(bid);
    id launchInfo = OMCCarLaunchInfo(info);
    // Gian cach cac lan mo: DashBoard phai xong phien doi workspace cua lan truoc (va lan ve Home)
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double delay = MAX(0, self.nextLaunchAt - now);
    self.nextLaunchAt = now + delay + SCPC_LAUNCH_GAP;
    SCPLog("CarSplit: mo %@ vao ngan %d sau %.1fs (launchInfo=%@)", bid, slot, delay, launchInfo);
    if (!launchInfo) {
        [self launchFailed:bid slot:slot];
        [self toast:[NSString stringWithFormat:SCPCT(@"Không mở được %@ trong ô", @"Couldn't open %@ in the pane"), [self displayNameFor:bid]]];
        return;
    }
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(delay, ^{
        SCPCarSplit *me = weakSelf;
        if (!me.active || [me pendingSlotForBundle:bid] < 0) return;
        SCPCSendEvent(4, launchInfo);
        // App da la app chinh cua workspace (khong nam trong ngan) -> DashBoard khong trinh bay lai -> tu lay VC
        SCPCAfter(2.0, ^{
            [weakSelf recoverPending:bid attempt:1];
        });
    });
}

// App mo cham (TikTok, YouTube qua tweak CarPlay khac mat ~4s): thu lai o giay 2, 4, 6 roi moi bao loi
- (void)recoverPending:(NSString *)bid attempt:(int)attempt
{
    if (!self.active || [self pendingSlotForBundle:bid] < 0) return;
    id owner = objcInvoke(SCPCDashboard(), @"workspaceOwner");
    NSDictionary *map = nil;
    @try { map = [owner valueForKey:@"_entityIdentifierToViewControllerMap"]; } @catch (NSException *e) {}
    NSArray *vcs = [map isKindOfClass:[NSDictionary class]] ? map.allValues : @[];
    for (id vc in vcs) {
        if (![self wantsViewController:vc]) continue;
        NSString *b = SCPRealBundleForInfos(objcInvoke(vc, @"applicationInfo"), objcInvoke(vc, @"proxyApplicationInfo"));
        if (![b isEqualToString:bid]) continue;
        SCPLog("CarSplit: DashBoard khong trinh bay %@ -> lay VC co san", bid);
        [self adoptViewController:vc];
        return;
    }
    if (attempt < 3) {
        SCPLog("CarSplit: %@ chua toi sau %ds, doi them", bid, attempt * 2);
        __weak SCPCarSplit *weakSelf = self;
        SCPCAfter(2.0, ^{
            [weakSelf recoverPending:bid attempt:attempt + 1];
        });
        return;
    }
    // Ghi lai cac VC DashBoard dang giu de biet vi sao app (vd YouTube qua tweak CarPlay khac) khong vao ngan
    NSMutableArray *seen = [NSMutableArray array];
    for (id vc in vcs) {
        id info = [vc respondsToSelector:NSSelectorFromString(@"applicationInfo")] ? objcInvoke(vc, @"applicationInfo") : nil;
        NSString *b = info ? SCPRealBundleForInfos(info, [vc respondsToSelector:NSSelectorFromString(@"proxyApplicationInfo")] ? objcInvoke(vc, @"proxyApplicationInfo") : nil) : nil;
        [seen addObject:[NSString stringWithFormat:@"%@(%@ fullScreen=%d)", NSStringFromClass([vc class]), b ?: @"?", SCPCBool(info, @"presentsFullScreen")]];
    }
    SCPLog("CarSplit: khong tim thay VC cua %@ sau khi mo; DashBoard dang giu: %@", bid, [seen componentsJoinedByString:@", "]);
    [self toast:[NSString stringWithFormat:SCPCT(@"Không mở được %@ trong ô", @"Couldn't open %@ in the pane"), [self displayNameFor:bid]]];
    [self launchFailed:bid slot:[self pendingSlotForBundle:bid]];
}

// Mo app vao o that bai: bo cho, bo the "dang mo"; o con trong thi hien lai bang chon app
- (void)launchFailed:(NSString *)bid slot:(int)slot
{
    [self.pending removeObjectForKey:bid];
    for (SCPCarPane *p in [self allPanes]) {   // cho da het han (slot -1) van tim duoc o qua the "dang mo"
        if (p.slot != slot && ![p.loader.accessibilityIdentifier isEqualToString:bid]) continue;
        [self removeLoaderFromPane:p animated:YES];
        if (!p.vc && ![self slotOccupied:p.slot]) [self showPickerForSlot:p.slot];
    }
    [self relayoutAnimated:YES];
}

// SpringBoard tat han app sau khi DashBoard dong xong ngan cua no
- (void)killAppSoon:(NSString *)bid
{
    if (!bid.length) return;
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(0.6, ^{
        SCPCarSplit *me = weakSelf;
        // Trong 0.6s nguoi dung vua mo lai chinh app nay -> khong tat
        if (me.active && ([me paneForBundle:bid] || [me pendingSlotForBundle:bid] >= 0)) { SCPLog("CarSplit: %@ vua mo lai -> khong tat", bid); return; }
        SCPLog("CarSplit: tat han %@", bid);
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
            postNotificationName:SPL_NOTIF_KILL object:nil userInfo:@{@"identifier": bid}];
    });
}

- (void)openPairLeft:(NSString *)left right:(NSString *)right
{
    SCPLog("CarSplit: mo cap left=%@ right=%@", left, right);
    if (self.active) [self setPaneCount:2];
    else if (![self activateWithCount:2]) return;
    CGFloat saved = (left && right) ? [SCPPrefs ratioForPairLeft:left right:right] : 0;
    if (saved >= 0.2 && saved <= 0.8) self.fractions = [NSMutableArray arrayWithObjects:@(saved), @(1 - saved), nil];
    [self openAppsInOrder:@[left ?: [NSNull null], right ?: [NSNull null]]];
}

// Mo lan luot cac app vao o 0, 1, ... (NSNull = de trong, hien bang chon). Cach nhau de DashBoard xong
// phien doi workspace cua app truoc.
- (void)openAppsInOrder:(NSArray *)apps
{
    double delay = 0;
    for (int s = 0; s < [self paneCount]; s++) {
        NSString *bid = (s < (int)apps.count && [apps[s] isKindOfClass:[NSString class]]) ? apps[s] : nil;
        if (!bid) { [self showPickerForSlot:s]; continue; }
        if (delay <= 0) { [self openApp:bid slot:s]; delay = 1.2; continue; }
        __weak SCPCarSplit *weakSelf = self;
        int slot = s;
        self.pending[bid] = @[@(slot), [NSDate date]];   // giu cho o nay (khong hien bang chon) trong luc doi
        [self showLoaderInPane:self.slots[s] bundle:bid];
        SCPCAfter(delay, ^{
            SCPCarSplit *me = weakSelf;
            if (!me.active || slot >= [me paneCount]) return;
            [me.pending removeObjectForKey:bid];
            [me openApp:bid slot:slot];
        });
        delay += 1.2;
    }
    [self relayoutAnimated:YES];
}

// ---------------------------------------------------------------------
//  Nhan VC tu DashBoard
// ---------------------------------------------------------------------
- (BOOL)wantsViewController:(UIViewController *)vc
{
    return self.active && [self isAdoptableViewController:vc];
}

- (BOOL)isAdoptableViewController:(UIViewController *)vc
{
    Class cls = OMCCarClass("DBApplicationSceneViewController");
    if (!cls || ![vc isKindOfClass:cls]) return NO;
    id info = objcInvoke(vc, @"applicationInfo");
    if (SCPCBool(info, @"presentsFullScreen")) return NO;
    return SCPRealBundleForInfos(info, objcInvoke(vc, @"proxyApplicationInfo")) != nil;
}

- (void)adoptViewController:(UIViewController *)vc
{
    NSString *bid = SCPRealBundleForInfos(objcInvoke(vc, @"applicationInfo"), objcInvoke(vc, @"proxyApplicationInfo"));
    int slot = [self pendingSlotForBundle:bid];
    SCPCarPane *existing = nil;
    for (SCPCarPane *p in [self allPanes]) if ([p.bundleID isEqualToString:bid]) existing = p;
    // App vua bi huy luc dang mo (nut x tren the "dang mo") ma DashBoard van trinh bay -> dua ve nen, khong vao o
    NSDate *cancelled = bid ? self.cancelledLaunches[bid] : nil;
    if (cancelled) [self.cancelledLaunches removeObjectForKey:bid];
    if (cancelled && slot < 0 && !existing && [[NSDate date] timeIntervalSinceDate:cancelled] < 30) {
        SCPLog("CarSplit: %@ da bi huy luc dang mo -> dua ve nen", bid);
        [self detachVC:vc background:YES];
        return;
    }
    BOOL fromCarPlay = (slot < 0 && !existing);
    if (![self validSlot:slot]) slot = existing ? existing.slot : [self autoSlot];
    if (bid) [self.pending removeObjectForKey:bid];
    SCPCarPane *tp = [self paneAtSlot:slot];
    if (fromCarPlay && tp.vc && tp.bundleID && ![tp.bundleID isEqualToString:bid]) {   // cham app tren dock khi dang chia
        [self toast:[NSString stringWithFormat:SCPCT(@"%@ thay %@ ở ô %d", @"%@ replaced %@ in pane %d"),
                     [self displayNameFor:bid], [self displayNameFor:tp.bundleID], slot + 1]];
    }
    [self adopt:vc slot:slot];
}

- (void)adopt:(UIViewController *)vc slot:(int)slot
{
    SCPCarPane *p = [self paneAtSlot:slot];
    if (!p) { SCPLog("CarSplit: bo qua dua VC vao o %d (chi co %d o)", slot, [self paneCount]); return; }
    NSString *bid = SCPRealBundleForInfos(objcInvoke(vc, @"applicationInfo"), objcInvoke(vc, @"proxyApplicationInfo"));
    [self removePickerFromPane:p];
    if (p.vc == vc) { [self relayoutAnimated:YES]; return; }

    // Cung app dang nam o o khac (VC cu) -> go VC cu (khong background vi van la scene do), o do chon app khac
    SCPCarPane *vacated = nil;
    for (SCPCarPane *other in [self allPanes]) {
        if (other == p || !other.vc || ![other.bundleID isEqualToString:bid]) continue;
        [self detachVC:other.vc background:NO];
        other.vc = nil; other.bundleID = nil; other.sceneSize = CGSizeZero;
        vacated = other;
    }
    NSString *oldBid = p.vc ? p.bundleID : nil;
    BOOL oldHosted = SCPCIsHostedVC(p.vc);
    if (p.vc) [self detachVC:p.vc background:![p.bundleID isEqualToString:bid]];
    if (oldHosted && oldBid) [self hostClose:oldBid terminate:NO];   // app iPhone dang o o nay -> SpringBoard bo o

    UIViewController *root = SCPCRootVC();
    BOOL moved = NO;
    if (vc.parentViewController != root) {
        if (vc.parentViewController) { [vc willMoveToParentViewController:nil]; [vc removeFromParentViewController]; }
        [root addChildViewController:vc];
        moved = YES;
    }
    [vc.view removeFromSuperview];
    vc.view.hidden = NO;
    vc.view.alpha = 1;
    vc.view.transform = CGAffineTransformIdentity;
    vc.view.frame = p.host.bounds;
    vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [p.host addSubview:vc.view];
    if (moved) [vc didMoveToParentViewController:root];
    vc.additionalSafeAreaInsets = UIEdgeInsetsZero;

    p.vc = vc; p.bundleID = bid; p.sceneSize = CGSizeZero;
    if (slot != SCPC_FLOAT_SLOT) self.focusedSlot = slot;
    [self removeLoaderFromPane:p animated:YES];   // app da vao ngan: bo the "dang mo"
    SCPLog("CarSplit: dua %@ (%@) vao o %d", bid, NSStringFromClass([vc class]), slot);
    [self rememberPair];
    [self rememberRecent];
    [self raise];
    if (vacated) [self showPickerForSlot:vacated.slot];
    [self relayoutAnimated:YES];
}

// Day scene vao nen ngoai luong cua DashBoard lam no an view cua app (hidden / alpha 0). Lan sau mo app,
// DashBoard dung lai dung VC do ma khong hien lai -> app len man den, cham khong vao. Tra view (va chuoi
// view trinh bay scene ben duoi) ve trang thai hien. Tra ve YES neu co sua.
static BOOL SCPCRevealSceneView(UIView *v, int depth)
{
    if (!v || depth > 4) return NO;
    BOOL fixed = NO;
    if (v.hidden) { v.hidden = NO; fixed = YES; }
    if (v.alpha < 0.99) { v.alpha = 1; fixed = YES; }
    for (UIView *c in v.subviews) {
        NSString *cls = NSStringFromClass([c class]);
        if ([cls hasPrefix:@"_UIScene"] || [cls hasPrefix:@"_UITouchPassthrough"]) {
            if (SCPCRevealSceneView(c, depth + 1)) fixed = YES;
        }
    }
    return fixed;
}

- (void)repairPresentedViewController:(UIViewController *)vc
{
    if (![vc isKindOfClass:[UIViewController class]] || !vc.isViewLoaded) return;
    for (SCPCarPane *p in [self allPanes]) if (p.vc == vc) return;   // dang nam trong ngan, split tu lo
    if (SCPCRevealSceneView(vc.view, 0)) {
        vc.view.transform = CGAffineTransformIdentity;
        SCPLog("CarSplit: app toan man %@ bi an (con sot tu split) -> hien lai",
               SCPRealBundleForInfos(objcInvoke(vc, @"applicationInfo"), objcInvoke(vc, @"proxyApplicationInfo")));
    }
}

// Moi o deu da co app -> nho cach chia nay vao "Gan day"
- (void)rememberRecent
{
    if ([self paneCount] < 2) return;   // 1 o + cua so noi khong phai 1 cach chia
    NSMutableArray *apps = [NSMutableArray array];
    for (SCPCarPane *p in self.slots) {
        if (!p.vc || !p.bundleID || p.picker) return;
        [apps addObject:p.bundleID];
    }
    [SCPPrefs addRecentLayout:[self layoutID] apps:apps];
}

// Ca 2 ngan deu co app -> nho cap nay (tu mo lai khi cam xe / nut mo split)
- (void)rememberPair
{
    if ([self paneCount] != 2) return;
    NSString *l = self.slots[0].bundleID, *r = self.slots[1].bundleID;
    if (l && r) [SCPPrefs setLastPairLeft:l right:r];
}

- (void)detachVC:(UIViewController *)vc background:(BOOL)background
{
    if (!vc) return;
    if (background) {
        self.allowBackground++;
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(vc, NSSelectorFromString(@"backgroundSceneWithCompletion:"), ^{});
        } @catch (NSException *e) { SCPLog("CarSplit: background loi %@", e); }
        self.allowBackground--;
    }
    [vc willMoveToParentViewController:nil];
    [vc.view removeFromSuperview];
    [vc removeFromParentViewController];
    // Tra VC cho DashBoard o trang thai binh thuong de lan sau no mo toan man duoc
    SCPCRevealSceneView(vc.view, 0);
    vc.view.transform = CGAffineTransformIdentity;
}

- (BOOL)protectsViewController:(id)vc
{
    if (!self.active || self.allowBackground > 0) return NO;
    for (SCPCarPane *p in [self allPanes]) if (p.vc == vc) return YES;
    return NO;
}

static id SCPCSceneOf(UIViewController *vc);

- (id)sceneOfViewController:(id)vc
{
    return [vc isKindOfClass:[UIViewController class]] ? SCPCSceneOf(vc) : nil;
}

static NSString *SCPCSceneID(id scene)
{
    @try { return [scene respondsToSelector:NSSelectorFromString(@"identifier")] ? objcInvoke(scene, @"identifier") : nil; }
    @catch (NSException *e) { return nil; }
}

// DashBoard bao didDestroyScene cho MOI VC dang nghe, ke ca scene cua app khac (vd mo GOFA huy scene cu
// cua no -> ca 2 ngan bi dong) -> chi dong ngan khi dung la scene cua VC trong ngan.
- (void)scene:(id)scene destroyedForViewController:(id)vc ownScene:(id)own
{
    for (SCPCarPane *p in [self allPanes]) {
        if (p.vc != vc) continue;
        NSString *sid = SCPCSceneID(scene), *oid = SCPCSceneID(own);
        BOOL mine = own && (own == scene || (sid && [sid isEqualToString:oid]));
        if (!mine) {
            SCPLog("CarSplit: scene %@ bi huy khong phai cua %@ (%@) -> giu ngan %d", sid ?: scene, p.bundleID, oid ?: @"?", p.slot);
            continue;
        }
        SCPLog("CarSplit: scene cua %@ bi huy (app thoat/crash) -> dong ngan %d", p.bundleID, p.slot);
        __weak SCPCarPane *weakPane = p;
        SCPCAfter(0, ^{
            SCPCarPane *pp = weakPane;
            if (pp && pp.vc == vc && [[self allPanes] containsObject:pp]) [self closeSlot:pp.slot background:NO];
        });
    }
}

- (BOOL)paneSize:(CGSize *)outSize forBundle:(NSString *)bid
{
    if (!self.active || !bid || !self.container) return NO;
    SCPCarPane *p = [self paneForBundle:bid];
    int slot = p ? p.slot : [self pendingSlotForBundle:bid];
    if (slot < 0) return NO;
    CGSize s = [self frameForSlot:slot].size;
    if (s.width < 2 || s.height < 2) return NO;
    if (outSize) *outSize = s;
    return YES;
}

// ---------------------------------------------------------------------
//  Bo cuc
// ---------------------------------------------------------------------
- (void)relayoutAnimated:(BOOL)animated
{
    [self relayoutAnimated:animated pushScenes:YES];
}

- (void)relayoutAnimated:(BOOL)animated pushScenes:(BOOL)push
{
    if (!self.container) return;
    if (self.pickerSheet) [self refreshPickerSheetSoon];   // o doi cho / bi bo / vung app doi -> bang chon app ve lai neu can
    if (self.zoomedSlot) {   // o phong to da dong / doi bo cuc -> ve binh thuong
        int z = self.zoomedSlot.intValue;
        SCPCarPane *zp = (z >= 0 && z < (int)self.slots.count) ? self.slots[z] : nil;
        if (!self.active || [self paneCount] < 2 || z >= [self paneCount] || !zp.vc) {
            SCPLog("CarSplit: bo phong to o %d", z);
            self.zoomedSlot = nil;
        }
    }
    BOOL showDividers = [self dividersVisible];
    if (self.floatPane) [self fitFloatFrame];
    SCPCarPane *fp = self.floatPane;
    NSNumber *zoomed = self.zoomedSlot;
    void (^changes)(void) = ^{
        for (SCPCarPane *p in self.slots) {
            CGRect f = [self frameForSlot:p.slot];
            BOOL visible = f.size.width > 1 && f.size.height > 1 && (!zoomed || zoomed.intValue == p.slot);
            p.view.frame = f;
            p.view.alpha = visible ? 1 : 0;
            p.view.layer.cornerRadius = [self innerCornersForSlot:p.slot] ? SCPC_RADIUS : 0;
            p.view.layer.maskedCorners = [self innerCornersForSlot:p.slot];
            p.host.frame = p.view.bounds;
            p.picker.frame = p.view.bounds;
            [self layoutBarForPane:p];
        }
        for (SCPCarDividerView *d in self.dividers) {
            d.frame = [self dividerFrameAt:d.index];
            d.alpha = showDividers ? 1 : 0;
            [self layoutKnobOf:d];
        }
        // 1 lon + 2: vach 1 nam sat tay nam tron cua vach 0 -> dua vach 0 len tren cung, neu khong cham vao
        // nua tay nam se roi vao vach 1 va chi keo duoc 1 chieu
        if ([self mainStack] && self.dividers.count) [self.container bringSubviewToFront:self.dividers[0]];
        if (fp) {   // cua so noi: bo du 4 goc, nam tren cac o va vach chia
            fp.view.frame = self.floatFrame;
            fp.view.alpha = 1;
            fp.view.layer.cornerRadius = SCPC_RADIUS;
            fp.view.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            fp.host.frame = fp.view.bounds;
            fp.picker.frame = fp.view.bounds;
            [self layoutBarForPane:fp];
            [self.container bringSubviewToFront:fp.view];
        }
        if (zoomed && zoomed.intValue < (int)self.slots.count) [self.container bringSubviewToFront:self.slots[zoomed.intValue].view];
        if (fp) [self.container bringSubviewToFront:fp.view];
        if (self.dragGhost) [self.container bringSubviewToFront:self.dragGhost];
        if (self.ratioMenu.superview == self.container) [self.container bringSubviewToFront:self.ratioMenu];
    };
    if (animated) {
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes completion:nil];
    } else {
        changes();
    }
    for (SCPCarPane *p in self.slots) p.view.userInteractionEnabled = (p.view.alpha > 0);
    fp.view.userInteractionEnabled = YES;
    for (SCPCarDividerView *d in self.dividers) d.userInteractionEnabled = showDividers;
    if (push) [self pushSceneSizes];
    [self pushHostFramesLive:!push];   // cua so host (App Bridge) theo khung o moi; dang keo vach thi chi di theo tay
}

// FBScene cua 1 DBApplicationSceneViewController (thu vai ten thuoc tinh), nil neu khong lay duoc
static id SCPCSceneOf(UIViewController *vc)
{
    for (NSString *k in @[@"scene", @"_scene"]) {
        @try { id s = [vc valueForKey:k]; if (s) return s; } @catch (NSException *e) {}
    }
    @try {
        id h = [vc valueForKey:@"sceneHandle"];
        id s = h ? [h valueForKey:@"scene"] : nil;
        if (s) return s;
    } @catch (NSException *e) {}
    return nil;
}

// Kich thuoc scene dang dung (settings.frame); CGSizeZero neu khong doc duoc
static CGSize SCPCSceneSize(UIViewController *vc)
{
    id scene = SCPCSceneOf(vc);
    id st = nil;
    @try { st = [scene respondsToSelector:NSSelectorFromString(@"settings")] ? objcInvoke(scene, @"settings") : nil; } @catch (NSException *e) {}
    if (![st respondsToSelector:NSSelectorFromString(@"frame")]) return CGSizeZero;
    return ((CGRect (*)(id, SEL))objc_msgSend)(st, NSSelectorFromString(@"frame")).size;
}

// Bao kich thuoc moi cho scene cua tung ngan: DashBoard tao DBSceneUpdate, lay frame qua hook sceneFrameForAppInfo
- (void)pushSceneSizes
{
    for (SCPCarPane *p in [self allPanes]) {
        if (!p.vc || SCPCIsHostedVC(p.vc)) continue;   // app iPhone: SpringBoard tu doi kich thuoc scene theo khung gui
        CGSize s = [self frameForSlot:p.slot].size;
        if (s.width < 2 || s.height < 2 || CGSizeEqualToSize(s, p.sceneSize)) continue;
        p.sceneSize = s;
        SCPLog("CarSplit: scene %@ -> %@", p.bundleID, NSStringFromCGSize(s));
        @try {
            ((void (*)(id, SEL, id, id))objc_msgSend)(p.vc, NSSelectorFromString(@"foregroundSceneWithSettings:completion:"), nil, ^{});
        } @catch (NSException *e) { SCPLog("CarSplit: foregroundScene loi %@", e); }
        UIViewController *vc = p.vc;
        __weak SCPCarSplit *weakSelf = self;
        SCPCAfter(0.4, ^{
            UIView *h = nil;
            @try { h = objcInvoke(vc, @"sceneHostView"); } @catch (NSException *e) {}
            if (h && h.superview == vc.view && !CGRectEqualToRect(h.frame, vc.view.bounds)) {
                SCPLog("CarSplit: sceneHostView %@ -> %@", NSStringFromCGRect(h.frame), NSStringFromCGRect(vc.view.bounds));
                h.frame = vc.view.bounds;
            }
        });
        // Kiem tra scene da doi kich thuoc that chua; chua thi dua scene ve nen roi len lai 1 lan
        SCPCAfter(0.9, ^{
            [weakSelf verifySceneOfPane:p expected:s retry:YES];
        });
    }
}

- (void)verifySceneOfPane:(SCPCarPane *)p expected:(CGSize)s retry:(BOOL)retry
{
    if (!self.active || !p.vc || !CGSizeEqualToSize(p.sceneSize, s)) return;   // da doi tiep / da dong
    CGSize cur = SCPCSceneSize(p.vc);
    if (CGSizeEqualToSize(cur, CGSizeZero)) { SCPLog("CarSplit: khong doc duoc kich thuoc scene %@", p.bundleID); return; }
    BOOL ok = (fabs(cur.width - s.width) < 2 && fabs(cur.height - s.height) < 2)
           || (fabs(cur.width - s.height) < 2 && fabs(cur.height - s.width) < 2);   // co the bi dao chieu
    SCPLog("CarSplit: scene %@ that = %@ (can %@)%@", p.bundleID, NSStringFromCGSize(cur), NSStringFromCGSize(s),
           ok ? @"" : (retry ? @" -> ve nen roi len lai" : @" -> van sai"));
    if (ok || !retry) return;
    UIViewController *vc = p.vc;
    self.allowBackground++;
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(vc, NSSelectorFromString(@"backgroundSceneWithCompletion:"), ^{});
    } @catch (NSException *e) { SCPLog("CarSplit: background loi %@", e); }
    self.allowBackground--;
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(0.25, ^{
        SCPCarSplit *me = weakSelf;
        if (!me.active || p.vc != vc) return;
        @try {
            ((void (*)(id, SEL, id, id))objc_msgSend)(vc, NSSelectorFromString(@"foregroundSceneWithSettings:completion:"), nil, ^{});
        } @catch (NSException *e) { SCPLog("CarSplit: foregroundScene loi %@", e); }
        SCPCAfter(0.8, ^{
            [weakSelf verifySceneOfPane:p expected:s retry:NO];
        });
    });
}

// Doi cho 2 o (o, ti le, app dang cho mo)
- (void)swapSlot:(int)a with:(int)b
{
    int n = [self paneCount];
    if (a == b || a < 0 || b < 0 || a >= n || b >= n) return;
    [self.slots exchangeObjectAtIndex:a withObjectAtIndex:b];
    if (self.focusedSlot == a) self.focusedSlot = b; else if (self.focusedSlot == b) self.focusedSlot = a;   // focus theo app
    if (![self mainStack] && (int)self.fractions.count == n) [self.fractions exchangeObjectAtIndex:a withObjectAtIndex:b];
    for (NSString *bid in self.pending.allKeys) {
        NSArray *v = self.pending[bid];
        int ps = [v[0] intValue];
        if (ps == a) self.pending[bid] = @[@(b), v[1]];
        else if (ps == b) self.pending[bid] = @[@(a), v[1]];
    }
    [self reindexPanes];
    SCPLog("CarSplit: doi cho o %d va %d", a, b);
    [self rememberPair];
    [self rememberRecent];
    [self relayoutAnimated:YES];
}

// ---------------------------------------------------------------------
//  Dong
// ---------------------------------------------------------------------
- (void)closeSlot:(int)slot background:(BOOL)background
{
    if (slot == SCPC_FLOAT_SLOT) { [self closeFloat:background]; return; }
    if (!self.active || slot < 0 || slot >= [self paneCount]) return;
    NSString *bid = self.slots[slot].bundleID;
    [self removePaneAt:slot background:background];
    SCPLog("CarSplit: dong o %d (%@), con %d o", slot, bid, [self paneCount]);
    [self afterPaneRemoved:bid];
}

// Sau khi bot 1 o: het o -> tat split; con 1 o -> app do ve toan man nhu luc chua chia; con lai -> chia lai
- (void)afterPaneRemoved:(NSString *)closedBid
{
    int n = [self paneCount];
    if (n == 0) {   // het o chia: cua so noi con app thi app do ve toan man
        NSString *fb = self.floatPane.vc ? self.floatPane.bundleID : nil;
        if (fb) [self soloBundle:fb]; else [self closeGoingHome:YES];
        return;
    }
    if (n == 1 && !self.floatPane) {   // con 1 o (khong co cua so noi) -> app do ve toan man
        NSString *keep = self.slots[0].bundleID;
        if (!keep) for (NSString *b in self.pending) if ([self pendingSlotForBundle:b] == 0) keep = b;
        if (keep) [self soloBundle:keep]; else [self closeGoingHome:YES];
        return;
    }
    [self relayoutAnimated:YES];

    // Workspace cua DashBoard van coi app vua dong la app chinh -> chuyen sang 1 app con lai cho khop
    NSString *activeBase = objcInvoke(objcInvoke(SCPCDashboard(), @"workspaceOwner"), @"activeBaseApplicationBundleID");
    SCPCarPane *other = nil;
    for (SCPCarPane *p in self.slots) if (p.vc && p.bundleID) { other = p; break; }
    // App iPhone (App Bridge) khong mo qua DashBoard: declaration gia lam DashBoard tao scene CarPlay den cho no,
    // split nhan scene do vao o va dong cua so host (log 10/10 15:43: YouTube "khong ve" trong o sau khi dong o khac)
    if (closedBid && other && [activeBase isEqualToString:closedBid] && !SCPCIsBridgedApp(other.bundleID)) {
        NSString *ob = other.bundleID;
        self.pending[ob] = @[@(other.slot), [NSDate date]];
        id launchInfo = OMCCarLaunchInfo(SCPCAppInfo(ob));
        if (launchInfo) SCPCSendEvent(4, launchInfo);
        SCPCAfter(2.0, ^{
            [self.pending removeObjectForKey:ob];
        });
    }
}

// Tat split, mo `bid` toan man nhu khi cham icon (ve Home truoc de DashBoard mo lai tu dau)
- (void)soloBundle:(NSString *)bid
{
    if (!self.active) return;
    if (!bid) { [self closeGoingHome:YES]; return; }
    if (SCPCIsBridgedApp(bid)) {   // app iPhone: App Bridge host o ca vung app, man chinh CarPlay van o duoi
        SCPLog("CarSplit: chi giu %@ (app iPhone) -> App Bridge toan man", bid);
        // Host toan man TRUOC (o dang host chi truot ra ca vung app), roi moi tat split: hostCloseAll giu app nay lai,
        // man chinh CarPlay ve ben duoi ma khong lo ra -> khong nhay ve Home
        [self hostSolo:bid];
        self.ignoreHomeOnce = YES;   // su kien Home ben duoi la cua minh, khong phai nguoi dung bam -> khong dong app
        [self closeGoingHome:YES];
        self.ignoreHomeOnce = NO;    // handleEvent dong bo; khong dung toi thi bo co
        return;
    }
    SCPLog("CarSplit: chi giu %@ -> mo toan man", bid);
    // VC cua app dang nam trong o: tra thang cho DashBoard trinh bay toan man (goi presentBaseViewController that, hook
    // cho qua vi split da tat), khong ve Home roi mo lai: workspace cua DashBoard van coi app nay la app dang mo (split
    // da chan lan trinh bay dau), nen "mo lai" sau Home bi bo qua -> chi thay man chinh (log 10/10 15:33, 16:xx)
    SCPCarPane *keepPane = nil;
    for (SCPCarPane *p in [self allPanes]) if (p.vc && [p.bundleID isEqualToString:bid] && !SCPCIsHostedVC(p.vc)) keepPane = p;
    UIViewController *keepVC = keepPane.vc;
    UIViewController *root = SCPCRootVC();
    SEL present = NSSelectorFromString(@"presentBaseViewController:animated:launchSource:completion:");
    if (keepVC && root && [root respondsToSelector:present]) {
        keepPane.vc = nil; keepPane.bundleID = nil;   // closeGoingHome khong detach / dua ve nen VC nay
        [self detachVC:keepVC background:NO];
        [self closeGoingHome:NO];
        ((void (*)(id, SEL, id, BOOL, unsigned long long, id))objc_msgSend)(root, present, keepVC, YES, 0, nil);
        self.soloReturnedVC = keepVC;
        SCPLog("CarSplit: tra %@ cho DashBoard trinh bay toan man", bid);
        // Scene van giu co o (DashBoard khong hoi lai kich thuoc cho scene da co): bao lai nhu luc doi co o
        // (foregroundSceneWithSettings: -> DashBoard lay frame qua hook sceneFrameForAppInfo, gio la ca man)
        SCPCAfter(0.15, ^{
            @try {
                ((void (*)(id, SEL, id, id))objc_msgSend)(keepVC, NSSelectorFromString(@"foregroundSceneWithSettings:completion:"), nil, ^{});
                SCPLog("CarSplit: scene %@ -> toan man %@", bid, NSStringFromCGSize(keepVC.view.bounds.size));
            } @catch (NSException *e) { SCPLog("CarSplit: foregroundScene toan man loi %@", e); }
        });
        SCPCAfter(0.6, ^{
            UIView *h = nil;
            @try { h = objcInvoke(keepVC, @"sceneHostView"); } @catch (NSException *e) {}
            if (h && h.superview == keepVC.view && !CGRectEqualToRect(h.frame, keepVC.view.bounds)) {
                SCPLog("CarSplit: sceneHostView %@ -> %@ (toan man)", NSStringFromCGRect(h.frame), NSStringFromCGRect(keepVC.view.bounds));
                h.frame = keepVC.view.bounds;
            }
        });
        return;
    }
    id launchInfo = OMCCarLaunchInfo(SCPCAppInfo(bid));
    if (launchInfo) [self showSoloCoverForBundle:bid];   // che man chinh nhay qua + app ve lai tu dau
    [self closeGoingHome:YES];
    if (!launchInfo) {
        [self toast:[NSString stringWithFormat:SCPCT(@"Không mở lại được %@", @"Couldn't reopen %@"), [self displayNameFor:bid]]];
        return;
    }
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(0.8, ^{
        SCPCarSplit *me = weakSelf;
        if (!me || me.active) return;
        // Mo lai nhu cham icon tren man chinh (_launchAppWithInfo:forURL:); su kien DBEvent 4 voi launchInfo lay truoc
        // khi ve Home khong mo duoc (log 10/10 15:33: "mo toan man" roi khong co gi)
        id d = SCPCDashboard();
        id info = SCPCAppInfo(bid);
        SCPLog("CarSplit: mo lai %@ toan man (dashboard=%d, info=%d)", bid, d != nil, info != nil);
        if (d && info && [d respondsToSelector:NSSelectorFromString(@"_launchAppWithInfo:forURL:")]) objcCall_2(d, @"_launchAppWithInfo:forURL:", info, (id)nil);
        else SCPCSendEvent(4, launchInfo);
    });
}

// ---------------------------------------------------------------------
//  Cua so noi (HyperOS "cua so nho"): 1 o rieng nam tren cac o chia. Mo tu bang nut Split Screen hoac nut
//  "dua ra cua so noi" tren thanh "•••" cua 1 o. Keo "•••" de di chuyen, tha ra hit sat canh trai / phai.
//  Khong nhan app CarBridge, va luon tranh o dang chieu CarBridge (CBWindow nam tren moi view CarPlay).
// ---------------------------------------------------------------------
- (SCPCarPane *)ensureFloatPane
{
    if (self.floatPane) return self.floatPane;
    if (!self.container) return nil;
    SCPCarPane *p = [self newPane];
    p.slot = SCPC_FLOAT_SLOT;
    p.view.layer.borderWidth = 1;
    p.view.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;   // cua so noi: vien kinh trang
    [self.container addSubview:p.view];
    self.floatPane = p;
    self.floatLarge = NO;
    CGSize c = self.container.bounds.size, fs = [self floatSizeLarge:NO];
    self.floatFrame = CGRectMake(c.width - fs.width - 8, c.height - fs.height - 8, fs.width, fs.height);
    [self fitFloatFrame];
    // Cham 2 lan "•••" cua cua so noi: doi co nho <-> lon (man CarPlay thuong chi cham 1 ngon, khong pinch duoc);
    // nhan dien cham dup gan san o setupBarForPane, handleDoubleTapped chuyen sang floatHandleDoubleTapped
    p.view.frame = self.floatFrame;
    p.host.frame = p.view.bounds;
    p.view.alpha = 0;
    p.view.transform = CGAffineTransformMakeScale(0.6, 0.6);
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0
                     animations:^{ p.view.alpha = 1; p.view.transform = CGAffineTransformIdentity; } completion:nil];
    SCPLog("CarSplit: mo cua so noi %@", NSStringFromCGRect(self.floatFrame));
    return p;
}

// Co cua so noi: nho ~30% x 45% vung app (khong che het o ben duoi), lon ~45% x 62%
- (CGSize)floatSizeLarge:(BOOL)large
{
    CGSize c = self.container.bounds.size;
    CGFloat w = large ? MIN(MAX(c.width * 0.45, 220), 360) : MIN(MAX(c.width * 0.3, 160), 240);
    CGFloat h = large ? MIN(MAX(c.height * 0.62, 130), 260) : MIN(MAX(c.height * 0.45, 96), 170);
    return CGSizeMake(MIN(w, c.width - 16), MIN(h, c.height - 16));
}

- (void)floatHandleDoubleTapped:(UITapGestureRecognizer *)g
{
    @try {
        SCPCarPane *fp = self.floatPane;
        if (!fp || !self.container) return;
        self.floatLarge = !self.floatLarge;
        CGSize ns = [self floatSizeLarge:self.floatLarge];
        CGRect f = self.floatFrame, c = self.container.bounds;
        BOOL right = CGRectGetMidX(f) > CGRectGetMidX(c), bottom = CGRectGetMidY(f) > CGRectGetMidY(c);
        f.origin.x = right ? CGRectGetMaxX(f) - ns.width : f.origin.x;   // giu nguyen goc dang bam canh
        f.origin.y = bottom ? CGRectGetMaxY(f) - ns.height : f.origin.y;
        f.size = ns;
        self.floatFrame = f;
        [self setBarVisible:NO forPane:fp];
        SCPLog("CarSplit: cua so noi %@ %@", self.floatLarge ? @"lon" : @"nho", NSStringFromCGSize(ns));
        [self relayoutAnimated:YES];   // scene cua so noi nhan kich thuoc moi
    } @catch (NSException *e) { SCPLog("CarSplit: loi doi co cua so noi %@", e); }
}

// Giu cua so noi gon trong vung app va khong de len o dang chieu CarBridge. Khong con cho -> hen dong.
- (void)fitFloatFrame
{
    SCPCarPane *fp = self.floatPane;
    if (!fp || !self.container) return;
    CGRect c = self.container.bounds, f = self.floatFrame;
    f.size.width = MIN(f.size.width, c.size.width - 16);
    f.size.height = MIN(f.size.height, c.size.height - 16);
    f.origin.x = MIN(MAX(f.origin.x, 8), c.size.width - f.size.width - 8);
    f.origin.y = MIN(MAX(f.origin.y, 8), c.size.height - f.size.height - 8);
    SCPCarPane *bp = [self bridgedPane];
    CGRect busy = bp ? [self frameForSlot:bp.slot] : CGRectNull;
    if (!bp || !CGRectIntersectsRect(f, busy)) self.floatClosing = NO;   // het bi che -> bo hen dong
    if (bp && CGRectIntersectsRect(f, busy)) {
        CGRect g = f;   // thu sang canh ben kia
        g.origin.x = (CGRectGetMidX(f) > CGRectGetMidX(c)) ? 8 : c.size.width - f.size.width - 8;
        if (!CGRectIntersectsRect(g, busy)) f = g;
        else if (!self.floatClosing) {
            self.floatClosing = YES;
            SCPLog("CarSplit: cua so noi bi %@ (CarBridge) che het cho -> dong", bp.bundleID);
            __weak SCPCarSplit *weakSelf = self;
            SCPCAfter(0, ^{
                SCPCarSplit *me = weakSelf;
                SCPCarPane *bpp = [me bridgedPane];
                if (!me.floatPane || !me.floatClosing || !bpp || !CGRectIntersectsRect(me.floatFrame, [me frameForSlot:bpp.slot])) {
                    me.floatClosing = NO;
                    return;
                }
                [me toast:[NSString stringWithFormat:SCPCT(@"Đóng cửa sổ nổi: %@ đang che hết chỗ", @"Floating window closed: %@ covers the screen"), [me displayNameFor:bpp.bundleID]]];
                [me closeFloat:YES];
            });
        }
    }
    self.floatFrame = f;
}

- (void)closeFloat:(BOOL)background
{
    SCPCarPane *fp = self.floatPane;
    if (!fp) return;
    NSString *bid = fp.bundleID;
    [fp.barTimer invalidate]; fp.barTimer = nil;
    [self removePickerFromPane:fp];
    [self removeLoaderFromPane:fp animated:NO];
    if (fp.vc) [self detachVC:fp.vc background:background];
    fp.vc = nil; fp.bundleID = nil;
    self.floatPane = nil;
    self.floatClosing = NO;
    self.floatReturnLayout = 0; self.floatReturnFractions = nil;
    for (NSString *b in self.pending.allKeys) if ([self.pending[b][0] intValue] == SCPC_FLOAT_SLOT) [self.pending removeObjectForKey:b];
    UIView *v = fp.view;
    [UIView animateWithDuration:0.2 animations:^{ v.alpha = 0; v.transform = CGAffineTransformMakeScale(0.8, 0.8); }
                     completion:^(BOOL f) { [v removeFromSuperview]; }];
    SCPLog("CarSplit: dong cua so noi (%@), con %d o", bid, [self paneCount]);
    if (!self.active) return;
    if ([self paneCount] <= 1) [self afterPaneRemoved:bid];   // con 1 o -> app do ve toan man
    else [self relayoutAnimated:YES];
}

// Nut "hinh trong hinh" tren thanh nut cua 1 o: dua app cua o do ra cua so noi.
// Chua co cua so noi -> bot 1 o (can con >= 2 o). Da co -> doi cho: app dang noi ve lai o nay.
// Ly do khong dua o nay ra hinh trong hinh duoc (nil = duoc). Hien thanh thong bao khi bam nut bi mo.
- (NSString *)popOutBlockReason:(SCPCarPane *)p
{
    if (!p || p == self.floatPane || !p.vc || !p.bundleID) return SCPCT(@"Ô chưa có app", @"This pane has no app");
    if (self.floatPane.vc) return nil;   // doi cho voi cua so noi
    if ([self paneCount] < 2) return SCPCT(@"Cần ít nhất 2 ô", @"Needs at least 2 panes");
    // App iPhone noi ra: cua so cua no duoc SpringBoard dua len tren cac o app iPhone khac (front) -> luon duoc
    if (SCPCIsBridgedApp(p.bundleID)) return nil;
    // Cac o con lai deu la app iPhone: cua so cua chung phu het vung app, cua so noi CarPlay khong con cho -> app vua dua ra se mat
    BOOL roomLeft = NO;
    for (SCPCarPane *o in self.slots) if (o != p && !(o.vc && SCPCIsBridgedApp(o.bundleID))) roomLeft = YES;
    if (!roomLeft) {
        NSString *other = nil;
        for (SCPCarPane *o in self.slots) if (o != p) other = o.bundleID;
        return [NSString stringWithFormat:SCPCT(@"%@ sẽ che mất cửa sổ nổi", @"%@ would cover the floating window"), [self displayNameFor:other]];
    }
    return nil;
}

- (BOOL)canPopOutPane:(SCPCarPane *)p { return [self popOutBlockReason:p] == nil; }

- (void)panePopOut:(UIButton *)b
{
    SCPCarPane *p = [self paneForView:b];
    if (p) [self popOutPane:p];
}

- (void)popOutPane:(SCPCarPane *)p
{
    @try {
        if (p == self.floatPane) { [self floatDockBack]; return; }   // nut cua cua so noi = dua ve o
        NSString *why = [self popOutBlockReason:p];
        if (why) { [self toast:why]; return; }
        [self setBarVisible:NO forPane:p];
        UIViewController *vc = p.vc;
        NSString *bid = p.bundleID;
        SCPCarPane *fp = self.floatPane;
        if (fp.vc) {   // doi cho: 2 app doi khung, scene cua ca 2 nhan kich thuoc moi
            UIViewController *fvc = fp.vc;
            NSString *fbid = fp.bundleID;
            [self removePickerFromPane:fp];
            [vc.view removeFromSuperview];
            [fvc.view removeFromSuperview];
            vc.view.frame = fp.host.bounds;  [fp.host addSubview:vc.view];
            fvc.view.frame = p.host.bounds;  [p.host addSubview:fvc.view];
            fp.vc = vc;  fp.bundleID = bid;  fp.sceneSize = CGSizeZero;
            p.vc = fvc;  p.bundleID = fbid;  p.sceneSize = CGSizeZero;
            SCPLog("CarSplit: hinh trong hinh doi cho %@ (o %d) <-> %@ (cua so noi)", bid, p.slot, fbid);
            [self rememberPair];
            [self rememberRecent];
            [self relayoutAnimated:YES];
            return;
        }
        self.floatReturnLayout = [self layoutID];
        self.floatReturnSlot = p.slot;
        self.floatReturnFractions = [self.fractions copy];
        fp = [self ensureFloatPane];
        if (!fp) return;
        [self removePickerFromPane:fp];
        [vc.view removeFromSuperview];
        vc.view.frame = fp.host.bounds;
        [fp.host addSubview:vc.view];
        fp.vc = vc; fp.bundleID = bid; fp.sceneSize = CGSizeZero;
        p.vc = nil; p.bundleID = nil;
        SCPLog("CarSplit: dua %@ tu o %d ra cua so noi", bid, p.slot);
        [self removePaneAt:p.slot background:NO];
        [self afterPaneRemoved:nil];
    } @catch (NSException *e) { SCPLog("CarSplit: loi hinh trong hinh %@\n%@", e, e.callStackSymbols); }
}

// Keo "•••" cua cua so noi: di chuyen theo tay, tha ra hit sat canh trai / phai gan nhat
- (void)floatPanned:(UIPanGestureRecognizer *)g
{
    static CGPoint start;
    SCPCarPane *fp = self.floatPane;
    if (!fp || !self.container) return;
    if (g.state == UIGestureRecognizerStateBegan) {
        start = self.floatFrame.origin;
        [self setBarVisible:NO forPane:fp];
        [self hideRatioMenu];
    }
    CGPoint t = [g translationInView:self.container];
    CGRect f = self.floatFrame;
    f.origin = CGPointMake(start.x + t.x, start.y + t.y);
    BOOL ended = (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled
                  || g.state == UIGestureRecognizerStateFailed);
    if (!ended) {
        self.floatFrame = f;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        fp.view.frame = f;
        [CATransaction commit];
        return;
    }
    CGRect c = self.container.bounds;
    f.origin.x = (CGRectGetMidX(f) < CGRectGetMidX(c)) ? 8 : c.size.width - f.size.width - 8;
    self.floatFrame = f;
    [self relayoutAnimated:YES];   // fitFloatFrame: kep trong vung app, tranh o CarBridge
    SCPLog("CarSplit: tha cua so noi o %@", NSStringFromCGRect(self.floatFrame));
}

// The icon app phu vung app trong luc ve man chinh roi mo lai app toan man (khong thay man chinh nhay qua).
// Bo khi DashBoard trinh bay app (baseViewControllerPresented) hoac sau 3s (CarBridge 6s).
- (void)showSoloCoverForBundle:(NSString *)bid
{
    UIView *parent = [self tabParent];
    if (!parent) return;
    [self.soloCover removeFromSuperview];
    UIView *cover = [[UIView alloc] initWithFrame:[self appAreaInParent:parent]];
    cover.backgroundColor = SCPCPastel();   // dang mo app: nen pastel sang
    cover.userInteractionEnabled = NO;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    iv.image = SCPCAppIcon(bid);
    SCPCStyleIcon(iv);
    iv.center = CGPointMake(cover.bounds.size.width / 2, cover.bounds.size.height / 2 - 6);
    [cover addSubview:iv];
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spin.color = SCPCAccent();
    spin.center = CGPointMake(cover.bounds.size.width / 2, CGRectGetMaxY(iv.frame) + 18);
    [spin startAnimating];
    [cover addSubview:spin];
    [parent addSubview:cover];
    [self raiseView:cover];
    self.soloCover = cover;
    __weak SCPCarSplit *weakSelf = self;
    __weak UIView *weakCover = cover;
    SCPCAfter(SCPCIsBridgedApp(bid) ? 6.0 : 3.0, ^{ if (weakCover && weakSelf.soloCover == weakCover) [weakSelf hideSoloCover]; });
}

- (void)hideSoloCover
{
    UIView *c = self.soloCover;
    self.soloCover = nil;
    if (!c) return;
    [UIView animateWithDuration:0.25 animations:^{ c.alpha = 0; } completion:^(BOOL f) { [c removeFromSuperview]; }];
}

// DashBoard vua trinh bay 1 app toan man (hook presentBaseViewController): bo the icon cua soloBundle
- (void)baseViewControllerPresented
{
    [self endHostedSolo];   // DashBoard mo app toan man -> app iPhone toan man (neu co) nhuong cho
    if (!self.soloCover) return;
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(0.35, ^{ [weakSelf hideSoloCover]; });   // doi app ve khung dau tien
}

- (void)closeApp:(NSString *)bundleID
{
    SCPCarPane *p = [self paneForBundle:bundleID];
    if (self.active && p) [self closeSlot:p.slot background:YES];
}

- (void)closeGoingHome:(BOOL)goHome
{
    if (!self.active) return;
    SCPLog("CarSplit: tat split (goHome=%d)", goHome);
    [self hostCloseAll];   // app iPhone trong cac o: SpringBoard bo moi o (app van chay nen)
    for (SCPCarPane *p in [self allPanes]) {
        [p.barTimer invalidate]; p.barTimer = nil;
        if (p.vc) [self detachVC:p.vc background:YES];
        p.vc = nil; p.bundleID = nil;
        [p.picker removeFromSuperview]; p.picker = nil;
    }
    self.active = NO;
    [self.pending removeAllObjects];
    [self publishBusy];
    [self removePickerSheet];
    [self hideRatioMenu];
    [self cancelPaneDrag];
    for (SCPCarPane *p in self.slots) [self removeCoverFromPane:p];
    self.resizing = NO;
    UIView *c = self.container;
    self.container = nil; self.slots = nil; self.fractions = nil; self.dividers = nil;
    self.floatPane = nil; self.floatClosing = NO;
    [UIView animateWithDuration:0.2 animations:^{ c.alpha = 0; } completion:^(BOOL f) { [c removeFromSuperview]; }];
    if (goHome) SCPCSendEvent(1, @"SplitScreen: dong split");
    [self refreshAppTabSoon];   // DashBoard co the dang mo 1 app toan man -> hien tab
    [self publishKnobsSoon];    // het split -> SpringBoard bo cham tron ve tren cua so App Bridge
}

// Settings chi cho chon app ma CarPlay hien duoc: app CarPlay that ghi o day, app iPhone la danh sach
// nguoi dung chon trong App Bridge (AB_KEY_APPS, Settings doc thang)
- (void)publishCarPlayApps
{
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *a in SCPCCarPlayApps()) [ids addObject:a[@"id"]];
    if (ids.count) [SCPPrefs setCarPlayApps:ids];
    SCPLog("CarSplit: %lu app CarPlay cho Settings, %lu app iPhone da chon (App Bridge)", (unsigned long)ids.count, (unsigned long)SCPCPhoneApps().count);
}

// DashBoard bi huy (ngat xe): bo trang thai, khong goi gi vao scene nua
- (void)dashboardInvalidated
{
    [self removeAppTab];
    [self removeHomeButton];
    self.autoLaunchDone = NO;
    self.soloHostedBundle = nil;   // App Bridge tu bo o khi xe ngat
    [self removePickerSheet];
    self.trayWindow.hidden = YES; self.trayWindow = nil;   // cua so bang bo cuc gan voi man xe cu
    if (!self.active) return;
    SCPLog("CarSplit: DashBoard invalidate -> bo split");
    self.active = NO;
    [self.pending removeAllObjects];
    [self publishBusy];
    for (SCPCarPane *p in [self allPanes]) [p.barTimer invalidate];
    self.floatPane = nil; self.floatClosing = NO;
    [self.dragGhost removeFromSuperview]; self.dragGhost = nil; self.dragTarget = -1;
    [self.ratioMenu removeFromSuperview];
    [self.ratioTimer invalidate]; self.ratioTimer = nil; self.ratioMenu = nil;
    self.resizing = NO;
    [self.container removeFromSuperview];
    self.container = nil; self.slots = nil; self.fractions = nil; self.dividers = nil;
}

// ---------------------------------------------------------------------
//  Thanh "•••" o dau moi o (HyperOS): cham -> thanh nut [Doi app | Toan man hinh | Dong];
//  keo "•••" tha len o khac -> doi cho 2 o.
// ---------------------------------------------------------------------
static UIView *SCPCDotsHandle(void)
{
    // Kinh trang, 3 cham mau muc; dang mo thanh nut: gradient + cham trang (SCPCHandleOpen)
    UIView *h = [[SCPCarTabView alloc] initWithFrame:CGRectMake(0, 0, SCPC_HANDLE_W, SCPC_HANDLE_H)];
    h.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];   // vien bau duc trong, chi 3 cham ro
    h.layer.cornerRadius = SCPC_HANDLE_H / 2;
    h.layer.cornerCurve = kCACornerCurveContinuous;
    h.layer.borderWidth = 0.5;
    h.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
    for (int i = -1; i <= 1; i++) {
        UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, 4)];
        d.center = CGPointMake(SCPC_HANDLE_W / 2 + i * 8, SCPC_HANDLE_H / 2);
        d.backgroundColor = [SCPCInk() colorWithAlphaComponent:0.85];
        d.layer.cornerRadius = 2;
        d.userInteractionEnabled = NO;
        [h addSubview:d];
    }
    return h;
}

// Tay cam "•••" dang mo thanh nut: gradient + cham trang; dong: kinh trang + cham muc
static void SCPCHandleOpen(UIView *h, BOOL open)
{
    SCPCAccentFill(h, open);
    h.backgroundColor = open ? [UIColor clearColor] : [UIColor colorWithWhite:1 alpha:0.35];
    for (UIView *d in h.subviews) d.backgroundColor = open ? [UIColor whiteColor] : [SCPCInk() colorWithAlphaComponent:0.85];
}

- (void)setupBarForPane:(SCPCarPane *)p
{
    UIView *h = SCPCDotsHandle();
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapped:)];
    // Cham dup "•••": o thuong -> phong to tam / ve lai; cua so noi -> doi co nho / lon
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTapped:)];
    dbl.numberOfTapsRequired = 2;
    [tap requireGestureRecognizerToFail:dbl];
    [h addGestureRecognizer:tap];
    [h addGestureRecognizer:dbl];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanned:)];
    pan.maximumNumberOfTouches = 1;
    [h addGestureRecognizer:pan];
    p.handle = h;
    [p.view addSubview:h];

    // Thanh ••• (DESIGN.md, tools/preview/theme.html): o kinh tron + nhan ngan - Doi app · Toan man / Chia man ·
    // Cua so noi · Chay nen | Tat app (do, tach bang vach trang). Icon HarmonyOS Symbol giu nguyen.
    UIButton *replace = SCPCActionButton(@"hm_apps", SCPCT(@"Đổi app", @"Change app"), SCPCInk(), self, @selector(paneChoose:));
    UIButton *full = SCPCActionButton(@"hm_full", SCPCT(@"Toàn màn", @"Full screen"), SCPCInk(), self, @selector(paneSolo:));
    p.soloButton = full;
    UIButton *pop = SCPCActionButton(@"hm_float", SCPCT(@"Cửa sổ nổi", @"Float"), SCPCInk(), self, @selector(panePopOut:));
    p.popButton = pop;
    UIButton *bg = SCPCActionButton(@"hm_min", SCPCT(@"Chạy nền", @"Background"), SCPCInk(), self, @selector(paneBackground:));
    UIButton *close = SCPCActionButton(@"hm_close", SCPCT(@"Tắt app", @"Quit app"), SCPCDanger(), self, @selector(paneClose:));
    UIView *bar = SCPCActionBar(@[replace, full, pop, bg, [NSNull null], close]);
    bar.hidden = YES;
    p.bar = bar;
    [p.view addSubview:bar];
}

- (SCPCarPane *)paneForView:(UIView *)v
{
    for (SCPCarPane *p in [self allPanes]) if ([v isDescendantOfView:p.view]) return p;
    return nil;
}

// O nam ngay duoi vach ngang co cham tron o giua mep tren -> thanh "•••" lech sang phai cho khoi trung.
// Bo cuc 1 lon + 2: tay nam duy nhat nam o cho giao 2 vach (mep o), khong trung "•••" -> de giua.
- (CGFloat)handleShiftForPane:(SCPCarPane *)p
{
    if (p == self.floatPane || [self mainStack]) return 0;
    return CGRectGetMinY(p.view.frame) > SCPC_INSET + 1 ? SCPC_KNOB_DOT + 24 : 0;
}

- (void)layoutBarForPane:(SCPCarPane *)p
{
    CGSize s = p.view.bounds.size;
    p.handle.center = CGPointMake(s.width / 2 + [self handleShiftForPane:p], SCPC_HANDLE_Y + SCPC_HANDLE_H / 2);
    p.handle.hidden = (p.vc == nil);   // dang chon app thi khong can
    // O hep (3 o, ~150pt): thu nho ca thanh nut cho vua o thay vi bi cat mep; mep tren van ngay duoi tay cam
    CGFloat avail = s.width - 10, bw = p.bar.bounds.size.width;
    CGFloat k = (bw > avail && avail > 40) ? avail / bw : 1;
    p.bar.transform = CGAffineTransformMakeScale(k, k);
    p.bar.center = CGPointMake(s.width / 2, SCPC_HANDLE_Y + SCPC_HANDLE_H + 6 + p.bar.bounds.size.height * k / 2);
    // "Hinh trong hinh": o chia co app thuong (khong phai CarBridge)
    BOOL isFloat = (p == self.floatPane);
    BOOL canPop = isFloat ? (p.vc && [self paneCount] < SCPC_MAX_PANES) : [self canPopOutPane:p];
    SCPCActionSet(p.popButton, isFloat ? @"hm_split" : @"hm_float", isFloat ? SCPCT(@"Chia màn", @"Split") : SCPCT(@"Cửa sổ nổi", @"Float"));
    p.popButton.alpha = canPop ? 1 : 0.35;   // van bam duoc: bam vao thi bao ly do
    // Dang chay 1 man hinh (o nay phong to): nut doi thanh "Chia man hinh" -> ve lai bo cuc truoc
    BOOL single = self.zoomedSlot && self.zoomedSlot.intValue == p.slot;
    SCPCActionSet(p.soloButton, single ? @"hm_split" : @"hm_full", single ? SCPCT(@"Chia màn", @"Split") : SCPCT(@"Toàn màn", @"Full screen"));
    [p.view bringSubviewToFront:p.handle];
    [p.view bringSubviewToFront:p.bar];
}

- (void)setBarVisible:(BOOL)visible forPane:(SCPCarPane *)p
{
    [p.barTimer invalidate]; p.barTimer = nil;
    if (visible) {
        [self hideRatioMenu];
        for (SCPCarPane *o in [self allPanes]) if (o != p) [self setBarVisible:NO forPane:o];
        [self layoutBarForPane:p];
        BOOL wasHidden = p.bar.hidden;
        p.bar.hidden = NO;
        SCPCHandleOpen(p.handle, YES);
        if (wasHidden) SCPCDropIn(p.bar);
        __weak SCPCarSplit *weakSelf = self;
        __weak SCPCarPane *weakPane = p;
        p.barTimer = [NSTimer scheduledTimerWithTimeInterval:4 repeats:NO block:^(NSTimer *t) {
            if (weakPane) [weakSelf setBarVisible:NO forPane:weakPane];
        }];
        if (wasHidden) [self sendHostFrameForPane:p live:NO];   // o app iPhone: cua so host nhuong cho thanh nut
    } else if (!p.bar.hidden) {
        SCPCHandleOpen(p.handle, NO);
        UIView *bar = p.bar;
        __weak SCPCarSplit *weakSelf = self;
        __weak SCPCarPane *weakPane = p;
        CGAffineTransform t = bar.transform;
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{   // mo + nho lai nhe
            bar.alpha = 0; bar.transform = CGAffineTransformScale(t, 0.94, 0.94);
        } completion:^(BOOL f) {
            bar.hidden = YES; bar.alpha = 1; bar.transform = t;
            SCPCarPane *pp = weakPane;
            if (pp) [weakSelf sendHostFrameForPane:pp live:NO];   // o app iPhone: cua so host len lai khi thanh an xong
        }];
    }
}

// ---- Siri / Phim tat (omnicar://splitscreen/layout | ratio | swap | zoom) ----
- (void)urlLayout:(int)layoutID
{
    if (layoutID != 2 && layoutID != 3 && layoutID != SCPC_LAYOUT_MAIN_STACK && layoutID != SCPC_LAYOUT_MAIN_RIGHT) return;
    if (self.active) [self switchToLayout:layoutID];
    else if ([self activateWithLayout:layoutID]) [self showPickersForEmptySlots];
}

- (void)urlRatio:(CGFloat)ratio
{
    if (!self.active || [self paneCount] != 2 || [self mainStack]) return;
    ratio = MIN(0.8, MAX(0.2, ratio));
    self.fractions = [NSMutableArray arrayWithObjects:@(ratio), @(1 - ratio), nil];
    [self relayoutAnimated:YES];
    [self rememberPair];
}

- (void)urlSwap
{
    if (!self.active || [self paneCount] < 2) return;
    [self swapSlot:0 with:1];
    [self relayoutAnimated:YES];
}

- (void)urlZoomPane:(int)pane
{
    SCPCarPane *p = [self paneAtSlot:pane - 1];
    if (p) [self toggleZoomForPane:p];
}

- (void)handleDoubleTapped:(UITapGestureRecognizer *)g
{
    @try {
        SCPCarPane *p = [self paneForView:g.view];
        if (!p) return;
        if (p == self.floatPane) { [self floatHandleDoubleTapped:g]; return; }
        [self toggleZoomForPane:p];
    } @catch (NSException *e) { SCPLog("CarSplit: loi cham dup thanh ••• %@", e); }
}

// Phong to tam 1 o (khac "toan man": cac o khac van mo, chi an di); goi lai -> ve bo cuc cu
- (void)toggleZoomForPane:(SCPCarPane *)p
{
    if (!self.active || !p.vc || p.slot == SCPC_FLOAT_SLOT || [self paneCount] < 2) return;
    BOOL zoomIn = !(self.zoomedSlot && self.zoomedSlot.intValue == p.slot);
    self.zoomedSlot = zoomIn ? @(p.slot) : nil;
    SCPLog("CarSplit: %@ o %d (%@)", zoomIn ? @"phong to" : @"thu nho", p.slot, p.bundleID);
    [self setBarVisible:NO forPane:p];
    [self relayoutAnimated:YES];
}

- (void)handleTapped:(UITapGestureRecognizer *)g
{
    @try {
        SCPCarPane *p = [self paneForView:g.view];
        if (p) [self setBarVisible:p.bar.hidden forPane:p];
    } @catch (NSException *e) { SCPLog("CarSplit: loi cham thanh ••• %@", e); }
}

// Keo "•••": the icon app theo tay, o duoi tay sang vien xanh; tha len o khac -> doi cho
- (void)handlePanned:(UIPanGestureRecognizer *)g
{
    @try {
        SCPCarPane *p = [self paneForView:g.view];
        if (!p || !self.container) { [self cancelPaneDrag]; return; }
        if (p == self.floatPane) { [self floatPanned:g]; return; }   // cua so noi: keo = di chuyen
        CGPoint pt = [g locationInView:self.container];
        switch (g.state) {
            case UIGestureRecognizerStateBegan:   [self beginPaneDrag:p at:pt]; break;
            case UIGestureRecognizerStateChanged: [self movePaneDragTo:pt from:p]; break;
            case UIGestureRecognizerStateEnded:   [self endPaneDrag:p]; break;
            default:                              [self cancelPaneDrag]; break;
        }
    } @catch (NSException *e) { SCPLog("CarSplit: loi keo doi cho %@", e); [self cancelPaneDrag]; }
}

- (void)beginPaneDrag:(SCPCarPane *)p at:(CGPoint)pt
{
    if ([self paneCount] < 2 || !p.vc || self.dragGhost) return;
    for (SCPCarPane *o in [self allPanes]) [self setBarVisible:NO forPane:o];
    [self hideRatioMenu];
    [self beginResize];
    p.cover.alpha = 0.55;   // o dang duoc nhac len
    CGSize ps = p.view.bounds.size;
    CGFloat w = MIN(180, MAX(96, ps.width * 0.4)), h = MIN(130, MAX(72, w * ps.height / MAX(1, ps.width)));
    UIView *ghost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    SCPCChrome(ghost, 16);
    ghost.backgroundColor = [UIColor colorWithWhite:1 alpha:0.92];   // the kinh trang theo tay, vien mau nhan
    ghost.layer.borderColor = SCPCAccent().CGColor;
    ghost.layer.borderWidth = 1.5;
    ghost.userInteractionEnabled = NO;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    iv.image = SCPCAppIcon(p.bundleID);
    SCPCStyleIcon(iv);
    iv.center = CGPointMake(w / 2, h / 2);
    [ghost addSubview:iv];
    // The theo tay nam trong cua so bang bo cuc (tren cac o app iPhone) khi co; khong thi trong container
    UIWindow *tw = [self trayWindowForParent:self.container];
    ghost.center = tw ? [self.container convertPoint:pt toView:nil] : pt;
    [tw ?: self.container addSubview:ghost];
    self.dragGhost = ghost;
    self.dragTarget = -1;
    ghost.transform = CGAffineTransformMakeScale(0.6, 0.6);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ ghost.transform = CGAffineTransformIdentity; } completion:nil];
    SCPLog("CarSplit: keo o %d (%@) de doi cho", p.slot, p.bundleID);
}

- (void)movePaneDragTo:(CGPoint)pt from:(SCPCarPane *)src
{
    if (!self.dragGhost) return;
    self.dragGhost.center = (self.dragGhost.superview == self.container) ? pt : [self.container convertPoint:pt toView:nil];
    int target = -1;
    for (SCPCarPane *o in self.slots)
        if (o != src && o.view.alpha > 0 && CGRectContainsPoint(o.view.frame, pt)) target = o.slot;
    if (target == self.dragTarget) return;
    self.dragTarget = target;
    for (SCPCarPane *o in self.slots) {
        if (o.slot != target) { SCPCFrame(o.view); continue; }
        o.view.layer.borderWidth = 3;
        o.view.layer.borderColor = SCPCAccent().CGColor;   // o sap tha: vien mau nhan
    }
}

- (void)endPaneDrag:(SCPCarPane *)src
{
    int target = self.dragTarget;
    UIView *ghost = self.dragGhost;
    if (!ghost) { [self cancelPaneDrag]; return; }
    [self clearPaneDragMarks];
    CGPoint to = (target >= 0 && target < [self paneCount]) ? self.slots[target].view.center : src.view.center;
    if (ghost.superview != self.container) to = [self.container convertPoint:to toView:nil];
    __weak SCPCarSplit *weakSelf = self;
    [UIView animateWithDuration:0.25 animations:^{
        ghost.center = to; ghost.alpha = 0; ghost.transform = CGAffineTransformMakeScale(0.7, 0.7);
    } completion:^(BOOL f) { [ghost removeFromSuperview]; [weakSelf hideTrayWindowIfIdle]; }];
    src.cover.alpha = 1;
    if (target >= 0 && target != src.slot) [self swapSlot:src.slot with:target];
    [self endResize];
}

- (void)clearPaneDragMarks
{
    self.dragGhost = nil;
    self.dragTarget = -1;
    for (SCPCarPane *o in self.slots) { SCPCFrame(o.view); o.cover.alpha = 1; }
}

- (void)cancelPaneDrag
{
    UIView *ghost = self.dragGhost;
    if (!ghost) return;
    [self clearPaneDragMarks];
    __weak SCPCarSplit *weakSelf = self;
    [UIView animateWithDuration:0.15 animations:^{ ghost.alpha = 0; } completion:^(BOOL f) { [ghost removeFromSuperview]; [weakSelf hideTrayWindowIfIdle]; }];
    [self endResize];
}

// Cua so bang bo cuc khong con gi (bang, thanh ti le, bang chon app, the keo, thong bao) -> an (giu lai cho lan sau)
- (void)hideTrayWindowIfIdle
{
    UIWindow *tw = self.trayWindow;
    if (!tw || self.tray || self.ratioMenu || self.pickerSheet || self.dragGhost) return;
    if ([tw viewWithTag:SCPC_BG_TOAST_TAG]) return;
    tw.hidden = YES;
}

// SpringBoard bao keo thanh "•••" tren o app iPhone (AB_NOTIF_HANDLE_DRAG): keo doi cho nhu o CarPlay; cua so noi: di chuyen
- (void)bridgeHandleDrag:(NSDictionary *)u
{
    SCPCarPane *p = [self paneForBundle:u[@"identifier"]];
    if (!p || !self.container || !self.active) return;
    int phase = [u[@"phase"] intValue];
    CGPoint pt = [self.container convertPoint:CGPointMake([u[@"x"] doubleValue], [u[@"y"] doubleValue]) fromView:nil];
    if (p == self.floatPane) { [self floatDragPhase:phase at:pt]; return; }
    switch (phase) {
        case 0:  [self beginPaneDrag:p at:pt]; break;
        case 1:  [self movePaneDragTo:pt from:p]; break;
        case 2:  [self endPaneDrag:p]; break;
        default: [self cancelPaneDrag]; break;
    }
}

// Keo cua so noi theo tung pha (cung viec voi floatPanned nhung khong co gesture: app iPhone trong cua so noi)
- (void)floatDragPhase:(int)phase at:(CGPoint)pt
{
    static CGPoint startPt, startOrigin;
    SCPCarPane *fp = self.floatPane;
    if (!fp || !self.container) return;
    if (phase == 0) {
        startPt = pt; startOrigin = self.floatFrame.origin;
        [self setBarVisible:NO forPane:fp];
        [self hideRatioMenu];
        return;
    }
    CGRect f = self.floatFrame;
    f.origin = CGPointMake(startOrigin.x + pt.x - startPt.x, startOrigin.y + pt.y - startPt.y);
    if (phase == 1) {
        self.floatFrame = f;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        fp.view.frame = f;
        [CATransaction commit];
        [self pushHostFramesLive:YES];   // cua so app chay theo tay
        return;
    }
    CGRect c = self.container.bounds;
    f.origin.x = (CGRectGetMidX(f) < CGRectGetMidX(c)) ? 8 : c.size.width - f.size.width - 8;
    self.floatFrame = f;
    [self relayoutAnimated:YES];
    SCPLog("CarSplit: tha cua so noi (app iPhone) o %@", NSStringFromCGRect(self.floatFrame));
}

// "Chay 1 man hinh": o nay phu ca vung app, cac o khac van chay phia sau (phong to tam); bam lai ("Chia man hinh")
// -> ve dung bo cuc truoc. Chi con 1 o / cua so noi: thoat chia, app nay toan man nhu cu.
- (void)paneSolo:(UIButton *)b
{
    @try { SCPCarPane *p = [self paneForView:b]; if (p) [self runSoloForPane:p]; }
    @catch (NSException *e) { SCPLog("CarSplit: loi nut chay 1 man hinh %@", e); }
}

- (void)runSoloForPane:(SCPCarPane *)p
{
    [self setBarVisible:NO forPane:p];
    if (p != self.floatPane && [self paneCount] >= 2) { [self toggleZoomForPane:p]; return; }
    SCPLog("CarSplit: [chay 1 man hinh] o %d -> chi giu %@", p.slot, p.bundleID);
    [self soloBundle:p.bundleID];
}

// "Chay nen": dong o nhung app van chay (nhac van phat, chi duong van tiep); thong bao co nut "Mo lai" dua app ve o cu
- (void)paneBackground:(UIButton *)b
{
    @try { SCPCarPane *p = [self paneForView:b]; if (p) [self runBackgroundForPane:p]; }
    @catch (NSException *e) { SCPLog("CarSplit: loi nut chay nen %@", e); }
}

- (void)runBackgroundForPane:(SCPCarPane *)p
{
    NSString *bid = p.bundleID;
    int slot = p.slot;
    [self setBarVisible:NO forPane:p];
    SCPLog("CarSplit: [chay nen] o %d (%@)", slot, bid);
    [self closeSlot:slot background:YES];
    if (bid) [self showBackgroundToastFor:bid slot:slot];
}

// Thong bao "<App> dang chay nen  [Mo lai]" (kinh trang, nut gradient) o dau vung app, tu an sau 5 s
- (void)showBackgroundToastFor:(NSString *)bid slot:(int)slot
{
    // Trong cua so bang bo cuc (tren cac o app iPhone, khong bi che) khi co; khong thi trong view goc CarPlay
    UIView *root = SCPCRootVC().view;
    UIView *host = root ? ([self trayWindowForParent:root] ?: root) : nil;
    if (!host) return;
    [[host viewWithTag:SCPC_BG_TOAST_TAG] removeFromSuperview];
    UIView *t = [[UIView alloc] initWithFrame:CGRectZero];
    t.tag = SCPC_BG_TOAST_TAG;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(7, 6, 24, 24)];
    iv.image = SCPCAppIcon(bid);
    SCPCStyleIcon(iv);
    [t addSubview:iv];
    UILabel *l = [UILabel new];
    l.text = [NSString stringWithFormat:SCPCT(@"%@ đang chạy nền", @"%@ is running in the background"), [self displayNameFor:bid]];
    l.textColor = SCPCInk();
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [l sizeToFit];
    CGFloat maxText = MAX(80, host.bounds.size.width - 200);
    l.frame = CGRectMake(39, 0, MIN(maxText, l.bounds.size.width), 36);
    [t addSubview:l];
    UIButton *open = [SCPCButton buttonWithType:UIButtonTypeCustom];
    [open setTitle:SCPCT(@"Mở lại", @"Reopen") forState:UIControlStateNormal];
    [open setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    open.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    CGFloat ow = [open.titleLabel sizeThatFits:CGSizeZero].width + 24;
    open.frame = CGRectMake(CGRectGetMaxX(l.frame) + 10, 5, ow, 26);
    open.layer.cornerRadius = 13;
    SCPCAccentFill(open, YES);
    __weak SCPCarSplit *weakSelf = self;
    __weak UIView *weakToast = t;
    [open addAction:[UIAction actionWithHandler:^(UIAction *a) {
        [weakToast removeFromSuperview];
        SCPCarSplit *me = weakSelf;
        if (!me) return;
        [me hideTrayWindowIfIdle];
        int at = me.active ? MIN(slot, [me paneCount]) : 0;
        SCPLog("CarSplit: [mo lai] %@ vao o %d", bid, at);
        [me openApp:bid slot:at];
    }] forControlEvents:UIControlEventTouchUpInside];
    [t addSubview:open];
    t.bounds = CGRectMake(0, 0, CGRectGetMaxX(open.frame) + 5, 36);
    SCPCGlass(t, 18);
    t.center = CGPointMake(CGRectGetMidX(host.bounds), 26);
    [host addSubview:t];
    SCPCDropIn(t);
    SCPCAfter(5, ^{
        UIView *tt = weakToast;
        if (!tt) return;
        [UIView animateWithDuration:0.25 animations:^{ tt.alpha = 0; } completion:^(BOOL f) { [tt removeFromSuperview]; [weakSelf hideTrayWindowIfIdle]; }];
    });
}

- (void)paneChoose:(UIButton *)b
{
    @try {
        SCPCarPane *p = [self paneForView:b];
        if (!p) return;
        [self setBarVisible:NO forPane:p];
        if ([self slotIsPinned:p.slot]) { [self toast:SCPCT(@"Ô này đang ghim", @"This pane is pinned")]; return; }
        [self showPickerForSlot:p.slot];
        if (p.picker) { self.pickerSheetPane = p; [self refreshPickerSheetSoon]; }   // chon lai app cho o nay: bang chon cho o nay ngay
    } @catch (NSException *e) { SCPLog("CarSplit: loi nut doi app %@", e); }
}

- (void)paneClose:(UIButton *)b
{
    @try { SCPCarPane *p = [self paneForView:b]; if (p) [self runCloseForPane:p]; }
    @catch (NSException *e) { SCPLog("CarSplit: loi nut dong %@", e); }
}

// "Tat han app": dong o va thoat luon app (muon giu app chay thi dung "Chay nen")
- (void)runCloseForPane:(SCPCarPane *)p
{
    NSString *bid = p.bundleID;
    [self setBarVisible:NO forPane:p];
    [self closeSlot:p.slot background:YES];
    SCPLog("CarSplit: [tat han app] %@", bid);
    if (bid) [self killAppSoon:bid];
}

// ---------------------------------------------------------------------
//  Keo kieu HyperOS: moi o phu the toi + icon app (scene chi doi kich thuoc 1 lan khi tha tay, noi dung
//  dang bi gian thi khong lo ra), CBWindow cua CarBridge an trong luc keo.
// ---------------------------------------------------------------------
#define SCPC_COVER_ICON_TAG 77

- (void)addCoverToPane:(SCPCarPane *)p
{
    if (p.cover || !p.vc) return;
    UIView *cover = [[UIView alloc] initWithFrame:p.view.bounds];
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    cover.backgroundColor = SCPCPastel();
    cover.userInteractionEnabled = NO;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 52, 52)];
    iv.image = SCPCAppIcon(p.bundleID);
    SCPCStyleIcon(iv);
    iv.tag = SCPC_COVER_ICON_TAG;
    iv.center = CGPointMake(CGRectGetMidX(cover.bounds), CGRectGetMidY(cover.bounds));
    iv.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                        | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [cover addSubview:iv];
    [p.view insertSubview:cover aboveSubview:p.host];
    [p.view bringSubviewToFront:p.handle];
    p.cover = cover;
    cover.alpha = 0;
    [UIView animateWithDuration:0.12 animations:^{ cover.alpha = 1; }];
}

- (void)removeCoverFromPane:(SCPCarPane *)p
{
    UIView *cover = p.cover;
    p.cover = nil;
    if (!cover) return;
    [UIView animateWithDuration:0.22 animations:^{ cover.alpha = 0; } completion:^(BOOL f) { [cover removeFromSuperview]; }];
}

// The "dang mo app" kieu HyperOS: icon app phong ra tu giua o roi nhip tho nhe + vong xoay mong ben duoi,
// den khi app ve xong thi icon phong to va mo dan -> app mo cham (CarBridge 2-6s) khong thay dung hinh.
#define SCPC_LOADER_ICON_TAG 78
- (void)showLoaderInPane:(SCPCarPane *)p bundle:(NSString *)bid
{
    if (!p.view) return;
    [self removeLoaderFromPane:p animated:NO];
    UIView *card = [[UIView alloc] initWithFrame:p.view.bounds];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    card.backgroundColor = SCPCPastel();   // the dang mo app: nen pastel sang
    card.userInteractionEnabled = NO;
    card.accessibilityIdentifier = bid;
    card.userInteractionEnabled = YES;   // nut huy

    UIView *group = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 112)];   // icon + ten + vong xoay, luon giua o
    group.center = CGPointMake(CGRectGetMidX(card.bounds), CGRectGetMidY(card.bounds));
    group.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                           | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [card addSubview:group];

    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(32, 0, 56, 56)];
    iv.image = SCPCAppIcon(bid);
    SCPCStyleIcon(iv);
    iv.tag = SCPC_LOADER_ICON_TAG;
    [group addSubview:iv];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(0, 62, 120, 16)];
    name.text = [self displayNameFor:bid];
    name.textColor = SCPCInk2();
    name.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    name.textAlignment = NSTextAlignmentCenter;
    [group addSubview:name];

    UIView *spin = [[UIView alloc] initWithFrame:CGRectMake(50, 88, 20, 20)];
    CAShapeLayer *arc = [CAShapeLayer layer];
    arc.frame = spin.bounds;
    arc.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(10, 10) radius:8 startAngle:-M_PI_2 endAngle:M_PI clockwise:YES].CGPath;
    arc.fillColor = nil;
    arc.strokeColor = SCPCAccent().CGColor;   // vong xoay mau nhan
    arc.lineWidth = 2;
    arc.lineCap = kCALineCapRound;
    [spin.layer addSublayer:arc];
    CABasicAnimation *rot = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rot.toValue = @(M_PI * 2); rot.duration = 0.9; rot.repeatCount = HUGE_VALF;
    [spin.layer addAnimation:rot forKey:@"spin"];
    [group addSubview:spin];

    // O hep (3 o, man xe thap): thu nho ca cum cho vua
    CGFloat k = MIN(1, MIN(p.view.bounds.size.width / 130, p.view.bounds.size.height / 124));
    if (k > 0.2) group.transform = CGAffineTransformMakeScale(k, k);

    [p.view insertSubview:card aboveSubview:p.host];
    [p.view bringSubviewToFront:p.handle];
    [p.view bringSubviewToFront:p.bar];
    p.loader = card;
    // Nut x: app mo lau / treo -> huy, o hien lai bang chon app
    UIButton *stop = SCPCCircleButton(SCPCGlyph(@"close", 16, NO), 32, self, @selector(loaderCancelTapped:));
    stop.tintColor = SCPCDanger();   // moi dau x (tat / thoat) mau do, nen do nhat
    stop.backgroundColor = [SCPCDanger() colorWithAlphaComponent:0.14];
    stop.center = CGPointMake(card.bounds.size.width - 22, 22);
    stop.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    stop.accessibilityLabel = SCPCT(@"Huỷ mở app", @"Cancel opening");
    [card addSubview:stop];
    // Chot chan: the "dang mo" khong bao gio ket mai (cho het han ma khong qua duong bao loi nao)
    __weak SCPCarSplit *weakSelf = self;
    __weak SCPCarPane *weakPane = p;
    __weak UIView *weakCard = card;
    SCPCAfter(SCPC_PENDING_TTL + 8, ^{
        SCPCarSplit *me = weakSelf; SCPCarPane *pp = weakPane;
        if (!me || !pp || !weakCard || pp.loader != weakCard || [me pendingSlotForBundle:bid] >= 0) return;
        SCPLog("CarSplit: the dang mo %@ con sot -> bo", bid);
        [me launchFailed:bid slot:-1];
    });

    // Vao: the mo dan, icon phong tu 0.6 (lo xo); sau do nhip tho 1 <-> 0.93
    card.alpha = 0;
    iv.transform = CGAffineTransformMakeScale(0.6, 0.6);
    [UIView animateWithDuration:0.2 animations:^{ card.alpha = 1; }];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.6 options:0
                     animations:^{ iv.transform = CGAffineTransformIdentity; }
                     completion:^(BOOL f) {
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @1.0; pulse.toValue = @0.93; pulse.duration = 0.8;
        pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [iv.layer addAnimation:pulse forKey:@"pulse"];
    }];
}

- (void)loaderCancelTapped:(UIButton *)b
{
    @try {
        SCPCarPane *p = [self paneForView:b];
        NSString *bid = p.loader.accessibilityIdentifier;
        if (!p || !bid) return;
        SCPLog("CarSplit: huy mo %@ o o %d", bid, p.slot);
        self.cancelledLaunches[bid] = [NSDate date];
        [self launchFailed:bid slot:p.slot];
    } @catch (NSException *e) { SCPLog("CarSplit: loi huy mo app %@", e); }
}

// App da hien: icon phong to + the mo dan (de scene kip ve khung dau tien ben duoi)
- (void)removeLoaderFromPane:(SCPCarPane *)p animated:(BOOL)animated
{
    UIView *card = p.loader;
    p.loader = nil;
    if (!card) return;
    if (!animated) { [card removeFromSuperview]; return; }
    UIView *iv = [card viewWithTag:SCPC_LOADER_ICON_TAG];
    [iv.layer removeAnimationForKey:@"pulse"];
    [UIView animateWithDuration:0.3 delay:0.2 options:UIViewAnimationOptionCurveEaseOut animations:^{
        card.alpha = 0;
        iv.transform = CGAffineTransformMakeScale(1.25, 1.25);
    } completion:^(BOOL f) { [card removeFromSuperview]; }];
}

// O sap bi dong (keo vach sat mep): the dam hon, icon mo + nho lai
- (void)markDismissSlot:(int)slot
{
    for (SCPCarPane *p in self.slots) {
        BOOL on = (p.slot == slot);
        UIView *iv = [p.cover viewWithTag:SCPC_COVER_ICON_TAG];
        p.cover.backgroundColor = on ? [UIColor colorWithRed:0xD9 / 255.0 green:0xD6 / 255.0 blue:0xEE / 255.0 alpha:1] : SCPCPastel();
        iv.alpha = on ? 0.35 : 1;
        iv.transform = on ? CGAffineTransformMakeScale(0.8, 0.8) : CGAffineTransformIdentity;
    }
}

- (void)beginResize
{
    if (self.resizing) return;
    self.resizing = YES;
    for (SCPCarPane *p in self.slots) [self addCoverToPane:p];
}

// Tha tay: dat CBWindow vao khung moi, doi scene ve xong kich thuoc moi roi moi bo the icon
- (void)endResize
{
    if (!self.resizing) return;
    self.resizing = NO;
    [self pushHostFramesLive:NO];   // tha tay: cua so host (App Bridge) doi kich thuoc scene theo o
    NSArray *panes = [self.slots copy];
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(0.45, ^{
        SCPCarSplit *me = weakSelf;
        if (!me || me.resizing) return;
        [me markDismissSlot:-1];
        for (SCPCarPane *p in panes) [me removeCoverFromPane:p];
    });
}

// ---------------------------------------------------------------------
//  Vach chia + tay nam (HyperOS): keo doi ti le (tha tay hit 1/3 · 1/2 · 2/3), keo sat mep -> dong o bi ep,
//  cham 2 lan -> doi cho 2 o hai ben.
// ---------------------------------------------------------------------
// Mau cua cham tron: kinh trang, vien sang, cham mau muc o giua (kieu nut joystick); dang cham / keo: mau nhan tim, cham trang, quang tim
static UIColor *SCPCKnobFill(BOOL on) { return on ? SCPCAccent() : [UIColor clearColor]; }   // khong cham: lo kinh mo ben duoi

static void SCPCKnobActive(UIView *knob, BOOL on)
{
    [UIView animateWithDuration:on ? 0.15 : 0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        knob.transform = on ? CGAffineTransformMakeScale(SCPC_KNOB_GROW, SCPC_KNOB_GROW) : CGAffineTransformIdentity;
        knob.backgroundColor = SCPCKnobFill(on);
        for (CALayer *l in knob.layer.sublayers) l.backgroundColor = (on ? [UIColor whiteColor] : SCPCInk()).CGColor;   // cham giua
        knob.layer.shadowColor = (on ? SCPCAccent() : SCPCShadow()).CGColor;   // dang cham: quang tim
    } completion:nil];
    [[SCPCarSplit shared] publishKnobsSoon];   // o app iPhone (App Bridge) ve de len cham tron -> SpringBoard ve lai cham tron len tren
}

// Tay nam: nut tron (SCPC_KNOB_DOT) giua vach / o giao 2 vach, vong trang vien toi + cham o giua (y tuong nguoi dung,
// anh 10/10). Cung mot kieu cho moi bo cuc; style chi con de biet da dung kich thuoc chua (tag).
static void SCPCKnobStyle(UIView *knob, NSInteger style)
{
    if (knob.tag == 3) return;
    knob.tag = 3;
    knob.bounds = CGRectMake(0, 0, SCPC_KNOB_DOT, SCPC_KNOB_DOT);
    SCPCGlassFill(knob, SCPC_KNOB_DOT / 2);   // cham tron kinh mo (nhu nut dock), cham giua mau muc; dang cham: mau nhan
    knob.backgroundColor = SCPCKnobFill(NO);
    knob.layer.borderWidth = 1.5;
    knob.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.95].CGColor;
    knob.layer.shadowColor = SCPCShadow().CGColor;
    knob.layer.shadowOpacity = 0.45; knob.layer.shadowRadius = 3; knob.layer.shadowOffset = CGSizeMake(0, 1);
    CALayer *dot = [CALayer layer];
    CGFloat ds = 4;
    dot.frame = CGRectMake((SCPC_KNOB_DOT - ds) / 2, (SCPC_KNOB_DOT - ds) / 2, ds, ds);
    dot.cornerRadius = ds / 2;
    dot.backgroundColor = SCPCInk().CGColor;
    [knob.layer addSublayer:dot];
}

- (SCPCarDividerView *)newDividerAt:(int)i
{
    SCPCarDividerView *d = [[SCPCarDividerView alloc] initWithFrame:CGRectZero];
    d.index = i;
    d.backgroundColor = [UIColor clearColor];
    UIView *knob = [[UIView alloc] initWithFrame:CGRectZero];
    knob.backgroundColor = [UIColor clearColor];   // SCPCKnobStyle them kinh mo
    knob.layer.cornerCurve = kCACornerCurveContinuous;
    knob.layer.shadowColor = SCPCShadow().CGColor;
    knob.layer.shadowOpacity = 0.4; knob.layer.shadowRadius = 3; knob.layer.shadowOffset = CGSizeZero;
    knob.userInteractionEnabled = NO;
    [d addSubview:knob];
    d.knob = knob;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dividerPanned:)];
    pan.cancelsTouchesInView = NO;   // cham tron giu to suot luc keo (touchesBegan da phong to), khong bi huy roi phong lai
    pan.maximumNumberOfTouches = 1;
    [d addGestureRecognizer:pan];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dividerDoubleTapped:)];
    dbl.numberOfTapsRequired = 2;
    [d addGestureRecognizer:dbl];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dividerTapped:)];
    // Cham 1 lan hien thanh ti le ngay (khong doi 0.3s xem co cham lan 2); cham 2 lan dong thanh roi doi cho
    [d addGestureRecognizer:tap];
    [self.container addSubview:d];
    return d;
}

- (void)layoutKnobOf:(SCPCarDividerView *)d
{
    CGSize s = d.bounds.size;
    BOOL v = [self dividerRunsHorizontally:d.index];
    UIView *knob = d.knob;
    SCPCKnobStyle(knob, [self mainStack] ? 3 : (v ? 2 : 1));
    if ([self mainStack]) {
        // 1 lon + 2: 1 tay nam duy nhat o cho giao 2 vach (nam tren vach 0), vach 1 khong co tay nam
        knob.hidden = (d.index != 0);
        if (d.index == 0) {
            CGRect d1 = [self dividerFrameAt:1];
            CGPoint j = [d convertPoint:CGPointMake(CGRectGetMidX(d1), CGRectGetMidY(d1)) fromView:self.container];
            knob.center = [self vertical] ? CGPointMake(j.x, s.height / 2) : CGPointMake(s.width / 2, j.y);
        }
    } else {
        knob.hidden = NO;
        // Cham tron o chinh giua moi vach (dong nhat); thanh "•••" cua o ngay duoi vach ngang lech sang phai (layoutBarForPane)
        knob.center = CGPointMake(s.width / 2, s.height / 2);
    }
    [self.container bringSubviewToFront:d];
    if (self.ratioMenu.superview == self.container) [self.container bringSubviewToFront:self.ratioMenu];
    [self publishKnobsSoon];
}

// Ti le hit khi tha tay. 2 o: 1/3 · 1/2 · 2/3 (nhu HyperOS). 3 o: buoc 1/12, moi o >= SCPC_MIN_FRAC.
static CGFloat SCPCSnap(CGFloat f, CGFloat pair, int n)
{
    if (n == 2) {
        CGFloat best = 0.5;
        for (NSNumber *s in @[@(1.0 / 3), @0.5, @(2.0 / 3)]) if (fabs(f - s.doubleValue) < fabs(f - best)) best = s.doubleValue;
        return best;
    }
    if (pair < SCPC_MIN_FRAC * 2) return pair / 2;
    CGFloat r = round(f * 12) / 12;
    return MIN(pair - SCPC_MIN_FRAC, MAX(SCPC_MIN_FRAC, r));
}

- (void)dividerPanned:(UIPanGestureRecognizer *)g
{
    @try {
        SCPCarDividerView *d = (SCPCarDividerView *)g.view;
        [self dividerPan:d state:g.state location:[g locationInView:d] translation:[g translationInView:self.container]];
    } @catch (NSException *e) {
        SCPLog("CarSplit: loi keo vach %@", e);
        [self markDismissSlot:-1];
        [self endResize];
        [self relayoutAnimated:YES];
    }
}

// Keo vach d (tu UIPanGestureRecognizer cua no, hoac tu cham tron SpringBoard ve: remoteKnobTouch). loc = diem trong d,
// tr = do doi trong container.
- (void)dividerPan:(SCPCarDividerView *)d state:(UIGestureRecognizerState)st location:(CGPoint)loc translation:(CGPoint)tr
{
    // Keo vach i: chi doi ti le 2 o hai ben (o i va i + 1), cac o khac giu nguyen
    int i = d.index, n = [self paneCount];
    BOOL ended = (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled
                  || st == UIGestureRecognizerStateFailed);
    if (i < 0 || i + 1 >= n) { if (ended) [self endResize]; return; }
    if (st == UIGestureRecognizerStateBegan) {
        for (SCPCarPane *p in self.slots) [self setBarVisible:NO forPane:p];
        [self hideRatioMenu];   // truoc beginResize: hideRatioMenu goi endResize
        [self beginResize];
    }
    if ([self mainStack]) { [self mainStackDividerPan:d state:st location:loc translation:tr ended:ended]; return; }
    static CGFloat startA = 0.5, startB = 0.5;
    CGRect a = CGRectInset(self.container.bounds, SCPC_INSET, SCPC_INSET);
    BOOL v = [self vertical];
    CGFloat len = (v ? a.size.height : a.size.width) - SCPC_GAP * (n - 1);
    if (len < 10) { if (ended) [self endResize]; return; }
    if ((int)self.fractions.count != n) [self resetFractions];
    if (st == UIGestureRecognizerStateBegan) {
        startA = [self fractionAt:i]; startB = [self fractionAt:i + 1];
        SCPCKnobActive(d.knob, YES);
    }
    CGPoint t = tr;
    CGFloat pair = startA + startB;
    // Trong luc keo cho ep sat mep (de dong o); tha tay moi hit ti le / dong
    CGFloat na = MIN(pair - 0.04, MAX(0.04, startA + (v ? t.y : t.x) / len));
    int dismiss = (na < SCPC_DISMISS) ? i : ((pair - na < SCPC_DISMISS) ? i + 1 : -1);
    if (!ended) {
        self.fractions[i] = @(na);
        self.fractions[i + 1] = @(pair - na);
        [self markDismissSlot:dismiss];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self relayoutAnimated:NO pushScenes:NO];
        [CATransaction commit];
        return;
    }
    SCPCKnobActive(d.knob, NO);
    [self markDismissSlot:-1];
    if (dismiss >= 0) {
        // O bi ep giu ti le nho, xoa o thi o ben canh nhan het phan cua no
        self.fractions[i] = @(na);
        self.fractions[i + 1] = @(pair - na);
        SCPLog("CarSplit: keo vach %d sat mep -> dong o %d (%@)", i, dismiss, self.slots[dismiss].bundleID);
        [self endResize];
        [self closeSlot:dismiss background:YES];
        return;
    }
    na = SCPCSnap(na, pair, n);
    self.fractions[i] = @(na);
    self.fractions[i + 1] = @(pair - na);
    [self endResize];
    [self relayoutAnimated:YES];   // tha tay moi bao kich thuoc moi cho scene
    [self saveRatio];
}

// 1 lon + 2 nho. Keo tay nam o cho giao 2 vach: doi ca be rong o lon (f0) lan chieu cao 2 o nho (f1) cung luc.
// Keo doc theo vach (khong cham tay nam): vach 0 doi f0, vach 1 doi f1. Ep sat mep: f0 -> dong o lon,
// f1 -> dong o nho bi ep.
- (void)mainStackDividerPan:(SCPCarDividerView *)d state:(UIGestureRecognizerState)st location:(CGPoint)loc translation:(CGPoint)tr ended:(BOOL)ended
{
    int i = d.index;
    static CGFloat start0 = 0.5, start1 = 0.5;
    static BOOL both = NO;
    static int axis = 0;   // tay nam tron: 0 chua ro, 1 chi o lon, 2 chi 2 o nho, 3 ca hai (keo cheo ro rang)
    CGRect a = CGRectInset(self.container.bounds, SCPC_INSET, SCPC_INSET);
    BOOL along0 = [self dividerRunsHorizontally:0], along1 = [self dividerRunsHorizontally:1];
    CGRect rest = CGRectUnion([self frameForSlot:1], [self frameForSlot:2]);
    CGFloat len0 = (along0 ? a.size.height : a.size.width) - SCPC_GAP;
    CGFloat len1 = (along1 ? rest.size.height : rest.size.width) - SCPC_GAP;
    if (len0 < 10 || len1 < 10) { if (ended) [self endResize]; return; }
    if ((int)self.fractions.count != 2) [self resetFractions];
    UIView *knob = self.dividers.count ? self.dividers[0].knob : nil;
    if (st == UIGestureRecognizerStateBegan) {
        start0 = [self fractionAt:0]; start1 = [self fractionAt:1];
        both = (i == 0 && !d.knob.hidden && CGRectContainsPoint(CGRectInset(d.knob.frame, -SCPC_DIVIDER_HIT, -SCPC_DIVIDER_HIT), loc));
        axis = 0;
        if (both || i == 0) SCPCKnobActive(knob, YES);
    }
    CGPoint t = tr;
    CGFloat f0 = start0, f1 = start1;
    CGFloat d0 = (along0 ? t.y : t.x) * ([self mainRight] ? -1 : 1);   // 2 + 1 lon: keo vach ve phia o lon = o lon nho lai
    CGFloat d1 = along1 ? t.y : t.x;
    // Keo tay nam tron: xe rung lam tay lech -> chi doi theo chieu keo chinh; cheo ro rang (lech < 1.5 lan) moi doi ca hai
    if (both && axis == 0 && hypot(d0, d1) > 12) axis = fabs(d0) > fabs(d1) * 1.5 ? 1 : (fabs(d1) > fabs(d0) * 1.5 ? 2 : 3);
    BOOL move0 = (i == 0) && (!both || axis == 1 || axis == 3), move1 = (i == 1) || (both && (axis == 2 || axis == 3));
    if (move0) f0 = MIN(0.75, MAX(0.04, start0 + d0 / len0));
    if (move1) f1 = MIN(0.96, MAX(0.04, start1 + d1 / len1));
    int dismiss = (f0 < SCPC_DISMISS) ? 0 : (f1 < SCPC_DISMISS ? 1 : (1 - f1 < SCPC_DISMISS ? 2 : -1));
    self.fractions[0] = @(f0);
    self.fractions[1] = @(f1);
    if (!ended) {
        [self markDismissSlot:dismiss];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self relayoutAnimated:NO pushScenes:NO];
        [CATransaction commit];
        return;
    }
    if (both || i == 0) SCPCKnobActive(knob, NO);
    [self markDismissSlot:-1];
    if (dismiss >= 0) {
        SCPLog("CarSplit: keo vach sat mep (1 lon + 2) -> dong o %d (%@)", dismiss, self.slots[dismiss].bundleID);
        [self endResize];
        [self closeSlot:dismiss background:YES];
        return;
    }
    self.fractions[0] = @(MIN(0.67, SCPCSnap(f0, 1, 2)));
    self.fractions[1] = @(SCPCSnap(f1, 1, 2));
    [self endResize];
    [self relayoutAnimated:YES];
    [self saveRatio];
}

- (void)saveRatio
{
    NSMutableArray *txt = [NSMutableArray array];
    for (NSNumber *f in self.fractions) [txt addObject:[NSString stringWithFormat:@"%.2f", f.doubleValue]];
    SCPLog("CarSplit: ti le cac o = %@", [txt componentsJoinedByString:@" / "]);
    if ([self paneCount] != 2) return;
    CGFloat r = [self fractionAt:0];
    [SCPPrefs setSplitRatio:r];
    NSString *l = self.slots[0].bundleID, *rb = self.slots[1].bundleID;
    if (l && rb) [SCPPrefs setRatio:r forPairLeft:l right:rb];
}

// Cham 2 lan vao vach: doi cho 2 o hai ben (HyperOS)
- (void)dividerDoubleTapped:(UITapGestureRecognizer *)g { [self dividerDoubleTapOn:(SCPCarDividerView *)g.view]; }
- (void)dividerDoubleTapOn:(SCPCarDividerView *)d
{
    @try {
        int i = d.index;
        if (i < 0 || i + 1 >= [self paneCount]) return;
        SCPLog("CarSplit: cham 2 lan vach %d -> doi cho o %d va %d", i, i, i + 1);
        [self hideRatioMenu];
        for (SCPCarPane *p in self.slots) [self setBarVisible:NO forPane:p];
        [self swapSlot:i with:i + 1];
    } @catch (NSException *e) { SCPLog("CarSplit: loi doi cho %@", e); }
}


// Icon 1 ti le: cac o to dac theo dung ti le (1 lon + 2: o lon trai, 2 o nho xep chong). rot = man xe doc.
static UIImage *SCPCRatioGlyph(NSArray<NSNumber *> *fr, BOOL mainStack, BOOL mirror, BOOL rot, CGFloat pt)
{
    return SCPCDraw(pt, rot, ^(UIBezierPath *p, UIBezierPath *f) {
        // O vien net 1.5 bo 2 (kieu HarmonyOS, tools/preview/theme.html), khong to dac
        CGFloat x0 = 3, y0 = 5, W = 18, H = 14, gap = 1.6;
        p.lineWidth = 1.5;
        void (^box)(CGFloat, CGFloat, CGFloat, CGFloat) = ^(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
            [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, MAX(1, w), MAX(1, h)) cornerRadius:MIN(2, MIN(w, h) / 2)]];
        };
        if (mainStack && fr.count >= 2) {
            CGFloat mw = round((W - gap) * fr[0].doubleValue * 10) / 10, th = round((H - gap) * fr[1].doubleValue * 10) / 10;
            CGFloat sx = mirror ? x0 : x0 + mw + gap, mx = mirror ? x0 + W - mw : x0;   // 2 + 1 lon: o lon ben phai
            box(mx, y0, mw, H);
            box(sx, y0, W - mw - gap, th);
            box(sx, y0 + th + gap, W - mw - gap, H - th - gap);
            return;
        }
        CGFloat len = W - gap * (fr.count - 1), x = x0;
        for (NSUInteger i = 0; i < fr.count; i++) {
            CGFloat w = (i + 1 == fr.count) ? x0 + W - x : round(len * fr[i].doubleValue * 10) / 10;
            box(x, y0, w, H);
            x += w + gap;
        }
    });
}

// Ti le mac dinh cho thanh ti le (mang thay ca self.fractions)
- (NSArray<NSArray<NSNumber *> *> *)ratioPresets
{
    if ([self mainStack]) return @[@[@(1.0 / 3), @0.5], @[@0.5, @0.5], @[@(2.0 / 3), @0.5]];
    if ([self paneCount] == 2) return @[@[@(1.0 / 3), @(2.0 / 3)], @[@0.5, @0.5], @[@(2.0 / 3), @(1.0 / 3)]];
    return @[@[@(1.0 / 3), @(1.0 / 3), @(1.0 / 3)], @[@0.25, @0.5, @0.25], @[@0.5, @0.25, @0.25], @[@0.25, @0.25, @0.5]];
}

- (BOOL)fractionsMatch:(NSArray<NSNumber *> *)fr
{
    if (fr.count != self.fractions.count) return NO;
    for (NSUInteger i = 0; i < fr.count; i++) if (fabs(fr[i].doubleValue - self.fractions[i].doubleValue) > 0.03) return NO;
    return YES;
}

// Cham 1 lan vao tay nam: hien / an thanh ti le mac dinh
- (void)dividerTapped:(UITapGestureRecognizer *)g
{
    SCPCarDividerView *d = (SCPCarDividerView *)g.view;
    [self dividerTapOn:d at:[g locationInView:d]];
}
- (void)dividerTapOn:(SCPCarDividerView *)d at:(CGPoint)loc
{
    @try {
        if (!d.knob || d.knob.hidden) return;
        if (!CGRectContainsPoint(CGRectInset(d.knob.frame, -SCPC_DIVIDER_HIT, -SCPC_DIVIDER_HIT), loc)) return;
        if (self.ratioMenu) { [self hideRatioMenu]; return; }
        [self showRatioMenuForDivider:d];
    } @catch (NSException *e) { SCPLog("CarSplit: loi cham tay nam %@\n%@", e, e.callStackSymbols); }
}

// SpringBoard bao cham vao cham tron no ve len tren o app iPhone (AB_NOTIF_KNOB_TOUCH; cham do khong bao gio toi CarPlay):
// phase 0 bat dau / 1 di / 2 nhac / 3 huy, x y = diem man xe. Dieu khien vach nhu cham vao cham tron cua chinh CarPlay:
// di > 8 pt = keo (dividerPan), nhac ma chua keo = cham (thanh ti le), 2 cham nhanh = doi cho.
- (void)remoteKnobTouch:(NSDictionary *)info
{
    static CGPoint start;
    static BOOL panning;
    static NSTimeInterval lastTap;
    @try {
        int idx = [info[@"index"] intValue], phase = [info[@"phase"] intValue];
        SCPCarDividerView *d = nil;
        for (SCPCarDividerView *x in self.dividers) if (x.index == idx) d = x;
        if (!d || !self.active || !self.container || !d.window) {
            if (phase == 0) SCPLog("CarSplit: cham tron SpringBoard vach %d bo qua (vach %@, active %d)", idx, d ? @"co" : @"khong", (int)self.active);
            return;
        }
        CGPoint w = CGPointMake([info[@"x"] doubleValue], [info[@"y"] doubleValue]);
        CGPoint c = [self.container convertPoint:w fromView:nil];
        CGPoint loc = [d convertPoint:w fromView:nil];
        CGPoint tr = CGPointMake(c.x - start.x, c.y - start.y);
        if (phase == 0) {
            start = c; panning = NO;
            SCPLog("CarSplit: cham tron SpringBoard vach %d tai %@", idx, NSStringFromCGPoint(loc));
            if (d.knob && !d.knob.hidden) SCPCKnobActive(d.knob, YES);
        } else if (phase == 1) {
            if (panning) { [self dividerPan:d state:UIGestureRecognizerStateChanged location:loc translation:tr]; return; }
            if (hypot(tr.x, tr.y) < 8) return;
            panning = YES;
            [self dividerPan:d state:UIGestureRecognizerStateBegan location:loc translation:tr];
        } else if (panning) {
            panning = NO;
            [self dividerPan:d state:(phase == 2 ? UIGestureRecognizerStateEnded : UIGestureRecognizerStateCancelled) location:loc translation:tr];
        } else {
            if (d.knob) SCPCKnobActive(d.knob, NO);
            if (phase != 2) return;
            NSTimeInterval now = CACurrentMediaTime();
            [self dividerTapOn:d at:loc];
            if (now - lastTap < 0.35) { lastTap = 0; [self dividerDoubleTapOn:d]; }
            else lastTap = now;
        }
    } @catch (NSException *e) {
        SCPLog("CarSplit: loi cham tron tu SpringBoard %@", e);
        panning = NO;
        [self markDismissSlot:-1];
        [self endResize];
        [self relayoutAnimated:YES];
    }
}

- (void)showRatioMenuForDivider:(SCPCarDividerView *)d
{
    if ([self paneCount] < 2 || !self.container) return;
    for (SCPCarPane *p in self.slots) [self setBarVisible:NO forPane:p];
    if ((int)self.fractions.count != ([self mainStack] ? 2 : [self paneCount])) [self resetFractions];
    NSArray<NSArray<NSNumber *> *> *presets = [self ratioPresets];
    BOOL v = [self vertical];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSUInteger k = 0; k < presets.count; k++) {
        UIButton *b = SCPCRoundButton(SCPCRatioGlyph(presets[k], [self mainStack], [self mainRight], v, 22), self, @selector(ratioPresetTapped:));
        b.tag = (NSInteger)k;
        if ([self fractionsMatch:presets[k]]) SCPCSelectRing(b, YES);   // ti le dang dung: vien cau vong, nen van trong
        [btns addObject:b];
    }
    UIView *m = SCPCPill(btns, NO);
    // Ngay tren tay nam (khong du cho thi ngay duoi), luon nam gon trong vung app
    CGRect kf = [self.container convertRect:d.knob.frame fromView:d];
    CGSize ms = m.bounds.size, cs = self.container.bounds.size;
    CGFloat y = CGRectGetMinY(kf) - 10 - ms.height / 2;
    if (y < ms.height / 2 + 6) y = CGRectGetMaxY(kf) + 10 + ms.height / 2;
    CGFloat x = MIN(cs.width - ms.width / 2 - 6, MAX(ms.width / 2 + 6, CGRectGetMidX(kf)));
    m.center = CGPointMake(x, MIN(cs.height - ms.height / 2 - 6, y));

    // Thanh nam tren cua so rieng (tren o App Bridge): man hinh giu nguyen, chi hien thanh (nguoi dung 10/10 23:19: cham
    // cham tron thi YouTube nhay sang logo). Khong tao duoc cua so -> trong container nhu cu, an o app iPhone bi de.
    UIWindow *ow = [self trayWindowForParent:self.container];
    self.ratioOverlay = (ow != nil);
    if (ow) { m.center = [self.container convertPoint:m.center toView:nil]; [ow addSubview:m]; }
    else [self.container addSubview:m];
    self.ratioMenu = m;
    if (!ow) for (SCPCarPane *hp in [self hostedPanes]) {   // thanh de len o app iPhone -> cua so host tam an, phu the icon
        if (!CGRectIntersectsRect(CGRectInset(m.frame, -6, -6), hp.view.frame)) continue;
        self.ratioHidesBridge = YES;
        [self addCoverToPane:hp];
    }
    [self pushHostFramesLive:NO];
    self.ratioKnob = d.knob;
    SCPCKnobActive(d.knob, YES);
    SCPCDropIn(m);
    __weak SCPCarSplit *weakSelf = self;
    self.ratioTimer = [NSTimer scheduledTimerWithTimeInterval:4 repeats:NO block:^(NSTimer *t) { [weakSelf hideRatioMenu]; }];
    SCPLog("CarSplit: cham tay nam vach %d -> thanh ti le (%lu muc)", d.index, (unsigned long)presets.count);
}

- (void)hideRatioMenu
{
    [self.ratioTimer invalidate]; self.ratioTimer = nil;
    UIView *m = self.ratioMenu;
    self.ratioMenu = nil;
    if (!m) return;
    if (self.ratioKnob) SCPCKnobActive(self.ratioKnob, NO);
    self.ratioKnob = nil;
    UIWindow *tw = self.ratioOverlay ? self.trayWindow : nil;
    __weak SCPCarSplit *weakSelf = self;
    [UIView animateWithDuration:0.15 animations:^{ m.alpha = 0; } completion:^(BOOL f) {
        [m removeFromSuperview];
        if (tw && !weakSelf.tray && !weakSelf.ratioMenu && !weakSelf.pickerSheet) tw.hidden = YES;
    }];
    if (self.ratioHidesBridge) {
        self.ratioHidesBridge = NO;
        if (!self.resizing) for (SCPCarPane *hp in [self hostedPanes]) [self removeCoverFromPane:hp];
    }
    [self pushHostFramesLive:NO];
}

// Chon 1 ti le: cac o co gian ve dung ti le (the icon che trong luc scene doi kich thuoc)
- (void)ratioPresetTapped:(UIButton *)b
{
    @try {
        NSArray<NSArray<NSNumber *> *> *presets = [self ratioPresets];
        if (b.tag < 0 || b.tag >= (NSInteger)presets.count) { [self hideRatioMenu]; return; }
        [self hideRatioMenu];
        [self beginResize];   // the icon che trong luc cac scene doi kich thuoc (nhu luc keo vach)
        self.fractions = [presets[b.tag] mutableCopy];
        [self relayoutAnimated:YES];
        [self saveRatio];
        [self endResize];
    } @catch (NSException *e) { SCPLog("CarSplit: loi chon ti le %@\n%@", e, e.callStackSymbols); [self hideRatioMenu]; }
}

// ---------------------------------------------------------------------
//  Bang chon app CarPlay: moi o can chon app co 1 the "dang chon" trong o (p.picker, giu cho bo cuc tinh o do),
//  con danh sach app hien toan man hinh va chon cho tung o mot (o nho 3 o / 1 lon + 2 qua hep, khong thay het app).
//  Bang nam trong cua so rieng (trayWindowForParent, tren cac o App Bridge); so do nho tren dau bang cho biet dang
//  chon cho o nao, cham o khac dang cho trong so do de chuyen sang chon cho o do.
// ---------------------------------------------------------------------
- (void)removePickerFromPane:(SCPCarPane *)p
{
    if (!p.picker) return;
    UIView *pv = p.picker;
    p.picker = nil;
    [UIView animateWithDuration:0.15 animations:^{ pv.alpha = 0; } completion:^(BOOL f) { [pv removeFromSuperview]; }];
    [self refreshPickerSheetSoon];
}

- (void)showPickerForSlot:(int)slot
{
    if (![self activate]) return;
    if (![self validSlot:slot]) slot = [self autoSlot];
    SCPCarPane *p = [self paneAtSlot:slot];
    if (!p) return;
    [self removePickerFromPane:p];
    [self removeLoaderFromPane:p animated:NO];

    // The trong o: nen pastel sang + dau "+" (o dang duoc chon trong bang toan man co vien mau nhan, xem markPickerPanes)
    UIView *pv = [[UIView alloc] init];
    p.picker = pv;                     // dat truoc de bo cuc tinh ca ngan nay
    CGSize size = [self frameForSlot:slot].size;
    pv.frame = CGRectMake(0, 0, size.width, size.height);
    pv.backgroundColor = SCPCPastel();
    pv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    pv.layer.borderColor = SCPCAccent().CGColor;   // vien mau nhan (o dang chon), cung mau o sang trong so do
    UILabel *plus = [[UILabel alloc] initWithFrame:pv.bounds];
    plus.text = @"+";
    plus.textColor = [SCPCInk2() colorWithAlphaComponent:0.6];
    plus.font = [UIFont systemFontOfSize:40 weight:UIFontWeightLight];
    plus.textAlignment = NSTextAlignmentCenter;
    plus.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [pv addSubview:plus];
    [pv addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickerPaneTapped:)]];

    [p.view addSubview:pv];
    [p.view bringSubviewToFront:p.handle];
    [self relayoutAnimated:YES];
    pv.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ pv.alpha = 1; }];
    [self refreshPickerSheetSoon];
}

// The trong o (khi bang khong che duoc o, vd khong tao duoc cua so rieng): cham -> chon cho o nay
- (void)pickerPaneTapped:(UITapGestureRecognizer *)g
{
    SCPCarPane *p = [self paneForView:g.view];
    if (!p.picker) return;
    self.pickerSheetPane = p;
    [self refreshPickerSheetSoon];
}

- (void)refreshPickerSheetSoon
{
    if (self.pickerSheetQueued) return;
    self.pickerSheetQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pickerSheetQueued = NO;
        @try { [self refreshPickerSheet]; }
        @catch (NSException *e) { SCPLog("CarSplit: loi bang chon app %@\n%@", e, e.callStackSymbols); [self removePickerSheet]; }
    });
}

// Chon o cho bang: giu o dang chon neu con cho, khong thi o dau tien con the "dang chon"; het o cho -> dong bang
// O theo thu tu doc: tu trai sang phai, cung cot thi tren truoc; cua so noi sau cung (so "o 1, 2, 3" trong bang chon)
- (NSArray<SCPCarPane *> *)panesInReadingOrder
{
    return [[self allPanes] sortedArrayUsingComparator:^NSComparisonResult(SCPCarPane *a, SCPCarPane *b) {
        if ((a == self.floatPane) != (b == self.floatPane)) return (a == self.floatPane) ? NSOrderedDescending : NSOrderedAscending;
        CGRect fa = [self frameForSlot:a.slot], fb = [self frameForSlot:b.slot];
        if (fabs(CGRectGetMinX(fa) - CGRectGetMinX(fb)) > 1) return CGRectGetMinX(fa) < CGRectGetMinX(fb) ? NSOrderedAscending : NSOrderedDescending;
        if (fabs(CGRectGetMinY(fa) - CGRectGetMinY(fb)) > 1) return CGRectGetMinY(fa) < CGRectGetMinY(fb) ? NSOrderedAscending : NSOrderedDescending;
        return a.slot < b.slot ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (void)refreshPickerSheet
{
    NSArray<SCPCarPane *> *panes = self.active ? [self allPanes] : @[];
    SCPCarPane *target = self.pickerSheetPane;
    if (!target.picker || ![panes containsObject:target]) target = nil;
    // Mac dinh chon lan luot o 1, 2, 3 theo vi tri tu trai sang phai (cung cot: tren truoc), cua so noi sau cung
    NSArray<SCPCarPane *> *ordered = self.active ? [self panesInReadingOrder] : @[];
    for (SCPCarPane *p in ordered) if (!target && p.picker) target = p;
    self.pickerSheetPane = target;
    if (!target || !self.container.window) { [self removePickerSheet]; return; }
    NSString *key = [NSString stringWithFormat:@"%p/%d/%lu/%d/%@", target, target.slot, (unsigned long)panes.count, (int)[self mainStack],
                     NSStringFromCGSize(self.container.bounds.size)];
    if (self.pickerSheet && [key isEqualToString:self.pickerSheetKey]) { [self markPickerPanes]; return; }
    [self buildPickerSheetForPane:target];
    self.pickerSheetKey = key;
    [self markPickerPanes];
}

- (void)markPickerPanes
{
    for (SCPCarPane *p in [self allPanes]) p.picker.layer.borderWidth = (p == self.pickerSheetPane) ? 3 : 0;
}

- (void)removePickerSheet
{
    UIView *sheet = self.pickerSheet, *shield = self.pickerShield;
    BOOL overlay = self.pickerSheetOverlay;
    self.pickerSheet = nil; self.pickerShield = nil; self.pickerSheetKey = nil; self.pickerSheetOverlay = NO;
    if (!sheet && !shield) return;
    __weak SCPCarSplit *weakSelf = self;
    UIWindow *tw = self.trayWindow;
    // HarmonyOS: bang chim xuong + thu nho nhe, lop mo tan dan
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        sheet.alpha = 0;
        if ([shield isKindOfClass:[UIVisualEffectView class]]) { ((UIVisualEffectView *)shield).effect = nil; ((UIVisualEffectView *)shield).contentView.alpha = 0; }
        else shield.alpha = 0;
        sheet.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, 24), 0.94, 0.94);
    } completion:^(BOOL f) {
        [sheet removeFromSuperview]; [shield removeFromSuperview];
        if (tw && !weakSelf.tray && !weakSelf.ratioMenu && !weakSelf.pickerSheet) tw.hidden = YES;
    }];
    if (!overlay && self.active) [self pushHostFramesLive:NO];   // bang nam trong CarPlay: tra lai o app iPhone
}

// So do bo cuc nho: o da co app (hoac dang mo) hien logo app; o dang chon xanh voi dau "+"; o khac con cho chon
// "+" mo (cham de chuyen sang o do)
- (UIView *)pickerMapForPane:(SCPCarPane *)target height:(CGFloat)mh
{
    CGSize cs = self.container.bounds.size;
    if (cs.width < 1 || cs.height < 1) return nil;
    CGFloat k = mh / cs.height, mw = cs.width * k;
    UIView *map = [[UIView alloc] initWithFrame:CGRectMake(0, 0, mw, mh)];
    for (SCPCarPane *p in [self allPanes]) {
        CGRect r = (p == self.floatPane) ? self.floatFrame : [self frameForSlot:p.slot];
        if (r.size.width < 1 || r.size.height < 1) continue;
        r = CGRectInset(CGRectMake(r.origin.x * k, r.origin.y * k, r.size.width * k, r.size.height * k), 1.5, 1.5);
        NSString *bid = p.picker ? nil : p.bundleID;
        if (!p.picker && !bid)   // app dang mo vao o nay (cho DashBoard)
            for (NSString *pb in self.pending) if ([self.pending[pb][0] intValue] == p.slot) { bid = pb; break; }
        UIButton *b = [SCPCButton buttonWithType:UIButtonTypeCustom];
        b.frame = r;
        b.tag = p.slot;
        b.layer.cornerRadius = 5;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        // O dang chon app: gradient nut chinh + quang; o khac: kinh trang trong + vien trang 1.5pt (nhu o bo cuc trong khay)
        b.backgroundColor = (p == target) ? [UIColor clearColor] : [UIColor colorWithWhite:1 alpha:p.picker ? 0.6 : 0.45];
        if (p == target) SCPCAccentFill(b, YES);
        else { b.layer.borderWidth = 1.5; b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.95].CGColor; }
        CGFloat side = MIN(r.size.width, r.size.height);
        if (bid) {
            CGFloat s = MIN(22, floor(side * 0.7));
            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((r.size.width - s) / 2, (r.size.height - s) / 2, s, s)];
            iv.image = SCPCAppIcon(bid);
            SCPCStyleIcon(iv);
            iv.userInteractionEnabled = NO;
            [b addSubview:iv];
        } else if (p.picker) {
            UILabel *plus = [[UILabel alloc] initWithFrame:b.bounds];
            plus.text = @"+";
            plus.textAlignment = NSTextAlignmentCenter;
            plus.textColor = (p == target) ? [UIColor whiteColor] : SCPCInk2();   // o dang chon (gradient): dau + trang
            plus.font = [UIFont systemFontOfSize:MIN(22, floor(side * 0.8)) weight:(p == target) ? UIFontWeightBold : UIFontWeightRegular];
            plus.userInteractionEnabled = NO;
            [b addSubview:plus];
        }
        b.userInteractionEnabled = (p.picker && p != target);
        [b addTarget:self action:@selector(pickerMapTapped:) forControlEvents:UIControlEventTouchUpInside];
        [map addSubview:b];
    }
    return map;
}

- (void)pickerMapTapped:(UIButton *)b
{
    SCPCarPane *p = [self paneAtSlot:(int)b.tag];
    if (!p.picker) return;
    self.pickerSheetPane = p;
    [self refreshPickerSheetSoon];
}

- (void)buildPickerSheetForPane:(SCPCarPane *)target
{
    UIView *oldSheet = self.pickerSheet, *oldShield = self.pickerShield;
    UIWindow *host = [self trayWindowForParent:self.container];   // nil -> bang trong container (o app iPhone phai nhuong)
    BOOL overlay = (host != nil);
    CGRect area = overlay ? [self.container convertRect:self.container.bounds toView:nil] : self.container.bounds;
    UIView *parent = overlay ? host : self.container;

    // Kieu HarmonyOS: popup kinh mo trong suot giua vung app, khong lop phu - dock va cac o van thay / cham duoc
    // (cham the "+" cua o khac de chuyen sang o do). Cao vua so hang app, toi da gan het vung app.
    [oldShield removeFromSuperview];
    NSMutableArray *apps = [NSMutableArray array];   // app CarPlay roi app iPhone (App Bridge)
    BOOL inFloat = (target == self.floatPane);
    for (NSDictionary *app in [SCPCCarPlayApps() arrayByAddingObjectsFromArray:SCPCPhoneApps()])
        if (!inFloat || !SCPCIsBridgedApp(app[@"id"])) [apps addObject:app];   // cua so noi khong nhan YouTube / TikTok
    // Popup 2 phan: ben trai la luoi app dung het chieu cao (man xe thap van duoc nhieu hang); cot phai: "Ô N" + nut
    // dong o goc tren phai, so do bo cuc lon de cham chon o, "Còn N ô". App van cach nhau de
    // cham khi xe chay (o 78 x 68pt, icon 36pt); het cho thi chia trang vuot ngang co cham trang
    CGFloat cellW = 62, cellH = 56, icon = 38, gridPad = 10, sideW = 150, pad = 14;   // chi icon, khong ten (nguoi dung)
    CGSize cs = self.container.bounds.size;
    CGFloat mapW = sideW - pad * 2, mapH = (cs.width > 1) ? MIN(84, mapW * cs.height / cs.width) : 60;
    NSInteger cols = MAX(1, MIN((NSInteger)((area.size.width - 24 - sideW - gridPad * 2) / cellW), MAX((NSInteger)4, (NSInteger)apps.count)));
    NSInteger maxRows = MAX(1, (NSInteger)((area.size.height - 16 - 12 - 16) / cellH));
    NSInteger rows = MAX(1, MIN(maxRows, ((NSInteger)apps.count + cols - 1) / cols));
    NSInteger perPage = rows * cols, pages = MAX(1, ((NSInteger)apps.count + perPage - 1) / perPage);
    CGFloat gridW = cols * cellW + gridPad * 2, gridH = rows * cellH + 4, dotsH = pages > 1 ? 16 : 0;
    CGFloat sideMinH = pad + 32 + 8 + mapH + pad;   // nut X, so do
    CGFloat h = MIN(area.size.height - 16, MAX(sideMinH, 8 + gridH + dotsH + 6)), w = sideW + gridW;
    CGFloat gridX = 0, gridY = MAX(8, (h - gridH - dotsH) / 2);   // luoi app ben trai, cot thong tin ben phai
    CGRect pf = CGRectMake(CGRectGetMidX(area) - w / 2, CGRectGetMidY(area) - h / 2, w, h);

    UIView *card = [[UIView alloc] initWithFrame:pf];
    card.layer.cornerRadius = 24;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.shadowColor = SCPCShadow().CGColor;
    card.layer.shadowOpacity = 0.3; card.layer.shadowRadius = 24; card.layer.shadowOffset = CGSizeMake(0, 8);
    UIVisualEffectView *glass = SCPCGlassView();
    glass.frame = card.bounds;
    // Cung nen logo / vien / bong voi khay bo cuc (showLayoutPanelForApp) de 2 bang nhin nhu mot
    SCPCMesh(glass);
    glass.layer.cornerRadius = 24;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    [card addSubview:glass];
    UIView *sheet = glass.contentView;   // noi dung nam tren kinh; card la khung hien / an

    UIView *side = [[UIView alloc] initWithFrame:CGRectMake(gridW, 0, sideW, h)];   // cot phai: nen trong, cung mau bang
    side.backgroundColor = [UIColor clearColor];
    [sheet addSubview:side];
    UIView *map = [self pickerMapForPane:target height:mapH];
    if (map) { map.frame = CGRectMake(pad, pad + 32 + 8, map.bounds.size.width, mapH); [side addSubview:map]; }

    int waiting = 0;
    for (SCPCarPane *p in [self allPanes]) if (p.picker && p != target) waiting++;

    UIButton *cancel = SCPCRoundButton(SCPCGlyph(@"close", 14, NO), self, @selector(pickerCancel:));
    cancel.bounds = CGRectMake(0, 0, 32, 32);
    cancel.layer.cornerRadius = 16;
    SCPCTile(cancel, 16);   // nut X: o kinh trang nhu cac nut khac, chi dau x mau do
    cancel.tintColor = SCPCDanger();
    cancel.center = CGPointMake(sideW - pad - 16, pad + 16);   // goc tren phai cua popup
    [side addSubview:cancel];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(gridX, gridY, gridW, gridH)];
    scroll.pagingEnabled = YES;   // vuot ngang theo trang, khong co thanh cuon
    scroll.showsHorizontalScrollIndicator = NO;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceHorizontal = pages > 1;
    scroll.delegate = self;       // cap nhat cham trang (scrollViewDidScroll)
    [sheet addSubview:scroll];

    NSMutableSet *inUse = [NSMutableSet set];
    for (SCPCarPane *o in [self allPanes]) if (o.bundleID) [inUse addObject:o.bundleID];
    [inUse addObjectsFromArray:self.pending.allKeys];   // app dang mo vao 1 o (cho DashBoard) cung tinh la da chon
    NSInteger i = 0;
    NSMutableArray *cells = [NSMutableArray array];
    for (NSDictionary *app in apps) {
        NSInteger page = i / perPage, row = (i % perPage) / cols, col = i % cols;
        UIButton *b = [SCPCButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(page * gridW + gridPad + col * cellW, 2 + row * cellH, cellW, cellH);
        b.accessibilityIdentifier = app[@"id"];
        [b addTarget:self action:@selector(pickerAppTapped:) forControlEvents:UIControlEventTouchUpInside];
        // Khong khung quanh app: icon tran nhu man Home, bong tim nhat de noi tren nen logo
        b.accessibilityLabel = app[@"name"];   // khong hien ten, chi doc len
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((cellW - icon) / 2, (cellH - icon) / 2, icon, icon)];
        iv.image = SCPCAppIcon(app[@"id"]);
        SCPCStyleIcon(iv);
        iv.userInteractionEnabled = NO;
        UIView *lift = [[UIView alloc] initWithFrame:iv.frame];   // giu bong (icon cat bo goc nen khong tu do bong duoc)
        lift.userInteractionEnabled = NO;
        lift.layer.shadowColor = SCPCShadow().CGColor;
        lift.layer.shadowOpacity = 0.25; lift.layer.shadowRadius = 5; lift.layer.shadowOffset = CGSizeMake(0, 4);
        lift.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:lift.bounds cornerRadius:iv.layer.cornerRadius].CGPath;
        [b addSubview:lift];
        [b addSubview:iv];
        BOOL used = [inUse containsObject:app[@"id"]];
        if (used) {   // da o 1 o khac: dau tich gradient, ca o mo di va khong cham duoc (khong chon trung app)
            UIImageView *tick = [[UIImageView alloc] initWithImage:SCPCGlyph(@"check", 10, NO)];
            tick.tintColor = [UIColor whiteColor];
            tick.backgroundColor = SCPCAccent();   // dau tich mau nhan, dau check trang
            tick.frame = CGRectMake(CGRectGetMaxX(iv.frame) - 10, CGRectGetMinY(iv.frame) - 4, 14, 14);
            tick.contentMode = UIViewContentModeCenter;
            tick.layer.cornerRadius = 7;
            tick.layer.borderWidth = 1;
            tick.layer.borderColor = [UIColor whiteColor].CGColor;
            tick.clipsToBounds = YES;
            tick.userInteractionEnabled = NO;
            [b addSubview:tick];
        }
        if (used) {   // mo noi dung (khong mo ca nut: hieu ung hien len dat alpha nut ve 1); cham xuyen xuong scroll de van vuot trang
            for (UIView *sv in b.subviews) sv.alpha = 0.3;
            b.userInteractionEnabled = NO;
            b.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
        }
        [scroll addSubview:b];
        if (i < perPage) [cells addObject:b];   // trang dau: hien lan luot
        i++;
    }
    scroll.contentSize = CGSizeMake(pages * gridW, gridH);
    UIView *dots = nil;
    if (pages > 1) {   // cham trang HarmonyOS: trang dang xem la vien dai, trang khac cham tron mo
        dots = [[UIView alloc] initWithFrame:CGRectMake(gridX, gridY + gridH, gridW, dotsH)];
        dots.userInteractionEnabled = NO;
        for (NSInteger k = 0; k < pages; k++) {
            UIView *d = [[UIView alloc] init];
            d.layer.cornerRadius = 3;
            [dots addSubview:d];
        }
        [sheet addSubview:dots];
    }
    self.pickerDots = dots;
    dots.tag = 1;   // trang 1 (scrollViewDidScroll chi ve lai khi doi trang)
    [self layoutPickerDotsForPage:0];
    if (i == 0) {   // khong co app nao: 1 dong chu giua luoi
        UILabel *none = [[UILabel alloc] initWithFrame:scroll.bounds];
        none.text = SCPCT(@"Không có app", @"No apps");
        none.textColor = SCPCInk2();
        none.textAlignment = NSTextAlignmentCenter;
        [scroll addSubview:none];
    }

    [parent addSubview:card];
    if (self.tray && self.tray.superview == parent) {   // bang bo cuc dang mo cung cua so -> giu no o tren
        [parent bringSubviewToFront:self.trayShield];
        [parent bringSubviewToFront:self.tray];
    }
    self.pickerSheet = card; self.pickerShield = nil; self.pickerSheetOverlay = overlay;
    // Hien kieu HarmonyOS: popup troi len + phong nhe theo lo xo; doi o: popup cu mo, popup moi troi len it
    BOOL fresh = !oldSheet;
    if (oldSheet) [UIView animateWithDuration:0.15 animations:^{ oldSheet.alpha = 0; } completion:^(BOOL f) { [oldSheet removeFromSuperview]; }];
    card.alpha = 0;
    card.transform = fresh ? CGAffineTransformScale(CGAffineTransformMakeTranslation(0, 48), 0.92, 0.92) : CGAffineTransformMakeTranslation(0, 14);
    [UIView animateWithDuration:fresh ? 0.5 : 0.35 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ card.alpha = 1; card.transform = CGAffineTransformIdentity; } completion:nil];
    // Icon hien lan luot theo hang: mo + troi len nhe
    for (UIView *c in cells) {
        NSInteger row = (NSInteger)((c.frame.origin.y - 2) / cellH), col = (NSInteger)((c.frame.origin.x - gridPad) / cellW);
        c.alpha = 0; c.transform = CGAffineTransformMakeTranslation(0, 16);
        [UIView animateWithDuration:0.45 delay:(fresh ? 0.08 : 0.03) + row * 0.05 + col * 0.012 usingSpringWithDamping:0.85 initialSpringVelocity:0.3
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ c.alpha = 1; c.transform = CGAffineTransformIdentity; } completion:nil];
    }
    if (!overlay) [self pushHostFramesLive:NO];   // bang nam trong CarPlay: o app iPhone nhuong cho (hostFrameForPane)
    SCPLog("CarSplit: popup chon %ld app cho o %d (%s, %d o cho)", (long)i, target.slot, overlay ? "cua so rieng" : "container", waiting);
}

- (void)pickerAppTapped:(UIButton *)b
{
    @try {
        SCPCarPane *p = self.pickerSheetPane ?: [self paneForView:b];
        if (!p) return;
        NSString *bid = b.accessibilityIdentifier;
        SCPLog("CarSplit: chon %@ cho o %d", bid, p.slot);
        [self openApp:bid slot:p.slot];
        if (p.picker) [self refreshPickerSheetSoon];   // openApp tu choi (vd app iPhone vao cua so noi) -> bang van mo
    } @catch (NSException *e) { SCPLog("CarSplit: loi chon app %@\n%@", e, e.callStackSymbols); }
}

// Huy bang chon: o con app -> quay lai app; o trong -> bo o do (3 -> 2 o; con 1 app -> ve toan man)
- (void)pickerCancel:(UIButton *)b
{
    @try {
        SCPCarPane *p = self.pickerSheetPane ?: [self paneForView:b];
        if (!p) return;
        [self removePickerFromPane:p];
        if (p.vc || [self slotOccupied:p.slot]) { [self relayoutAnimated:YES]; return; }
        if (p == self.floatPane) { [self closeFloat:NO]; return; }   // cua so noi chua co app -> dong
        [self removePaneAt:p.slot background:NO];
        [self afterPaneRemoved:nil];
    } @catch (NSException *e) { SCPLog("CarSplit: loi huy bang chon %@\n%@", e, e.callStackSymbols); }
}

// ---------------------------------------------------------------------
// ---------------------------------------------------------------------
//  Bang cua nut Split Screen tren dock: Mac dinh (2 o / 3 o / 1 lon + 2), Gan day, Yeu thich.
//  Dang mo app toan man: chon bo cuc mac dinh -> app do vao o 1, cac o con lai hien bang chon app.
// ---------------------------------------------------------------------
#define SCPC_TRAY_IDLE  4.0     // giay khong cham -> thu bang bo cuc (cung 4s nhu thanh nut cua o / thanh ti le)

- (UIView *)tabParent
{
    UIViewController *root = SCPCRootVC();
    UIView *base = objcInvoke(root, @"baseContainerView");
    return base.superview ?: root.view;
}

// App CarPlay dang mo toan man (co the dua vao ngan), nil neu dang o man chinh / app khong ho tro
- (NSString *)fullscreenAppBundle
{
    if (self.soloHostedBundle) return self.soloHostedBundle;   // app iPhone toan man qua App Bridge
    UIViewController *cur = objcInvoke(SCPCRootVC(), @"currentBaseViewController");
    if (!cur || ![self isAdoptableViewController:cur]) return nil;
    return SCPRealBundleForInfos(objcInvoke(cur, @"applicationInfo"), objcInvoke(cur, @"proxyApplicationInfo"));
}

// Dat view tren app/home nhung duoi Siri (stackedContainerView)
- (BOOL)viewIsRaised:(UIView *)v
{
    UIView *parent = v.superview;
    if (!parent) return NO;
    UIView *stacked = objcInvoke(SCPCRootVC(), @"stackedContainerView");
    NSArray *subs = parent.subviews;
    if (stacked.superview != parent) return subs.lastObject == v;
    NSUInteger i = [subs indexOfObjectIdenticalTo:v], si = [subs indexOfObjectIdenticalTo:stacked];
    return i != NSNotFound && i + 1 == si;
}

- (void)raiseView:(UIView *)v
{
    UIView *parent = v.superview;
    if (!parent || [self viewIsRaised:v]) return;   // da dung cho -> khong dong vao (tranh layout lai)
    UIView *stacked = objcInvoke(SCPCRootVC(), @"stackedContainerView");
    if (stacked.superview == parent) [parent insertSubview:v belowSubview:stacked];
    else [parent bringSubviewToFront:v];
}

- (void)refreshAppTabSoon
{
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(0.35, ^{
        [weakSelf refreshAppTab];
    });
}

// Goi khi DashBoard layout / mo / dong app: cap nhat nut Split Screen tren dock (khong con the logo tren app,
// nut dock lam het viec do). Bang dang mo thi giu no tren cung.
- (void)refreshAppTab
{
    [self refreshHomeButton];
    if (self.tray && ![self viewIsRaised:self.tray]) { [self raiseView:self.trayShield]; [self raiseView:self.tray]; }
}

- (void)removeAppTab
{
    [self collapseAppTray];
}

// Bang bo cuc o giua mep tren vung app. app = app vao o 1 (app dang mo / icon vua giu);
// nil = mo tu man chinh -> mo lai cap app lan truoc theo bo cuc chon.
// Cac lua chon cua bang. layout: 2 / 3 / 13. apps = nil: bo cuc mac dinh (app dang mo vao o 1);
// apps != nil: mo dung cac app do (NSNull = o trong, hien bang chon).
- (NSArray<NSArray<NSDictionary *> *> *)panelSections:(NSArray<NSString *> **)titles
{
    NSMutableArray *sections = [NSMutableArray array], *names = [NSMutableArray array];
    [sections addObject:@[@{@"layout": @2, @"name": SCPCT(@"2 ô", @"2 panes")},
                          @{@"layout": @3, @"name": SCPCT(@"3 ô", @"3 panes")},
                          @{@"layout": @(SCPC_LAYOUT_MAIN_STACK), @"name": SCPCT(@"1 lớn + 2", @"1 large + 2")},
                          @{@"layout": @(SCPC_LAYOUT_MAIN_RIGHT), @"name": SCPCT(@"2 + 1 lớn", @"2 + 1 large")}]];
    [names addObject:@"layouts"];

    NSMutableArray *recent = [NSMutableArray array];
    for (NSDictionary *r in ([SCPPrefs showRecent] ? [SCPPrefs recentLayouts] : @[])) {
        NSArray *apps = r[@"apps"];
        BOOL ok = apps.count >= 2;
        NSMutableArray *short_ = [NSMutableArray array];
        for (NSString *bid in apps) {
            if (![bid isKindOfClass:[NSString class]] || ![self isCarPlayApp:bid]) { ok = NO; break; }
            [short_ addObject:[self displayNameFor:bid]];
        }
        if (ok) [recent addObject:@{@"layout": r[@"layout"], @"apps": apps, @"name": [short_ componentsJoinedByString:@" + "]}];
    }
    if ([SCPPrefs showRecent]) {   // bat trong Cai dat -> luon hien (trong -> dong goi y)
        [sections addObject:recent];
        [names addObject:@"recent"];
    }

    NSMutableArray *favs = [NSMutableArray array];
    NSInteger favCount = [SCPPrefs showFavorites] ? 3 : 0;   // tat trong Cai dat -> khong hien muc Yeu thich
    for (NSInteger i = 1; i <= favCount; i++) {
        NSDictionary *f = [SCPPrefs favorite:i];
        NSArray *apps = [self favoriteApps:f];
        if (!apps) continue;
        [favs addObject:@{@"layout": f[@"layout"] ?: @2, @"apps": apps, @"name": f[@"name"] ?: @""}];
    }
    if (favs.count) { [sections addObject:favs]; [names addObject:@"favorite"]; }
    if (titles) *titles = names;
    return sections;
}

// Bang cua nut Split Screen / logo: Mac dinh (2 o / 3 o / 1 lon + 2), Gan day, Yeu thich. app = app vao o 1 khi
// chon bo cuc mac dinh (app dang mo / icon vua giu); nil = tu man chinh -> cap app lan truoc.
// Cua so rieng cho bang bo cuc, muc tren cua so App Bridge cua SpringBoard (+60) va duoi bong bong toc do (+70): bang
// hien de len ca o app iPhone ma khong phai an o (nguoi dung: bam OmniCar thi man hinh giu nguyen, chi hien bang).
// Cung cach SpringBoard dat cua so len man xe (ABMakeCarWindow): UIRootSceneWindow theo FBSDisplayConfiguration.
#define SCPC_TRAY_LEVEL (UIWindowLevelStatusBar + 65)
// Cua so chi nhan cham o view con (thanh ti le); cho trong suot cham xuyen xuong (doi class cua instance luc chay)
static UIView *SCPCPassHitTest(id self, SEL _cmd, CGPoint p, UIEvent *e)
{
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    UIView *v = ((UIView *(*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
    return (v == self) ? nil : v;
}
static void SCPCMakePassThrough(UIWindow *w)
{
    Class base = object_getClass(w);
    NSString *name = [NSString stringWithFormat:@"SCPCPass_%@", NSStringFromClass(base)];
    Class cls = objc_getClass(name.UTF8String);
    if (!cls) {
        cls = objc_allocateClassPair(base, name.UTF8String, 0);
        Method m = class_getInstanceMethod(base, @selector(hitTest:withEvent:));
        class_addMethod(cls, @selector(hitTest:withEvent:), (IMP)SCPCPassHitTest, method_getTypeEncoding(m));
        objc_registerClassPair(cls);
    }
    object_setClass(w, cls);
}
- (UIWindow *)trayWindowForParent:(UIView *)parent
{
    UIScreen *screen = parent.window.screen;
    if (!screen) return nil;
    UIWindow *w = self.trayWindow;
    if (w && w.screen == screen) { w.hidden = NO; return w; }
    if (w) { w.hidden = YES; self.trayWindow = nil; }
    id config = [screen respondsToSelector:NSSelectorFromString(@"displayConfiguration")] ? objcInvoke(screen, @"displayConfiguration") : nil;
    if (!config) {
        id display = [screen respondsToSelector:NSSelectorFromString(@"_display")] ? objcInvoke(screen, @"_display") : nil;
        if (display) config = objcInvoke_2([objc_getClass("FBSDisplayConfiguration") alloc], @"initWithCADisplay:isMainDisplay:", display, (BOOL)NO);
    }
    id rw = config ? objcInvoke_1([objc_getClass("UIRootSceneWindow") alloc], @"initWithDisplayConfiguration:", config) : nil;
    if (![rw isKindOfClass:[UIWindow class]]) {
        SCPLog("CarSplit: khong tao duoc cua so bang bo cuc (config %@, window %@) -> bang nam trong view goc, an o app iPhone", config, rw);
        return nil;
    }
    w = rw;
    SCPCMakePassThrough(w);   // thanh ti le khong co lop phu: cho trong cham xuyen xuong o / CarPlay
    w.windowLevel = SCPC_TRAY_LEVEL;
    w.backgroundColor = [UIColor clearColor];
    w.hidden = NO;
    self.trayWindow = w;
    SCPLog("CarSplit: cua so bang bo cuc %@ muc %.0f", NSStringFromCGRect(w.bounds), w.windowLevel);
    return w;
}

- (void)showLayoutPanelForApp:(NSString *)app
{
    [self collapseAppTray];
    UIView *parent = [self tabParent];
    if (!parent || ![SCPPrefs enabled]) return;
    self.layoutApp = app;
    CGRect area = [self appAreaInParent:parent];
    UIWindow *host = [self trayWindowForParent:parent];   // nil -> bang trong view goc nhu cu (phai an o app iPhone)
    self.trayOverlay = (host != nil);

    // Lop phu trong suot chi tren vung app (HarmonyOS: khong to toi, khong che dock): cham ra ngoai bang -> thu lai.
    // Cua so rieng cho cham xuyen o cho trong (SCPCMakePassThrough) nen dock van bam duoc.
    UIView *shield = [[UIView alloc] initWithFrame:host ? [parent convertRect:area toView:nil] : area];
    shield.backgroundColor = [UIColor clearColor];
    [shield addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(collapseAppTray)]];
    [host ?: parent addSubview:shield];
    self.trayShield = shield;
    [self publishBusy];
    // App CarBridge dang mo toan man: CBWindow (SpringBoard) nam tren moi view CarPlay nen che mat bang -> an CBWindow
    // trong luc bang mo, hien lai khi bang dong (collapseAppTray)
    if (!host && !self.active && self.soloHostedBundle) [self setFullscreenBridgeHidden:YES bundle:self.soloHostedBundle];

    BOOL v = [self vertical];
    NSArray<NSString *> *titles = nil;
    NSArray<NSArray<NSDictionary *> *> *sections = [self panelSections:&titles];
    int current = self.active ? [self layoutID] : 0;
    // Hang bo cuc: o nao se co app thi hien logo app do, o trong hien dau cong. Dang chia: app dang nam trong
    // tung o; dang mo 1 app toan man (app != nil): app do o o 1; man chinh: moi o deu la dau cong.
    NSMutableArray *slotApps = [NSMutableArray array];
    if (self.active) for (SCPCarPane *pp in self.slots) [slotApps addObject:(pp.vc && pp.bundleID) ? pp.bundleID : [NSNull null]];
    else if (app) [slotApps addObject:app];
    // Chi icon, khong chu: moi hang = icon muc (bo cuc / gan day / yeu thich) + cac hinh bo cuc
    NSDictionary *sectionName = @{@"layouts": SCPCT(@"Bố cục", @"Layouts"), @"recent": SCPCT(@"Gần đây", @"Recent"),
                                  @"favorite": SCPCT(@"Yêu thích", @"Favorites")};
    // O bo cuc to (84 x 56pt, hinh 72 x 40) de cham trung khi xe chay
    CGFloat pad = 10, iconCol = 32, rowH = 56, cellW = 84, imgW = 72, imgH = 40, rowGap = 6;
    NSUInteger cols = 1;
    for (NSArray *sec in sections) cols = MAX(cols, sec.count);
    CGFloat exitW = 52;   // nut thoat cuoi hang dau
    CGFloat w = pad * 2 + iconCol + cols * cellW + exitW, h = pad * 2 + sections.count * rowH + (sections.count - 1) * rowGap;
    h = MIN(h, area.size.height - 12);
    CGFloat contentW = w;
    w = MIN(w, area.size.width - 16);   // man xe hep / doc: bang cuon ngang
    CGRect pf = CGRectMake(CGRectGetMidX(area) - w / 2, CGRectGetMinY(area) + 6, w, h);   // phia tren, can giua vung app
    if (host) pf = [parent convertRect:pf toView:nil];   // cua so rieng phu kin man xe nhu cua so chinh -> cung toa do man xe
    // Kieu HarmonyOS: the kinh mo mong (nhin xuyen), bo goc lon lien tuc, vien sang manh, bong mem
    UIView *panel = [[UIView alloc] initWithFrame:pf];
    panel.layer.cornerRadius = 24;
    panel.layer.cornerCurve = kCACornerCurveContinuous;
    panel.layer.shadowColor = SCPCShadow().CGColor;
    panel.layer.shadowOpacity = 0.3; panel.layer.shadowRadius = 24; panel.layer.shadowOffset = CGSizeMake(0, 8);
    UIVisualEffectView *glass = SCPCGlassView();
    glass.frame = panel.bounds;
    SCPCMesh(glass);   // nen logo 4 mau tren kinh mo (nguoi dung: khong nen trang duc)
    glass.layer.cornerRadius = 24;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    [panel addSubview:glass];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:panel.bounds];   // man xe thap: cuon duoc
    scroll.showsVerticalScrollIndicator = NO;
    scroll.delegate = self;   // cuon bang -> hen gio thu lai tinh tu dau
    [glass.contentView addSubview:scroll];

    NSMutableArray *choices = [NSMutableArray array], *cells = [NSMutableArray array];
    CGFloat y = pad;
    for (NSUInteger si = 0; si < sections.count; si++) {
        UIImageView *head = [[UIImageView alloc] initWithImage:SCPCGlyph(titles[si], 18, NO)];
        head.tintColor = SCPCInk2();
        head.center = CGPointMake(pad + iconCol / 2, y + rowH / 2);
        head.accessibilityLabel = (si == 0 && self.active) ? SCPCT(@"Đổi bố cục", @"Change layout") : sectionName[titles[si]];
        [scroll addSubview:head];
        NSArray<NSDictionary *> *items = sections[si];
        CGFloat x0 = pad + iconCol;
        if (!items.count) {   // "Gan day" chua co gi: o vien net dut mo
            UIView *ph = [[UIView alloc] initWithFrame:CGRectMake(x0 + (cellW - imgW) / 2, y + (rowH - imgH) / 2, imgW, imgH)];
            CAShapeLayer *dash = [CAShapeLayer layer];
            dash.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(ph.bounds, 0.5, 0.5) cornerRadius:6].CGPath;
            dash.fillColor = nil;
            dash.strokeColor = [SCPCInk() colorWithAlphaComponent:0.25].CGColor;
            dash.lineWidth = 1; dash.lineDashPattern = @[@3, @3];
            [ph.layer addSublayer:dash];
            ph.accessibilityLabel = SCPCT(@"Chia màn xong sẽ hiện ở đây", @"Your splits will show up here");
            [scroll addSubview:ph];
            y += rowH + rowGap;
            continue;
        }
        for (NSUInteger k = 0; k < items.count; k++) {
            NSDictionary *c = items[k];
            int layoutID = [c[@"layout"] intValue];
            UIButton *b = [SCPCButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(x0 + k * cellW, y, cellW, rowH);
            b.tag = (NSInteger)choices.count;
            b.accessibilityLabel = c[@"name"];
            [choices addObject:c];
            [b addTarget:self action:@selector(panelChoiceTapped:) forControlEvents:UIControlEventTouchUpInside];
            BOOL currentLayout = (si == 0 && layoutID == current);
            SCPCOptionTile(b);   // nen trong + khung trang manh tach tung bo cuc
            if (currentLayout) SCPCSelectRing(b, YES);   // bo cuc dang dung: vien cau vong + quang, nen van trong
            NSArray *picApps = c[@"apps"] ?: slotApps;
            UIImageView *iv = [[UIImageView alloc] initWithImage:SCPCLayoutImage(layoutID, v, CGSizeMake(imgW, imgH), picApps, currentLayout)];
            iv.center = CGPointMake(cellW / 2, rowH / 2);
            iv.userInteractionEnabled = NO;
            [b addSubview:iv];
            [scroll addSubview:b];
            [cells addObject:b];
        }
        if (si == 0) {   // nut thoat chia man, tach khoi cac bo cuc bang 1 vach mo
            CGFloat px = pad + iconCol + cols * cellW;
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(px + 2, y + 10, 1, rowH - 20)];
            sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.95];
            [scroll addSubview:sep];
            UIButton *exitBtn = SCPCRoundButton(SCPCGlyph(@"exit", 20, NO), self, @selector(exitTapped));
            exitBtn.tintColor = SCPCDanger();
            SCPCTile(exitBtn, exitBtn.bounds.size.width / 2);   // nut thoat: o kinh trang, chi hinh mau do
            exitBtn.center = CGPointMake(px + 4 + (exitW - 4) / 2, y + rowH / 2);
            exitBtn.accessibilityLabel = self.active ? SCPCT(@"Thoát chia màn", @"Exit split") : SCPCT(@"Đóng", @"Close");
            NSString *keep = [self exitKeepBundle];
            UIImage *keepIcon = keep ? SCPCAppIcon(keep) : nil;
            if (keepIcon) {   // icon nho o goc: app nay se o lai toan man
                UIImageView *kv = [[UIImageView alloc] initWithFrame:CGRectMake(exitBtn.bounds.size.width - 15, exitBtn.bounds.size.height - 15, 16, 16)];
                kv.image = keepIcon;
                SCPCStyleIcon(kv);
                kv.layer.borderWidth = 1;
                kv.layer.borderColor = [UIColor whiteColor].CGColor;
                kv.userInteractionEnabled = NO;
                [exitBtn addSubview:kv];
            }
            [scroll addSubview:exitBtn];
            [cells addObject:exitBtn];
        }
        y += rowH + rowGap;
    }
    y += pad - rowGap;
    scroll.contentSize = CGSizeMake(contentW, y);
    self.panelChoices = choices;

    [host ?: parent addSubview:panel];
    self.tray = panel;
    [self pushHostFramesLive:NO];   // dang chia: o app iPhone nhuong cho bang (hostFrameForPane xet self.tray -> phai dat tray truoc;
                                    // log 10/10 22:48: goi truoc khi dat tray nen o YouTube van de len bang)
    // Cua so host an thi o app iPhone chi con nen den / app toan man lo man chinh (log 10/10 22:59) -> the icon app nhu luc
    // thanh ti le de len o (addCoverToPane); app toan man: the icon phu ca vung app, duoi lop phu cua bang
    if (!host) for (SCPCarPane *hp in [self hostedPanes]) [self addCoverToPane:hp];
    if (!host && !self.active && self.soloHostedBundle) {
        [self.trayCover removeFromSuperview];
        UIView *cover = [[UIView alloc] initWithFrame:area];
        cover.backgroundColor = SCPCPastel();
        cover.userInteractionEnabled = NO;
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
        iv.image = SCPCAppIcon(self.soloHostedBundle);
        SCPCStyleIcon(iv);
        iv.center = CGPointMake(cover.bounds.size.width / 2, cover.bounds.size.height / 2);
        [cover addSubview:iv];
        [parent addSubview:cover];
        [self raiseView:cover];
        self.trayCover = cover;
    }
    [self raiseView:shield];
    [self raiseView:panel];
    // Hien kieu HarmonyOS: bang nho ra tu mep tren + phong nhe theo lo xo, cac muc mo + troi len lan luot
    panel.alpha = 0;
    panel.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, -18), 0.92, 0.92);   // nho ra tu mep tren
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ panel.alpha = 1; panel.transform = CGAffineTransformIdentity; } completion:nil];
    NSInteger ci = 0;
    for (UIView *c in cells) {
        c.alpha = 0; c.transform = CGAffineTransformMakeTranslation(0, 12);
        [UIView animateWithDuration:0.45 delay:0.06 + ci++ * 0.025 usingSpringWithDamping:0.85 initialSpringVelocity:0.3
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ c.alpha = 1; c.transform = CGAffineTransformIdentity; } completion:nil];
    }
    [self restartTrayTimer];
    NSMutableArray *shown = [NSMutableArray array];   // tung hang: ma bo cuc cua moi o (2 / 3 / 13 / 31 ...)
    for (NSArray<NSDictionary *> *sec in sections) [shown addObject:[[sec valueForKey:@"layout"] componentsJoinedByString:@","]];
    SCPLog("CarSplit: bang bo cuc cho %@ (%@, %lu lua chon: %@)", app ?: (self.active ? @"doi bo cuc" : @"cap lan truoc"),
           [titles componentsJoinedByString:@" / "], (unsigned long)choices.count, [shown componentsJoinedByString:@" | "]);
}

- (void)panelChoiceTapped:(UIButton *)b
{
    @try { [self panelChoiceTappedUnsafe:b]; }
    @catch (NSException *e) { SCPLog("CarSplit: loi chon bo cuc %@\n%@", e, e.callStackSymbols); }
}

- (void)panelChoiceTappedUnsafe:(UIButton *)b
{
    NSDictionary *c = (b.tag >= 0 && b.tag < (NSInteger)self.panelChoices.count) ? self.panelChoices[b.tag] : nil;
    if (!c) return;
    int layoutID = [c[@"layout"] intValue];
    NSArray *apps = c[@"apps"];
    if (!apps) { [self layoutChosenID:layoutID]; return; }
    NSString *app = self.layoutApp;
    self.layoutApp = nil;
    [self collapseAppTray];
    SCPLog("CarSplit: mo lai %@ (bo cuc %d, app %@, thay cho %@)", c[@"name"], layoutID, apps, app ?: @"-");
    [self openSetupLayout:layoutID apps:apps];
}

// App theo tung o cua 1 bo cuc yeu thich (NSNull = o trong / app khong con tren CarPlay), nil neu khong co app nao
- (NSArray *)favoriteApps:(NSDictionary *)f
{
    if (!f) return nil;
    int layoutID = [f[@"layout"] intValue];
    int n = SCPCPanesForLayout(layoutID);
    NSArray *keys = @[@"left", @"right", @"third"];
    NSMutableArray *apps = [NSMutableArray array];
    BOOL any = NO;
    for (int i = 0; i < n; i++) {
        NSString *bid = f[keys[i]];
        if (bid && [self isCarPlayApp:bid]) { [apps addObject:bid]; any = YES; }
        else [apps addObject:[NSNull null]];
    }
    return any ? apps : nil;
}

// Siri / Shortcuts omnicar://splitscreen/fav?n=1
- (void)openFavorite:(NSInteger)index
{
    NSDictionary *f = [SCPPrefs favorite:index];
    NSArray *apps = [self favoriteApps:f];
    SCPLog("CarSplit: bo cuc yeu thich %ld: %@", (long)index, f);
    if (apps) [self openSetupLayout:[f[@"layout"] intValue] apps:apps];
}

// Mo dung 1 cach chia (gan day / yeu thich). Dang chia -> doi bo cuc va thay app theo thu tu o.
- (void)openSetupLayout:(int)layoutID apps:(NSArray *)apps
{
    if (self.active) [self switchToLayout:layoutID];
    else {
        self.suppressReopen = YES;   // app dang toan man khong tu vao o 1, cac o lay dung app cua cach chia
        BOOL ok = [self activateWithLayout:layoutID];
        self.suppressReopen = NO;
        if (!ok) return;
    }
    if (layoutID == 2 && apps.count >= 2 && [apps[0] isKindOfClass:[NSString class]] && [apps[1] isKindOfClass:[NSString class]]) {
        CGFloat saved = [SCPPrefs ratioForPairLeft:apps[0] right:apps[1]];
        if (saved >= 0.2 && saved <= 0.8) self.fractions = [NSMutableArray arrayWithObjects:@(saved), @(1 - saved), nil];
    }
    [self openAppsInOrder:apps];
}

// Nut thoat trong bang: dang chia -> thoat chia man, app o dang chon ve toan man (khong co app -> man chinh).
// Chua chia -> chi dong bang.
// App duoc giu toan man khi thoat chia: o dang chon (cham gan nhat, app vua vao o, o vua chieu CarBridge),
// khong co thi o dau tien co app (ca cua so noi)
- (NSString *)exitKeepBundle
{
    if (!self.active) return nil;
    NSString *keep = nil;
    if (self.focusedSlot >= 0 && self.focusedSlot < [self paneCount]) keep = self.slots[self.focusedSlot].bundleID;
    if (!keep) for (SCPCarPane *p in [self allPanes]) if (p.vc && p.bundleID) { keep = p.bundleID; break; }
    return keep;
}

// omnicar://splitscreen/picker khi dang chia: bang chon app cho o dang chon (truoc day lenh nay dong split)
- (void)showPickerForFocusedPane
{
    if (!self.active) { [self showPickerForSlot:-1]; return; }
    int s = (self.focusedSlot >= 0 && self.focusedSlot < [self paneCount]) ? self.focusedSlot : [self autoSlot];
    [self showPickerForSlot:s];
    SCPCarPane *p = [self paneAtSlot:s];
    if (p.picker) { self.pickerSheetPane = p; [self refreshPickerSheetSoon]; }
}

- (void)exitTapped
{
    @try {
        [self collapseAppTray];
        if (!self.active) { SCPLog("CarSplit: nut thoat (chua chia) -> dong bang"); return; }
        NSString *keep = [self exitKeepBundle];
        SCPLog("CarSplit: nut thoat -> thoat chia man%@", keep ? [NSString stringWithFormat:@", %@ ve toan man", keep] : @"");
        if (keep) [self soloBundle:keep]; else [self closeGoingHome:YES];
    } @catch (NSException *e) { SCPLog("CarSplit: loi nut thoat %@\n%@", e, e.callStackSymbols); }
}

// 3 lan dau chia man: moi lan 1 meo ve thao tac khong nhin thay duoc (cham 2 lan vach, keo •••, keo sat mep)
- (void)showTipSoon
{
    NSInteger n = [SCPPrefs tipCount];
    if (n >= 3) return;
    NSArray *tips = @[SCPCT(@"Mẹo: chạm 2 lần vào vạch chia để đổi chỗ 2 ô", @"Tip: double-tap a divider to swap the two panes"),
                      SCPCT(@"Mẹo: giữ và kéo ••• thả lên ô khác để đổi chỗ", @"Tip: drag ••• onto another pane to swap them"),
                      SCPCT(@"Mẹo: kéo vạch chia sát mép để đóng ô đó", @"Tip: drag a divider to the edge to close that pane")];
    [SCPPrefs setTipCount:n + 1];
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(3.0, ^{ if (weakSelf.active) [weakSelf toast:tips[n] duration:4.5]; });
}

// Cham trang popup chon app: trang dang xem la vien dai 16pt mau nhan, cac trang khac cham 6pt mau muc mo, can giua
- (void)layoutPickerDotsForPage:(NSInteger)page
{
    UIView *dots = self.pickerDots;
    if (!dots) return;
    NSArray<UIView *> *ds = dots.subviews;
    CGFloat gap = 6, total = gap * (ds.count - 1);
    for (NSUInteger k = 0; k < ds.count; k++) total += (k == (NSUInteger)page) ? 16 : 6;
    CGFloat x = (dots.bounds.size.width - total) / 2, cy = dots.bounds.size.height / 2;
    for (NSUInteger k = 0; k < ds.count; k++) {
        CGFloat dw = (k == (NSUInteger)page) ? 16 : 6;
        ds[k].frame = CGRectMake(x, cy - 3, dw, 6);
        ds[k].backgroundColor = (k == (NSUInteger)page) ? SCPCAccent() : [SCPCInk() colorWithAlphaComponent:0.2];
        x += dw + gap;
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)sv
{
    if (!self.pickerDots || ![sv isDescendantOfView:self.pickerSheet] || sv.bounds.size.width < 1) return;
    NSInteger page = (NSInteger)lround(sv.contentOffset.x / sv.bounds.size.width);
    page = MAX(0, MIN(page, (NSInteger)self.pickerDots.subviews.count - 1));
    if (self.pickerDots.tag == page + 1) return;
    self.pickerDots.tag = page + 1;
    [UIView animateWithDuration:0.25 animations:^{ [self layoutPickerDotsForPage:page]; }];
}

// Bang nut Split Screen: dang cuon thi khong tu thu lai
- (void)scrollViewWillBeginDragging:(UIScrollView *)sv
{
    if (self.tray && [sv isDescendantOfView:self.tray]) [self restartTrayTimer];
}

- (void)restartTrayTimer
{
    [self.trayTimer invalidate];
    __weak SCPCarSplit *weakSelf = self;
    self.trayTimer = [NSTimer scheduledTimerWithTimeInterval:SCPC_TRAY_IDLE repeats:NO block:^(NSTimer *t) { [weakSelf collapseAppTray]; }];
}

- (void)collapseAppTray
{
    __weak SCPCarSplit *weakSelf = self;
    [self.trayTimer invalidate]; self.trayTimer = nil;
    UIView *tray = self.tray, *shield = self.trayShield;
    self.tray = nil; self.trayShield = nil;
    [self publishBusy];
    [self setFullscreenBridgeHidden:NO bundle:nil];
    [self pushHostFramesLive:NO];   // bang dong: o app iPhone hien lai
    if (!self.resizing && !self.ratioMenu) for (SCPCarPane *hp in [self hostedPanes]) [self removeCoverFromPane:hp];
    UIView *tc = self.trayCover;
    self.trayCover = nil;
    if (tc) [UIView animateWithDuration:0.2 animations:^{ tc.alpha = 0; } completion:^(BOOL f) { [tc removeFromSuperview]; }];
    if (!tray && !shield) return;
    UIWindow *tw = self.trayWindow;
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{   // thu ve mep tren + nho lai
        tray.alpha = 0; tray.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, -14), 0.94, 0.94);
    } completion:^(BOOL f) {
        [tray removeFromSuperview]; [shield removeFromSuperview];
        if (tw && !weakSelf.tray && !weakSelf.ratioMenu && !weakSelf.pickerSheet) tw.hidden = YES;   // khong con gi tren cua so -> an (giu lai cho lan sau)
    }];
}

// Bang bo cuc mo tren app iPhone toan man (App Bridge): cua so host che mat bang -> an (khung 0) / hien lai
- (void)setFullscreenBridgeHidden:(BOOL)hidden bundle:(NSString *)bid
{
    NSString *solo = self.soloHostedBundle;
    if (!solo || hidden == self.trayHidesBridge) return;
    self.trayHidesBridge = hidden;
    CGRect r = hidden ? CGRectZero : self.soloHostedFrame;
    SCPLog("AppBridge: %@ app toan man %@ (bang bo cuc)", hidden ? @"an" : @"hien lai", solo);
    [self hostPost:AB_NOTIF_FRAME info:@{@"identifier": solo, @"x": @(r.origin.x), @"y": @(r.origin.y),
                                         @"w": @(r.size.width), @"h": @(r.size.height), @"live": @NO, @"handle": @NO}];
}

// Chon bo cuc mac dinh. Dang chia -> doi bo cuc. Dang mo 1 app toan man -> app do vao o 1, cac o con lai hien
// bang chon. Man chinh -> moi o deu hien bang chon.
// Xe lai tay phai: Cai dat (SPL_KEY_DRIVER_SIDE) hoac tu phien CarKit (Core ghi configuration vao diagCar)
static BOOL SCPCRightHandDrive(void)
{
    NSInteger side = [OMCPref(SPL_KEY_DRIVER_SIDE, @0) integerValue];
    if (side == 1 || side == 2) return side == 2;
    NSDictionary *car = OMCPref(OMC_KEY_DIAG_CAR, nil);
    NSDictionary *cfg = [car isKindOfClass:[NSDictionary class]] ? car[@"configuration"] : nil;
    if (![cfg isKindOfClass:[NSDictionary class]]) return NO;
    for (NSString *k in @[@"rightHandDrive", @"_rightHandDrive", @"isRightHandDrive"]) {
        id v = cfg[k];
        if ([v respondsToSelector:@selector(boolValue)]) return [v boolValue];
    }
    return NO;
}

- (void)layoutChosenID:(int)layoutID
{
    NSString *app = self.layoutApp;
    self.layoutApp = nil;
    [self collapseAppTray];
    if (self.active) { [self switchToLayout:layoutID]; return; }
    SCPLog("CarSplit: chon bo cuc %d cho %@", layoutID, app ?: @"man chinh (moi o trong)");
    if (!app) {   // man chinh: moi o deu trong, hien bang chon app (dung nhu hinh dau cong trong bang)
        if (![self activateWithLayout:layoutID]) return;
        [self showPickersForEmptySlots];
        return;
    }
    if (![self activateWithLayout:layoutID]) return;   // app dang mo toan man: activate tu mo lai no vao o 1
    // Lai tay phai: app dang dung vao o sat ghe lai (o cuoi ben phai) khi chia ngang deu
    int first = (SCPCRightHandDrive() && ![self vertical] && ![self mainStack]) ? [self paneCount] - 1 : 0;
    if (first != 0 && [self.slots[0].bundleID isEqualToString:app]) {
        SCPLog("CarSplit: lai tay phai -> %@ vao o %d", app, first);
        [self swapSlot:0 with:first];
    }
    [self openApp:app slot:first];
    for (int s = 0; s < [self paneCount]; s++) if (![self slotOccupied:s]) [self showPickerForSlot:s];
}

// ---------------------------------------------------------------------
//  App Bridge (app iPhone tren CarPlay, thay CarBridge): SpringBoard host scene cua app trong cua so rieng tren
//  man xe (Features/AppBridge), cua so nam tren moi view cua CarPlay. O ben CarPlay giu 1 VC gia (SCPHostedAppVC)
//  de bo cuc / thanh nut / doi cho / nho cap dung chung voi app CarPlay, va gui khung o (toa do man xe) cho
//  SpringBoard moi khi bo cuc doi. Thanh "•••" cua o do SpringBoard ve tren app; cham -> AB_NOTIF_HANDLE_TAP ->
//  hien thanh nut, cua so host lui xuong duoi thanh nut.
// ---------------------------------------------------------------------
// Canh giap o khac: cua so host phu sat khe (khong lui vao) nhung dai SCPC_BRIDGE_PASS pt sat mep cho cham xuyen xuong
// CarPlay de keo vach / cham tay nam duoc (SpringBoard bo qua cham trong dai do)
#define SCPC_BRIDGE_PASS   10.0

// App iPhone App Bridge dua len xe: danh sach nguoi dung chon trong Settings > App Bridge > App tren man xe
// (AB_KEY_APPS), chi giu app con cai. Chua chon gi = khong co app iPhone nao. Cache 60s, doi prefs thi lam lai.
static NSSet<NSString *> *SCPCPhoneAppSet(void)
{
    static NSSet *set; static CFAbsoluteTime at; static int token; static dispatch_once_t once;
    dispatch_once(&once, ^{
        notify_register_dispatch("com.anlai.omnicar/prefschanged", &token, dispatch_get_main_queue(), ^(int t) { at = 0; });
    });
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (set && at > 0 && now - at < 60) return set;
    at = now;
    OMCPrefsSync();
    id chosen = OMCPref(AB_KEY_APPS, nil);
    NSMutableSet *s = [NSMutableSet set];
    if ([chosen isKindOfClass:[NSArray class]] && [chosen count]) {
        NSSet *want = [NSSet setWithArray:chosen];
        Class ws = objc_getClass("LSApplicationWorkspace");
        NSArray *all = ws ? objcInvoke(objcInvoke(ws, @"defaultWorkspace"), @"allInstalledApplications") : nil;
        for (id proxy in all) {
            NSString *bid = objcInvoke(proxy, @"bundleIdentifier");
            if (bid.length && [want containsObject:bid]) [s addObject:bid];
        }
    }
    set = s;
    return set;
}

// Ten giu tu thoi CarBridge: app iPhone duoc dua len xe qua App Bridge (khong phai app CarPlay)
static BOOL SCPCIsBridgedApp(NSString *bid)
{
    if (!bid.length || !OMCFeatureEnabled(AB_FEATURE)) return NO;
    if (SCPIsInjectedPhoneApp(bid)) return YES;   // icon chen vao thu vien CarPlay: info gia, khong phai app CarPlay that
    if (SCPCInfoIsCarPlayApp(SCPCAppInfo(bid))) return NO;
    return [SCPCPhoneAppSet() containsObject:bid];
}

// Danh sach app iPhone cho bang chon / Settings: @{ id, name }, xep theo ten
static NSArray<NSDictionary *> *SCPCPhoneApps(void)
{
    NSMutableArray *out = [NSMutableArray array];
    if (!OMCFeatureEnabled(AB_FEATURE)) return out;
    Class ws = objc_getClass("LSApplicationWorkspace");
    NSArray *all = ws ? objcInvoke(objcInvoke(ws, @"defaultWorkspace"), @"allInstalledApplications") : nil;
    NSSet *set = SCPCPhoneAppSet();
    for (id proxy in all) {
        NSString *bid = objcInvoke(proxy, @"bundleIdentifier");
        if (![set containsObject:bid] || SCPCInfoIsCarPlayApp(SCPCAppInfo(bid))) continue;
        NSString *name = [proxy respondsToSelector:NSSelectorFromString(@"localizedName")] ? objcInvoke(proxy, @"localizedName") : nil;
        [out addObject:@{@"id": bid, @"name": name.length ? name : bid}];
    }
    [out sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
    return out;
}

- (NSArray<SCPCarPane *> *)hostedPanes
{
    NSMutableArray *a = [NSMutableArray array];
    for (SCPCarPane *p in [self allPanes]) if (SCPCIsHostedVC(p.vc)) [a addObject:p];
    return a;
}

// O dau tien dang host app iPhone (thong bao tranh o nay: cua so host nam tren moi view CarPlay)
- (SCPCarPane *)bridgedPane
{
    return [self hostedPanes].firstObject;
}

- (void)hostPost:(NSString *)name info:(NSDictionary *)info
{
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:name object:nil userInfo:info];
}

// Khung cua so host (toa do man xe) cho o; CGRectZero = an (o dang an / bang bo cuc dang mo / bang chon / thanh ti le de len)
- (CGRect)hostFrameForPane:(SCPCarPane *)p
{
    if (!self.active || !p.vc || p.picker || p.view.alpha < 0.5 || p.view.bounds.size.width < 20 || !p.view.window) return CGRectZero;
    if (self.tray && !self.trayOverlay) return CGRectZero;   // bang bo cuc ve trong view goc CarPlay (khong co cua so rieng) -> nhuong cho
    if (self.pickerSheet && !self.pickerSheetOverlay) return CGRectZero;   // bang chon app ve trong container (khong co cua so rieng) -> nhuong cho
    if (self.ratioMenu && !self.ratioOverlay && CGRectIntersectsRect(CGRectInset(self.ratioMenu.frame, -6, -6), p.view.frame)) return CGRectZero;
    // Khung day du ca khi thanh nut dang hien: thanh nut do SpringBoard ve de len app (bar trong hostBarInfoForPane), app
    // xuong, de noi dung app khong bi day / bo cuc lai moi lan mo thanh nut
    return [p.view convertRect:p.view.bounds toView:nil];
}

// Thanh nut cua o app iPhone do SpringBoard ve de len app (thanh ve ben CarPlay nam duoi cua so host, khong thay):
// bar = dang hien, pop = 1 nut "noi" / 2 nut "ghim" (cua so noi), popDim = khong noi ra duoc (bam thi bao ly do),
// single = o nay dang chay 1 man hinh (nut "Chay 1 man hinh" doi thanh "Chia man hinh")
- (NSDictionary *)hostBarInfoForPane:(SCPCarPane *)p
{
    BOOL isFloat = (p == self.floatPane);
    BOOL canPop = isFloat ? (p.vc && [self paneCount] < SCPC_MAX_PANES) : [self canPopOutPane:p];
    BOOL single = self.zoomedSlot && self.zoomedSlot.intValue == p.slot;
    return @{@"bar": @(!p.bar.hidden), @"pop": @(isFloat ? 2 : 1), @"popDim": @(!canPop), @"single": @(single)};
}

// Dai sat mep cua so host cho cham xuyen xuong CarPlay (canh giap o khac: keo vach; canh giap mep vung app: 0)
- (UIEdgeInsets)hostPassInsetsForPane:(SCPCarPane *)p
{
    CGRect f = p.view.frame;
    CGSize box = p.view.superview.bounds.size;
    return UIEdgeInsetsMake(CGRectGetMinY(f) > 1 ? SCPC_BRIDGE_PASS : 0, CGRectGetMinX(f) > 1 ? SCPC_BRIDGE_PASS : 0,
                            CGRectGetMaxY(f) < box.height - 1 ? SCPC_BRIDGE_PASS : 0, CGRectGetMaxX(f) < box.width - 1 ? SCPC_BRIDGE_PASS : 0);
}

- (NSDictionary *)hostFrameInfo:(CGRect)r pane:(SCPCarPane *)p live:(BOOL)live handle:(BOOL)handle
{
    UIEdgeInsets pi = p ? [self hostPassInsetsForPane:p] : UIEdgeInsetsZero;
    NSMutableDictionary *d = [@{@"identifier": p.bundleID ?: @"", @"x": @(r.origin.x), @"y": @(r.origin.y), @"w": @(r.size.width), @"h": @(r.size.height),
                                @"live": @(live), @"handle": @(handle), @"pt": @(pi.top), @"pl": @(pi.left), @"pb": @(pi.bottom), @"pr": @(pi.right)} mutableCopy];
    if (p) [d addEntriesFromDictionary:[self hostBarInfoForPane:p]];
    // Bo goc nhu o CarPlay (SCPC_RADIUS o goc giap o khac, cua so noi 4 goc): cua so host ve cung goc
    if (p) { d[@"r"] = @(p.view.layer.cornerRadius); d[@"corners"] = @((unsigned long long)p.view.layer.maskedCorners); }
    // Thanh "•••" lech sang phai nhu thanh cua o CarPlay khi o nam duoi vach ngang (cham tron cua vach o giua)
    if (p) d[@"hx"] = @([self handleShiftForPane:p]);
    if (p) d[@"front"] = @(p == self.floatPane);   // cua so noi app iPhone: SpringBoard dua len tren cac o app iPhone khac
    // Vung app cua man xe (khong tinh dock): ban phim xe trai theo ca vung nay du app dang o 1 o chia
    UIView *parent = [self tabParent];
    if (parent) {
        CGRect area = [parent convertRect:[self appAreaInParent:parent] toView:nil];
        d[@"ax"] = @(area.origin.x); d[@"ay"] = @(area.origin.y); d[@"aw"] = @(area.size.width); d[@"ah"] = @(area.size.height);
    }
    return d;
}

- (void)sendHostFrameForPane:(SCPCarPane *)p live:(BOOL)live
{
    if (!SCPCIsHostedVC(p.vc) || !p.bundleID) return;
    CGRect r = [self hostFrameForPane:p];
    BOOL handle = !CGRectIsEmpty(r);   // thanh "•••" luon hien, thanh nut (SpringBoard ve) nam duoi no
    BOOL bar = !p.bar.hidden;
    if (!live && CGRectEqualToRect(r, p.hostFrame) && handle == p.hostHandle && bar == p.hostBar) return;
    p.hostFrame = r; p.hostHandle = handle; p.hostBar = bar;
    [self hostPost:AB_NOTIF_FRAME info:[self hostFrameInfo:r pane:p live:live handle:handle]];
    [self publishKnobsSoon];   // gui kem cham tron (gom 1 lan/vong runloop): SpringBoard moi respring hay vua tao cua so cung co
}

// live: dang keo vach -> cua so chay theo tay, scene doi kich thuoc khi tha tay (live = NO)
- (void)pushHostFramesLive:(BOOL)live
{
    for (SCPCarPane *p in [self hostedPanes]) [self sendHostFrameForPane:p live:live];
}

// Mo app iPhone vao o: VC gia ben CarPlay + SpringBoard host app o dung khung cua o
- (void)hostApp:(NSString *)bid inPane:(SCPCarPane *)p
{
    if (p.vc) {
        if (SCPCIsHostedVC(p.vc)) [self hostClose:p.bundleID terminate:NO];
        else [self detachVC:p.vc background:YES];
        p.vc = nil; p.bundleID = nil;
    }
    SCPHostedAppVC *vc = [SCPHostedAppVC new];
    vc.bundleID = bid;
    vc.view.frame = p.host.bounds;
    vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [p.host addSubview:vc.view];
    p.vc = vc; p.bundleID = bid; p.sceneSize = CGSizeZero; p.hostFrame = CGRectNull; p.hostHandle = NO;
    if (p.slot != SCPC_FLOAT_SLOT) self.focusedSlot = p.slot;
    [self showLoaderInPane:p bundle:bid];
    SCPLog("AppBridge: host %@ vao o %d", bid, p.slot);
    [self rememberPair];
    [self rememberRecent];
    [self raise];
    [self relayoutAnimated:YES];
    __weak SCPCarSplit *weakSelf = self;
    __weak SCPCarPane *weakPane = p;
    SCPCAfter(0.05, ^{
        SCPCarSplit *me = weakSelf; SCPCarPane *pp = weakPane;
        if (!me.active || !pp || ![pp.bundleID isEqualToString:bid]) return;
        CGRect r = [me hostFrameForPane:pp];
        if (CGRectIsEmpty(r)) r = [pp.view convertRect:pp.view.bounds toView:nil];
        pp.hostFrame = r; pp.hostHandle = !CGRectIsEmpty(r); pp.hostBar = !pp.bar.hidden;
        [me hostPost:AB_NOTIF_OPEN info:[me hostFrameInfo:r pane:pp live:NO handle:pp.hostHandle]];
    });
    // Khong thay app len sau 8s -> bo the "dang mo" (app van co the toi muon)
    SCPCAfter(8.0, ^{ SCPCarPane *pp = weakPane; if (pp && [pp.bundleID isEqualToString:bid]) [weakSelf removeLoaderFromPane:pp animated:YES]; });
}

- (void)hostClose:(NSString *)bid terminate:(BOOL)terminate
{
    if (!bid.length) return;
    [self hostPost:AB_NOTIF_CLOSE info:@{@"identifier": bid, @"terminate": @(terminate)}];
}

// Cham tron cua cac vach -> SpringBoard ve lai len tren cua so App Bridge (cua so do nam tren CarPlay, che cham tron
// canh o app iPhone). Gom nhieu lan goi trong 1 vong runloop thanh 1 lan gui; chi gui khi co o app iPhone hoac vua het.
- (void)publishKnobsSoon
{
    static BOOL queued;
    if (queued) return;
    queued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        queued = NO;
        [self publishKnobsNow];
    });
}

- (void)publishKnobsNow
{
    static BOOL sentAny;
    BOOL hosted = NO;
    for (SCPCarPane *p in [self allPanes]) if (SCPCIsHostedVC(p.vc)) hosted = YES;
    NSMutableArray *knobs = [NSMutableArray array];
    if (self.active && hosted && !self.tray) {
        for (SCPCarDividerView *d in self.dividers) {
            UIView *k = d.knob;
            if (!k || k.hidden || d.alpha < 0.5 || !k.window) continue;
            CGPoint c = [d convertPoint:k.center toView:nil];
            BOOL on = !CGAffineTransformIsIdentity(k.transform);
            [knobs addObject:@[@(c.x), @(c.y), @(on), @(d.index)]];
        }
    }
    if (!knobs.count && !sentAny) return;
    sentAny = knobs.count > 0;
    [self hostPost:AB_NOTIF_KNOBS info:@{@"knobs": knobs}];
}

- (void)hostCloseAll
{
    // App dang chuyen sang toan man (soloBundle) giu lai: cua so cua no chi doi khung, khong dong roi mo lai
    NSString *keep = self.soloHostedBundle;
    [self hostPost:AB_NOTIF_CLOSEALL info:keep ? @{@"except": keep} : @{}];
}

// SpringBoard bao trang thai app dang host (AB_NOTIF_STATE): ready / failed / gone
- (void)hostedApp:(NSString *)bid state:(NSString *)state
{
    if (self.soloHostedBundle && [self.soloHostedBundle isEqualToString:bid]) {
        if ([state isEqualToString:@"ready"]) [self hideSoloCover];
        else { SCPLog("AppBridge: app toan man %@ %@", bid, state); [self endHostedSolo]; [self hideSoloCover]; }
        return;
    }
    SCPCarPane *p = [self paneForBundle:bid];
    if (!self.active || !p || !SCPCIsHostedVC(p.vc)) return;
    if ([state isEqualToString:@"ready"]) { [self removeLoaderFromPane:p animated:YES]; return; }
    SCPLog("AppBridge: %@ %@ -> dong o %d", bid, state, p.slot);
    if ([state isEqualToString:@"failed"])
        [self toast:[NSString stringWithFormat:SCPCT(@"Không mở được %@ trên xe", @"Couldn't show %@ on the car"), [self displayNameFor:bid]]];
    [self closeSlot:p.slot background:NO];
}

// SpringBoard bao: cham thanh "•••" ve tren app dang host -> hien / an thanh nut cua o do
- (void)bridgeHandleTapped:(NSString *)bid
{
    SCPCarPane *p = [self paneForBundle:bid];
    if (!self.active || !p) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL dbl = [self.lastBridgeTapBundle isEqualToString:bid] && now - self.lastBridgeTapAt < 0.35;
    self.lastBridgeTapBundle = dbl ? nil : bid;
    self.lastBridgeTapAt = now;
    if (dbl && p != self.floatPane) { [self toggleZoomForPane:p]; return; }   // lan 1 da mo thanh nut: toggleZoom dong lai
    [self setBarVisible:p.bar.hidden forPane:p];
}

// Nut tren thanh nut do SpringBoard ve de len app iPhone (AB_NOTIF_BAR_ACTION): cung viec voi 4 nut cua thanh CarPlay
- (void)bridgeBarAction:(NSString *)action forBundle:(NSString *)bid
{
    SCPCarPane *p = [self paneForBundle:bid];
    if (!self.active || !p) return;
    SCPLog("AppBridge: thanh nut %@ cua %@", action, bid);
    if ([action isEqualToString:@"replace"]) {
        [self setBarVisible:NO forPane:p];
        [self showPickerForSlot:p.slot];
    } else if ([action isEqualToString:@"full"]) {   // Chay 1 man hinh / Chia man hinh
        [self runSoloForPane:p];
    } else if ([action isEqualToString:@"pop"]) {    // Anh trong anh
        [self popOutPane:p];
    } else if ([action isEqualToString:@"bg"]) {     // Chay nen
        [self runBackgroundForPane:p];
    } else if ([action isEqualToString:@"close"]) {  // Tat han app
        [self runCloseForPane:p];
    }
}

// ---- App iPhone toan man (khong chia): host o ca vung app, man chinh CarPlay van o duoi ----
- (void)hostSolo:(NSString *)bid
{
    UIView *parent = [self tabParent];
    if (!parent) return;
    CGRect r = [parent convertRect:[self appAreaInParent:parent] toView:nil];
    self.soloHostedBundle = bid;
    self.soloHostedFrame = r;
    self.trayHidesBridge = NO;
    SCPLog("AppBridge: %@ toan man %@", bid, NSStringFromCGRect(r));
    [self hostPost:AB_NOTIF_OPEN info:@{@"identifier": bid, @"x": @(r.origin.x), @"y": @(r.origin.y), @"w": @(r.size.width), @"h": @(r.size.height)}];
    [self hostPost:AB_NOTIF_FRAME info:@{@"identifier": bid, @"x": @(r.origin.x), @"y": @(r.origin.y), @"w": @(r.size.width), @"h": @(r.size.height), @"live": @NO, @"handle": @NO}];
    [self refreshAppTabSoon];
}

- (void)endHostedSolo
{
    NSString *bid = self.soloHostedBundle;
    if (!bid) return;
    self.soloHostedBundle = nil;
    self.trayHidesBridge = NO;
    SCPLog("AppBridge: dong app toan man %@", bid);
    [self hostClose:bid terminate:NO];
}

// Nut Home cua CarPlay (hook _handleHomeEvent): app iPhone toan man -> dong
// Sau su kien Home: DashBoard co the van giu 1 VC "toan man" ma workspace cua no da coi la Home (VC split tra lai bang
// presentBaseViewController, log 10/10 17:47: Home khi dang chia -> man trang/den, currentBaseViewController van la GOFA).
// Con VC do ma split khong dung -> bao DashBoard dong no that de man chinh hien ra.
- (void)dismissStuckBaseSoon
{
    __weak SCPCarSplit *weakSelf = self;
    SCPCAfter(0.35, ^{
        SCPCarSplit *me = weakSelf;
        if (!me || me.soloHostedBundle) return;
        UIViewController *root = SCPCRootVC();
        UIViewController *cur = objcInvoke(root, @"currentBaseViewController");
        if (!cur) return;
        for (SCPCarPane *p in [me allPanes]) if (p.vc == cur) return;   // dang nam trong o: split lo
        SCPLog("CarSplit: DashBoard con giu %@ sau Home -> dong de hien man chinh", cur);
        SEL dis = NSSelectorFromString(@"dismissBaseViewControllerAnimated:completion:");
        if ([root respondsToSelector:dis]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(root, dis, YES, nil);
    });
}

- (void)homePressedDuringSplit:(BOOL)split
{
    // Chi sau Home luc dang chia: 1 app toan man thuong thi DashBoard tu dong; iOS 15 thu app ve icon lau hon 0.35s,
    // dismiss them lan nua lam logo app giat 1 lan (log 12/10 21:12)
    UIViewController *cur = objcInvoke(SCPCRootVC(), @"currentBaseViewController");
    if (split || (cur && cur == self.soloReturnedVC)) [self dismissStuckBaseSoon];
    self.soloReturnedVC = nil;
    // Home do chinh split gui khi tat split (soloBundle app iPhone): man chinh ve ben duoi, app toan man giu nguyen
    if (self.ignoreHomeOnce) { self.ignoreHomeOnce = NO; return; }
    if (self.soloHostedBundle) [self endHostedSolo];
}

// Cham icon app iPhone tren man chinh / dock CarPlay (icon do SCPAppIcons chen): dang chia -> vao o, khong thi toan man
- (BOOL)launchPhoneAppIfNeeded:(NSString *)bid
{
    if (!SCPCIsBridgedApp(bid)) return NO;
    SCPLog("AppBridge: cham icon %@ tren man chinh", bid);
    if (self.active) { [self openApp:bid slot:-1]; return YES; }
    if ([self.soloHostedBundle isEqualToString:bid]) return YES;
    [self endHostedSolo];
    [self showSoloCoverForBundle:bid];
    [self hostSolo:bid];
    return YES;
}

// ---------------------------------------------------------------------
//  Chua split: nut Split Screen tren dock CarPlay (tren nut Home) mo bang bo cuc; giu icon app 0.7s tren man
//  chinh cung vay. Tu mo split khi cam xe.
// ---------------------------------------------------------------------
#define SCPC_HOME_BTN 34.0
#define SCPC_DOCK_BTN 30.0    // nut Split Screen khi nam tren dock CarPlay
#define SCPC_DOCK_TOP 36.0    // dong ho + song / 4G o dau dai dock: khong day cum icon dock len qua day
#define SCPC_DOCK_MIN 22.0    // nut Split Screen tren dock nho nhat (khe tren nut Home hep)
static char kSCPCLongPressKey;

// Nut Split Screen tren dock CarPlay: chi la hinh 2 o canh nhau (chia doi man hinh), khong o nen, cung mau voi luoi
// app cua nut Home ngay duoi (anh template, tintColor = mau nut Home). Khung 1024, le 60.
static UIImage *SCPCSplitImage(CGFloat side)
{
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        // Nhu nut dock trong tools/preview/theme.html: 2 o 6 x 10 cach nhau 2 trong nut 26 (hinh 54% rong, 38% cao,
        // khe 14%), de o cho nho (22..30 pt) van thay 2 o chu khong thanh 1 cham
        CGContextScaleCTM(rc.CGContext, side / 1024.0, side / 1024.0);
        UIBezierPath *panes = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(236, 315, 236, 394) cornerRadius:78];
        [panes appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(552, 315, 236, 394) cornerRadius:78]];
        [[UIColor whiteColor] setFill];
        [panes fill];
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// O cua nut Split Screen tren dock: nen logo 4 mau dac, vien trang 1pt, quang tim nhat de noi tren dock den
static void SCPCDockTile(UIView *v, CGFloat radius)
{
    v.backgroundColor = [UIColor clearColor];
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.shadowColor = SCPCAccent().CGColor;
    v.layer.shadowOpacity = 0.35; v.layer.shadowRadius = 4; v.layer.shadowOffset = CGSizeMake(0, 1);
    UIImageView *mesh = [[UIImageView alloc] initWithImage:OMCLogoMeshImage(YES)];
    mesh.frame = v.bounds;
    mesh.contentMode = UIViewContentModeScaleToFill;
    mesh.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    mesh.layer.cornerRadius = radius;
    mesh.layer.cornerCurve = kCACornerCurveContinuous;
    mesh.layer.borderWidth = 1;
    mesh.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
    mesh.clipsToBounds = YES;
    mesh.userInteractionEnabled = NO;
    [v insertSubview:mesh atIndex:0];
}

// Mau luoi app cua nut Home (o vuong nho co backgroundColor, hoac anh template co tint) de nut Split Screen cung mau
static UIColor *SCPCViewInk(UIView *v, int depth)
{
    if (!v || depth > 6) return nil;
    for (UIView *c in v.subviews) {
        if (c.hidden || c.alpha < 0.05) continue;
        UIColor *bg = c.backgroundColor;
        if (bg && CGColorGetAlpha(bg.CGColor) > 0.3 && c.bounds.size.width <= 20 && c.bounds.size.height <= 20) return bg;
        if ([c isKindOfClass:[UIImageView class]] && ((UIImageView *)c).image.renderingMode == UIImageRenderingModeAlwaysTemplate) return c.tintColor;
        UIColor *ink = SCPCViewInk(c, depth + 1);
        if (ink) return ink;
    }
    return nil;
}

- (BOOL)atHomeScreen
{
    UIViewController *root = SCPCRootVC();
    return root && !self.active && [SCPPrefs enabled] && !objcInvoke(root, @"currentBaseViewController");
}

// Khung cum icon cua dock CarPlay (appDockViewController) trong toa do parent, Null neu khong thay
- (CGRect)dockClusterInParent:(UIView *)parent
{
    UIView *dock = nil;
    @try { id dockVC = objcInvoke(SCPCRootVC(), @"appDockViewController"); dock = dockVC ? objcInvoke(dockVC, @"view") : nil; } @catch (NSException *e) {}
    if (!dock.window || dock.hidden || !parent.window) return CGRectNull;
    UIScreen *screen = parent.window.screen ?: dock.window.screen;
    if (!screen) return CGRectNull;
    CGRect inScreen = [dock convertRect:dock.bounds toCoordinateSpace:screen.coordinateSpace];
    inScreen.origin.y -= dock.transform.ty;   // vi tri goc, chua tinh phan nut Split Screen da day cum icon len
    return [parent convertRect:inScreen fromCoordinateSpace:screen.coordinateSpace];
}

// Tim nut Home cua dock (DBStatusBarHomeButton): view co ten lop chua "Home", nho (20..70pt), nam trong dai dock.
// Tra ve khung phan hinh dang hien (luoi app, nho hon khung cham cua nut) de nut Split Screen nam sat ngay tren no.
static void SCPCFindHomeButton(UIView *v, UIView *parent, CGRect strip, int depth, UIView *skip, CGRect *best, UIView **bestView)
{
    if (!v || depth > 20 || v == skip || v.hidden || v.alpha < 0.05) return;
    NSString *cls = NSStringFromClass([v class]);
    if ([cls rangeOfString:@"Home" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        CGRect r = [parent convertRect:v.bounds fromView:v];
        if (r.size.width >= 20 && r.size.width <= 70 && r.size.height >= 20 && r.size.height <= 70
            && CGRectContainsPoint(CGRectInset(strip, -4, -4), CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r)))) {
            CGRect glyph = CGRectNull;
            for (UIView *c in v.subviews)
                if (!c.hidden && c.alpha >= 0.05 && c.bounds.size.height > 2) glyph = CGRectUnion(glyph, [parent convertRect:c.bounds fromView:c]);
            if (!CGRectIsNull(glyph) && CGRectContainsRect(CGRectInset(r, -1, -1), glyph)) r = glyph;
            if (CGRectIsNull(*best) || CGRectGetMinY(r) > CGRectGetMinY(*best)) { *best = r; if (bestView) *bestView = v; }   // lay nut thap nhat
            return;
        }
    }
    for (UIView *c in v.subviews) SCPCFindHomeButton(c, parent, strip, depth + 1, skip, best, bestView);
}

// Day cua dong ho / song / pin (_UIStatusBar*, _UIBattery*) o dau dai dock: cum icon dock khong duoc day len qua
static void SCPCStatusBottom(UIView *v, UIView *parent, CGRect strip, int depth, CGFloat *maxY)
{
    if (!v || depth > 20 || v.hidden || v.alpha < 0.05) return;
    NSString *cls = NSStringFromClass([v class]);
    if (([cls hasPrefix:@"_UIStatusBar"] || [cls hasPrefix:@"_UIBattery"]) && v.bounds.size.height < 40 && v.bounds.size.height > 2) {
        CGRect r = [parent convertRect:v.bounds fromView:v];
        if (CGRectContainsPoint(CGRectInset(strip, -4, -4), CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r)))
            && CGRectGetMidY(r) < CGRectGetMidY(strip))
            *maxY = MAX(*maxY, CGRectGetMaxY(r));
    }
    for (UIView *c in v.subviews) SCPCStatusBottom(c, parent, strip, depth + 1, maxY);
}

// Vi tri nut Split Screen: tren dock CarPlay (dai trai / phai), ngay duoi cum icon dock va tren nut Home. Khe khong du
// thi day cum icon len (khong de len dong ho / song / pin) va thu nho nut; van khong du thi goc tren phai vung app.
// *outShift = so pt can day cum icon dock len. Ghi log moi lan doi cho.
- (CGPoint)launcherCenterInParent:(UIView *)parent size:(CGFloat *)outSize shift:(CGFloat *)outShift
{
    UIViewController *root = SCPCRootVC();
    UIView *content = objcInvoke(root, @"contentView") ?: root.view;
    CGRect full = [parent convertRect:content.bounds fromView:content];
    CGRect area = [self appAreaInParent:parent];
    CGFloat leftW = CGRectGetMinX(area) - CGRectGetMinX(full), rightW = CGRectGetMaxX(full) - CGRectGetMaxX(area);
    CGRect strip = CGRectNull;
    if (leftW >= 30) strip = CGRectMake(CGRectGetMinX(full), CGRectGetMinY(full), leftW, full.size.height);
    else if (rightW >= 30) strip = CGRectMake(CGRectGetMaxX(area), CGRectGetMinY(full), rightW, full.size.height);

    CGFloat size = SCPC_HOME_BTN, shift = 0;
    CGPoint c = CGPointMake(CGRectGetMaxX(area) - size / 2 - 8, CGRectGetMinY(area) + size / 2 + 8);
    NSString *where = @"goc tren phai vung app (khong co dock doc)";
    CGRect cluster = CGRectNull, home = CGRectNull;
    if (!CGRectIsNull(strip)) {
        size = MIN(SCPC_DOCK_BTN, strip.size.width - 8);
        CGFloat cx = CGRectGetMidX(strip);
        cluster = CGRectIntersection([self dockClusterInParent:parent], strip);
        // Dai dock (status bar CarPlay) co the khong nam duoi root.view -> quet tu window cua dock
        UIView *dock = nil;
        @try { id dockVC = objcInvoke(root, @"appDockViewController"); dock = dockVC ? objcInvoke(dockVC, @"view") : nil; } @catch (NSException *e) {}
        UIView *scan = dock.window ?: root.view;
        UIView *homeView = nil;
        SCPCFindHomeButton(scan, parent, strip, 0, self.homeButton, &home, &homeView);
        self.homeInk = SCPCViewInk(homeView, 0) ?: self.homeInk;   // cung mau luoi app cua nut Home
        CGFloat statusBottom = CGRectGetMinY(strip) + SCPC_DOCK_TOP;
        SCPCStatusBottom(scan, parent, strip, 0, &statusBottom);
        CGFloat clusterBottom = CGRectIsNull(cluster) ? statusBottom : CGRectGetMaxY(cluster);
        CGFloat clusterTop = CGRectIsNull(cluster) ? clusterBottom : CGRectGetMinY(cluster);
        // Nut Home (luoi app) nam cuoi dai dock; khong tim thay thi coi o day dai dock cao bang be ngang dai
        CGFloat homeTop = !CGRectIsNull(home) && CGRectGetMinY(home) > clusterBottom ? CGRectGetMinY(home)
                                                                                    : CGRectGetMaxY(strip) - strip.size.width;
        // Nut Split Screen luon sat ngay tren nut Home. Khe duoi cum icon thieu thi day cum icon len, nhung khong de len
        // dong ho / song / pin; van thieu thi thu nho nut (toi thieu SCPC_DOCK_MIN).
        CGFloat room = CGRectIsNull(cluster) ? 0 : MAX(0, clusterTop - (statusBottom + 4));
        CGFloat fit = homeTop - 4 - (clusterBottom - room + 4);   // nut lon nhat vua khe khi day het co
        if (fit >= SCPC_DOCK_MIN) {
            size = MIN(size, floor(fit));
            shift = CGRectIsNull(cluster) ? 0 : MAX(0, clusterBottom + 4 - (homeTop - 4 - size));
            c = CGPointMake(cx, homeTop - 4 - size / 2);
            where = [NSString stringWithFormat:@"tren nut Home, %.0fpt%@", size, shift > 0 ? @" (day cum icon len)" : @""];
        } else {
            size = SCPC_HOME_BTN;
            c = CGPointMake(CGRectGetMaxX(area) - size / 2 - 8, CGRectGetMinY(area) + size / 2 + 8);
            where = @"goc tren phai vung app (dock khong con cho)";
        }
    }
    if (![where isEqualToString:self.launcherWhere]) {
        self.launcherWhere = where;
        SCPLog("CarSplit: nut Split Screen dat %@ | dai dock=%@ cum icon=%@ nut Home=%@ day len %.1f", where,
               NSStringFromCGRect(strip), NSStringFromCGRect(cluster), NSStringFromCGRect(home), shift);
    }
    if (outSize) *outSize = size;
    if (outShift) *outShift = shift;
    return c;
}

// Nut Split Screen tren dock CarPlay: luon hien (man chinh, app toan man, dang chia -> doi bo cuc)
- (void)refreshHomeButton
{
    UIViewController *root = SCPCRootVC();
    BOOL show = root && [SCPPrefs enabled];
    UIView *parent = show ? [self tabParent] : nil;
    if (!parent) { [self removeHomeButton]; return; }
    // Ham nay chay moi lan DashBoard layout -> do dock (quet cay view tim nut Home) toi da 1 lan / giay
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (self.homeButton.superview && self.homeButton.superview == self.launcherHost && now - self.lastLauncherCalc < 1.0) {
        [self raiseLauncher];
        return;
    }
    self.lastLauncherCalc = now;
    CGFloat size = SCPC_HOME_BTN, shift = 0;
    CGPoint c = [self launcherCenterInParent:parent size:&size shift:&shift];
    [self setDockShift:shift];
    // Tren dock: o nen logo 4 mau (nhu cac bang tren xe), vien trang, glyph 2 o mau cham giong nut Chia man cua thanh •••
    // (tools/preview/theme.html). Goc vung app (khong co dock doc): nut tron kinh trang cho noi tren app.
    BOOL bare = ![self.launcherWhere hasPrefix:@"goc"];
    if (!self.homeButton || fabs(self.homeButton.bounds.size.width - size) > 0.5 || self.launcherBare != bare) {
        [self.homeButton removeFromSuperview];
        UIButton *b = bare ? SCPCRoundButton(SCPCGlyph(@"hm_split", round(size * 0.62), NO), self, @selector(homeButtonTapped))
                           : SCPCCircleButton(SCPCSplitImage(size * 0.9), size, self, @selector(homeButtonTapped));
        b.bounds = CGRectMake(0, 0, size, size);
        if (bare) SCPCDockTile(b, size * 0.28);
        self.homeButton = b;
        self.launcherBare = bare;
    }
    self.homeButton.tintColor = SCPCInk();
    // Nut nam tren dai dock: gan vao chinh view ve dai dock (status bar CarPlay nam tren baseContainerView,
    // gan vao tabParent thi nut bi dai dock che mat). Ngoai dock (goc vung app) thi van gan vao tabParent.
    CGRect r = CGRectMake(c.x - size / 2, c.y - size / 2, size, size);
    UIView *host = [self.launcherWhere hasPrefix:@"goc"] ? nil : [self dockHostForRect:r inParent:parent];
    if (!host) host = parent;
    if (self.homeButton.superview != host) {
        [host addSubview:self.homeButton];
        SCPLog("CarSplit: nut Split Screen gan vao %@ %@", NSStringFromClass([host class]),
               host == parent ? @"(tabParent)" : NSStringFromCGRect([parent convertRect:host.bounds fromView:host]));
    }
    self.launcherHost = host;
    self.homeButton.center = [host convertPoint:c fromView:parent];
    [self raiseLauncher];
    if ([self atHomeScreen]) [self installIconLongPress];
}

// Day cum icon dock CarPlay len dy pt (transform, DashBoard layout lai khong mat) de chua cho nut Split Screen
// ngay tren nut Home; dy = 0 tra ve cho cu
- (void)setDockShift:(CGFloat)dy
{
    UIView *dock = nil;
    @try { id dockVC = objcInvoke(SCPCRootVC(), @"appDockViewController"); dock = dockVC ? objcInvoke(dockVC, @"view") : nil; } @catch (NSException *e) {}
    if (!dock) return;
    CGAffineTransform t = dy > 0 ? CGAffineTransformMakeTranslation(0, -dy) : CGAffineTransformIdentity;
    if (!CGAffineTransformEqualToTransform(dock.transform, t)) dock.transform = t;
}

- (void)raiseLauncher
{
    UIView *host = self.homeButton.superview;
    if (!host) return;
    if (host == [self tabParent]) [self raiseView:self.homeButton];
    else if (host.subviews.lastObject != self.homeButton) [host bringSubviewToFront:self.homeButton];
}

static void SCPCDumpTree(UIView *v, UIView *root, int depth, NSMutableString *out)
{
    if (!v || depth > 7 || out.length > 6000) return;
    CGRect r = [root convertRect:v.bounds fromView:v];
    [out appendFormat:@"%@%@ %@%@%@\n", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
        NSStringFromClass([v class]), NSStringFromCGRect(r), v.hidden ? @" hidden" : @"",
        v.userInteractionEnabled ? @"" : @" noTouch"];
    for (UIView *c in v.subviews) SCPCDumpTree(c, root, depth + 1, out);
}

// View to nhat chua cum icon dock ma van nam gon trong dai dock va bao tron khung r (toa do parent).
// nil neu khong thay (dock chua layout / khac man hinh). Lan dau ghi cay view dai dock vao log.
- (UIView *)dockHostForRect:(CGRect)r inParent:(UIView *)parent
{
    UIView *dock = nil;
    @try { id dockVC = objcInvoke(SCPCRootVC(), @"appDockViewController"); dock = dockVC ? objcInvoke(dockVC, @"view") : nil; } @catch (NSException *e) {}
    if (!dock.window || !parent.window) return nil;
    UIScreen *screen = parent.window.screen ?: dock.window.screen;
    if (!screen) return nil;
    CGRect want = [parent convertRect:r toCoordinateSpace:screen.coordinateSpace];
    CGRect full = [parent convertRect:parent.bounds toCoordinateSpace:screen.coordinateSpace];
    UIView *best = nil;
    for (UIView *v = dock; v && ![v isKindOfClass:[UIWindow class]] && v != parent; v = v.superview) {
        CGRect mine = [v convertRect:v.bounds toCoordinateSpace:screen.coordinateSpace];
        if (mine.size.width > full.size.width * 0.5) break;   // da ra ngoai dai dock (view toan man hinh)
        if (CGRectContainsRect(CGRectInset(mine, -0.5, -0.5), want)) { best = v; break; }
    }
    if (!self.dockTreeLogged && dock.bounds.size.height < full.size.height * 0.9) {   // dock da layout xong
        self.dockTreeLogged = YES;
        UIView *top = dock;
        while (top.superview && ![top.superview isKindOfClass:[UIWindow class]] && top.superview != parent
               && [top.superview convertRect:top.superview.bounds toCoordinateSpace:screen.coordinateSpace].size.width <= full.size.width * 0.5)
            top = top.superview;
        NSMutableString *s = [NSMutableString string];
        SCPCDumpTree(top, top, 0, s);
        SCPLog("DIAG cay dai dock:\n%@", s);
    }
    return best;
}

- (void)removeHomeButton
{
    [self.homeButton removeFromSuperview];
    self.homeButton = nil;
    self.lastLauncherCalc = 0;
    [self setDockShift:0];
}

- (void)homeButtonTapped
{
    @try { [self homeButtonTappedUnsafe]; }
    @catch (NSException *e) { SCPLog("CarSplit: loi nut Split Screen %@\n%@", e, e.callStackSymbols); }
}

- (void)homeButtonTappedUnsafe
{
    NSString *cur = self.active ? nil : [self fullscreenAppBundle];
    SCPLog("CarSplit: bam nut Split Screen tren dock (%@)", self.active ? @"dang chia -> doi bo cuc" : (cur ?: @"man chinh"));
    if (self.tray) [self collapseAppTray]; else [self showLayoutPanelForApp:cur];
}

// Cap dung lan cuoi (khong co thi cap trong Cai dat). App khong con tren CarPlay thi bo, o do hien bang chon.
// Tu mo khi cam xe: mo lai dung cach chia gan nhat (bo cuc + app); khong co thi Bo cuc yeu thich 1
// Cam xe: mo lai cach chia gan nhat nhung
//  - khong tu phat YouTube / TikTok (o do hien bang chon app)
//  - app CarPlay vua tu mo lai (ban do, nhac) duoc giu: vao o 1 neu chua nam trong cach chia
//  - app dang mo la YouTube / TikTok (CarPlay tu mo lai) -> khong tu chia
- (void)openRememberedPairForConnect
{
    NSArray *apps = nil;
    int layoutID = 2;
    for (NSDictionary *r in [SCPPrefs recentLayouts]) {
        NSArray *a = r[@"apps"];
        BOOL ok = a.count >= 2;
        for (NSString *bid in a) if (![bid isKindOfClass:[NSString class]] || ![self isCarPlayApp:bid]) ok = NO;
        if (ok) { apps = a; layoutID = [r[@"layout"] intValue]; break; }
    }
    if (!apps) {
        NSDictionary *f = [SCPPrefs favorite:1];
        apps = [self favoriteApps:f];
        layoutID = [f[@"layout"] intValue] ?: 2;
    }
    if (!apps) { SCPLog("CarSplit: chua co cach chia gan day / yeu thich -> khong tu mo"); return; }
    NSString *cur = [self fullscreenAppBundle];
    NSMutableArray *list = [NSMutableArray array];
    for (id a in apps) [list addObject:[a isKindOfClass:[NSString class]] ? a : [NSNull null]];
    if (cur && ![list containsObject:cur] && list.count) list[0] = cur;
    SCPLog("CarSplit: tu mo khi cam xe: bo cuc %d, app %@ (dang mo %@)", layoutID, list, cur ?: @"-");
    [self openSetupLayout:layoutID apps:list];
}

- (void)openRememberedPair
{
    for (NSDictionary *r in [SCPPrefs recentLayouts]) {
        NSArray *apps = r[@"apps"];
        BOOL ok = apps.count >= 2;
        for (NSString *bid in apps) if (![bid isKindOfClass:[NSString class]] || ![self isCarPlayApp:bid]) ok = NO;
        if (!ok) continue;
        SCPLog("CarSplit: mo lai cach chia gan nhat %@", r);
        [self openSetupLayout:[r[@"layout"] intValue] apps:apps];
        return;
    }
    NSDictionary *f = [SCPPrefs favorite:1];
    NSArray *apps = [self favoriteApps:f];
    if (apps) { SCPLog("CarSplit: chua co cach chia gan day -> Bo cuc yeu thich 1"); [self openSetupLayout:[f[@"layout"] intValue] apps:apps]; }
    else SCPLog("CarSplit: chua co cach chia gan day / yeu thich -> khong tu mo");
}

// Gan cu chi giu lau vao luoi icon man chinh CarPlay (*IconListView), toi da 1 lan quet / 2s
- (void)installIconLongPress
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - self.lastIconScan < 2.0) return;
    self.lastIconScan = now;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) [self installLongPressIn:w depth:0];
    }
}

- (void)installLongPressIn:(UIView *)v depth:(int)depth
{
    if (!v || depth > 14 || v == self.container) return;
    if ([NSStringFromClass([v class]) hasSuffix:@"IconListView"]) {
        if (objc_getAssociatedObject(v, &kSCPCLongPressKey)) return;
        UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(iconLongPressed:)];
        g.minimumPressDuration = 0.7;
        [v addGestureRecognizer:g];
        objc_setAssociatedObject(v, &kSCPCLongPressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SCPLog("CarSplit: gan giu icon vao %@", NSStringFromClass([v class]));
        return;
    }
    for (UIView *c in v.subviews) [self installLongPressIn:c depth:depth + 1];
}

- (void)iconLongPressed:(UILongPressGestureRecognizer *)g
{
    @try { [self iconLongPressedUnsafe:g]; }
    @catch (NSException *e) { SCPLog("CarSplit: loi giu icon %@\n%@", e, e.callStackSymbols); }
}

- (void)iconLongPressedUnsafe:(UILongPressGestureRecognizer *)g
{
    if (g.state != UIGestureRecognizerStateBegan || self.active || ![SCPPrefs enabled]) return;
    UIView *hit = [g.view hitTest:[g locationInView:g.view] withEvent:nil];
    NSString *bid = nil;
    for (UIView *v = hit; v && v != g.view.superview && !bid; v = v.superview) {
        id icon = SCPCTry(v, @"icon");
        if (icon) bid = SCPCIconBundle(icon);
    }
    if (!bid || ![self isCarPlayApp:bid]) {
        SCPLog("CarSplit: giu icon %@ -> khong chia man duoc", bid);
        if (bid) [self toast:SCPCT(@"App này không chia màn hình được", @"This app can't be split")];
        return;
    }
    SCPLog("CarSplit: giu icon %@ -> bang bo cuc", bid);
    [self showLayoutPanelForApp:bid];
}

// Man xe vua hien (cam xe). Bat "Tu mo split khi cam xe" -> doi DashBoard san sang roi mo cap da nho.
- (void)carScreenAppeared
{
    if (self.autoLaunchDone) return;
    self.autoLaunchDone = YES;
    // SpringBoard giu yeu cau omnicar://splitscreen/ gui luc xe chua ket noi -> bao man xe da san sang de gui lai
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:SPL_NOTIF_READY object:nil userInfo:nil];
    if (![SCPPrefs enabled] || ![SCPPrefs autoLaunch]) return;
    SCPLog("CarSplit: cam xe -> se tu mo split");
    [self autoLaunchAttempt:0];
}

- (void)autoLaunchAttempt:(int)n
{
    __weak SCPCarSplit *weakSelf = self;
    if (self.active) return;
    if (!SCPCRootVC() && n < 40) {
        SCPCAfter(1.0, ^{
            [weakSelf autoLaunchAttempt:n + 1];
        });
        return;
    }
    SCPCAfter(1.5, ^{
        SCPCarSplit *me = weakSelf;
        if (!me || me.active) return;
        SCPLog("CarSplit: tu mo split khi cam xe");
        [me openRememberedPairForConnect];
    });
}

- (void)toast:(NSString *)msg { [self toast:msg duration:2.6]; }

// Thong bao nho o day vung app. Dang chieu CarBridge (CBWindow nam tren moi view CarPlay) thi dat len o khac.
- (void)toast:(NSString *)msg duration:(NSTimeInterval)duration
{
    UIView *host = SCPCRootVC().view;
    if (!host || !msg.length) return;
    UILabel *l = [[UILabel alloc] init];
    l.text = msg;
    l.textColor = SCPCInk();
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 2;
    CGFloat maxW = MAX(160, host.bounds.size.width - 48);
    CGSize fit = [l sizeThatFits:CGSizeMake(maxW - 32, 60)];
    l.bounds = CGRectMake(0, 0, MIN(maxW, fit.width + 32), MAX(38, fit.height + 18));
    SCPCChrome(l, 19);
    l.backgroundColor = [UIColor colorWithWhite:1 alpha:0.94];   // kinh trang, chu mau muc
    CGPoint c = CGPointMake(CGRectGetMidX(host.bounds), host.bounds.size.height - 50);
    SCPCarPane *bp = [self bridgedPane];
    if (self.active && bp && self.container) {
        CGRect bf = [host convertRect:bp.view.frame fromView:self.container];
        if (CGRectContainsPoint(CGRectInset(bf, -l.bounds.size.width / 2, -l.bounds.size.height / 2), c)) {
            for (SCPCarPane *o in [self allPanes]) {
                if (o == bp || o.view.alpha < 0.5) continue;
                CGRect of = [host convertRect:o.view.frame fromView:self.container];
                c = CGPointMake(CGRectGetMidX(of), CGRectGetMaxY(of) - l.bounds.size.height / 2 - 12);
                break;
            }
        }
    }
    l.center = c;
    [host addSubview:l];
    l.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ l.alpha = 1; } completion:^(BOOL f) {
        [UIView animateWithDuration:0.3 delay:duration options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f2) { [l removeFromSuperview]; }];
    }];
}

@end


