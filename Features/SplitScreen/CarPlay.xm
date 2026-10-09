#import "common.h"
#import "SCPPrefs.h"
#import "SCPCarSplit.h"

// Inject vao process CarPlay (com.apple.CarPlayApp, code trong DashBoard.framework, prefix DB).
// Split hien GIAO DIEN CARPLAY cua app: DashBoard tu mo scene CarPlay cua app (giong cham icon),
// tweak dua view controller cua scene do vao 1 ngan va bao kich thuoc ngan cho scene (xem SCPCarSplit.mm).
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

// Nut Home cua CarPlay khi dang split -> tat split (scene ve background) roi de DashBoard ve man chinh
- (void)_handleHomeEvent:(id)event
{
    @try {
        SCPCarSplit *sp = [SCPCarSplit shared];
        // CarBridge tu gui Home ngay luc bat dau chieu (~1s dau) -> giu split; sau do la nguoi dung bam -> dong
        if (sp.active && [sp ignoreHomeDuringBridgeStart]) SCPLog("CarSplit: Home do CarBridge luc bat dau chieu -> giu split");
        else if (sp.active) [sp closeGoingHome:NO];
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
        [sp baseViewControllerPresented];   // bo the icon che luc thoat chia / toan man hinh
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
        if (sp.active && !sp.bridgeStarting && !objcInvoke(self, @"currentBaseViewController")) {
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

// ---- CarBridge (app iPhone tren CarPlay): chieu vao ngan thay vi toan man ----
%group CARBRIDGE
%hook CBBridgeManagerDashboard

// Khung CBWindow: dang chieu vao ngan -> khung ngan
- (CGRect)getAppFrame
{
    @try {
        CGRect r = [[SCPCarSplit shared] bridgeFrame];
        if (r.size.width > 1 && r.size.height > 1) return r;
    } @catch (NSException *e) { SCPHookError("getAppFrame", e); }
    return %orig;
}

// Truoc khi chieu CarBridge dua CarPlay ve man chinh -> dang split thi bo qua (se dong split)
- (void)prepareHomeScreenForBridge:(id)completion
{
    if ([SCPCarSplit shared].active) {
        SCPLog("CarBridge: dang split -> bo qua ve man chinh");
        if (completion) ((void (^)(void))completion)();
        return;
    }
    %orig;
}

// CarBridge dong app CarPlay dang mo (vd Vietmap o ngan kia) -> dang split thi giu lai
- (void)closeOfficialTopApp:(id)arg
{
    if ([SCPCarSplit shared].active) {
        SCPLog("CarBridge: dang split -> giu app CarPlay o ngan kia");
        if (arg && [arg isKindOfClass:NSClassFromString(@"NSBlock")]) ((void (^)(void))arg)();
        return;
    }
    %orig;
}

%end
%end // CARBRIDGE

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.CarPlayApp"]) return;
    SCPLog("loaded into CarPlay");
    %init(CARPLAY);
    if (objc_getClass("CBBridgeManagerDashboard")) { %init(CARBRIDGE); SCPLog("CarBridge: da noi vao CarBridge"); }
    else SCPLog("CarBridge: khong co (bo qua)");

    // SpringBoard: CarBridge da dong CBWindow cua app dang nam trong ngan -> chieu lai
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:SPL_NOTIF_CBLOST object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        @try { [[SCPCarSplit shared] bridgeWindowLost:note.userInfo[@"identifier"]]; }
        @catch (NSException *e) { SCPHookError("CBLOST", e); }
    }];

    // SpringBoard: cham thanh "•••" ve tren CBWindow -> hien thanh nut cua ngan
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:SPL_NOTIF_HANDLE_TAP object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        @try { [[SCPCarSplit shared] bridgeHandleTapped:note.userInfo[@"identifier"]]; }
        @catch (NSException *e) { SCPHookError("HANDLE_TAP", e); }
    }];

    // SpringBoard (URL scheme / Siri) -> mo / dong split CarPlay
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:SPL_NOTIF_NATIVE object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
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
