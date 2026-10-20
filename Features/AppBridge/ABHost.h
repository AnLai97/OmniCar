#import <UIKit/UIKit.h>

// SpringBoard-side host: one window on the car display, one box per hosted iPhone app (scene created
// with SBAppViewController, carplay-cast style). Driven by the AB_NOTIF_* messages (AppBridge.h).
// SpringBoard.xm: va ham BKSDisplayServicesSetScreenBlanked lan dau host app (khong va luc khoi dong, co cau dao chong treo may)
#ifdef __cplusplus
extern "C" {
#endif
void ABInstallScreenBlankHook(void);
#ifdef __cplusplus
}
#endif

@interface ABHost : NSObject
+ (instancetype)shared;
- (void)openApp:(NSString *)bid frame:(CGRect)frame;                                    // frame in car-screen points
- (void)setFrame:(CGRect)frame forApp:(NSString *)bid live:(BOOL)live handle:(BOOL)handle passInsets:(UIEdgeInsets)pass;
- (void)setPassInsets:(UIEdgeInsets)pass forApp:(NSString *)bid;   // dai sat mep cho cham xuyen xuong CarPlay
// Thanh nut cua o ve de len app (SpringBoard ve, CarPlay nhan tap qua AB_NOTIF_BAR_ACTION); pop 1 = nut "noi", 2 = "ghim";
// single = o dang chay 1 man hinh (nut "Chay 1 man hinh" doi thanh "Chia man hinh")
- (void)setBarVisible:(BOOL)visible pop:(int)pop dim:(BOOL)dim single:(BOOL)single forApp:(NSString *)bid;
// AB_NOTIF_SHIELD: co bang nao mo tren man xe -> lop chan mong (co ve, de backboardd dua cham ve SpringBoard) phu kin MOI o
// (ke ca app toan man, ke ca o mo sau do): cham vao app = cham cho khac -> AB_NOTIF_BAR_DISMISS, cham do khong toi app
- (void)setShieldAll:(BOOL)on;
- (void)outsideTouched;   // lop chan nhan cham: an moi thanh nut + bo moi lop chan ngay (ABShieldView goi)
// Cua so noi cua CarPlay (ve duoi cua so host) nam tren o nay: khoet lo dung khung do (toa do man xe, CGRectZero = khong)
// de cua so noi lo ra va cham duoc (FRAME / OPEN "ox/oy/ow/oh")
- (void)setHole:(CGRect)hole forApp:(NSString *)bid;
- (void)setFront:(BOOL)front forApp:(NSString *)bid;   // cua so noi: len tren cac o app iPhone khac
@property (nonatomic) CGRect carAppArea;   // vung app cua man xe (khong tinh dock), CarPlay gui kem moi khung o; ban phim xe trai theo day
- (void)setCornerRadius:(CGFloat)radius corners:(CACornerMask)corners forApp:(NSString *)bid;   // bo goc nhu o CarPlay
- (void)setHandleOffset:(CGFloat)dx forApp:(NSString *)bid;   // thanh "•••" lech ngang (o duoi vach ngang: tranh cham tron cua vach)
- (void)setKnobs:(NSArray *)knobs;   // cham tron cua vach chia (AB_NOTIF_KNOBS): ve len tren cac o, nhan cham roi chuyen sang CarPlay
- (void)closeApp:(NSString *)bid terminate:(BOOL)terminate;
- (void)closeAll;
- (void)closeAllExcept:(NSString *)keep;   // giu lai app dang chuyen sang toan man (khong nhay ve Home)
- (void)carDisconnected;                 // car screen gone: drop every box without touching the apps
- (BOOL)hostsApp:(NSString *)bid;        // SpringBoard hooks: keep this app's scene foreground / alive under lock
// AB_DARWIN_APP_ORIENT: the hosted app (found by ABBundleHash) asks for another orientation (YouTube full-screen video)
- (void)appWithHash:(unsigned long long)hash changedOrientation:(int)code supportedMask:(NSUInteger)mask;
- (NSUInteger)count;
- (NSString *)bundleForHash:(unsigned long long)hash;   // hosted app with this ABBundleHash, nil if none
- (CGRect)frameOfApp:(NSString *)bid;                    // its box on the car screen (points), CGRectNull if none
- (UIWindow *)carWindow;   // the host window on the car screen (pass-through, kept for the whole connection), nil if no car
@end
