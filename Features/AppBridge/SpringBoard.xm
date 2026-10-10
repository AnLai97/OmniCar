#import "common.h"
#import "ABHost.h"
#import <substrate.h>
#import <notify.h>

// Dylib nap vao moi process UIKit (Filter: com.apple.UIKit): phan SpringBoard o day, phan trong app (ep huong) o App.xm.
// Inject vao SpringBoard: nhan AB_NOTIF_* tu process CarPlay (Split Screen) va giu app dang host song:
// khong bi dua ve nen khi khoa may / mo app khac tren iPhone, man iPhone tat van render (carplay-cast).

static int (*orig_BKSDisplayServicesSetScreenBlanked)(int) = NULL;

%group SPRINGBOARD

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)app
{
    %orig;
    ABLog("SpringBoard ready");
    NSNotificationCenter *dnc = [objc_getClass("NSDistributedNotificationCenter") defaultCenter];
    NSOperationQueue *main = [NSOperationQueue mainQueue];
    [dnc addObserverForName:AB_NOTIF_OPEN object:nil queue:main usingBlock:^(NSNotification *note) {
        NSDictionary *u = note.userInfo;
        CGRect r = CGRectMake([u[@"x"] doubleValue], [u[@"y"] doubleValue], [u[@"w"] doubleValue], [u[@"h"] doubleValue]);
        @try {
            [[ABHost shared] openApp:u[@"identifier"] frame:r];
            [[ABHost shared] setPassInsets:UIEdgeInsetsMake([u[@"pt"] doubleValue], [u[@"pl"] doubleValue], [u[@"pb"] doubleValue], [u[@"pr"] doubleValue])
                                    forApp:u[@"identifier"]];
            [[ABHost shared] setBarVisible:[u[@"bar"] boolValue] pop:[u[@"pop"] intValue] dim:[u[@"popDim"] boolValue] forApp:u[@"identifier"]];
            [[ABHost shared] setCornerRadius:[u[@"r"] doubleValue] corners:(CACornerMask)[u[@"corners"] unsignedLongLongValue] forApp:u[@"identifier"]];
            [[ABHost shared] setHandleOffset:[u[@"hx"] doubleValue] forApp:u[@"identifier"]];
        } @catch (NSException *e) { ABLog("open loi %@\n%@", e, e.callStackSymbols); }
    }];
    [dnc addObserverForName:AB_NOTIF_FRAME object:nil queue:main usingBlock:^(NSNotification *note) {
        NSDictionary *u = note.userInfo;
        CGRect r = CGRectMake([u[@"x"] doubleValue], [u[@"y"] doubleValue], [u[@"w"] doubleValue], [u[@"h"] doubleValue]);
        UIEdgeInsets pass = UIEdgeInsetsMake([u[@"pt"] doubleValue], [u[@"pl"] doubleValue], [u[@"pb"] doubleValue], [u[@"pr"] doubleValue]);
        @try {
            [[ABHost shared] setFrame:r forApp:u[@"identifier"] live:[u[@"live"] boolValue] handle:[u[@"handle"] boolValue] passInsets:pass];
            [[ABHost shared] setBarVisible:[u[@"bar"] boolValue] pop:[u[@"pop"] intValue] dim:[u[@"popDim"] boolValue] forApp:u[@"identifier"]];
            [[ABHost shared] setCornerRadius:[u[@"r"] doubleValue] corners:(CACornerMask)[u[@"corners"] unsignedLongLongValue] forApp:u[@"identifier"]];
            [[ABHost shared] setHandleOffset:[u[@"hx"] doubleValue] forApp:u[@"identifier"]];
        } @catch (NSException *e) { ABLog("frame loi %@", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_CLOSE object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[ABHost shared] closeApp:note.userInfo[@"identifier"] terminate:[note.userInfo[@"terminate"] boolValue]]; }
        @catch (NSException *e) { ABLog("close loi %@", e); }
    }];
    [dnc addObserverForName:AB_NOTIF_CLOSEALL object:nil queue:main usingBlock:^(NSNotification *note) {
        @try { [[ABHost shared] closeAllExcept:note.userInfo[@"except"]]; } @catch (NSException *e) { ABLog("closeall loi %@", e); }
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
    // Xe ngat -> bo moi o (app van chay nen)
    [[NSNotificationCenter defaultCenter] addObserverForName:@"CarPlayIsConnectedDidChange" object:nil queue:main
                                                  usingBlock:^(NSNotification *note) {
        id dev = objcInvoke(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice");
        if (!dev) [[ABHost shared] carDisconnected];
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

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
    ABLog("loaded into SpringBoard");
    %init(SPRINGBOARD);
    void *fn = dlsym(RTLD_DEFAULT, "BKSDisplayServicesSetScreenBlanked");
    if (fn) MSHookFunction(fn, (void *)hook_BKSDisplayServicesSetScreenBlanked, (void **)&orig_BKSDisplayServicesSetScreenBlanked);
    else ABLog("khong tim thay BKSDisplayServicesSetScreenBlanked");
}
