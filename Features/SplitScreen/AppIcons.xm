#import "common.h"
#import "SCPAppIcons.h"
#import "SCPCarSplit.h"
#import "SCPHomeScreen.h"
#import <notify.h>

// SBIconImageInfo cua SpringBoardHome (hook iconImageInfo ben duoi); phai nam truoc %group vi Logos khai bao ham goc o dau file
typedef struct {
    CGSize size;
    CGFloat scale;
    CGFloat continuousCornerRadius;
} SCPIconImageInfo;

// Inject vao process CarPlay cung OmniCarSplitScreen.dylib: icon app iPhone da chon (App Bridge) tren man chinh
// CarPlay. Xem SCPAppIcons.mm. Moi hook boc @try nhu CarPlay.xm.

static void SCPIconsHookError(const char *where, NSException *e)
{
    SCPLog("LOI trong %s: %@\n%@", where, e, e.callStackSymbols);
}

// So cot / hang cua luoi man chinh: chi doi luoi co >= 2 cot va >= 2 hang theo CarPlay (khong dong vao dock 1 hang / 1 cot).
// Hoi so goc qua chinh cac getter da hook -> co bao bypass tren luong nay de chung tra %orig.
static __thread BOOL sSCPGridBypass;

static BOOL SCPIsHomeGrid(id cfg, BOOL landscape)
{
    sSCPGridBypass = YES;
    NSUInteger c = 0, r = 0;
    @try {
        c = ((NSUInteger (*)(id, SEL))objc_msgSend)(cfg, NSSelectorFromString(landscape ? @"numberOfLandscapeColumns" : @"numberOfPortraitColumns"));
        r = ((NSUInteger (*)(id, SEL))objc_msgSend)(cfg, NSSelectorFromString(landscape ? @"numberOfLandscapeRows" : @"numberOfPortraitRows"));
    } @catch (NSException *e) {}
    sSCPGridBypass = NO;
    return c >= 2 && r >= 2;
}

static NSUInteger SCPGridValue(id cfg, NSUInteger orig, BOOL landscape, BOOL columns)
{
    if (sSCPGridBypass) return orig;
    NSInteger want = 0;
    @try { want = columns ? SCPHomeGridColumns() : SCPHomeGridRows(); } @catch (NSException *e) { want = 0; }
    if (want <= 0 || (NSUInteger)want == orig || !SCPIsHomeGrid(cfg, landscape)) return orig;
    static NSMutableSet *logged;
    NSString *k = [NSString stringWithFormat:@"%@%@%lu>%ld", landscape ? @"L" : @"P", columns ? @"c" : @"r", (unsigned long)orig, (long)want];
    if (!logged) logged = [NSMutableSet set];
    if (![logged containsObject:k]) { [logged addObject:k]; SCPLog("HomeScreen: luoi %@ %@ %lu -> %ld", landscape ? @"ngang" : @"doc", columns ? @"cot" : @"hang", (unsigned long)orig, (long)want); }
    return (NSUInteger)want;
}

// Mo hinh icon man chinh CarPlay: DBIconModel (DashBoard) truoc, roi SBHIconModel (iOS 14+) / SBIconModel (cu)
static Class SCPIconModelClass(void)
{
    return OMCCarClass("DBIconModel") ?: objc_getClass("SBHIconModel") ?: objc_getClass("SBIconModel");
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

// Hinh nen rieng duoi luoi icon + co icon (SCPHomeScreen.mm): man chinh CarPlay giu nguyen
- (void)viewDidLayoutSubviews
{
    %orig;
    @try { SCPHomeApply((UIViewController *)self); } @catch (NSException *e) { SCPIconsHookError("SCPHomeApply", e); }
}

// Hinh nen dong chi chay khi man chinh dang hien
- (void)viewDidAppear:(BOOL)animated
{
    %orig;
    @try { SCPHomeSetVisible(YES); } @catch (NSException *e) { SCPIconsHookError("SCPHomeSetVisible", e); }
}

- (void)viewDidDisappear:(BOOL)animated
{
    %orig;
    @try { SCPHomeSetVisible(NO); } @catch (NSException *e) { SCPIconsHookError("SCPHomeSetVisible", e); }
}

%end

// DashBoard sap mo app theo declaration gia (duong khac ngoai _launchAppWithInfo:, vi du mo lai app cuoi khi cam xe):
// dua sang App Bridge, khong bao gio de DashBoard tao scene CarPlay cho app iPhone (man den)
%hook DBApplicationLaunchInfo

// Bien the 1 tham so (Split Screen va DashBoard goi) khong di qua ban 2 tham so: cung chan app iPhone
+ (id)launchInfoForApplication:(id)info
{
    NSString *bid = nil;
    @try { bid = objcInvoke(info, @"bundleIdentifier"); } @catch (NSException *e) {}
    if (SCPIsInjectedPhoneApp(bid)) return nil;   // chi chan, khong tu mo (nguoi goi tu quyet)
    return %orig;
}

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

// Co icon tren man chinh goc cua CarPlay: luoi icon (SBIconListView / DBIconListView) xep theo SBIconListGridLayoutConfiguration
// cua SpringBoardHome; iconImageInfo (co anh icon, ti le, bo goc) nhan voi he so trong Cai dat (App tren man xe > Co icon).
// Cot / hang giu nguyen nen chi icon to / nho trong o cua no; nhan ten di theo icon. 100 % = khong doi gi.

%hook SBIconListGridLayoutConfiguration

- (SCPIconImageInfo)iconImageInfo
{
    SCPIconImageInfo info = %orig;
    CGFloat k = 1;
    @try {
        // da chon cot / hang: canh icon theo o luoi deu (SCPHomeIconSide), chi luoi man chinh (khong dock)
        if ((SCPHomeGridColumns() > 0 || SCPHomeGridRows() > 0) && info.size.width > 1 && SCPIsHomeGrid(self, YES))
            k = SCPHomeIconSide(info.size.width) / info.size.width;
        else k = SCPHomeIconScale();
    } @catch (NSException *e) { k = 1; }
    if (k > 0 && fabs(k - 1) > 0.001) {
        info.size.width *= k;
        info.size.height *= k;
        info.continuousCornerRadius *= k;
    }
    return info;
}

- (NSUInteger)numberOfPortraitColumns
{
    NSUInteger n = %orig;
    return SCPGridValue(self, n, NO, YES);
}

- (NSUInteger)numberOfPortraitRows
{
    NSUInteger n = %orig;
    return SCPGridValue(self, n, NO, NO);
}

- (NSUInteger)numberOfLandscapeColumns
{
    NSUInteger n = %orig;
    return SCPGridValue(self, n, YES, YES);
}

- (NSUInteger)numberOfLandscapeRows
{
    NSUInteger n = %orig;
    return SCPGridValue(self, n, YES, NO);
}

%end

// Luoi deu (SCPHomeLayoutGrid, SCPHomeScreen.mm): CarPlay xep icon xong (layoutIconsNow hoac layoutSubviews) thi dat lai tam
// icon vao tam o cua luoi cot x hang da chon. Ham tu bo qua luoi ngoai man chinh va khi so cot / hang de Tu dong.
%hook SBIconListView

- (void)layoutIconsNow
{
    %orig;
    @try { SCPHomeLayoutGrid((UIView *)self); } @catch (NSException *e) { SCPIconsHookError("SCPHomeLayoutGrid", e); }
}

- (void)layoutSubviews
{
    %orig;
    @try { SCPHomeLayoutGrid((UIView *)self); } @catch (NSException *e) { SCPIconsHookError("SCPHomeLayoutGrid", e); }
}

%end

// Ten app duoi icon (Man chinh CarPlay > Ten app): tat thi moi lan CarPlay dat nhan deu thanh an
%hook SBIconView

- (void)setLabelHidden:(BOOL)hidden
{
    BOOL show = YES;
    @try { show = SCPHomeShowNames(); } @catch (NSException *e) { show = YES; }
    %orig(hidden || !show);
}

%end

// An app CarPlay khoi man chinh (App tren man xe > tab App CarPlay, HS_KEY_HIDDEN_APPS): SpringBoardHome chi dua vao luoi
// icon nao isIconVisible:; app bi an van mo duoc (cuoc goi, chi duong, Siri). Xem SCPIconHiddenOnCar (SCPAppIcons.mm).
// Lop that la mo hinh icon cua CarPlay: DBIconModel (iOS 16: DBIconModel < SBHIconModel, khong con SBIconModel) tu
// override isIconVisible: -> hook thang DBIconModel, khong co thi lop cha cua SpringBoardHome (xem %ctor).
%hook SBIconModel

- (BOOL)isIconVisible:(id)icon
{
    @try { if (SCPIconHiddenOnCar(icon)) return NO; } @catch (NSException *e) { SCPIconsHookError("isIconVisible", e); }
    BOOL visible = %orig;
    // app iOS da bo trong Tuy chinh ma nguoi dung them lai trong OmniCar
    @try { if (!visible && SCPIconForcedOnCar(icon)) return YES; } @catch (NSException *e) { SCPIconsHookError("isIconVisible", e); }
    return visible;
}

%end

%end // APPICONS

// Du phong cho Ten app (cach CarPlayHideLabels da chay tren iOS 13-15): icon CarPlay hoi co toi da cua nhan -> 0 = khong ve
// nhan. Chi init khi lop icon cua CarPlay co ham nay (xem %ctor), khong thi chi con hook setLabelHidden: o tren.
%group CARLABELS

%hook CARIconView

+ (CGSize)maxLabelSizeForIconImageSize:(CGSize)size
{
    BOOL show = YES;
    @try { show = SCPHomeShowNames(); } @catch (NSException *e) { show = YES; }
    if (!show) return CGSizeZero;   // Logos khong doc duoc %orig trong bieu thuc ? :
    return %orig;
}

%end

%end // CARLABELS

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.CarPlayApp"]) return;
    if (!OMCCrashGuard(SPL_FEATURE)) return;
    %init(APPICONS, DashBoard = OMCCarClass("DashBoard"), DBApplicationInfo = OMCCarClass("DBApplicationInfo"), DBDashboardHomeViewController = OMCCarClass("DBDashboardHomeViewController"), DBApplicationLaunchInfo = OMCCarClass("DBApplicationLaunchInfo"),
          SBIconListGridLayoutConfiguration = objc_getClass("SBIconListGridLayoutConfiguration"), SBIconModel = SCPIconModelClass(),
          SBIconView = objc_getClass("SBIconView"), SBIconListView = objc_getClass("SBIconListView"));
    OMCCheckHooks(@"SplitScreen", @[@"DashBoard +_newApplicationLibrary", @"DBApplicationInfo -_loadFromProxy:",
        @"DBDashboardHomeViewController -initWithEnvironment:", @"DBDashboardHomeViewController -viewDidLayoutSubviews", @"DBApplicationLaunchInfo +launchInfoForApplication:",
        @"DBApplicationLaunchInfo +launchInfoForApplication:withActivationSettings:", @"SBIconListGridLayoutConfiguration -iconImageInfo",
        [NSString stringWithFormat:@"%s -isIconVisible:", class_getName(SCPIconModelClass())], @"SBIconListGridLayoutConfiguration -numberOfLandscapeColumns",
        @"SBIconListGridLayoutConfiguration -numberOfLandscapeRows", @"SBIconView -setLabelHidden:", @"SBIconListView -layoutIconsNow",
        @"SBIconListView -layoutSubviews"]);
    // Ten app du phong: lop icon cua CarPlay (CARIconView iOS 13-15, DBIconView iOS 16) co +maxLabelSizeForIconImageSize:
    Class iconView = objc_getClass("CARIconView") ?: OMCCarClass("DBIconView");
    if (iconView && [iconView respondsToSelector:NSSelectorFromString(@"maxLabelSizeForIconImageSize:")]) {
        %init(CARLABELS, CARIconView = iconView);
        SCPLog("HomeScreen: ten app du phong qua +[%@ maxLabelSizeForIconImageSize:]", NSStringFromClass(iconView));
    } else SCPLog("HomeScreen: khong co +maxLabelSizeForIconImageSize: (%@), ten app chi qua setLabelHidden:", iconView ? NSStringFromClass(iconView) : @"khong co lop icon");
    if (!OMCCarClass("DashBoard")) SCPLog("AppIcons: khong co lop DashBoard, icon app iPhone khong chen duoc");
    if (!objc_getClass("SBIconListGridLayoutConfiguration")) SCPLog("HomeScreen: khong co SBIconListGridLayoutConfiguration, Co icon khong doi duoc tren iOS nay");
    // Settings doi danh sach app (hoac bat / tat App Bridge) -> cap nhat thu vien, ve lai man chinh
    static int token;
    notify_register_dispatch("com.anlai.omnicar/prefschanged", &token, dispatch_get_main_queue(), ^(int t) {
        SCPRefreshAppIconsSoon();
        SCPRefreshHiddenAppsSoon();
        @try { SCPHomeRefresh(); } @catch (NSException *e) { SCPIconsHookError("SCPHomeRefresh", e); }
    });
}
