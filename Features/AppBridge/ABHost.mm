#import "ABHost.h"
#import "ABKeyboard.h"
#import "common.h"
#import <objc/runtime.h>

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

// Ten selector doi theo iOS: iOS 16 sceneIdentityForApplication:createPrimaryIfRequired:sceneSessionRole:, iOS 14 (carplay-cast)
// _sceneIdentityForApplication:createPrimaryIfRequired:, iOS 15.8.4 khong co ca hai (log 17/10 22:47 "THIEU METHOD ... ->
// expected FBSSceneIdentity got (null)"). Thu danh sach ten da biet, khong co thi quet method cua lop (va lop cha) lay
// selector chua `stem`; goi bang NSInvocation, moi tham so dien theo ten: "...Application:" = app, "...createPrimary..." = YES,
// "...Role:" = vai tro, "...BundleIdentifier:" = bundle id, "...displayIdentity:" = display. Ghi ten tim duoc 1 lan / lop.
static NSString *ABFindSelector(id obj, NSArray<NSString *> *known, NSString *stem)
{
    if (!obj) return nil;
    for (NSString *s in known) if ([obj respondsToSelector:NSSelectorFromString(s)]) return s;
    NSString *found = nil;
    NSMutableArray *near = [NSMutableArray array];
    for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
        unsigned n = 0;
        Method *ms = class_copyMethodList(c, &n);
        for (unsigned i = 0; i < n; i++) {
            NSString *name = NSStringFromSelector(method_getName(ms[i]));
            if ([name rangeOfString:stem options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
            [near addObject:name];
            if (!found || name.length < found.length) found = name;   // ngan nhat = it tham so phai doan nhat
        }
        free(ms);
    }
    static NSMutableSet *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *key = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([obj class]), stem];
    if (![logged containsObject:key]) {
        [logged addObject:key];
        ABLog("iOS %@: %@ khong co %@ -> dung %@ (co: %@)", [UIDevice currentDevice].systemVersion, NSStringFromClass([obj class]),
              [known componentsJoinedByString:@" / "], found ?: @"(khong tim thay)", near.count ? [near componentsJoinedByString:@", "] : @"-");
    }
    return found;
}

static id ABCallNamed(id obj, NSString *selName, id app, NSString *bundleID, id displayIdentity)
{
    if (!obj || !selName) return nil;
    SEL sel = NSSelectorFromString(selName);
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = obj; inv.selector = sel;
    NSArray *parts = [selName componentsSeparatedByString:@":"];
    NSString *role = UIWindowSceneSessionRoleApplication;
    for (NSUInteger i = 0; i + 1 < parts.count && i + 2 < sig.numberOfArguments; i++) {
        NSString *p = ((NSString *)parts[i]).lowercaseString;
        const char *t = [sig getArgumentTypeAtIndex:i + 2];
        if (t[0] == 'B' || t[0] == 'c') { BOOL yes = [p containsString:@"createprimary"]; [inv setArgument:&yes atIndex:i + 2]; continue; }
        id v = nil;
        if ([p containsString:@"bundleidentifier"]) v = bundleID;
        else if ([p containsString:@"application"]) v = app;
        else if ([p containsString:@"role"]) v = role;
        else if ([p containsString:@"display"]) v = displayIdentity;
        [inv setArgument:&v atIndex:i + 2];
    }
    [inv retainArguments];
    [inv invoke];
    if (!sig.methodReturnLength) return nil;
    __unsafe_unretained id ret = nil;
    [inv getReturnValue:&ret];
    return ret;
}

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
// Gioi han khung hinh / giay cho app tren xe (AB_KEY_FPS): nguoi dung chon 30 / 24; khong gioi han thi tu ha 30 khi
// Che do nhe dang bat hoac CarPlay khong day. 0 = khong gioi han.
static int ABFpsCap(void)
{
    int fps = [OMCPref(AB_KEY_FPS, @0) intValue];
    if (fps > 0) return fps;
    return (OMCLiteActive() || OMCCarWireless() == 1) ? 30 : 0;
}

static void ABPostOrientation(NSString *bid, long long orientation)
{
    if (!bid) return;
    long long device = orientation > 0 ? orientation : 0;
    int fps = orientation > 0 ? ABFpsCap() : 0;   // thoi host: bo gioi han
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        postNotificationName:AB_NOTIF_ORIENTATION object:bid userInfo:@{@"orientation": @(orientation), @"device": @(device), @"fps": @(fps)}];
}

// Khung o: cham trong dai passInsets sat mep (canh giap o khac) khong tinh la cham vao o -> cua so (pass-through)
// tra nil. Thanh "•••" van cham duoc. Cham tron cua vach (ABKnobView, nam tren moi o) tu nhan cham va chuyen sang CarPlay.
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
@property (nonatomic, strong) UIButton *soloButton;    // nut "Chay 1 man hinh" / "Chia man hinh" (glyph doi theo "single")
@property (nonatomic) CGFloat handleOffset;            // thanh "•••" lech ngang (hx tu CarPlay)
@end
@implementation ABPane
@end

#pragma mark - Cham tron cua vach chia (ve lai len tren cac o)

// Cung kieu voi cham tron ben CarPlay (SCPCKnobStyle / SCPCKnobActive trong SCPCarSplit.mm)
#define AB_KNOB      14.0
#define AB_KNOB_GROW 1.6
#define AB_KNOB_HIT  26.0   // = SCPC_DIVIDER_HIT: vung cham quanh cham tron

// Cham tron nam trong cua so cua SpringBoard nen cham vao no den SpringBoard, khong bao gio den CarPlay (log 10/10 22:18:
// cham cham tron canh o YouTube khong co gi). Nen cham tron tu nhan cham va chuyen tung pha sang CarPlay
// (AB_NOTIF_KNOB_TOUCH); CarPlay keo / bam vach nhu cham vao cham tron cua chinh no.
// backboardd dua cham thang vao tien trinh so huu lop VE THAT tai diem cham (app iPhone duoc host co lop rieng), nen vung
// cham rong quanh cham tron phai la mot lop co ve (dem AB_KNOB_HIT moi ben, trang alpha 0.02 - mat khong thay) chu khong
// phai pointInside mo rong: cham vao vung trong suot roi vao app, SpringBoard khong bao gio nhan duoc.
@interface ABKnobView : UIView
@property (nonatomic) int index;          // vach thu may (CarPlay gui kem trong AB_NOTIF_KNOBS)
@property (nonatomic) CGPoint lastSent;
@property (nonatomic, strong) UIView *dot; // hinh cham tron that (AB_KNOB) giua dem
@end
@implementation ABKnobView
- (void)relay:(int)phase touches:(NSSet<UITouch *> *)touches
{
    CGPoint p = [touches.anyObject locationInView:self.window];
    if (phase == 1 && hypot(p.x - self.lastSent.x, p.y - self.lastSent.y) < 1) return;
    self.lastSent = p;
    if (phase != 1) ABLog("cham tron vach %d: pha %d tai %@", self.index, phase, NSStringFromCGPoint(p));
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        postNotificationName:AB_NOTIF_KNOB_TOUCH object:nil
                    userInfo:@{@"index": @(self.index), @"phase": @(phase), @"x": @(p.x), @"y": @(p.y)}];
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self relay:0 touches:t]; }
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self relay:1 touches:t]; }
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self relay:2 touches:t]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self relay:3 touches:t]; }
@end


@interface ABHost ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, copy) NSString *displayID;
@property (nonatomic, strong) NSMutableArray<ABPane *> *panes;
@property (nonatomic, strong) NSMutableArray<UIView *> *knobViews;   // cham tron cua vach chia ve len tren cac o
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
    [self raiseKnobs];   // o moi them vao nam tren cac cham tron da ve -> dua cham tron len lai
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
    // iOS 16: layoutStateManager / sceneIdentityForApplication:...sceneSessionRole:; iOS 14 (carplay-cast): _layoutStateManager /
    // _sceneIdentityForApplication:createPrimaryIfRequired:; iOS 15.8.4 khong co ca hai (log 17/10 22:47) -> ABFindSelector quet
    // lop tim ten that (ghi vao log) va ABCallNamed goi theo ten tham so
    NSString *lsmSel = ABFindSelector(sceneManager, @[@"layoutStateManager", @"_layoutStateManager"], @"layoutStateManager");
    id layoutStateManager = lsmSel ? objcInvoke(sceneManager, lsmSel) : nil;
    id displayIdentity    = objcInvoke(sceneManager, @"displayIdentity");
    expectClass(displayIdentity, "FBSDisplayIdentity");

    NSString *idSel = ABFindSelector(sceneManager, @[@"sceneIdentityForApplication:createPrimaryIfRequired:sceneSessionRole:",
                                                     @"sceneIdentityForApplication:createPrimaryIfRequired:",
                                                     @"_sceneIdentityForApplication:createPrimaryIfRequired:"], @"sceneIdentityForApplication");
    id sceneIdentity = ABCallNamed(sceneManager, idSel, pane.application, appID, displayIdentity);
    if (!sceneIdentity && [pane.application respondsToSelector:NSSelectorFromString(@"sceneIdentityForRole:")])   // phong khi SBApplication tu biet
        sceneIdentity = objcInvoke_1(pane.application, @"sceneIdentityForRole:", UIWindowSceneSessionRoleApplication);
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
    SEL setMode = NSSelectorFromString(@"setDisplayMode:animationFactory:completion:");
    if ([appView respondsToSelector:setMode]) ((void (*)(id, SEL, long long, id, id))objc_msgSend)(appView, setMode, 4, animFactory, nil);
    else ABMissingSelector(appView, @"setDisplayMode:animationFactory:completion:");

    UIView *v = [appVC view];
    v.backgroundColor = [UIColor clearColor];
    [pane.box insertSubview:v atIndex:0];

    NSString *pidSel = ABFindSelector(layoutStateManager, @[@"primarySceneIdentifierForBundleIdentifier:sceneSessionRole:displayIdentity:",
                                                            @"primarySceneIdentifierForBundleIdentifier:"], @"primarySceneIdentifierForBundleIdentifier");
    NSString *sceneID = ABCallNamed(layoutStateManager, pidSel, pane.application, appID, displayIdentity);
    if (![sceneID isKindOfClass:[NSString class]]) sceneID = nil;
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
- (UIWindow *)carWindow
{
    return [self ensureWindow] ? self.window : nil;
}

- (NSString *)bundleForHash:(unsigned long long)hash
{
    for (ABPane *p in self.panes) if (ABBundleHash(p.bundleID) == hash) return p.bundleID;
    return nil;
}

- (CGRect)frameOfApp:(NSString *)bid
{
    ABPane *p = [self paneFor:bid];
    return p ? p.box.frame : CGRectNull;
}

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

// Cung hinh voi thanh ••• cua Split Screen ben CarPlay (SCPCActionButton / SCPCActionBar trong SCPCarSplit.mm):
// vien thuoc 52pt nen logo 4 mau, moi nut 48pt = o kinh tron 40pt chi icon (khong nhan), glyph HarmonyOS 22pt; nut Tat
// do, tach bang vach trang
#define AB_BAR_H     52.0
#define AB_ACT_W     48.0
#define AB_ACT_SIDE  40.0
#define AB_ACT_ICON  7302
#define AB_BAR_Y     (6 + 12 + 6 + AB_BAR_H / 2)   // duoi thanh "•••" nhu thanh nut cua CarPlay

// Giao dien moi (DESIGN.md, = SCPCInk / SCPCShadow / SCPCAccentFill ben CarPlay): chu / icon mau cham diu, bong tim
// nhat, nut chinh = gradient tim -> xanh troi
static UIColor *ABInk(void) { return [UIColor colorWithRed:0x4A / 255.0 green:0x4F / 255.0 blue:0x80 / 255.0 alpha:1]; }
static UIColor *ABShadow(void) { return [UIColor colorWithRed:110 / 255.0 green:100 / 255.0 blue:200 / 255.0 alpha:1]; }

// Tay cam "•••" dang mo thanh nut: gradient + cham trang; dong: kinh trang + cham muc
static void ABHandleOpen(UIView *pill, BOOL open)
{
    if (!pill) return;
    CAGradientLayer *g = nil;
    for (CALayer *l in pill.layer.sublayers) if ([l.name isEqualToString:@"omcAccent"]) g = (CAGradientLayer *)l;
    if (open && !g) {
        g = [CAGradientLayer layer];
        g.name = @"omcAccent";
        g.colors = @[(id)[UIColor colorWithRed:0x9B / 255.0 green:0x87 / 255.0 blue:0xF8 / 255.0 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:0x5D / 255.0 green:0xB4 / 255.0 blue:0xF6 / 255.0 alpha:1].CGColor];
        g.startPoint = CGPointZero; g.endPoint = CGPointMake(1, 1);
        g.frame = pill.bounds;
        g.cornerRadius = pill.layer.cornerRadius;
        [pill.layer insertSublayer:g atIndex:0];
    } else if (!open) {
        [g removeFromSuperlayer];
    }
    pill.backgroundColor = open ? [UIColor clearColor] : [UIColor colorWithWhite:1 alpha:0.35];
    for (UIView *d in pill.subviews) d.backgroundColor = open ? [UIColor whiteColor] : [ABInk() colorWithAlphaComponent:0.85];
}

#define AB_M(x, y) [p moveToPoint:CGPointMake(x, y)]
#define AB_L(x, y) [p addLineToPoint:CGPointMake(x, y)]
#define AB_RR(x, y, w, h, r) [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, w, h) cornerRadius:r]]

static UIImage *ABGlyph(NSString *name)
{
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache[name]) return cache[name];
    CGFloat pt = [name hasPrefix:@"hm_"] ? 22 : 20;   // hm_*: glyph trong o kinh tron 40pt cua thanh •••
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
        } else if ([name hasPrefix:@"hm_"]) {             // thanh ••• kieu HarmonyOS Symbol: net 1.5 (= SCPCGlyph hm_* ben CarPlay)
            p.lineWidth = 1.5;
            if ([name isEqualToString:@"hm_apps"]) {
                AB_RR(4, 4, 7, 7, 2.2); AB_RR(13, 4, 7, 7, 2.2); AB_RR(4, 13, 7, 7, 2.2); AB_RR(13, 13, 7, 7, 2.2);
            } else if ([name isEqualToString:@"hm_full"]) {
                AB_M(4, 9.5); AB_L(4, 7.5); [p addArcWithCenter:CGPointMake(7.5, 7.5) radius:3.5 startAngle:M_PI endAngle:-M_PI_2 clockwise:YES]; AB_L(9.5, 4);
                AB_M(14.5, 4); AB_L(16.5, 4); [p addArcWithCenter:CGPointMake(16.5, 7.5) radius:3.5 startAngle:-M_PI_2 endAngle:0 clockwise:YES]; AB_L(20, 9.5);
                AB_M(20, 14.5); AB_L(20, 16.5); [p addArcWithCenter:CGPointMake(16.5, 16.5) radius:3.5 startAngle:0 endAngle:M_PI_2 clockwise:YES]; AB_L(14.5, 20);
                AB_M(9.5, 20); AB_L(7.5, 20); [p addArcWithCenter:CGPointMake(7.5, 16.5) radius:3.5 startAngle:M_PI_2 endAngle:M_PI clockwise:YES]; AB_L(4, 14.5);
            } else if ([name isEqualToString:@"hm_split"]) {
                AB_RR(3.5, 4.5, 7.5, 15, 2.5); AB_RR(13, 4.5, 7.5, 15, 2.5);
            } else if ([name isEqualToString:@"hm_float"]) {
                AB_RR(3.5, 4.5, 17, 15, 3);
                [f appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(11.5, 11.5, 6.5, 5.5) cornerRadius:1.6]];
            } else if ([name isEqualToString:@"hm_min"]) {
                AB_M(5.5, 12); AB_L(18.5, 12);
            } else if ([name isEqualToString:@"hm_close"]) {
                AB_M(6.5, 6.5); AB_L(17.5, 17.5); AB_M(17.5, 6.5); AB_L(6.5, 17.5);
            }
        }
        [p stroke];
        [f fill];
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cache[name] = img;
    return img;
}

static void ABActionSet(UIButton *b, NSString *glyph, NSString *title)
{
    ((UIImageView *)[b viewWithTag:AB_ACT_ICON]).image = ABGlyph(glyph);
    b.accessibilityLabel = title;
}

// Nut thanh •••: o kinh tron 40pt (trang trong + vien trang nhu dia trong logo), chi icon - khong nhan
static UIButton *ABActionButton(NSString *glyph, NSString *title, UIColor *tint, id target, SEL action)
{
    UIButton *b = [ABBarButton buttonWithType:UIButtonTypeCustom];
    b.bounds = CGRectMake(0, 0, AB_ACT_W, AB_ACT_SIDE);
    b.tintColor = tint;
    UIView *disc = [[UIView alloc] initWithFrame:CGRectMake((AB_ACT_W - AB_ACT_SIDE) / 2, 0, AB_ACT_SIDE, AB_ACT_SIDE)];
    disc.userInteractionEnabled = NO;
    disc.backgroundColor = [UIColor colorWithWhite:1 alpha:0.5];
    disc.layer.cornerRadius = AB_ACT_SIDE / 2;
    disc.layer.borderWidth = 1;
    disc.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    disc.layer.shadowColor = ABShadow().CGColor;
    disc.layer.shadowOpacity = 0.12; disc.layer.shadowRadius = 3; disc.layer.shadowOffset = CGSizeMake(0, 2);
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectInset(disc.bounds, 6, 6)];
    iv.tag = AB_ACT_ICON;
    iv.contentMode = UIViewContentModeCenter;
    [disc addSubview:iv];
    [b addSubview:disc];
    ABActionSet(b, glyph, title);
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// Thanh ••• (= setupBarForPane ben CarPlay, DESIGN.md): nen logo 4 mau, o kinh tron chi icon - Doi app ·
// Toan man / Chia man · Cua so noi · Chay nen | Tat app (do)
- (UIView *)buildBarForPane:(ABPane *)pane
{
    UIButton *replace = ABActionButton(@"hm_apps", OMCTr(@"Đổi app", @"Change app"), ABInk(), self, @selector(barReplace:));
    UIButton *full = ABActionButton(@"hm_full", OMCTr(@"Toàn màn", @"Full screen"), ABInk(), self, @selector(barFull:));
    UIButton *pop = ABActionButton(@"hm_float", OMCTr(@"Cửa sổ nổi", @"Float"), ABInk(), self, @selector(barPop:));
    UIButton *bg = ABActionButton(@"hm_min", OMCTr(@"Chạy nền", @"Background"), ABInk(), self, @selector(barBackground:));
    UIButton *close = ABActionButton(@"hm_close", OMCTr(@"Tắt app", @"Quit app"),
                                     [UIColor colorWithRed:1.0 green:0x5A / 255.0 blue:0x5F / 255.0 alpha:1], self, @selector(barClose:));
    pane.popButton = pop;
    pane.soloButton = full;
    NSArray *items = @[replace, full, pop, bg, [NSNull null], close];
    CGFloat pad = 6, sep = 7, len = pad * 2;
    for (id it in items) len += [it isKindOfClass:[UIButton class]] ? AB_ACT_W : sep;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, len, AB_BAR_H)];
    bar.backgroundColor = [UIColor clearColor];
    bar.layer.cornerRadius = 22;
    bar.layer.cornerCurve = kCACornerCurveContinuous;
    bar.layer.shadowColor = ABShadow().CGColor;
    bar.layer.shadowOpacity = 0.3; bar.layer.shadowRadius = 14; bar.layer.shadowOffset = CGSizeMake(0, 6);
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight]];
    glass.frame = bar.bounds;
    UIImageView *mesh = [[UIImageView alloc] initWithImage:OMCLogoMeshImage(NO)];   // nen logo 4 mau
    mesh.frame = glass.contentView.bounds;
    mesh.contentMode = UIViewContentModeScaleToFill;
    mesh.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [glass.contentView addSubview:mesh];
    glass.layer.cornerRadius = 22;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.borderWidth = 1;
    glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
    glass.clipsToBounds = YES;
    glass.userInteractionEnabled = NO;
    [bar addSubview:glass];
    CGFloat o = pad;
    for (id it in items) {
        if (![it isKindOfClass:[UIButton class]]) {   // vach trang tach nut Tat
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(o + (sep - 1) / 2, (AB_BAR_H - 30) / 2, 1, 30)];
            line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.95];
            line.userInteractionEnabled = NO;
            [bar addSubview:line];
            o += sep;
            continue;
        }
        UIButton *b = it;
        b.center = CGPointMake(o + AB_ACT_W / 2, AB_BAR_H / 2);
        [bar addSubview:b];
        o += AB_ACT_W;
    }
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
    bar.center = CGPointMake(s.width / 2, AB_BAR_Y - AB_BAR_H * (1 - k) / 2);   // thu nho: mep tren van ngay duoi tay cam
    [pane.box bringSubviewToFront:bar];
    [pane.box bringSubviewToFront:pane.handleHit];
}

- (void)setBarVisible:(BOOL)visible pop:(int)pop dim:(BOOL)dim single:(BOOL)single forApp:(NSString *)bid
{
    ABPane *p = [self paneFor:bid];
    if (!p) return;
    if (!p.bar && !visible) return;
    UIView *bar = p.bar ?: [self buildBarForPane:p];
    ABActionSet(p.popButton, pop == 2 ? @"hm_split" : @"hm_float", pop == 2 ? OMCTr(@"Chia màn", @"Split") : OMCTr(@"Cửa sổ nổi", @"Float"));
    p.popButton.alpha = dim ? 0.35 : 1;
    ABActionSet(p.soloButton, single ? @"hm_split" : @"hm_full", single ? OMCTr(@"Chia màn", @"Split") : OMCTr(@"Toàn màn", @"Full screen"));
    [self layoutBarForPane:p];
    ABHandleOpen(p.handle, visible);   // tay cam "•••": gradient khi thanh dang mo
    if (visible == !bar.hidden) return;
    if (visible) {
        // Kieu HarmonyOS nhu SCPCDropIn: troi xuong nhe + phong tu 0.9, lo xo em
        bar.hidden = NO;
        CGAffineTransform t = bar.transform;
        bar.transform = CGAffineTransformConcat(CGAffineTransformScale(t, 0.9, 0.9), CGAffineTransformMakeTranslation(0, -8));
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionAllowUserInteraction animations:^{
            bar.alpha = 1;
            bar.transform = t;
        } completion:nil];
    } else {
        CGAffineTransform t = bar.transform;
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            bar.alpha = 0; bar.transform = CGAffineTransformScale(t, 0.94, 0.94);
        } completion:^(BOOL f) { if (bar.alpha == 0) { bar.hidden = YES; bar.transform = t; } }];
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
- (void)barBackground:(UIButton *)b { [self postBarAction:@"bg" from:b]; }
- (void)barClose:(UIButton *)b   { [self postBarAction:@"close" from:b]; }

#pragma mark - Thanh "•••" tren app

- (void)setupHandleForPane:(ABPane *)pane
{
    UIView *hit = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 24)];
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(5, 6, 34, 12)];
    pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];   // vien bau duc trong, 3 cham mau muc (= SCPCDotsHandle)
    pill.layer.cornerRadius = 6;
    pill.layer.borderWidth = 0.5;
    pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
    pill.userInteractionEnabled = NO;
    for (int i = 0; i < 3; i++) {
        UIView *d = [[UIView alloc] initWithFrame:CGRectMake(9 + i * 7, 4, 4, 4)];
        d.backgroundColor = [ABInk() colorWithAlphaComponent:0.85];
        d.layer.cornerRadius = 2;
        [pill addSubview:d];
    }
    [hit addSubview:pill];
    [hit addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapped:)]];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanned:)];   // keo doi cho / keo cua so noi
    pan.maximumNumberOfTouches = 1;
    [hit addGestureRecognizer:pan];
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

#pragma mark - Cham tron cua vach chia (ve lai len tren cac o)

// Cung kieu voi cham tron ben CarPlay (SCPCKnobStyle / SCPCKnobActive trong SCPCarSplit.mm)
static ABKnobView *ABMakeKnob(void)
{
    CGFloat pad = AB_KNOB + 2 * AB_KNOB_HIT;
    ABKnobView *v = [[ABKnobView alloc] initWithFrame:CGRectMake(0, 0, pad, pad)];
    v.multipleTouchEnabled = NO;
    // Co ve -> backboardd giao cham cho SpringBoard. Tron (khong thanh hinh vuong mo quanh cham) va gan nhu trong
    // suot: 0.012 ~ 3/255, van khac 0 sau khi luong tu hoa 8 bit nen lop van duoc tinh la co ve
    v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.012];
    v.layer.cornerRadius = pad / 2;
    UIView *k = [[UIView alloc] initWithFrame:CGRectMake(AB_KNOB_HIT, AB_KNOB_HIT, AB_KNOB, AB_KNOB)];
    k.userInteractionEnabled = NO;
    k.backgroundColor = [UIColor clearColor];   // kinh mo, cham mau muc (= SCPCKnobStyle / SCPCGlassFill)
    k.layer.cornerRadius = AB_KNOB / 2;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight]];
    glass.frame = k.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
    glass.layer.cornerRadius = AB_KNOB / 2;
    glass.clipsToBounds = YES;
    glass.userInteractionEnabled = NO;
    [k addSubview:glass];
    k.layer.borderWidth = 1.5;
    k.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.95].CGColor;
    k.layer.shadowColor = ABShadow().CGColor;
    k.layer.shadowOpacity = 0.45; k.layer.shadowRadius = 3; k.layer.shadowOffset = CGSizeMake(0, 1);
    CALayer *dot = [CALayer layer];
    dot.name = @"omcDot";
    CGFloat ds = 4;
    dot.frame = CGRectMake((AB_KNOB - ds) / 2, (AB_KNOB - ds) / 2, ds, ds);
    dot.cornerRadius = ds / 2;
    dot.backgroundColor = ABInk().CGColor;
    [k.layer addSublayer:dot];
    [v addSubview:k];
    v.dot = k;
    return v;
}

// Dang cham / keo / thanh ti le dang mo: nhu tay cam ••• dang mo (= SCPCKnobActive ben CarPlay) - gradient tim -> xanh troi
// tren lop kinh mo, duoi cham giua; cham trang; quang tim; phong to AB_KNOB_GROW
static void ABKnobActive(UIView *k, BOOL on)
{
    CALayer *dot = nil; CAGradientLayer *g = nil;
    for (CALayer *l in k.layer.sublayers) {
        if ([l.name isEqualToString:@"omcDot"]) dot = l;
        else if ([l.name isEqualToString:@"omcAccent"]) g = (CAGradientLayer *)l;
    }
    if (on && !g) {
        g = [CAGradientLayer layer];
        g.name = @"omcAccent";
        g.colors = @[(id)[UIColor colorWithRed:0x9B / 255.0 green:0x87 / 255.0 blue:0xF8 / 255.0 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:0x5D / 255.0 green:0xB4 / 255.0 blue:0xF6 / 255.0 alpha:1].CGColor];
        g.startPoint = CGPointZero; g.endPoint = CGPointMake(1, 1);
        g.frame = k.bounds;
        g.cornerRadius = k.bounds.size.width / 2;
        g.opacity = 0;
        if (dot) [k.layer insertSublayer:g below:dot]; else [k.layer addSublayer:g];
    }
    [UIView animateWithDuration:on ? 0.15 : 0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        k.transform = on ? CGAffineTransformMakeScale(AB_KNOB_GROW, AB_KNOB_GROW) : CGAffineTransformIdentity;
        g.opacity = on ? 1 : 0;
        dot.backgroundColor = (on ? [UIColor whiteColor] : ABInk()).CGColor;
        k.layer.borderColor = [UIColor colorWithWhite:1 alpha:on ? 1 : 0.95].CGColor;
        k.layer.shadowColor = (on ? [UIColor colorWithRed:110 / 255.0 green:120 / 255.0 blue:1.0 alpha:1] : ABShadow()).CGColor;
        k.layer.shadowOpacity = on ? 0.5 : 0.45;
        k.layer.shadowRadius = on ? 7 : 3;
    } completion:^(BOOL f) { if (!on && g.opacity == 0) [g removeFromSuperlayer]; }];
}

// Cham tron luon nam tren moi o (o them sau bang addSubview se de len)
- (void)raiseKnobs
{
    for (UIView *v in self.knobViews) if (v.superview == self.window) [self.window bringSubviewToFront:v];
}

- (void)setKnobs:(NSArray *)knobs
{
    if (!self.knobViews) self.knobViews = [NSMutableArray array];
    if (![knobs isKindOfClass:[NSArray class]]) knobs = @[];
    if (knobs.count && ![self ensureWindow]) return;
    while (self.knobViews.count > knobs.count) { [self.knobViews.lastObject removeFromSuperview]; [self.knobViews removeLastObject]; }
    for (NSUInteger i = 0; i < knobs.count; i++) {
        NSArray *k = knobs[i];
        if (![k isKindOfClass:[NSArray class]] || k.count < 3) continue;
        ABKnobView *v = (i < self.knobViews.count) ? (ABKnobView *)self.knobViews[i] : nil;
        if (!v) { v = ABMakeKnob(); [self.knobViews addObject:v]; }
        if (v.superview != self.window) [self.window addSubview:v];
        [self.window bringSubviewToFront:v];
        v.index = k.count > 3 ? [k[3] intValue] : (int)i;
        BOOL on = [k[2] boolValue];
        v.center = CGPointMake([k[0] doubleValue], [k[1] doubleValue]);
        ABKnobActive(v.dot, on);
    }
}

- (void)setHandleOffset:(CGFloat)dx forApp:(NSString *)bid
{
    ABPane *p = [self paneFor:bid];
    if (!p || p.handleOffset == dx) return;
    p.handleOffset = dx;
    [self setHandleVisible:!p.handleHit.hidden forPane:p];
}

// Keo "•••": CarPlay khong nhan duoc cham tren cua so nay -> gui tung pha cho CarPlay (AB_NOTIF_HANDLE_DRAG), ben do
// keo doi cho / keo cua so noi nhu voi o CarPlay
- (void)handlePanned:(UIPanGestureRecognizer *)g
{
    for (ABPane *p in self.panes) {
        if (p.handleHit != g.view) continue;
        int phase = g.state == UIGestureRecognizerStateBegan ? 0 : g.state == UIGestureRecognizerStateChanged ? 1
                  : g.state == UIGestureRecognizerStateEnded ? 2 : 3;
        CGPoint pt = [g locationInView:self.window];
        if (phase != 1) ABLog("keo thanh ••• cua %@: pha %d tai %@", p.bundleID, phase, NSStringFromCGPoint(pt));
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
            postNotificationName:AB_NOTIF_HANDLE_DRAG object:nil
                        userInfo:@{@"identifier": p.bundleID, @"phase": @(phase), @"x": @(pt.x), @"y": @(pt.y)}];
        return;
    }
}

// Cua so noi: o nay nam tren cac o app iPhone khac (cham tron van tren cung)
- (void)setFront:(BOOL)front forApp:(NSString *)bid
{
    ABPane *p = [self paneFor:bid];
    if (!p || !front || p.box.superview != self.window) return;
    [self.window bringSubviewToFront:p.box];
    [self raiseKnobs];
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
    [[ABKeyboard shared] hideForApp:bid];
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
    [self.knobViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self.knobViews removeAllObjects];
    if (!self.panes.count && !self.window) return;
    ABLog("xe ngat -> bo %lu o", (unsigned long)self.panes.count);
    for (ABPane *p in [self.panes copy]) [self teardownPane:p];
    [self.panes removeAllObjects];
    self.window.hidden = YES;
    self.window = nil;
}

@end
