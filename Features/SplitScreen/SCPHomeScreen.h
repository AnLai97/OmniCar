#import "common.h"

// Hinh nen + co icon tren man chinh GOC cua CarPlay (HS_KEY_* trong AppBridge.h, xem truoc: tools/preview/index.html#home).
// OmniCar khong ve luoi / dock rieng (an app CarPlay: SCPIconHiddenOnCar, SCPAppIcons.mm): hinh nen la mot view chen xuong duoi luoi icon cua
// DBDashboardHomeViewController; co icon / so cot / so hang qua hook SBIconListGridLayoutConfiguration, ten app qua
// -[SBIconView setLabelHidden:] (AppIcons.xm).
// Khong chon hinh nen + co 100 % = CarPlay nguyen ven.
#ifdef __cplusplus
extern "C" {
#endif
// DBDashboardHomeViewController vua layout: dat / bo hinh nen, xep lai icon neu co vua doi
void SCPHomeApply(UIViewController *homeVC);
// He so co icon (1 = nhu CarPlay) cho hook iconImageInfo
CGFloat SCPHomeIconScale(void);
// So cot / hang cua luoi man chinh (0 = Tu dong, nhu CarPlay) cho hook SBIconListGridLayoutConfiguration
NSInteger SCPHomeGridColumns(void);
NSInteger SCPHomeGridRows(void);
// Hien ten app duoi icon (hook -[SBIconView setLabelHidden:])
BOOL SCPHomeShowNames(void);
// Cai dat doi (prefschanged): doc lai, ap lai
void SCPHomeRefresh(void);
// Man chinh vua hien / bi app toan man che (viewDidAppear / viewDidDisappear): hinh nen dong chay / dung
void SCPHomeSetVisible(BOOL visible);
#ifdef __cplusplus
}
#endif
