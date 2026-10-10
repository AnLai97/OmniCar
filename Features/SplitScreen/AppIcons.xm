#import "common.h"
#import "SCPAppIcons.h"
#import "SCPCarSplit.h"
#import <notify.h>

// Inject vao process CarPlay cung OmniCarSplitScreen.dylib: icon app iPhone da chon (App Bridge) tren man chinh
// CarPlay. Cach lam theo carplay-cast (nhanh ios16), xem SCPAppIcons.mm. Moi hook boc @try nhu CarPlay.xm.

static void SCPIconsHookError(const char *where, NSException *e)
{
    SCPLog("LOI trong %s: %@\n%@", where, e, e.callStackSymbols);
}

%group APPICONS

// Thu vien app cua DashBoard: goc chi gom app CarPlay -> thay bang thu vien gom moi app + declaration gia cho app da chon
%hook DashBoard

+ (id)_newApplicationLibrary
{
    @try {
        if (SCPChosenPhoneApps().count) {
            id lib = SCPNewLibraryWithPhoneApps();
            if (lib) return lib;
        } else {
            SCPAddPhoneAppDeclarations(nil);   // xoa danh sach da chen (app chon = 0 hoac App Bridge tat)
        }
    } @catch (NSException *e) { SCPIconsHookError("_newApplicationLibrary", e); }
    return %orig;
}

%end

// Man chinh: nho lai de doi thu vien khi danh sach app doi; cai / go app thi DashBoard goi _handleAppLibraryRefresh
%hook DBDashboardHomeViewController

- (id)initWithEnvironment:(id)env
{
    id r = %orig;
    SCPSetHomeViewController(r);
    return r;
}

- (void)_handleAppLibraryRefresh
{
    @try {
        if (SCPChosenPhoneApps().count) SCPAddPhoneAppDeclarations(objcInvoke(self, @"library"));
    } @catch (NSException *e) { SCPIconsHookError("_handleAppLibraryRefresh", e); }
    %orig;
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
    // Settings doi danh sach app (hoac bat / tat App Bridge) -> thu vien moi, ve lai man chinh
    static int token;
    notify_register_dispatch("com.anlai.omnicar/prefschanged", &token, dispatch_get_main_queue(), ^(int t) { SCPRefreshAppIconsSoon(); });
}
