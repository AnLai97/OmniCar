#import "common.h"
#import "SCPHomeScreen.h"
#import "SCPPrefs.h"
#import "SCPCarSplit.h"
#import "SCPAppIcons.h"
#import "SCPAutoTest.h"
#import <unistd.h>

// Inject vao process CarPlay (com.apple.CarPlayApp, code trong DashBoard.framework, prefix DB).
// Split hien GIAO DIEN CARPLAY cua app: DashBoard tu mo scene CarPlay cua app (giong cham icon),
// tweak dua view controller cua scene do vao 1 ngan va bao kich thuoc ngan cho scene (xem SCPCarSplit.mm).
// App iPhone khong co CarPlay: SpringBoard host qua App Bridge, CarPlay chi giu o va gui khung.
//
// Quy tac on dinh: phan code cua tweak trong moi hook nam trong @try. Loi cua tweak chi ghi log
// (va tat split neu can), %orig cua DashBoard luon duoc goi nhu binh thuong -> CarPlay khong bi sap.

static void SCPHookError(const char *where, NSException *e)
{
    SCPLog("LOI trong %s: %@\n%@", where, e, e.callStackSymbols);
}

%group CARPLAY

// ---- Kich thuoc scene: app trong ngan nhan kich thuoc ngan, khong phai ca man xe ----
%hook DBDashboard

- (CGRect)sceneFrameForAppInfo:(id)info proxyAppInfo:(id)proxy
{
    CGRect r = %orig;
    @try {
        CGSize s;
        if ([[SCPCarSplit shared] paneSize:&s forBundle:SCPRealBundleForInfos(info, proxy)]) r.size = s;
    } @catch (NSException *e) { SCPHookError("sceneFrameForAppInfo", e); }
    return r;
}

- (UIEdgeInsets)safeAreaInsetsForAppInfo:(id)info proxyAppInfo:(id)proxy
{
    UIEdgeInsets e = %orig;
    @try {
        CGSize s;
        // Ngan khong nam duoi dock/status bar -> khong can chua le
        if ([[SCPCarSplit shared] paneSize:&s forBundle:SCPRealBundleForInfos(info, proxy)]) return UIEdgeInsetsZero;
    } @catch (NSException *ex) { SCPHookError("safeAreaInsetsForAppInfo", ex); }
    return e;
}

// Nut Home cua CarPlay: dang split -> tat split (scene ve background) roi de DashBoard ve man chinh;
// app iPhone toan man (App Bridge) -> dong
- (void)_handleHomeEvent:(id)event
{
    @try {
        SCPCarSplit *sp = [SCPCarSplit shared];
        BOOL split = sp.active;
        if (split) [sp closeGoingHome:NO];
        [sp homePressedDuringSplit:split];
    } @catch (NSException *e) { SCPHookError("_handleHomeEvent", e); }
    %orig;
}

- (void)invalidate
{
    @try {
        [[SCPCarSplit shared] dashboardInvalidated];
    } @catch (NSException *e) { SCPHookError("DBDashboard invalidate", e); }
    %orig;
}

// Cham icon tren man chinh / dock: app iPhone (icon do App Bridge chen) -> host qua App Bridge, khong mo scene CarPlay
- (void)_launchAppWithInfo:(id)info forURL:(id)url
{
    BOOL handled = NO;
    @try {
        NSString *bid = objcInvoke(info, @"bundleIdentifier");
        handled = [[SCPCarSplit shared] launchPhoneAppIfNeeded:bid];
    } @catch (NSException *e) { SCPHookError("_launchAppWithInfo", e); }
    if (!handled) %orig;
}

%end

// ---- DashBoard trinh bay app: dang split thi dua app vao ngan thay vi hien toan man ----
%hook DBDashboardRootViewController

- (void)presentBaseViewController:(id)vc animated:(BOOL)animated launchSource:(unsigned long long)source completion:(id)completion
{
    SCPCarSplit *sp = [SCPCarSplit shared];
    BOOL adopted = NO;
    @try {
        if (sp.active) {
            if ([sp wantsViewController:vc]) {
                [sp adoptViewController:vc];
                adopted = YES;
            } else {
                SCPLog("CarSplit: DashBoard mo %@ toan man -> tat split", vc);
                [sp closeGoingHome:NO];
            }
        }
    } @catch (NSException *e) {
        // Dua vao ngan that bai: tat split, de DashBoard mo app toan man nhu binh thuong
        SCPHookError("presentBaseViewController (adopt)", e);
        adopted = NO;
        @try { [sp closeGoingHome:NO]; } @catch (NSException *e2) { SCPHookError("closeGoingHome", e2); }
    }
    if (adopted) {
        if (completion) ((void (^)(void))completion)();
        return;
    }
    %orig;
    @try {
        SCPLog("CarSplit: DashBoard trinh bay %@ toan man (nguon %llu)", vc, source);
        if ([vc isKindOfClass:[UIViewController class]]) [sp noteBaseViewController:vc];   // iOS 15: nho VC dang toan man
        [sp baseViewControllerPresented];   // bo the icon che luc thoat chia / toan man hinh, dong app iPhone toan man
        [sp refreshAppTabSoon];   // app vua mo toan man -> tab icon o mep tren
        // App tung nam trong ngan: DashBoard co the trinh bay lai view dang bi an -> man den, cham khong vao.
        // Doi animation mo xong, van la app dang hien ma view con an thi hien lai.
        if ([vc isKindOfClass:[UIViewController class]]) {
            __weak UIViewController *weakVC = vc;
            __weak id weakRoot = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try {
                    UIViewController *v = weakVC;
                    id root = weakRoot;
                    if (v && root && objcInvoke(root, @"currentBaseViewController") == v) [[SCPCarSplit shared] repairPresentedViewController:v];
                } @catch (NSException *e) { SCPHookError("repairPresentedViewController", e); }
            });
        }
    } @catch (NSException *e) { SCPHookError("presentBaseViewController (sau)", e); }
}

- (void)dismissBaseViewControllerAnimated:(BOOL)animated completion:(id)completion
{
    SCPCarSplit *sp = [SCPCarSplit shared];
    @try {
        // Dang split thi currentBaseViewController = nil; workspace ve man chinh -> tat split
        if (sp.active && !objcInvoke(self, @"currentBaseViewController")) {
            SCPLog("CarSplit: DashBoard ve man chinh -> tat split");
            [sp closeGoingHome:NO];
        }
        [sp removeAppTab];
        [sp noteBaseViewController:nil];   // iOS 15: ve man chinh
    } @catch (NSException *e) { SCPHookError("dismissBaseViewController", e); }
    %orig;
    @try { [sp refreshAppTabSoon]; } @catch (NSException *e) { SCPHookError("refreshAppTabSoon", e); }
}

- (void)viewDidLayoutSubviews
{
    %orig;
    @try { [[SCPCarSplit shared] rootDidLayout]; } @catch (NSException *e) { SCPHookError("rootDidLayout", e); }
}

// Man xe vua hien (cam xe): danh sach app CarPlay cho Settings, tu mo split
- (void)viewDidAppear:(BOOL)animated
{
    %orig;
    @try {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                [[SCPCarSplit shared] publishCarPlayApps];
                [[SCPCarSplit shared] carScreenAppeared];
                SCPAppIconsCarScreenOK();   // man xe hien duoc sau khi chen icon -> khong phai crash-loop
            } @catch (NSException *e) { SCPHookError("viewDidAppear (sau 3s)", e); }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SCPDumpAppLibraryOnce(); });
    } @catch (NSException *e) { SCPHookError("viewDidAppear", e); }
}

%end

// ---- Giu scene cua app trong ngan luon foreground (DashBoard tuong app da bi thay) ----
%hook DBApplicationSceneViewController

- (void)backgroundSceneWithCompletion:(id)completion
{
    BOOL protect = NO;
    @try { protect = [[SCPCarSplit shared] protectsViewController:self]; } @catch (NSException *e) { SCPHookError("backgroundScene", e); }
    if (protect) {
        SCPLog("CarSplit: chan background scene cua app trong ngan");
        if (completion) ((void (^)(void))completion)();
        return;
    }
    %orig;
}

- (void)deactivateSceneWithReasonMask:(unsigned long long)mask
{
    BOOL protect = NO;
    @try { protect = [[SCPCarSplit shared] protectsViewController:self]; } @catch (NSException *e) { SCPHookError("deactivateScene", e); }
    if (protect) {
        SCPLog("CarSplit: chan deactivate scene (mask=%llu) cua app trong ngan", mask);
        return;
    }
    %orig;
}

- (void)sceneManager:(id)manager didDestroyScene:(id)scene
{
    id own = nil;
    @try { own = [[SCPCarSplit shared] sceneOfViewController:self]; } @catch (NSException *e) {}   // lay truoc %orig (co the bi xoa)
    %orig;
    @try { [[SCPCarSplit shared] scene:scene destroyedForViewController:self ownScene:own]; }
    @catch (NSException *e) { SCPHookError("didDestroyScene", e); }
}

%end

%end // CARPLAY

// ---- iOS 15: moi app tren man xe chi duoc khai bao 1 lan voi FBSDisplayLayoutPublisher ----
// Split dua lai app con lai len (dong 1 o, keo o ra) -> CarPlay khai bao app do lan nua -> iOS 15 assert
// "already have an element with identifier=Car[2-3]:com.apple.mobilephone" (SIGTRAP, log 12/10 21:21). iOS 16 bo qua.
// Phan tu da co thi giu nguyen, tra 1 token rong cho CarPlay (no se goi invalidate khi app roi man).
// Log 19/10 21:59 (iPhone 8, 15.6): quet ivar cua publisher KHONG thay phan tu cu cua Google Maps (scene Maps da bi huy
// 19:28:53, CarPlay khong rut khai bao) -> 19:29:46 thoat chia man giu Navitel, CarPlay khai bao Maps lan nua -> assert.
// Nay tu theo doi: moi khai bao di qua addElement duoc ghi vao sLiveLayout (identifier -> token that) va bo ra khi token
// that bi invalidate (swizzle lop token luc gap lan dau); quet ivar chi con la du phong.
@interface SCPNoopLayoutAssertion : NSObject
- (void)invalidate;
@end
@implementation SCPNoopLayoutAssertion
- (void)invalidate {}
@end

// identifier -> token CarPlay dang giu, giu YEU (token dealloc = CarPlay da bo khai bao, khong duoc giu no song). Chi tren luong chinh.
static NSMapTable<NSString *, id> *sLiveLayout;
static NSArray<NSString *> *SCPLiveLayoutIDs(void)
{
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *k in sLiveLayout) if ([sLiveLayout objectForKey:k]) [ids addObject:k];
    return ids;
}

// Token that bi invalidate -> phan tu roi publisher -> bo khoi sLiveLayout. Swizzle 1 lan cho lop cua token.
static void SCPLayoutWatchTokenClass(id token)
{
    static NSMutableSet *done;
    if (!done) done = [NSMutableSet set];
    Class cls = object_getClass(token);
    NSString *name = NSStringFromClass(cls);
    if (!cls || [done containsObject:name]) return;
    [done addObject:name];
    SEL sel = @selector(invalidate);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { SCPLog("CarSplit: token khai bao %@ khong co invalidate -> khong theo doi duoc", name); return; }
    IMP orig = method_getImplementation(m);
    IMP mine = imp_implementationWithBlock(^(id self_) {
        NSMutableArray *gone = [NSMutableArray array];
        for (NSString *k in sLiveLayout) if ([sLiveLayout objectForKey:k] == self_) [gone addObject:k];
        for (NSString *k in gone) [sLiveLayout removeObjectForKey:k];
        ((void (*)(id, SEL))orig)(self_, sel);
    });
    method_setImplementation(m, mine);
    SCPLog("CarSplit: theo doi token khai bao lop %@", name);
}

static BOOL SCPLayoutIs(id obj, NSString *identifier)
{
    SEL s = @selector(identifier);
    if (![obj respondsToSelector:s]) return NO;
    id v = ((id (*)(id, SEL))objc_msgSend)(obj, s);
    return [v isKindOfClass:[NSString class]] && [v isEqualToString:identifier];
}

static BOOL SCPLayoutContains(id container, NSString *identifier)
{
    if ([container isKindOfClass:[NSDictionary class]] || [container isKindOfClass:[NSMapTable class]]) {
        if ([container objectForKey:identifier]) return YES;
        for (id key in [container keyEnumerator]) {
            if ([key isKindOfClass:[NSString class]] && [key hasSuffix:[@":" stringByAppendingString:identifier]]) return YES;   // "Car[2-3]:<id>"
            if (SCPLayoutIs(key, identifier) || SCPLayoutIs([container objectForKey:key], identifier)) return YES;
        }
    } else if ([container conformsToProtocol:@protocol(NSFastEnumeration)] && ![container isKindOfClass:[NSString class]]) {
        for (id item in container)
            if (SCPLayoutIs(item, identifier)) return YES;
    }
    return NO;
}

static BOOL SCPLayoutHasElement(id publisher, NSString *identifier)
{
    for (Class c = [publisher class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Ivar *ivars = class_copyIvarList(c, &n);
        BOOL found = NO;
        for (unsigned int i = 0; i < n && !found; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            found = SCPLayoutContains(object_getIvar(publisher, ivars[i]), identifier);
        }
        free(ivars);
        if (found) return YES;
    }
    return NO;
}

%group LAYOUT

%hook FBSDisplayLayoutPublisher

- (id)addElement:(id)element
{
    NSString *identifier = nil;
    @try {
        SEL s = @selector(identifier);
        id v = [element respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(element, s) : nil;
        if ([v isKindOfClass:[NSString class]]) identifier = v;
        if (!sLiveLayout) sLiveLayout = [NSMapTable strongToWeakObjectsMapTable];
        if (identifier && ([sLiveLayout objectForKey:identifier] || SCPLayoutHasElement(self, identifier))) {
            SCPLog("CarSplit: bo khai bao trung %@ (tranh assert cua iOS 15; dang giu: %@)", identifier,
                   [SCPLiveLayoutIDs() componentsJoinedByString:@" "]);
            return [SCPNoopLayoutAssertion new];
        }
    } @catch (NSException *e) { SCPHookError("addElement", e); }
    id token = %orig;
    @try {
        if (identifier && token) { [sLiveLayout setObject:token forKey:identifier]; SCPLayoutWatchTokenClass(token); }
    } @catch (NSException *e) { SCPHookError("addElement/theo doi", e); }
    return token;
}

%end

%end // LAYOUT

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.CarPlayApp"]) return;
    // Rescue mode + crash logger (Core): a crash goes to OmniCar.log on the next launch ("CARPLAY SAP LAN TRUOC")
    if (!OMCCrashGuard(SPL_FEATURE)) return;
    SCPLog("loaded into CarPlay");
    OMCLogFlush();
    %init(CARPLAY, DBDashboard = OMCCarClass("DBDashboard"), DBDashboardRootViewController = OMCCarClass("DBDashboardRootViewController"), DBApplicationSceneViewController = OMCCarClass("DBApplicationSceneViewController"));
    if (!objc_getClass("DBDashboard")) %init(LAYOUT);   // chi iOS 14-15 (CarPlay.app, lop CAR*); iOS 16+ giu nguyen
    OMCCheckHooks(@"SplitScreen", @[@"DBDashboard -sceneFrameForAppInfo:proxyAppInfo:", @"DBDashboard -safeAreaInsetsForAppInfo:proxyAppInfo:",
        @"DBDashboard -_handleHomeEvent:", @"DBDashboard -invalidate", @"DBDashboard -_launchAppWithInfo:forURL:",
        @"DBDashboardRootViewController -presentBaseViewController:animated:launchSource:completion:",
        @"DBDashboardRootViewController -dismissBaseViewControllerAnimated:completion:",
        @"DBApplicationSceneViewController -backgroundSceneWithCompletion:", @"DBApplicationSceneViewController -deactivateSceneWithReasonMask:",
        @"DBApplicationSceneViewController -sceneManager:didDestroyScene:"]);
#if OMC_AUTOTEST
    SCPAutoTestInstall();   // bo test Chia man hinh + App Bridge (chi ban dev)
#endif

    NSNotificationCenter *dnc = [objc_getClass("NSDistributedNotificationCenter") defaultCenter];
    NSOperationQueue *main = [NSOperationQueue mainQueue];

    // App Bridge (SpringBoard): trang thai app iPhone dang host / cham thanh "•••" ve tren app
    [dnc addObserverForName:AB_NOTIF_STATE object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[SCPCarSplit shared] hostedApp:note.userInfo[@"identifier"] state:note.userInfo[@"state"]]; }
        @catch (NSException *e) { SCPHookError("AB_STATE", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_HANDLE_TAP object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[SCPCarSplit shared] bridgeHandleTapped:note.userInfo[@"identifier"]]; }
        @catch (NSException *e) { SCPHookError("AB_HANDLE_TAP", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_HANDLE_DRAG object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[SCPCarSplit shared] bridgeHandleDrag:note.userInfo]; }
        @catch (NSException *e) { SCPHookError("AB_HANDLE_DRAG", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_BAR_ACTION object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[SCPCarSplit shared] bridgeBarAction:note.userInfo[@"action"] forBundle:note.userInfo[@"identifier"]]; }
        @catch (NSException *e) { SCPHookError("AB_BAR_ACTION", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_BAR_DISMISS object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[SCPCarSplit shared] bridgeOutsideTouched]; }
        @catch (NSException *e) { SCPHookError("AB_BAR_DISMISS", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_KNOB_TOUCH object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[SCPCarSplit shared] remoteKnobTouch:note.userInfo]; }
        @catch (NSException *e) { SCPHookError("AB_KNOB_TOUCH", e); }
    }];

    // SpringBoard (URL scheme / Siri) -> mo / dong split CarPlay
    [dnc addObserverForName:SPL_NOTIF_NATIVE object:nil queue:main usingBlock:^(NSNotification *note) {
        NSDictionary *u = note.userInfo;
        NSString *action = u[@"action"];
        SCPLog("CarSplit: yeu cau %@", u);
        SCPCarSplit *sp = [SCPCarSplit shared];
        @try {
            if ([action isEqualToString:@"close"]) {
                [sp closeGoingHome:YES];
            } else if ([action isEqualToString:@"closeApp"]) {
                [sp closeApp:u[@"identifier"]];
            } else if ([action isEqualToString:@"open"]) {
                [sp openApp:u[@"identifier"] slot:u[@"slot"] ? [u[@"slot"] intValue] : -1];
            } else if ([action isEqualToString:@"pair"]) {
                [sp openPairLeft:u[@"left"] right:u[@"right"]];
            } else if ([action isEqualToString:@"fav"]) {
                [sp openFavorite:[u[@"index"] integerValue]];
            } else if ([action isEqualToString:@"picker"]) {
                [sp showPickerForFocusedPane];
            } else if ([action isEqualToString:@"layout"]) {
                [sp urlLayout:[u[@"id"] intValue]];
            } else if ([action isEqualToString:@"ratio"]) {
                [sp urlRatio:[u[@"r"] doubleValue]];
            } else if ([action isEqualToString:@"swap"]) {
                [sp urlSwap];
            } else if ([action isEqualToString:@"zoom"]) {
                [sp urlZoomPane:[u[@"pane"] intValue] ?: 1];
            }
        } @catch (NSException *e) { SCPHookError("yeu cau tu SpringBoard", e); }
        // Bao SpringBoard da nhan (khong thi SpringBoard giu lai, gui lai khi man xe san sang)
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:SPL_NOTIF_ACK object:nil userInfo:nil];
    }];
}
