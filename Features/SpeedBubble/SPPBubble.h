#import "common.h"

// Bong bong toc do: hien toc do hien tai + gioi han toc do lay tu app dan duong (Vietmap Live / GOFA) khi app do chay NEN
// (co app dan duong dang hien tren iPhone hoac CarPlay thi an). Tren xe: CHI hien tren man CarPlay; khong co xe: tren iPhone.
// Du lieu do hook trong tien trinh app gui qua Darwin notify (SPP_DARWIN_SPEED).
@interface SPPBubble : NSObject
+ (instancetype)shared;
- (void)updateSpeed:(int)speed limit:(int)limit;   // speed/limit < 0 = khong co
- (void)updateSpeed:(int)speed limit:(int)limit appForeground:(BOOL)fg;   // fg: app dang hien -> an
- (void)updateSpeed:(int)speed limit:(int)limit appForeground:(BOOL)fg app:(int)app;   // app: chi so SPP_NAV_APPS
- (void)refresh;                                    // tinh lai hien/an
- (void)setCarBusy:(BOOL)busy;                      // Split Screen dang chiem man xe (OMC_DARWIN_CAR_BUSY) -> an tren xe
- (void)hide;
- (void)resetLayout;                                // Cai dat > Dat lai vi tri & kich thuoc
- (void)runDemo;                                    // Cai dat > Xem thu: toc do gia 10 giay
- (void)sourceStopped:(int)app;                     // nguon ngung han: bo so, an bong bong ngay
@end

// Cua so tren man xe, dung chung voi canh bao qua toc do (SPPWarn.mm)
#ifdef __cplusplus
extern "C" {
#endif
id SPPGetCarPlayCADisplay(void);                    // CADisplay man xe, nil = chua ket noi
UIWindow *SPPMakeCarWindow(CGFloat *scale);         // UIRootSceneWindow tren man xe; *scale = diem anh / diem
void SPPMakeWindowPassThrough(UIWindow *w);         // cham vao cho trong cua so -> xuyen xuong CarPlay
#ifdef __cplusplus
}
#endif

#if OMC_AUTOTEST
#ifdef __cplusplus
extern "C" {
#endif
void SPPAutoTestInstall(void);   // SpringBoard: bo test "speedBubble" (Core/OMCTest.h, chi ban dev)
#ifdef __cplusplus
}
#endif
#endif
