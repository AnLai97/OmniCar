#import "common.h"
#import <notify.h>

// Phan cua App Bridge chay TRONG app (dylib nap vao moi process UIKit, xem Filter.plist). Port tu CarDuo 1.0
// (src/hooks/UIApplication.xm), bo thiet ke da chay duoc YouTube tren xe:
//  - SpringBoard gui huong GOC cua o (AB_NOTIF_ORIENTATION: orientation, mac dinh doc) + huong "thiet bi" gia (device).
//    App chi bi xoay ve huong do khi no CON CHO PHEP huong do; app chi cho ngang (video fullscreen) thi de UIKit theo app.
//  - App xin huong khac (YouTube fullscreen: requestGeometryUpdateWithPreferences:, setOrientation:, doi mask
//    supportedInterfaceOrientations) -> bao SpringBoard qua Darwin notify + state (AB_DARWIN_APP_ORIENT), SpringBoard
//    doi huong scene cho app. Huong "thiet bi" gia + su kien xoay gia de YouTube bam fullscreen thi xin ngang that.
//  - -1 = khong host nua: thoi moi can thiep.

static int orientationOverride = -1;        // huong goc cua o SpringBoard gui, -1 = khong host
static long long appWantsOrientation = 0;   // huong app TU XIN (fullscreen video -> ngang); 0 = theo huong cua o
static int fakeDeviceOrientation = 0;       // huong "thiet bi" gia (SpringBoard gui), 0 = dung huong that
static NSUInteger ABAppEffectiveMask(void);

// Phat su kien "thiet bi vua xoay" (gia) sau `delay` giay
static void ABPostFakeDeviceRotation(double delay)
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (fakeDeviceOrientation <= 0) return;
        NSUInteger m = ABAppEffectiveMask();
        if (!(m & UIInterfaceOrientationMaskPortrait)) { ABLog("bo qua su kien xoay gia: app dang chi cho mask %lu", (unsigned long)m); return; }
        [[NSNotificationCenter defaultCenter] postNotificationName:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
    });
}

static long long ABEffectiveOrientation(void)
{
    return appWantsOrientation > 0 ? appWantsOrientation : orientationOverride;
}

// Mask huong ma cua so DANG cho phep: VC tren cung cua chuoi present
static NSUInteger ABWindowMask(UIWindow *w)
{
    UIViewController *vc = w.rootViewController;
    if (!vc) return UIInterfaceOrientationMaskAll;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    NSUInteger mask = vc.supportedInterfaceOrientations;
    return mask ? mask : UIInterfaceOrientationMaskAll;
}

// Duyet cay VC (con + presented) dang hien: co VC nao chi cho NGANG -> tra mask do (YouTube fullscreen: VC goc van
// tra "doc", nhung VC con fullscreen tra "ngang")
static NSUInteger ABLandscapeOnlyMaskInTree(UIViewController *vc, int depth)
{
    if (!vc || depth > 12) return 0;
    if (vc.isViewLoaded && vc.view.window && !vc.view.hidden) {
        NSUInteger m = vc.supportedInterfaceOrientations;
        if (m && !(m & UIInterfaceOrientationMaskPortrait) && (m & UIInterfaceOrientationMaskLandscape)) return m;
    }
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        NSUInteger m = ABLandscapeOnlyMaskInTree(vc.presentedViewController, depth + 1);
        if (m) return m;
    }
    for (UIViewController *c in vc.childViewControllers) {
        NSUInteger m = ABLandscapeOnlyMaskInTree(c, depth + 1);
        if (m) return m;
    }
    return 0;
}

static UIWindow *ABBestWindow(void)
{
    UIWindow *best = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) {
            if (!w.rootViewController || w.hidden) continue;
            if (w.isKeyWindow) { best = w; break; }
            if (!best) best = w;
        }
        if (best && best.isKeyWindow) break;
    }
    return best;
}

// Mask hieu luc cua ca app: uu tien VC chi-cho-ngang dang hien, khong thi VC tren cung cua cua so key
static NSUInteger ABAppEffectiveMask(void)
{
    UIWindow *best = ABBestWindow();
    if (!best) return UIInterfaceOrientationMaskAll;
    NSUInteger landscapeOnly = ABLandscapeOnlyMaskInTree(best.rootViewController, 0);
    if (landscapeOnly) return landscapeOnly;
    return ABWindowMask(best);
}

// Bao SpringBoard (Darwin notify + state): app vua doi yeu cau xoay. Gom cac lan goi lien tiep, gui mask cuoi sau 0.25s
static void ABTellSpringBoardNow(long long o)
{
    static int token = 0;
    if (!token) notify_register_check(AB_DARWIN_APP_ORIENT, &token);
    NSUInteger mask = ABAppEffectiveMask();
    uint64_t state = (ABBundleHash([[NSBundle mainBundle] bundleIdentifier]) << 24) | (((uint64_t)mask & 0xFFFF) << 8) | ((uint64_t)o & 0xFF);
    notify_set_state(token, state);
    notify_post(AB_DARWIN_APP_ORIENT);
    ABLog("bao SpringBoard: ma %lld, mask %lu", o, (unsigned long)mask);
}

static void ABTellSpringBoard(long long o)
{
    static dispatch_block_t pending = nil;
    if (pending) { dispatch_block_cancel(pending); pending = nil; }
    pending = dispatch_block_create((dispatch_block_flags_t)0, ^{
        pending = nil;
        ABTellSpringBoardNow(o);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), pending);
}

// Mask app xin -> 1 huong cu the. Co doc thi coi nhu "tra ve binh thuong" (0)
static long long ABOrientationFromMask(NSUInteger mask)
{
    if (mask & UIInterfaceOrientationMaskPortrait) return 0;
    if (mask & UIInterfaceOrientationMaskLandscapeLeft)  return UIInterfaceOrientationLandscapeLeft;
    if (mask & UIInterfaceOrientationMaskLandscapeRight) return UIInterfaceOrientationLandscapeRight;
    if (mask & UIInterfaceOrientationMaskPortraitUpsideDown) return UIInterfaceOrientationPortraitUpsideDown;
    return 0;
}

// SpringBoard gui huong cua o
static void ABHandleOrientationRequest(NSDictionary *info)
{
    int newOverride = [info[@"orientation"] intValue];
    BOOL changed = (newOverride != orientationOverride);
    orientationOverride = newOverride;
    appWantsOrientation = 0;
    fakeDeviceOrientation = (orientationOverride > 0) ? [info[@"device"] intValue] : 0;
    ABLog("huong o %d, thiet bi gia %d (doi=%d)", orientationOverride, fakeDeviceOrientation, (int)changed);
    if (!changed) return;   // khong doi -> khong ep xoay, khong phat su kien xoay (tranh YouTube tu vao/ra fullscreen)
    // YouTube chi xin ngang khi bam fullscreen neu truoc do DA nhan 1 su kien xoay thiet bi. Phat vai lan sau khi app len
    if (fakeDeviceOrientation > 0) for (NSNumber *d in @[@0.3, @1.5, @4.0]) ABPostFakeDeviceRotation(d.doubleValue);

    int o = orientationOverride;
    if (o == -1) o = MAX(1, (int)[[UIDevice currentDevice] orientation]);
    // Khong ep sang huong app dang khong cho phep (vd fullscreen video chi ngang)
    NSUInteger mask = ABAppEffectiveMask();
    if (o > 0 && !(mask & (1u << o))) { ABLog("bo qua ep xoay %d: app chi cho mask %lu", o, (unsigned long)mask); return; }
    UIWindow *key = ABBestWindow();
    SEL sel = NSSelectorFromString(@"_setRotatableViewOrientation:duration:force:");
    if (key && [key respondsToSelector:sel]) ((void (*)(id, SEL, long long, double, BOOL))objc_msgSend)(key, sel, (long long)o, 0.0, YES);
}

%group APPS

%hook UIWindow

- (void)_setRotatableViewOrientation:(long long)orientation duration:(double)duration force:(BOOL)force
{
    long long target = ABEffectiveOrientation();
    NSUInteger mask = ABWindowMask(self);
    // Chi ep ve huong cua o khi app con cho phep huong do; app dang chi cho ngang (fullscreen video) -> theo app
    BOOL canForce = target > 0 && (mask & (1u << target)) != 0;
    if (canForce && orientation != target) {
        %orig(target, duration, force);
    } else {
        %orig;
    }
}

%end

// iOS 16: app xin xoay bang requestGeometryUpdateWithPreferences: (YouTube fullscreen)
%hook UIWindowScene

- (void)requestGeometryUpdateWithPreferences:(id)prefs errorHandler:(id)handler
{
    if (orientationOverride > 0 && [prefs respondsToSelector:@selector(interfaceOrientations)]) {
        NSUInteger mask = ((NSUInteger (*)(id, SEL))objc_msgSend)(prefs, @selector(interfaceOrientations));
        appWantsOrientation = ABOrientationFromMask(mask);
        ABLog("app xin huong mask=%lu -> %lld", (unsigned long)mask, appWantsOrientation);
        ABTellSpringBoard(appWantsOrientation);
    }
    %orig;
}

%end

// App doi danh sach huong ho tro (iOS 16) -> SpringBoard lay lai scene
%hook UIViewController

- (void)setNeedsUpdateOfSupportedInterfaceOrientations
{
    %orig;
    if (orientationOverride > 0) ABTellSpringBoard(0xFF);
}

%end

// App cu: ep xoay bang [UIDevice setOrientation:]; app hoi huong thiet bi -> tra loi theo huong dang ap
%hook UIDevice

- (void)beginGeneratingDeviceOrientationNotifications
{
    %orig;
    if (fakeDeviceOrientation > 0) ABPostFakeDeviceRotation(0.2);
}

- (void)setOrientation:(long long)orientation animated:(BOOL)animated
{
    if (orientationOverride > 0) {
        appWantsOrientation = (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) ? orientation : 0;
        ABLog("app setOrientation %lld -> %lld", orientation, appWantsOrientation);
        ABTellSpringBoard(appWantsOrientation);
    }
    %orig;
}

- (long long)orientation
{
    if (appWantsOrientation > 0) return appWantsOrientation;   // gia tri so trung nhau giua UIInterface / UIDeviceOrientation
    if (fakeDeviceOrientation > 0) return fakeDeviceOrientation;
    return %orig;
}

%end

%end // APPS

%ctor
{
    NSBundle *mb = [NSBundle mainBundle];
    NSString *bid = mb.bundleIdentifier;
    // Moi app co the duoc chon (app nguoi dung lan app he thong); khong dong vao SpringBoard / CarPlay / daemon
    if (!bid.length || ![mb.bundlePath containsString:@".app"]) return;
    if ([@[@"com.apple.springboard", @"com.apple.CarPlayApp", @"com.apple.CarPlayTemplateUIHost", @"com.apple.CarPlaySettings",
           @"com.apple.InCallService", @"com.apple.Preferences"] containsObject:bid]) return;
    %init(APPS);
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:AB_NOTIF_ORIENTATION object:bid queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        @try { ABHandleOrientationRequest(note.userInfo); } @catch (NSException *e) { ABLog("%@: xoay loi %@", bid, e); }
    }];
}
