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
// Canh anh icon (pt) khi da chon cot / hang: theo o luoi deu x Co icon; chua co o / Tu dong: origSide x Co icon
CGFloat SCPHomeIconSide(CGFloat origSide);
// So cot / hang cua luoi man chinh (0 = Tu dong, nhu CarPlay) cho hook SBIconListGridLayoutConfiguration
NSInteger SCPHomeGridColumns(void);
NSInteger SCPHomeGridRows(void);
// Sau khi CarPlay xep icon trong mot *IconListView: chia vung thanh cot x hang o deu, dat tam anh icon vao tam o
// (chi khi da chon so cot / hang; Tu dong x Tu dong = de CarPlay)
void SCPHomeLayoutGrid(UIView *list);
// Hien ten app duoi icon (hook -[SBIconView setLabelHidden:])
BOOL SCPHomeShowNames(void);
// Cai dat doi (prefschanged): doc lai, ap lai
void SCPHomeRefresh(void);
#if OMC_AUTOTEST
// Bo test Man chinh CarPlay (SCPAutoTest.mm): app tren luoi (nil = man chinh khong hien), so icon trang dau, so nhan ten dang hien
NSArray<NSString *> *SCPHomeVisibleBundles(void);
NSInteger SCPHomeFirstPageIconCount(void);
NSInteger SCPHomeVisibleLabelCount(void);
// Luoi deu tren trang dang hien: nil = dung (tam anh dung tam o, canh = SCPHomeIconSide, khong tran / chong khi !allowOverlap);
// wantCols / wantRows 0 = lay theo luoi that. outCenters / outSide: tam anh va canh do duoc
NSString *SCPHomeGridCheck(NSInteger wantCols, NSInteger wantRows, BOOL allowOverlap, NSArray<NSValue *> **outCenters, CGFloat *outSide);
#endif
// Man chinh vua hien / bi app toan man che (viewDidAppear / viewDidDisappear): hinh nen dong chay / dung
void SCPHomeSetVisible(BOOL visible);
#ifdef __cplusplus
}
#endif
