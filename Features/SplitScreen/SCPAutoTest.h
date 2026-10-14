#import "common.h"

// =====================================================================
//  SCPAutoTest - bo test tu dong cua Chia man hinh ("splitScreen") va App Bridge ("appBridge"), chi khi
//  OMC_AUTOTEST = 1 (Core/OMCTest.h). Chay trong process CarPlay: goi dung cac ham ma nut bam tren xe goi
//  (bo cuc, ti le, doi cho, cua so noi, toan man, lenh URL / Siri, App Bridge ...), cho, roi kiem trang thai split.
// =====================================================================

#if OMC_AUTOTEST
#ifdef __cplusplus
extern "C" {
#endif
void SCPAutoTestInstall(void);     // %ctor CarPlay: dang ky 2 bo test
#ifdef __cplusplus
}
#endif
#endif
