#import "common.h"
#import "SCPAppIcons.h"
#import "SCPCarSplit.h"
#import <notify.h>

// Inject vao process CarPlay cung OmniCarSplitScreen.dylib: icon app iPhone da chon (App Bridge) tren man chinh
// CarPlay. Xem SCPAppIcons.mm. Moi hook boc @try nhu CarPlay.xm.

static void SCPIconsHookError(const char *where, NSException *e)
{
    SCPLog("LOI trong %s: %@\n%@", where, e, e.callStackSymbols);
}

%group APPICONS

// Thu vien app cua DashBoard: giu nguyen, chi them app da chon vao (them tuong minh thi khong qua bo loc cua thu vien)
%hook DashBoard

+ (id)_newApplicationLibrary
{
    id lib = %orig;
    @try {
        if (SCPChosenPhoneApps().count && SCPAppIconsBeginInjection()) SCPAddChosenAppsToLibrary(lib);
    } @catch (NSException *e) { SCPIconsHookError("_newApplicationLibrary", e); }
    return lib;
}

%end

// Info cua tung app vua nap tu proxy: app da chon -> declaration gia (chay ca tren work queue cua thu vien)
%hook DBApplicationInfo

- (void)_loadFromProxy:(id)proxy
{
    %orig;
    @try { SCPInjectDeclarationIfChosen(self); } @catch (NSException *e) { SCPIconsHookError("_loadFromProxy", e); }
}

%end

// Man chinh: nho lai de cap nhat thu vien khi danh sach app doi
%hook DBDashboardHomeViewController

- (id)initWithEnvironment:(id)env
{
    id r = %orig;
    SCPSetHomeViewController(r);
    return r;
}

%end

// DashBoard sap mo app theo declaration gia (duong khac ngoai _launchAppWithInfo:, vi du mo lai app cuoi khi cam xe):
// dua sang App Bridge, khong bao gio de DashBoard tao scene CarPlay cho app iPhone (man den)
%hook DBApplicationLaunchInfo

+ (id)launchInfoForApplication:(id)info withActivationSettings:(id)settings
{
    NSString *bid = nil;
    @try { bid = objcInvoke(info, @"bundleIdentifier"); } @catch (NSException *e) {}
    if (SCPIsInjectedPhoneApp(bid)) {
        @try { [[SCPCarSplit shared] launchPhoneAppIfNeeded:bid]; } @catch (NSException *e) { SCPIconsHookError("launchInfoForApplication", e); }
        return nil;
    }
    return %orig;
}

%end

%end // APPICONS

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.CarPlayApp"]) return;
    %init(APPICONS);
    if (!objc_getClass("DashBoard")) SCPLog("AppIcons: khong co lop DashBoard, icon app iPhone khong chen duoc");
    // Settings doi danh sach app (hoac bat / tat App Bridge) -> cap nhat thu vien, ve lai man chinh
    static int token;
    notify_register_dispatch("com.anlai.omnicar/prefschanged", &token, dispatch_get_main_queue(), ^(int t) { SCPRefreshAppIconsSoon(); });
}
