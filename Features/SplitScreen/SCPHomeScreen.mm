#import "SCPHomeScreen.h"
#import "SCPCarSplit.h"
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>

// =====================================================================
//  Hinh nen + co icon tren man chinh GOC cua CarPlay (xem SCPHomeScreen.h). OmniCar khong ve luoi / dock rieng, khong an
//  gi cua CarPlay: hinh nen la mot view chen xuong DUOI CUNG cua view man chinh (de len hinh nen CarPlay, duoi luoi icon),
//  co icon la hook SBIconListGridLayoutConfiguration -iconImageInfo (AppIcons.xm) nhan voi SCPHomeIconScale(); doi co thi
//  bao cac *IconListView xep lai icon. Khong chon hinh nen va co 100 % = CarPlay nguyen ven.
//  Lan dau ghi log cay view man chinh de chinh lai neu iOS khac sap xep khac.
//  Da bo (10/2026): luoi icon rieng, an / sap xep app, dock, so cot / hang, ten, ngay / dem, goi icon, thu muc, widget.
// =====================================================================

static NSDictionary *sHS;            // cai dat dang dung (doc lai khi prefschanged)
static __weak UIViewController *sHomeVC;
static BOOL sHomeVisible = YES;      // DBDashboardHomeViewController dang hien (khong bi app toan man che)
static NSInteger sAppliedSize = 100; // co icon (%) lan xep gan nhat

static NSDictionary *SCPHLoad(void)
{
    OMCPrefsSync();
    NSInteger (^num)(NSString *, NSInteger, NSInteger, NSInteger) = ^NSInteger(NSString *k, NSInteger def, NSInteger lo, NSInteger hi) {
        id v = OMCPref(k, nil);
        NSInteger n = [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def;
        return MIN(hi, MAX(lo, n));
    };
    NSInteger style = [OMCPref(HS_KEY_WALLPAPER, @NO) boolValue] ? num(HS_KEY_WALLPAPER_STYLE, 7, 1, 8) : 0;
    return @{
        @"on": @(OMCEnabled()),
        @"size": @(num(HS_KEY_ICON_SIZE, 100, 60, 130)),
        @"style": @(style), @"blur": @(num(HS_KEY_BLUR, 0, 0, 30)), @"dim": @(num(HS_KEY_DIM, 25, 0, 70)),
    };
}

static NSDictionary *SCPHSettings(void)
{
    if (!sHS) sHS = SCPHLoad();
    return sHS;
}

// He so co icon cho hook iconImageInfo (AppIcons.xm): 1 = nhu CarPlay
CGFloat SCPHomeIconScale(void)
{
    NSDictionary *hs = SCPHSettings();
    if (![hs[@"on"] boolValue]) return 1;
    return [hs[@"size"] doubleValue] / 100.0;
}

// ---------------------------------------------------------------------
//  Hinh nen: anh (lam mo bang CIGaussianBlur tren luong phu) hoac video lap khong tieng, phu lop toi.
// ---------------------------------------------------------------------
static UIImage *SCPHBlurred(UIImage *img, CGFloat radius)
{
    if (radius <= 0 || !img.CGImage) return img;
    CIImage *in = [CIImage imageWithCGImage:img.CGImage];
    CIFilter *f = [CIFilter filterWithName:@"CIGaussianBlur"];
    [f setValue:[in imageByClampingToExtent] forKey:kCIInputImageKey];
    [f setValue:@(radius) forKey:kCIInputRadiusKey];
    CIImage *outImg = [f.outputImage imageByCroppingToRect:in.extent];
    CGImageRef cg = outImg ? [[CIContext contextWithOptions:nil] createCGImage:outImg fromRect:in.extent] : NULL;
    if (!cg) return img;
    UIImage *r = [UIImage imageWithCGImage:cg scale:img.scale orientation:img.imageOrientation];
    CGImageRelease(cg);
    return r;
}

// Hinh nen dang dung: @{path, video} hoac nil = de nguyen hinh nen CarPlay
static NSDictionary *SCPHWallSource(NSDictionary *hs)
{
    NSInteger style = [hs[@"style"] integerValue];
    if (style <= 0) return nil;
    NSString *path = style == 8 ? HS_VIDEO_PATH : HS_WALLPAPER_PATH;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return @{@"path": path, @"video": @(style == 8)};
}

// Video chi chay khi man chinh dang hien, khong chia man, may khong nong va khong o che do nhe
static BOOL SCPHVideoMayPlay(UIView *v)
{
    if (!v.window || !sHomeVisible) return NO;
    if ([NSProcessInfo processInfo].thermalState >= NSProcessInfoThermalStateSerious) return NO;
    if (OMCLiteActive()) return NO;
    BOOL split = NO;
    @try { split = [SCPCarSplit shared].active; } @catch (NSException *e) {}
    return !split;
}

@interface SCPHomeWallView : UIView
@property (nonatomic, strong) UIImageView *image;
@property (nonatomic, strong) UIView *dim;
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, strong) AVPlayerLayer *videoLayer;
@property (nonatomic, copy) NSString *loadedKey;
@end
@implementation SCPHomeWallView
- (instancetype)initWithFrame:(CGRect)f
{
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        _image = [[UIImageView alloc] initWithFrame:self.bounds];
        _image.contentMode = UIViewContentModeScaleAspectFill;
        _image.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_image];
        _dim = [[UIView alloc] initWithFrame:self.bounds];
        _dim.backgroundColor = [UIColor blackColor];
        _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_dim];
    }
    return self;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.videoLayer.frame = self.bounds;
    [CATransaction commit];
}
- (void)stopVideo
{
    [self.player pause];
    [self.looper disableLooping];
    [self.videoLayer removeFromSuperlayer];
    self.player = nil; self.looper = nil; self.videoLayer = nil;
}
- (void)startVideo:(NSString *)path
{
    [self stopVideo];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    self.player = [AVQueuePlayer queuePlayerWithItems:@[]];
    self.player.muted = YES;
    self.player.preventsDisplaySleepDuringVideoPlayback = NO;
    self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    self.videoLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.videoLayer.frame = self.bounds;
    [self.layer insertSublayer:self.videoLayer above:self.image.layer];
    self.image.image = nil;
    SCPLog("HomeScreen: hinh nen dong %@", path.lastPathComponent);
    [self updatePlayback];
}
- (void)updatePlayback
{
    if (!self.player) return;
    BOOL may = SCPHVideoMayPlay(self);
    if (may == (self.player.rate > 0)) return;
    if (may) [self.player play]; else [self.player pause];
    SCPLog("HomeScreen: hinh nen dong %@", may ? @"chay" : @"dung (an / chia man / may nong / che do nhe)");
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self updatePlayback]; }
- (void)applySettings:(NSDictionary *)hs source:(NSDictionary *)src
{
    self.dim.alpha = [hs[@"dim"] doubleValue] / 100.0;
    NSString *path = src[@"path"];
    BOOL video = [src[@"video"] boolValue];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%d", path, attrs.fileModificationDate, hs[@"blur"], video];
    if ([key isEqualToString:self.loadedKey]) { [self updatePlayback]; return; }
    self.loadedKey = key;
    if (video) { [self startVideo:path]; return; }
    [self stopVideo];
    CGFloat blur = [hs[@"blur"] doubleValue];
    __weak SCPHomeWallView *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        UIImage *done = nil;
        @try { done = SCPHBlurred(img, blur); } @catch (NSException *e) { done = img; }
        dispatch_async(dispatch_get_main_queue(), ^{
            SCPHomeWallView *me = weakSelf;
            if (!me || ![me.loadedKey isEqualToString:key]) return;
            [UIView transitionWithView:me.image duration:0.4 options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ me.image.image = done; } completion:nil];
            if (!done) SCPLog("HomeScreen: khong doc duoc hinh nen %@", path);
        });
    });
}
@end

// ---------------------------------------------------------------------
//  Man chinh
// ---------------------------------------------------------------------
static const NSInteger kSCPHWallTag = 0x4857;   // "HW"

static void SCPHDumpTree(UIView *v, UIView *root, int d, NSMutableString *s)
{
    if (!v || d > 8 || s.length > 6000) return;
    [s appendFormat:@"%@%@ %@%@\n", [@"" stringByPaddingToLength:d * 2 withString:@" " startingAtIndex:0], NSStringFromClass([v class]),
        NSStringFromCGRect([root convertRect:v.bounds fromView:v]), v.hidden ? @" hidden" : @""];
    for (UIView *c in v.subviews) SCPHDumpTree(c, root, d + 1, s);
}

static void SCPHLogTreeOnce(UIView *root)
{
    static BOOL done;
    if (done) return;
    done = YES;
    NSMutableString *s = [NSMutableString string];
    SCPHDumpTree(root, root, 0, s);
    SCPLog("HomeScreen: DIAG cay man chinh CarPlay:\n%@", s);
}

// Cac *IconListView trong man chinh (luoi icon cua CarPlay)
static void SCPHCollectLists(UIView *v, NSMutableArray *out, int depth)
{
    if (!v || depth > 16) return;
    if ([NSStringFromClass([v class]) hasSuffix:@"IconListView"]) { [out addObject:v]; return; }
    for (UIView *c in v.subviews) SCPHCollectLists(c, out, depth + 1);
}

static void SCPHSetNeedsLayoutDeep(UIView *v, int depth)
{
    if (!v || depth > 6) return;
    [v setNeedsLayout];
    for (UIView *c in v.subviews) SCPHSetNeedsLayoutDeep(c, depth + 1);
}

// Co icon vua doi: bao CarPlay xep lai icon (layoutIconsNow cua SBIconListView, khong co thi setNeedsLayout)
static void SCPHRelayoutIcons(UIView *root, NSInteger size)
{
    NSMutableArray<UIView *> *lists = [NSMutableArray array];
    SCPHCollectLists(root, lists, 0);
    for (UIView *l in lists) {
        SCPHSetNeedsLayoutDeep(l, 0);
        @try { objcCall(l, @"layoutIconsNow"); } @catch (NSException *e) {}
    }
    SCPLog("HomeScreen: co icon %ld%% -> xep lai %lu luoi icon (%@)", (long)size, (unsigned long)lists.count,
           lists.count ? NSStringFromClass([lists.firstObject class]) : @"khong thay *IconListView");
}

// Moi 30 s khi dang ve hinh nen dong: bat / dung video theo dieu kien (may nong, che do nhe)
static void SCPHStartTicker(void)
{
    static NSTimer *timer;
    if (timer) return;
    timer = [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *t) {
        UIViewController *home = sHomeVC;
        if (home.isViewLoaded && [SCPHSettings()[@"style"] integerValue] == 8) SCPHomeApply(home);
    }];
}

void SCPHomeApply(UIViewController *homeVC)
{
    if (!homeVC.isViewLoaded) return;
    sHomeVC = homeVC;
    UIView *root = homeVC.view;
    NSDictionary *hs = SCPHSettings();
    SCPHomeWallView *wall = (SCPHomeWallView *)[root viewWithTag:kSCPHWallTag];
    NSDictionary *src = [hs[@"on"] boolValue] ? SCPHWallSource(hs) : nil;
    // Hinh nen: lop duoi cung cua man chinh, duoi luoi icon cua CarPlay (khong chon: de nguyen hinh nen CarPlay)
    if (src) {
        SCPHLogTreeOnce(root);
        if (!wall) {
            wall = [[SCPHomeWallView alloc] initWithFrame:root.bounds];
            wall.tag = kSCPHWallTag;
            wall.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [root insertSubview:wall atIndex:0];
            SCPLog("HomeScreen: hinh nen rieng %@ duoi luoi icon CarPlay", [src[@"video"] boolValue] ? @"(video)" : @"(anh)");
        }
        wall.frame = root.bounds;
        if (root.subviews.firstObject != wall) [root sendSubviewToBack:wall];
        if ([src[@"video"] boolValue]) SCPHStartTicker();
        [wall applySettings:hs source:src];
    } else if (wall) {
        SCPLog("HomeScreen: bo hinh nen rieng -> hinh nen CarPlay");
        [wall stopVideo];
        [wall removeFromSuperview];
    }
    // Co icon: hook iconImageInfo doc SCPHomeIconScale() moi lan xep; doi co thi ep xep lai
    NSInteger size = [hs[@"on"] boolValue] ? [hs[@"size"] integerValue] : 100;
    if (size != sAppliedSize) {
        sAppliedSize = size;
        SCPHLogTreeOnce(root);
        SCPHRelayoutIcons(root, size);
    }
}

void SCPHomeSetVisible(BOOL visible)
{
    if (sHomeVisible == visible) return;
    sHomeVisible = visible;
    UIViewController *home = sHomeVC;
    SCPHomeWallView *wall = home.isViewLoaded ? (SCPHomeWallView *)[home.view viewWithTag:kSCPHWallTag] : nil;
    [wall updatePlayback];
}

void SCPHomeRefresh(void)
{
    sHS = SCPHLoad();
    UIViewController *home = sHomeVC;
    if (home.isViewLoaded) { SCPHomeApply(home); [home.view setNeedsLayout]; }
}
