#import "common.h"

// Man chinh CarPlay cua OmniCar (ROADMAP-DEV Muc 2 "Man chinh CarPlay", HS_KEY_* trong AppBridge.h, xem truoc:
// tools/preview/home.html). Bat thi OmniCar ve luoi icon + icon dock cua minh len tren cua CarPlay: luoi goc chi bi an
// (hidden), khong doi model / thu tu cua CarPlay, tat la tra lai nguyen ven. Doc thu tu app tu model cua cac
// *IconListView (cach Split Screen da dung), mo app qua -[DBDashboard _launchAppWithInfo:forURL:] (app iPhone -> App Bridge).
#ifdef __cplusplus
extern "C" {
#endif
// DBDashboardHomeViewController vua layout: ve / cap nhat luoi va hinh nen, an luoi goc
void SCPHomeApply(UIViewController *homeVC);
// DBDashboardRootViewController vua layout: dock tuy chinh
void SCPHomeApplyDock(UIViewController *rootVC);
// Cai dat doi (prefschanged): doc lai, ve lai
void SCPHomeRefresh(void);
#ifdef __cplusplus
}
#endif
