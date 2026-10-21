#import "SCPHomeScreen.h"
#import "SCPCarSplit.h"
#import "SCPAppIcons.h"
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>
#if OMC_AUTOTEST
#import "OMCTest.h"
#endif

// =====================================================================
//  Hinh nen + co icon tren man chinh GOC cua CarPlay (xem SCPHomeScreen.h). OmniCar khong ve luoi / dock rieng, khong an
//  gi cua CarPlay: hinh nen la mot view chen xuong DUOI CUNG cua view man chinh (de len hinh nen CarPlay, duoi luoi icon),
//  co icon la hook SBIconListGridLayoutConfiguration -iconImageInfo (AppIcons.xm) nhan voi SCPHomeIconScale(); doi co thi
//  bao cac *IconListView xep lai icon. Khong chon hinh nen va co 100 % = CarPlay nguyen ven.
//  Lan dau ghi log cay view man chinh de chinh lai neu iOS khac sap xep khac.
//  So cot / hang: hook numberOf*Columns / numberOf*Rows cua cung lop (0 = nhu CarPlay); ten app: -[SBIconView setLabelHidden:].
//  Da bo (10/2026): luoi icon rieng, sap xep app, dock, ngay / dem, goi icon, thu muc, widget.
// =====================================================================

static NSDictionary *sHS;            // cai dat dang dung (doc lai khi prefschanged)
static __weak UIViewController *sHomeVC;
static BOOL sHomeVisible = YES;      // DBDashboardHomeViewController dang hien (khong bi app toan man che)
static NSInteger sAppliedSize = 100; // co icon (%) lan xep gan nhat
static NSString *sAppliedGrid = @"0x0"; // so cot x hang lan xep gan nhat (0 = Tu dong)
static BOOL sAppliedNames = YES;     // ten app lan ap gan nhat

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
        @"cols": @([HS_COLS_VALUES containsObject:@(num(HS_KEY_COLS, 0, 0, 8))] ? num(HS_KEY_COLS, 0, 0, 8) : 0),
        @"rows": @([HS_ROWS_VALUES containsObject:@(num(HS_KEY_ROWS, 0, 0, 4))] ? num(HS_KEY_ROWS, 0, 0, 4) : 0),
        @"names": @([OMCPref(HS_KEY_NAMES, @YES) boolValue]),
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

// O luoi deu lan xep gan nhat (SCPHomeLayoutGrid); 0 = chua co / dang Tu dong
static CGSize sGridCell;

// Co anh icon (canh, pt) khi da chon cot / hang: theo o luoi chu khong theo icon goc cua CarPlay, de 100 % vua o tren moi
// ti le man (640 x 240, 512 x 300, 1920 x 720...). Canh = 80 % canh ngan cua o; co ten thi chua 2 lan cao nhan (tam anh
// o tam o, ten treo duoi). Roi nhan Co icon (60-130 %). Chua do duoc o hoac Tu dong: icon goc x Co icon nhu truoc.
CGFloat SCPHomeIconSide(CGFloat origSide)
{
    CGFloat k = SCPHomeIconScale();
    if ((SCPHomeGridColumns() <= 0 && SCPHomeGridRows() <= 0) || sGridCell.width < 1 || sGridCell.height < 1) return origSide * k;
    static const CGFloat kFill = 0.8, kLabelH = 18;
    CGFloat byH = SCPHomeShowNames() ? sGridCell.height - 2 * kLabelH : sGridCell.height * kFill;
    CGFloat side = MIN(sGridCell.width * kFill, byH);
    return MAX(20, floor(side * k));
}

NSInteger SCPHomeGridColumns(void)
{
    NSDictionary *hs = SCPHSettings();
    return [hs[@"on"] boolValue] ? [hs[@"cols"] integerValue] : 0;
}

NSInteger SCPHomeGridRows(void)
{
    NSDictionary *hs = SCPHSettings();
    return [hs[@"on"] boolValue] ? [hs[@"rows"] integerValue] : 0;
}

BOOL SCPHomeShowNames(void)
{
    NSDictionary *hs = SCPHSettings();
    return ![hs[@"on"] boolValue] || [hs[@"names"] boolValue];
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

// Ten app: an / hien nhan cua moi *IconView trong cac luoi icon (icon tao sau di qua hook setLabelHidden:)
static NSUInteger SCPHSetLabels(UIView *v, BOOL hidden, int depth)
{
    if (!v || depth > 8) return 0;
    NSUInteger n = 0;
    if ([NSStringFromClass([v class]) hasSuffix:@"IconView"] && [v respondsToSelector:NSSelectorFromString(@"setLabelHidden:")]) {
        // da dung trang thai thi thoi (ham nay chay moi lan layout khi tat ten: khong gay layout lai)
        if (![v respondsToSelector:NSSelectorFromString(@"isLabelHidden")] || objcInvokeT(v, @"isLabelHidden", BOOL) != hidden)
            objcCall_1(v, @"setLabelHidden:", hidden);
        return 1;
    }
    for (UIView *c in v.subviews) n += SCPHSetLabels(c, hidden, depth + 1);
    return n;
}

static void SCPHApplyNames(UIView *root, BOOL show, BOOL log)
{
    NSMutableArray<UIView *> *lists = [NSMutableArray array];
    SCPHCollectLists(root, lists, 0);
    NSUInteger n = 0;
    for (UIView *l in lists) n += SCPHSetLabels(l, !show, 0);
    if (log) SCPLog("HomeScreen: ten app %@ (%lu icon)", show ? @"hien" : @"an", (unsigned long)n);
}

// ---------------------------------------------------------------------
//  Luoi deu: khi chon so cot / hang, CarPlay doi so icon moi trang nhung van dat icon theo le / khoang cach cua luoi goc nen
//  chia lech. Sau moi lan CarPlay xep (hook SBIconListView, AppIcons.xm) chia vung luoi icon thanh cot x hang o bang nhau
//  theo kich thuoc that cua no, dat TAM ANH icon vao tam o (giao diem duong giua cot va duong giua hang); ten app treo
//  ben duoi. Co icon doi (iconImageInfo) thi anh to / nho quanh chinh diem do. Thu tu icon = thu tu CarPlay da xep
//  (tren xuong, trai sang). Tu dong x Tu dong = khong dong vao.
// ---------------------------------------------------------------------
static NSUInteger SCPHListCount(UIView *list, NSString *sel)
{
    SEL s = NSSelectorFromString(sel);
    if (![list respondsToSelector:s]) return 0;
    @try { return ((NSUInteger (*)(id, SEL))objc_msgSend)(list, s); } @catch (NSException *e) { return 0; }
}

// So o khac nhau theo mot truc (du phong khi luoi khong noi so cot / hang)
static NSUInteger SCPHDistinct(NSArray<UIView *> *icons, BOOL xAxis)
{
    NSMutableSet *seen = [NSMutableSet set];
    for (UIView *v in icons) [seen addObject:@(lround((xAxis ? v.center.x : v.center.y) / 8.0))];
    return seen.count;
}

// Khung anh icon trong icon view (nhan ten nam duoi anh); khong co iconImageFrame thi coi anh vuong o dinh
static CGRect SCPHIconImageRect(UIView *v)
{
    CGRect b = v.bounds;
    CGRect img = CGRectMake(0, 0, b.size.width, MIN(b.size.width, b.size.height));
    SEL imgSel = NSSelectorFromString(@"iconImageFrame");   // objcInvokeT khong dung duoc voi CGRect ((t){0}: -Wmissing-braces)
    if ([v respondsToSelector:imgSel]) {
        @try { CGRect f = ((CGRect (*)(id, SEL))objc_msgSend)(v, imgSel); if (f.size.width > 1 && f.size.height > 1) img = f; } @catch (NSException *e) {}
    }
    return img;
}

// Icon cua mot luoi theo thu tu CarPlay da xep (tren xuong, trai sang)
static NSMutableArray<UIView *> *SCPHGridIcons(UIView *list)
{
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    for (UIView *v in list.subviews) {
        NSString *cls = NSStringFromClass([v class]);
        if (!v.hidden && [cls hasSuffix:@"IconView"] && ![cls hasSuffix:@"ListView"]) [icons addObject:v];
    }
    [icons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        long ya = lround(a.center.y / 8.0), yb = lround(b.center.y / 8.0);
        if (ya != yb) return ya < yb ? NSOrderedAscending : NSOrderedDescending;
        return a.center.x < b.center.x ? NSOrderedAscending : (a.center.x > b.center.x ? NSOrderedDescending : NSOrderedSame);
    }];
    return icons;
}

void SCPHomeLayoutGrid(UIView *list)
{
    NSInteger wantCols = SCPHomeGridColumns(), wantRows = SCPHomeGridRows();
    if (wantCols <= 0 && wantRows <= 0) return;
    UIViewController *home = sHomeVC;
    if (!home.isViewLoaded || !list.window || ![list isDescendantOfView:home.view]) return;
    NSMutableArray<UIView *> *icons = SCPHGridIcons(list);
    if (!icons.count) return;
    NSUInteger cols = wantCols > 0 ? (NSUInteger)wantCols : SCPHListCount(list, @"iconColumnsForCurrentOrientation");
    NSUInteger rows = wantRows > 0 ? (NSUInteger)wantRows : SCPHListCount(list, @"iconRowsForCurrentOrientation");
    if (!cols) cols = SCPHDistinct(icons, YES);
    if (!rows) rows = SCPHDistinct(icons, NO);
    if (!cols || !rows) return;
    CGRect area = list.bounds;
    if (area.size.width < 120 || area.size.height < 120) return;   // dai hep kieu dock: de CarPlay
    CGFloat cellW = area.size.width / cols, cellH = area.size.height / rows;
    if (cellW < 1 || cellH < 1) return;
    // o doi (lan dau, doi cot / hang, doi man) -> co icon tinh lai theo o (SCPHomeIconSide): bao CarPlay xep lai mot lan
    if (fabs(sGridCell.width - cellW) > 1 || fabs(sGridCell.height - cellH) > 1) {
        sGridCell = CGSizeMake(cellW, cellH);
        SCPLog("HomeScreen: o luoi %.0fx%.0f -> canh icon %.0f pt (Co icon %.0f %%)", cellW, cellH, SCPHomeIconSide(60), SCPHomeIconScale() * 100);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *h = sHomeVC;
            if (h.isViewLoaded) SCPHRelayoutIcons(h.view, [SCPHSettings()[@"size"] integerValue]);
        });
    }
    NSUInteger moved = 0;
    for (NSUInteger i = 0; i < icons.count && i < cols * rows; i++) {
        UIView *v = icons[i];
        CGPoint target = CGPointMake(CGRectGetMinX(area) + (i % cols + 0.5) * cellW, CGRectGetMinY(area) + (i / cols + 0.5) * cellH);
        CGRect b = v.bounds, img = SCPHIconImageRect(v);
        CGPoint c = CGPointMake(target.x - (CGRectGetMidX(img) - CGRectGetMidX(b)), target.y - (CGRectGetMidY(img) - CGRectGetMidY(b)));
        if (fabs(v.center.x - c.x) > 0.5 || fabs(v.center.y - c.y) > 0.5) { v.center = c; moved++; }
    }
    static NSString *lastLog;
    NSString *key = [NSString stringWithFormat:@"%lux%lu %@ %lu", (unsigned long)cols, (unsigned long)rows, NSStringFromCGSize(area.size), (unsigned long)icons.count];
    if (moved && ![key isEqualToString:lastLog]) {
        lastLog = key;
        SCPLog("HomeScreen: luoi deu %lux%lu trong %@ (%@): o %.0fx%.0f, %lu icon, dat lai %lu", (unsigned long)cols, (unsigned long)rows,
               NSStringFromCGSize(area.size), NSStringFromClass([list class]), cellW, cellH, (unsigned long)icons.count, (unsigned long)moved);
    }
}

// ---------------------------------------------------------------------
//  Danh sach app tren man chinh cho Cai dat (HS_KEY_CAR_APPS): lay tu mo hinh icon cua luoi (moi trang, thu tu cua xe),
//  ten tu icon / thu vien app (app rieng cua CarPlay nhu Dang phat, Cai dat khong co trong LSApplicationProxy cua iPhone).
//  Bo app iPhone OmniCar chen (App Bridge). App OmniCar dang an (HS_KEY_HIDDEN_APPS) giu cho cu tu danh sach truoc.
// ---------------------------------------------------------------------
static id SCPHTry(id obj, NSString *sel)
{
    if (!obj || ![obj respondsToSelector:NSSelectorFromString(sel)]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel)); } @catch (NSException *e) { return nil; }
}

static NSString *SCPHIconBundle(id icon)
{
    for (NSString *k in @[@"applicationBundleID", @"leafIdentifier"]) {
        id v = SCPHTry(icon, k);
        if ([v isKindOfClass:[NSString class]] && [v length]) return v;
    }
    return nil;
}

static NSString *SCPHIconName(id icon, NSString *bid)
{
    id n = SCPHTry(icon, @"displayName");
    if (![n isKindOfClass:[NSString class]] || ![n length]) {
        id lib = SCPHTry([UIApplication sharedApplication], @"sharedApplicationLibrary");
        id info = nil;
        @try { if ([lib respondsToSelector:NSSelectorFromString(@"applicationInfoForBundleIdentifier:")])
            info = ((id (*)(id, SEL, id))objc_msgSend)(lib, NSSelectorFromString(@"applicationInfoForBundleIdentifier:"), bid); } @catch (NSException *e) {}
        n = SCPHTry(info, @"displayName");
    }
    return [n isKindOfClass:[NSString class]] && [n length] ? n : bid;
}

// Moi app tren man chinh theo thu tu: @[@{id, name}]; nil = chua doc duoc ca thu muc (chi 1 trang -> khong ghi)
static NSArray<NSDictionary *> *SCPHHomeApps(UIView *root)
{
    NSMutableArray<UIView *> *lists = [NSMutableArray array];
    SCPHCollectLists(root, lists, 0);
    NSArray *best = nil;
    for (UIView *l in lists) {
        NSArray *pages = SCPHTry(SCPHTry(SCPHTry(l, @"model"), @"folder"), @"lists");
        if ([pages isKindOfClass:[NSArray class]] && pages.count > best.count) best = pages;   // thu muc lon nhat = man chinh
    }
    if (!best.count) return nil;
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id page in best) {
        NSArray *icons = SCPHTry(page, @"icons");
        if (![icons isKindOfClass:[NSArray class]]) continue;
        for (id icon in icons) {
            NSString *bid = SCPHIconBundle(icon);
            if (!bid || [seen containsObject:bid] || SCPIsInjectedPhoneApp(bid)) continue;
            [seen addObject:bid];
            [out addObject:@{@"id": bid, @"name": SCPHIconName(icon, bid)}];
        }
    }
    return out;
}

static void SCPHPublishApps(UIView *root)
{
    NSArray *now = SCPHHomeApps(root);
    if (!now.count) return;
    OMCPrefsSync();
    id oldV = OMCPref(HS_KEY_CAR_APPS, nil), hidV = OMCPref(HS_KEY_HIDDEN_APPS, nil);
    NSArray *old = [oldV isKindOfClass:[NSArray class]] ? oldV : @[];
    NSSet *hidden = [hidV isKindOfClass:[NSArray class]] ? [NSSet setWithArray:hidV] : [NSSet set];
    NSMutableArray *list = [now mutableCopy];
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *a in now) [ids addObject:a[@"id"]];
    // app OmniCar dang an: khong con tren luoi nhung giu cho cu de Cai dat van bat lai duoc
    for (NSUInteger i = 0; i < old.count; i++) {
        NSDictionary *a = old[i];
        if (![a isKindOfClass:[NSDictionary class]] || ![a[@"id"] isKindOfClass:[NSString class]]) continue;
        if (![hidden containsObject:a[@"id"]] || [ids containsObject:a[@"id"]]) continue;
        [list insertObject:a atIndex:MIN(i, list.count)];
        [ids addObject:a[@"id"]];
    }
    // App co giao dien CarPlay ma khong tren man chinh: da bo trong Tuy chinh cua iOS (off) - hoac OmniCar dang an (khong off)
    id lib = SCPHTry([UIApplication sharedApplication], @"sharedApplicationLibrary");
    NSArray *all = SCPHTry(lib, @"allInstalledApplications");
    NSMutableArray *offApps = [NSMutableArray array];
    for (id info in [all isKindOfClass:[NSArray class]] ? all : @[]) {
        NSString *bid = SCPHTry(info, @"bundleIdentifier");
        if (![bid isKindOfClass:[NSString class]] || !bid.length || [ids containsObject:bid] || !SCPHTry(info, @"carPlayDeclaration")) continue;
        if ([bid hasPrefix:@"com.apple.CarPlay"] || [bid isEqualToString:@"com.apple.InCallService"] || SCPIsInjectedPhoneApp(bid)) continue;
        id n = SCPHTry(info, @"displayName");
        NSMutableDictionary *a = [@{@"id": bid, @"name": [n isKindOfClass:[NSString class]] && [n length] ? n : bid} mutableCopy];
        if (![hidden containsObject:bid]) a[@"off"] = @YES;
        [offApps addObject:a];
        [ids addObject:bid];
    }
    [offApps sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
    [list addObjectsFromArray:offApps];
    if ([list isEqualToArray:old]) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)HS_KEY_CAR_APPS, (__bridge CFPropertyListRef)list, OMC_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *a in list) [names addObject:a[@"id"]];
    SCPLog("HomeScreen: %lu app tren man chinh cho Cai dat: %@", (unsigned long)list.count, [names componentsJoinedByString:@", "]);
}

#if OMC_AUTOTEST
NSArray<NSString *> *SCPHomeVisibleBundles(void)
{
    UIViewController *home = sHomeVC;
    if (!home.isViewLoaded || !home.view.window) return nil;
    return [SCPHHomeApps(home.view) valueForKey:@"id"] ?: @[];
}

NSInteger SCPHomeFirstPageIconCount(void)
{
    UIViewController *home = sHomeVC;
    if (!home.isViewLoaded) return -1;
    NSMutableArray<UIView *> *lists = [NSMutableArray array];
    SCPHCollectLists(home.view, lists, 0);
    for (UIView *l in lists) {
        NSArray *pages = SCPHTry(SCPHTry(SCPHTry(l, @"model"), @"folder"), @"lists");
        NSArray *icons = [pages isKindOfClass:[NSArray class]] && pages.count ? SCPHTry(pages.firstObject, @"icons") : SCPHTry(SCPHTry(l, @"model"), @"icons");
        if ([icons isKindOfClass:[NSArray class]]) return (NSInteger)icons.count;
    }
    return -1;
}

static NSInteger SCPHCountLabels(UIView *v, int depth)
{
    if (!v || depth > 8) return 0;
    if ([NSStringFromClass([v class]) hasSuffix:@"IconView"]) {
        BOOL hidden = [v respondsToSelector:NSSelectorFromString(@"isLabelHidden")] && objcInvokeT(v, @"isLabelHidden", BOOL);
        UIView *label = SCPHTry(v, @"labelView");
        BOOL drawn = !label || (!label.hidden && label.alpha > 0.05 && label.bounds.size.width > 1);
        return (!hidden && drawn) ? 1 : 0;
    }
    NSInteger n = 0;
    for (UIView *c in v.subviews) n += SCPHCountLabels(c, depth + 1);
    return n;
}

// Luoi deu tren trang dang hien (bo test "homeScreen"): tam anh moi icon dung tam o (lech <= 2 pt), canh anh = SCPHomeIconSide,
// anh nam trong vung luoi va khong chong nhau (tru khi allowOverlap: Co icon > 100 %). nil = dung; outCenters / outSide: tam
// anh (toa do luoi) va canh anh do duoc, de buoc sau so sanh (doi Co icon thi tam phai giu nguyen).
NSString *SCPHomeGridCheck(NSInteger wantCols, NSInteger wantRows, BOOL allowOverlap, NSArray<NSValue *> **outCenters, CGFloat *outSide)
{
    UIViewController *home = sHomeVC;
    if (!home.isViewLoaded || !home.view.window) return @"man chinh CarPlay khong hien";
    NSMutableArray<UIView *> *lists = [NSMutableArray array];
    SCPHCollectLists(home.view, lists, 0);
    UIView *list = nil;
    CGFloat bestArea = 0;
    for (UIView *l in lists) {   // trang dang hien = luoi chiem nhieu man chinh nhat
        CGRect r = CGRectIntersection([l convertRect:l.bounds toView:home.view], home.view.bounds);
        if (!CGRectIsNull(r) && r.size.width * r.size.height > bestArea) { bestArea = r.size.width * r.size.height; list = l; }
    }
    if (!list) return @"khong thay *IconListView nao dang hien";
    NSMutableArray<UIView *> *icons = SCPHGridIcons(list);
    if (!icons.count) return OMCTestFormat(@"%@ khong co icon", NSStringFromClass([list class]));
    NSUInteger cols = wantCols > 0 ? (NSUInteger)wantCols : SCPHListCount(list, @"iconColumnsForCurrentOrientation");
    NSUInteger rows = wantRows > 0 ? (NSUInteger)wantRows : SCPHListCount(list, @"iconRowsForCurrentOrientation");
    if (!cols) cols = SCPHDistinct(icons, YES);
    if (!rows) rows = SCPHDistinct(icons, NO);
    CGRect area = list.bounds;
    CGFloat cellW = area.size.width / cols, cellH = area.size.height / rows, want = SCPHomeIconSide(0);
    NSMutableArray<NSValue *> *centers = [NSMutableArray array];
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    CGFloat side = 0;
    NSUInteger n = MIN(icons.count, cols * rows);
    for (NSUInteger i = 0; i < n; i++) {
        UIView *v = icons[i];
        CGRect img = [v convertRect:SCPHIconImageRect(v) toView:list];
        CGPoint c = CGPointMake(CGRectGetMidX(img), CGRectGetMidY(img));
        CGPoint t = CGPointMake(CGRectGetMinX(area) + (i % cols + 0.5) * cellW, CGRectGetMinY(area) + (i / cols + 0.5) * cellH);
        if (fabs(c.x - t.x) > 2 || fabs(c.y - t.y) > 2)
            return OMCTestFormat(@"icon %lu (cot %lu hang %lu): tam anh %@, can %@ (luoi %lux%lu trong %@)", (unsigned long)i + 1, (unsigned long)(i % cols) + 1,
                                 (unsigned long)(i / cols) + 1, NSStringFromCGPoint(c), NSStringFromCGPoint(t), (unsigned long)cols, (unsigned long)rows,
                                 NSStringFromCGSize(area.size));
        if (fabs(img.size.width - want) > 2)
            return OMCTestFormat(@"icon %lu: canh anh %.1f pt, can %.1f (o %.0fx%.0f)", (unsigned long)i + 1, img.size.width, want, cellW, cellH);
        if (!allowOverlap && !CGRectContainsRect(CGRectInset(area, -2, -2), img))
            return OMCTestFormat(@"icon %lu: anh %@ tran ra ngoai vung luoi %@", (unsigned long)i + 1, NSStringFromCGRect(img), NSStringFromCGRect(area));
        if (!allowOverlap) for (NSValue *o in rects) if (CGRectIntersectsRect(CGRectInset(o.CGRectValue, 1, 1), CGRectInset(img, 1, 1)))
            return OMCTestFormat(@"icon %lu: anh %@ chong len icon khac %@", (unsigned long)i + 1, NSStringFromCGRect(img), NSStringFromCGRect(o.CGRectValue));
        [rects addObject:[NSValue valueWithCGRect:img]];
        [centers addObject:[NSValue valueWithCGPoint:c]];
        side = img.size.width;
    }
    OMCTestLog(@"luoi %lux%lu trong %@: o %.0fx%.0f, %lu icon, canh anh %.1f pt", (unsigned long)cols, (unsigned long)rows, NSStringFromCGSize(area.size),
               cellW, cellH, (unsigned long)n, side);
    if (outCenters) *outCenters = centers;
    if (outSide) *outSide = side;
    return nil;
}

NSInteger SCPHomeVisibleLabelCount(void)
{
    UIViewController *home = sHomeVC;
    if (!home.isViewLoaded) return -1;
    NSMutableArray<UIView *> *lists = [NSMutableArray array];
    SCPHCollectLists(home.view, lists, 0);
    NSInteger n = 0;
    for (UIView *l in lists) n += SCPHCountLabels(l, 0);
    return n;
}
#endif

// Moi lan man chinh layout: ghi danh sach 1 s sau lan cuoi (gom lai, man chinh layout nhieu lan lien tiep)
static void SCPHPublishAppsSoon(void)
{
    static NSUInteger gen;
    NSUInteger my = ++gen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (my != gen) return;
        UIViewController *home = sHomeVC;
        if (!home.isViewLoaded || !home.view.window) return;
        @try { SCPHPublishApps(home.view); } @catch (NSException *e) { SCPLog("HomeScreen: ghi danh sach app loi %@", e); }
    });
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
    // So cot / hang: hook doc SCPHomeGridColumns / Rows; doi thi mo hinh icon xep lai trang (so icon moi trang doi)
    NSString *grid = [NSString stringWithFormat:@"%ldx%ld", (long)SCPHomeGridColumns(), (long)SCPHomeGridRows()];
    if (![grid isEqualToString:sAppliedGrid]) {
        sAppliedGrid = grid;
        SCPHLogTreeOnce(root);
        SCPHomeIconModelLayout([@"luoi " stringByAppendingString:grid]);
        SCPHRelayoutIcons(root, size);
    }
    // Ten app: tat thi ap moi lan layout (icon moi tao co the chua qua setLabelHidden:); bat lai thi ap 1 lan
    BOOL names = SCPHomeShowNames();
    if (!names || names != sAppliedNames) SCPHApplyNames(root, names, names != sAppliedNames);
    if (names != sAppliedNames) SCPHRelayoutIcons(root, size);   // hook +maxLabelSizeForIconImageSize: chi co hieu luc khi xep lai
    sAppliedNames = names;
    SCPHPublishAppsSoon();
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
