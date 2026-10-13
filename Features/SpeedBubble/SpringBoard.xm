#import "common.h"
#import "SPPBubble.h"
#import "SPPPrefs.h"
#import "SPPWarn.h"
#import "SPPGPS.h"
#import <notify.h>

// Inject vao SpringBoard: nhan toc do tu app dan duong (Vietmap / GOFA) hoac GPS iPhone (SPPGPS.mm) -> ve bong bong +
// canh bao qua toc do tren man xe (SPPWarn.mm); nhan lenh tu Cai dat

// Xe ket noi / ngat: GPS iPhone bat / tat, cua so vien canh bao tao lai / bo. Man xe (CADisplay) co the hien muon hon
// thong bao -> xet lai them vai lan.
static void SPPCarChanged(void)
{
    [[SPPOverspeed shared] carChanged];
    [[SPPPhoneGPS shared] update];
}
static void SPPCarChangedSoon(void)
{
    SPPCarChanged();
    for (NSNumber *delay in @[@2, @6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SPPCarChanged(); });
    }
}

%group SPRINGBOARD

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)app
{
    %orig;
    SPPLog("SpringBoard ready");

    int tokSpeed = 0, tokDemo = 0, tokPrefs = 0, tokReset = 0;
    // App dan duong gui toc do + gioi han (kem chi so app); app bi tat trong Cai dat -> bo qua
    notify_register_dispatch(SPP_DARWIN_SPEED, &tokSpeed, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0; notify_get_state(t, &state);
        int flags = (int)((state >> 16) & 0xFF), speed = (int)((state >> 8) & 0xFF), limit = (int)(state & 0xFF);
        int app = (flags >> 3) & 7;
        if (![SPPPrefs appEnabled:app]) return;
        [[SPPBubble shared] updateSpeed:((flags & 1) ? speed : -1) limit:((flags & 2) ? limit : -1)
                          appForeground:(flags & 4) != 0 app:app];
    });
    notify_register_dispatch(SPP_DARWIN_DEMO, &tokDemo, dispatch_get_main_queue(), ^(int t) { [[SPPBubble shared] runDemo]; });
    notify_register_dispatch(SPP_DARWIN_RESET, &tokReset, dispatch_get_main_queue(), ^(int t) { [[SPPBubble shared] resetLayout]; });
    // Doi kieu / bat tat trong Cai dat -> ve lai ngay
    notify_register_dispatch(SPP_DARWIN_PREFS, &tokPrefs, dispatch_get_main_queue(), ^(int t) {
        [[SPPBubble shared] refresh];
        [[SPPOverspeed shared] reloadPrefs];   // che do / nguong canh bao
        [[SPPPhoneGPS shared] update];         // nguon GPS iPhone bat / tat
    });
    // Split Screen dang chia / mo bang chon tren man xe (state 1) -> bong bong tren xe tam an, 0 -> hien lai
    static int tokBusy = 0;
    notify_register_dispatch(OMC_DARWIN_CAR_BUSY, &tokBusy, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0; notify_get_state(t, &state);
        [[SPPBubble shared] setCarBusy:state != 0];
    });

    // Xe ket noi / ngat: bong bong chuyen cua so giua man xe va iPhone
    [[NSNotificationCenter defaultCenter] addObserverForName:@"CarPlayIsConnectedDidChange" object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [[SPPBubble shared] refresh];
        SPPCarChangedSoon();
    }];
    // Process CarPlay bao co man xe (Core: OMC_DARWIN_CAR_CONNECTED)
    static int tokCar = 0;
    notify_register_dispatch(OMC_DARWIN_CAR_CONNECTED, &tokCar, dispatch_get_main_queue(), ^(int t) { SPPCarChangedSoon(); });
    // Respring khi xe dang ket noi: bat GPS iPhone neu nguon la GPS
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SPPCarChanged(); });
}

%end

%end // SPRINGBOARD

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
    SPPLog("loaded into SpringBoard");
    %init(SPRINGBOARD);
#if OMC_AUTOTEST
    SPPAutoTestInstall();
#endif
}
