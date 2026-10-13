#import <Foundation/Foundation.h>

// Reads the Speed Bubble settings (SB_KEY_* in SpeedBubble.h, OmniCar prefs domain); every read re-syncs.
@interface SPPPrefs : NSObject
+ (BOOL)enabled;          // bat bong bong
+ (NSInteger)style;       // 0..17, xem danh sach kieu trong SPPBubble.mm
+ (BOOL)showAppIcon;      // hien icon app dang cap toc do tren bong bong
+ (int)source;            // app duy nhat cap toc do (chi so trong SPP_NAV_APPS)
+ (BOOL)appEnabled:(int)appIndex;   // = appIndex == source
+ (BOOL)useMph;           // hien mph thay km/h (SB_KEY_UNIT; tu dong: vung khong dung he met hoac US/GB/LR/MM)
+ (BOOL)usSign;           // bien gioi han kieu My thay Vienna (SB_KEY_SIGN; tu dong: vung US/PR/LR/MM)
+ (double)sizePercentForCar:(BOOL)car;               // kich thuoc bong bong (%), rieng iPhone / CarPlay; 100 = mac dinh
+ (void)setSizePercent:(double)pct forCar:(BOOL)car;  // ghi tu SpringBoard (chum 2 ngon / dat lai)
@end
