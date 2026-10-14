#import "SPPBubble.h"
#import "SPPBubbleView.h"
#import "SPPPrefs.h"
#import "SPPWarn.h"
#import <notify.h>

// Lite mode (OMCLiteActive): shadows without a path are drawn off screen on every frame; the card goes flat
static void SPPStripShadows(CALayer *layer)
{
    layer.shadowOpacity = 0;
    for (CALayer *l in layer.sublayers) SPPStripShadows(l);
}

#define SPP_SPEED_STALE 5.0   // giay khong co so moi -> hien "--" (bong bong van hien)
#define SPP_VALUE_HOLD  3.0   // giay giu so cu khi app tam khong doc duoc (khong nhay qua lai so <-> "--")
#define SPP_SOURCE_GONE 90.0  // giay khong nghe gi tu app (va khong biet app con chay khong) -> an
#define SPP_CAR_GRACE   3.0   // giay mat man xe lien tuc moi chuyen bong bong ve iPhone
#define SPP_SCALE_BASE  0.9   // ti le ung voi 100% trong Cai dat (Kich thuoc tren iPhone / CarPlay)
#define SPP_SIZE_MIN    60.0  // % (Cai dat + chum 2 ngon)
#define SPP_SIZE_MAX    220.0
#define SPP_HOLD_QUIT   2.0   // giay giu bong bong de thoat han app
#define SPP_HOLD_BEGIN  0.2   // giay giu toi thieu truoc khi bat dau dem (de khong nham voi cham / keo)

// ---------------------------------------------------------------------
//  Cua so: man xe (UIRootSceneWindow tren CADisplay cua CarPlay) hoac man iPhone
//  Co che tao cua so tren man xe: theo carplay-cast (EthanArbuckle)
// ---------------------------------------------------------------------

// CADisplay cua man hinh xe (nil neu chua ket noi)
id SPPGetCarPlayCADisplay(void)
{
    id carplayDevice = objcInvoke(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice");
    if (!carplayDevice) return nil;
    NSArray *screenIDs = objcInvoke(carplayDevice, @"screenIDs");
    if (screenIDs.count == 0) return nil;
    NSString *carplayScreenID = screenIDs[0];
    for (id display in objcInvoke(objc_getClass("CADisplay"), @"displays")) {
        if ([carplayScreenID isEqualToString:objcInvoke(display, @"uniqueId")]) return display;
    }
    return nil;
}

// *scale = so diem anh that tren 1 diem cua man xe (man xe thuong 1x / 2x, khac iPhone 3x)
UIWindow *SPPMakeCarWindow(CGFloat *scale)
{
    id carDisplay = SPPGetCarPlayCADisplay();
    if (!carDisplay) return nil;
    id displayConfig = objcInvoke_2([objc_getClass("FBSDisplayConfiguration") alloc],
                                    @"initWithCADisplay:isMainDisplay:", carDisplay, 0);
    if (!displayConfig) { SPPLog("khong tao duoc FBSDisplayConfiguration"); return nil; }
    UIWindow *w = objcInvoke_1([objc_getClass("UIRootSceneWindow") alloc], @"initWithDisplayConfiguration:", displayConfig);
    if (![w isKindOfClass:[UIWindow class]]) { SPPLog("khong tao duoc UIRootSceneWindow: %@", w); return nil; }

    CGFloat s = 0;
    if ([displayConfig respondsToSelector:NSSelectorFromString(@"pointScale")]) s = objcInvokeT(displayConfig, @"pointScale", CGFloat);
    if (s < 1) {   // du phong: diem anh cua che do man / kich thuoc cua so (diem)
        id mode = [carDisplay respondsToSelector:NSSelectorFromString(@"currentMode")] ? objcInvoke(carDisplay, @"currentMode") : nil;
        CGFloat px = mode ? MAX(objcInvokeT(mode, @"width", size_t), objcInvokeT(mode, @"height", size_t)) : 0;
        CGFloat pt = MAX(w.bounds.size.width, w.bounds.size.height);
        if (px > 0 && pt > 0) s = round(px / pt * 4) / 4;
    }
    if (s < 1 || s > 4) s = w.screen.scale >= 1 ? w.screen.scale : 2;
    *scale = s;
    SPPLog("man xe: %.0fx%.0f diem, ti le %.2f", w.bounds.size.width, w.bounds.size.height, s);
    return w;
}

static UIWindow *SPPMakePhoneWindow(void)
{
    CGRect sb = [UIScreen mainScreen].bounds;
    UIWindowScene *mainScene = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen == [UIScreen mainScreen]) {
            mainScene = (UIWindowScene *)sc; break;
        }
    }
    UIWindow *w = mainScene ? [[UIWindow alloc] initWithWindowScene:mainScene] : [[UIWindow alloc] initWithFrame:sb];
    w.frame = sb;
    return w;
}

// Tat han process app dan duong ngay (nut X)
static void SPPKillApp(NSString *bid)
{
    id svc = objcInvoke(objc_getClass("FBSSystemService"), @"sharedService");
    SEL sel = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
    if (svc && [svc respondsToSelector:sel]) {
        ((void (*)(id, SEL, id, long long, BOOL, id))objc_msgSend)(svc, sel, bid, 1, NO, @"OmniCar: user closed");
        SPPLog("terminate %@ (FBSSystemService)", bid);
        return;
    }
    void (*fn)(NSString *, int, BOOL, NSString *) =
        (void (*)(NSString *, int, BOOL, NSString *))dlsym(RTLD_DEFAULT, "BKSTerminateApplicationForReasonAndReportWithDescription");
    if (fn) { fn(bid, 1, NO, @"OmniCar"); SPPLog("terminate %@ (BKS)", bid); }
    else SPPLog("khong tim thay API terminate cho %@", bid);
}

// Cua so bong bong phu kin man (de keo tha tu do) nhung PHAI cho cham xuyen qua o moi cho khong co the/nut X.
// Cua so xe la UIRootSceneWindow (class rieng cua SpringBoard) nen khong subclass tinh duoc
// -> tao subclass luc chay va doi class cua instance (object_setClass).
static UIView *SPPPassThroughHitTest(id self, SEL _cmd, CGPoint p, UIEvent *e)
{
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    UIView *v = ((UIView *(*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
    return (v == self) ? nil : v;   // cham vao chinh cua so (khong trung subview) -> bo qua, xuong duoi
}

void SPPMakeWindowPassThrough(UIWindow *w)
{
    Class base = object_getClass(w);
    NSString *name = [NSString stringWithFormat:@"SPPPassThrough_%@", NSStringFromClass(base)];
    Class cls = objc_getClass(name.UTF8String);
    if (!cls) {
        cls = objc_allocateClassPair(base, name.UTF8String, 0);
        Method m = class_getInstanceMethod(base, @selector(hitTest:withEvent:));
        class_addMethod(cls, @selector(hitTest:withEvent:), (IMP)SPPPassThroughHitTest, method_getTypeEncoding(m));
        objc_registerClassPair(cls);
    }
    object_setClass(w, cls);
}

@interface UIImage (SPPPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end

// Icon cua app (API rieng cua UIKit, co trong SpringBoard); khong lay duoc -> o mau co chu viet tat
static UIImage *SPPAppIcon(int app)
{
    static NSMutableDictionary<NSNumber *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    UIImage *img = cache[@(app)];
    if (img) return img;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        img = [UIImage _applicationIconImageForBundleIdentifier:SPPNavAppBundle(app) format:2 scale:[UIScreen mainScreen].scale];
    if (!img) {
        CGFloat d = 60;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
        img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIColor *bg = app == 1 ? [UIColor colorWithRed:0.0 green:0.6 blue:0.45 alpha:1]
                        : app == 2 ? [UIColor colorWithRed:0.2 green:0.75 blue:0.95 alpha:1] : [UIColor colorWithRed:0.1 green:0.4 blue:0.85 alpha:1];
            [bg setFill]; UIRectFill(CGRectMake(0, 0, d, d));
            NSArray *abbr = @[@"VM", @"GO", @"WZ"];
            NSString *t = (app >= 0 && app < (int)abbr.count) ? abbr[app] : @"?";
            NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy], NSForegroundColorAttributeName: [UIColor whiteColor]};
            CGSize ts = [t sizeWithAttributes:a];
            [t drawAtPoint:CGPointMake((d - ts.width) / 2, (d - ts.height) / 2) withAttributes:a];
        }];
        SPPLog("bubble: khong lay duoc icon %@ -> dung chu viet tat", SPPNavAppBundle(app));
    }
    cache[@(app)] = img;
    return img;
}

// Mau do cua vien "giu de thoat" (cac thanh phan ve bong bong nam trong SPPBubbleView.m)
static UIColor *SPPRed(void) { return [UIColor colorWithRed:1 green:69 / 255.0 blue:58 / 255.0 alpha:1]; }

@interface SpringBoard : UIApplication
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

@interface SPPBubble ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) SPPBubbleView *bubbleView;   // bong bong theo kieu da chon (SPPBubbleView.m)
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) NSTimeInterval timerInterval;  // 0.5 s, 1 s in lite mode
@property (nonatomic) BOOL builtLite;                // card built in lite mode (no shadows)
@property (nonatomic) int speed, limit;
@property (nonatomic) CFAbsoluteTime lastUpdate;      // ban tin gan nhat tu app nguon (ke ca khi khong co so)
@property (nonatomic) CFAbsoluteTime speedAt, limitAt; // lan cuoi doc duoc toc do / gioi han
@property (nonatomic) CFAbsoluteTime carLostAt;        // luc bat dau mat man xe (0 = dang co)
@property (nonatomic) BOOL onPhone;
@property (nonatomic) BOOL carBusy;                  // Split Screen dang mo bang tren man xe -> an bong bong tren xe
@property (nonatomic) CGFloat scale;                 // ti le dang ap = SPP_SCALE_BASE * % trong Cai dat (rieng iPhone / xe)
@property (nonatomic) BOOL pinching;                 // dang chum 2 ngon: khong nap lai ti le tu Cai dat
@property (nonatomic) int app;                       // chi so SPP_NAV_APPS cua app dang cap toc do (cham / X dung app nay)
@property (nonatomic) int iconApp;                   // app dang ve tren iconView (-1 = chua ve)
@property (nonatomic, strong) CAShapeLayer *holdRing;   // giu bong bong: vien do chay quanh, du 3 giay -> thoat app
@property (nonatomic, strong) NSTimer *holdTimer;
@property (nonatomic) CGPoint holdStart;                // diem bat dau giu (keo xa -> chuyen sang di chuyen the)
@property (nonatomic) BOOL holdDragging;
@property (nonatomic) CGRect outlineRect;               // hinh chinh cua kieu dang ve (vien giu chay quanh)
@property (nonatomic) CGFloat outlineCorner;
@property (nonatomic, strong) NSTimer *demoTimer;    // "Xem thu bong bong" trong Cai dat
@property (nonatomic, strong) NSTimer *staleTimer;   // canh so cu ca khi bong bong an (canh bao qua toc do, SB_DARWIN_SPEED_NOW)
@property (nonatomic) CGFloat appliedRotation;       // goc xoay dang ap cho cua so tren iPhone
@property (nonatomic) CGFloat displayScale;          // diem anh / diem cua man dang ve (xe hoac iPhone)
@property (nonatomic) CGPoint phoneFraction, carFraction;   // vi tri the theo ti le man (-1 = mac dinh), rieng iPhone / xe
@end

@implementation SPPBubble

+ (instancetype)shared
{
    static SPPBubble *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [SPPBubble new]; s.speed = -1; s.limit = -1; s.iconApp = -1;
        s.scale = SPP_SCALE_BASE * [SPPPrefs sizePercentForCar:NO] / 100.0;
        s.phoneFraction = CGPointMake(-1, -1); s.carFraction = CGPointMake(-1, -1);
        [s startOrientationTracking];
    });
    return s;
}

// Transform goc cua the = ti le nguoi dung chon (moi animation deu nhan them vao day)
- (CGAffineTransform)baseTransform { return CGAffineTransformMakeScale(self.scale, self.scale); }

// Ti le theo Cai dat cho man dang dung (iPhone / CarPlay)
- (CGFloat)savedScale { return SPP_SCALE_BASE * [SPPPrefs sizePercentForCar:!self.onPhone] / 100.0; }

// Cai dat doi kich thuoc (hoac vua doi man) -> ap ngay
- (void)applySavedScale
{
    CGFloat want = [self savedScale];
    if (self.pinching || self.holdRing || fabs(want - self.scale) < 0.001) return;
    self.scale = want;
    if (self.card) { self.card.transform = [self baseTransform]; [self clampCard]; [self applyCrispScale]; }
}
- (CGAffineTransform)baseScaled:(CGFloat)k { return CGAffineTransformMakeScale(self.scale * k, self.scale * k); }

// Toc do hien tai cho tinh nang khac: Darwin SB_DARWIN_SPEED_NOW, state = km/h, SB_SPEED_UNKNOWN = khong
// biet. Chi gui khi doi.
static void SPPPublishSpeed(int kmh)
{
    static int token = 0;
    static uint64_t last = UINT64_MAX;
    uint64_t state = kmh >= 0 ? (uint64_t)MIN(kmh, 255) : (uint64_t)SB_SPEED_UNKNOWN;
    if (state == last) return;
    if (!token) notify_register_check(SB_DARWIN_SPEED_NOW, &token);
    if (!token) return;
    last = state;
    notify_set_state(token, state);
    notify_post(SB_DARWIN_SPEED_NOW);
}

// Moi lan doi toc do (ban tin moi, so cu qua han, mat nguon...) -> bao cho tinh nang khac. "Xem thu" / test: so gia, khong gui.
- (void)setSpeed:(int)speed
{
    _speed = speed;
    if (!self.demoTimer) SPPPublishSpeed(speed);
}

// Ban tin moi -> canh bao qua toc do theo so moi; dong ho 1 giay canh so cu (bong bong an thi timer cua refresh dung)
- (void)feedWarning
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL fresh = self.speed >= 0 && now - self.speedAt <= SPP_SPEED_STALE;
    int limit = (self.limit > 0 && now - self.limitAt <= SPP_SPEED_STALE) ? self.limit : -1;
    [[SPPOverspeed shared] updateSpeed:(fresh ? self.speed : -1) limit:limit];
    if (!fresh) {
        if (self.speed >= 0 && !self.demoTimer) self.speed = -1;   // so cu -> "khong biet"
        [self.staleTimer invalidate]; self.staleTimer = nil;
        return;
    }
    if (self.staleTimer) return;
    __weak SPPBubble *weakSelf = self;
    self.staleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        SPPBubble *me = weakSelf;
        if (!me) { [t invalidate]; return; }
        [me feedWarning];
    }];
}

// Nguon ngung han (doi nguon / tat tinh nang): bo so, an ngay - khong cho SPP_SOURCE_GONE
- (void)sourceStopped:(int)app
{
    if ((app & 7) != (self.app & 7) || self.demoTimer) return;
    SPPLog("bubble: nguon %@ ngung -> bo so", SPPNavAppName(app));
    self.speed = -1; self.limit = -1; self.speedAt = 0; self.limitAt = 0; self.lastUpdate = 0;
    [self feedWarning];
    [self refresh];
}

- (void)updateSpeed:(int)speed limit:(int)limit
{
    [self updateSpeed:speed limit:limit appForeground:NO];
}

- (void)updateSpeed:(int)speed limit:(int)limit appForeground:(BOOL)fg
{
    [self updateSpeed:speed limit:limit appForeground:fg app:self.app];
}

// Trang thai hien/an cua tung app (co the chay ca Vietmap lan GOFA cung luc)
static BOOL sAppFg[8];
static CFAbsoluteTime sAppSeenAt[8];
static CFAbsoluteTime sAppFgSince[8];   // luc app bat dau hien
static BOOL sAppOpened[8];       // app da duoc nguoi dung mo len man hinh (iPhone / CarPlay) tu lan chay nay
static int sPreferredApp = -1;   // app mo gan nhat (nguon uu tien)

// Co app dan duong nao dang hien (va con gui du lieu) -> an bong bong
- (BOOL)anyAppForeground
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < 8; i++) if (sAppFg[i] && now - sAppSeenAt[i] < SPP_SPEED_STALE) return YES;
    return NO;
}

- (void)updateSpeed:(int)speed limit:(int)limit appForeground:(BOOL)fg app:(int)app
{
    app &= 7;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (fg != sAppFg[app]) SPPLog("bubble: %@ %@", SPPNavAppName(app), fg ? @"dang hien -> an bong bong" : @"chay nen -> hien bong bong");
    if (fg && !sAppFg[app]) sAppFgSince[app] = now;
    sAppFg[app] = fg; sAppSeenAt[app] = now;
    // Chi tinh la "da mo" khi app hien lien tuc >= 1.5 giay (bo qua lan active thoang qua luc he thong khoi chay app)
    if (fg && !sAppOpened[app] && now - sAppFgSince[app] >= 1.5) {
        sAppOpened[app] = YES; SPPLog("bubble: %@ da duoc mo", SPPNavAppName(app));
    }
    // App tu chay nen ma chua tung duoc mo (vd he thong danh thuc) -> bo qua, khong hien bong bong
    if (!sAppOpened[app] && !self.demoTimer) return;
    if (fg) sPreferredApp = app;   // app nguoi dung mo gan nhat -> nguon uu tien khi ca 2 app cung chay
    // Giu 1 nguon: chi doi sang app khac khi nguon dang theo im lang (> 2 giay), nguon dang theo khong co so ma app kia
    // co, hoac app kia la app vua mo
    CFAbsoluteTime age = now - self.lastUpdate;
    BOOL accept = (app == self.app) || age > 2.0 || (self.speed < 0 && speed >= 0)
                  || (app == sPreferredApp && self.app != sPreferredApp);
    if (!accept) return;
    // App dang hien khong gianh nguon cua app khac dang chay nen (bong bong van an toi khi het app nao dang hien)
    BOOL otherFresh = app != self.app && !sAppFg[self.app] && age < SPP_SPEED_STALE;
    if (!(fg && otherFresh)) {
        if (app != self.app) {
            SPPLog("bubble: nguon toc do -> %@", SPPNavAppName(app));
            self.speedAt = 0; self.limitAt = 0;   // so cu cua app kia khong giu lai
        }
        self.app = app;
        // Tam khong doc duoc (-1): giu so cu SPP_VALUE_HOLD giay roi moi hien "--"
        if (speed >= 0) { self.speed = speed; self.speedAt = now; }
        else if (now - self.speedAt > SPP_VALUE_HOLD) self.speed = -1;
        if (limit > 0) { self.limit = limit; self.limitAt = now; }
        else if (now - self.limitAt > SPP_VALUE_HOLD) self.limit = -1;
        self.lastUpdate = now;
    }
    [self feedWarning];
    [self refresh];
}

// App dang cap toc do con chay khong (SBApplication): 1 = chay (ke ca dang treo nen), 0 = da tat, -1 = khong biet.
// Chi tin ket qua "da tat" sau khi API tung bao "dang chay" trong phien nay - API khac di tren ban iOS khac thi
// khong bao gio an nham bong bong.
static BOOL sSeenRunning[8];

- (int)sourceAppState
{
    int app = self.app & 7;
    id ctl = objcInvoke(objc_getClass("SBApplicationController"), @"sharedInstance");
    id sbApp = ctl ? objcInvoke_1(ctl, @"applicationWithBundleIdentifier:", SPPNavAppBundle(app)) : nil;
    if (!sbApp) return -1;
    BOOL running = YES, known = NO;
    if ([sbApp respondsToSelector:NSSelectorFromString(@"isRunning")]) { running = objcInvokeT(sbApp, @"isRunning", BOOL); known = YES; }
    else if ([sbApp respondsToSelector:NSSelectorFromString(@"processState")]) {
        id ps = objcInvoke(sbApp, @"processState");
        running = ps && (![ps respondsToSelector:NSSelectorFromString(@"isRunning")] || objcInvokeT(ps, @"isRunning", BOOL));
        known = YES;
    }
    if (!known) return -1;
    if (running) { sSeenRunning[app] = YES; return 1; }
    return sSeenRunning[app] ? 0 : -1;
}

// Bong bong chi hien sau khi app dan duong da duoc mo roi chuyen sang chay nen - khong doc duoc so thi hien "--".
// Chi an khi: tat trong Cai dat, app dan duong dang hien, app da bi tat, hoac chua tung / lau qua khong nghe tu app.
- (void)refresh
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - self.speedAt > SPP_SPEED_STALE) self.speed = -1;   // app im lang (bi treo nen...) -> "--"
    if (now - self.limitAt > SPP_SPEED_STALE) self.limit = -1;
    int run = (self.lastUpdate > 0 && !self.demoTimer) ? [self sourceAppState] : 1;
    BOOL alive = self.lastUpdate > 0 && (run == 1 || now - self.lastUpdate < SPP_SOURCE_GONE);
    // Split Screen dang mo bang bo cuc / bang chon app: bong bong tren xe de len cho dang cham -> tam an (chia man thi van hien)
    BOOL carBusy = self.carBusy && SPPGetCarPlayCADisplay() != nil;
    BOOL show = alive && [SPPPrefs enabled] && ![self anyAppForeground] && !carBusy;
    // App vua bi tat (vuot khoi da nhiem / bi he thong dong) -> an ngay
    if (show && run == 0) {
        SPPLog("bubble: %@ da tat -> an bong bong ngay", SPPNavAppName(self.app));
        self.speed = -1; self.limit = -1; self.lastUpdate = 0;
        sAppOpened[self.app & 7] = NO; sAppFg[self.app & 7] = NO;   // lan chay sau phai mo app lai moi hien
        show = NO;
    }
    if (!show) {
        if (self.window && !self.window.hidden)
            SPPLog("bubble: an (ban tin %.1fs truoc, app chay=%d, tat=%d, app dan duong dang hien=%d, man xe ban=%d)",
                   now - self.lastUpdate, run, ![SPPPrefs enabled], [self anyAppForeground], carBusy);
        [self hide];
        return;
    }
    [self ensureWindow];
    if (!self.window) return;
    if (self.onPhone) [self applyPhoneOrientationForce:NO];

    [self applySavedScale];
    // So doi muot: chi dat text, khong animation (cap nhat lien tuc)
    [self renderBubble];
    [self applyCrispScale];
    if (self.builtLite) SPPStripShadows(self.card.layer);

    if (self.window.hidden) {
        self.window.hidden = NO;
        self.card.alpha = 0; self.card.transform = [self baseScaled:0.7];
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0
                         animations:^{ self.card.alpha = 1; self.card.transform = [self baseTransform]; } completion:nil];
    } else if (self.card.alpha < 1 && !self.holdRing) {
        // Dang mo dan (hide) thi co du lieu lai -> hien lai ngay, khong de cua so bi an roi moi hien
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ self.card.alpha = 1; self.card.transform = [self baseTransform]; } completion:nil];
    }
    NSTimeInterval every = self.builtLite ? 1.0 : 0.5;   // lite mode: half the redraws
    if (self.timer && self.timerInterval != every) { [self.timer invalidate]; self.timer = nil; }
    if (!self.timer) {
        __weak SPPBubble *weakSelf = self;
        self.timerInterval = every;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:every repeats:YES block:^(NSTimer *t) { [weakSelf refresh]; }];
    }
}

// Split Screen (process CarPlay) bao man xe dang ban / ranh qua OMC_DARWIN_CAR_BUSY
- (void)setCarBusy:(BOOL)busy
{
    if (_carBusy == busy) return;
    _carBusy = busy;
    SPPLog("bubble: man xe %@ (Split Screen)", busy ? @"ban -> an tren xe" : @"ranh");
    [self refresh];
}

- (void)hide
{
    if (self.window && !self.window.hidden) {
        UIView *card = self.card; UIWindow *win = self.window;
        [self cancelHold];
        [UIView animateWithDuration:0.18 animations:^{ card.alpha = 0; card.transform = [self baseScaled:0.8]; }
                         completion:^(BOOL f) { if (card.alpha < 0.01) win.hidden = YES; }];
    }
    [self.timer invalidate]; self.timer = nil;
}

// Kieu bong bong ve trong SPPBubbleView (dung chung voi trang Cai dat): 0 binh thuong, 1 sap cham gioi han, 2 vuot
- (int)speedState { return [self.bubbleView speedState]; }

// Dat so / kieu / tuy chon vao bong bong, ve lai, giu tam the co dinh
- (void)renderBubble
{
    SPPBubbleView *bv = self.bubbleView;
    BOOL lite = OMCLiteActive();
    if (lite != self.builtLite) { self.builtLite = lite; [bv rebuild]; }
    bv.style = [SPPPrefs style];
    bv.speed = self.speed; bv.limit = self.limit;
    bv.showIcon = [SPPPrefs showAppIcon]; bv.mph = [SPPPrefs useMph]; bv.usSign = [SPPPrefs usSign];
    if (bv.showIcon && self.iconApp != self.app) { bv.iconImage = SPPAppIcon(self.app); self.iconApp = self.app; }
    CGPoint c = self.card.center;
    CGSize size = [bv render];
    self.card.bounds = CGRectMake(0, 0, size.width, size.height);
    self.card.center = c;
    bv.frame = self.card.bounds;
    self.outlineRect = bv.outlineRect; self.outlineCorner = bv.outlineCorner;
    [self clampCard];
}

// Cai dat > Dat lai: ti le mac dinh, vi tri mac dinh tren ca iPhone lan xe
- (void)resetLayout
{
    [SPPPrefs setSizePercent:100 forCar:NO];
    [SPPPrefs setSizePercent:100 forCar:YES];
    self.scale = [self savedScale];
    self.phoneFraction = CGPointMake(-1, -1); self.carFraction = CGPointMake(-1, -1);
    if (self.window) {
        self.card.transform = [self baseTransform];
        [self restoreCardPosition];
        [self applyCrispScale];
    }
    SPPLog("bubble: dat lai vi tri + kich thuoc");
}

// "Xem thu bong bong" trong Cai dat: toc do gia 10 giay (tang qua gioi han 60 de thay doi mau)
- (void)runDemo
{
    [self.demoTimer invalidate];
    __block int tick = 0;
    SPPLog("bubble: xem thu 10 giay");
    __weak SPPBubble *weakSelf = self;
    self.demoTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        tick++;
        if (tick > 20) {
            // Het xem thu: bo so gia; app dan duong that dang chay se gui lai ngay (moi SPP_TICK) -> hien tiep
            [t invalidate]; weakSelf.demoTimer = nil;
            weakSelf.speed = -1; weakSelf.limit = -1; weakSelf.speedAt = 0; weakSelf.limitAt = 0; weakSelf.lastUpdate = 0;
            [weakSelf refresh];
            return;
        }
        int speed = 40 + tick * 2;   // 42 -> 80 km/h
        [weakSelf updateSpeed:speed limit:60];
    }];
}

// ---------------------------------------------------------------------
//  Cham / giu / keo / 2 ngon
// ---------------------------------------------------------------------
// Giu bong bong: sau SPP_HOLD_BEGIN giay hien vien do chay quanh hinh chinh, du SPP_HOLD_QUIT giay -> thoat han app.
// Tha tay som -> huy. Dang giu ma keo di -> huy dem, chuyen sang di chuyen the.
- (void)longPressed:(UILongPressGestureRecognizer *)g
{
    CGPoint p = [g locationInView:self.window];
    switch (g.state) {
    case UIGestureRecognizerStateBegan:
        self.holdStart = p; self.holdDragging = NO;
        [self startHold];
        break;
    case UIGestureRecognizerStateChanged:
        if (!self.holdDragging && hypot(p.x - self.holdStart.x, p.y - self.holdStart.y) > 12) { self.holdDragging = YES; [self cancelHold]; }
        if (self.holdDragging) {
            self.card.center = CGPointMake(self.card.center.x + p.x - self.holdStart.x, self.card.center.y + p.y - self.holdStart.y);
            self.holdStart = p;
            [self clampCard];
        }
        break;
    default:   // Ended / Cancelled / Failed
        if (self.holdDragging) [self saveCardPosition];
        self.holdDragging = NO;
        [self cancelHold];
        break;
    }
}

- (void)startHold
{
    [self cancelHold];
    CGFloat remain = SPP_HOLD_QUIT - SPP_HOLD_BEGIN;
    CGRect r = CGRectInset(self.outlineRect, -5, -5);
    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:self.outlineCorner + 5].CGPath;
    ring.fillColor = [UIColor clearColor].CGColor;
    ring.strokeColor = SPPRed().CGColor;
    ring.lineWidth = 4; ring.lineCap = kCALineCapRound;
    ring.shadowColor = SPPRed().CGColor; ring.shadowRadius = 4; ring.shadowOpacity = 0.8; ring.shadowOffset = CGSizeZero;
    ring.strokeEnd = 1;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    a.fromValue = @0; a.toValue = @1; a.duration = remain;
    [ring addAnimation:a forKey:@"sppHold"];
    [self.card.layer addSublayer:ring];
    [self applyCrispScale];
    self.holdRing = ring;
    [UIView animateWithDuration:remain delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.card.transform = [self baseScaled:0.92]; } completion:nil];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    __weak SPPBubble *weakSelf = self;
    self.holdTimer = [NSTimer scheduledTimerWithTimeInterval:remain repeats:NO block:^(NSTimer *t) { [weakSelf quitSourceApp]; }];
}

- (void)cancelHold
{
    [self.holdTimer invalidate]; self.holdTimer = nil;
    if (!self.holdRing) return;
    [self.holdRing removeFromSuperlayer]; self.holdRing = nil;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.card.transform = [self baseTransform]; } completion:nil];
}

// Du 3 giay: thoat han app dang cap toc do, an bong bong ngay
- (void)quitSourceApp
{
    [self cancelHold];
    NSString *bid = SPPNavAppBundle(self.app);
    SPPLog("bubble: giu %.0f giay -> thoat han %@", SPP_HOLD_QUIT, bid);
    [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
    SPPKillApp(bid);
    self.speed = -1; self.limit = -1;
    self.lastUpdate = 0;
    [self hide];
}

// 2 ngon: phong to / thu nho the (SPP_SIZE_MIN .. SPP_SIZE_MAX %), luu vao Cai dat cho man dang dung
- (void)pinched:(UIPinchGestureRecognizer *)g
{
    static CGFloat startScale = 1;
    if (g.state == UIGestureRecognizerStateBegan) { startScale = self.scale; self.pinching = YES; [self cancelHold]; }
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        CGFloat lo = SPP_SCALE_BASE * SPP_SIZE_MIN / 100, hi = SPP_SCALE_BASE * SPP_SIZE_MAX / 100;
        self.scale = MIN(hi, MAX(lo, startScale * g.scale));
        self.card.transform = [self baseTransform];
        [self clampCard];
    }
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        self.pinching = NO;
        [self saveCardPosition];
        [SPPPrefs setSizePercent:self.scale / SPP_SCALE_BASE * 100 forCar:!self.onPhone];
        self.scale = [self savedScale];   // khop voi gia tri da lam tron trong Cai dat
        self.card.transform = [self baseTransform];
        [self applyCrispScale];
    }
}

- (void)panned:(UIPanGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) [self cancelHold];
    CGPoint t = [g translationInView:self.window];
    self.card.center = CGPointMake(self.card.center.x + t.x, self.card.center.y + t.y);
    [self clampCard];
    [g setTranslation:CGPointZero inView:self.window];
    if (g.state == UIGestureRecognizerStateEnded) [self saveCardPosition];
}

// Cham bong bong -> mo lai app dan duong (tren xe: giao dien CarPlay cua app; khong co xe: tren iPhone)
- (void)tapped:(UITapGestureRecognizer *)g
{
    [UIView animateWithDuration:0.1 animations:^{ self.card.transform = [self baseScaled:0.92]; }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.15 animations:^{ self.card.transform = [self baseTransform]; }]; }];
    if (!self.onPhone) {
        SPPLog("bubble: cham -> mo %@ tren CarPlay", SPPNavAppName(self.app));
        static int tokOpen = 0;
        if (!tokOpen) notify_register_check(SPP_DARWIN_OPEN_CAR, &tokOpen);
        notify_set_state(tokOpen, (uint64_t)self.app);
        notify_post(SPP_DARWIN_OPEN_CAR);   // process CarPlay mo app (CarPlay.xm)
        return;
    }
    SPPLog("bubble: cham -> mo %@ tren iPhone", SPPNavAppName(self.app));
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(launchApplicationWithIdentifier:suspended:)])
        [sb launchApplicationWithIdentifier:SPPNavAppBundle(self.app) suspended:NO];
}

// ---------------------------------------------------------------------
//  Cua so rieng: tren man xe neu dang ket noi, neu khong thi tren man iPhone
// ---------------------------------------------------------------------
- (void)ensureWindow
{
    BOOL car = SPPGetCarPlayCADisplay() != nil;
    // Man xe chop mat 1 nhip (API tra nil thoang qua) -> giu cua so xe, chi chuyen ve iPhone khi mat lien tuc
    if (self.window && !self.onPhone && !car) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (self.carLostAt <= 0) self.carLostAt = now;
        if (now - self.carLostAt < SPP_CAR_GRACE) return;
    }
    self.carLostAt = 0;
    if (self.window && self.onPhone == !car) return;
    if (self.window) { self.window.hidden = YES; [self.window removeFromSuperview]; self.window = nil; }
    CGFloat ds = [UIScreen mainScreen].scale;
    UIWindow *w = car ? SPPMakeCarWindow(&ds) : SPPMakePhoneWindow();   // iPhone: xoay theo huong may (applyPhoneOrientation)
    if (!w) return;
    self.onPhone = !car;
    self.displayScale = ds;
    self.scale = [self savedScale];   // moi man co kich thuoc rieng
    SPPMakeWindowPassThrough(w);
    w.windowLevel = UIWindowLevelStatusBar + 70;
    w.backgroundColor = [UIColor clearColor];

    // The chua bong bong theo kieu da chon (SPPBubbleView) + cu chi
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    SPPBubbleView *bv = [[SPPBubbleView alloc] initWithFrame:card.bounds];
    bv.log = ^(NSString *line) { SPPLogWrite(line); };
    [card addSubview:bv];
    [card addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)]];
    [card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
    [card addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)]];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    lp.minimumPressDuration = SPP_HOLD_BEGIN;
    lp.allowableMovement = CGFLOAT_MAX;   // tu xu ly keo trong longPressed: (keo xa -> di chuyen the)
    [card addGestureRecognizer:lp];
    card.transform = [self baseTransform];
    [w addSubview:card];

    self.window = w; self.card = card; self.bubbleView = bv;
    self.iconApp = -1;   // the moi: ve lai icon
    if (!car) [self applyPhoneOrientationForce:YES];
    [self restoreCardPosition];
    w.hidden = YES;
    SPPLog("bubble: cua so %@ tao xong", car ? @"xe" : @"iPhone");
}

// ---------------------------------------------------------------------
//  Huong & vi tri
//  iPhone: cua so xoay theo huong cam may (doc / ngang trai / ngang phai).
//  CarPlay: cua so nam tren man xe (huong cua man xe), vi tri mac dinh ben phai dock CarPlay.
// ---------------------------------------------------------------------
- (void)startOrientationTracking
{
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    __weak SPPBubble *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil
                                                       queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        SPPBubble *me = weakSelf;
        if (me.window && me.onPhone) [me applyPhoneOrientationForce:NO];
    }];
}

// Goc xoay noi dung tren iPhone (giu goc cu khi may nam ngua / up / khong ro)
- (CGFloat)phoneRotation
{
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortrait:       return 0;
        case UIDeviceOrientationLandscapeLeft:  return M_PI_2;
        case UIDeviceOrientationLandscapeRight: return -M_PI_2;
        default: return self.appliedRotation;
    }
}

- (void)applyPhoneOrientationForce:(BOOL)force
{
    if (!self.window || !self.onPhone) return;
    CGFloat r = [self phoneRotation];
    if (!force && fabs(r - self.appliedRotation) < 0.01) return;
    BOOL wasVisible = !self.window.hidden && self.card.bounds.size.width > 10;
    if (wasVisible && !force) [self saveCardPosition];
    CGRect sb = [UIScreen mainScreen].bounds;
    BOOL land = fabs(r) > 0.1;
    self.window.transform = CGAffineTransformMakeRotation(r);
    self.window.bounds = land ? CGRectMake(0, 0, sb.size.height, sb.size.width) : CGRectMake(0, 0, sb.size.width, sb.size.height);
    self.window.center = CGPointMake(CGRectGetMidX(sb), CGRectGetMidY(sb));
    self.appliedRotation = r;
    [self restoreCardPosition];
    SPPLog("bubble: iPhone xoay %.0f do", r * 180 / M_PI);
}

// Vi tri mac dinh: iPhone = goc tren trai (duoi thanh trang thai); xe = ngay ben phai dock CarPlay
- (CGPoint)defaultCardCenter
{
    CGRect b = self.window.bounds;
    if (self.onPhone) return CGPointMake(16 + 70, b.size.height > b.size.width ? 70 : 12 + 40);
    return CGPointMake(MIN(b.size.width - 80, 90 + 80), 12 + 40);
}

- (void)saveCardPosition
{
    CGRect b = self.window.bounds;
    if (b.size.width < 1 || b.size.height < 1) return;
    CGPoint f = CGPointMake(self.card.center.x / b.size.width, self.card.center.y / b.size.height);
    if (self.onPhone) self.phoneFraction = f; else self.carFraction = f;
}

- (void)restoreCardPosition
{
    CGRect b = self.window.bounds;
    CGPoint f = self.onPhone ? self.phoneFraction : self.carFraction;
    self.card.center = (f.x < 0) ? [self defaultCardCenter] : CGPointMake(f.x * b.size.width, f.y * b.size.height);
    [self clampCard];
}

- (void)clampCard
{
    CGRect b = self.window.bounds; CGSize s = self.card.frame.size; CGPoint c = self.card.center;   // frame da tinh ti le
    c.x = MIN(CGRectGetMaxX(b) - s.width / 2, MAX(s.width / 2, c.x));
    c.y = MIN(CGRectGetMaxY(b) - s.height / 2, MAX(s.height / 2, c.y));
    // Goc the dung tron diem anh that: chu / vien khong bi lech nua diem anh (nhoe)
    CGFloat ps = self.displayScale > 0 ? self.displayScale : 1;
    c.x = round((c.x - s.width / 2) * ps) / ps + s.width / 2;
    c.y = round((c.y - s.height / 2) * ps) / ps + s.height / 2;
    self.card.center = c;
}

// Ve net: the duoc phong bang transform (ti le trong Cai dat). Mac dinh moi lop ve theo ti le man roi moi bi phong /
// thu khi ghep hinh -> chu, vong, vien bi nhoe / rang cua (ro nhat tren man xe 1x-2x). Dat contentsScale = ti le man x
// ti le the de moi lop ve dung bang so diem anh that tren man.
static void SPPSetContentsScale(CALayer *l, CGFloat s)
{
    BOOL image = [l.delegate isKindOfClass:[UIImageView class]];   // anh: giu nguyen, khong ve lai
    if (!image && fabs(l.contentsScale - s) > 0.001) {
        l.contentsScale = s;
        if ([l.delegate isKindOfClass:[UILabel class]]) [l setNeedsDisplay];
    }
    if (l.shouldRasterize) l.rasterizationScale = s;
    for (CALayer *c in l.sublayers) SPPSetContentsScale(c, s);
    if (l.mask) SPPSetContentsScale(l.mask, s);
}

- (void)applyCrispScale
{
    if (!self.card) return;
    CGFloat ds = self.displayScale > 0 ? self.displayScale : [UIScreen mainScreen].scale;
    SPPSetContentsScale(self.card.layer, ds * MAX(self.scale, 0.3));
}

@end

#pragma mark - Auto test (developer only)

#if OMC_AUTOTEST
#import "OMCTest.h"

// Bo test "speedBubble" (Core/OMCTest.h), chay trong SpringBoard khi xe da ket noi: bom toc do gia vao dung duong
// app dan duong gui (updateSpeed:...), kiem bong bong hien tren xe, so dung, trang thai gan / vuot gioi han, an khi
// Split Screen chiem man xe, ve dung moi kieu, co lon, an khi mat nguon. Kieu / co lon cua nguoi dung duoc tra lai.
static NSTimer *sSPPTestTimer;   // gia lam "Xem thu" (demoTimer): bo qua dieu kien "app da duoc mo"
static id sSPPTestStyle, sSPPTestSizeCar;

static void SPPTestFeed(int speed, int limit)
{
    SPPBubble *b = [SPPBubble shared];
    if (!sSPPTestTimer) sSPPTestTimer = [NSTimer timerWithTimeInterval:1e6 repeats:NO block:^(NSTimer *t) {}];
    b.demoTimer = sSPPTestTimer;
    [b updateSpeed:speed limit:limit appForeground:NO app:b.app];
}

static void SPPTestEnd(void)
{
    SPPBubble *b = [SPPBubble shared];
    if (b.demoTimer == sSPPTestTimer) b.demoTimer = nil;
    sSPPTestTimer = nil;
    b.speed = -1; b.limit = -1; b.speedAt = 0; b.limitAt = 0; b.lastUpdate = 0;
    [b refresh];
}

static void SPPTestSetPref(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, OMC_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

static NSString *SPPTestState(void)
{
    SPPBubble *b = [SPPBubble shared];
    return OMCTestFormat(@"window=%d hidden=%d alpha=%.2f onPhone=%d speed=%d limit=%d state=%d style=%ld/%ld scale=%.2f card=%@ carBusy=%d fg=%d",
        b.window != nil, b.window.hidden, b.card.alpha, b.onPhone, b.speed, b.limit, [b speedState], (long)b.bubbleView.builtStyle, (long)[SPPPrefs style],
        b.scale, NSStringFromCGRect(b.card.frame), b.carBusy, [b anyAppForeground]);
}

static NSString *SPPTestWhy(NSString *why) { return why ? [NSString stringWithFormat:@"%@ || %@", why, SPPTestState()] : nil; }

static NSString *SPPTestVisibleOnCar(void)
{
    SPPBubble *b = [SPPBubble shared];
    if (!b.window || b.window.hidden || b.card.alpha < 0.9) return SPPTestWhy(@"bong bong khong hien");
    if (b.onPhone) return SPPTestWhy(@"bong bong dang o iPhone, khong o man xe");
    if ([b anyAppForeground]) return SPPTestWhy(@"app dan duong dang mo tren man hinh (bong bong co tinh an)");
    CGRect inWin = [b.card convertRect:b.card.bounds toView:b.window];
    if (inWin.size.width < 20 || !CGRectIntersectsRect(inWin, b.window.bounds)) return SPPTestWhy(@"the bong bong ra ngoai man xe");
    return nil;
}

static NSArray<NSDictionary *> *SPPTestSteps(void)
{
    NSMutableArray *steps = [NSMutableArray array];
    SPPBubble *b = [SPPBubble shared];
    sSPPTestStyle = OMCPref(SB_KEY_STYLE, nil);
    sSPPTestSizeCar = OMCPref(SB_KEY_SIZE_CAR, nil);

    [steps addObject:OMCTestStep(@"Moi truong: bat bong bong, co man xe", 0, 0, nil, ^NSString *{
        if (![SPPPrefs enabled]) return @"Bong bong toc do dang tat";
        if (!SPPGetCarPlayCADisplay()) return @"khong thay man CarPlay";
        return nil;
    })];
    if (![SPPPrefs enabled]) return steps;

    [steps addObject:OMCTestStep(@"Hien tren xe khi co toc do (50 / 60)", 1, 5, ^NSString *{ SPPTestFeed(50, 60); return nil; },
        ^NSString *{ SPPTestFeed(50, 60); return SPPTestVisibleOnCar(); })];
    [steps addObject:OMCTestStep(@"So toc do dung", 0.5, 3, ^NSString *{ SPPTestFeed(57, 60); return nil; }, ^NSString *{
        SPPTestFeed(57, 60);
        if (b.speed != 57 || b.limit != 60) return SPPTestWhy(@"toc do / gioi han khong khop");
        NSString *want = [NSString stringWithFormat:@"%d", (int)([SPPPrefs useMph] ? lround(57 / 1.609344) : 57)];   // mph: 35
        if (b.bubbleView.speedLabel && ![b.bubbleView.speedLabel.text isEqualToString:want]) return SPPTestWhy(OMCTestFormat(@"chu hien '%@', can %@", b.bubbleView.speedLabel.text, want));
        return nil;
    })];
    [steps addObject:OMCTestStep(@"Gan gioi han (57 / 60) -> canh bao", 0.5, 3, nil, ^NSString *{
        SPPTestFeed(57, 60);
        return [b speedState] == 1 ? nil : SPPTestWhy(@"khong o trang thai gan gioi han");
    })];
    [steps addObject:OMCTestStep(@"Vuot gioi han (75 / 60) -> do", 0.5, 3, nil, ^NSString *{
        SPPTestFeed(75, 60);
        return [b speedState] == 2 ? nil : SPPTestWhy(@"khong o trang thai vuot gioi han");
    })];
    [steps addObject:OMCTestStep(@"Duoi gioi han (40 / 60) -> binh thuong", 0.5, 3, nil, ^NSString *{
        SPPTestFeed(40, 60);
        return [b speedState] == 0 ? nil : SPPTestWhy(@"van canh bao khi da cham lai");
    })];
    [steps addObject:OMCTestStep(@"Split Screen chiem man xe -> an", 0.8, 3, ^NSString *{ [b setCarBusy:YES]; return nil; }, ^NSString *{
        SPPTestFeed(40, 60);
        return (b.window.hidden || b.card.alpha < 0.1) ? nil : SPPTestWhy(@"van hien khi man xe ban");
    })];
    [steps addObject:OMCTestStep(@"Man xe ranh -> hien lai", 0.8, 4, ^NSString *{ [b setCarBusy:NO]; return nil; },
        ^NSString *{ SPPTestFeed(40, 60); return SPPTestVisibleOnCar(); })];

    for (NSInteger style = 0; style < SB_STYLE_COUNT; style++) {
        [steps addObject:OMCTestStep(OMCTestFormat(@"Kieu %ld", (long)style), 0.8, 4, ^NSString *{
            SPPTestSetPref(SB_KEY_STYLE, @(style));
            SPPTestFeed(style % 3 == 2 ? 72 : 48, 60);   // vai kieu ve luc vuot gioi han
            return nil;
        }, ^NSString *{
            SPPTestFeed(style % 3 == 2 ? 72 : 48, 60);
            if (b.bubbleView.builtStyle != style) return SPPTestWhy(OMCTestFormat(@"dang ve kieu %ld", (long)b.bubbleView.builtStyle));
            return SPPTestVisibleOnCar();
        })];
    }
    [steps addObject:OMCTestStep(@"Tra lai kieu cua nguoi dung", 0.5, 3, ^NSString *{ SPPTestSetPref(SB_KEY_STYLE, sSPPTestStyle); return nil; },
        ^NSString *{ SPPTestFeed(48, 60); return b.bubbleView.builtStyle == [SPPPrefs style] ? nil : SPPTestWhy(@"kieu chua ve lai"); })];

    for (NSNumber *pct in @[@60, @220]) {
        [steps addObject:OMCTestStep(OMCTestFormat(@"Co %@%% tren xe", pct), 0.8, 4, ^NSString *{ SPPTestSetPref(SB_KEY_SIZE_CAR, pct); return nil; },
            ^NSString *{
            SPPTestFeed(48, 60);
            CGFloat want = SPP_SCALE_BASE * pct.doubleValue / 100.0;
            if (fabs(b.scale - want) > 0.02) return SPPTestWhy(OMCTestFormat(@"ti le %.2f, can %.2f", b.scale, want));
            return SPPTestVisibleOnCar();
        })];
    }
    [steps addObject:OMCTestStep(@"Tra lai co cua nguoi dung", 0.5, 3, ^NSString *{ SPPTestSetPref(SB_KEY_SIZE_CAR, sSPPTestSizeCar); return nil; },
        ^NSString *{ SPPTestFeed(48, 60); return SPPTestVisibleOnCar(); })];

    [steps addObject:OMCTestStep(@"Mat nguon toc do -> an", 1, 4, ^NSString *{ SPPTestEnd(); return nil; },
        ^NSString *{ return (!b.window || b.window.hidden || b.card.alpha < 0.1) ? nil : SPPTestWhy(@"van hien khi khong con nguon"); })];
    return steps;
}

void SPPAutoTestInstall(void)
{
    OMCTestRegister(SB_FEATURE, ^BOOL { return SPPGetCarPlayCADisplay() != nil; }, ^NSArray<NSDictionary *> *{ return SPPTestSteps(); }, ^NSArray<UIWindow *> *{
        UIWindow *w = [SPPBubble shared].window;
        return w ? @[w] : @[];
    });
}
#endif
