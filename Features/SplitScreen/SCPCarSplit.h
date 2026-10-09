#import "common.h"

// =====================================================================
//  SCPCarSplit - chia doi man CarPlay NGAY TRONG process CarPlay (DashBoard).
//  Moi ngan la giao dien CarPlay that cua app (scene CarPlay / template), khong phai giao dien iPhone:
//  DashBoard tu mo app theo duong binh thuong (DBEvent type 4) va tao DBApplicationSceneViewController
//  (ke ca proxy CarPlayTemplateUIHost cho app template). Tweak chi "nhan nuoi" view controller do vao
//  1 ngan thay vi de DashBoard hien toan man, va bao kich thuoc ngan cho scene qua
//  -[DBDashboard sceneFrameForAppInfo:proxyAppInfo:].
//  Notification giua CarPlay <-> SpringBoard: SPL_NOTIF_* trong SplitScreen.h.
// =====================================================================

#define SCP_TEMPLATE_HOST @"com.apple.CarPlayTemplateUIHost"

@interface SCPCarSplit : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, readonly) BOOL bridgeStarting;   // CarBridge dang khoi dong chieu app vao ngan
- (CGRect)bridgeFrame;                                   // khung chieu CarBridge (toa do man xe), Zero neu khong co

- (void)openApp:(NSString *)bundleID slot:(int)slot;          // slot -1 = tu chon (ngan trong / ngan dang chon)
- (void)openPairLeft:(NSString *)left right:(NSString *)right;
- (void)openFavorite:(NSInteger)index;                         // bo cuc yeu thich 1..3 (dung bo cuc + app da dat)
- (void)showPickerForSlot:(int)slot;                           // -1 = ngan trong
- (void)closeGoingHome:(BOOL)goHome;                           // goHome: gui Home cho DashBoard de workspace ve man chinh
- (void)closeApp:(NSString *)bundleID;                         // dong ngan dang chua app nay (neu co)
- (BOOL)isCarPlayApp:(NSString *)bundleID;

// Dung trong hook
- (BOOL)paneSize:(CGSize *)outSize forBundle:(NSString *)bundleID;
- (BOOL)wantsViewController:(UIViewController *)vc;
- (void)adoptViewController:(UIViewController *)vc;
- (BOOL)protectsViewController:(id)vc;
- (id)sceneOfViewController:(id)vc;
- (void)scene:(id)scene destroyedForViewController:(id)vc ownScene:(id)own;
- (void)bridgeWindowLost:(NSString *)bundleID;   // SpringBoard khong con CBWindow cho app nay
- (void)bridgeHandleTapped:(NSString *)bundleID; // SpringBoard: cham thanh "•••" ve tren CBWindow -> hien thanh nut cua ngan
- (void)rootDidLayout;                 // DBDashboardRootViewController viewDidLayoutSubviews
- (void)dashboardInvalidated;           // ngat xe
- (void)refreshAppTabSoon;              // DashBoard vua mo / dong app toan man -> cap nhat nut Split Screen tren dock
- (void)repairPresentedViewController:(UIViewController *)vc;   // app toan man con bi an tu split -> hien lai
- (void)removeAppTab;
- (void)publishCarPlayApps;          // ghi danh sach app CarPlay (ca CarBridge) cho Settings loc app
- (void)carScreenAppeared;            // man xe vua hien (cam xe) -> tu mo split neu bat
- (void)baseViewControllerPresented;  // DashBoard vua trinh bay app toan man -> bo the che cua soloBundle
- (BOOL)ignoreHomeDuringBridgeStart;  // Home do CarBridge tu gui luc bat dau chieu (bo qua)
- (void)showPickerForFocusedPane;     // omnicar://splitscreen/picker khi dang chia: bang chon app cho o dang chon
@end

#ifdef __cplusplus
extern "C" {
#endif
NSString *SCPRealBundleForInfos(id info, id proxyInfo);   // bo qua CarPlayTemplateUIHost, tra ve bundle that cua app
#ifdef __cplusplus
}
#endif
