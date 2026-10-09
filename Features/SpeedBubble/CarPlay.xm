#import "common.h"
#import <notify.h>

// Inject vao process CarPlay (com.apple.CarPlayApp, code trong DashBoard.framework):
// cham bong bong tren xe -> SpringBoard gui SPP_DARWIN_OPEN_CAR (state = chi so app) -> mo giao dien CarPlay
// cua app do bang duong binh thuong cua DashBoard: [DBDashboard handleEvent:[DBEvent eventWithType:4 context:launchInfo]]
static void SPPOpenAppOnCar(NSString *bid)
{
    UIApplication *app = [UIApplication sharedApplication];
    if (![app respondsToSelector:NSSelectorFromString(@"_currentDashboard")]
        || ![app respondsToSelector:NSSelectorFromString(@"sharedApplicationLibrary")]) {
        SPPLog("CarPlay: khong co _currentDashboard / sharedApplicationLibrary");
        return;
    }
    id dashboard = objcInvoke(app, @"_currentDashboard");
    id info = objcInvoke_1(objcInvoke(app, @"sharedApplicationLibrary"), @"applicationInfoForBundleIdentifier:", bid);
    id launchInfo = info ? objcInvoke_1(objc_getClass("DBApplicationLaunchInfo"), @"launchInfoForApplication:", info) : nil;
    if (!dashboard || !launchInfo) { SPPLog("CarPlay: khong mo duoc %@ (dashboard=%@ info=%@)", bid, dashboard, info); return; }
    id ev = objcInvoke_2(objc_getClass("DBEvent"), @"eventWithType:context:", (unsigned long long)4, launchInfo);
    if (ev) objcInvoke_1(dashboard, @"handleEvent:", ev);
    SPPLog("CarPlay: mo %@", bid);
}

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.CarPlayApp"]) return;
    SPPLog("loaded into CarPlay");
    int tok = 0;
    notify_register_dispatch(SPP_DARWIN_OPEN_CAR, &tok, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0; notify_get_state(t, &state);
        SPPOpenAppOnCar(SPPNavAppBundle((int)state));
    });
}
