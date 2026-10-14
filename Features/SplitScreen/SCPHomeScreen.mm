#import "SCPHomeScreen.h"
#import "SCPCarSplit.h"
#import <CoreImage/CoreImage.h>

// =====================================================================
//  Man chinh CarPlay cua OmniCar (xem SCPHomeScreen.h). Moi thu tren xe di qua 3 duong da chay that:
//  - thu tu app: model cua *IconListView (SCPCarHomeBundles, nhu bang chon app cua Split Screen)
//  - icon app: SCPCarAppIcon; mo app: SCPCarLaunchApp (DashBoard _launchAppWithInfo:forURL:, app iPhone -> App Bridge)
//  - dock: root VC appDockViewController.view (nhu nut Split Screen)
//  Luoi / dock / hinh nen goc chi bi an (hidden = YES, nho lai de tra), khong sua gi ben trong CarPlay.
//  Lan dau ghi log cay view man chinh de chinh lai neu iOS khac sap xep khac.
// =====================================================================

static NSDictionary *sHS;            // cai dat dang dung (doc lai khi prefschanged)
static __weak UIViewController *sHomeVC, *sRootVC;
static NSHashTable<UIView *> *sHiddenByUs;   // view goc OmniCar da an (de tra lai khi tat)

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
    BOOL wall = [OMCPref(HS_KEY_WALLPAPER, @NO) boolValue] && [[NSFileManager defaultManager] fileExistsAtPath:HS_WALLPAPER_PATH];
    return @{
        @"on": @(OMCEnabled() && [OMCPref(HS_KEY_ENABLED, @NO) boolValue]),
        @"order": arr(HS_KEY_ORDER), @"hidden": arr(HS_KEY_HIDDEN), @"dock": arr(HS_KEY_DOCK),
        @"size": @(num(HS_KEY_ICON_SIZE, 100, 80, 130)), @"cols": @(num(HS_KEY_COLS, 5, 3, 7)), @"rows": @(num(HS_KEY_ROWS, 2, 1, 3)),
        @"gap": @(num(HS_KEY_GAP, 100, 60, 140)), @"names": @([OMCPref(HS_KEY_NAMES, @YES) boolValue]),
        @"wall": @(wall), @"blur": @(num(HS_KEY_BLUR, 0, 0, 30)), @"dim": @(num(HS_KEY_DIM, 25, 0, 70)),
        @"suggest": @([OMCPref(HS_KEY_DOCK_SUGGEST, @YES) boolValue]),
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

// ---------------------------------------------------------------------
//  Hinh nen: anh nguoi dung chon (HS_WALLPAPER_PATH), lam mo bang CIGaussianBlur tren luong phu, phu lop toi
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

@interface SCPHomeWallView : UIView
@property (nonatomic, strong) UIImageView *image;
@property (nonatomic, strong) UIView *dim;
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
- (void)applySettings:(NSDictionary *)hs
{
    self.dim.alpha = [hs[@"dim"] doubleValue] / 100.0;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:HS_WALLPAPER_PATH error:nil];
    NSString *key = [NSString stringWithFormat:@"%@|%@", attrs.fileModificationDate, hs[@"blur"]];
    if ([key isEqualToString:self.loadedKey]) return;
    self.loadedKey = key;
    CGFloat blur = [hs[@"blur"] doubleValue];
    __weak SCPHomeWallView *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *img = [UIImage imageWithContentsOfFile:HS_WALLPAPER_PATH];
        UIImage *done = nil;
        @try { done = SCPHBlurred(img, blur); } @catch (NSException *e) { done = img; }
        dispatch_async(dispatch_get_main_queue(), ^{
            SCPHomeWallView *me = weakSelf;
            if (!me || ![me.loadedKey isEqualToString:key]) return;
            me.image.image = done;
            if (!done) SCPLog("HomeScreen: khong doc duoc hinh nen %@", HS_WALLPAPER_PATH);
        });
    });
}
@end

// ---------------------------------------------------------------------
//  Luoi icon: trang vuot ngang, moi trang cols x rows, icon squircle + ten (tuy chon); cham -> mo app
// ---------------------------------------------------------------------
@interface SCPHomeIconButton : UIButton
@property (nonatomic, copy) NSString *bundle;
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

static SCPHomeIconButton *SCPHIcon(NSString *bid, CGFloat side, BOOL name, CGFloat cellW, id target, SEL action)
{
    CGFloat nameH = name ? 16 : 0;
    SCPHomeIconButton *b = [SCPHomeIconButton buttonWithType:UIButtonTypeCustom];
    b.bundle = bid;
    b.frame = CGRectMake(0, 0, cellW, side + (name ? 4 + nameH : 0));
    UIView *lift = [[UIView alloc] initWithFrame:CGRectMake((cellW - side) / 2, 0, side, side)];   // bong (icon cat bo goc)
    lift.userInteractionEnabled = NO;
    lift.layer.shadowColor = [UIColor blackColor].CGColor;
    lift.layer.shadowOpacity = 0.3; lift.layer.shadowRadius = 6; lift.layer.shadowOffset = CGSizeMake(0, 3);
    lift.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:lift.bounds cornerRadius:side * 0.225].CGPath;
    [b addSubview:lift];
    UIImageView *iv = [[UIImageView alloc] initWithFrame:lift.frame];
    iv.image = SCPCarAppIcon(bid);
    iv.layer.cornerRadius = side * 0.225;
    iv.layer.cornerCurve = kCACornerCurveContinuous;
    iv.clipsToBounds = YES;
    iv.userInteractionEnabled = NO;
    iv.backgroundColor = iv.image ? [UIColor clearColor] : [UIColor colorWithWhite:1 alpha:0.2];
    [b addSubview:iv];
    if (name) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(-2, side + 4, cellW + 4, nameH)];
        l.text = SCPCarAppName(bid);
        l.textColor = [UIColor whiteColor];
        l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        l.textAlignment = NSTextAlignmentCenter;
        l.lineBreakMode = NSLineBreakByTruncatingTail;
        l.layer.shadowColor = [UIColor blackColor].CGColor;
        l.layer.shadowOpacity = 0.6; l.layer.shadowRadius = 2; l.layer.shadowOffset = CGSizeZero;
        l.userInteractionEnabled = NO;
        [b addSubview:l];
    }
    b.accessibilityLabel = SCPCarAppName(bid);
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

@interface SCPHomeGridView : UIView <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIPageControl *dots;
@property (nonatomic, copy) NSArray<NSString *> *apps;
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
    SCPLog("HomeScreen: mo %@", b.bundle);
    @try { SCPCarLaunchApp(b.bundle); } @catch (NSException *e) { SCPLog("HomeScreen: loi mo app %@: %@", b.bundle, e); }
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
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", [self.apps componentsJoinedByString:@","], NSStringFromCGSize(s),
                     [@[hs[@"size"], hs[@"cols"], hs[@"rows"], hs[@"gap"], hs[@"names"]] componentsJoinedByString:@","]];
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
    NSInteger pages = MAX(1, ((NSInteger)self.apps.count + per - 1) / per);
    self.scroll.frame = CGRectMake(0, 0, s.width, usableH);
    self.scroll.contentSize = CGSizeMake(s.width * pages, usableH);
    CGFloat gridW = cols * cellW, gridH = rows * cellH + (rows - 1) * gapY;
    for (NSInteger i = 0; i < (NSInteger)self.apps.count; i++) {
        NSInteger page = i / per, r = (i % per) / cols, c = i % cols;
        // trang chua day van can tu goc tren trai cua luoi (nhu CarPlay)
        CGFloat x0 = page * s.width + (s.width - gridW) / 2, y0 = (usableH - gridH) / 2;
        SCPHomeIconButton *b = SCPHIcon(self.apps[i], side, names, cellW, self, @selector(iconTapped:));
        b.frame = CGRectMake(x0 + c * cellW, y0 + r * (cellH + gapY), cellW, b.bounds.size.height);
        [self.scroll addSubview:b];
    }
    self.dots.numberOfPages = pages;
    self.dots.frame = CGRectMake(0, usableH, s.width, dotsH);
    [self scrollViewDidScroll:self.scroll];
    SCPLog("HomeScreen: luoi %ld x %ld (chon %@ x %@), %lu app, %ld trang, icon %.0fpt", (long)cols, (long)rows, hs[@"cols"], hs[@"rows"],
           (unsigned long)self.apps.count, (long)pages, side);
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    [self buildWithSettings:SCPHSettings()];
}
@end

// ---------------------------------------------------------------------
//  Man chinh
// ---------------------------------------------------------------------
static const NSInteger kSCPHWallTag = 0x4857, kSCPHGridTag = 0x4847;   // "HW", "HG"

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

void SCPHomeApply(UIViewController *homeVC)
{
    if (!homeVC.isViewLoaded) return;
    sHomeVC = homeVC;
    UIView *root = homeVC.view;
    NSDictionary *hs = SCPHSettings();
    SCPHomeWallView *wall = (SCPHomeWallView *)[root viewWithTag:kSCPHWallTag];
    SCPHomeGridView *grid = (SCPHomeGridView *)[root viewWithTag:kSCPHGridTag];
    if (![hs[@"on"] boolValue]) {
        if (wall || grid || SCPHHidden().count) SCPLog("HomeScreen: tat -> tra lai man chinh CarPlay");
        [wall removeFromSuperview];
        [grid removeFromSuperview];
        SCPHUnhideAll();
        return;
    }
    SCPHLogTreeOnce(root);
    // Hinh nen: lop duoi cung cua man chinh (khong chon anh: de nguyen hinh nen CarPlay)
    if ([hs[@"wall"] boolValue]) {
        if (!wall) {
            wall = [[SCPHomeWallView alloc] initWithFrame:root.bounds];
            wall.tag = kSCPHWallTag;
            wall.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [root insertSubview:wall atIndex:0];
        }
        wall.frame = root.bounds;
        if (root.subviews.firstObject != wall) [root sendSubviewToBack:wall];
        [wall applySettings:hs];
    } else [wall removeFromSuperview];

    // Luoi: thay cho o chua icon cua CarPlay (o goc chi an)
    UIView *container = grid ? nil : SCPHIconContainer(root);
    static __weak UIView *sContainer;
    if (container) sContainer = container;
    UIView *box = sContainer;
    if (!box || ![box isDescendantOfView:root]) {
        static BOOL warned;
        if (!warned) { warned = YES; SCPLog("HomeScreen: khong thay luoi icon CarPlay (*IconListView) trong man chinh -> chi hinh nen"); }
        [grid removeFromSuperview];
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
    if (!CGRectEqualToRect(grid.frame, f)) grid.frame = f;
    NSArray *apps = SCPHApps(carplay, hs);
    if (![apps isEqualToArray:grid.apps]) grid.apps = apps;
    [grid setNeedsLayout];
    if (root.subviews.lastObject != grid) [root bringSubviewToFront:grid];
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
    SCPLog("HomeScreen: dock mo %@", b.bundle);
    @try { SCPCarLaunchApp(b.bundle); } @catch (NSException *e) { SCPLog("HomeScreen: loi mo app %@: %@", b.bundle, e); }
}
- (void)buildWithApps:(NSArray<NSString *> *)apps
{
    CGSize s = self.bounds.size;
    NSString *key = [NSString stringWithFormat:@"%@|%@", [apps componentsJoinedByString:@","], NSStringFromCGSize(s)];
    if ([key isEqualToString:self.builtKey]) return;
    self.builtKey = key;
    for (UIView *v in self.subviews) [v removeFromSuperview];
    if (s.width < 20 || s.height < 20) return;
    CGFloat side = MIN(46, s.width - 8), gap = 8;
    NSInteger fit = MAX(0, (NSInteger)floor((s.height + gap) / (side + gap)));
    NSInteger n = MIN((NSInteger)apps.count, fit);
    CGFloat y = (s.height - (n * side + (n - 1) * gap)) / 2;
    for (NSInteger i = 0; i < n; i++) {
        SCPHomeIconButton *b = SCPHIcon(apps[i], side, NO, side, self, @selector(iconTapped:));
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
    [mine buildWithApps:pins];
}

void SCPHomeRefresh(void)
{
    sHS = SCPHLoad();
    UIViewController *home = sHomeVC, *root = sRootVC;
    if (home.isViewLoaded) { SCPHomeApply(home); [home.view setNeedsLayout]; }
    if (root) SCPHomeApplyDock(root);
}
