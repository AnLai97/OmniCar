#import <UIKit/UIKit.h>

// SpringBoard-side host: one window on the car display, one box per hosted iPhone app (scene created
// with SBAppViewController, carplay-cast style). Driven by the AB_NOTIF_* messages (AppBridge.h).
@interface ABHost : NSObject
+ (instancetype)shared;
- (void)openApp:(NSString *)bid frame:(CGRect)frame;                                    // frame in car-screen points
- (void)setFrame:(CGRect)frame forApp:(NSString *)bid live:(BOOL)live handle:(BOOL)handle passInsets:(UIEdgeInsets)pass;
- (void)setPassInsets:(UIEdgeInsets)pass forApp:(NSString *)bid;   // dai sat mep cho cham xuyen xuong CarPlay
- (void)setClipTop:(CGFloat)top forApp:(NSString *)bid;             // che `top` pt tren cung cua o (thanh nut ben CarPlay lo ra), app khong bi day
- (void)closeApp:(NSString *)bid terminate:(BOOL)terminate;
- (void)closeAll;
- (void)carDisconnected;                 // car screen gone: drop every box without touching the apps
- (BOOL)hostsApp:(NSString *)bid;        // SpringBoard hooks: keep this app's scene foreground / alive under lock
// AB_DARWIN_APP_ORIENT: the hosted app (found by ABBundleHash) asks for another orientation (YouTube full-screen video)
- (void)appWithHash:(unsigned long long)hash changedOrientation:(int)code supportedMask:(NSUInteger)mask;
- (NSUInteger)count;
@end
