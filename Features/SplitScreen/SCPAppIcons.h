#import "common.h"

// Icon app iPhone tren man chinh CarPlay (nhu CarBridge): giu thu vien app goc cua DashBoard, them proxy cua app
// nguoi dung chon trong App Bridge > App tren man xe (AB_KEY_APPS) vao thu vien, va gan CarPlay declaration gia
// (CRCarPlayAppDeclaration) cho DBApplicationInfo cua app do ngay luc thu vien tao info (_loadFromProxy:) de DashBoard
// ve icon. Cham icon: hook _launchAppWithInfo: (CarPlay.xm) / launchInfoForApplication: (AppIcons.xm) dua app sang
// App Bridge thay vi mo scene CarPlay.
#ifdef __cplusplus
extern "C" {
#endif
// Chan doan 1 lan: lop / method / ivar cua thu vien app, app info, declaration, icon tren man chinh
void SCPDumpAppLibraryOnce(void);
// App iPhone da duoc gan declaration gia (bundle id) -> khong coi la app CarPlay that
BOOL SCPIsInjectedPhoneApp(NSString *bid);
// Bundle id da chon trong App Bridge (AB_KEY_APPS), doc lai prefs moi lan goi; rong khi App Bridge tat
NSSet<NSString *> *SCPChosenPhoneApps(void);
// -[DBApplicationInfo _loadFromProxy:] vua chay: app da chon ma khong co declaration -> gan declaration gia
void SCPInjectDeclarationIfChosen(id info);
// Them proxy cua app da chon vao thu vien (app CarPlay that da co trong thu vien thi bo qua)
void SCPAddChosenAppsToLibrary(id library);
// DBDashboardHomeViewController dang hien (de cap nhat thu vien khi danh sach app doi)
void SCPSetHomeViewController(id vc);
// Danh sach app da chon vua doi (prefschanged): them / bo app trong thu vien va ve lai man chinh (co debounce)
void SCPRefreshAppIconsSoon(void);
// App CarPlay an khoi man chinh (HS_KEY_HIDDEN_APPS): icon (SBApplicationIcon ...) co phai cua app bi an khong.
// Goi tu hook -[SBIconModel isIconVisible:] (co the tren nhieu queue).
BOOL SCPIconHiddenOnCar(id icon);
// Cai dat doi (prefschanged): doc lai danh sach an; doi thi bao mo hinh icon xep lai man chinh
void SCPRefreshHiddenAppsSoon(void);
// Xep lai man chinh tu mo hinh icon (-[iconModel layout], khong co thi _handleAppLibraryRefresh): an app, doi so cot / hang
void SCPHomeIconModelLayout(NSString *why);
// Cau dao chong crash-loop (xem SCPAppIcons.mm): hoi truoc khi chen; bao man xe da hien; cho phep thu lai
BOOL SCPAppIconsBeginInjection(void);
void SCPAppIconsCarScreenOK(void);
void SCPAppIconsRetry(void);
#ifdef __cplusplus
}
#endif
