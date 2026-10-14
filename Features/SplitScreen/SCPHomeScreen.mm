#import "SCPHomeScreen.h"
#import "SCPCarSplit.h"
#import "SCPAppIcons.h"
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <dlfcn.h>

// =====================================================================
//  Man chinh CarPlay cua OmniCar (xem SCPHomeScreen.h). Moi thu tren xe di qua 3 duong da chay that:
//  - thu tu app: model cua *IconListView (SCPCarHomeBundles, nhu bang chon app cua Split Screen)
//  - icon app: SCPCarAppIcon (hoac goi icon IconBundles); mo app: SCPCarLaunchApp (DashBoard _launchAppWithInfo:forURL:,
//    app iPhone -> App Bridge)
//  - dock: root VC appDockViewController.view (nhu nut Split Screen)
//  Luoi / dock / hinh nen goc chi bi an (hidden = YES, nho lai de tra), khong sua gi ben trong CarPlay.
//  Lan dau ghi log cay view man chinh de chinh lai neu iOS khac sap xep khac.
//  ROADMAP-DEV 3.1: hinh nen ngay / dem, hinh nen dong (video), hinh dang + goi icon, thu muc + trang app iPhone, widget.
// =====================================================================

static NSDictionary *sHS;            // cai dat dang dung (doc lai khi prefschanged)
static __weak UIViewController *sHomeVC, *sRootVC;
static NSHashTable<UIView *> *sHiddenByUs;   // view goc OmniCar da an (de tra lai khi tat)
static BOOL sHomeVisible = YES;      // DBDashboardHomeViewController dang hien (khong bi app toan man che)

static NSHashTable *SCPHHidden(void)
{
    if (!sHiddenByUs) sHiddenByUs = [NSHashTable weakObjectsHashTable];
    return sHiddenByUs;
}

static void SCPHHide(UIView *v)
{
    if (!v || v.hidden) return;
    v.hidden = YES;
    [SCPHHidden() addObject:v];
}

static void SCPHUnhideAll(void)
{
    for (UIView *v in SCPHHidden().allObjects) v.hidden = NO;
    [SCPHHidden() removeAllObjects];
}

static NSDictionary *SCPHLoad(void)
{
    OMCPrefsSync();
    NSArray *(^arr)(NSString *) = ^NSArray *(NSString *k) { id v = OMCPref(k, nil); return [v isKindOfClass:[NSArray class]] ? v : @[]; };
    NSInteger (^num)(NSString *, NSInteger, NSInteger, NSInteger) = ^NSInteger(NSString *k, NSInteger def, NSInteger lo, NSInteger hi) {
        id v = OMCPref(k, nil);
        NSInteger n = [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def;
        return MIN(hi, MAX(lo, n));
    };
    NSInteger day = [OMCPref(HS_KEY_WALLPAPER, @NO) boolValue] ? num(HS_KEY_WALLPAPER_STYLE, 7, 1, 8) : 0;
    NSMutableArray *widgets = [NSMutableArray array];
    for (NSString *w in arr(HS_KEY_WIDGETS))
        if ([@[@"clock", @"weather", @"music"] containsObject:w] && ![widgets containsObject:w] && widgets.count < HS_WIDGETS_MAX) [widgets addObject:w];
    id theme = OMCPref(HS_KEY_ICON_THEME, @"");
    return @{
        @"on": @(OMCEnabled() && [OMCPref(HS_KEY_ENABLED, @NO) boolValue]),
        @"order": arr(HS_KEY_ORDER), @"hidden": arr(HS_KEY_HIDDEN), @"dock": arr(HS_KEY_DOCK),
        @"size": @(num(HS_KEY_ICON_SIZE, 100, 80, 130)), @"cols": @(num(HS_KEY_COLS, 5, 3, 7)), @"rows": @(num(HS_KEY_ROWS, 2, 1, 3)),
        @"gap": @(num(HS_KEY_GAP, 100, 60, 140)), @"names": @([OMCPref(HS_KEY_NAMES, @YES) boolValue]),
        @"day": @(day), @"night": @(num(HS_KEY_NIGHT_STYLE, 0, 0, 8)), @"nightBy": @(num(HS_KEY_NIGHT_BY, 0, 0, 1)),
        @"blur": @(num(HS_KEY_BLUR, 0, 0, 30)), @"dim": @(num(HS_KEY_DIM, 25, 0, 70)),
        @"suggest": @([OMCPref(HS_KEY_DOCK_SUGGEST, @YES) boolValue]),
        @"shape": @(num(HS_KEY_ICON_SHAPE, 0, 0, 2)), @"glass": @([OMCPref(HS_KEY_ICON_GLASS, @NO) boolValue]),
        @"shadow": @([OMCPref(HS_KEY_ICON_SHADOW, @YES) boolValue]), @"theme": [theme isKindOfClass:[NSString class]] ? theme : @"",
        @"folders": arr(HS_KEY_FOLDERS), @"phonePage": @([OMCPref(HS_KEY_PHONE_PAGE, @NO) boolValue]), @"widgets": widgets,
    };
}

static NSDictionary *SCPHSettings(void)
{
    if (!sHS) sHS = SCPHLoad();
    return sHS;
}

// App theo thu tu nguoi dung: app co trong HS_KEY_ORDER truoc (theo thu tu do), app moi theo thu tu CarPlay; bo app an
static NSArray<NSString *> *SCPHApps(NSArray<NSString *> *carplay, NSDictionary *hs)
{
    NSMutableArray *out = [NSMutableArray array];
    NSSet *hidden = [NSSet setWithArray:hs[@"hidden"]];
    for (NSString *b in hs[@"order"]) if ([b isKindOfClass:[NSString class]] && [carplay containsObject:b] && ![hidden containsObject:b] && ![out containsObject:b]) [out addObject:b];
    for (NSString *b in carplay) if (![hidden containsObject:b] && ![out containsObject:b]) [out addObject:b];
    return out;
}

// O tren luoi: app (NSString) hoac thu muc @{name, apps} dat o cho app dau tien cua no. Thu muc khong con app hien -> bo.
static NSArray *SCPHItems(NSArray<NSString *> *apps, NSDictionary *hs)
{
    NSMutableDictionary<NSString *, NSDictionary *> *folderOf = [NSMutableDictionary dictionary];
    for (NSDictionary *f in hs[@"folders"]) {
        if (![f isKindOfClass:[NSDictionary class]] || ![f[@"apps"] isKindOfClass:[NSArray class]]) continue;
        NSMutableArray *in = [NSMutableArray array];
        for (NSString *b in f[@"apps"]) if ([b isKindOfClass:[NSString class]] && [apps containsObject:b] && !folderOf[b]) [in addObject:b];
        if (!in.count) continue;
        NSString *name = [f[@"name"] isKindOfClass:[NSString class]] && [f[@"name"] length] ? f[@"name"] : OMCTr(@"Thư mục", @"Folder");
        NSDictionary *folder = @{@"name": name, @"apps": in};
        for (NSString *b in in) folderOf[b] = folder;
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *b in apps) {
        NSDictionary *f = folderOf[b];
        if (!f) [out addObject:b];
        else if (![out containsObject:f]) [out addObject:f];
    }
    return out;
}

// ---------------------------------------------------------------------
//  Icon: goi icon (IconBundles) neu co, khong thi icon cua CarPlay; hinh dang / vien kinh / bong theo cai dat
// ---------------------------------------------------------------------
static UIImage *SCPHThemeIcon(NSString *bid, NSString *theme)
{
    if (!theme.length || !bid.length) return nil;
    static NSCache *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@/%@", theme, bid];
    id hit = [cache objectForKey:key];
    if (hit) return hit == [NSNull null] ? nil : hit;
    NSString *dir = [[HS_THEMES_DIR stringByAppendingPathComponent:theme] stringByAppendingPathComponent:@"IconBundles"];
    UIImage *img = nil;
    for (NSString *base in @[[bid stringByAppendingString:@"-large"], bid])
        for (NSString *sfx in @[@"@3x.png", @"@2x.png", @".png"]) {
            if (img) break;
            img = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:[base stringByAppendingString:sfx]]];
        }
    [cache setObject:img ?: (id)[NSNull null] forKey:key];
    return img;
}

static UIImage *SCPHIconImage(NSString *bid, NSDictionary *hs)
{
    return SCPHThemeIcon(bid, hs[@"theme"]) ?: SCPCarAppIcon(bid);
}

static CGFloat SCPHCorner(NSDictionary *hs, CGFloat side)
{
    switch ([hs[@"shape"] integerValue]) {
        case 1: return side * 0.12;
        case 2: return side / 2;
        default: return side * 0.225;
    }
}

// O thu muc: nen kinh mo + toi da 4 icon nho 2 x 2
static UIImage *SCPHFolderImage(NSArray<NSString *> *apps, CGFloat side, NSDictionary *hs)
{
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.opaque = NO;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:f] imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        [[UIColor colorWithWhite:1 alpha:0.26] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:SCPHCorner(hs, side)] fill];
        CGFloat pad = side * 0.14, gap = side * 0.08, mini = (side - pad * 2 - gap) / 2;
        for (NSInteger i = 0; i < MIN(4, (NSInteger)apps.count); i++) {
            CGRect r = CGRectMake(pad + (i % 2) * (mini + gap), pad + (i / 2) * (mini + gap), mini, mini);
            UIImage *ic = SCPHIconImage(apps[i], hs);
            CGContextSaveGState(rc.CGContext);
            [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:SCPHCorner(hs, mini)] addClip];
            if (ic) [ic drawInRect:r]; else { [[UIColor colorWithWhite:1 alpha:0.3] setFill]; UIRectFill(r); }
            CGContextRestoreGState(rc.CGContext);
        }
    }];
}

@interface SCPHomeIconButton : UIButton
@property (nonatomic, copy) NSString *bundle;
@property (nonatomic, copy) NSDictionary *folder;
@end
@implementation SCPHomeIconButton
- (void)setHighlighted:(BOOL)h
{
    BOOL changed = (h != self.highlighted);
    [super setHighlighted:h];
    if (!changed) return;
    [UIView animateWithDuration:h ? 0.12 : 0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = h ? CGAffineTransformMakeScale(0.9, 0.9) : CGAffineTransformIdentity; } completion:nil];
}
@end

// item: bundle id hoac thu muc @{name, apps}
static SCPHomeIconButton *SCPHIcon(id item, CGFloat side, BOOL name, CGFloat cellW, NSDictionary *hs, id target, SEL action)
{
    BOOL isFolder = [item isKindOfClass:[NSDictionary class]];
    NSString *bid = isFolder ? nil : item;
    CGFloat nameH = name ? 16 : 0, corner = SCPHCorner(hs, side);
    SCPHomeIconButton *b = [SCPHomeIconButton buttonWithType:UIButtonTypeCustom];
    b.bundle = bid;
    b.folder = isFolder ? item : nil;
    b.frame = CGRectMake(0, 0, cellW, side + (name ? 4 + nameH : 0));
    CGRect iconFrame = CGRectMake((cellW - side) / 2, 0, side, side);
    if ([hs[@"shadow"] boolValue]) {   // bong (icon cat bo goc)
        UIView *lift = [[UIView alloc] initWithFrame:iconFrame];
        lift.userInteractionEnabled = NO;
        lift.layer.shadowColor = [UIColor blackColor].CGColor;
        lift.layer.shadowOpacity = 0.3; lift.layer.shadowRadius = 6; lift.layer.shadowOffset = CGSizeMake(0, 3);
        lift.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:lift.bounds cornerRadius:corner].CGPath;
        [b addSubview:lift];
    }
    UIImageView *iv = [[UIImageView alloc] initWithFrame:iconFrame];
    iv.image = isFolder ? SCPHFolderImage(item[@"apps"], side, hs) : SCPHIconImage(bid, hs);
    iv.layer.cornerRadius = corner;
    iv.layer.cornerCurve = kCACornerCurveContinuous;
    iv.clipsToBounds = YES;
    iv.userInteractionEnabled = NO;
    iv.backgroundColor = iv.image ? [UIColor clearColor] : [UIColor colorWithWhite:1 alpha:0.2];
    [b addSubview:iv];
    if ([hs[@"glass"] boolValue]) {   // vien kinh: vien trang mong + vet sang nua tren
        CAGradientLayer *shine = [CAGradientLayer layer];
        shine.frame = iv.bounds;
        shine.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.35].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
        shine.endPoint = CGPointMake(0.5, 0.55);
        [iv.layer addSublayer:shine];
        iv.layer.borderWidth = 1;
        iv.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
    }
    NSString *title = isFolder ? item[@"name"] : SCPCarAppName(bid);
    if (name) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(-2, side + 4, cellW + 4, nameH)];
        l.text = title;
        l.textColor = [UIColor whiteColor];
        l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        l.textAlignment = NSTextAlignmentCenter;
        l.lineBreakMode = NSLineBreakByTruncatingTail;
        l.layer.shadowColor = [UIColor blackColor].CGColor;
        l.layer.shadowOpacity = 0.6; l.layer.shadowRadius = 2; l.layer.shadowOffset = CGSizeZero;
        l.userInteractionEnabled = NO;
        [b addSubview:l];
    }
    b.accessibilityLabel = title;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

static void SCPHLaunch(NSString *bid, const char *where)
{
    SCPLog("HomeScreen: %s mo %@", where, bid);
    @try { SCPCarLaunchApp(bid); } @catch (NSException *e) { SCPLog("HomeScreen: loi mo app %@: %@", bid, e); }
}

// ---------------------------------------------------------------------
//  Hinh nen: anh (lam mo bang CIGaussianBlur tren luong phu) hoac video lap khong tieng, phu lop toi.
//  Ngay / dem: theo giao dien sang / toi cua xe, hoac mat troi moc / lan (vi tri iOS da biet, khong co: 6:00 / 18:00).
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

// Mat troi moc / lan hom nay (phuong trinh mat troi moc, sai so vai phut). NO = dem / ngay vung cuc.
static BOOL SCPHSunTimes(NSDate *now, double lat, double lon, NSDate **rise, NSDate **set)
{
    double rad = M_PI / 180.0;
    NSDate *noon = [[NSCalendar currentCalendar] dateBySettingHour:12 minute:0 second:0 ofDate:now options:0] ?: now;
    double jd = noon.timeIntervalSince1970 / 86400.0 + 2440587.5;
    double n = round(jd - 2451545.0 + lon / 360.0);
    double js = n - lon / 360.0;
    double m = fmod(357.5291 + 0.98560028 * js, 360.0);
    double c = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad);
    double l = fmod(m + c + 180 + 102.9372, 360.0);
    double transit = 2451545.0 + js + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * l * rad);
    double decl = asin(sin(l * rad) * sin(23.4397 * rad));
    double cosw = (sin(-0.833 * rad) - sin(lat * rad) * sin(decl)) / (cos(lat * rad) * cos(decl));
    if (cosw < -1 || cosw > 1) return NO;
    double w = acos(cosw) / rad;
    *rise = [NSDate dateWithTimeIntervalSince1970:(transit - w / 360.0 - 2440587.5) * 86400.0];
    *set = [NSDate dateWithTimeIntervalSince1970:(transit + w / 360.0 - 2440587.5) * 86400.0];
    return YES;
}

static BOOL SCPHIsNight(NSDictionary *hs, UITraitCollection *tc)
{
    if ([hs[@"nightBy"] integerValue] == 0) return tc.userInterfaceStyle == UIUserInterfaceStyleDark;
    NSDate *now = [NSDate date], *rise = nil, *set = nil;
    static CLLocation *sLoc;
    static NSDate *sLocAt;
    if (!sLocAt || -sLocAt.timeIntervalSinceNow > 3600) {   // vi tri cuoi iOS da biet, khong hoi vi tri moi
        sLocAt = now;
        @try { sLoc = [CLLocationManager new].location ?: sLoc; } @catch (NSException *e) {}
    }
    if (sLoc && SCPHSunTimes(now, sLoc.coordinate.latitude, sLoc.coordinate.longitude, &rise, &set))
        return [now compare:rise] == NSOrderedAscending || [now compare:set] != NSOrderedAscending;
    NSInteger h = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:now];
    return h < 6 || h >= 18;
}

// Hinh nen dang dung: @{path, video} hoac nil = de nguyen hinh nen CarPlay
static NSDictionary *SCPHWallSource(NSDictionary *hs, BOOL night)
{
    NSInteger style = [hs[@"day"] integerValue];
    NSString *image = HS_WALLPAPER_PATH;
    if (night && [hs[@"night"] integerValue] > 0) { style = [hs[@"night"] integerValue]; image = HS_NIGHT_PATH; }
    if (style <= 0) return nil;
    NSString *path = style == 8 ? HS_VIDEO_PATH : image;
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
//  Thu muc mo ra: the kinh giua man, luoi icon cua thu muc; cham ngoai the / mo app la dong
// ---------------------------------------------------------------------
static const NSInteger kSCPHFolderTag = 0x4846;   // "HF"

@interface SCPHomeFolderView : UIView
@end
@implementation SCPHomeFolderView
+ (void)showFolder:(NSDictionary *)folder inView:(UIView *)root settings:(NSDictionary *)hs
{
    [[root viewWithTag:kSCPHFolderTag] removeFromSuperview];
    SCPHomeFolderView *v = [[SCPHomeFolderView alloc] initWithFrame:root.bounds];
    v.tag = kSCPHFolderTag;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    [v addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:v action:@selector(close)]];
    NSArray *apps = folder[@"apps"];
    CGFloat side = round(64 * [hs[@"size"] doubleValue] / 100.0), cellW = side + 26, cellH = side + 24;
    NSInteger cols = MIN((NSInteger)apps.count, MAX(1, (NSInteger)floor((root.bounds.size.width - 120) / cellW)));
    cols = MIN(cols, 5);
    NSInteger rows = (apps.count + cols - 1) / cols;
    CGFloat titleH = 40, pad = 18, gridH = rows * cellH;
    CGFloat cardW = cols * cellW + pad * 2, cardH = MIN(root.bounds.size.height - 40, titleH + gridH + pad * 2);
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    card.frame = CGRectMake((root.bounds.size.width - cardW) / 2, (root.bounds.size.height - cardH) / 2, cardW, cardH);
    card.layer.cornerRadius = 26;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    [v addSubview:card];
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(pad, pad - 4, cardW - pad * 2, titleH - 8)];
    t.text = folder[@"name"];
    t.textColor = [UIColor whiteColor];
    t.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    t.textAlignment = NSTextAlignmentCenter;
    [card.contentView addSubview:t];
    UIScrollView *sc = [[UIScrollView alloc] initWithFrame:CGRectMake(pad, titleH + pad / 2, cols * cellW, cardH - titleH - pad * 1.5)];
    sc.contentSize = CGSizeMake(cols * cellW, gridH);
    sc.showsVerticalScrollIndicator = NO;
    [card.contentView addSubview:sc];
    for (NSInteger i = 0; i < (NSInteger)apps.count; i++) {
        SCPHomeIconButton *b = SCPHIcon(apps[i], side, YES, cellW, hs, v, @selector(iconTapped:));
        b.frame = CGRectMake((i % cols) * cellW, (i / cols) * cellH, cellW, b.bounds.size.height);
        [sc addSubview:b];
    }
    v.alpha = 0;
    card.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [root addSubview:v];
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        v.alpha = 1; card.transform = CGAffineTransformIdentity;
    } completion:nil];
    SCPLog("HomeScreen: mo thu muc \"%@\" (%lu app)", folder[@"name"], (unsigned long)apps.count);
}
- (void)close
{
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; } completion:^(BOOL f) { [self removeFromSuperview]; }];
}
- (void)iconTapped:(SCPHomeIconButton *)b
{
    [self close];
    SCPHLaunch(b.bundle, "thu muc");
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g   // cham trong the khong dong
{
    UIView *hit = [self hitTest:[g locationInView:self] withEvent:nil];
    return hit == self;
}
@end

// ---------------------------------------------------------------------
//  Luoi icon: trang vuot ngang, moi trang cols x rows, icon + ten (tuy chon); cham -> mo app / mo thu muc.
//  Trang rieng cho app iPhone: app iPhone (App Bridge) bat dau o trang moi sau app CarPlay.
// ---------------------------------------------------------------------
@interface SCPHomeGridView : UIView <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIPageControl *dots;
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, copy) NSString *builtKey;
@end
@implementation SCPHomeGridView
- (instancetype)initWithFrame:(CGRect)f
{
    if ((self = [super initWithFrame:f])) {
        _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scroll.pagingEnabled = YES;
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.delegate = self;
        [self addSubview:_scroll];
        _dots = [UIPageControl new];
        _dots.userInteractionEnabled = NO;
        _dots.hidesForSinglePage = YES;
        [self addSubview:_dots];
    }
    return self;
}
- (void)iconTapped:(SCPHomeIconButton *)b
{
    if (b.folder) {
        UIView *root = self.superview;
        if (root) [SCPHomeFolderView showFolder:b.folder inView:root settings:SCPHSettings()];
        return;
    }
    SCPHLaunch(b.bundle, "luoi");
}
- (void)scrollViewDidScroll:(UIScrollView *)sv
{
    CGFloat w = sv.bounds.size.width;
    if (w > 0) self.dots.currentPage = (NSInteger)round(sv.contentOffset.x / w);
}
- (void)buildWithSettings:(NSDictionary *)hs
{
    CGSize s = self.bounds.size;
    if (s.width < 100 || s.height < 60) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (id it in self.items) [ids addObject:[it isKindOfClass:[NSDictionary class]] ? [NSString stringWithFormat:@"[%@:%@]", it[@"name"], [it[@"apps"] componentsJoinedByString:@","]] : it];
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", [ids componentsJoinedByString:@","], NSStringFromCGSize(s),
                     [@[hs[@"size"], hs[@"cols"], hs[@"rows"], hs[@"gap"], hs[@"names"], hs[@"shape"], hs[@"glass"], hs[@"shadow"], hs[@"theme"], hs[@"phonePage"]] componentsJoinedByString:@","]];
    if ([key isEqualToString:self.builtKey]) return;
    self.builtKey = key;
    for (UIView *v in self.scroll.subviews) [v removeFromSuperview];
    BOOL names = [hs[@"names"] boolValue];
    CGFloat dotsH = 18, side = round(64 * [hs[@"size"] doubleValue] / 100.0);
    CGFloat gapX = 26 * [hs[@"gap"] doubleValue] / 100.0, gapY = 14 * [hs[@"gap"] doubleValue] / 100.0;
    CGFloat cellW = side + gapX, cellH = side + (names ? 20 : 0);
    CGFloat usableH = s.height - dotsH;
    // Khong bao gio tran man: icon to qua thi bot cot / hang (toi thieu 1)
    NSInteger maxCols = MAX(1, (NSInteger)floor((s.width - 16) / cellW)), maxRows = MAX(1, (NSInteger)floor((usableH - 8 + gapY) / (cellH + gapY)));
    NSInteger cols = MIN([hs[@"cols"] integerValue], maxCols), rows = MIN([hs[@"rows"] integerValue], maxRows), per = MAX(1, cols * rows);
    // Trang rieng cho app iPhone: chen o trong cho het trang cua app CarPlay
    NSMutableArray *slots = [NSMutableArray array];
    if ([hs[@"phonePage"] boolValue]) {
        NSMutableArray *phone = [NSMutableArray array];
        for (id it in self.items) {
            BOOL isPhone = [it isKindOfClass:[NSString class]] && SCPIsInjectedPhoneApp(it);
            [(isPhone ? phone : slots) addObject:it];
        }
        if (phone.count && slots.count) while (slots.count % per) [slots addObject:[NSNull null]];
        [slots addObjectsFromArray:phone];
    } else [slots addObjectsFromArray:self.items];
    NSInteger pages = MAX(1, ((NSInteger)slots.count + per - 1) / per);
    self.scroll.frame = CGRectMake(0, 0, s.width, usableH);
    self.scroll.contentSize = CGSizeMake(s.width * pages, usableH);
    CGFloat gridW = cols * cellW, gridH = rows * cellH + (rows - 1) * gapY;
    for (NSInteger i = 0; i < (NSInteger)slots.count; i++) {
        if (slots[i] == [NSNull null]) continue;
        NSInteger page = i / per, r = (i % per) / cols, c = i % cols;
        // trang chua day van can tu goc tren trai cua luoi (nhu CarPlay)
        CGFloat x0 = page * s.width + (s.width - gridW) / 2, y0 = (usableH - gridH) / 2;
        SCPHomeIconButton *b = SCPHIcon(slots[i], side, names, cellW, hs, self, @selector(iconTapped:));
        b.frame = CGRectMake(x0 + c * cellW, y0 + r * (cellH + gapY), cellW, b.bounds.size.height);
        [self.scroll addSubview:b];
    }
    self.dots.numberOfPages = pages;
    self.dots.frame = CGRectMake(0, usableH, s.width, dotsH);
    [self scrollViewDidScroll:self.scroll];
    SCPLog("HomeScreen: luoi %ld x %ld (chon %@ x %@), %lu o, %ld trang, icon %.0fpt, hinh %@%@%@", (long)cols, (long)rows, hs[@"cols"], hs[@"rows"],
           (unsigned long)slots.count, (long)pages, side, hs[@"shape"], [hs[@"theme"] length] ? [@", goi icon " stringByAppendingString:hs[@"theme"]] : @"",
           [hs[@"phonePage"] boolValue] ? @", trang app iPhone rieng" : @"");
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    [self buildWithSettings:SCPHSettings()];
}
@end

// ---------------------------------------------------------------------
//  Widget: cot the kinh ben trai luoi (toi da 2): dong ho, thoi tiet (Open-Meteo, chung bo nho voi Man hinh khoi dong),
//  nhac dang phat (MediaRemote, nut phat / dung)
// ---------------------------------------------------------------------
#define SCPH_WEATHER_CACHE ROOT_PATH_NS(@"/var/mobile/Library/OmniCar/StartupScreen/weather.plist")   // = SS_WEATHER_CACHE

static NSDictionary *SCPHWeatherCache(void)
{
    NSDictionary *best = nil;
    for (NSString *path in @[SCPH_WEATHER_CACHE, [NSTemporaryDirectory() stringByAppendingPathComponent:@"OmniCarStartupWeather.plist"]]) {
        NSDictionary *w = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![w[@"date"] isKindOfClass:[NSDate class]] || ![w[@"temp"] isKindOfClass:[NSNumber class]]) continue;
        if (!best || [w[@"date"] compare:best[@"date"]] == NSOrderedDescending) best = w;
    }
    return best;
}

// Thoi tiet moi qua 30 phut thi hoi lai Open-Meteo o vi tri cuoi iOS da biet (lam tron 2 so le), luu cung bo nho
static void SCPHWeatherRefresh(void (^done)(NSDictionary *))
{
    NSDictionary *cached = SCPHWeatherCache();
    static NSDate *sAsked;
    if ((cached && -[cached[@"date"] timeIntervalSinceNow] < 1800) || (sAsked && -sAsked.timeIntervalSinceNow < 600)) { done(cached); return; }
    sAsked = [NSDate date];
    CLLocation *loc = nil;
    @try {
        CLLocationManager *m = [CLLocationManager new];
        CLAuthorizationStatus st = m.authorizationStatus;
        if (st == kCLAuthorizationStatusAuthorizedAlways || st == kCLAuthorizationStatusAuthorizedWhenInUse) loc = m.location;
    } @catch (NSException *e) {}
    if (!loc) { SCPLog("HomeScreen: widget thoi tiet: chua co vi tri, dung so cu"); done(cached); return; }
    NSString *q = [NSString stringWithFormat:@"https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f"
                   "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max"
                   "&timezone=auto&forecast_days=1", round(loc.coordinate.latitude * 100) / 100, round(loc.coordinate.longitude * 100) / 100];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 8; cfg.timeoutIntervalForResource = 8;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    [[session dataTaskWithURL:[NSURL URLWithString:q] completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSDictionary *w = nil;
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *cur = [json isKindOfClass:[NSDictionary class]] ? json[@"current"] : nil, *daily = [json isKindOfClass:[NSDictionary class]] ? json[@"daily"] : nil;
        if ([cur isKindOfClass:[NSDictionary class]] && [cur[@"temperature_2m"] isKindOfClass:[NSNumber class]]) {
            NSMutableDictionary *m = [NSMutableDictionary dictionary];
            m[@"temp"] = cur[@"temperature_2m"];
            m[@"code"] = [cur[@"weather_code"] isKindOfClass:[NSNumber class]] ? cur[@"weather_code"] : @0;
            m[@"isDay"] = [cur[@"is_day"] isKindOfClass:[NSNumber class]] ? cur[@"is_day"] : @1;
            if ([daily isKindOfClass:[NSDictionary class]]) {
                for (NSArray *pair in @[@[@"high", @"temperature_2m_max"], @[@"low", @"temperature_2m_min"], @[@"rain", @"precipitation_probability_max"]]) {
                    NSArray *a = daily[pair[1]];
                    if ([a isKindOfClass:[NSArray class]] && [a.firstObject isKindOfClass:[NSNumber class]]) m[pair[0]] = a.firstObject;
                }
            }
            m[@"date"] = [NSDate date];
            w = m;
            [[NSFileManager defaultManager] createDirectoryAtPath:[SCPH_WEATHER_CACHE stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            if (![w writeToURL:[NSURL fileURLWithPath:SCPH_WEATHER_CACHE] error:nil])
                [w writeToURL:[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"OmniCarStartupWeather.plist"]] error:nil];
        }
        SCPLog("HomeScreen: widget thoi tiet %@ (%@)", w ? @"da cap nhat" : @"loi", err.localizedDescription ?: @"ok");
        dispatch_async(dispatch_get_main_queue(), ^{ done(w ?: cached); });
    }] resume];
    [session finishTasksAndInvalidate];
}

static NSString *SCPHWeatherSymbol(NSInteger code, BOOL day)
{
    if (code == 0) return day ? @"sun.max.fill" : @"moon.stars.fill";
    if (code <= 2) return day ? @"cloud.sun.fill" : @"cloud.moon.fill";
    if (code == 3) return @"cloud.fill";
    if (code == 45 || code == 48) return @"cloud.fog.fill";
    if (code >= 51 && code <= 57) return @"cloud.drizzle.fill";
    if (code == 65 || code == 67 || code == 82) return @"cloud.heavyrain.fill";
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return day ? @"cloud.sun.rain.fill" : @"cloud.rain.fill";
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return @"cloud.snow.fill";
    if (code >= 95) return @"cloud.bolt.rain.fill";
    return @"cloud.fill";
}

static NSString *SCPHTemp(NSNumber *celsius)
{
    if (!celsius) return @"—";
    NSMeasurementFormatter *mf = [NSMeasurementFormatter new];
    mf.unitStyle = NSFormattingUnitStyleShort;
    NSNumberFormatter *nf = [NSNumberFormatter new];
    nf.maximumFractionDigits = 0;
    mf.numberFormatter = nf;
    return [mf stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:celsius.doubleValue unit:[NSUnitTemperature celsius]]];
}

// MediaRemote (rieng tu): thong tin bai dang phat + lenh phat / dung
typedef void (*SCPHMRGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef Boolean (*SCPHMRSend)(int, CFDictionaryRef);
typedef void (*SCPHMRRegister)(dispatch_queue_t);
static void *SCPHMediaRemote(const char *sym)
{
    static void *h;
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    return h ? dlsym(h, sym) : NULL;
}

@interface SCPHomeWidgetsView : UIView
@property (nonatomic, copy) NSArray<NSString *> *kinds;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, strong) UILabel *time, *date, *temp, *range, *song, *artist;
@property (nonatomic, strong) UIImageView *sky, *art;
@property (nonatomic, strong) UIButton *play;
@property (nonatomic) BOOL observing;
@property (nonatomic) CGSize builtSize;
@end
@implementation SCPHomeWidgetsView
- (void)dealloc
{
    [_clockTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (UIVisualEffectView *)card:(CGRect)f
{
    UIVisualEffectView *c = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    c.frame = f;
    c.layer.cornerRadius = 20;
    c.layer.cornerCurve = kCACornerCurveContinuous;
    c.clipsToBounds = YES;
    [self addSubview:c];
    return c;
}
- (UILabel *)label:(UIFont *)font alpha:(CGFloat)a in:(UIView *)v frame:(CGRect)f
{
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.font = font;
    l.textColor = [UIColor colorWithWhite:1 alpha:a];
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.6;
    [v addSubview:l];
    return l;
}
- (void)buildKinds:(NSArray<NSString *> *)kinds
{
    if ([kinds isEqualToArray:self.kinds] && CGSizeEqualToSize(self.builtSize, self.bounds.size)) return;
    self.kinds = kinds;
    [self relayout];
}
- (void)relayout
{
    for (UIView *v in [self.subviews copy]) [v removeFromSuperview];
    self.time = self.date = self.temp = self.range = self.song = self.artist = nil;
    self.sky = self.art = nil; self.play = nil;
    CGSize s = self.bounds.size;
    self.builtSize = s;
    NSInteger n = self.kinds.count;
    if (!n || s.width < 60 || s.height < 60) return;
    CGFloat gap = 10, h = (s.height - gap * (n - 1)) / n, w = s.width;
    for (NSInteger i = 0; i < n; i++) {
        NSString *k = self.kinds[i];
        UIView *c = [self card:CGRectMake(0, i * (h + gap), w, h)].contentView;
        CGFloat big = MIN(46, h * 0.42);
        if ([k isEqualToString:@"clock"]) {
            self.time = [self label:[UIFont monospacedDigitSystemFontOfSize:big weight:UIFontWeightSemibold] alpha:1 in:c frame:CGRectMake(16, h / 2 - big * 0.8, w - 32, big * 1.1)];
            self.date = [self label:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium] alpha:0.7 in:c frame:CGRectMake(16, h / 2 + big * 0.35, w - 32, 18)];
        } else if ([k isEqualToString:@"weather"]) {
            self.sky = [[UIImageView alloc] initWithFrame:CGRectMake(16, h / 2 - 22, 44, 44)];
            self.sky.contentMode = UIViewContentModeScaleAspectFit;
            self.sky.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightMedium];
            self.sky.image = [[UIImage systemImageNamed:@"cloud.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            [c addSubview:self.sky];
            self.temp = [self label:[UIFont monospacedDigitSystemFontOfSize:MIN(36, big) weight:UIFontWeightSemibold] alpha:1 in:c frame:CGRectMake(70, h / 2 - 26, w - 84, 34)];
            self.range = [self label:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium] alpha:0.7 in:c frame:CGRectMake(70, h / 2 + 8, w - 84, 18)];
        } else {
            CGFloat a = MIN(56, h - 24);
            self.art = [[UIImageView alloc] initWithFrame:CGRectMake(14, (h - a) / 2, a, a)];
            self.art.layer.cornerRadius = 10;
            self.art.clipsToBounds = YES;
            self.art.contentMode = UIViewContentModeScaleAspectFill;
            self.art.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
            [c addSubview:self.art];
            CGFloat x = 14 + a + 10;
            self.song = [self label:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] alpha:1 in:c frame:CGRectMake(x, h / 2 - 20, w - x - 48, 20)];
            self.artist = [self label:[UIFont systemFontOfSize:13] alpha:0.7 in:c frame:CGRectMake(x, h / 2 + 1, w - x - 48, 18)];
            self.play = [UIButton buttonWithType:UIButtonTypeSystem];
            self.play.frame = CGRectMake(w - 46, h / 2 - 20, 40, 40);
            self.play.tintColor = [UIColor whiteColor];
            [self.play setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold] forImageInState:UIControlStateNormal];
            [self.play addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
            [c addSubview:self.play];
        }
    }
    [self tick];
    [self loadWeather];
    [self loadMusic];
    if (self.art && !self.observing) {
        self.observing = YES;
        SCPHMRRegister reg = (SCPHMRRegister)SCPHMediaRemote("MRMediaRemoteRegisterForNowPlayingNotifications");
        if (reg) reg(dispatch_get_main_queue());
        for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"])
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadMusic) name:name object:nil];
    }
}
- (void)didMoveToWindow
{
    [super didMoveToWindow];
    [self.clockTimer invalidate];
    self.clockTimer = nil;
    if (!self.window) return;
    __weak SCPHomeWidgetsView *weakSelf = self;
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *t) { [weakSelf tick]; }];
    [self tick];
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    if (!CGSizeEqualToSize(self.builtSize, self.bounds.size)) [self relayout];
}
- (void)tick
{
    if (!self.time) return;
    NSDate *now = [NSDate date];
    self.time.text = [NSDateFormatter localizedStringFromDate:now dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEEdMMMM" options:0 locale:[NSLocale currentLocale]];
    self.date.text = [df stringFromDate:now];
    static NSDate *lastWeather;
    if (self.temp && (!lastWeather || -lastWeather.timeIntervalSinceNow > 600)) { lastWeather = now; [self loadWeather]; }
}
- (void)loadWeather
{
    if (!self.temp) return;
    __weak SCPHomeWidgetsView *weakSelf = self;
    SCPHWeatherRefresh(^(NSDictionary *w) {
        SCPHomeWidgetsView *me = weakSelf;
        if (!me.temp) return;
        if (!w) { me.temp.text = @"—"; me.range.text = OMCTr(@"Chưa có thời tiết", @"No weather yet"); return; }
        me.temp.text = SCPHTemp(w[@"temp"]);
        NSMutableArray *parts = [NSMutableArray array];
        if (w[@"high"]) [parts addObject:[@"↑" stringByAppendingString:SCPHTemp(w[@"high"])]];
        if (w[@"low"]) [parts addObject:[@"↓" stringByAppendingString:SCPHTemp(w[@"low"])]];
        if (w[@"rain"]) [parts addObject:[NSString stringWithFormat:@"☂ %@%%", w[@"rain"]]];
        me.range.text = [parts componentsJoinedByString:@"  "];
        UIImage *sym = [UIImage systemImageNamed:SCPHWeatherSymbol([w[@"code"] integerValue], [w[@"isDay"] boolValue])];
        me.sky.image = [sym imageByApplyingSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPaletteColors:@[[UIColor whiteColor], [UIColor systemYellowColor], [UIColor systemCyanColor]]]] ?: sym;
    });
}
- (void)loadMusic
{
    if (!self.art) return;
    SCPHMRGetInfo get = (SCPHMRGetInfo)SCPHMediaRemote("MRMediaRemoteGetNowPlayingInfo");
    if (!get) { self.song.text = OMCTr(@"Không có nhạc", @"Nothing playing"); return; }
    __weak SCPHomeWidgetsView *weakSelf = self;
    get(dispatch_get_main_queue(), ^(CFDictionaryRef ref) {
        SCPHomeWidgetsView *me = weakSelf;
        if (!me.art) return;
        NSDictionary *info = (__bridge NSDictionary *)ref;
        NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"], *artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        BOOL playing = [info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] doubleValue] > 0;
        me.song.text = [title isKindOfClass:[NSString class]] && title.length ? title : OMCTr(@"Không có nhạc", @"Nothing playing");
        me.artist.text = [artist isKindOfClass:[NSString class]] ? artist : @"";
        UIImage *img = [art isKindOfClass:[NSData class]] ? [UIImage imageWithData:art] : nil;
        me.art.image = img;
        me.art.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
        if (!img) { me.art.image = [UIImage systemImageNamed:@"music.note"]; me.art.tintColor = [UIColor colorWithWhite:1 alpha:0.7]; }
        [me.play setImage:[UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill"] forState:UIControlStateNormal];
    });
}
- (void)togglePlay
{
    SCPHMRSend send = (SCPHMRSend)SCPHMediaRemote("MRMediaRemoteSendCommand");
    if (send) send(2, NULL);   // kMRTogglePlayPause
    SCPLog("HomeScreen: widget nhac: phat / dung%@", send ? @"" : @" (khong co MediaRemote)");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self loadMusic]; });
}
@end

// ---------------------------------------------------------------------
//  Man chinh
// ---------------------------------------------------------------------
static const NSInteger kSCPHWallTag = 0x4857, kSCPHGridTag = 0x4847, kSCPHWidgetTag = 0x4858;   // "HW", "HG", "HX"

// O chua cac *IconListView (khung cuon trang icon cua CarPlay): to tien chung gan nhat la UIScrollView, khong thi to
// tien chung cua tat ca icon list. nil = man chinh khong co luoi icon (vd dang o trang khac / iOS khac).
static void SCPHCollectLists(UIView *v, NSMutableArray *out, int depth)
{
    if (!v || depth > 16) return;
    if ([NSStringFromClass([v class]) hasSuffix:@"IconListView"]) { [out addObject:v]; return; }
    for (UIView *c in v.subviews) SCPHCollectLists(c, out, depth + 1);
}

static UIView *SCPHIconContainer(UIView *root)
{
    NSMutableArray<UIView *> *lists = [NSMutableArray array];
    SCPHCollectLists(root, lists, 0);
    if (!lists.count) return nil;
    for (UIView *v = lists.firstObject.superview; v && v != root; v = v.superview) {
        BOOL all = YES;
        for (UIView *l in lists) if (![l isDescendantOfView:v]) { all = NO; break; }
        if (all && [v isKindOfClass:[UIScrollView class]]) return v;
    }
    return lists.count == 1 ? lists.firstObject : lists.firstObject.superview;
}

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

// Moi 30 s khi bat: doi hinh nen ngay / dem, bat / dung video theo dieu kien
static void SCPHStartTicker(void)
{
    static NSTimer *timer;
    if (timer) return;
    timer = [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *t) {
        UIViewController *home = sHomeVC;
        if (home.isViewLoaded && [SCPHSettings()[@"on"] boolValue]) SCPHomeApply(home);
    }];
}

void SCPHomeApply(UIViewController *homeVC)
{
    if (!homeVC.isViewLoaded) return;
    sHomeVC = homeVC;
    UIView *root = homeVC.view;
    NSDictionary *hs = SCPHSettings();
    SCPHomeWallView *wall = (SCPHomeWallView *)[root viewWithTag:kSCPHWallTag];
    SCPHomeGridView *grid = (SCPHomeGridView *)[root viewWithTag:kSCPHGridTag];
    SCPHomeWidgetsView *widgets = (SCPHomeWidgetsView *)[root viewWithTag:kSCPHWidgetTag];
    if (![hs[@"on"] boolValue]) {
        if (wall || grid || SCPHHidden().count) SCPLog("HomeScreen: tat -> tra lai man chinh CarPlay");
        [wall stopVideo];
        [wall removeFromSuperview];
        [grid removeFromSuperview];
        [widgets removeFromSuperview];
        [[root viewWithTag:kSCPHFolderTag] removeFromSuperview];
        SCPHUnhideAll();
        return;
    }
    SCPHStartTicker();
    SCPHLogTreeOnce(root);
    // Hinh nen: lop duoi cung cua man chinh (khong chon: de nguyen hinh nen CarPlay)
    BOOL night = [hs[@"night"] integerValue] > 0 && SCPHIsNight(hs, root.traitCollection);
    NSDictionary *src = SCPHWallSource(hs, night);
    static int lastNight = -1;
    if ([hs[@"night"] integerValue] > 0 && lastNight != night) { lastNight = night; SCPLog("HomeScreen: hinh nen %@", night ? @"dem" : @"ngay"); }
    if (src) {
        if (!wall) {
            wall = [[SCPHomeWallView alloc] initWithFrame:root.bounds];
            wall.tag = kSCPHWallTag;
            wall.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [root insertSubview:wall atIndex:0];
        }
        wall.frame = root.bounds;
        if (root.subviews.firstObject != wall) [root sendSubviewToBack:wall];
        [wall applySettings:hs source:src];
    } else { [wall stopVideo]; [wall removeFromSuperview]; }

    // Luoi: thay cho o chua icon cua CarPlay (o goc chi an)
    UIView *container = grid ? nil : SCPHIconContainer(root);
    static __weak UIView *sContainer;
    if (container) sContainer = container;
    UIView *box = sContainer;
    if (!box || ![box isDescendantOfView:root]) {
        static BOOL warned;
        if (!warned) { warned = YES; SCPLog("HomeScreen: khong thay luoi icon CarPlay (*IconListView) trong man chinh -> chi hinh nen"); }
        [grid removeFromSuperview];
        [widgets removeFromSuperview];
        return;
    }
    NSArray<NSString *> *carplay = SCPCarHomeBundles();
    if (carplay.count < 1) return;   // chua doc duoc thu tu app: de nguyen CarPlay
    SCPHHide(box);
    if (!grid) {
        grid = [[SCPHomeGridView alloc] initWithFrame:CGRectZero];
        grid.tag = kSCPHGridTag;
        [root addSubview:grid];
        SCPLog("HomeScreen: bat, thay luoi %@ %@", NSStringFromClass([box class]), NSStringFromCGRect([root convertRect:box.bounds fromView:box]));
    }
    CGRect f = [root convertRect:box.bounds fromView:box];
    // Widget: cot ben trai vung app (khoang 1/3, 200..280 pt), luoi lui sang phai
    NSArray *kinds = hs[@"widgets"];
    if (kinds.count && f.size.width > 420) {
        CGFloat ww = MIN(280, MAX(200, floor(f.size.width * 0.32)));
        CGRect wf = CGRectMake(f.origin.x + 14, f.origin.y + 14, ww, f.size.height - 28);
        if (!widgets) {
            widgets = [[SCPHomeWidgetsView alloc] initWithFrame:wf];
            widgets.tag = kSCPHWidgetTag;
            [root addSubview:widgets];
            SCPLog("HomeScreen: widget %@", [kinds componentsJoinedByString:@", "]);
        }
        if (!CGRectEqualToRect(widgets.frame, wf)) widgets.frame = wf;
        [widgets buildKinds:kinds];
        f.origin.x += ww + 14; f.size.width -= ww + 14;
    } else [widgets removeFromSuperview];
    if (!CGRectEqualToRect(grid.frame, f)) grid.frame = f;
    NSArray *items = SCPHItems(SCPHApps(carplay, hs), hs);
    if (![items isEqualToArray:grid.items]) grid.items = items;
    [grid setNeedsLayout];
    if ([root viewWithTag:kSCPHFolderTag]) [root bringSubviewToFront:[root viewWithTag:kSCPHFolderTag]];
    else if (root.subviews.lastObject != grid) [root bringSubviewToFront:grid];
    if (widgets && widgets.superview == root) [root insertSubview:widgets belowSubview:grid];
}

void SCPHomeSetVisible(BOOL visible)
{
    if (sHomeVisible == visible) return;
    sHomeVisible = visible;
    UIViewController *home = sHomeVC;
    SCPHomeWallView *wall = home.isViewLoaded ? (SCPHomeWallView *)[home.view viewWithTag:kSCPHWallTag] : nil;
    [wall updatePlayback];
    if (!visible) [[home.view viewWithTag:kSCPHFolderTag] removeFromSuperview];
}

// ---------------------------------------------------------------------
//  Dock: app ghim (HS_KEY_DOCK) thay cho goi y cua CarPlay; khong ghim + tat goi y -> dock trong
// ---------------------------------------------------------------------
static const NSInteger kSCPHDockTag = 0x4844;   // "HD"

@interface SCPHomeDockView : UIView
@property (nonatomic, copy) NSString *builtKey;
@end
@implementation SCPHomeDockView
- (void)iconTapped:(SCPHomeIconButton *)b
{
    SCPHLaunch(b.bundle, "dock");
}
- (void)buildWithApps:(NSArray<NSString *> *)apps settings:(NSDictionary *)hs
{
    CGSize s = self.bounds.size;
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", [apps componentsJoinedByString:@","], NSStringFromCGSize(s),
                     [@[hs[@"shape"], hs[@"glass"], hs[@"shadow"], hs[@"theme"]] componentsJoinedByString:@","]];
    if ([key isEqualToString:self.builtKey]) return;
    self.builtKey = key;
    for (UIView *v in self.subviews) [v removeFromSuperview];
    if (s.width < 20 || s.height < 20) return;
    CGFloat side = MIN(46, s.width - 8), gap = 8;
    NSInteger fit = MAX(0, (NSInteger)floor((s.height + gap) / (side + gap)));
    NSInteger n = MIN((NSInteger)apps.count, fit);
    CGFloat y = (s.height - (n * side + (n - 1) * gap)) / 2;
    for (NSInteger i = 0; i < n; i++) {
        SCPHomeIconButton *b = SCPHIcon(apps[i], side, NO, side, hs, self, @selector(iconTapped:));
        b.frame = CGRectMake((s.width - side) / 2, y + i * (side + gap), side, side);
        [self addSubview:b];
    }
    if (n < (NSInteger)apps.count) SCPLog("HomeScreen: dock chi vua %ld / %lu app ghim", (long)n, (unsigned long)apps.count);
}
@end

void SCPHomeApplyDock(UIViewController *rootVC)
{
    if (!rootVC) return;
    sRootVC = rootVC;
    UIView *dock = nil;
    @try { id dockVC = objcInvoke(rootVC, @"appDockViewController"); dock = dockVC ? objcInvoke(dockVC, @"view") : nil; } @catch (NSException *e) {}
    if (![dock isKindOfClass:[UIView class]]) return;
    NSDictionary *hs = SCPHSettings();
    SCPHomeDockView *mine = (SCPHomeDockView *)[dock viewWithTag:kSCPHDockTag];
    NSMutableArray *pins = [NSMutableArray array];
    NSArray *known = SCPCarHomeBundles();
    for (NSString *b in hs[@"dock"]) if ([b isKindOfClass:[NSString class]] && (!known || [known containsObject:b]) && pins.count < HS_DOCK_MAX) [pins addObject:b];
    BOOL custom = [hs[@"on"] boolValue] && (pins.count || ![hs[@"suggest"] boolValue]);
    if (!custom) {
        if (mine) {
            [mine removeFromSuperview];
            for (UIView *v in dock.subviews) if ([SCPHHidden() containsObject:v]) { v.hidden = NO; [SCPHHidden() removeObject:v]; }
            SCPLog("HomeScreen: dock tra lai goi y cua CarPlay");
        }
        return;
    }
    for (UIView *v in dock.subviews)   // giu nut Split Screen (SCPCButton) neu no nam ngay trong view dock
        if (v != mine && ![NSStringFromClass([v class]) hasPrefix:@"SCP"]) SCPHHide(v);
    if (!mine) {
        mine = [[SCPHomeDockView alloc] initWithFrame:dock.bounds];
        mine.tag = kSCPHDockTag;
        mine.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [dock addSubview:mine];
        SCPLog("HomeScreen: dock tuy chinh %@ (dock %@)", pins, NSStringFromCGRect(dock.bounds));
    }
    mine.frame = dock.bounds;
    [mine buildWithApps:pins settings:hs];
}

void SCPHomeRefresh(void)
{
    sHS = SCPHLoad();
    UIViewController *home = sHomeVC, *root = sRootVC;
    if (home.isViewLoaded) { SCPHomeApply(home); [home.view setNeedsLayout]; }
    if (root) SCPHomeApplyDock(root);
}
