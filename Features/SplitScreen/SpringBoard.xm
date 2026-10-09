#import "common.h"
#import "SCPPrefs.h"
#import "SCPCarSplit.h"
#import <signal.h>

// Inject vao SpringBoard. Split nam het trong process CarPlay (SCPCarSplit); SpringBoard chi:
//  - nhan URL omnicar://splitscreen/... tu app OmniCar (Shortcuts / Siri) va chuyen sang CarPlay
//  - dat khung cua so CarBridge (CBWindow, nam trong SpringBoard) dung vao ngan split
//  - ve thanh "•••" mo tren CBWindow (CBWindow che het view cua CarPlay) va bao CarPlay khi cham
//  - tat han app khi bam [x] tren ngan
// Log cua process CarPlay di qua OmniCarCore (OMCLog), khong can ghi ho o day.

#pragma mark - Chan doan CarBridge (1 lan moi process + moi lan dat khung)

static NSString *SCPMethodNames(Class c)
{
    unsigned n = 0;
    Method *ms = class_copyMethodList(c, &n);
    NSMutableArray *a = [NSMutableArray array];
    for (unsigned i = 0; i < n; i++) [a addObject:NSStringFromSelector(method_getName(ms[i]))];
    free(ms);
    return [[a sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "];
}

static NSString *SCPIvarNames(Class c)
{
    unsigned n = 0;
    Ivar *iv = class_copyIvarList(c, &n);
    NSMutableArray *a = [NSMutableArray array];
    for (unsigned i = 0; i < n; i++) [a addObject:[NSString stringWithUTF8String:ivar_getName(iv[i]) ?: "?"]];
    free(iv);
    return [a componentsJoinedByString:@" "];
}

// API cua CBWindow / CBBridgeManager: de tim cach doi kich thuoc app CarBridge dung ti le (hien tai setAppFrame: +
// resizeWindows chi doi khung cua so, noi dung app giu co cu)
static void SCPDumpBridgeAPIOnce(id mgr, id win)
{
    static BOOL done;
    if (done || !win) return;
    done = YES;
    for (id obj in @[mgr ?: [NSNull null], win]) {
        if (obj == [NSNull null]) continue;
        Class c = object_getClass(obj);
        SCPLog("DIAG %@ (%@) ivars: %@", NSStringFromClass(c), NSStringFromClass(class_getSuperclass(c)), SCPIvarNames(c));
        SCPLog("DIAG %@ -%@", NSStringFromClass(c), SCPMethodNames(c));
    }
}

static NSString *SCPSceneInfo(UIView *v)
{
    for (NSString *k in @[@"sceneHandle", @"scene", @"hostedScene", @"_scene"]) {
        SEL s = NSSelectorFromString(k);
        if (![v respondsToSelector:s]) continue;
        id scene = nil;
        @try { scene = ((id (*)(id, SEL))objc_msgSend)(v, s); } @catch (NSException *e) {}
        if (!scene) continue;
        NSString *ident = nil, *frame = nil;
        @try {
            if ([scene respondsToSelector:NSSelectorFromString(@"identifier")]) ident = objcInvoke(scene, @"identifier");
            id settings = [scene respondsToSelector:NSSelectorFromString(@"settings")] ? objcInvoke(scene, @"settings") : nil;
            if (settings && [settings respondsToSelector:NSSelectorFromString(@"frame")])
                frame = NSStringFromCGRect(((CGRect (*)(id, SEL))objc_msgSend)(settings, NSSelectorFromString(@"frame")));
        } @catch (NSException *e) {}
        return [NSString stringWithFormat:@" %@=%@ id=%@ settings.frame=%@", k, NSStringFromClass([scene class]), ident ?: @"?", frame ?: @"?"];
    }
    return @"";
}

static void SCPDumpView(UIView *v, UIView *root, int depth, NSMutableString *out)
{
    if (!v || depth > 6 || out.length > 5000) return;
    CGRect r = [root convertRect:v.bounds fromView:v];
    CGAffineTransform t = v.transform;
    [out appendFormat:@"%@%@ %@ bounds=%@ t=(%.3f,%.3f)%@%@%@\n",
        [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], NSStringFromClass([v class]),
        NSStringFromCGRect(r), NSStringFromCGSize(v.bounds.size), t.a, t.d, v.hidden ? @" hidden" : @"",
        v.clipsToBounds ? @" clip" : @"", SCPSceneInfo(v)];
    for (UIView *c in v.subviews) SCPDumpView(c, root, depth + 1, out);
}

#pragma mark - Thanh "•••" tren CBWindow

// CADisplay cua man hinh xe (nil neu chua ket noi)
static id SCPCarDisplay(void)
{
    id dev = objcInvoke(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice");
    NSArray *ids = dev ? objcInvoke(dev, @"screenIDs") : nil;
    if (!ids.count) return nil;
    for (id display in objcInvoke(objc_getClass("CADisplay"), @"displays")) {
        if ([ids[0] isEqualToString:objcInvoke(display, @"uniqueId")]) return display;
    }
    return nil;
}

// Cua so cua SpringBoard tren man xe (UIRootSceneWindow, nhu bong bong toc do)
static UIWindow *SCPMakeCarWindow(void)
{
    id display = SCPCarDisplay();
    if (!display) return nil;
    id config = objcInvoke_2([objc_getClass("FBSDisplayConfiguration") alloc], @"initWithCADisplay:isMainDisplay:", display, 0);
    if (!config) return nil;
    UIWindow *w = objcInvoke_1([objc_getClass("UIRootSceneWindow") alloc], @"initWithDisplayConfiguration:", config);
    return [w isKindOfClass:[UIWindow class]] ? w : nil;
}

// Cua so phu kin man xe nhung cho cham xuyen qua o moi cho khong co thanh "•••" (doi class cua instance luc chay)
static UIView *SCPPassThroughHitTest(id self, SEL _cmd, CGPoint p, UIEvent *e)
{
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    UIView *v = ((UIView *(*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
    return (v == self) ? nil : v;
}

static void SCPMakeWindowPassThrough(UIWindow *w)
{
    Class base = object_getClass(w);
    NSString *name = [NSString stringWithFormat:@"SCPPassThrough_%@", NSStringFromClass(base)];
    Class cls = objc_getClass(name.UTF8String);
    if (!cls) {
        cls = objc_allocateClassPair(base, name.UTF8String, 0);
        Method m = class_getInstanceMethod(base, @selector(hitTest:withEvent:));
        class_addMethod(cls, @selector(hitTest:withEvent:), (IMP)SCPPassThroughHitTest, method_getTypeEncoding(m));
        objc_registerClassPair(cls);
    }
    object_setClass(w, cls);
}

static UIWindow *sHandleWindow;
static UIView *sHandleView;        // vung cham 44x24, pill "•••" ve ben trong
static NSString *sHandleBundle;    // app CarBridge dang chieu (gui kem khi cham)
static NSString *sHandleDisplayID; // man xe cua cua so dang co (doi xe / cam lai -> tao cua so moi)

@interface SCPHandleTarget : NSObject
- (void)tapped:(UITapGestureRecognizer *)g;
@end
@implementation SCPHandleTarget
- (void)tapped:(UITapGestureRecognizer *)g
{
    if (!sHandleBundle) return;
    SCPLog("CarBridge: cham thanh ••• tren CBWindow (%@)", sHandleBundle);
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        postNotificationName:SPL_NOTIF_HANDLE_TAP object:nil userInfo:@{@"identifier": sHandleBundle}];
}
@end

static void SCPHideBridgeHandle(void)
{
    sHandleWindow.hidden = YES;
}

// r: khung thanh "•••" (toa do man xe) do CarPlay gui
static void SCPShowBridgeHandle(CGRect r, NSString *bid)
{
    id display = SCPCarDisplay();
    NSString *did = display ? objcInvoke(display, @"uniqueId") : nil;
    if (!did) { SCPHideBridgeHandle(); return; }
    if (sHandleWindow && ![did isEqualToString:sHandleDisplayID]) { sHandleWindow.hidden = YES; sHandleWindow = nil; sHandleView = nil; }
    if (!sHandleWindow) {
        UIWindow *w = SCPMakeCarWindow();
        if (!w) { SCPLog("CarBridge: khong tao duoc cua so thanh ••• tren man xe"); return; }
        SCPMakeWindowPassThrough(w);
        w.windowLevel = UIWindowLevelAlert + 200;   // tren CBWindow cua CarBridge
        w.backgroundColor = [UIColor clearColor];

        UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 24)];
        UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(5, 6, 34, 12)];
        pill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.38];   // bong mo tren app
        pill.layer.cornerRadius = 6;
        pill.userInteractionEnabled = NO;
        for (int i = 0; i < 3; i++) {
            UIView *d = [[UIView alloc] initWithFrame:CGRectMake(9 + i * 7, 4, 4, 4)];
            d.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
            d.layer.cornerRadius = 2;
            [pill addSubview:d];
        }
        [v addSubview:pill];
        static SCPHandleTarget *target;
        if (!target) target = [SCPHandleTarget new];
        [v addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(tapped:)]];
        [w addSubview:v];
        sHandleWindow = w; sHandleView = v; sHandleDisplayID = did;
        SCPLog("CarBridge: cua so thanh ••• tren man xe %@", NSStringFromCGRect(w.bounds));
    }
    sHandleBundle = bid;
    sHandleView.center = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    sHandleWindow.hidden = NO;
}

#pragma mark - Khung CBWindow

// Dat CBWindow cua CarBridge (SpringBoard) = khung ngan split CarPlay. w = 0 -> an cua so (ngan dang an).
// Moi yeu cau dat khung tang so thu tu; lan thu lai cua yeu cau cu thi bo (khong de khung cu de len khung moi)
static NSUInteger sCBFrameSeq;

static void SCPApplyCarBridgeFrame(CGRect r, NSString *bid, int attempt, NSUInteger seq)
{
    if (seq != sCBFrameSeq) return;
    Class mc = objc_getClass("CBBridgeManager");
    id mgr = (mc && [mc respondsToSelector:@selector(sharedInstance)]) ? objcInvoke(mc, @"sharedInstance") : nil;
    id win = nil;
    @try { win = (mgr && [mgr respondsToSelector:NSSelectorFromString(@"window")]) ? objcInvoke(mgr, @"window") : nil; } @catch (NSException *e) {}
    if (!win) {
        if (attempt < 6) {   // ~2.4s roi bao CarPlay chieu lai
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SCPApplyCarBridgeFrame(r, bid, attempt + 1, seq);
            });
        } else {
            SCPLog("CarBridge: khong thay CBWindow de dat khung %@ (%@) -> bao CarPlay chieu lai", NSStringFromCGRect(r), bid);
            if (bid && r.size.width >= 2)
                [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
                    postNotificationName:SPL_NOTIF_CBLOST object:nil userInfo:@{@"identifier": bid}];
        }
        return;
    }
    SCPDumpBridgeAPIOnce(mgr, win);
    UIWindow *root = nil;
    @try { root = [win respondsToSelector:NSSelectorFromString(@"rootWindow")] ? objcInvoke(win, @"rootWindow") : nil; } @catch (NSException *e) {}
    if (r.size.width < 2 || r.size.height < 2) {
        root.hidden = YES;
        SCPLog("CarBridge: ngan dang an -> an CBWindow");
        return;
    }
    @try {
        ((void (*)(id, SEL, CGRect))objc_msgSend)(win, NSSelectorFromString(@"setAppFrame:"), r);
        @try { [mgr setValue:[NSValue valueWithCGRect:r] forKey:@"appFrame"]; } @catch (NSException *e) {}
        objcCall(win, @"resizeWindows");
    } @catch (NSException *e) { SCPLog("CarBridge: dat khung loi %@", e); return; }
    root.hidden = NO;
    SCPLog("CarBridge: CBWindow %@ -> %@ (rootWindow %@)", bid, NSStringFromCGRect(r), root ? NSStringFromCGRect(root.frame) : @"nil");
    // Chan doan: cay view trong rootWindow sau khi dat khung (xem view nao chua app, scale the nao)
    if (root) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSMutableString *s = [NSMutableString string];
            SCPDumpView(root, root, 0, s);
            SCPLog("DIAG CBWindow rootWindow level=%.0f sau khi dat %@:\n%@", root.windowLevel, NSStringFromCGRect(r), s);
        });
    }
}

// Nut [x] tren ngan CarPlay: tat han app (nhu vuot tat trong app switcher). FBSSystemService, khong co thi kill pid.
static void SCPTerminateApp(NSString *bid)
{
    if (![bid isKindOfClass:[NSString class]] || !bid.length) return;
    id svc = nil;
    Class sc = objc_getClass("FBSSystemService");
    if (sc && [sc respondsToSelector:@selector(sharedService)]) svc = objcInvoke(sc, @"sharedService");
    SEL sel = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
    if ([svc respondsToSelector:sel]) {
        @try {
            ((void (*)(id, SEL, id, long long, BOOL, id))objc_msgSend)(svc, sel, bid, 1, NO, @"OmniCar Split Screen close");
            SCPLog("tat han %@ (FBSSystemService)", bid);
            return;
        } @catch (NSException *e) { SCPLog("tat han %@ loi %@", bid, e); }
    }
    id ctl = objcInvoke(objc_getClass("SBApplicationController"), @"sharedInstance");
    id app = ctl ? objcInvoke_1(ctl, @"applicationWithBundleIdentifier:", bid) : nil;
    id state = app ? objcInvoke(app, @"processState") : nil;
    int pid = state ? objcInvokeT(state, @"pid", int) : 0;
    if (pid > 0) { kill(pid, SIGKILL); SCPLog("tat han %@ (kill pid %d)", bid, pid); }
    else SCPLog("tat han %@: khong thay process", bid);
}

#pragma mark - URL -> CarPlay

// Gui yeu cau sang process CarPlay. Xe chua ket noi thi khong co process CarPlay nghe: giu lai yeu cau cuoi
// (toi da 10 phut) va gui lai khi man xe san sang (SPL_NOTIF_READY). CarPlay nhan duoc thi tra SPL_NOTIF_ACK.
static NSDictionary *sPendingNative;
static CFAbsoluteTime sPendingNativeAt;

static void SCPPostNative(NSDictionary *info)
{
    SCPLog("-> split CarPlay: %@", info);
    sPendingNative = info;
    sPendingNativeAt = CFAbsoluteTimeGetCurrent();
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:SPL_NOTIF_NATIVE object:nil userInfo:info];
}

// URL tu app OmniCar (Shortcuts / Siri): omnicar://splitscreen/open?left=..&right=.. | fav?n=1 | close | picker
static void SCPHandleURL(NSString *urlString)
{
    NSURL *url = [urlString isKindOfClass:[NSString class]] ? [NSURL URLWithString:urlString] : nil;
    if (![url.scheme isEqualToString:@"omnicar"] || ![url.host isEqualToString:SPL_URL_HOST]) return;
    if (![SCPPrefs enabled]) { SCPLog("URL %@ bo qua: tinh nang dang tat", urlString); return; }
    NSString *action = url.pathComponents.count > 1 ? url.pathComponents[1] : @"open";
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *it in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if (it.value) q[it.name] = it.value;
    }
    SCPLog("yeu cau tu URL: %@ %@", action, q);
    if ([action isEqualToString:@"close"]) {
        SCPPostNative(@{@"action": @"close"});
    } else if ([action isEqualToString:@"picker"]) {
        SCPPostNative(@{@"action": @"picker"});
    } else if ([action isEqualToString:@"fav"]) {
        SCPPostNative(@{@"action": @"fav", @"index": @([q[@"n"] integerValue])});
    } else {
        // open?left=..&right=..: chi mo dung app trong link (khong ghi de cap mac dinh, thieu ben nao thi
        // o do hien bang chon app)
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObject:@"pair" forKey:@"action"];
        if (q[@"left"]) d[@"left"] = q[@"left"];
        if (q[@"right"]) d[@"right"] = q[@"right"];
        SCPPostNative(d);
    }
}

%group SPRINGBOARD

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)app
{
    %orig;
    SCPLog("SpringBoard ready, dang ky notification");

    // Process CarPlay: dat cua so CarBridge (CBWindow) dung khung ngan split, va thanh "•••" tren do. CBWindow chi co
    // khi CarBridge dang chieu -> thu lai vai lan neu chua co.
    NSNotificationCenter *dnc = [objc_getClass("NSDistributedNotificationCenter") defaultCenter];
    [dnc addObserverForName:SPL_NOTIF_CBFRAME object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *note) {
        NSDictionary *u = note.userInfo;
        CGRect r = CGRectMake([u[@"x"] doubleValue], [u[@"y"] doubleValue], [u[@"w"] doubleValue], [u[@"h"] doubleValue]);
        ++sCBFrameSeq;   // yeu cau moi: lan thu lai cua yeu cau cu bi bo
        // w < 0: CarBridge dung chieu / split dong luc CarBridge dang khoi dong -> bo yeu cau dang cho, an thanh "•••",
        // khong dong / doi khung cua so CarBridge (no tu lo)
        // w == -2: bang bo cuc vua dong tren app CarBridge toan man -> hien lai CBWindow, khong doi khung
        if (r.size.width == -2) {
            Class mc = objc_getClass("CBBridgeManager");
            id mgr = (mc && [mc respondsToSelector:@selector(sharedInstance)]) ? objcInvoke(mc, @"sharedInstance") : nil;
            id win = nil;
            @try { win = (mgr && [mgr respondsToSelector:NSSelectorFromString(@"window")]) ? objcInvoke(mgr, @"window") : nil; } @catch (NSException *e) {}
            UIWindow *root = nil;
            @try { root = (win && [win respondsToSelector:NSSelectorFromString(@"rootWindow")]) ? objcInvoke(win, @"rootWindow") : nil; } @catch (NSException *e) {}
            root.hidden = NO;
            SCPLog("CarBridge: hien lai CBWindow cua %@ (%@)", u[@"identifier"], root ? @"ok" : @"khong co cua so");
            return;
        }
        if (r.size.width < 0) { SCPHideBridgeHandle(); SCPLog("CarBridge: bo yeu cau dat khung cho %@", u[@"identifier"]); return; }
        BOOL handle = [u[@"handle"] boolValue] && r.size.width >= 2;
        if (handle) SCPShowBridgeHandle(CGRectMake([u[@"hx"] doubleValue], [u[@"hy"] doubleValue], [u[@"hw"] doubleValue], [u[@"hh"] doubleValue]), u[@"identifier"]);
        else SCPHideBridgeHandle();
        SCPApplyCarBridgeFrame(r, u[@"identifier"], 0, sCBFrameSeq);
    }];

    // CarPlay da nhan yeu cau -> bo yeu cau dang giu; man xe vua san sang -> gui lai yeu cau chua toi (< 10 phut)
    [dnc addObserverForName:SPL_NOTIF_ACK object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *note) { sPendingNative = nil; }];
    [dnc addObserverForName:SPL_NOTIF_READY object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *note) {
        SCPHideBridgeHandle();   // xe vua ket noi: khong con app CarBridge nao dang chieu trong ngan
        NSDictionary *req = sPendingNative;
        if (!req || CFAbsoluteTimeGetCurrent() - sPendingNativeAt > 600) { sPendingNative = nil; return; }
        SCPLog("man xe san sang -> gui lai yeu cau %@", req);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (sPendingNative == req) SCPPostNative(req);
        });
    }];

    // Nut [x] tren ngan CarPlay -> tat han app
    [dnc addObserverForName:SPL_NOTIF_KILL object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *note) { SCPTerminateApp(note.userInfo[@"identifier"]); }];

    // App OmniCar (URL scheme) -> yeu cau cho tinh nang nay
    [dnc addObserverForName:OMC_URL_NOTIFY object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *note) { SCPHandleURL(note.userInfo[@"url"]); }];
}

%end

%end // SPRINGBOARD

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
    SCPLog("loaded into SpringBoard");
    %init(SPRINGBOARD);
}
