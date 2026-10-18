#import <Foundation/Foundation.h>

// Reads the Speed Bubble settings (SB_KEY_* in SpeedBubble.h, OmniCar prefs domain); every read re-syncs.
@interface SPPPrefs : NSObject
+ (BOOL)enabled;          // bat bong bong
+ (NSInteger)style;       // 0..17, xem danh sach kieu trong SPPBubble.mm
+ (BOOL)showAppIcon;      // hien icon app dang cap toc do tren bong bong
+ (int)source;            // nguon duy nhat cap toc do (chi so trong SPP_NAV_APPS)
+ (BOOL)appEnabled:(int)appIndex;   // = appIndex == source
+ (double)sizePercentForCar:(BOOL)car;               // kich thuoc bong bong (%), rieng iPhone / CarPlay; 100 = mac dinh
+ (void)setSizePercent:(double)pct forCar:(BOOL)car;  // ghi tu SpringBoard (chum 2 ngon / dat lai)
+ (NSInteger)warnMode;    // canh bao qua toc do: 0 tat, 1 canh bao (vien), 2 am thanh (tieng), 3 vien + tieng (SB_KEY_WARN_MODE)
+ (NSInteger)warnFx;      // kieu canh bao (SB_KEY_WARN_FX): 0 vien nhay, 1 phat sang, 2 nhay man, 3 bong bong rung
+ (BOOL)warnVoice;        // am thanh la giong noi (SB_KEY_WARN_SOUND = 1), khong thi am bao
+ (NSInteger)warnTone;    // am bao 0..SB_TONE_COUNT-1
+ (NSInteger)warnVoiceLine;     // cau 0..SB_VOICE_COUNT-1 hoac SB_VOICE_CUSTOM
+ (NSString *)warnVoiceText;    // cau tu nhap
+ (NSInteger)color;       // mau nen bong bong (SB_KEY_COLOR), 0 = theo kieu
+ (double)warnMarginKmh;  // nguong so voi gioi han (-10..10, am = truoc khi cham), km/h
@end
