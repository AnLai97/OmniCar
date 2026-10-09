#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Reads the Split Screen settings (SPL_KEY_* in SplitScreen.h, OmniCar prefs domain); every read
// re-syncs so changes in Settings apply at once, no respring.
@interface SCPPrefs : NSObject
+ (BOOL)enabled;                 // master switch AND splitScreenEnabled
+ (BOOL)english;                 // text on the car screen follows Settings > OmniCar > language (vi / en)
+ (NSInteger)tipCount;           // so lan da hien meo thao tac tren xe (toi da 3)
+ (void)setTipCount:(NSInteger)n;
+ (NSString *)lastLeftApp;       // cap app dung lan cuoi tren xe (tu mo lai khi cam xe)
+ (NSString *)lastRightApp;
+ (BOOL)autoLaunch;
+ (BOOL)showRecent;              // bang nut Split Screen: hien muc Gan day (mac dinh bat)
+ (BOOL)showFavorites;           // bang nut Split Screen: hien muc Yeu thich (mac dinh bat)
+ (NSInteger)paneOrientation;    // 1 = portrait, 3 = landscape
+ (CGFloat)splitRatio;           // ti le be rong ngan trai (0.2 - 0.8)
+ (NSInteger)splitDirection;     // 0 trai/phai, 1 tren/duoi
+ (NSArray<NSString *> *)carPlayApps;   // app CarPlay hien duoc (CarPlay process ghi lai)
+ (void)setCarPlayApps:(NSArray<NSString *> *)ids;
+ (void)setCarBridgeApps:(NSArray<NSString *> *)ids;   // app CarBridge dang bat (CarPlay process ghi lai)

// Bo cuc yeu thich 1..3: @{ @"name", @"layout": 2|3|13|31, @"left", @"right", @"third" } (nil neu chua dat app nao)
+ (NSDictionary *)favorite:(NSInteger)index;

// Cach chia dung gan day (toi da 3, moi nhat truoc): @{ @"layout": 2|3|13|31, @"apps": @[bundle, ...] }
+ (NSArray<NSDictionary *> *)recentLayouts;
+ (void)addRecentLayout:(NSInteger)layout apps:(NSArray<NSString *> *)apps;

// Ti le rieng cho tung cap app
+ (CGFloat)ratioForPairLeft:(NSString *)left right:(NSString *)right;   // 0 neu chua co
+ (void)setRatio:(CGFloat)ratio forPairLeft:(NSString *)left right:(NSString *)right;

+ (void)setSplitRatio:(CGFloat)r;
+ (void)setLastPairLeft:(NSString *)left right:(NSString *)right;
@end
