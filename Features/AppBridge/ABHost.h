#import <UIKit/UIKit.h>

// SpringBoard-side host: one window on the car display, one box per hosted iPhone app (scene created
// with SBAppViewController, carplay-cast style). Driven by the AB_NOTIF_* messages (AppBridge.h).
@interface ABHost : NSObject
+ (instancetype)shared;
- (void)openApp:(NSString *)bid frame:(CGRect)frame;                                    // frame in car-screen points
- (void)setFrame:(CGRect)frame forApp:(NSString *)bid live:(BOOL)live handle:(BOOL)handle passInsets:(UIEdgeInsets)pass;
- (void)setPassInsets:(UIEdgeInsets)pass forApp:(NSString *)bid;   // dai sat mep cho cham xuyen xuong CarPlay
// Thanh nut cua o ve de len app (SpringBoard ve, CarPlay nhan tap qua AB_NOTIF_BAR_ACTION); pop 1 = nut "noi", 2 = "ghim";
// single = o dang chay 1 man hinh (nut "Chay 1 man hinh" doi thanh "Chia man hinh")
- (void)setBarVisible:(BOOL)visible pop:(int)pop dim:(BOOL)dim single:(BOOL)single forApp:(NSString *)bid;
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
- (UIWindow *)carWindow;
- (void)startDriveMonitor;   // SpringBoard start: driving mode follows AB_DARWIN_SPEED_NOW   // the host window on the car screen (pass-through, kept for the whole connection), nil if no car
@end
