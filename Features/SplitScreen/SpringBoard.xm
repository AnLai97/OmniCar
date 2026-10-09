#import "common.h"
#import "SCPPrefs.h"
#import "SCPCarSplit.h"
#import <signal.h>

// Inject vao SpringBoard. Split nam het trong process CarPlay (SCPCarSplit); SpringBoard chi:
//  - nhan URL omnicar://splitscreen/... tu app OmniCar (Shortcuts / Siri) va chuyen sang CarPlay
//  - dat khung cua so CarBridge (CBWindow, nam trong SpringBoard) dung vao ngan split
//  - tat han app khi bam [x] tren ngan
// Log cua process CarPlay di qua OmniCarCore (OMCLog), khong can ghi ho o day.

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

    // Process CarPlay: dat cua so CarBridge (CBWindow) dung khung ngan split. CBWindow chi co khi CarBridge
    // dang chieu -> thu lai vai lan neu chua co.
    NSNotificationCenter *dnc = [objc_getClass("NSDistributedNotificationCenter") defaultCenter];
    [dnc addObserverForName:SPL_NOTIF_CBFRAME object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *note) {
        NSDictionary *u = note.userInfo;
        CGRect r = CGRectMake([u[@"x"] doubleValue], [u[@"y"] doubleValue], [u[@"w"] doubleValue], [u[@"h"] doubleValue]);
        SCPApplyCarBridgeFrame(r, u[@"identifier"], 0, ++sCBFrameSeq);
    }];

    // CarPlay da nhan yeu cau -> bo yeu cau dang giu; man xe vua san sang -> gui lai yeu cau chua toi (< 10 phut)
    [dnc addObserverForName:SPL_NOTIF_ACK object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *note) { sPendingNative = nil; }];
    [dnc addObserverForName:SPL_NOTIF_READY object:nil queue:[NSOperationQueue mainQueue]
                 usingBlock:^(NSNotification *note) {
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
