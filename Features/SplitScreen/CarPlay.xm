#import "common.h"
#import "SCPPrefs.h"
#import "SCPCarSplit.h"
#import "SCPAppIcons.h"

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
        if (sp.active) [sp closeGoingHome:NO];
        [sp homePressed];
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

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.CarPlayApp"]) return;
    SCPLog("loaded into CarPlay");
    %init(CARPLAY);

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
            }
        } @catch (NSException *e) { SCPHookError("yeu cau tu SpringBoard", e); }
        // Bao SpringBoard da nhan (khong thi SpringBoard giu lai, gui lai khi man xe san sang)
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:SPL_NOTIF_ACK object:nil userInfo:nil];
    }];
}
