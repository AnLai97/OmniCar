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
- (void)hide;
- (void)resetLayout;                                // Cai dat > Dat lai vi tri & kich thuoc
- (void)runDemo;                                    // Cai dat > Xem thu: toc do gia 10 giay
@end
