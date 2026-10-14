#import <Foundation/Foundation.h>

// Reads the Speed Bubble settings (SB_KEY_* in SpeedBubble.h, OmniCar prefs domain); every read re-syncs.
@interface SPPPrefs : NSObject
+ (BOOL)enabled;          // bat bong bong
+ (NSInteger)style;       // 0..17, xem danh sach kieu trong SPPBubble.mm
+ (BOOL)showAppIcon;      // hien icon app dang cap toc do tren bong bong
+ (int)source;            // nguon duy nhat cap toc do (chi so trong SPP_NAV_APPS)
+ (BOOL)appEnabled:(int)appIndex;   // = appIndex == source
+ (BOOL)useMph;           // hien mph thay km/h (SB_KEY_UNIT; tu dong: vung khong dung he met hoac US/GB/LR/MM)
+ (BOOL)usSign;           // bien gioi han kieu My thay Vienna (SB_KEY_SIGN; tu dong: vung US/PR/LR/MM)
+ (double)sizePercentForCar:(BOOL)car;               // kich thuoc bong bong (%), rieng iPhone / CarPlay; 100 = mac dinh
+ (void)setSizePercent:(double)pct forCar:(BOOL)car;  // ghi tu SpringBoard (chum 2 ngon / dat lai)
+ (NSInteger)warnMode;    // canh bao qua toc do: 0 tat, 1 canh bao (vien), 2 am thanh (vien + tieng) (SB_KEY_WARN_MODE)
+ (double)warnMarginKmh;  // nguong so voi gioi han (-10..10, am = truoc khi cham), doi ra km/h (Cai dat ghi theo don vi dang hien)
@end
