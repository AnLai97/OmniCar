#import "SPPBubble.h"
#import "SPPPrefs.h"
#import <notify.h>

#define SPP_SPEED_STALE 5.0   // giay khong co so moi -> hien "--" (bong bong van hien)
#define SPP_VALUE_HOLD  3.0   // giay giu so cu khi app tam khong doc duoc (khong nhay qua lai so <-> "--")
#define SPP_SOURCE_GONE 90.0  // giay khong nghe gi tu app (va khong biet app con chay khong) -> an
#define SPP_CAR_GRACE   3.0   // giay mat man xe lien tuc moi chuyen bong bong ve iPhone
#define SPP_SCALE_BASE  0.9   // ti le ung voi 100% trong Cai dat (Kich thuoc tren iPhone / CarPlay)
#define SPP_SIZE_MIN    60.0  // % (Cai dat + chum 2 ngon)
#define SPP_SIZE_MAX    220.0
#define SPP_HOLD_QUIT   2.0   // giay giu bong bong de thoat han app
#define SPP_HOLD_BEGIN  0.2   // giay giu toi thieu truoc khi bat dau dem (de khong nham voi cham / keo)
#define SPP_STYLE_COUNT 18

// ---------------------------------------------------------------------
//  Cua so: man xe (UIRootSceneWindow tren CADisplay cua CarPlay) hoac man iPhone
//  Co che tao cua so tren man xe: theo carplay-cast (EthanArbuckle)
// ---------------------------------------------------------------------

// CADisplay cua man hinh xe (nil neu chua ket noi)
static id SPPGetCarPlayCADisplay(void)
{
    id carplayDevice = objcInvoke(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice");
    if (!carplayDevice) return nil;
    NSArray *screenIDs = objcInvoke(carplayDevice, @"screenIDs");
    if (screenIDs.count == 0) return nil;
    NSString *carplayScreenID = screenIDs[0];
    for (id display in objcInvoke(objc_getClass("CADisplay"), @"displays")) {
        if ([carplayScreenID isEqualToString:objcInvoke(display, @"uniqueId")]) return display;
    }
    return nil;
}

// *scale = so diem anh that tren 1 diem cua man xe (man xe thuong 1x / 2x, khac iPhone 3x)
static UIWindow *SPPMakeCarWindow(CGFloat *scale)
{
    id carDisplay = SPPGetCarPlayCADisplay();
    if (!carDisplay) return nil;
    id displayConfig = objcInvoke_2([objc_getClass("FBSDisplayConfiguration") alloc],
                                    @"initWithCADisplay:isMainDisplay:", carDisplay, 0);
    if (!displayConfig) { SPPLog("khong tao duoc FBSDisplayConfiguration"); return nil; }
    UIWindow *w = objcInvoke_1([objc_getClass("UIRootSceneWindow") alloc], @"initWithDisplayConfiguration:", displayConfig);
    if (![w isKindOfClass:[UIWindow class]]) { SPPLog("khong tao duoc UIRootSceneWindow: %@", w); return nil; }

    CGFloat s = 0;
    if ([displayConfig respondsToSelector:NSSelectorFromString(@"pointScale")]) s = objcInvokeT(displayConfig, @"pointScale", CGFloat);
    if (s < 1) {   // du phong: diem anh cua che do man / kich thuoc cua so (diem)
        id mode = [carDisplay respondsToSelector:NSSelectorFromString(@"currentMode")] ? objcInvoke(carDisplay, @"currentMode") : nil;
        CGFloat px = mode ? MAX(objcInvokeT(mode, @"width", size_t), objcInvokeT(mode, @"height", size_t)) : 0;
        CGFloat pt = MAX(w.bounds.size.width, w.bounds.size.height);
        if (px > 0 && pt > 0) s = round(px / pt * 4) / 4;
    }
    if (s < 1 || s > 4) s = w.screen.scale >= 1 ? w.screen.scale : 2;
    *scale = s;
    SPPLog("man xe: %.0fx%.0f diem, ti le %.2f", w.bounds.size.width, w.bounds.size.height, s);
    return w;
}

static UIWindow *SPPMakePhoneWindow(void)
{
    CGRect sb = [UIScreen mainScreen].bounds;
    UIWindowScene *mainScene = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen == [UIScreen mainScreen]) {
            mainScene = (UIWindowScene *)sc; break;
        }
    }
    UIWindow *w = mainScene ? [[UIWindow alloc] initWithWindowScene:mainScene] : [[UIWindow alloc] initWithFrame:sb];
    w.frame = sb;
    return w;
}

// Tat han process app dan duong ngay (nut X)
static void SPPKillApp(NSString *bid)
{
    id svc = objcInvoke(objc_getClass("FBSSystemService"), @"sharedService");
    SEL sel = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
    if (svc && [svc respondsToSelector:sel]) {
        ((void (*)(id, SEL, id, long long, BOOL, id))objc_msgSend)(svc, sel, bid, 1, NO, @"OmniCar: user closed");
        SPPLog("terminate %@ (FBSSystemService)", bid);
        return;
    }
    void (*fn)(NSString *, int, BOOL, NSString *) =
        (void (*)(NSString *, int, BOOL, NSString *))dlsym(RTLD_DEFAULT, "BKSTerminateApplicationForReasonAndReportWithDescription");
    if (fn) { fn(bid, 1, NO, @"OmniCar"); SPPLog("terminate %@ (BKS)", bid); }
    else SPPLog("khong tim thay API terminate cho %@", bid);
}

// Cua so bong bong phu kin man (de keo tha tu do) nhung PHAI cho cham xuyen qua o moi cho khong co the/nut X.
// Cua so xe la UIRootSceneWindow (class rieng cua SpringBoard) nen khong subclass tinh duoc
// -> tao subclass luc chay va doi class cua instance (object_setClass).
static UIView *SPPPassThroughHitTest(id self, SEL _cmd, CGPoint p, UIEvent *e)
{
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    UIView *v = ((UIView *(*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
    return (v == self) ? nil : v;   // cham vao chinh cua so (khong trung subview) -> bo qua, xuong duoi
}

static void SPPMakeWindowPassThrough(UIWindow *w)
{
    Class base = object_getClass(w);
    NSString *name = [NSString stringWithFormat:@"SPPPassThrough_%@", NSStringFromClass(base)];
    Class cls = objc_getClass(name.UTF8String);
    if (!cls) {
        cls = objc_allocateClassPair(base, name.UTF8String, 0);
        Method m = class_getInstanceMethod(base, @selector(hitTest:withEvent:));
        class_addMethod(cls, @selector(hitTest:withEvent:), (IMP)SPPPassThroughHitTest, method_getTypeEncoding(m));
        objc_registerClassPair(cls);
    }
    object_setClass(w, cls);
}

@interface UIImage (SPPPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end

// Icon cua app (API rieng cua UIKit, co trong SpringBoard); khong lay duoc -> o mau co chu viet tat
static UIImage *SPPAppIcon(int app)
{
    static NSMutableDictionary<NSNumber *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    UIImage *img = cache[@(app)];
    if (img) return img;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        img = [UIImage _applicationIconImageForBundleIdentifier:SPPNavAppBundle(app) format:2 scale:[UIScreen mainScreen].scale];
    if (!img) {
        CGFloat d = 60;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
        img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIColor *bg = app == 1 ? [UIColor colorWithRed:0.0 green:0.6 blue:0.45 alpha:1] : [UIColor colorWithRed:0.1 green:0.4 blue:0.85 alpha:1];
            [bg setFill]; UIRectFill(CGRectMake(0, 0, d, d));
            NSString *t = app == 1 ? @"GO" : @"VM";
            NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy], NSForegroundColorAttributeName: [UIColor whiteColor]};
            CGSize ts = [t sizeWithAttributes:a];
            [t drawAtPoint:CGPointMake((d - ts.width) / 2, (d - ts.height) / 2) withAttributes:a];
        }];
        SPPLog("bubble: khong lay duoc icon %@ -> dung chu viet tat", SPPNavAppBundle(app));
    }
    cache[@(app)] = img;
    return img;
}

// ---------------------------------------------------------------------
//  Thanh phan ve bong bong (mau, font, nen kinh, icon app, bien gioi han)
// ---------------------------------------------------------------------
static UIColor *SPPRGB(int r, int g, int b, CGFloat a) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a]; }
static UIColor *SPPSignRed(void) { return SPPRGB(229, 38, 45, 1); }
static UIColor *SPPRed(void)     { return SPPRGB(255, 69, 58, 1); }
static UIColor *SPPOrange(void)  { return SPPRGB(255, 159, 10, 1); }
static UIColor *SPPGreen(void)   { return SPPRGB(48, 209, 88, 1); }
static UIColor *SPPBlue(void)    { return SPPRGB(10, 132, 255, 1); }
static UIColor *SPPUnitGray(void){ return SPPRGB(235, 235, 245, 0.6); }
static UIColor *SPPHarmonyBlue(void) { return SPPRGB(10, 89, 247, 1); }   // mau thuong hieu HarmonyOS

// Tron 2 mau: t = 0 -> a, 1 -> b
static UIColor *SPPMix(UIColor *a, UIColor *b, CGFloat t)
{
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 1, r2 = 0, g2 = 0, b2 = 0, a2 = 1;
    [a getRed:&r1 green:&g1 blue:&b1 alpha:&a1]; [b getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r1 + (r2 - r1) * t green:g1 + (g2 - g1) * t blue:b1 + (b2 - b1) * t alpha:a1 + (a2 - a1) * t];
}

// So: SF Rounded dam, chu so cung do rong (khong nhay khi doi so)
static UIFont *SPPNumFont(CGFloat size)
{
    UIFont *f = [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
    UIFontDescriptor *d = [f.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded] ?: f.fontDescriptor;
    d = [d fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute:
            @[@{@"CTFeatureTypeIdentifier": @6, @"CTFeatureSelectorIdentifier": @0}]}];   // kNumberSpacingType / kMonospacedNumbersSelector
    return [UIFont fontWithDescriptor:d size:size];
}

static UIFont *SPPUnitFont(CGFloat size)
{
    UIFont *f = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    UIFontDescriptor *d = [f.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded] ?: f.fontDescriptor;
    return [UIFont fontWithDescriptor:d size:size];
}

static UILabel *SPPLabel(UIFont *font, UIColor *color, NSTextAlignment align)
{
    UILabel *l = [[UILabel alloc] init];
    l.font = font; l.textColor = color; l.textAlignment = align;
    l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.6;
    return l;
}

// Nen kinh toi: gradient doc + vien mong + bong do (bong do o view ngoai, gradient cat theo goc bo o layer trong)
@interface SPPGlassView : UIView
@property (nonatomic, strong) CAGradientLayer *fill;
@property (nonatomic, strong) CAGradientLayer *sheen;   // anh sang mem nua tren (do sau cua kinh)
@property (nonatomic) CGFloat corner;
- (void)setTop:(UIColor *)top bottom:(UIColor *)bottom;
@end

@implementation SPPGlassView
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        _fill = [CAGradientLayer layer];
        _fill.masksToBounds = YES;
        _fill.borderWidth = 1;
        _fill.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        if (@available(iOS 13.0, *)) _fill.cornerCurve = kCACornerCurveContinuous;
        [self.layer addSublayer:_fill];
        _sheen = [CAGradientLayer layer];
        _sheen.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.11].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
        [_fill addSublayer:_sheen];
        [self setTop:SPPRGB(34, 36, 46, 0.9) bottom:SPPRGB(14, 15, 20, 0.9)];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35; self.layer.shadowRadius = 6; self.layer.shadowOffset = CGSizeMake(0, 3);
    }
    return self;
}
- (void)setTop:(UIColor *)top bottom:(UIColor *)bottom { self.fill.colors = @[(id)top.CGColor, (id)bottom.CGColor]; }
- (void)setCorner:(CGFloat)corner { _corner = corner; [self setNeedsLayout]; }
- (void)layoutSubviews
{
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.fill.frame = self.bounds;
    self.fill.cornerRadius = self.corner;
    self.sheen.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height * 0.55);
    [CATransaction commit];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.corner].CGPath;
}
@end

// Icon app: o vuong bo goc kieu iOS, vien sang mong, bong do nhe
typedef NS_ENUM(NSInteger, SPPIconShape) {
    SPPIconSquircle = 0,   // o vuong bo goc kieu iOS, co vien + bong
    SPPIconCircle,         // tron (kieu vien thuoc / dong ho)
    SPPIconTile,           // o lon phu kin 1 canh cua the, bo theo goc the (tileCorner + tileMask), khong vien / bong
};

@interface SPPIconView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic) SPPIconShape shape;
@property (nonatomic) CGFloat tileCorner;
@property (nonatomic) CACornerMask tileMask;
@end

@implementation SPPIconView
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        _imageView = [[UIImageView alloc] init];
        _imageView.layer.masksToBounds = YES;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.layer.minificationFilter = kCAFilterTrilinear;   // icon lon thu nho van muot
        _imageView.layer.borderWidth = 0.75;
        _imageView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
        if (@available(iOS 13.0, *)) _imageView.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_imageView];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4; self.layer.shadowRadius = 2.5; self.layer.shadowOffset = CGSizeMake(0, 1.5);
    }
    return self;
}
- (void)setShape:(SPPIconShape)shape { _shape = shape; [self setNeedsLayout]; }
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize sz = self.bounds.size;
    CGFloat r = sz.width * 0.225;
    CACornerMask mask = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    if (self.shape == SPPIconCircle) r = MIN(sz.width, sz.height) / 2;
    else if (self.shape == SPPIconTile) { r = self.tileCorner; mask = self.tileMask; }
    self.imageView.frame = self.bounds;
    self.imageView.layer.cornerRadius = r;
    self.imageView.layer.maskedCorners = mask;
    self.imageView.layer.borderWidth = (self.shape == SPPIconTile) ? 0 : 0.75;
    if (self.shape == SPPIconTile) { self.layer.shadowOpacity = 0; self.layer.shadowPath = nil; }
    else self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:r].CGPath;
}
@end

// Bien gioi han toc do: tron trang, vien do (12% duong kinh), so den dam
@interface SPPSignView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic) BOOL muted;   // khong doc duoc gioi han: vien xam, "--"
@end

@implementation SPPSignView
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor whiteColor];
        self.layer.borderColor = SPPSignRed().CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4; self.layer.shadowRadius = 3; self.layer.shadowOffset = CGSizeMake(0, 1.5);
        _label = SPPLabel(SPPNumFont(20), SPPRGB(20, 20, 20, 1), NSTextAlignmentCenter);
        [self addSubview:_label];
    }
    return self;
}
- (void)setMuted:(BOOL)muted
{
    if (muted == _muted && self.layer.borderColor) return;
    _muted = muted;
    self.layer.borderColor = (muted ? SPPRGB(174, 178, 188, 1) : SPPSignRed()).CGColor;
    self.label.textColor = muted ? SPPRGB(120, 124, 134, 1) : SPPRGB(20, 20, 20, 1);
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat d = self.bounds.size.width, bw = d * 0.12;
    self.layer.cornerRadius = d / 2;
    self.layer.borderWidth = bw;
    self.label.font = SPPNumFont(d * (self.label.text.length >= 3 ? 0.36 : 0.46));
    self.label.frame = CGRectInset(self.bounds, bw * 0.9, bw);
}
@end


@interface SpringBoard : UIApplication
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

@interface SPPBubble ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) SPPGlassView *glass;   // nen kinh cua kieu dang ve
@property (nonatomic, strong) SPPIconView *iconView; // icon app dang cap toc do
@property (nonatomic, strong) SPPSignView *sign;     // bien gioi han toc do
@property (nonatomic, strong) UILabel *speedLabel, *unitLabel;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) int speed, limit;
@property (nonatomic) CFAbsoluteTime lastUpdate;      // ban tin gan nhat tu app nguon (ke ca khi khong co so)
@property (nonatomic) CFAbsoluteTime speedAt, limitAt; // lan cuoi doc duoc toc do / gioi han
@property (nonatomic) CFAbsoluteTime carLostAt;        // luc bat dau mat man xe (0 = dang co)
@property (nonatomic) BOOL onPhone;
@property (nonatomic) CGFloat scale;                 // ti le dang ap = SPP_SCALE_BASE * % trong Cai dat (rieng iPhone / xe)
@property (nonatomic) BOOL pinching;                 // dang chum 2 ngon: khong nap lai ti le tu Cai dat
@property (nonatomic) int app;                       // chi so SPP_NAV_APPS cua app dang cap toc do (cham / X dung app nay)
@property (nonatomic) int iconApp;                   // app dang ve tren iconView (-1 = chua ve)
@property (nonatomic, strong) CAShapeLayer *holdRing;   // giu bong bong: vien do chay quanh, du 3 giay -> thoat app
@property (nonatomic, strong) NSTimer *holdTimer;
@property (nonatomic) CGPoint holdStart;                // diem bat dau giu (keo xa -> chuyen sang di chuyen the)
@property (nonatomic) BOOL holdDragging;
@property (nonatomic) CGRect outlineRect;               // hinh chinh cua kieu dang ve (vien giu chay quanh)
@property (nonatomic) CGFloat outlineCorner;
@property (nonatomic) NSInteger builtStyle;          // kieu dang ve trong the (-1 = chua ve)
@property (nonatomic, strong) CAShapeLayer *gaugeTrack, *gaugeArc;   // kieu Dong ho (gaugeArc = mat na cua gaugeFill)
@property (nonatomic, strong) CAGradientLayer *gaugeFill;            // kieu Dong ho: gradient non xanh -> do
@property (nonatomic, strong) CAShapeLayer *stateRing;               // kieu Dia nho: vien mau trang thai
@property (nonatomic, strong) CAGradientLayer *glow;                 // kieu HUD: anh mau trang thai ben trai
@property (nonatomic, strong) UIView *separator;                     // kieu HUD / Cot doc: vach ngan truoc bien
@property (nonatomic, strong) CALayer *panel;                        // kieu Vien thuoc doi: nua phai mau trang
@property (nonatomic, strong) UIView *meterTrack, *meterFill, *meterMark;   // kieu Thanh do / The HarmonyOS / Live View
@property (nonatomic, strong) UIView *deco;                          // kieu 12..17: lop ve rieng (vanh, lop, vach...) duoi chu
@property (nonatomic, strong) NSMutableDictionary<NSString *, CALayer *> *parts;   // cac lop trong deco theo ten
@property (nonatomic, strong) NSArray<UILabel *> *tickLabels;        // kieu Dong ho kim: so tren mat
@property (nonatomic, strong) UILabel *nameLabel;                    // kieu The HarmonyOS: ten app
@property (nonatomic) CGFloat spinRate;                              // kieu Banh xe: vong/giay dang quay
@property (nonatomic, strong) UIView *flashView;     // nen / quang do nhay khi vuot gioi han (moi kieu)
@property (nonatomic, strong) NSTimer *demoTimer;    // "Xem thu bong bong" trong Cai dat
@property (nonatomic) CGFloat appliedRotation;       // goc xoay dang ap cho cua so tren iPhone
@property (nonatomic) CGFloat displayScale;          // diem anh / diem cua man dang ve (xe hoac iPhone)
@property (nonatomic) CGPoint phoneFraction, carFraction;   // vi tri the theo ti le man (-1 = mac dinh), rieng iPhone / xe
@end

@implementation SPPBubble

+ (instancetype)shared
{
    static SPPBubble *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [SPPBubble new]; s.speed = -1; s.limit = -1; s.builtStyle = -1;
        s.scale = SPP_SCALE_BASE * [SPPPrefs sizePercentForCar:NO] / 100.0;
        s.phoneFraction = CGPointMake(-1, -1); s.carFraction = CGPointMake(-1, -1);
        [s startOrientationTracking];
    });
    return s;
}

// Transform goc cua the = ti le nguoi dung chon (moi animation deu nhan them vao day)
- (CGAffineTransform)baseTransform { return CGAffineTransformMakeScale(self.scale, self.scale); }

// Ti le theo Cai dat cho man dang dung (iPhone / CarPlay)
- (CGFloat)savedScale { return SPP_SCALE_BASE * [SPPPrefs sizePercentForCar:!self.onPhone] / 100.0; }

// Cai dat doi kich thuoc (hoac vua doi man) -> ap ngay
- (void)applySavedScale
{
    CGFloat want = [self savedScale];
    if (self.pinching || self.holdRing || fabs(want - self.scale) < 0.001) return;
    self.scale = want;
    if (self.card) { self.card.transform = [self baseTransform]; [self clampCard]; [self applyCrispScale]; }
}
- (CGAffineTransform)baseScaled:(CGFloat)k { return CGAffineTransformMakeScale(self.scale * k, self.scale * k); }

- (void)updateSpeed:(int)speed limit:(int)limit
{
    [self updateSpeed:speed limit:limit appForeground:NO];
}

- (void)updateSpeed:(int)speed limit:(int)limit appForeground:(BOOL)fg
{
    [self updateSpeed:speed limit:limit appForeground:fg app:self.app];
}

// Trang thai hien/an cua tung app (co the chay ca Vietmap lan GOFA cung luc)
static BOOL sAppFg[8];
static CFAbsoluteTime sAppSeenAt[8];
static CFAbsoluteTime sAppFgSince[8];   // luc app bat dau hien
static BOOL sAppOpened[8];       // app da duoc nguoi dung mo len man hinh (iPhone / CarPlay) tu lan chay nay
static int sPreferredApp = -1;   // app mo gan nhat (nguon uu tien)

// Co app dan duong nao dang hien (va con gui du lieu) -> an bong bong
- (BOOL)anyAppForeground
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < 8; i++) if (sAppFg[i] && now - sAppSeenAt[i] < SPP_SPEED_STALE) return YES;
    return NO;
}

- (void)updateSpeed:(int)speed limit:(int)limit appForeground:(BOOL)fg app:(int)app
{
    app &= 7;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (fg != sAppFg[app]) SPPLog("bubble: %@ %@", SPPNavAppName(app), fg ? @"dang hien -> an bong bong" : @"chay nen -> hien bong bong");
    if (fg && !sAppFg[app]) sAppFgSince[app] = now;
    sAppFg[app] = fg; sAppSeenAt[app] = now;
    // Chi tinh la "da mo" khi app hien lien tuc >= 1.5 giay (bo qua lan active thoang qua luc he thong khoi chay app)
    if (fg && !sAppOpened[app] && now - sAppFgSince[app] >= 1.5) {
        sAppOpened[app] = YES; SPPLog("bubble: %@ da duoc mo", SPPNavAppName(app));
    }
    // App tu chay nen ma chua tung duoc mo (vd he thong danh thuc) -> bo qua, khong hien bong bong
    if (!sAppOpened[app] && !self.demoTimer) return;
    if (fg) sPreferredApp = app;   // app nguoi dung mo gan nhat -> nguon uu tien khi ca 2 app cung chay
    // Giu 1 nguon: chi doi sang app khac khi nguon dang theo im lang (> 2 giay), nguon dang theo khong co so ma app kia
    // co, hoac app kia la app vua mo
    CFAbsoluteTime age = now - self.lastUpdate;
    BOOL accept = (app == self.app) || age > 2.0 || (self.speed < 0 && speed >= 0)
                  || (app == sPreferredApp && self.app != sPreferredApp);
    if (!accept) return;
    // App dang hien khong gianh nguon cua app khac dang chay nen (bong bong van an toi khi het app nao dang hien)
    BOOL otherFresh = app != self.app && !sAppFg[self.app] && age < SPP_SPEED_STALE;
    if (!(fg && otherFresh)) {
        if (app != self.app) {
            SPPLog("bubble: nguon toc do -> %@", SPPNavAppName(app));
            self.speedAt = 0; self.limitAt = 0;   // so cu cua app kia khong giu lai
        }
        self.app = app;
        // Tam khong doc duoc (-1): giu so cu SPP_VALUE_HOLD giay roi moi hien "--"
        if (speed >= 0) { self.speed = speed; self.speedAt = now; }
        else if (now - self.speedAt > SPP_VALUE_HOLD) self.speed = -1;
        if (limit > 0) { self.limit = limit; self.limitAt = now; }
        else if (now - self.limitAt > SPP_VALUE_HOLD) self.limit = -1;
        self.lastUpdate = now;
    }
    [self refresh];
}

// App dang cap toc do con chay khong (SBApplication): 1 = chay (ke ca dang treo nen), 0 = da tat, -1 = khong biet.
// Chi tin ket qua "da tat" sau khi API tung bao "dang chay" trong phien nay - API khac di tren ban iOS khac thi
// khong bao gio an nham bong bong.
static BOOL sSeenRunning[8];

- (int)sourceAppState
{
    int app = self.app & 7;
    id ctl = objcInvoke(objc_getClass("SBApplicationController"), @"sharedInstance");
    id sbApp = ctl ? objcInvoke_1(ctl, @"applicationWithBundleIdentifier:", SPPNavAppBundle(app)) : nil;
    if (!sbApp) return -1;
    BOOL running = YES, known = NO;
    if ([sbApp respondsToSelector:NSSelectorFromString(@"isRunning")]) { running = objcInvokeT(sbApp, @"isRunning", BOOL); known = YES; }
    else if ([sbApp respondsToSelector:NSSelectorFromString(@"processState")]) {
        id ps = objcInvoke(sbApp, @"processState");
        running = ps && (![ps respondsToSelector:NSSelectorFromString(@"isRunning")] || objcInvokeT(ps, @"isRunning", BOOL));
        known = YES;
    }
    if (!known) return -1;
    if (running) { sSeenRunning[app] = YES; return 1; }
    return sSeenRunning[app] ? 0 : -1;
}

// Bong bong chi hien sau khi app dan duong da duoc mo roi chuyen sang chay nen - khong doc duoc so thi hien "--".
// Chi an khi: tat trong Cai dat, app dan duong dang hien, app da bi tat, hoac chua tung / lau qua khong nghe tu app.
- (void)refresh
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - self.speedAt > SPP_SPEED_STALE) self.speed = -1;   // app im lang (bi treo nen...) -> "--"
    if (now - self.limitAt > SPP_SPEED_STALE) self.limit = -1;
    int run = (self.lastUpdate > 0 && !self.demoTimer) ? [self sourceAppState] : 1;
    BOOL alive = self.lastUpdate > 0 && (run == 1 || now - self.lastUpdate < SPP_SOURCE_GONE);
    BOOL show = alive && [SPPPrefs enabled] && ![self anyAppForeground];
    // App vua bi tat (vuot khoi da nhiem / bi he thong dong) -> an ngay
    if (show && run == 0) {
        SPPLog("bubble: %@ da tat -> an bong bong ngay", SPPNavAppName(self.app));
        self.speed = -1; self.limit = -1; self.lastUpdate = 0;
        sAppOpened[self.app & 7] = NO; sAppFg[self.app & 7] = NO;   // lan chay sau phai mo app lai moi hien
        show = NO;
    }
    if (!show) {
        if (self.window && !self.window.hidden)
            SPPLog("bubble: an (ban tin %.1fs truoc, app chay=%d, tat=%d, app dan duong dang hien=%d)",
                   now - self.lastUpdate, run, ![SPPPrefs enabled], [self anyAppForeground]);
        [self hide];
        return;
    }
    [self ensureWindow];
    if (!self.window) return;
    if (self.onPhone) [self applyPhoneOrientationForce:NO];

    [self applySavedScale];
    NSInteger style = [SPPPrefs style];
    if (style != self.builtStyle) [self buildStyle:style];
    // So doi muot: chi dat text, khong animation (cap nhat lien tuc)
    [self renderStyle];
    [self applyCrispScale];

    if (self.window.hidden) {
        self.window.hidden = NO;
        self.card.alpha = 0; self.card.transform = [self baseScaled:0.7];
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0
                         animations:^{ self.card.alpha = 1; self.card.transform = [self baseTransform]; } completion:nil];
    } else if (self.card.alpha < 1 && !self.holdRing) {
        // Dang mo dan (hide) thi co du lieu lai -> hien lai ngay, khong de cua so bi an roi moi hien
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ self.card.alpha = 1; self.card.transform = [self baseTransform]; } completion:nil];
    }
    if (!self.timer) {
        __weak SPPBubble *weakSelf = self;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [weakSelf refresh]; }];
    }
}

- (void)hide
{
    if (self.window && !self.window.hidden) {
        UIView *card = self.card; UIWindow *win = self.window;
        [self cancelHold];
        [UIView animateWithDuration:0.18 animations:^{ card.alpha = 0; card.transform = [self baseScaled:0.8]; }
                         completion:^(BOOL f) { if (card.alpha < 0.01) win.hidden = YES; }];
    }
    [self.timer invalidate]; self.timer = nil;
}

// =====================================================================
//  Cac kieu bong bong (Settings > OmniCar > Speed Bubble > Style). Moi kieu deu co icon app dang cap toc do.
//    0 The ngang     : the kinh toi [icon] [toc do / km/h] [bien gioi han]
//    1 Dia nho       : dia tron, vien mau theo trang thai, icon nho tren so, bien goc tren phai
//    2 Bien bao      : bien gioi han lon + vien toc do (icon + so) o goc duoi phai
//    3 Dong ho       : cung 270 do mau xanh -> cam -> do, icon o khe duoi, bien goc tren phai
//    4 Thanh HUD     : thanh ngang [icon] [so km/h] | [bien], anh mau trang thai ben trai
//    5 Mau toc do    : dia to mau xanh / cam / do, icon nho tren so, bien goc tren phai
//    6 Cot doc       : cot dung [icon] [so / km/h] --- [bien]
//    7 Vien thuoc doi: nua trai mau trang thai (icon + so), nua phai trang (bien)
//    8 Neon          : nen den, so phat sang theo mau trang thai, vien mau
//    9 Thanh do      : [icon] [so km/h] [bien] + thanh tien do, vach o muc gioi han
//   10 Chu noi       : khong nen, so lon co bong, icon + km/h nho, bien ben canh
//   11 The sang      : nhu The ngang nhung nen trang chu toi
//   --- Lay y tuong tu xe hoi, phong cach HarmonyOS ---
//   12 Vo lang       : vanh toi co vung cam mau trang thai, 3 nan, so tren tam vo lang, icon tren nan duoi
//   13 Banh xe       : lop co gai, mam bac 5 chau quay theo toc do, so + icon tren nap giua
//   14 The HarmonyOS : the vuong bo lon gradient xanh (cam / do khi gan / vuot), icon + ten app, so lon, thanh tien do
//   15 Dong ho kim   : mat dong ho 0..160 co vach, cung do tu muc gioi han, kim mau trang thai, icon lam chot kim
//   16 Vong kep      : dia sang, vong ngoai = toc do (gradient xanh -> tim), vong trong = gioi han
//   17 Live View     : vien thuoc den nhu cua so truc tiep, icon + so + thanh tien do mong + bien
// =====================================================================
// 0 = binh thuong, 1 = sap cham gioi han (>= 90%), 2 = vuot
- (int)speedState
{
    if (self.limit <= 0) return 0;
    if (self.speed > self.limit) return 2;
    if (self.speed >= self.limit * 0.9) return 1;
    return 0;
}

- (UIColor *)stateColor
{
    switch ([self speedState]) {
        case 2: return SPPRed();
        case 1: return SPPOrange();
        default: return self.limit > 0 ? SPPGreen() : SPPBlue();
    }
}

// Mau so toc do tren nen toi: trang / cam / do
- (UIColor *)numberColor
{
    switch ([self speedState]) {
        case 2: return SPPRed();
        case 1: return SPPOrange();
        default: return [UIColor whiteColor];
    }
}

- (void)buildStyle:(NSInteger)style
{
    UIView *card = self.card;
    for (UIView *v in [card.subviews copy]) [v removeFromSuperview];
    for (CALayer *l in [card.layer.sublayers copy]) [l removeFromSuperlayer];
    self.glass = nil; self.iconView = nil; self.sign = nil; self.flashView = nil; self.separator = nil;
    self.speedLabel = nil; self.unitLabel = nil;
    self.gaugeTrack = nil; self.gaugeArc = nil; self.gaugeFill = nil; self.stateRing = nil; self.glow = nil;
    self.panel = nil; self.meterTrack = nil; self.meterFill = nil; self.meterMark = nil;
    self.deco = nil; self.parts = nil; self.tickLabels = nil; self.nameLabel = nil; self.spinRate = 0;
    if (style < 0 || style >= SPP_STYLE_COUNT) style = 0;

    UIView *flash = [[UIView alloc] init];
    flash.backgroundColor = SPPRed();
    flash.alpha = 0;
    flash.userInteractionEnabled = NO;
    self.flashView = flash;

    // Nen kinh (kieu 2: chi la vien toc do nho; kieu 10: khong co nen). Kieu tron (1 / 2 / 3 / 5 / 10): quang do nhay
    // quanh hinh chinh (nam sau nen); kieu the / thanh: nhay phu kin nen (tren nen, duoi chu - chu la view them sau)
    SPPGlassView *g = [[SPPGlassView alloc] init];
    BOOL flashInside = (style == 0 || style == 4 || style == 6 || style == 7 || style == 8 || style == 9 || style == 11
                        || style == 14 || style == 17);
    if (flashInside) { [card addSubview:g]; [g addSubview:flash]; }
    else { [card addSubview:flash]; [card addSubview:g]; }
    g.hidden = (style == 10 || style == 12 || style == 13);   // Vo lang / Banh xe tu ve ca hinh
    self.glass = g;
    if (style >= 12) {
        UIView *deco = [[UIView alloc] init];
        deco.userInteractionEnabled = NO;
        [card addSubview:deco];
        self.deco = deco;
        self.parts = [NSMutableDictionary dictionary];
    }

    UIColor *unitColor = SPPUnitGray();
    switch (style) {
    case 0:     // The ngang
        self.speedLabel = SPPLabel(SPPNumFont(30), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(11), unitColor, NSTextAlignmentCenter);
        break;
    case 1: {   // Dia nho
        self.speedLabel = SPPLabel(SPPNumFont(28), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentCenter);
        CAShapeLayer *ring = [CAShapeLayer layer];
        ring.fillColor = [UIColor clearColor].CGColor; ring.lineWidth = 2.5;
        [self.glass.layer addSublayer:ring];
        self.stateRing = ring;
        break;
    }
    case 2:     // Bien bao: vien toc do
        self.speedLabel = SPPLabel(SPPNumFont(20), [UIColor whiteColor], NSTextAlignmentLeft);
        self.unitLabel = SPPLabel(SPPUnitFont(9), unitColor, NSTextAlignmentLeft);
        self.speedLabel.adjustsFontSizeToFitWidth = NO; self.unitLabel.adjustsFontSizeToFitWidth = NO;
        break;
    case 3: {   // Dong ho
        self.speedLabel = SPPLabel(SPPNumFont(32), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentCenter);
        CAShapeLayer *track = [CAShapeLayer layer], *arc = [CAShapeLayer layer];
        for (CAShapeLayer *l in @[track, arc]) { l.fillColor = [UIColor clearColor].CGColor; l.lineWidth = 8; l.lineCap = kCALineCapRound; }
        track.strokeColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        arc.strokeColor = [UIColor blackColor].CGColor;   // chi lam mat na cho gradient
        // Gradient non xanh -> cam -> do chay theo cung (bat dau o 125 do de dau tron cua cung van mau xanh)
        CAGradientLayer *fill = [CAGradientLayer layer];
        fill.type = kCAGradientLayerConic;
        fill.startPoint = CGPointMake(0.5, 0.5);
        fill.endPoint = CGPointMake(0.5 + cos(125 * M_PI / 180), 0.5 + sin(125 * M_PI / 180));
        CGFloat lead = 10.0 / 360, sweep = 270.0 / 360;
        fill.colors = @[(id)SPPGreen().CGColor, (id)SPPGreen().CGColor, (id)SPPOrange().CGColor, (id)SPPRed().CGColor, (id)SPPRed().CGColor];
        fill.locations = @[@0, @(lead), @(lead + sweep * 0.6), @(lead + sweep), @1];
        fill.mask = arc;
        [self.glass.layer addSublayer:track];
        [self.glass.layer addSublayer:fill];
        self.gaugeTrack = track; self.gaugeArc = arc; self.gaugeFill = fill;
        break;
    }
    case 4: {   // Thanh HUD
        self.speedLabel = SPPLabel(SPPNumFont(26), [UIColor whiteColor], NSTextAlignmentRight);
        self.unitLabel = SPPLabel(SPPUnitFont(11), unitColor, NSTextAlignmentLeft);
        CAGradientLayer *glow = [CAGradientLayer layer];
        glow.startPoint = CGPointMake(0, 0.5); glow.endPoint = CGPointMake(1, 0.5);
        [self.glass.fill addSublayer:glow];   // bi cat theo vien bo tron cua nen
        self.glow = glow;
        UIView *sep = [[UIView alloc] init];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        sep.userInteractionEnabled = NO;
        [card addSubview:sep];
        self.separator = sep;
        break;
    }
    case 5:     // Mau toc do
        self.speedLabel = SPPLabel(SPPNumFont(30), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(9.5), [UIColor colorWithWhite:1 alpha:0.85], NSTextAlignmentCenter);
        self.glass.fill.borderWidth = 3;
        self.glass.fill.borderColor = [UIColor whiteColor].CGColor;
        break;
    case 6: {   // Cot doc
        self.speedLabel = SPPLabel(SPPNumFont(30), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentCenter);
        UIView *sep = [[UIView alloc] init];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        sep.userInteractionEnabled = NO;
        [card addSubview:sep];
        self.separator = sep;
        break;
    }
    case 7: {   // Vien thuoc doi
        self.speedLabel = SPPLabel(SPPNumFont(26), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(9.5), [UIColor colorWithWhite:1 alpha:0.85], NSTextAlignmentCenter);
        self.glass.fill.borderWidth = 0;
        CALayer *panel = [CALayer layer];
        panel.backgroundColor = SPPRGB(250, 250, 252, 1).CGColor;
        [self.glass.fill addSublayer:panel];   // bi cat theo vien bo tron cua nen
        self.panel = panel;
        break;
    }
    case 8:     // Neon
        self.speedLabel = SPPLabel(SPPNumFont(32), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(8), unitColor, NSTextAlignmentCenter);
        [self.glass setTop:SPPRGB(6, 6, 10, 0.94) bottom:SPPRGB(2, 2, 4, 0.94)];
        self.glass.fill.borderWidth = 1.5;
        self.speedLabel.layer.shadowOffset = CGSizeZero;
        self.speedLabel.layer.shadowRadius = 6;
        self.speedLabel.layer.shadowOpacity = 1;
        break;
    case 9: {   // Thanh do
        self.speedLabel = SPPLabel(SPPNumFont(30), [UIColor whiteColor], NSTextAlignmentLeft);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentLeft);
        self.speedLabel.adjustsFontSizeToFitWidth = NO;
        UIView *track = [[UIView alloc] init], *fill = [[UIView alloc] init], *mark = [[UIView alloc] init];
        track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
        mark.backgroundColor = [UIColor colorWithWhite:1 alpha:0.92];
        for (UIView *v in @[track, fill, mark]) { v.userInteractionEnabled = NO; [card addSubview:v]; }
        self.meterTrack = track; self.meterFill = fill; self.meterMark = mark;
        break;
    }
    case 10:    // Chu noi: so co bong do de doc duoc tren nen ban do
        self.speedLabel = SPPLabel(SPPNumFont(40), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(11), [UIColor colorWithWhite:1 alpha:0.92], NSTextAlignmentLeft);
        for (UILabel *l in @[self.speedLabel, self.unitLabel]) {
            l.layer.shadowColor = [UIColor blackColor].CGColor;
            l.layer.shadowOffset = CGSizeMake(0, 1); l.layer.shadowRadius = 3; l.layer.shadowOpacity = 0.75;
        }
        break;
    case 11:    // The sang
        self.speedLabel = SPPLabel(SPPNumFont(30), SPPRGB(20, 20, 24, 1), NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(11), SPPRGB(60, 60, 67, 0.6), NSTextAlignmentCenter);
        [self.glass setTop:SPPRGB(255, 255, 255, 0.96) bottom:SPPRGB(238, 239, 243, 0.96)];
        self.glass.fill.borderColor = [UIColor colorWithWhite:0 alpha:0.1].CGColor;
        break;
    case 12: {  // Vo lang
        self.speedLabel = SPPLabel(SPPNumFont(24), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(8), unitColor, NSTextAlignmentCenter);
        self.deco.layer.shadowColor = [UIColor blackColor].CGColor;
        self.deco.layer.shadowOpacity = 0.4; self.deco.layer.shadowRadius = 6; self.deco.layer.shadowOffset = CGSizeMake(0, 3);
        [self shapePart:@"rim" stroke:SPPRGB(28, 30, 36, 1) width:14];
        [self shapePart:@"sheen" stroke:SPPRGB(62, 66, 78, 1) width:14];
        [self shapePart:@"gripL" stroke:SPPGreen() width:14];
        [self shapePart:@"gripR" stroke:SPPGreen() width:14];
        CAShapeLayer *spokes = [self shapePart:@"spokes" stroke:nil width:0];
        spokes.fillColor = SPPRGB(74, 78, 92, 1).CGColor;
        [self gradientPart:@"hub" top:SPPRGB(74, 78, 92, 1) bottom:SPPRGB(24, 26, 32, 1)];
        break;
    }
    case 13: {  // Banh xe
        self.speedLabel = SPPLabel(SPPNumFont(22), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(8), unitColor, NSTextAlignmentCenter);
        self.deco.layer.shadowColor = [UIColor blackColor].CGColor;
        self.deco.layer.shadowOpacity = 0.4; self.deco.layer.shadowRadius = 6; self.deco.layer.shadowOffset = CGSizeMake(0, 3);
        CAShapeLayer *tire = [self shapePart:@"tire" stroke:nil width:0];
        tire.fillColor = SPPRGB(22, 22, 24, 1).CGColor;
        [self shapePart:@"tread" stroke:SPPRGB(50, 50, 55, 1) width:6];
        CAGradientLayer *rim = [self gradientPart:@"rim" top:SPPRGB(214, 218, 226, 1) bottom:SPPRGB(146, 152, 164, 1)];
        rim.type = kCAGradientLayerRadial; rim.startPoint = CGPointMake(0.5, 0.5); rim.endPoint = CGPointMake(1, 1);
        rim.borderWidth = 0;
        CAShapeLayer *well = [self shapePart:@"well" stroke:nil width:0];
        well.fillColor = SPPRGB(40, 42, 48, 1).CGColor;
        CAShapeLayer *spokes = [self shapePart:@"spokes" stroke:nil width:0];
        spokes.fillColor = SPPRGB(198, 202, 212, 1).CGColor;
        CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.fromValue = @0; spin.toValue = @(2 * M_PI); spin.duration = 1; spin.repeatCount = HUGE_VALF;
        spin.removedOnCompletion = NO;
        [spokes addAnimation:spin forKey:@"sppSpin"];
        spokes.speed = 0;   // dung yen toi khi co toc do
        [self shapePart:@"state" stroke:SPPGreen() width:2];
        [self gradientPart:@"cap" top:SPPRGB(60, 64, 76, 1) bottom:SPPRGB(20, 22, 26, 1)];
        break;
    }
    case 14: {  // The HarmonyOS
        self.speedLabel = SPPLabel(SPPNumFont(44), [UIColor whiteColor], NSTextAlignmentLeft);
        self.unitLabel = SPPLabel(SPPUnitFont(12), [UIColor colorWithWhite:1 alpha:0.8], NSTextAlignmentLeft);
        self.speedLabel.adjustsFontSizeToFitWidth = NO;
        self.glass.fill.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
        UILabel *name = SPPLabel(SPPUnitFont(11), [UIColor colorWithWhite:1 alpha:0.92], NSTextAlignmentLeft);
        [card addSubview:name];
        self.nameLabel = name;
        UIView *track = [[UIView alloc] init], *fill = [[UIView alloc] init];
        track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
        fill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.95];
        for (UIView *v in @[track, fill]) { v.userInteractionEnabled = NO; [card addSubview:v]; }
        self.meterTrack = track; self.meterFill = fill;
        break;
    }
    case 15: {  // Dong ho kim
        self.speedLabel = SPPLabel(SPPNumFont(20), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(8), unitColor, NSTextAlignmentCenter);
        [self shapePart:@"minor" stroke:[UIColor colorWithWhite:1 alpha:0.42] width:1.2];
        [self shapePart:@"major" stroke:[UIColor colorWithWhite:1 alpha:0.86] width:2];
        [self shapePart:@"zone" stroke:[SPPRed() colorWithAlphaComponent:0.9] width:3];
        CAShapeLayer *needle = [self shapePart:@"needle" stroke:SPPGreen() width:3];
        needle.lineCap = kCALineCapRound;
        NSMutableArray *labels = [NSMutableArray array];
        for (int v = 0; v <= 160; v += 40) {
            UILabel *l = SPPLabel(SPPUnitFont(7.5), SPPRGB(235, 235, 245, 0.66), NSTextAlignmentCenter);
            l.text = [NSString stringWithFormat:@"%d", v];
            [self.deco addSubview:l];
            [labels addObject:l];
        }
        self.tickLabels = labels;
        break;
    }
    case 16: {  // Vong kep
        self.speedLabel = SPPLabel(SPPNumFont(22), SPPRGB(20, 20, 26, 1), NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(9), SPPRGB(60, 60, 67, 0.6), NSTextAlignmentCenter);
        [self.glass setTop:SPPRGB(250, 250, 252, 0.96) bottom:SPPRGB(232, 236, 245, 0.96)];
        self.glass.fill.borderColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
        [self shapePart:@"outerTrack" stroke:[SPPHarmonyBlue() colorWithAlphaComponent:0.14] width:9];
        CAGradientLayer *outer = [self gradientPart:@"outerFill" top:SPPHarmonyBlue() bottom:SPPRGB(140, 80, 255, 1)];
        outer.type = kCAGradientLayerConic; outer.startPoint = CGPointMake(0.5, 0.5); outer.endPoint = CGPointMake(0.5, 0);
        outer.borderWidth = 0; outer.masksToBounds = NO; outer.cornerRadius = 0;
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.fillColor = [UIColor clearColor].CGColor; mask.strokeColor = [UIColor blackColor].CGColor;
        mask.lineWidth = 9; mask.lineCap = kCALineCapRound;
        outer.mask = mask;
        self.parts[@"outerMask"] = mask;
        [self shapePart:@"innerTrack" stroke:[SPPRed() colorWithAlphaComponent:0.12] width:7];
        CAShapeLayer *inner = [self shapePart:@"innerFill" stroke:SPPRed() width:7];
        inner.lineCap = kCALineCapRound;
        break;
    }
    case 17: {  // Live View
        self.speedLabel = SPPLabel(SPPNumFont(24), [UIColor whiteColor], NSTextAlignmentLeft);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentLeft);
        self.speedLabel.adjustsFontSizeToFitWidth = NO;
        [self.glass setTop:SPPRGB(0, 0, 0, 0.97) bottom:SPPRGB(0, 0, 0, 0.97)];
        self.glass.fill.borderColor = [UIColor colorWithWhite:1 alpha:0.1].CGColor;
        UIView *track = [[UIView alloc] init], *fill = [[UIView alloc] init];
        track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        for (UIView *v in @[track, fill]) { v.userInteractionEnabled = NO; [card addSubview:v]; }
        self.meterTrack = track; self.meterFill = fill;
        break;
    }
    }
    // Co so toc do theo kieu: du lon de doc khi lai xe (o 100% ~ 26..43pt tren man)
    static const CGFloat kSpeedFont[SPP_STYLE_COUNT] = {34, 32, 29, 36, 32, 34, 36, 32, 38, 34, 46, 34, 28, 26, 48, 26, 28, 30};
    self.speedLabel.font = SPPNumFont(kSpeedFont[style]);
    self.unitLabel.text = (style == 8) ? @"KM/H" : @"km/h";
    [card addSubview:self.speedLabel];
    [card addSubview:self.unitLabel];
    self.sign = [[SPPSignView alloc] init];
    [card addSubview:self.sign];
    self.iconView = [[SPPIconView alloc] init];
    // Dang logo (nho, khong lan at so): kieu vien thuoc / dong ho = tron; con lai = o bo goc iOS
    switch (style) {
    case 2: case 3: case 4: case 7: case 8: case 10: case 12: case 13: case 15: case 17: self.iconView.shape = SPPIconCircle; break;
    default: self.iconView.shape = SPPIconSquircle; break;
    }
    [card addSubview:self.iconView];
    self.iconApp = -1;
    self.builtStyle = style;
    SPPLog("bubble: kieu %ld", (long)style);
}

// Lop ve rieng trong deco (thu tu tao = thu tu chong)
- (CAShapeLayer *)shapePart:(NSString *)key stroke:(UIColor *)stroke width:(CGFloat)w
{
    CAShapeLayer *l = [CAShapeLayer layer];
    l.fillColor = [UIColor clearColor].CGColor;
    l.strokeColor = stroke.CGColor;
    l.lineWidth = w;
    [self.deco.layer addSublayer:l];
    self.parts[key] = l;
    return l;
}

// Hinh tron gradient (tam vo lang, nap banh xe, mam...): dat frame + cornerRadius khi ve
- (CAGradientLayer *)gradientPart:(NSString *)key top:(UIColor *)top bottom:(UIColor *)bottom
{
    CAGradientLayer *g = [CAGradientLayer layer];
    g.colors = @[(id)top.CGColor, (id)bottom.CGColor];
    g.masksToBounds = YES;
    g.borderWidth = 1; g.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
    [self.deco.layer addSublayer:g];
    self.parts[key] = g;
    return g;
}

static UIBezierPath *SPPCircle(CGPoint c, CGFloat r) { return [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0 endAngle:2 * M_PI clockwise:YES]; }
static UIBezierPath *SPPArc(CGPoint c, CGFloat r, CGFloat deg0, CGFloat deg1)
{
    return [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:deg0 * M_PI / 180 endAngle:deg1 * M_PI / 180 clockwise:YES];
}
static void SPPCirclePart(CALayer *l, CGPoint c, CGFloat r)
{
    l.frame = CGRectMake(c.x - r, c.y - r, 2 * r, 2 * r);
    l.cornerRadius = r;
}

// Kieu Banh xe: doi toc do quay cua mam ma khong giat (doi speed cua lop, giu nguyen goc hien tai)
- (void)setSpin:(CGFloat)rate
{
    CALayer *l = self.parts[@"spokes"];
    if (!l || fabs(rate - self.spinRate) < 0.02) return;
    CFTimeInterval now = CACurrentMediaTime();
    l.timeOffset = [l convertTime:now fromLayer:nil];
    l.beginTime = now;
    l.speed = rate;
    self.spinRate = rate;
}

// Vuot gioi han (moi kieu): nen / quang do nhay, bien gioi han dap theo nhip
- (void)setOverLimitWarning:(BOOL)on
{
    UIView *f = self.flashView;
    BOOL running = [f.layer animationForKey:@"sppFlash"] != nil;
    if (on == running) return;
    if (on) {
        CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
        blink.fromValue = @0.0; blink.toValue = @0.55;
        blink.duration = 0.35; blink.autoreverses = YES; blink.repeatCount = HUGE_VALF;
        blink.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        f.alpha = 1; f.layer.opacity = 0;
        [f.layer addAnimation:blink forKey:@"sppFlash"];
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @1.0; pulse.toValue = @1.15;
        pulse.duration = 0.35; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
        [self.sign.layer addAnimation:pulse forKey:@"sppPulse"];
        SPPLog("bubble: vuot gioi han -> nhay canh bao");
    } else {
        [f.layer removeAnimationForKey:@"sppFlash"];
        f.alpha = 0;
        [self.sign.layer removeAnimationForKey:@"sppPulse"];
    }
}

// Mau so theo kieu: nen mau (5, 7) -> trang; Neon -> mau trang thai nhat; nen sang (11) -> toi / cam / do
- (UIColor *)numberColorForStyle:(NSInteger)style
{
    int st = [self speedState];
    switch (style) {
    case 5: case 7: case 14: return [UIColor whiteColor];
    case 8: return SPPMix([self stateColor], [UIColor whiteColor], 0.55);
    case 11: case 16: return st == 2 ? SPPRed() : (st == 1 ? SPPRGB(230, 130, 0, 1) : SPPRGB(20, 20, 24, 1));
    default: return [self numberColor];
    }
}

// km/h cung dong day (baseline) voi so toc do dang can giua theo chieu doc tai midY
static void SPPAlignUnit(UILabel *unit, UILabel *number, CGFloat x, CGFloat midY, CGFloat w)
{
    CGFloat base = midY + number.font.capHeight / 2;
    unit.frame = CGRectMake(x, base - unit.font.ascender, w, unit.font.lineHeight);
}

static void SPPPlace(UIView *v, CGFloat cx, CGFloat cy, CGFloat size)
{
    v.bounds = CGRectMake(0, 0, size, size);
    v.center = CGPointMake(cx, cy);
    [v setNeedsLayout];
}

// Dat so + mau + bo cuc theo kieu, giu tam the co dinh
- (void)renderStyle
{
    BOOL hasLimit = self.limit > 0;
    const BOOL withSign = YES;   // bien luon co cho (khong co gioi han -> "--" mau xam), the khong doi kich thuoc
    BOOL showIcon = [SPPPrefs showAppIcon];
    int state = [self speedState];
    UIColor *sc = [self stateColor];
    self.speedLabel.text = self.speed >= 0 ? [NSString stringWithFormat:@"%d", self.speed] : @"--";
    self.speedLabel.textColor = [self numberColorForStyle:self.builtStyle];
    self.sign.label.text = hasLimit ? [NSString stringWithFormat:@"%d", self.limit] : @"--";
    self.sign.muted = !hasLimit;
    self.sign.hidden = NO;
    self.iconView.hidden = !showIcon;
    if (showIcon && self.iconApp != self.app) { self.iconView.imageView.image = SPPAppIcon(self.app); self.iconApp = self.app; }

    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGPoint c = self.card.center;
    CGSize size;
    UIView *halo = nil;   // hinh chinh de ve quang do nhay xung quanh (nil = nhay trong nen)
    switch (self.builtStyle) {
    case 1: {   // Dia nho: logo o vi tri 12 gio, so o giua
        CGFloat d = 80, r = d / 2, sg = 62;
        size = CGSizeMake(withSign ? d + 6 + sg : d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        self.stateRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, d - 6, d - 6)].CGPath;
        self.stateRing.strokeColor = sc.CGColor;
        CGFloat dy = showIcon ? 0 : -7;
        SPPPlace(self.iconView, r, 19, 16);
        self.speedLabel.frame = CGRectMake(6, 28 + dy, d - 12, 36);
        self.unitLabel.frame = CGRectMake(9, 61 + dy, d - 18, 12);
        SPPPlace(self.sign, d + 6 + sg / 2, r, sg);
        halo = self.glass;
        break;
    }
    case 2: {   // Bien bao
        CGFloat sd = 78, ch = 52;
        CGFloat ic = showIcon ? 22 : 0;
        self.speedLabel.font = SPPNumFont(ch * 0.56);
        self.unitLabel.font = SPPUnitFont(ch * 0.26);
        CGFloat nw = ceil([self.speedLabel sizeThatFits:CGSizeMake(200, ch)].width);
        CGFloat uw = ceil([self.unitLabel sizeThatFits:CGSizeMake(200, ch)].width);
        CGFloat cw = (showIcon ? 12 + ic + 6 : 12) + nw + 14;   // khong hien km/h
        CGFloat x = withSign ? sd - 28 : 0, y = withSign ? sd - 24 : 0;
        if (withSign) SPPPlace(self.sign, sd / 2, sd / 2, sd);
        self.glass.frame = CGRectMake(x, y, cw, ch); self.glass.corner = ch / 2;
        if (showIcon) SPPPlace(self.iconView, x + 12 + ic / 2, y + ch / 2, ic);
        CGFloat tx = x + (showIcon ? 12 + ic + 6 : 12);
        self.speedLabel.frame = CGRectMake(tx, y, nw, ch);
        SPPAlignUnit(self.unitLabel, self.speedLabel, tx + nw + 3, y + ch / 2, uw);
        size = CGSizeMake(MAX(x + cw, withSign ? sd : 0), y + ch);
        halo = withSign ? self.sign : self.glass;
        break;
    }
    case 3: {   // Dong ho
        CGFloat d = 108, r = d / 2, sg = 80;
        size = CGSizeMake(withSign ? d + 6 + sg : d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(r, r) radius:r - 11
                                                        startAngle:M_PI * 0.75 endAngle:M_PI * 2.25 clockwise:YES];
        self.gaugeTrack.path = path.CGPath; self.gaugeArc.path = path.CGPath;
        self.gaugeTrack.frame = CGRectMake(0, 0, d, d); self.gaugeFill.frame = CGRectMake(0, 0, d, d);
        self.gaugeArc.frame = self.gaugeFill.bounds;
        CGFloat maxV = hasLimit ? MAX(self.limit * 1.4, 40) : 140;
        [CATransaction setDisableActions:NO]; [CATransaction setAnimationDuration:0.4];
        self.gaugeArc.strokeEnd = MIN(1.0, MAX(0.0, self.speed / maxV));
        [CATransaction setDisableActions:YES];
        self.speedLabel.frame = CGRectMake(12, 28, d - 24, 44);
        self.unitLabel.frame = CGRectMake(16, 68, d - 32, 12);
        SPPPlace(self.iconView, r, d - 15, 18);
        SPPPlace(self.sign, d + 6 + sg / 2, r, sg);
        halo = self.glass;
        break;
    }
    case 4: {   // Thanh HUD
        CGFloat h = 52, x = showIcon ? 14 + 24 + 8 : 16, sg = 46;
        CGFloat sx = x + 54 + 10;   // khong hien km/h
        size = CGSizeMake(withSign ? sx + 8 + sg + 3 : sx, h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = h / 2;
        self.glow.frame = CGRectMake(0, 0, 110, h);
        self.glow.colors = @[(id)[sc colorWithAlphaComponent:0.34].CGColor, (id)[sc colorWithAlphaComponent:0].CGColor];
        SPPPlace(self.iconView, 14 + 12, h / 2, 24);
        self.speedLabel.frame = CGRectMake(x, 4, 54, h - 8);
        SPPAlignUnit(self.unitLabel, self.speedLabel, x + 58, h / 2, 30);
        self.separator.hidden = !withSign;
        self.separator.frame = CGRectMake(sx, 12, 1, h - 24);
        SPPPlace(self.sign, sx + 8 + sg / 2, h / 2, sg);
        break;
    }
    case 5: {   // Mau toc do: icon nho ben trong, tren so
        CGFloat d = 86, r = d / 2, sg = 66;
        size = CGSizeMake(withSign ? d + 6 + sg : d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        CGFloat hh, ss, bb, aa;
        UIColor *top = sc, *bottom = sc;
        if ([sc getHue:&hh saturation:&ss brightness:&bb alpha:&aa]) {
            top = [UIColor colorWithHue:hh saturation:ss * 0.8 brightness:MIN(1, bb * 1.12) alpha:1];
            bottom = [UIColor colorWithHue:hh saturation:MIN(1, ss * 1.05) brightness:bb * 0.72 alpha:1];
        }
        [self.glass setTop:top bottom:bottom];
        CGFloat dy = showIcon ? 0 : -7;
        SPPPlace(self.iconView, r, 19, 16);
        self.speedLabel.frame = CGRectMake(7, 29 + dy, d - 14, 40);
        self.unitLabel.frame = CGRectMake(10, 66 + dy, d - 20, 12);
        SPPPlace(self.sign, d + 6 + sg / 2, r, sg);
        halo = self.glass;
        break;
    }
    case 6: {   // Cot doc
        CGFloat w = 74, top = showIcon ? 12 + 24 + 4 : 12;
        CGFloat y2 = top + 40 + 12;
        size = CGSizeMake(w, withSign ? y2 + 8 + 60 + 7 : y2 + 2);
        self.glass.frame = CGRectMake(0, 0, w, size.height); self.glass.corner = 22;
        SPPPlace(self.iconView, w / 2, 12 + 12, 24);
        self.speedLabel.frame = CGRectMake(4, top - 3, w - 8, 42);
        self.unitLabel.frame = CGRectMake(5, top + 36, w - 10, 13);
        self.separator.hidden = !withSign;
        self.separator.frame = CGRectMake(14, y2, w - 28, 1);
        SPPPlace(self.sign, w / 2, y2 + 8 + 30, 60);
        break;
    }
    case 7: {   // Vien thuoc doi
        CGFloat h = 58, x = showIcon ? 12 + 26 + 6 : 14;
        CGFloat lw = x + 58 + 12, rw = withSign ? 68 : 0;
        size = CGSizeMake(lw + rw, h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = h / 2;
        CGFloat hh, ss, bb, aa;
        UIColor *top = sc, *bottom = sc;
        if ([sc getHue:&hh saturation:&ss brightness:&bb alpha:&aa]) {
            top = [UIColor colorWithHue:hh saturation:ss * 0.85 brightness:MIN(1, bb * 1.1) alpha:1];
            bottom = [UIColor colorWithHue:hh saturation:MIN(1, ss * 1.05) brightness:bb * 0.75 alpha:1];
        }
        [self.glass setTop:top bottom:bottom];
        self.panel.hidden = !withSign;
        self.panel.frame = CGRectMake(lw, 0, rw, h);
        SPPPlace(self.iconView, 12 + 13, h / 2, 26);
        self.speedLabel.frame = CGRectMake(x, 4, 58, 38);
        self.unitLabel.frame = CGRectMake(x, 41, 58, 12);
        SPPPlace(self.sign, lw + rw / 2 - 3, h / 2, 52);
        break;
    }
    case 8: {   // Neon
        CGFloat h = 62, x = showIcon ? 12 + 24 + 8 : 12;
        size = CGSizeMake(x + 72 + (withSign ? 6 + 54 + 5 : 12), h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = 18;
        self.iconView.layer.shadowColor = sc.CGColor;
        self.iconView.layer.shadowRadius = 6; self.iconView.layer.shadowOpacity = 0.95; self.iconView.layer.shadowOffset = CGSizeZero;
        self.glass.fill.borderColor = [sc colorWithAlphaComponent:0.8].CGColor;
        self.speedLabel.layer.shadowColor = sc.CGColor;
        self.unitLabel.textColor = sc;
        SPPPlace(self.iconView, 12 + 12, h / 2, 24);
        self.speedLabel.frame = CGRectMake(x, 4, 72, 44);
        self.unitLabel.frame = CGRectMake(x, h - 15, 72, 11);
        SPPPlace(self.sign, size.width - 5 - 27, h / 2, 54);
        break;
    }
    case 9: {   // Thanh do
        CGFloat h = 74, x = showIcon ? 12 + 24 + 8 : 14, mid = 29;
        size = CGSizeMake(x + 66 + (withSign ? 8 + 54 + 8 : 10), h);   // khong hien km/h
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = 18;
        SPPPlace(self.iconView, 12 + 12, mid, 24);
        CGFloat nw = ceil([self.speedLabel sizeThatFits:CGSizeMake(200, 44)].width);
        self.speedLabel.frame = CGRectMake(x, mid - 21, nw, 42);
        SPPAlignUnit(self.unitLabel, self.speedLabel, x + nw + 3, mid, 34);
        SPPPlace(self.sign, size.width - 8 - 27, mid + 1, 54);
        CGFloat bx = 12, bw = size.width - 24, by = h - 16;
        CGFloat maxV = hasLimit ? self.limit * 1.3 : 140;
        self.meterTrack.frame = CGRectMake(bx, by, bw, 6);
        self.meterTrack.layer.cornerRadius = 3;
        self.meterFill.layer.cornerRadius = 3;
        self.meterFill.backgroundColor = sc;
        [CATransaction setDisableActions:NO];
        [UIView animateWithDuration:0.35 animations:^{
            self.meterFill.frame = CGRectMake(bx, by, MAX(6, bw * MIN(1.0, self.speed / maxV)), 6);
        }];
        [CATransaction setDisableActions:YES];
        self.meterMark.hidden = !hasLimit;
        self.meterMark.frame = CGRectMake(bx + bw * (self.limit / maxV) - 1.25, by - 3, 2.5, 12);
        self.meterMark.layer.cornerRadius = 1.25;
        break;
    }
    case 10: {  // Chu noi
        CGFloat nw = 76;
        size = CGSizeMake(withSign ? nw + 8 + 58 : nw, 76);
        SPPPlace(self.iconView, 13, 65, 15);
        self.speedLabel.frame = CGRectMake(0, 0, nw, 56);
        self.unitLabel.frame = showIcon ? CGRectMake(26, 58, 46, 14) : CGRectMake(8, 58, 60, 14);
        self.unitLabel.textAlignment = showIcon ? NSTextAlignmentLeft : NSTextAlignmentCenter;
        SPPPlace(self.sign, nw + 8 + 29, 34, 58);
        halo = self.speedLabel;
        break;
    }
    case 12: {  // Vo lang
        CGFloat d = 112, r = d / 2, sg = 80; CGPoint m = CGPointMake(r, r);
        size = CGSizeMake(withSign ? d + 6 + sg : d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        self.deco.frame = self.glass.frame;
        self.deco.layer.shadowPath = SPPCircle(m, r).CGPath;
        ((CAShapeLayer *)self.parts[@"rim"]).path = SPPCircle(m, r - 7).CGPath;
        ((CAShapeLayer *)self.parts[@"sheen"]).path = SPPArc(m, r - 7, 200, 340).CGPath;
        ((CAShapeLayer *)self.parts[@"gripL"]).path = SPPArc(m, r - 7, 205, 245).CGPath;
        ((CAShapeLayer *)self.parts[@"gripR"]).path = SPPArc(m, r - 7, 295, 335).CGPath;
        ((CAShapeLayer *)self.parts[@"gripL"]).strokeColor = sc.CGColor;
        ((CAShapeLayer *)self.parts[@"gripR"]).strokeColor = sc.CGColor;
        UIBezierPath *sp = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(r - 43, r - 4, 16, 12) cornerRadius:4];
        [sp appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(r + 27, r - 4, 16, 12) cornerRadius:4]];
        [sp appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(r - 7, r + 27, 14, 16) cornerRadius:4]];
        ((CAShapeLayer *)self.parts[@"spokes"]).path = sp.CGPath;
        SPPCirclePart(self.parts[@"hub"], m, 30);
        self.speedLabel.frame = CGRectMake(r - 30, r - 21, 60, 34);
        self.unitLabel.frame = CGRectMake(r - 30, r + 11, 60, 11);
        SPPPlace(self.iconView, r, r + 40, 16);
        SPPPlace(self.sign, d + 6 + sg / 2, r, sg);
        halo = self.glass;
        break;
    }
    case 13: {  // Banh xe
        CGFloat d = 112, r = d / 2, sg = 80; CGPoint m = CGPointMake(r, r);
        size = CGSizeMake(withSign ? d + 6 + sg : d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        self.deco.frame = self.glass.frame;
        self.deco.layer.shadowPath = SPPCircle(m, r).CGPath;
        ((CAShapeLayer *)self.parts[@"tire"]).path = SPPCircle(m, r).CGPath;
        CAShapeLayer *tread = (CAShapeLayer *)self.parts[@"tread"];
        tread.path = SPPCircle(m, r - 4).CGPath;
        CGFloat period = 2 * M_PI * (r - 4) / 28;
        tread.lineDashPattern = @[@2.5, @(period - 2.5)];
        SPPCirclePart(self.parts[@"rim"], m, r - 12);
        ((CAShapeLayer *)self.parts[@"well"]).path = SPPCircle(m, r - 17).CGPath;
        // 5 chau mam (hinh thang tu ban kinh 30 toi r - 18), ve trong lop phu kin dia de quay quanh tam
        CAShapeLayer *spokes = (CAShapeLayer *)self.parts[@"spokes"];
        spokes.frame = CGRectMake(0, 0, d, d);
        UIBezierPath *sp = [UIBezierPath bezierPath];
        for (int i = 0; i < 5; i++) {
            CGFloat a = (i * 72 - 90) * M_PI / 180, r0 = 30, r1 = r - 18;
            CGFloat w0 = 9 * M_PI / 180, w1 = w0 * r0 / r1 * 0.6;
            [sp moveToPoint:CGPointMake(r + r0 * cos(a - w0), r + r0 * sin(a - w0))];
            [sp addLineToPoint:CGPointMake(r + r0 * cos(a + w0), r + r0 * sin(a + w0))];
            [sp addLineToPoint:CGPointMake(r + r1 * cos(a + w1), r + r1 * sin(a + w1))];
            [sp addLineToPoint:CGPointMake(r + r1 * cos(a - w1), r + r1 * sin(a - w1))];
            [sp closePath];
        }
        spokes.path = sp.CGPath;
        CAShapeLayer *st = (CAShapeLayer *)self.parts[@"state"];
        st.path = SPPCircle(m, r - 12.5).CGPath;
        st.strokeColor = sc.CGColor;
        SPPCirclePart(self.parts[@"cap"], m, 29);
        [self setSpin:MAX(0, self.speed) / 75.0];   // 75 km/h ~ 1 vong/giay
        CGFloat dy = showIcon ? 0 : -6;
        SPPPlace(self.iconView, r, r - 17, 14);
        self.speedLabel.frame = CGRectMake(r - 28, r - 15 + dy, 56, 30);
        self.unitLabel.frame = CGRectMake(r - 28, r + 13 + dy, 56, 10);
        SPPPlace(self.sign, d + 6 + sg / 2, r, sg);
        halo = self.glass;
        break;
    }
    case 14: {  // The HarmonyOS
        CGFloat w = withSign ? 186 : 136, h = 132, sg = 62;
        size = CGSizeMake(w, h);
        self.glass.frame = CGRectMake(0, 0, w, h); self.glass.corner = 30;
        UIColor *top = SPPRGB(64, 132, 255, 0.96), *bottom = SPPRGB(10, 89, 247, 0.96);
        if (state == 2) { top = SPPRGB(255, 112, 96, 0.96); bottom = SPPRGB(230, 40, 40, 0.96); }
        else if (state == 1) { top = SPPRGB(255, 186, 70, 0.96); bottom = SPPRGB(245, 128, 10, 0.96); }
        [self.glass setTop:top bottom:bottom];
        CGFloat nx = showIcon ? 16 + 18 + 6 : 16;
        SPPPlace(self.iconView, 16 + 9, 26, 18);
        self.nameLabel.text = SPPNavAppName(self.app);
        self.nameLabel.frame = CGRectMake(nx, 18, w - 14 - nx, 16);
        CGFloat nw = ceil([self.speedLabel sizeThatFits:CGSizeMake(200, 60)].width);
        self.speedLabel.frame = CGRectMake(14, 36, nw, 56);
        SPPAlignUnit(self.unitLabel, self.speedLabel, 14 + nw + 4, 64, 40);
        CGFloat maxV = hasLimit ? self.limit * 1.3 : 140, bw = w - 28;
        self.meterTrack.frame = CGRectMake(14, 100, bw, 18);
        self.meterTrack.layer.cornerRadius = 9; self.meterFill.layer.cornerRadius = 9;
        [CATransaction setDisableActions:NO];
        [UIView animateWithDuration:0.35 animations:^{
            self.meterFill.frame = CGRectMake(14, 100, MAX(18, bw * MIN(1.0, self.speed / maxV)), 18);
        }];
        [CATransaction setDisableActions:YES];
        SPPPlace(self.sign, w - 14 - sg / 2, 64, sg);
        break;
    }
    case 15: {  // Dong ho kim
        CGFloat d = 112, r = d / 2, R = r - 6, maxV = 160, a0 = 150, a1 = 390, sg = 80;
        CGPoint m = CGPointMake(r, r + 4);
        size = CGSizeMake(withSign ? d + 6 + sg : d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        self.deco.frame = self.glass.frame;
        UIBezierPath *minor = [UIBezierPath bezierPath], *major = [UIBezierPath bezierPath];
        for (int v = 0; v <= maxV; v += 10) {
            CGFloat a = (a0 + (a1 - a0) * v / maxV) * M_PI / 180;
            BOOL big = (v % 20 == 0);
            UIBezierPath *bp = big ? major : minor;
            CGFloat rr = R - (big ? 9 : 5);
            [bp moveToPoint:CGPointMake(m.x + rr * cos(a), m.y + rr * sin(a))];
            [bp addLineToPoint:CGPointMake(m.x + (R - 1) * cos(a), m.y + (R - 1) * sin(a))];
        }
        ((CAShapeLayer *)self.parts[@"minor"]).path = minor.CGPath;
        ((CAShapeLayer *)self.parts[@"major"]).path = major.CGPath;
        for (NSUInteger i = 0; i < self.tickLabels.count; i++) {
            CGFloat a = (a0 + (a1 - a0) * (i * 40.0) / maxV) * M_PI / 180, rt = R - 18;
            self.tickLabels[i].frame = CGRectMake(m.x + rt * cos(a) - 11, m.y + rt * sin(a) - 5, 22, 10);
        }
        CAShapeLayer *zone = (CAShapeLayer *)self.parts[@"zone"];
        zone.hidden = !hasLimit;
        if (hasLimit) zone.path = SPPArc(m, R - 1, a0 + (a1 - a0) * MIN(self.limit, maxV) / maxV, a1).CGPath;
        // Kim: ve chi ve ben phai tam (goc 0), xoay ca lop quanh tam
        CAShapeLayer *needle = (CAShapeLayer *)self.parts[@"needle"];
        needle.bounds = CGRectMake(0, 0, 2 * R, 2 * R);   // lop dang xoay: dat bounds + position (khong dat frame)
        needle.position = m;
        UIBezierPath *np = [UIBezierPath bezierPath];
        [np moveToPoint:CGPointMake(R - 8, R)]; [np addLineToPoint:CGPointMake(2 * R - 8, R)];
        needle.path = np.CGPath;
        needle.strokeColor = sc.CGColor;
        CGFloat ang = (a0 + (a1 - a0) * MIN(MAX(self.speed, 0), maxV) / maxV) * M_PI / 180;
        [CATransaction setDisableActions:NO]; [CATransaction setAnimationDuration:0.4];
        needle.transform = CATransform3DMakeRotation(ang, 0, 0, 1);
        [CATransaction setDisableActions:YES];
        SPPPlace(self.iconView, m.x, m.y, 16);   // logo lam chot kim
        self.speedLabel.frame = CGRectMake(r - 32, m.y + 12, 64, 32);
        self.unitLabel.hidden = YES;
        SPPPlace(self.sign, d + 6 + sg / 2, r, sg);
        halo = self.glass;
        break;
    }
    case 16: {  // Vong kep
        CGFloat d = 108, r = d / 2; CGPoint m = CGPointMake(r, r);
        size = CGSizeMake(d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        self.deco.frame = self.glass.frame;
        CGFloat maxV = hasLimit ? self.limit * 1.3 : 140;
        UIBezierPath *outer = SPPArc(m, 44, -90, 270), *inner = SPPArc(m, 32, -90, 270);
        ((CAShapeLayer *)self.parts[@"outerTrack"]).path = outer.CGPath;
        CAGradientLayer *of = (CAGradientLayer *)self.parts[@"outerFill"];
        of.frame = CGRectMake(0, 0, d, d);
        UIColor *endColor = state == 0 ? SPPRGB(140, 80, 255, 1) : sc;
        of.colors = @[(id)SPPHarmonyBlue().CGColor, (id)endColor.CGColor];
        CAShapeLayer *om = (CAShapeLayer *)self.parts[@"outerMask"];
        om.frame = of.bounds; om.path = outer.CGPath;
        ((CAShapeLayer *)self.parts[@"innerTrack"]).path = inner.CGPath;
        CAShapeLayer *inf = (CAShapeLayer *)self.parts[@"innerFill"];
        inf.path = inner.CGPath;
        inf.hidden = !hasLimit;
        [CATransaction setDisableActions:NO]; [CATransaction setAnimationDuration:0.4];
        om.strokeEnd = MIN(1.0, MAX(0.0, self.speed / maxV));
        inf.strokeEnd = hasLimit ? MIN(1.0, self.limit / maxV) : 0;
        [CATransaction setDisableActions:YES];
        CGFloat dy = showIcon ? 2 : -4;
        SPPPlace(self.iconView, r, r - 18, 14);
        self.speedLabel.frame = CGRectMake(r - 27, r - 16 + dy, 54, 32);
        self.unitLabel.frame = withSign ? CGRectMake(r - 26, r + 13 + dy, 52, 22) : CGRectMake(r - 26, r + 14 + dy, 52, 11);
        self.unitLabel.font = withSign ? SPPNumFont(20) : SPPUnitFont(9);
        self.unitLabel.text = hasLimit ? [NSString stringWithFormat:@"%d", self.limit] : @"--";
        self.unitLabel.textColor = hasLimit ? SPPSignRed() : SPPRGB(60, 60, 67, 0.45);
        self.sign.hidden = YES;   // gioi han da the hien o vong trong + so do
        halo = self.glass;
        break;
    }
    case 17: {  // Live View
        CGFloat h = 52, x = showIcon ? 14 + 24 + 8 : 16, mid = 23, sg = 46;
        size = CGSizeMake(x + 62 + (withSign ? 6 + sg + 3 : 10), h);   // khong hien km/h
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = h / 2;
        SPPPlace(self.iconView, 14 + 12, h / 2, 24);
        CGFloat nw = ceil([self.speedLabel sizeThatFits:CGSizeMake(200, 36)].width);
        self.speedLabel.frame = CGRectMake(x, mid - 18, nw, 36);
        SPPAlignUnit(self.unitLabel, self.speedLabel, x + nw + 3, mid, 34);
        CGFloat maxV = hasLimit ? self.limit * 1.3 : 140;
        self.meterTrack.frame = CGRectMake(x, h - 11, 56, 3);
        self.meterTrack.layer.cornerRadius = 1.5; self.meterFill.layer.cornerRadius = 1.5;
        self.meterFill.backgroundColor = sc;
        [CATransaction setDisableActions:NO];
        [UIView animateWithDuration:0.35 animations:^{
            self.meterFill.frame = CGRectMake(x, h - 11, MAX(3, 56 * MIN(1.0, self.speed / maxV)), 3);
        }];
        [CATransaction setDisableActions:YES];
        SPPPlace(self.sign, size.width - 3 - sg / 2, h / 2, sg);
        break;
    }
    case 11:    // The sang: bo cuc nhu The ngang
    default: {  // 0 The ngang
        CGFloat h = 60, nw = 66, sg = 52;
        CGFloat x = showIcon ? 12 + 26 + 4 : 14;
        size = CGSizeMake(x + nw + (withSign ? 4 + sg + 4 : 10), h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = 18;
        SPPPlace(self.iconView, 12 + 13, h / 2, 26);
        self.speedLabel.frame = CGRectMake(x, 4, nw, 42);
        self.unitLabel.frame = CGRectMake(x, 42, nw, 14);
        SPPPlace(self.sign, x + nw + 4 + sg / 2, h / 2, sg);
        break;
    }
    }
    // Khong hien don vi km/h (kieu Vong kep van dung nhan nay cho so gioi han mau do)
    BOOL unitIsLimit = (self.builtStyle == 16);
    if (!unitIsLimit && self.builtStyle != 15) {
        CGRect sf = self.speedLabel.frame, uf = self.unitLabel.frame;
        if (CGRectGetMinY(uf) >= CGRectGetMaxY(sf) - 6)
            self.speedLabel.center = CGPointMake(self.speedLabel.center.x, CGRectGetMidY(CGRectUnion(sf, uf)));
    }
    self.unitLabel.hidden = !unitIsLimit;

    // Vung nhay: quang tron quanh hinh chinh, hoac phu kin nen
    if (halo) {
        CGRect hr = CGRectInset(halo.frame, -6, -6);
        self.flashView.frame = hr;
        self.flashView.layer.cornerRadius = MIN(hr.size.width, hr.size.height) / 2;
    } else {
        self.flashView.frame = self.glass.bounds;
        self.flashView.layer.cornerRadius = self.glass.corner;
    }
    // Hinh chinh de ve vien "giu de thoat": bien (kieu 2), ca the (kieu 10), con lai la nen
    if (self.builtStyle == 2 && withSign) { self.outlineRect = self.sign.frame; self.outlineCorner = self.sign.frame.size.width / 2; }
    else if (self.builtStyle == 10) { self.outlineRect = CGRectMake(0, 0, size.width, size.height); self.outlineCorner = 16; }
    else { self.outlineRect = self.glass.frame; self.outlineCorner = self.glass.corner; }
    [CATransaction commit];
    self.card.bounds = CGRectMake(0, 0, size.width, size.height);
    self.card.center = c;
    [self setOverLimitWarning:(state == 2)];
    [self clampCard];
}

// Cai dat > Dat lai: ti le mac dinh, vi tri mac dinh tren ca iPhone lan xe
- (void)resetLayout
{
    [SPPPrefs setSizePercent:100 forCar:NO];
    [SPPPrefs setSizePercent:100 forCar:YES];
    self.scale = [self savedScale];
    self.phoneFraction = CGPointMake(-1, -1); self.carFraction = CGPointMake(-1, -1);
    if (self.window) {
        self.card.transform = [self baseTransform];
        [self restoreCardPosition];
        [self applyCrispScale];
    }
    SPPLog("bubble: dat lai vi tri + kich thuoc");
}

// "Xem thu bong bong" trong Cai dat: toc do gia 10 giay (tang qua gioi han 60 de thay doi mau)
- (void)runDemo
{
    [self.demoTimer invalidate];
    __block int tick = 0;
    SPPLog("bubble: xem thu 10 giay");
    __weak SPPBubble *weakSelf = self;
    self.demoTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        tick++;
        if (tick > 20) {
            // Het xem thu: bo so gia; app dan duong that dang chay se gui lai ngay (moi SPP_TICK) -> hien tiep
            [t invalidate]; weakSelf.demoTimer = nil;
            weakSelf.speed = -1; weakSelf.limit = -1; weakSelf.speedAt = 0; weakSelf.limitAt = 0; weakSelf.lastUpdate = 0;
            [weakSelf refresh];
            return;
        }
        int speed = 40 + tick * 2;   // 42 -> 80 km/h
        [weakSelf updateSpeed:speed limit:60];
    }];
}

// ---------------------------------------------------------------------
//  Cham / giu / keo / 2 ngon
// ---------------------------------------------------------------------
// Giu bong bong: sau SPP_HOLD_BEGIN giay hien vien do chay quanh hinh chinh, du SPP_HOLD_QUIT giay -> thoat han app.
// Tha tay som -> huy. Dang giu ma keo di -> huy dem, chuyen sang di chuyen the.
- (void)longPressed:(UILongPressGestureRecognizer *)g
{
    CGPoint p = [g locationInView:self.window];
    switch (g.state) {
    case UIGestureRecognizerStateBegan:
        self.holdStart = p; self.holdDragging = NO;
        [self startHold];
        break;
    case UIGestureRecognizerStateChanged:
        if (!self.holdDragging && hypot(p.x - self.holdStart.x, p.y - self.holdStart.y) > 12) { self.holdDragging = YES; [self cancelHold]; }
        if (self.holdDragging) {
            self.card.center = CGPointMake(self.card.center.x + p.x - self.holdStart.x, self.card.center.y + p.y - self.holdStart.y);
            self.holdStart = p;
            [self clampCard];
        }
        break;
    default:   // Ended / Cancelled / Failed
        if (self.holdDragging) [self saveCardPosition];
        self.holdDragging = NO;
        [self cancelHold];
        break;
    }
}

- (void)startHold
{
    [self cancelHold];
    CGFloat remain = SPP_HOLD_QUIT - SPP_HOLD_BEGIN;
    CGRect r = CGRectInset(self.outlineRect, -5, -5);
    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:self.outlineCorner + 5].CGPath;
    ring.fillColor = [UIColor clearColor].CGColor;
    ring.strokeColor = SPPRed().CGColor;
    ring.lineWidth = 4; ring.lineCap = kCALineCapRound;
    ring.shadowColor = SPPRed().CGColor; ring.shadowRadius = 4; ring.shadowOpacity = 0.8; ring.shadowOffset = CGSizeZero;
    ring.strokeEnd = 1;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    a.fromValue = @0; a.toValue = @1; a.duration = remain;
    [ring addAnimation:a forKey:@"sppHold"];
    [self.card.layer addSublayer:ring];
    [self applyCrispScale];
    self.holdRing = ring;
    [UIView animateWithDuration:remain delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.card.transform = [self baseScaled:0.92]; } completion:nil];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    __weak SPPBubble *weakSelf = self;
    self.holdTimer = [NSTimer scheduledTimerWithTimeInterval:remain repeats:NO block:^(NSTimer *t) { [weakSelf quitSourceApp]; }];
}

- (void)cancelHold
{
    [self.holdTimer invalidate]; self.holdTimer = nil;
    if (!self.holdRing) return;
    [self.holdRing removeFromSuperlayer]; self.holdRing = nil;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.card.transform = [self baseTransform]; } completion:nil];
}

// Du 3 giay: thoat han app dang cap toc do, an bong bong ngay
- (void)quitSourceApp
{
    [self cancelHold];
    NSString *bid = SPPNavAppBundle(self.app);
    SPPLog("bubble: giu %.0f giay -> thoat han %@", SPP_HOLD_QUIT, bid);
    [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
    SPPKillApp(bid);
    self.speed = -1; self.limit = -1;
    self.lastUpdate = 0;
    [self hide];
}

// 2 ngon: phong to / thu nho the (SPP_SIZE_MIN .. SPP_SIZE_MAX %), luu vao Cai dat cho man dang dung
- (void)pinched:(UIPinchGestureRecognizer *)g
{
    static CGFloat startScale = 1;
    if (g.state == UIGestureRecognizerStateBegan) { startScale = self.scale; self.pinching = YES; [self cancelHold]; }
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        CGFloat lo = SPP_SCALE_BASE * SPP_SIZE_MIN / 100, hi = SPP_SCALE_BASE * SPP_SIZE_MAX / 100;
        self.scale = MIN(hi, MAX(lo, startScale * g.scale));
        self.card.transform = [self baseTransform];
        [self clampCard];
    }
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        self.pinching = NO;
        [self saveCardPosition];
        [SPPPrefs setSizePercent:self.scale / SPP_SCALE_BASE * 100 forCar:!self.onPhone];
        self.scale = [self savedScale];   // khop voi gia tri da lam tron trong Cai dat
        self.card.transform = [self baseTransform];
        [self applyCrispScale];
    }
}

- (void)panned:(UIPanGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) [self cancelHold];
    CGPoint t = [g translationInView:self.window];
    self.card.center = CGPointMake(self.card.center.x + t.x, self.card.center.y + t.y);
    [self clampCard];
    [g setTranslation:CGPointZero inView:self.window];
    if (g.state == UIGestureRecognizerStateEnded) [self saveCardPosition];
}

// Cham bong bong -> mo lai app dan duong (tren xe: giao dien CarPlay cua app; khong co xe: tren iPhone)
- (void)tapped:(UITapGestureRecognizer *)g
{
    [UIView animateWithDuration:0.1 animations:^{ self.card.transform = [self baseScaled:0.92]; }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.15 animations:^{ self.card.transform = [self baseTransform]; }]; }];
    if (!self.onPhone) {
        SPPLog("bubble: cham -> mo %@ tren CarPlay", SPPNavAppName(self.app));
        static int tokOpen = 0;
        if (!tokOpen) notify_register_check(SPP_DARWIN_OPEN_CAR, &tokOpen);
        notify_set_state(tokOpen, (uint64_t)self.app);
        notify_post(SPP_DARWIN_OPEN_CAR);   // process CarPlay mo app (CarPlay.xm)
        return;
    }
    SPPLog("bubble: cham -> mo %@ tren iPhone", SPPNavAppName(self.app));
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(launchApplicationWithIdentifier:suspended:)])
        [sb launchApplicationWithIdentifier:SPPNavAppBundle(self.app) suspended:NO];
}

// ---------------------------------------------------------------------
//  Cua so rieng: tren man xe neu dang ket noi, neu khong thi tren man iPhone
// ---------------------------------------------------------------------
- (void)ensureWindow
{
    BOOL car = SPPGetCarPlayCADisplay() != nil;
    // Man xe chop mat 1 nhip (API tra nil thoang qua) -> giu cua so xe, chi chuyen ve iPhone khi mat lien tuc
    if (self.window && !self.onPhone && !car) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (self.carLostAt <= 0) self.carLostAt = now;
        if (now - self.carLostAt < SPP_CAR_GRACE) return;
    }
    self.carLostAt = 0;
    if (self.window && self.onPhone == !car) return;
    if (self.window) { self.window.hidden = YES; [self.window removeFromSuperview]; self.window = nil; }
    CGFloat ds = [UIScreen mainScreen].scale;
    UIWindow *w = car ? SPPMakeCarWindow(&ds) : SPPMakePhoneWindow();   // iPhone: xoay theo huong may (applyPhoneOrientation)
    if (!w) return;
    self.onPhone = !car;
    self.displayScale = ds;
    self.scale = [self savedScale];   // moi man co kich thuoc rieng
    SPPMakeWindowPassThrough(w);
    w.windowLevel = UIWindowLevelStatusBar + 70;
    w.backgroundColor = [UIColor clearColor];

    // The chua noi dung theo kieu da chon (xem buildStyle:)
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    [card addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)]];
    [card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
    [card addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)]];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    lp.minimumPressDuration = SPP_HOLD_BEGIN;
    lp.allowableMovement = CGFLOAT_MAX;   // tu xu ly keo trong longPressed: (keo xa -> di chuyen the)
    [card addGestureRecognizer:lp];
    card.transform = [self baseTransform];
    [w addSubview:card];

    self.window = w; self.card = card;
    self.builtStyle = -1;   // ve lai noi dung trong the moi
    if (!car) [self applyPhoneOrientationForce:YES];
    [self restoreCardPosition];
    w.hidden = YES;
    SPPLog("bubble: cua so %@ tao xong", car ? @"xe" : @"iPhone");
}

// ---------------------------------------------------------------------
//  Huong & vi tri
//  iPhone: cua so xoay theo huong cam may (doc / ngang trai / ngang phai).
//  CarPlay: cua so nam tren man xe (huong cua man xe), vi tri mac dinh ben phai dock CarPlay.
// ---------------------------------------------------------------------
- (void)startOrientationTracking
{
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    __weak SPPBubble *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil
                                                       queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        SPPBubble *me = weakSelf;
        if (me.window && me.onPhone) [me applyPhoneOrientationForce:NO];
    }];
}

// Goc xoay noi dung tren iPhone (giu goc cu khi may nam ngua / up / khong ro)
- (CGFloat)phoneRotation
{
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortrait:       return 0;
        case UIDeviceOrientationLandscapeLeft:  return M_PI_2;
        case UIDeviceOrientationLandscapeRight: return -M_PI_2;
        default: return self.appliedRotation;
    }
}

- (void)applyPhoneOrientationForce:(BOOL)force
{
    if (!self.window || !self.onPhone) return;
    CGFloat r = [self phoneRotation];
    if (!force && fabs(r - self.appliedRotation) < 0.01) return;
    BOOL wasVisible = !self.window.hidden && self.card.bounds.size.width > 10;
    if (wasVisible && !force) [self saveCardPosition];
    CGRect sb = [UIScreen mainScreen].bounds;
    BOOL land = fabs(r) > 0.1;
    self.window.transform = CGAffineTransformMakeRotation(r);
    self.window.bounds = land ? CGRectMake(0, 0, sb.size.height, sb.size.width) : CGRectMake(0, 0, sb.size.width, sb.size.height);
    self.window.center = CGPointMake(CGRectGetMidX(sb), CGRectGetMidY(sb));
    self.appliedRotation = r;
    [self restoreCardPosition];
    SPPLog("bubble: iPhone xoay %.0f do", r * 180 / M_PI);
}

// Vi tri mac dinh: iPhone = goc tren trai (duoi thanh trang thai); xe = ngay ben phai dock CarPlay
- (CGPoint)defaultCardCenter
{
    CGRect b = self.window.bounds;
    if (self.onPhone) return CGPointMake(16 + 70, b.size.height > b.size.width ? 70 : 12 + 40);
    return CGPointMake(MIN(b.size.width - 80, 90 + 80), 12 + 40);
}

- (void)saveCardPosition
{
    CGRect b = self.window.bounds;
    if (b.size.width < 1 || b.size.height < 1) return;
    CGPoint f = CGPointMake(self.card.center.x / b.size.width, self.card.center.y / b.size.height);
    if (self.onPhone) self.phoneFraction = f; else self.carFraction = f;
}

- (void)restoreCardPosition
{
    CGRect b = self.window.bounds;
    CGPoint f = self.onPhone ? self.phoneFraction : self.carFraction;
    self.card.center = (f.x < 0) ? [self defaultCardCenter] : CGPointMake(f.x * b.size.width, f.y * b.size.height);
    [self clampCard];
}

- (void)clampCard
{
    CGRect b = self.window.bounds; CGSize s = self.card.frame.size; CGPoint c = self.card.center;   // frame da tinh ti le
    c.x = MIN(CGRectGetMaxX(b) - s.width / 2, MAX(s.width / 2, c.x));
    c.y = MIN(CGRectGetMaxY(b) - s.height / 2, MAX(s.height / 2, c.y));
    // Goc the dung tron diem anh that: chu / vien khong bi lech nua diem anh (nhoe)
    CGFloat ps = self.displayScale > 0 ? self.displayScale : 1;
    c.x = round((c.x - s.width / 2) * ps) / ps + s.width / 2;
    c.y = round((c.y - s.height / 2) * ps) / ps + s.height / 2;
    self.card.center = c;
}

// Ve net: the duoc phong bang transform (ti le trong Cai dat). Mac dinh moi lop ve theo ti le man roi moi bi phong /
// thu khi ghep hinh -> chu, vong, vien bi nhoe / rang cua (ro nhat tren man xe 1x-2x). Dat contentsScale = ti le man x
// ti le the de moi lop ve dung bang so diem anh that tren man.
static void SPPSetContentsScale(CALayer *l, CGFloat s)
{
    BOOL image = [l.delegate isKindOfClass:[UIImageView class]];   // anh: giu nguyen, khong ve lai
    if (!image && fabs(l.contentsScale - s) > 0.001) {
        l.contentsScale = s;
        if ([l.delegate isKindOfClass:[UILabel class]]) [l setNeedsDisplay];
    }
    if (l.shouldRasterize) l.rasterizationScale = s;
    for (CALayer *c in l.sublayers) SPPSetContentsScale(c, s);
    if (l.mask) SPPSetContentsScale(l.mask, s);
}

- (void)applyCrispScale
{
    if (!self.card) return;
    CGFloat ds = self.displayScale > 0 ? self.displayScale : [UIScreen mainScreen].scale;
    SPPSetContentsScale(self.card.layer, ds * MAX(self.scale, 0.3));
}

@end
