#import "common.h"

// Canh bao qua toc do (Cai dat > Bong bong toc do > Canh bao qua toc do), chi tren man xe:
// toc do > gioi han + nguong (SB_KEY_WARN_OVER) -> vien do phat sang nhay quanh man CarPlay (cua so rieng tren man xe,
// cham xuyen qua) + 1 tieng ngan moi lan vuot (SB_KEY_WARN_MODE = 2). Keu lai chi sau khi xuong duoi gioi han
// lien tuc SPP_WARN_REARM giay. Nguon khong co gioi han (GPS iPhone) / so cu -> khong canh bao.
// SPPBubble goi updateSpeed:limit: moi ban tin + moi giay (so cu -> -1).
@interface SPPOverspeed : NSObject
+ (instancetype)shared;
- (void)updateSpeed:(int)speed limit:(int)limit;   // km/h goc; < 0 = khong co / so cu
- (void)reloadPrefs;                               // Cai dat vua doi (SB_DARWIN_PREFS)
- (void)carChanged;                                // xe ket noi / ngat: tao lai / bo cua so
@end
