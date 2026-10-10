#import "common.h"
#import <substrate.h>

// Phan cua App Bridge chay TRONG app nguoi dung (dylib nap vao moi process UIKit, xem Filter.plist). Chi lam mot viec:
// khi SpringBoard dang host app nay tren man xe, ep app xoay theo huong cua o (AB_NOTIF_ORIENTATION), vi app ma giao
// dien chinh chi ho tro doc (YouTube, TikTok) se ve doc trong o ngang -> bi xoay 90 do.
//
// iOS 16 quyet dinh huong cua scene theo -[UIViewController supportedInterfaceOrientations] cua VC dang hien (giao voi
// -[UIApplication supportedInterfaceOrientationsForWindow:] / Info.plist), khong con theo _setRotatableViewOrientation:
// cua UIWindow (cach carplay-cast). Cac VC cua app override supportedInterfaceOrientations nen hook lop UIViewController
// khong an: luc nhan yeu cau, duyet VC dang hien (root, con, presented) va hook dung lop implement method do (MSHookMessageEx
// moi lop mot lan), tra ve mask cua huong ep; roi bao UIKit tinh lai (setNeedsUpdateOfSupportedInterfaceOrientations,
// attemptRotationToDeviceOrientation). Khong host nua (-1) thi thoi ep, app ve lai binh thuong tren iPhone.

static long long sForcedOrientation = -1;   // UIInterfaceOrientation dang ep, -1 = khong ep

static UIInterfaceOrientationMask ABMaskFor(long long o)
{
    switch (o) {
        case UIInterfaceOrientationPortrait:           return UIInterfaceOrientationMaskPortrait;
        case UIInterfaceOrientationPortraitUpsideDown: return UIInterfaceOrientationMaskPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:      return UIInterfaceOrientationMaskLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:     return UIInterfaceOrientationMaskLandscapeRight;
    }
    return UIInterfaceOrientationMaskAll;
}

// ---- Hook supportedInterfaceOrientations tren dung lop cua VC (moi lop mot lan) ----
static NSMutableDictionary<NSString *, NSValue *> *sOrigByClass;   // ten lop -> IMP goc

static UIInterfaceOrientationMask ABForcedSupportedOrientations(id self, SEL _cmd)
{
    if (sForcedOrientation > 0) return ABMaskFor(sForcedOrientation);
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        NSValue *v = sOrigByClass[NSStringFromClass(c)];
        if (v) return ((UIInterfaceOrientationMask (*)(id, SEL))[v pointerValue])(self, _cmd);
    }
    return UIInterfaceOrientationMaskAll;
}

static void ABHookOrientationOfVC(UIViewController *vc)
{
    if (!vc) return;
    SEL sel = @selector(supportedInterfaceOrientations);
    // Lop gan nhat (ke ca lop cha) co implement rieng supportedInterfaceOrientations
    Class c = object_getClass(vc);
    Method m = class_getInstanceMethod(c, sel);
    if (!m) return;
    Class owner = c;
    for (Class k = c; k; k = class_getSuperclass(k)) {
        unsigned n = 0; Method *ms = class_copyMethodList(k, &n); BOOL found = NO;
        for (unsigned i = 0; i < n; i++) if (method_getName(ms[i]) == sel) { found = YES; break; }
        free(ms);
        if (found) { owner = k; break; }
    }
    if (owner == [UIViewController class]) return;   // lop UIViewController da hook bang %hook ben duoi
    NSString *name = NSStringFromClass(owner);
    if (sOrigByClass[name]) return;
    IMP orig = NULL;
    MSHookMessageEx(owner, sel, (IMP)ABForcedSupportedOrientations, &orig);
    if (orig) sOrigByClass[name] = [NSValue valueWithPointer:(void *)orig];
    ABLog("hook supportedInterfaceOrientations cua %@", name);
}

static void ABWalkVC(UIViewController *vc, int depth)
{
    if (!vc || depth > 12) return;
    ABHookOrientationOfVC(vc);
    for (UIViewController *c in vc.childViewControllers) ABWalkVC(c, depth + 1);
    if (vc.presentedViewController) ABWalkVC(vc.presentedViewController, depth + 1);
}

static NSArray<UIWindow *> *ABWindows(void)
{
    NSMutableArray *out = [NSMutableArray array];
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        [out addObjectsFromArray:((UIWindowScene *)s).windows];
    }
    return out;
}

// Bao UIKit tinh lai huong cho moi cua so (iOS 16: setNeedsUpdateOfSupportedInterfaceOrientations; cu: attemptRotation...)
static void ABApplyForcedOrientation(void)
{
    for (UIWindow *w in ABWindows()) {
        UIViewController *root = w.rootViewController;
        if (sForcedOrientation > 0) ABWalkVC(root, 0);
        for (UIViewController *vc = root; vc; vc = vc.presentedViewController) {
            SEL need = NSSelectorFromString(@"setNeedsUpdateOfSupportedInterfaceOrientations");
            if ([vc respondsToSelector:need]) ((void (*)(id, SEL))objc_msgSend)(vc, need);
        }
        SEL rot = NSSelectorFromString(@"_setRotatableViewOrientation:duration:force:");
        if (sForcedOrientation > 0 && [w respondsToSelector:rot])
            ((void (*)(id, SEL, long long, double, BOOL))objc_msgSend)(w, rot, sForcedOrientation, 0.0, YES);
    }
    SEL attempt = NSSelectorFromString(@"attemptRotationToDeviceOrientation");
    if ([UIViewController respondsToSelector:attempt]) ((void (*)(id, SEL))objc_msgSend)([UIViewController class], attempt);
}

%group APPS

// VC khong override: lop goc
%hook UIViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if (sForcedOrientation > 0) return ABMaskFor(sForcedOrientation);
    return %orig;
}

- (BOOL)shouldAutorotate
{
    if (sForcedOrientation > 0) return YES;
    return %orig;
}

// VC vua hien (push / present sau khi da ep): hook lop cua no
- (void)viewDidAppear:(BOOL)animated
{
    %orig;
    if (sForcedOrientation > 0) {
        @try { ABHookOrientationOfVC(self); } @catch (NSException *e) {}
    }
}

%end

// Mask cua Info.plist (UISupportedInterfaceOrientations): app chi khai bao doc thi UIKit cung khong cho xoay
%hook UIApplication

- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
    if (sForcedOrientation > 0) return ABMaskFor(sForcedOrientation);
    return %orig;
}

%end

// UIKit sap xoay cua so (duong cu): dang ep thi luon xoay theo huong cua o
%hook UIWindow

- (void)_setRotatableViewOrientation:(long long)orientation duration:(double)duration force:(BOOL)force
{
    long long want = sForcedOrientation;
    if (want > 0 && orientation != want) {
        %orig(want, duration, force);
    } else {
        %orig;
    }
}

%end

%end // APPS

// AppDelegate co application:supportedInterfaceOrientationsForWindow: thi UIKit hoi no thay vi UIApplication -> hook lop delegate
static IMP sOrigDelegateMask;
static UIInterfaceOrientationMask ABDelegateMask(id self, SEL _cmd, UIApplication *app, UIWindow *window)
{
    if (sForcedOrientation > 0) return ABMaskFor(sForcedOrientation);
    return sOrigDelegateMask ? ((UIInterfaceOrientationMask (*)(id, SEL, id, id))sOrigDelegateMask)(self, _cmd, app, window) : UIInterfaceOrientationMaskAll;
}

static void ABHookDelegateOnce(void)
{
    static BOOL done;
    if (done) return;
    id delegate = [UIApplication sharedApplication].delegate;
    SEL sel = @selector(application:supportedInterfaceOrientationsForWindow:);
    if (!delegate || ![delegate respondsToSelector:sel]) return;
    done = YES;
    MSHookMessageEx(object_getClass(delegate), sel, (IMP)ABDelegateMask, &sOrigDelegateMask);
    ABLog("hook application:supportedInterfaceOrientationsForWindow: cua %@", NSStringFromClass(object_getClass(delegate)));
}

%ctor
{
    NSBundle *mb = [NSBundle mainBundle];
    NSString *bid = mb.bundleIdentifier;
    // Moi app co the duoc chon (app nguoi dung lan app he thong); khong dong vao SpringBoard / CarPlay / daemon
    if (!bid.length || ![mb.bundlePath containsString:@".app"]) return;
    if ([@[@"com.apple.springboard", @"com.apple.CarPlayApp", @"com.apple.CarPlayTemplateUIHost", @"com.apple.CarPlaySettings",
           @"com.apple.InCallService", @"com.apple.Preferences"] containsObject:bid]) return;
    sOrigByClass = [NSMutableDictionary dictionary];
    %init(APPS);
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:AB_NOTIF_ORIENTATION object:bid queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        long long o = [note.userInfo[@"orientation"] longLongValue];
        sForcedOrientation = (o > 0) ? o : -1;
        ABLog("%@: ep huong %lld", bid, sForcedOrientation);
        @try {
            if (sForcedOrientation > 0) ABHookDelegateOnce();
            ABApplyForcedOrientation();
        } @catch (NSException *e) { ABLog("%@: ep huong loi %@", bid, e); }
    }];
}
