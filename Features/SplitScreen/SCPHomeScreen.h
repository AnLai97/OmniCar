#import "common.h"

// Hinh nen + co icon tren man chinh GOC cua CarPlay (HS_KEY_* trong AppBridge.h, xem truoc: tools/preview/home.html).
// OmniCar khong ve luoi / dock rieng va khong an gi cua CarPlay: hinh nen la mot view chen xuong duoi luoi icon cua
// DBDashboardHomeViewController; co icon qua hook SBIconListGridLayoutConfiguration -iconImageInfo (AppIcons.xm).
// Khong chon hinh nen + co 100 % = CarPlay nguyen ven.
#ifdef __cplusplus
extern "C" {
#endif
// DBDashboardHomeViewController vua layout: dat / bo hinh nen, xep lai icon neu co vua doi
void SCPHomeApply(UIViewController *homeVC);
// He so co icon (1 = nhu CarPlay) cho hook iconImageInfo
CGFloat SCPHomeIconScale(void);
// Cai dat doi (prefschanged): doc lai, ap lai
void SCPHomeRefresh(void);
// Man chinh vua hien / bi app toan man che (viewDidAppear / viewDidDisappear): hinh nen dong chay / dung
void SCPHomeSetVisible(BOOL visible);
#ifdef __cplusplus
}
#endif
