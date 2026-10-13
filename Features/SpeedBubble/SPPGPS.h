#import "common.h"

// Nguon toc do "GPS iPhone" (SB_SOURCE_GPS): CLLocationManager ngay trong SpringBoard, chi chay khi bat bong bong,
// nguon dang chon la GPS va xe dang ket noi (co man CarPlay). Toc do (m/s) -> km/h, lam muot, khong co gioi han;
// dua vao cung duong voi app dan duong ([SPPBubble updateSpeed:limit:appForeground:app:]) nen moi kieu deu chay.
@interface SPPPhoneGPS : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL running;   // dang nhan vi tri
- (void)update;                                 // xet lai dieu kien bat / tat (Cai dat doi, xe ket noi / ngat)
@end
