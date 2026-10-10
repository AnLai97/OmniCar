#import "ABHost.h"
#import "common.h"

// =====================================================================
//  ABHost - iPhone apps on the car screen, hosted by SpringBoard.
//  Ported from CarDuo 1.0's SCPSplitWindow (itself a port of carplay-cast's CRCarplayWindow, iOS 16.x
//  selectors): SBSceneManagerCoordinator -> scene identity -> SBApplicationSceneHandleRequest ->
//  SBDeviceApplicationSceneEntity -> SBAppViewController, whose view is placed in a box of our
//  UIRootSceneWindow on the car display. The scene gets the box size (divided by zoom) as its frame, so
//  the app lays itself out for the pane instead of being scaled from the phone size.
// =====================================================================

void ABMissingSelector(id obj, NSString *sel)
{
    if (!obj) return;
    static NSMutableSet<NSString *> *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    NSString *key = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([obj class]), sel];
    @synchronized (seen) {
        if ([seen containsObject:key]) return;
        [seen addObject:key];
    }
    ABLog("THIEU METHOD: %@ khong co %@ -> bo qua", NSStringFromClass([obj class]), sel);
}

#define getIvar(object, ivar)        [object valueForKey:ivar]
#define setIvar(object, ivar, value) [object setValue:value forKey:ivar]

// CADisplay cua man hinh xe (nil neu chua ket noi)
static id ABCarDisplay(void)
{
    id dev = objcInvoke(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice");
    NSArray *ids = dev ? objcInvoke(dev, @"screenIDs") : nil;
    if (!ids.count) return nil;
    for (id display in objcInvoke(objc_getClass("CADisplay"), @"displays")) {
        if ([ids[0] isEqualToString:objcInvoke(display, @"uniqueId")]) return display;
    }
    return nil;
}

// Cua so cua SpringBoard tren man xe (UIRootSceneWindow), nil neu xe chua ket noi
static UIWindow *ABMakeCarWindow(void)
{
    id display = ABCarDisplay();
    if (!display) { ABLog("khong tim thay CADisplay cua CarPlay"); return nil; }
    id config = objcInvoke_2([objc_getClass("FBSDisplayConfiguration") alloc], @"initWithCADisplay:isMainDisplay:", display, 0);
    if (!config) { ABLog("khong tao duoc FBSDisplayConfiguration"); return nil; }
    UIWindow *w = objcInvoke_1([objc_getClass("UIRootSceneWindow") alloc], @"initWithDisplayConfiguration:", config);
    if (![w isKindOfClass:[UIWindow class]]) { ABLog("khong tao duoc UIRootSceneWindow: %@", w); return nil; }
    return w;
}

// Cua so phu kin man xe nhung cho cham xuyen qua o moi cho khong co o app (doi class cua instance luc chay)
static UIView *ABPassThroughHitTest(id self, SEL _cmd, CGPoint p, UIEvent *e)
{
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    UIView *v = ((UIView *(*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
    return (v == self) ? nil : v;
}

static void ABMakeWindowPassThrough(UIWindow *w)
{
    Class base = object_getClass(w);
    NSString *name = [NSString stringWithFormat:@"ABPassThrough_%@", NSStringFromClass(base)];
    Class cls = objc_getClass(name.UTF8String);
    if (!cls) {
        cls = objc_allocateClassPair(base, name.UTF8String, 0);
        Method m = class_getInstanceMethod(base, @selector(hitTest:withEvent:));
        class_addMethod(cls, @selector(hitTest:withEvent:), (IMP)ABPassThroughHitTest, method_getTypeEncoding(m));
        objc_registerClassPair(cls);
    }
    object_setClass(w, cls);
}

static void ABPostState(NSString *bid, NSString *state)
{
    if (!bid) return;
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        postNotificationName:AB_NOTIF_STATE object:nil userInfo:@{@"identifier": bid, @"state": state}];
}

// Bao app (App.xm trong app) huong goc cua o + huong "thiet bi" gia (CO DINH = huong cua o: doi theo hinh dang o thi
// YouTube coi nhu may vua xoay, tu vao/ra fullscreen khi keo vach); -1 = thoi host (app ve lai binh thuong tren iPhone)
static void ABPostOrientation(NSString *bid, long long orientation)
{
    if (!bid) return;
    long long device = orientation > 0 ? orientation : 0;
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        postNotificationName:AB_NOTIF_ORIENTATION object:bid userInfo:@{@"orientation": @(orientation), @"device": @(device)}];
}

// Khung o: cham trong dai passInsets sat mep (canh giap o khac) khong tinh la cham vao o -> cua so (pass-through)
// tra nil -> CarPlay nhan cham de keo vach. Thanh "•••" van cham duoc.
@interface ABBoxView : UIView
@property (nonatomic) UIEdgeInsets passInsets;
@property (nonatomic, weak) UIView *handleHit;
@property (nonatomic, weak) UIView *bar;           // thanh nut ve de len app: luon nhan cham
@end
@implementation ABBoxView
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e
{
    if (![super pointInside:p withEvent:e]) return NO;
    if (self.handleHit && !self.handleHit.hidden && CGRectContainsPoint(self.handleHit.frame, p)) return YES;
    if (self.bar && !self.bar.hidden && CGRectContainsPoint(self.bar.frame, p)) return YES;
    return CGRectContainsPoint(UIEdgeInsetsInsetRect(self.bounds, self.passInsets), p);
}
@end

// Nut tron 34pt cua thanh nut, vung cham 44pt, nhun khi bam (SCPCButton ben CarPlay)
@interface ABBarButton : UIButton
@end
@implementation ABBarButton
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

// Mot o chua mot app
@interface ABPane : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) ABBoxView *box;          // khung o trong cua so (toa do man xe)
@property (nonatomic, strong) id application;          // SBApplication
@property (nonatomic, strong) id appViewController;    // SBAppViewController
@property (nonatomic, strong) id sceneMonitor;         // FBSceneMonitor
@property (nonatomic) long long orientation;           // huong goc cua o (AB_KEY_ORIENTATION, mac dinh doc), KHONG theo hinh dang o
@property (nonatomic) long long requestedOrientation;  // huong app tu xin (YouTube fullscreen -> ngang), 0 = theo orientation
@property (nonatomic) CGRect frame;                    // khung muon (live hay khong)
@property (nonatomic) CGSize sceneBox;                 // kich thuoc o da bao cho scene lan cuoi
@property (nonatomic) BOOL ready;
@property (nonatomic, strong) UIView *handle;          // thanh "•••" mo tren app
@property (nonatomic, strong) UIView *handleHit;       // vung cham cua thanh
@property (nonatomic, strong) UIView *bar;             // thanh nut cua o (doi app / noi / toan man / dong) ve de len app
@property (nonatomic, strong) UIButton *popButton;     // nut noi / ghim tren thanh (glyph doi theo "pop")
@property (nonatomic) CGFloat handleOffset;            // thanh "•••" lech ngang (hx tu CarPlay)
@end
@implementation ABPane
@end

@interface ABHost ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, copy) NSString *displayID;
@property (nonatomic, strong) NSMutableArray<ABPane *> *panes;
@end

@implementation ABHost

+ (instancetype)shared
{
    static ABHost *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ABHost new]; s.panes = [NSMutableArray array]; });
    return s;
}

- (NSUInteger)count { return self.panes.count; }

- (BOOL)hostsApp:(NSString *)bid
{
    if (!bid) return NO;
    for (ABPane *p in self.panes) if ([p.bundleID isEqualToString:bid]) return YES;
    return NO;
}

- (ABPane *)paneFor:(NSString *)bid
{
    for (ABPane *p in self.panes) if ([p.bundleID isEqualToString:bid]) return p;
    return nil;
}

// Ti le thu nho noi dung app (Cai dat > App Bridge)
- (CGFloat)zoom
{
    OMCPrefsSync();
    double z = [OMCPref(AB_KEY_ZOOM, @80) doubleValue] / 100.0;
    return MIN(1.0, MAX(0.6, z));
}

#pragma mark - Cua so

- (BOOL)ensureWindow
{
    id display = ABCarDisplay();
    NSString *did = display ? objcInvoke(display, @"uniqueId") : nil;
    if (!did) return NO;
    if (self.window && ![did isEqualToString:self.displayID]) { self.window.hidden = YES; self.window = nil; }
    if (self.window) return YES;
    UIWindow *w = ABMakeCarWindow();
    if (!w) return NO;
    ABMakeWindowPassThrough(w);
    w.windowLevel = UIWindowLevelStatusBar + 60;   // tren noi dung CarPlay, duoi bong bong toc do (+70)
    w.backgroundColor = [UIColor clearColor];
    w.hidden = NO;
    self.window = w;
    self.displayID = did;
    ABLog("cua so tren man xe %@ (%@)", NSStringFromCGRect(w.bounds), did);
    return YES;
}

// Het o: GIU cua so (rong, pass-through, vo hai). Huy roi tao lai UIRootSceneWindow tren man xe thi cua so moi khong hien
// len tren CarPlay nua (log 10/10 15:30: YouTube vao o / toan man sau khi dong o cuoi -> chi thay man chinh CarPlay).
// Chi bo cua so khi xe ngat (carDisconnected) hoac man xe doi (ensureWindow).
- (void)dropWindowIfEmpty
{
}

#pragma mark - Mo app

- (void)openApp:(NSString *)bid frame:(CGRect)frame
{
    if (!bid.length) return;
    if (!OMCFeatureEnabled(AB_FEATURE)) { ABLog("tat trong Cai dat -> khong host %@", bid); ABPostState(bid, @"failed"); return; }
    ABPane *existing = [self paneFor:bid];
    if (existing) { [self setFrame:frame forApp:bid live:NO handle:YES passInsets:existing.box.passInsets]; return; }
    if (![self ensureWindow]) { ABLog("xe chua ket noi -> khong host %@", bid); ABPostState(bid, @"failed"); return; }

    ABPane *pane = [ABPane new];
    pane.bundleID = bid;
    pane.frame = frame;
    // Huong goc: doc (o rong = cua so doc rong). App chi ho tro doc (YouTube) ma ep ngang thi ve nghieng; app can ngang
    // (video fullscreen) se tu xin qua AB_DARWIN_APP_ORIENT -> requestedOrientation
    OMCPrefsSync();
    long long base = [OMCPref(AB_KEY_ORIENTATION, @1) longLongValue];
    pane.orientation = (base == UIInterfaceOrientationLandscapeLeft || base == UIInterfaceOrientationLandscapeRight) ? base : UIInterfaceOrientationPortrait;
    pane.box = [[ABBoxView alloc] initWithFrame:frame];
    pane.box.backgroundColor = [UIColor blackColor];
    pane.box.clipsToBounds = YES;
    pane.box.alpha = 0;   // hien dan khi app san sang (afterLaunch), khong nhay cuc
    [self.window addSubview:pane.box];
    [self setupHandleForPane:pane];
    [self.panes addObject:pane];

    @try {
        [self setupLiveAppViewForPane:pane];
    } @catch (NSException *e) {
        ABLog("host %@ that bai: %@", bid, e);
        [self.panes removeObject:pane];
        [pane.box removeFromSuperview];
        [self dropWindowIfEmpty];
        ABPostState(bid, @"failed");
        return;
    }
    [self layoutPane:pane];
    ABLog("host %@ tai %@ (huong %lld, zoom %.2f)", bid, NSStringFromCGRect(frame), pane.orientation, [self zoom]);
    // Khong co tin "launch xong" (app da chay san) thi van bao ready sau 2.5s
    __weak ABPane *weakPane = pane;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ABPane *p = weakPane;
        if (p && [self.panes containsObject:p]) [self revealPane:p];
        if (p && !p.ready && [self.panes containsObject:p]) { p.ready = YES; ABPostState(p.bundleID, @"ready"); }
    });
}

// O hien dan (0.25s) khi app san sang
- (void)revealPane:(ABPane *)pane
{
    if (pane.box.alpha >= 1) return;
    [UIView animateWithDuration:0.25 animations:^{ pane.box.alpha = 1; }];
}

// Port tu CRCarplayWindow -setupLiveAppView (carplay-cast), selector iOS 16.x
- (void)setupLiveAppViewForPane:(ABPane *)pane
{
    NSString *appID = pane.bundleID;
    pane.application = objcInvoke_1(objcInvoke(objc_getClass("SBApplicationController"), @"sharedInstance"),
                                    @"applicationWithBundleIdentifier:", appID);
    expectClass(pane.application, "SBApplication");

    id sceneManager = objcInvoke(objc_getClass("SBSceneManagerCoordinator"), @"mainDisplaySceneManager");
    expectClass(sceneManager, "SBMainDisplaySceneManager");
    id layoutStateManager = objcInvoke(sceneManager, @"layoutStateManager");
    id displayIdentity    = objcInvoke(sceneManager, @"displayIdentity");
    expectClass(displayIdentity, "FBSDisplayIdentity");

    id sceneIdentity = objcInvoke_3(sceneManager, @"sceneIdentityForApplication:createPrimaryIfRequired:sceneSessionRole:",
                                    pane.application, 1, UIWindowSceneSessionRoleApplication);
    expectClass(sceneIdentity, "FBSSceneIdentity");
    id request = objcInvoke_3(objc_getClass("SBApplicationSceneHandleRequest"),
                              @"defaultRequestForApplication:sceneIdentity:displayIdentity:",
                              pane.application, sceneIdentity, displayIdentity);
    expectClass(request, "SBApplicationSceneHandleRequest");
    id sceneHandle = objcInvoke_1(sceneManager, @"fetchOrCreateApplicationSceneHandleForRequest:", request);
    expectClass(sceneHandle, "SBDeviceApplicationSceneHandle");
    id entity = objcInvoke_1([objc_getClass("SBDeviceApplicationSceneEntity") alloc], @"initWithApplicationSceneHandle:", sceneHandle);
    expectClass(entity, "SBDeviceApplicationSceneEntity");
    id appVC = objcInvoke_2([objc_getClass("SBAppViewController") alloc], @"initWithIdentifier:andApplicationSceneEntity:", appID, entity);
    expectClass(appVC, "SBAppViewController");
    pane.appViewController = appVC;

    objcCall_1(appVC, @"setIgnoresOcclusions:", (BOOL)0);
    setIvar(appVC, @"_currentMode", @(2));
    objcCall(getIvar(appVC, @"_activationSettings"), @"clearActivationSettings");

    id transaction = objcInvoke_2(appVC, @"_createSceneUpdateTransactionForApplicationSceneEntity:deliveringActions:", entity, (BOOL)1);
    expectClass(transaction, "SBApplicationSceneUpdateTransaction");
    NSMutableSet *transitions = getIvar(appVC, @"_activeTransitions");
    __weak ABHost *weakSelf = self;
    __weak ABPane *weakPane = pane;
    objcCall_1(transaction, @"setCompletionBlock:", ^(int result) {
        [transitions removeObject:transaction];
        id launchTx = getIvar(transaction, @"_processLaunchTransaction");
        id process  = launchTx ? objcInvoke(launchTx, @"process") : nil;
        void (^afterLaunch)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                ABPane *p = weakPane;
                ABHost *me = weakSelf;
                if (!p || !me || ![me.panes containsObject:p]) return;
                ABPostOrientation(p.bundleID, p.orientation);   // App.xm trong app: huong cua o + huong "thiet bi" gia
                [me layoutPane:p];
                [me revealPane:p];
                if (!p.ready) { p.ready = YES; ABPostState(p.bundleID, @"ready"); }
            });
        };
        if (process) objcCall_1(process, @"_executeBlockAfterLaunchCompletes:", afterLaunch);
        else { ABLog("khong co FBProcess sau launch (result=%d), coi nhu da chay", result); afterLaunch(); }
    });
    [transitions addObject:transaction];
    objcCall(transaction, @"begin");
    objcCall(appVC, @"_createSceneViewController");

    id animFactory = objcInvoke(objc_getClass("SBApplicationSceneView"), @"defaultDisplayModeAnimationFactory");
    id appView = objcInvoke(appVC, @"appView");
    ((void (*)(id, SEL, long long, id, id))objc_msgSend)(appView, NSSelectorFromString(@"setDisplayMode:animationFactory:completion:"), 4, animFactory, nil);

    UIView *v = [appVC view];
    v.backgroundColor = [UIColor clearColor];
    [pane.box insertSubview:v atIndex:0];

    NSString *sceneID = objcInvoke_3(layoutStateManager, @"primarySceneIdentifierForBundleIdentifier:sceneSessionRole:displayIdentity:",
                                     appID, UIWindowSceneSessionRoleApplication, displayIdentity);
    if (sceneID) {
        pane.sceneMonitor = objcInvoke_1([objc_getClass("FBSceneMonitor") alloc], @"initWithSceneID:", sceneID);
        objcCall_1(pane.sceneMonitor, @"setDelegate:", self);
    }
}

// FBSceneMonitorDelegate: app thoat / scene bi huy -> bo o, bao CarPlay
- (void)sceneMonitor:(id)monitor sceneWasDestroyed:(id)scene
{
    for (ABPane *p in [self.panes copy]) {
        if (p.sceneMonitor != monitor) continue;
        ABLog("scene cua %@ bi huy -> bo o", p.bundleID);
        NSString *bid = p.bundleID;
        [self teardownPane:p];
        [self.panes removeObject:p];
        [self dropWindowIfEmpty];
        ABPostState(bid, @"gone");
        return;
    }
}

#pragma mark - Bo cuc

// Resize scene cua app theo dung kich thuoc o (app tu bo cuc lai, khong phai chieu thu nho tu man iPhone).
// Noi dung ve o (o / zoom) roi thu nho bang transform de chu va nut khong qua to tren man xe.
- (void)layoutPane:(ABPane *)pane
{
    if (!pane.appViewController) return;
    CGSize boxSize = pane.box.bounds.size;
    if (boxSize.width < 2 || boxSize.height < 2) return;
    CGFloat z = [self zoom];
    CGSize paneSize = CGSizeMake(round(boxSize.width / z), round(boxSize.height / z));
    UIView *appView = [pane.appViewController view];
    appView.transform = CGAffineTransformIdentity;
    appView.frame = CGRectMake(0, 0, paneSize.width, paneSize.height);
    appView.transform = CGAffineTransformMakeScale(z, z);
    appView.center = CGPointMake(boxSize.width / 2, boxSize.height / 2);
    id deviceAppVC = nil, sceneView = nil; UIView *hostingContentView = nil;
    @try {
        deviceAppVC = getIvar(pane.appViewController, @"_deviceAppViewController");
        sceneView   = deviceAppVC ? getIvar(deviceAppVC, @"sceneView") : nil;
        hostingContentView = sceneView ? getIvar(sceneView, @"_sceneContentContainerView") : nil;
    } @catch (NSException *e) {}
    hostingContentView.transform = CGAffineTransformIdentity;

    id scene = objcInvoke(objcInvoke(pane.appViewController, @"sceneHandle"), @"sceneIfExists");
    if (!scene) return;
    // Huong dat thang vao scene settings (duong UIKit thuc su nghe): app xin huong khac thi theo app, khong thi huong goc cua o
    long long orient = [self effectiveOrientation:pane];
    // Khung scene tinh theo toa do DOC cua man hinh: giao dien ngang thi UIKit tu hoan doi rong/cao, nen gui (cao x rong)
    BOOL landscape = (orient == UIInterfaceOrientationLandscapeLeft || orient == UIInterfaceOrientationLandscapeRight);
    CGRect target = landscape ? CGRectMake(0, 0, paneSize.height, paneSize.width) : CGRectMake(0, 0, paneSize.width, paneSize.height);
    @try {
        objcCall_1(scene, @"updateSettingsWithBlock:", ^(id settings) {
            ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, NSSelectorFromString(@"setFrame:"), target);
            if ([settings respondsToSelector:NSSelectorFromString(@"setInterfaceOrientation:")])
                ((void (*)(id, SEL, long long))objc_msgSend)(settings, NSSelectorFromString(@"setInterfaceOrientation:"), orient);
            // Scene phai foreground moi ve: host lai ngay sau khi dong (teardown da cho scene ve nen) thi o den
            // (log 10/10 16:01: YouTube vao o 140ms sau khi dong cua so toan man). carplay-cast cung dat o day.
            objcCall_1(settings, @"setBackgrounded:", (BOOL)NO);
            objcCall_1(settings, @"setForeground:", (BOOL)YES);
        });
    } @catch (NSException *e) { ABLog("updateSettings %@ loi %@", pane.bundleID, e); }
    pane.sceneBox = boxSize;
}

- (long long)effectiveOrientation:(ABPane *)pane
{
    return pane.requestedOrientation > 0 ? pane.requestedOrientation : pane.orientation;
}

// App bao vua doi yeu cau xoay (code: huong muon, 0 = ve huong o, 0xFF = chi doi mask -> suy ra tu mask): dat
// requestedOrientation roi "lay" scene (khung lech 1pt, ngay sau do khung dung) de UIKit trong app tinh lai huong
- (void)appWithHash:(unsigned long long)hash changedOrientation:(int)code supportedMask:(NSUInteger)mask
{
    for (ABPane *p in self.panes) {
        if (ABBundleHash(p.bundleID) != hash) continue;
        long long want = 0;
        if (code != 0xFF) want = code;
        else if (mask && !(mask & UIInterfaceOrientationMaskPortrait)) {
            // App khong con cho phep doc (fullscreen video) -> xoay scene sang huong no cho phep
            if (mask & UIInterfaceOrientationMaskLandscapeLeft)            want = UIInterfaceOrientationLandscapeLeft;
            else if (mask & UIInterfaceOrientationMaskLandscapeRight)      want = UIInterfaceOrientationLandscapeRight;
            else if (mask & UIInterfaceOrientationMaskPortraitUpsideDown)  want = UIInterfaceOrientationPortraitUpsideDown;
        }
        p.requestedOrientation = want;
        ABLog("%@ doi yeu cau xoay (ma %d, mask %lu) -> scene huong %lld", p.bundleID, code, (unsigned long)mask, [self effectiveOrientation:p]);
        [self nudgePane:p];
        return;
    }
    ABLog("apporient: khong co o cho hash %llu", hash);
}

- (void)nudgePane:(ABPane *)pane
{
    id scene = objcInvoke(objcInvoke(pane.appViewController, @"sceneHandle"), @"sceneIfExists");
    if (!scene) return;
    CGFloat z = [self zoom];
    CGSize box = pane.box.bounds.size;
    CGSize sz = CGSizeMake(round(box.width / z), round(box.height / z));
    long long o = [self effectiveOrientation:pane];
    BOOL landscape = (o == UIInterfaceOrientationLandscapeLeft || o == UIInterfaceOrientationLandscapeRight);
    CGRect off = landscape ? CGRectMake(0, 0, sz.height, MAX(1, sz.width - 1)) : CGRectMake(0, 0, sz.width, MAX(1, sz.height - 1));
    @try {
        objcCall_1(scene, @"updateSettingsWithBlock:", ^(id settings) {
            ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, NSSelectorFromString(@"setFrame:"), off);
        });
    } @catch (NSException *e) { ABLog("nudge %@ loi %@", pane.bundleID, e); }
    __weak ABHost *weakSelf = self;
    __weak ABPane *weakPane = pane;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ABPane *p = weakPane;
        if (p) [weakSelf layoutPane:p];
    });
}

- (void)setFrame:(CGRect)frame forApp:(NSString *)bid live:(BOOL)live handle:(BOOL)handle passInsets:(UIEdgeInsets)pass
{
    ABPane *p = [self paneFor:bid];
    if (!p) return;
    BOOL hidden = frame.size.width < 2 || frame.size.height < 2;
    p.box.hidden = hidden;
    p.box.passInsets = pass;
    [self setHandleVisible:handle && !hidden forPane:p];
    if (hidden) return;
    CGRect old = p.frame;
    p.frame = frame;
    if (live) {   // dang keo vach: o chay theo tay, noi dung giu nguyen (scene doi kich thuoc khi tha tay)
        p.box.frame = frame;
        UIView *appView = [p.appViewController view];
        appView.center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
        [self layoutBarForPane:p];
        return;
    }
    // Khung o truot muot toi vi tri moi (doi bo cuc / toan man); scene doi kich thuoc ngay
    BOOL moved = !CGRectEqualToRect(old, frame) && !CGRectIsEmpty(old);
    [UIView animateWithDuration:(moved ? 0.25 : 0) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        p.box.frame = frame;
        [self layoutBarForPane:p];
        [self setHandleVisible:!p.handleHit.hidden forPane:p];
    } completion:nil];
    // Huong KHONG doi theo hinh dang o (xem openApp); chi scene doi kich thuoc
    if (!CGSizeEqualToSize(p.sceneBox, frame.size)) {
        [self layoutPane:p];
        ABLog("%@ -> %@ (huong %lld)", bid, NSStringFromCGRect(frame), [self effectiveOrientation:p]);
    } else {
        [p.appViewController view].center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
    }
}

- (void)setPassInsets:(UIEdgeInsets)pass forApp:(NSString *)bid
{
    ABPane *p = [self paneFor:bid];
    if (p) p.box.passInsets = pass;
}

// Bo goc cua o nhu o CarPlay ben duoi (goc giap o khac bo 12pt, goc sat mep man vuong; cua so noi 4 goc)
- (void)setCornerRadius:(CGFloat)radius corners:(CACornerMask)corners forApp:(NSString *)bid
{
    ABPane *p = [self paneFor:bid];
    if (!p) return;
    p.box.layer.cornerRadius = radius;
    p.box.layer.maskedCorners = corners;
    p.box.layer.cornerCurve = kCACornerCurveContinuous;
    p.box.clipsToBounds = YES;
}

#pragma mark - Thanh nut cua o (ve de len app)

// Cung hinh voi thanh nut cua Split Screen ben CarPlay (SCPCGlyph / SCPCRoundButton / SCPCPill trong SCPCarSplit.mm):
// pill toi 42pt, nut tron 34pt, glyph kieu HyperOS luoi 24, net 1.8; nut dong mau do
#define AB_BAR_H     42.0
#define AB_BAR_BTN   34.0
#define AB_BAR_Y     (6 + 12 + 6 + AB_BAR_H / 2)   // duoi thanh "•••" nhu thanh nut cua CarPlay

#define AB_M(x, y) [p moveToPoint:CGPointMake(x, y)]
#define AB_L(x, y) [p addLineToPoint:CGPointMake(x, y)]
#define AB_RR(x, y, w, h, r) [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, w, h) cornerRadius:r]]

static UIImage *ABGlyph(NSString *name)
{
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache[name]) return cache[name];
    CGFloat pt = 20;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(pt, pt)];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextScaleCTM(rc.CGContext, pt / 24.0, pt / 24.0);
        [[UIColor blackColor] set];
        UIBezierPath *p = [UIBezierPath bezierPath], *f = [UIBezierPath bezierPath];
        p.lineWidth = 1.8; p.lineCapStyle = kCGLineCapRound; p.lineJoinStyle = kCGLineJoinRound;
        if ([name isEqualToString:@"fullscreen"]) {      // 2 mui ten cheo ra 2 goc
            AB_M(13.5, 4); AB_L(20, 4); AB_L(20, 10.5);
            AB_M(20, 4); AB_L(14, 10);
            AB_M(10.5, 20); AB_L(4, 20); AB_L(4, 13.5);
            AB_M(4, 20); AB_L(10, 14);
        } else if ([name isEqualToString:@"replace"]) {  // 3 o app + dau cong o goc
            AB_RR(3.5, 3.5, 7.5, 7.5, 2.4); AB_RR(13, 3.5, 7.5, 7.5, 2.4);
            AB_RR(3.5, 13, 7.5, 7.5, 2.4);
            AB_M(16.75, 13.5); AB_L(16.75, 20); AB_M(13.5, 16.75); AB_L(20, 16.75);
        } else if ([name isEqualToString:@"close"]) {
            AB_M(7, 7); AB_L(17, 17); AB_M(17, 7); AB_L(7, 17);
        } else if ([name isEqualToString:@"float"]) {    // cua so noi: khung + o nho to dac goc duoi phai
            AB_RR(3.5, 4.5, 17, 15, 3);
            [f appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(11.5, 11, 6.5, 6) cornerRadius:1.6]];
        } else if ([name isEqualToString:@"dock"]) {     // dua ve o: khung chia doi, nua trai to dac
            AB_RR(3.5, 4.5, 17, 15, 3);
            AB_M(12, 4.5); AB_L(12, 19.5);
            [f appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(5.6, 6.6, 4.6, 10.8) cornerRadius:1.4]];
        }
        [p stroke];
        [f fill];
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cache[name] = img;
    return img;
}

static UIButton *ABRoundButton(NSString *glyph, id target, SEL action)
{
    UIButton *b = [ABBarButton buttonWithType:UIButtonTypeCustom];
    b.bounds = CGRectMake(0, 0, AB_BAR_BTN, AB_BAR_BTN);
    b.layer.cornerRadius = AB_BAR_BTN / 2;
    b.tintColor = [UIColor colorWithWhite:1 alpha:0.94];
    [b setImage:ABGlyph(glyph) forState:UIControlStateNormal];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)buildBarForPane:(ABPane *)pane
{
    UIButton *replace = ABRoundButton(@"replace", self, @selector(barReplace:));
    UIButton *pop = ABRoundButton(@"float", self, @selector(barPop:));
    UIButton *full = ABRoundButton(@"fullscreen", self, @selector(barFull:));
    UIButton *close = ABRoundButton(@"close", self, @selector(barClose:));
    close.tintColor = [UIColor colorWithRed:1.0 green:0.36 blue:0.33 alpha:1];
    pane.popButton = pop;
    // SCPCPill: pad 4, buoc 36, khe 9 truoc nut dong (co vach mo)
    CGFloat pad = (AB_BAR_H - AB_BAR_BTN) / 2, step = AB_BAR_BTN + 2, sep = 9;
    CGFloat len = pad * 2 - 2 + 3 * step + sep + step;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, len, AB_BAR_H)];
    bar.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.94];
    bar.layer.cornerRadius = AB_BAR_H / 2;
    bar.layer.cornerCurve = kCACornerCurveContinuous;
    bar.layer.borderWidth = 0.5;
    bar.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    bar.layer.shadowColor = [UIColor blackColor].CGColor;
    bar.layer.shadowOpacity = 0.35; bar.layer.shadowRadius = 8; bar.layer.shadowOffset = CGSizeMake(0, 2);
    CGFloat o = pad;
    for (UIButton *b in @[replace, pop, full]) {
        b.center = CGPointMake(o + AB_BAR_BTN / 2, AB_BAR_H / 2);
        [bar addSubview:b];
        o += step;
    }
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(o - 1 + sep / 2, (AB_BAR_H - 18) / 2, 1, 18)];
    line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    line.userInteractionEnabled = NO;
    [bar addSubview:line];
    o += sep;
    close.center = CGPointMake(o + AB_BAR_BTN / 2, AB_BAR_H / 2);
    [bar addSubview:close];
    bar.hidden = YES;
    bar.alpha = 0;
    pane.bar = bar;
    pane.box.bar = bar;
    [pane.box addSubview:bar];
    return bar;
}

- (void)layoutBarForPane:(ABPane *)pane
{
    UIView *bar = pane.bar;
    if (!bar) return;
    CGSize s = pane.box.bounds.size;
    // O hep: thu nho ca thanh cho vua o
    CGFloat avail = s.width - 10, bw = bar.bounds.size.width;
    CGFloat k = (bw > avail && avail > 40) ? avail / bw : 1;
    bar.transform = CGAffineTransformMakeScale(k, k);
    bar.center = CGPointMake(s.width / 2, AB_BAR_Y);
    [pane.box bringSubviewToFront:bar];
    [pane.box bringSubviewToFront:pane.handleHit];
}

- (void)setBarVisible:(BOOL)visible pop:(int)pop dim:(BOOL)dim forApp:(NSString *)bid
{
    ABPane *p = [self paneFor:bid];
    if (!p) return;
    if (!p.bar && !visible) return;
    UIView *bar = p.bar ?: [self buildBarForPane:p];
    [p.popButton setImage:ABGlyph(pop == 2 ? @"dock" : @"float") forState:UIControlStateNormal];
    p.popButton.alpha = dim ? 0.35 : 1;
    [self layoutBarForPane:p];
    if (visible == !bar.hidden) return;
    if (visible) {
        bar.hidden = NO;
        bar.transform = CGAffineTransformConcat(bar.transform, CGAffineTransformMakeTranslation(0, -8));
        CGAffineTransform t = bar.transform;
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            bar.alpha = 1;
            bar.transform = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(0, 8));
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.16 animations:^{ bar.alpha = 0; } completion:^(BOOL f) { if (bar.alpha == 0) bar.hidden = YES; }];
    }
}

- (ABPane *)paneOfBarButton:(UIView *)v
{
    for (ABPane *p in self.panes) if (p.bar && [v isDescendantOfView:p.bar]) return p;
    return nil;
}

- (void)postBarAction:(NSString *)action from:(UIView *)v
{
    ABPane *p = [self paneOfBarButton:v];
    if (!p) return;
    ABLog("thanh nut %@: %@", p.bundleID, action);
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        postNotificationName:AB_NOTIF_BAR_ACTION object:nil userInfo:@{@"identifier": p.bundleID, @"action": action}];
}

- (void)barReplace:(UIButton *)b { [self postBarAction:@"replace" from:b]; }
- (void)barPop:(UIButton *)b     { [self postBarAction:@"pop" from:b]; }
- (void)barFull:(UIButton *)b    { [self postBarAction:@"full" from:b]; }
- (void)barClose:(UIButton *)b   { [self postBarAction:@"close" from:b]; }

#pragma mark - Thanh "•••" tren app

- (void)setupHandleForPane:(ABPane *)pane
{
    UIView *hit = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 24)];
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(5, 6, 34, 12)];
    pill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.38];
    pill.layer.cornerRadius = 6;
    pill.userInteractionEnabled = NO;
    for (int i = 0; i < 3; i++) {
        UIView *d = [[UIView alloc] initWithFrame:CGRectMake(9 + i * 7, 4, 4, 4)];
        d.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
        d.layer.cornerRadius = 2;
        [pill addSubview:d];
    }
    [hit addSubview:pill];
    [hit addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapped:)]];
    hit.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    pane.handle = pill;
    pane.handleHit = hit;
    pane.box.handleHit = hit;
    [pane.box addSubview:hit];
    [self setHandleVisible:YES forPane:pane];
}

- (void)setHandleVisible:(BOOL)visible forPane:(ABPane *)pane
{
    pane.handleHit.hidden = !visible;
    pane.handleHit.center = CGPointMake(pane.box.bounds.size.width / 2 + pane.handleOffset, 12);
    [pane.box bringSubviewToFront:pane.handleHit];
}

- (void)setHandleOffset:(CGFloat)dx forApp:(NSString *)bid
{
    ABPane *p = [self paneFor:bid];
    if (!p || p.handleOffset == dx) return;
    p.handleOffset = dx;
    [self setHandleVisible:!p.handleHit.hidden forPane:p];
}

- (void)handleTapped:(UITapGestureRecognizer *)g
{
    for (ABPane *p in self.panes) {
        if (p.handleHit != g.view) continue;
        ABLog("cham thanh ••• cua %@", p.bundleID);
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
            postNotificationName:AB_NOTIF_HANDLE_TAP object:nil userInfo:@{@"identifier": p.bundleID}];
        return;
    }
}

#pragma mark - Dong

- (void)teardownPane:(ABPane *)pane
{
    [pane.sceneMonitor invalidate];
    pane.sceneMonitor = nil;
    NSString *appID = pane.bundleID;
    ABPostOrientation(appID, -1);   // thoi ep huong, app ve lai binh thuong tren iPhone
    id appVC = pane.appViewController;
    @try {
        objcCall_1(appVC, @"_setCurrentMode:", (long long)0);
        // SBAppViewController la BSInvalidatable: dealloc ma chua invalidate -> assertion crash SpringBoard
        [[appVC view] removeFromSuperview];
        if ([appVC respondsToSelector:@selector(invalidate)]) objcCall(appVC, @"invalidate");
        id appScene = objcInvoke(objcInvoke(appVC, @"sceneHandle"), @"sceneIfExists");
        if (appScene) {
            id frontmost = objcInvoke([UIApplication sharedApplication], @"_accessibilityFrontMostApplication");
            BOOL onMainScreen = frontmost && [objcInvoke(frontmost, @"bundleIdentifier") isEqualToString:appID];
            if (!onMainScreen) {   // tren man iPhone khong mo app nay -> cho scene ve nen
                objcCall_1(appScene, @"updateSettingsWithBlock:", ^(id settings) {
                    objcCall_1(settings, @"setBackgrounded:", (BOOL)1);
                    objcCall_1(settings, @"setForeground:", (BOOL)0);
                });
            }
        }
    } @catch (NSException *e) { ABLog("teardown %@ loi %@", appID, e); }
    pane.appViewController = nil;
    UIView *box = pane.box;
    box.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.15 animations:^{ box.alpha = 0; } completion:^(BOOL f) { [box removeFromSuperview]; }];
}

static void ABTerminate(NSString *bid)
{
    id svc = objcInvoke(objc_getClass("FBSSystemService"), @"sharedService");
    SEL sel = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
    if (svc && [svc respondsToSelector:sel]) {
        ((void (*)(id, SEL, id, long long, BOOL, id))objc_msgSend)(svc, sel, bid, 1, NO, @"OmniCar App Bridge: closed");
        ABLog("tat han %@", bid);
    } else ABLog("khong tim thay API terminate cho %@", bid);
}

- (void)closeApp:(NSString *)bid terminate:(BOOL)terminate
{
    ABPane *p = [self paneFor:bid];
    if (!p) return;
    ABLog("dong %@%@", bid, terminate ? @" (tat han)" : @"");
    [self teardownPane:p];
    [self.panes removeObject:p];
    [self dropWindowIfEmpty];
    if (terminate) {
        id frontmost = objcInvoke([UIApplication sharedApplication], @"_accessibilityFrontMostApplication");
        if (frontmost && [objcInvoke(frontmost, @"bundleIdentifier") isEqualToString:bid]) ABLog("%@ dang mo tren iPhone, khong tat", bid);
        else ABTerminate(bid);
    }
}

- (void)closeAll
{
    [self closeAllExcept:nil];
}

- (void)closeAllExcept:(NSString *)keep
{
    if (!self.panes.count) return;
    ABLog("dong tat ca (%lu app%@)", (unsigned long)self.panes.count, keep ? [@", giu " stringByAppendingString:keep] : @"");
    for (ABPane *p in [self.panes copy]) {
        if (keep && [p.bundleID isEqualToString:keep]) continue;
        [self teardownPane:p];
        [self.panes removeObject:p];
    }
    [self dropWindowIfEmpty];
}

- (void)carDisconnected
{
    if (!self.panes.count && !self.window) return;
    ABLog("xe ngat -> bo %lu o", (unsigned long)self.panes.count);
    for (ABPane *p in [self.panes copy]) [self teardownPane:p];
    [self.panes removeAllObjects];
    self.window.hidden = YES;
    self.window = nil;
}

@end
