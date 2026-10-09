#import "common.h"

// Icon app iPhone tren man chinh CarPlay (nhu CarBridge): chen app iPhone vao thu vien app cua CarPlay de DashBoard ve
// icon; cham icon thi di qua App Bridge (hook _launchAppWithInfo: trong CarPlay.xm) thay vi mo scene CarPlay.
#ifdef __cplusplus
extern "C" {
#endif
// Chan doan 1 lan: lop / method / ivar cua thu vien app, app info, declaration, icon tren man chinh (de chen icon dung API)
void SCPDumpAppLibraryOnce(void);
// App iPhone da duoc chen vao thu vien app CarPlay (bundle id) -> khong coi la app CarPlay that
BOOL SCPIsInjectedPhoneApp(NSString *bid);
#ifdef __cplusplus
}
#endif
