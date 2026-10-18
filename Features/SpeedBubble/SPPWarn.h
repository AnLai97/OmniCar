#import "common.h"

// Canh bao qua toc do (Cai dat > Bong bong toc do > Canh bao qua toc do), chi tren man xe:
// toc do > gioi han + nguong (SB_KEY_WARN_OVER) -> canh bao theo SB_KEY_WARN_FX (vien nhay / phat sang / nhay ca man tren
// cua so rieng tren man xe, cham xuyen qua; hoac bong bong phong to + rung) va / hoac 1 am bao / 1 cau noi moi lan vuot
// (SPPSound.h; SB_KEY_WARN_MODE: 1 canh bao, 2 am thanh, 3 ca hai). Keu lai chi sau khi xuong duoi gioi han
// lien tuc SPP_WARN_REARM giay. Khong co gioi han / so cu -> khong canh bao.
// SPPBubble goi updateSpeed:limit: moi ban tin + moi giay (so cu -> -1).
@interface SPPOverspeed : NSObject
+ (instancetype)shared;
- (void)updateSpeed:(int)speed limit:(int)limit;   // km/h goc; < 0 = khong co / so cu
- (void)reloadPrefs;                               // Cai dat vua doi (SB_DARWIN_PREFS)
- (void)carChanged;                                // xe ket noi / ngat: tao lai / bo cua so
@end
