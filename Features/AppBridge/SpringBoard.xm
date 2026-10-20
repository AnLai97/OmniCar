#import "common.h"
#import "ABHost.h"
#import "ABKeyboard.h"
#import <substrate.h>
#import <notify.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// Dylib nap vao moi process UIKit (Filter: com.apple.UIKit): phan SpringBoard o day, phan trong app (ep huong) o App.xm.
// Inject vao SpringBoard: nhan AB_NOTIF_* tu process CarPlay (Split Screen) va giu app dang host song:
// khong bi dua ve nen khi khoa may / mo app khac tren iPhone, man iPhone tat van render (carplay-cast).

static int (*orig_BKSDisplayServicesSetScreenBlanked)(int) = NULL;

#ifndef TWEAK_VERSION
#define TWEAK_VERSION "dev"
#endif
#ifndef OMC_BUILD
#define OMC_BUILD "dev"
#endif

// ---- Cau dao chong treo may (log 19/10 20:36, 7 Plus 15.7.7: SpringBoard ghi "loaded into SpringBoard" roi chet, may treo tao) ----
// Ghi "dang cai" (= ban + build) vao prefs truoc buoc nguy hiem, xoa khi xong / khi SpringBoard len. Lan khoi dong sau ma con
// "dang cai" CUA CHINH BUILD NAY = lan truoc SpringBoard khong len duoc sau buoc do -> ghi lai, khong lam buoc do nua o build nay;
// doi cai dat (prefschanged) hay cai build moi thi thu lai.
// Theo build, khong theo version (log 20/10 21:45): build e258fb5 treo vi OMCLogFlush, cau dao ghi "1.0.3"; ban sua 0518440 cung
// la 1.0.3 nen van bo hook SpringBoard -> App Bridge khong mo duoc app nao trong chia man hinh.
static void ABStore(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, OMC_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

// YES = duoc lam buoc nay (va da danh dau "dang cai", log da ghi xuong file)
static BOOL ABBreakerArm(NSString *pendingKey, NSString *crashedKey, NSString *what)
{
    OMCPrefsSync();
    NSString *ver = @TWEAK_VERSION " " OMC_BUILD;
    id pending = OMCPref(pendingKey, nil);
    if ([pending isEqual:ver]) {
        ABLog("lan truoc SpringBoard khong len duoc sau khi %@ -> bo buoc nay o build %@ (doi cai dat App Bridge de thu lai)", what, ver);
        ABStore(crashedKey, ver);
    } else if (pending) {
        ABLog("co dau \"dang cai\" cu (%@) cua build khac, khong tinh cho build %@", pending, ver);
    }
    if (pending) ABStore(pendingKey, nil);
    if ([OMCPref(crashedKey, nil) isEqual:ver]) { ABLog("bo qua %@: tung lam SpringBoard khong len o build %@", what, ver); OMCLogFlush(); return NO; }
    ABStore(pendingKey, ver);
    OMCLogFlush();
    return YES;
}

static void ABBreakerDisarm(NSString *pendingKey) { ABStore(pendingKey, nil); }

%group SPRINGBOARD

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)app
{
    %orig;
    ABLog("SpringBoard ready");
    ABBreakerDisarm(AB_KEY_SB_PENDING);   // SpringBoard len duoc voi hook da cai
    NSNotificationCenter *dnc = [objc_getClass("NSDistributedNotificationCenter") defaultCenter];
    NSOperationQueue *main = [NSOperationQueue mainQueue];
    [dnc addObserverForName:AB_NOTIF_OPEN object:nil queue:main usingBlock:^(NSNotification *note) {
        NSDictionary *u = note.userInfo;
        CGRect r = CGRectMake([u[@"x"] doubleValue], [u[@"y"] doubleValue], [u[@"w"] doubleValue], [u[@"h"] doubleValue]);
        @try {
            [[ABHost shared] openApp:u[@"identifier"] frame:r];
            [[ABHost shared] setPassInsets:UIEdgeInsetsMake([u[@"pt"] doubleValue], [u[@"pl"] doubleValue], [u[@"pb"] doubleValue], [u[@"pr"] doubleValue])
                                    forApp:u[@"identifier"]];
            [[ABHost shared] setBarVisible:[u[@"bar"] boolValue] pop:[u[@"pop"] intValue] dim:[u[@"popDim"] boolValue] single:[u[@"single"] boolValue] forApp:u[@"identifier"]];
            [[ABHost shared] setHole:CGRectMake([u[@"ox"] doubleValue], [u[@"oy"] doubleValue], [u[@"ow"] doubleValue], [u[@"oh"] doubleValue]) forApp:u[@"identifier"]];
            [[ABHost shared] setCornerRadius:[u[@"r"] doubleValue] corners:(CACornerMask)[u[@"corners"] unsignedLongLongValue] forApp:u[@"identifier"]];
            [[ABHost shared] setHandleOffset:[u[@"hx"] doubleValue] forApp:u[@"identifier"]];
            [[ABHost shared] setFront:[u[@"front"] boolValue] forApp:u[@"identifier"]];
            if ([u[@"aw"] doubleValue] > 0) [ABHost shared].carAppArea = CGRectMake([u[@"ax"] doubleValue], [u[@"ay"] doubleValue], [u[@"aw"] doubleValue], [u[@"ah"] doubleValue]);
        } @catch (NSException *e) { ABLog("open loi %@\n%@", e, e.callStackSymbols); }
    }];
    [dnc addObserverForName:AB_NOTIF_FRAME object:nil queue:main usingBlock:^(NSNotification *note) {
        NSDictionary *u = note.userInfo;
        CGRect r = CGRectMake([u[@"x"] doubleValue], [u[@"y"] doubleValue], [u[@"w"] doubleValue], [u[@"h"] doubleValue]);
        UIEdgeInsets pass = UIEdgeInsetsMake([u[@"pt"] doubleValue], [u[@"pl"] doubleValue], [u[@"pb"] doubleValue], [u[@"pr"] doubleValue]);
        @try {
            [[ABHost shared] setFrame:r forApp:u[@"identifier"] live:[u[@"live"] boolValue] handle:[u[@"handle"] boolValue] passInsets:pass];
            [[ABHost shared] setBarVisible:[u[@"bar"] boolValue] pop:[u[@"pop"] intValue] dim:[u[@"popDim"] boolValue] single:[u[@"single"] boolValue] forApp:u[@"identifier"]];
            [[ABHost shared] setHole:CGRectMake([u[@"ox"] doubleValue], [u[@"oy"] doubleValue], [u[@"ow"] doubleValue], [u[@"oh"] doubleValue]) forApp:u[@"identifier"]];
            [[ABHost shared] setCornerRadius:[u[@"r"] doubleValue] corners:(CACornerMask)[u[@"corners"] unsignedLongLongValue] forApp:u[@"identifier"]];
            [[ABHost shared] setHandleOffset:[u[@"hx"] doubleValue] forApp:u[@"identifier"]];
            [[ABHost shared] setFront:[u[@"front"] boolValue] forApp:u[@"identifier"]];
            if ([u[@"aw"] doubleValue] > 0) [ABHost shared].carAppArea = CGRectMake([u[@"ax"] doubleValue], [u[@"ay"] doubleValue], [u[@"aw"] doubleValue], [u[@"ah"] doubleValue]);
        } @catch (NSException *e) { ABLog("frame loi %@", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_SHIELD object:nil queue:main usingBlock:^(NSNotification *note) {   // co bang mo tren man xe -> chan cham vao moi app iPhone
        @try { [[ABHost shared] setShieldAll:[note.userInfo[@"on"] boolValue]]; } @catch (NSException *e) { ABLog("shield loi %@", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_CLOSE object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[ABHost shared] closeApp:note.userInfo[@"identifier"] terminate:[note.userInfo[@"terminate"] boolValue]]; }
        @catch (NSException *e) { ABLog("close loi %@", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_CLOSEALL object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[ABHost shared] closeAllExcept:note.userInfo[@"except"]]; } @catch (NSException *e) { ABLog("closeall loi %@", e); }
    }];
    // Cham tron cua vach chia (CarPlay gui) -> ve len tren cac o app iPhone
    [dnc addObserverForName:AB_NOTIF_KNOBS object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[ABHost shared] setKnobs:note.userInfo[@"knobs"]]; } @catch (NSException *e) { ABLog("knobs loi %@", e); }
    }];
    // App dang host vua doi yeu cau xoay (YouTube fullscreen): App.xm gui Darwin notify kem state (qua duoc sandbox)
    static int tokOrient = 0;
    notify_register_dispatch(AB_DARWIN_APP_ORIENT, &tokOrient, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        notify_get_state(t, &state);
        unsigned long long hash = state >> 24;
        NSUInteger mask = (NSUInteger)((state >> 8) & 0xFFFF);
        int code = (int)(state & 0xFF);
        @try { [[ABHost shared] appWithHash:hash changedOrientation:code supportedMask:mask]; }
        @catch (NSException *e) { ABLog("apporient loi %@", e); }
    });
    // O nhap trong app dang host duoc chon / bo chon -> ban phim tren man xe (ABKeyboard)
    static int tokKeyboard = 0;
    notify_register_dispatch(AB_DARWIN_APP_KEYBOARD, &tokKeyboard, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        notify_get_state(t, &state);
        @try {
            NSString *bid = [[ABHost shared] bundleForHash:state >> 24];
            if (!bid) { ABLog("ban phim: khong co o cho hash %llu", state >> 24); return; }
            if (state & 1) [[ABKeyboard shared] showForApp:bid keyboardType:(NSInteger)((state >> 1) & 0x7F) returnType:(NSInteger)((state >> 8) & 0xFF)];
            else [[ABKeyboard shared] hideForApp:bid];
        } @catch (NSException *e) { ABLog("ban phim loi %@", e); }
    });
    // Xe ngat -> bo moi o (app van chay nen)
    [[NSNotificationCenter defaultCenter] addObserverForName:@"CarPlayIsConnectedDidChange" object:nil queue:main
                                                  usingBlock:^(NSNotification *note) {
        id dev = objcInvoke(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice");
        if (!dev) { [[ABKeyboard shared] hideForApp:nil]; [[ABHost shared] carDisconnected]; }
    }];
}

%end

// Khong cho app dang host bi dua ve nen khi khoa may
%hook SBSuspendedUnderLockManager
- (BOOL)_shouldBeBackgroundUnderLockForScene:(id)scene withSettings:(id)settings
{
    BOOL r = %orig;
    if (r) {
        NSString *bid = nil;
        @try { bid = objcInvoke(objcInvoke(scene, @"clientProcess"), @"bundleIdentifier"); } @catch (NSException *e) {}   // iOS 16: FBScene.clientProcess
        if (bid && [[ABHost shared] hostsApp:bid]) r = NO;
    }
    return r;
}
%end

// Khong cho scene cua app dang host bi dua ve background khi mo app khac tren man iPhone
%hook FBScene
- (void)updateSettings:(id)settings withTransitionContext:(id)ctx completion:(void *)completion
{
    if ([ABHost shared].count) {
        NSString *bid = nil;
        @try { bid = objcInvoke(objcInvoke(self, @"clientProcess"), @"bundleIdentifier"); } @catch (NSException *e) {}
        if (bid && [[ABHost shared] hostsApp:bid] && !objcInvokeT(settings, @"isForeground", BOOL)) return;
    }
    %orig;
}
%end

// Scene view crash neu orientation la face-up/face-down -> ep ve landscape
%hook SBSceneView
- (void)_updateReferenceSize:(CGSize)size andOrientation:(long long)orientation
{
    if (orientation > 4) return %orig(size, 3);
    %orig;
}
%end

%end // SPRINGBOARD

// Man hinh iPhone tat khi dang host app tren XE -> tat roi bat lai "blank" de app van render (carplay-cast)
static int hook_BKSDisplayServicesSetScreenBlanked(int blanked)
{
    if (blanked == 1 && [ABHost shared].count > 0) {
        orig_BKSDisplayServicesSetScreenBlanked(1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            orig_BKSDisplayServicesSetScreenBlanked(0);
        });
        return 0;
    }
    return orig_BKSDisplayServicesSetScreenBlanked(blanked);
}

// Tweak khac cung va ham nay (CarBridge, carplay-cast) da nap vao SpringBoard? Hai tweak cung va mot ham C = SpringBoard de chet luc nap.
static BOOL ABOtherCarPlayTweakLoaded(NSString **name)
{
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (!n) continue;
        NSString *s = [@(n) lowercaseString];
        if ([s containsString:@"carbridge"] || [s containsString:@"carplay-cast"] || [s containsString:@"carplaycast"]) {
            if (name) *name = [@(n) lastPathComponent];
            return YES;
        }
    }
    return NO;
}

// Va ham BKSDisplayServicesSetScreenBlanked (man iPhone tat van render app tren xe, carplay-cast). Day la cho DUY NHAT OmniCar va
// ma may trong SpringBoard (MSHookFunction, ghi vao shared cache), phu thuoc jailbreak va ban ElleKit -> khong lam luc khoi dong
// nua, chi lam khi lan dau host app len xe (ABHost openApp): co treo thi treo luc do, may van len. Co cau dao rieng.
void ABInstallScreenBlankHook(void)
{
    static BOOL done;
    if (done) return;
    done = YES;
    NSString *other = nil;
    if (ABOtherCarPlayTweakLoaded(&other)) { ABLog("khong va BKSDisplayServicesSetScreenBlanked: SpringBoard da nap %@ (cung va ham nay)", other); return; }
    void *fn = dlsym(RTLD_DEFAULT, "BKSDisplayServicesSetScreenBlanked");
    if (!fn) { ABLog("khong tim thay BKSDisplayServicesSetScreenBlanked"); return; }
    if (!ABBreakerArm(AB_KEY_HOOK_PENDING, AB_KEY_HOOK_CRASHED, @"va ham BKSDisplayServicesSetScreenBlanked")) return;
    MSHookFunction(fn, (void *)hook_BKSDisplayServicesSetScreenBlanked, (void **)&orig_BKSDisplayServicesSetScreenBlanked);
    ABBreakerDisarm(AB_KEY_HOOK_PENDING);
    ABLog("da va BKSDisplayServicesSetScreenBlanked (lan dau host app)");
}

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
    ABLog("loaded into SpringBoard");
    // Doi cai dat -> cho cau dao thu lai o lan khoi dong sau
    static int prefsToken;
    notify_register_dispatch("com.anlai.omnicar/prefschanged", &prefsToken, dispatch_get_main_queue(), ^(int t) {
        OMCPrefsSync();
        if (OMCPref(AB_KEY_SB_CRASHED, nil) || OMCPref(AB_KEY_HOOK_CRASHED, nil)) {
            ABStore(AB_KEY_SB_CRASHED, nil); ABStore(AB_KEY_HOOK_CRASHED, nil);
            ABLog("doi cai dat -> lan khoi dong sau thu cai hook App Bridge lai");
        }
    });
    if (!ABBreakerArm(AB_KEY_SB_PENDING, AB_KEY_SB_CRASHED, @"cai hook trong SpringBoard")) return;
    %init(SPRINGBOARD);
    OMCCheckHooks(@"AppBridge", @[@"SBSuspendedUnderLockManager -_shouldBeBackgroundUnderLockForScene:withSettings:",
        @"FBScene -updateSettings:withTransitionContext:completion:", @"SBSceneView -_updateReferenceSize:andOrientation:"]);
    // Ham BKSDisplayServicesSetScreenBlanked: khong va o day nua, xem ABInstallScreenBlankHook
    OMCLogFlush();
}
