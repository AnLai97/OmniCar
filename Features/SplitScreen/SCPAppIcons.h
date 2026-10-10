#import "common.h"

// Icon app iPhone tren man chinh CarPlay (nhu CarBridge / carplay-cast): thu vien app cua DashBoard duoc thay bang
// mot thu vien gom moi app (FBSApplicationLibrary + DBApplicationInfo), roi app iPhone nguoi dung chon trong
// App Bridge > App tren man xe (AB_KEY_APPS) duoc gan mot CarPlay declaration gia (CRCarPlayAppDeclaration) de
// DashBoard ve icon. Cham icon: hook _launchAppWithInfo: (CarPlay.xm) / launchInfoForApplication: (AppIcons.xm)
// dua app sang App Bridge thay vi mo scene CarPlay.
#ifdef __cplusplus
extern "C" {
#endif
// Chan doan 1 lan: lop / method / ivar cua thu vien app, app info, declaration, icon tren man chinh (de chen icon dung API)
void SCPDumpAppLibraryOnce(void);
// App iPhone da duoc chen vao thu vien app CarPlay (bundle id) -> khong coi la app CarPlay that
BOOL SCPIsInjectedPhoneApp(NSString *bid);
// Bundle id da chon trong App Bridge (AB_KEY_APPS), doc lai prefs moi lan goi; rong khi App Bridge tat
NSSet<NSString *> *SCPChosenPhoneApps(void);
// Thu vien app moi gom moi app (tru app "hidden") + app he thong cua CarPlay, da gan declaration cho app iPhone
// da chon. nil = khong tao duoc (thieu lop) -> dung thu vien goc
id SCPNewLibraryWithPhoneApps(void);
// Gan declaration gia cho app iPhone da chon trong thu vien nay (DashBoard goi lai khi cai / go app)
void SCPAddPhoneAppDeclarations(id library);
// DBDashboardHomeViewController dang hien (de dua thu vien moi vao khi danh sach app doi)
void SCPSetHomeViewController(id vc);
// Danh sach app da chon vua doi (prefschanged): tao thu vien moi va ve lai man chinh (co debounce)
void SCPRefreshAppIconsSoon(void);
// Cau dao chong crash-loop (xem SCPAppIcons.mm): hoi truoc khi chen; bao man xe da hien; cho phep thu lai
BOOL SCPAppIconsBeginInjection(void);
void SCPAppIconsCarScreenOK(void);
void SCPAppIconsRetry(void);
#ifdef __cplusplus
}
#endif
