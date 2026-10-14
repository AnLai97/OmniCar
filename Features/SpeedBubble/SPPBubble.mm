#import "SPPBubble.h"
#import "SPPPrefs.h"
#import "SPPWarn.h"
#import "SPPGPS.h"
#import <notify.h>

// Lite mode (OMCLiteActive): shadows without a path are drawn off screen on every frame; the card goes flat
static void SPPStripShadows(CALayer *layer)
{
    layer.shadowOpacity = 0;
    for (CALayer *l in layer.sublayers) SPPStripShadows(l);
}

#define SPP_SPEED_STALE 5.0   // giay khong co so moi -> hien "--" (bong bong van hien)
#define SPP_VALUE_HOLD  3.0   // giay giu so cu khi app tam khong doc duoc (khong nhay qua lai so <-> "--")
#define SPP_SOURCE_GONE 90.0  // giay khong nghe gi tu app (va khong biet app con chay khong) -> an
#define SPP_CAR_GRACE   3.0   // giay mat man xe lien tuc moi chuyen bong bong ve iPhone
#define SPP_SCALE_BASE  0.9   // ti le ung voi 100% trong Cai dat (Kich thuoc tren iPhone / CarPlay)
#define SPP_SIZE_MIN    60.0  // % (Cai dat + chum 2 ngon)
#define SPP_SIZE_MAX    220.0
#define SPP_HOLD_QUIT   2.0   // giay giu bong bong de thoat han app
#define SPP_HOLD_BEGIN  0.2   // giay giu toi thieu truoc khi bat dau dem (de khong nham voi cham / keo)
#define SPP_STYLE_COUNT SB_STYLE_COUNT   // kieu bong bong (SPPStyle, xem buildStyle:)

// ---------------------------------------------------------------------
//  Cua so: man xe (UIRootSceneWindow tren CADisplay cua CarPlay) hoac man iPhone
//  Co che tao cua so tren man xe: theo carplay-cast (EthanArbuckle)
// ---------------------------------------------------------------------

// CADisplay cua man hinh xe (nil neu chua ket noi)
id SPPGetCarPlayCADisplay(void)
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
UIWindow *SPPMakeCarWindow(CGFloat *scale)
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

void SPPMakeWindowPassThrough(UIWindow *w)
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
    if (SPPIsGPSSource(app)) {
        // GPS iPhone khong phai app: o xanh co mui ten vi tri (SF Symbol)
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightBold];
        UIImage *glyph = [[UIImage systemImageNamed:@"location.fill" withConfiguration:cfg]
                          imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (glyph) {
            CGFloat d = 60;
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
            img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [[UIColor colorWithRed:10 / 255.0 green:132 / 255.0 blue:1 alpha:1] setFill];
                UIRectFill(CGRectMake(0, 0, d, d));
                CGSize gs = glyph.size;
                [glyph drawInRect:CGRectMake((d - gs.width) / 2, (d - gs.height) / 2, gs.width, gs.height)];
            }];
        }
    } else if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        img = [UIImage _applicationIconImageForBundleIdentifier:SPPNavAppBundle(app) format:2 scale:[UIScreen mainScreen].scale];
    if (!img) {
        CGFloat d = 60;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
        img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIColor *bg = app == 1 ? [UIColor colorWithRed:0.0 green:0.6 blue:0.45 alpha:1]
                        : app == 4 ? [UIColor colorWithRed:0.2 green:0.75 blue:0.95 alpha:1] : [UIColor colorWithRed:0.1 green:0.4 blue:0.85 alpha:1];
            [bg setFill]; UIRectFill(CGRectMake(0, 0, d, d));
            NSArray *abbr = @[@"VM", @"GO", @"GPS", @"G", @"WZ", @"AM"];
            NSString *t = (app >= 0 && app < (int)abbr.count) ? abbr[app] : @"?";
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
static UIColor *SPPShadow(void)  { return SPPRGB(70, 60, 140, 1); }

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

// Nen kinh trang: gradient doc + vien sang + bong tim nhat (bong do o view ngoai, gradient cat theo goc bo o layer trong)
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
        _fill.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
        if (@available(iOS 13.0, *)) _fill.cornerCurve = kCACornerCurveContinuous;
        [self.layer addSublayer:_fill];
        _sheen = [CAGradientLayer layer];
        _sheen.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.5].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
        [_fill addSublayer:_sheen];
        [self setTop:SPPRGB(255, 255, 255, 0.9) bottom:SPPRGB(0xF1, 0xF0, 0xFB, 0.9)];
        self.layer.shadowColor = SPPShadow().CGColor;
        self.layer.shadowOpacity = 0.22; self.layer.shadowRadius = 10; self.layer.shadowOffset = CGSizeMake(0, 4);
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

// Bien gioi han toc do: tron trang, vien do (12% duong kinh), so den dam (Vienna, mac dinh)
// Kieu My (usStyle): tam chu nhat trang dung (rong ~0.8 cao), vien den, "SPEED / LIMIT" nho tren so lon -
// ve trong cung o vuong voi kieu Vienna nen bo cuc cac kieu bong bong khong doi
@interface SPPSignView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic) BOOL muted;   // khong doc duoc gioi han: vien xam, "--"
@property (nonatomic) BOOL usStyle;
@property (nonatomic, strong) UIView *plate;       // kieu My: tam bien chu nhat
@property (nonatomic, strong) UILabel *titleLabel; // kieu My: "SPEED LIMIT"
- (CGRect)plateRect;   // hinh bien that trong bounds (kieu My: chu nhat o giua; Vienna: ca o)
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
        _plate = [[UIView alloc] init];
        _plate.userInteractionEnabled = NO;
        _plate.backgroundColor = [UIColor whiteColor];
        _plate.layer.borderColor = SPPRGB(20, 20, 20, 1).CGColor;
        _plate.hidden = YES;
        [self addSubview:_plate];
        _titleLabel = SPPLabel(SPPUnitFont(8), SPPRGB(20, 20, 20, 1), NSTextAlignmentCenter);
        _titleLabel.numberOfLines = 2;
        _titleLabel.text = @"SPEED\nLIMIT";
        _titleLabel.hidden = YES;
        [self addSubview:_titleLabel];
        _label = SPPLabel(SPPNumFont(20), SPPRGB(20, 20, 20, 1), NSTextAlignmentCenter);
        [self addSubview:_label];
    }
    return self;
}
- (void)applyColors
{
    UIColor *ink = self.muted ? SPPRGB(120, 124, 134, 1) : SPPRGB(20, 20, 20, 1);
    self.layer.borderColor = self.usStyle ? [UIColor clearColor].CGColor : (self.muted ? SPPRGB(174, 178, 188, 1) : SPPSignRed()).CGColor;
    self.plate.layer.borderColor = (self.muted ? SPPRGB(174, 178, 188, 1) : SPPRGB(20, 20, 20, 1)).CGColor;
    self.label.textColor = ink;
    self.titleLabel.textColor = ink;
}
- (void)setMuted:(BOOL)muted
{
    if (muted == _muted && self.layer.borderColor) return;
    _muted = muted;
    [self applyColors];
}
- (void)setUsStyle:(BOOL)usStyle
{
    if (usStyle == _usStyle) return;
    _usStyle = usStyle;
    self.backgroundColor = usStyle ? [UIColor clearColor] : [UIColor whiteColor];
    self.plate.hidden = !usStyle;
    self.titleLabel.hidden = !usStyle;
    [self applyColors];
    [self setNeedsLayout];
}
- (CGRect)plateRect
{
    CGSize b = self.bounds.size;
    if (!self.usStyle) return self.bounds;
    CGFloat h = b.height, w = MIN(b.width, h * 0.8);
    return CGRectMake((b.width - w) / 2, (b.height - h) / 2, w, h);
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat d = self.bounds.size.width;
    if (self.usStyle) {
        // Kieu My: khong ve vong tron cua view, bong do lay theo tam bien
        CGRect pr = [self plateRect];
        CGFloat h = pr.size.height, bw = MAX(1.5, h * 0.045), inset = bw + h * 0.04;
        self.layer.cornerRadius = 0;
        self.layer.borderWidth = 0;
        self.plate.frame = pr;
        self.plate.layer.cornerRadius = h * 0.08;
        self.plate.layer.borderWidth = bw;
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:pr cornerRadius:h * 0.08].CGPath;
        CGFloat iw = pr.size.width - 2 * inset;
        self.titleLabel.font = SPPUnitFont(h * 0.13);
        self.titleLabel.frame = CGRectMake(pr.origin.x + inset, pr.origin.y + inset, iw, h * 0.32);
        self.label.font = SPPNumFont(h * (self.label.text.length >= 3 ? 0.34 : 0.44));
        CGFloat ny = CGRectGetMaxY(self.titleLabel.frame);
        self.label.frame = CGRectMake(pr.origin.x + inset, ny, iw, CGRectGetMaxY(pr) - inset - ny);
        return;
    }
    CGFloat bw = d * 0.12;
    self.layer.shadowPath = nil;
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
@property (nonatomic) NSTimeInterval timerInterval;  // 0.5 s, 1 s in lite mode
@property (nonatomic) BOOL builtLite;                // card built in lite mode (no shadows)
@property (nonatomic) int speed, limit;
@property (nonatomic) CFAbsoluteTime lastUpdate;      // ban tin gan nhat tu app nguon (ke ca khi khong co so)
@property (nonatomic) CFAbsoluteTime speedAt, limitAt; // lan cuoi doc duoc toc do / gioi han
@property (nonatomic) CFAbsoluteTime carLostAt;        // luc bat dau mat man xe (0 = dang co)
@property (nonatomic) BOOL onPhone;
@property (nonatomic) BOOL carBusy;                  // Split Screen dang chia / mo bang tren man xe -> an bong bong tren xe
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
@property (nonatomic, strong) UIView *deco;                          // Dong ho taplo: mat dong ho (lop ve rieng duoi chu)
@property (nonatomic, strong) NSMutableDictionary<NSString *, CALayer *> *parts;   // lop ve rieng cua kieu dang ve, theo ten
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *bits;     // view rieng (thanh tien do, vach, cham...)
@property (nonatomic, strong) NSArray<UILabel *> *tickLabels;        // Dong ho taplo: so tren mat
@property (nonatomic, strong) UIView *flashView;     // nen / quang do nhay khi vuot gioi han (moi kieu)
@property (nonatomic, strong) NSTimer *demoTimer;    // "Xem thu bong bong" trong Cai dat
@property (nonatomic, strong) NSTimer *staleTimer;   // canh so cu ca khi bong bong an (canh bao qua toc do, SB_DARWIN_SPEED_NOW)
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

// Toc do hien tai cho tinh nang khac: Darwin SB_DARWIN_SPEED_NOW, state = km/h, SB_SPEED_UNKNOWN = khong
// biet. Chi gui khi doi.
static void SPPPublishSpeed(int kmh)
{
    static int token = 0;
    static uint64_t last = UINT64_MAX;
    uint64_t state = kmh >= 0 ? (uint64_t)MIN(kmh, 255) : (uint64_t)SB_SPEED_UNKNOWN;
    if (state == last) return;
    if (!token) notify_register_check(SB_DARWIN_SPEED_NOW, &token);
    if (!token) return;
    last = state;
    notify_set_state(token, state);
    notify_post(SB_DARWIN_SPEED_NOW);
}

// Moi lan doi toc do (ban tin moi, so cu qua han, mat nguon...) -> bao cho tinh nang khac. "Xem thu" / test: so gia, khong gui.
- (void)setSpeed:(int)speed
{
    _speed = speed;
    if (!self.demoTimer) SPPPublishSpeed(speed);
}

// Ban tin moi -> canh bao qua toc do theo so moi; dong ho 1 giay canh so cu (bong bong an thi timer cua refresh dung)
- (void)feedWarning
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL fresh = self.speed >= 0 && now - self.speedAt <= SPP_SPEED_STALE;
    int limit = (self.limit > 0 && now - self.limitAt <= SPP_SPEED_STALE) ? self.limit : -1;
    [[SPPOverspeed shared] updateSpeed:(fresh ? self.speed : -1) limit:limit];
    if (!fresh) {
        if (self.speed >= 0 && !self.demoTimer) self.speed = -1;   // so cu -> "khong biet"
        [self.staleTimer invalidate]; self.staleTimer = nil;
        return;
    }
    if (self.staleTimer) return;
    __weak SPPBubble *weakSelf = self;
    self.staleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        SPPBubble *me = weakSelf;
        if (!me) { [t invalidate]; return; }
        [me feedWarning];
    }];
}

// Nguon ngung han (GPS iPhone tat vi xe ngat / doi nguon / tat tinh nang): bo so, an ngay - khong cho SPP_SOURCE_GONE
- (void)sourceStopped:(int)app
{
    if ((app & 7) != (self.app & 7) || self.demoTimer) return;
    SPPLog("bubble: nguon %@ ngung -> bo so", SPPNavAppName(app));
    self.speed = -1; self.limit = -1; self.speedAt = 0; self.limitAt = 0; self.lastUpdate = 0;
    [self feedWarning];
    [self refresh];
}

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
    if (SPPIsGPSSource(app)) sAppOpened[app] = YES;   // GPS iPhone: khong co app de mo, co so la hien
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
    [self feedWarning];
    [self refresh];
}

// App dang cap toc do con chay khong (SBApplication): 1 = chay (ke ca dang treo nen), 0 = da tat, -1 = khong biet.
// Chi tin ket qua "da tat" sau khi API tung bao "dang chay" trong phien nay - API khac di tren ban iOS khac thi
// khong bao gio an nham bong bong.
static BOOL sSeenRunning[8];

- (int)sourceAppState
{
    int app = self.app & 7;
    if (SPPIsGPSSource(app)) return [SPPPhoneGPS shared].running ? 1 : 0;   // GPS iPhone: theo CLLocationManager trong SpringBoard
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
    // Split Screen dang chiem man xe (bang chon app, dang chia): bong bong tren xe de len cho dang cham -> tam an
    BOOL carBusy = self.carBusy && SPPGetCarPlayCADisplay() != nil;
    BOOL show = alive && [SPPPrefs enabled] && ![self anyAppForeground] && !carBusy;
    // App vua bi tat (vuot khoi da nhiem / bi he thong dong) -> an ngay
    if (show && run == 0) {
        SPPLog("bubble: %@ da tat -> an bong bong ngay", SPPNavAppName(self.app));
        self.speed = -1; self.limit = -1; self.lastUpdate = 0;
        sAppOpened[self.app & 7] = NO; sAppFg[self.app & 7] = NO;   // lan chay sau phai mo app lai moi hien
        show = NO;
    }
    if (!show) {
        if (self.window && !self.window.hidden)
            SPPLog("bubble: an (ban tin %.1fs truoc, app chay=%d, tat=%d, app dan duong dang hien=%d, man xe ban=%d)",
                   now - self.lastUpdate, run, ![SPPPrefs enabled], [self anyAppForeground], carBusy);
        [self hide];
        return;
    }
    [self ensureWindow];
    if (!self.window) return;
    if (self.onPhone) [self applyPhoneOrientationForce:NO];

    [self applySavedScale];
    NSInteger style = [SPPPrefs style];
    BOOL lite = OMCLiteActive();
    if (style != self.builtStyle || lite != self.builtLite) { self.builtLite = lite; [self buildStyle:style]; }
    // So doi muot: chi dat text, khong animation (cap nhat lien tuc)
    [self renderStyle];
    [self applyCrispScale];
    if (lite) SPPStripShadows(self.card.layer);

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
    NSTimeInterval every = lite ? 1.0 : 0.5;   // lite mode: half the redraws
    if (self.timer && self.timerInterval != every) { [self.timer invalidate]; self.timer = nil; }
    if (!self.timer) {
        __weak SPPBubble *weakSelf = self;
        self.timerInterval = every;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:every repeats:YES block:^(NSTimer *t) { [weakSelf refresh]; }];
    }
}

// Split Screen (process CarPlay) bao man xe dang ban / ranh qua OMC_DARWIN_CAR_BUSY
- (void)setCarBusy:(BOOL)busy
{
    if (_carBusy == busy) return;
    _carBusy = busy;
    SPPLog("bubble: man xe %@ (Split Screen)", busy ? @"ban -> an tren xe" : @"ranh");
    [self refresh];
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
//  Cac kieu bong bong (Settings > OmniCar > Speed Bubble > Style), ban duyet: tools/preview/speedbubble.html.
//  Chung: kinh trang + 4 mau logo khi binh thuong, ho phach khi >= 90 % gioi han, do + nhip sang khi vuot.
//    0 Giot kinh    : dia kinh tron, vien cau vong, bien nho chom goc tren phai, icon goc duoi trai
//    1 Vien kinh    : vien thuoc ngang [icon / cham trang thai] [so / km/h] | [bien]
//    2 Cap doi      : dia toc do kinh + bien cung co dat canh nhau; vuot -> dia do dac
//    3 Vong cung    : cung 270 do lap theo toc do / gioi han, bien o khe duoi
//    4 The Harmony  : the vuong nen 4 mau logo, so to, thanh tien do; gan / vuot -> ca the doi mau
//    5 Toi gian     : khong nen, so lon co quang trang, gach mong theo toc do, bien ben canh
//    6 Kinh dem     : vien thuoc dung kinh khoi, vien neon cau vong, bien tren, so duoi
//    7 Dai HUD      : thanh ngang [icon] [so / km/h] [vach sang tien toi gioi han] [bien]; cham gioi han la canh bao
//    8 Dong ho taplo: mat dong ho kim 0..160 km/h (0..100 mph), vung do tu muc gioi han, so dien tu duoi tam
// =====================================================================
typedef NS_ENUM(NSInteger, SPPStyle) {
    SPPStyleDrop = 0, SPPStylePill, SPPStyleTwin, SPPStyleArc, SPPStyleTile, SPPStyleMin, SPPStyleNight, SPPStyleHUD, SPPStyleDash,
};

static UIColor *SPPMk(void)       { return SPPRGB(0x4A, 0x4F, 0x80, 1); }      // chu cham (DESIGN.md)
static UIColor *SPPMk2(void)      { return SPPRGB(0x4A, 0x4F, 0x80, 0.55); }
static UIColor *SPPNear(void)     { return SPPRGB(0xFF, 0xB3, 0x40, 1); }
static UIColor *SPPNearText(void) { return SPPRGB(0xD9, 0x8A, 0x00, 1); }
static UIColor *SPPOver(void)     { return SPPRGB(0xFF, 0x5A, 0x5F, 1); }
static UIColor *SPPOverText(void) { return SPPRGB(0xF0, 0x32, 0x3A, 1); }
// 4 mau logo: tim, xanh troi, bac ha, hong (vong kin quay lai tim)
static NSArray *SPPAuroraColors(void)
{
    return @[(id)SPPRGB(0xA7, 0x8B, 0xFA, 1).CGColor, (id)SPPRGB(0x60, 0xC5, 0xFA, 1).CGColor, (id)SPPRGB(0x5E, 0xDD, 0xB6, 1).CGColor,
             (id)SPPRGB(0xF5, 0x9A, 0xC0, 1).CGColor, (id)SPPRGB(0xA7, 0x8B, 0xFA, 1).CGColor];
}
static NSArray *SPPTrioColors(void)   // tim -> xanh troi -> bac ha (thanh / cung tien do)
{
    return @[(id)SPPRGB(0xA7, 0x8B, 0xFA, 1).CGColor, (id)SPPRGB(0x60, 0xC5, 0xFA, 1).CGColor, (id)SPPRGB(0x5E, 0xDD, 0xB6, 1).CGColor];
}

// Gradient (non quanh tam hoac thang) chi hien theo net cua mat na (vong, cung, duong vien): tra ve gradient, mask la CAShapeLayer
static CAGradientLayer *SPPStrokeGradient(BOOL conic, CGFloat width)
{
    CAGradientLayer *g = [CAGradientLayer layer];
    if (conic) { g.type = kCAGradientLayerConic; g.startPoint = CGPointMake(0.5, 0.5); g.endPoint = CGPointMake(0.5, 0); g.colors = SPPAuroraColors(); }
    else { g.startPoint = CGPointMake(0, 0); g.endPoint = CGPointMake(1, 1); g.colors = SPPTrioColors(); }
    CAShapeLayer *m = [CAShapeLayer layer];
    m.fillColor = [UIColor clearColor].CGColor;
    m.strokeColor = [UIColor blackColor].CGColor;
    m.lineWidth = width;
    m.lineCap = kCALineCapRound;
    g.mask = m;
    return g;
}

static void SPPStrokePath(CAGradientLayer *g, CGRect frame, UIBezierPath *pathInFrame)
{
    g.frame = frame;
    CAShapeLayer *m = (CAShapeLayer *)g.mask;
    m.frame = g.bounds;
    m.path = pathInFrame.CGPath;
}

static UIBezierPath *SPPCircle(CGPoint c, CGFloat r) { return [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0 endAngle:2 * M_PI clockwise:YES]; }
static UIBezierPath *SPPArc(CGPoint c, CGFloat r, CGFloat deg0, CGFloat deg1)
{
    return [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:deg0 * M_PI / 180 endAngle:deg1 * M_PI / 180 clockwise:YES];
}

// 0 = binh thuong, 1 = sap cham gioi han (>= 90%), 2 = vuot (Dai HUD: cham gioi han da la canh bao)
- (int)speedState
{
    if (self.limit <= 0 || self.speed < 0) return 0;
    BOOL atLimitWarns = (self.builtStyle == SPPStyleHUD);
    if (atLimitWarns ? self.speed >= self.limit : self.speed > self.limit) return 2;
    if (self.speed >= self.limit * 0.9) return 1;
    return 0;
}

- (UIColor *)stateColor
{
    switch ([self speedState]) {
        case 2: return SPPOver();
        case 1: return SPPNear();
        default: return SPPMk();
    }
}

// Ti le cho thanh / cung tien do: toc do / gioi han (khong co gioi han: / 160 km/h)
- (CGFloat)speedRatio
{
    if (self.speed <= 0) return 0;
    return MIN(1.0, self.speed / (self.limit > 0 ? (CGFloat)self.limit : 160.0));
}

- (UIView *)bit:(NSString *)key { return self.bits[key]; }
- (UIView *)addBit:(NSString *)key to:(UIView *)parent
{
    UIView *v = [[UIView alloc] init];
    v.userInteractionEnabled = NO;
    [parent addSubview:v];
    self.bits[key] = v;
    return v;
}

// Lop ve rieng (thu tu tao = thu tu chong)
- (CAShapeLayer *)shapePart:(NSString *)key in:(CALayer *)parent stroke:(UIColor *)stroke width:(CGFloat)w
{
    CAShapeLayer *l = [CAShapeLayer layer];
    l.fillColor = [UIColor clearColor].CGColor;
    l.strokeColor = stroke.CGColor;
    l.lineWidth = w;
    [parent addSublayer:l];
    self.parts[key] = l;
    return l;
}

// Chu sang tren nen toi (Kinh dem, Dong ho taplo) / quang trang tren ban do (Toi gian)
static void SPPGlow(UILabel *l, UIColor *color, CGFloat radius)
{
    l.layer.shadowColor = color.CGColor;
    l.layer.shadowOffset = CGSizeZero;
    l.layer.shadowRadius = radius;
    l.layer.shadowOpacity = 1;
}

- (void)buildStyle:(NSInteger)style
{
    UIView *card = self.card;
    for (UIView *v in [card.subviews copy]) [v removeFromSuperview];
    for (CALayer *l in [card.layer.sublayers copy]) [l removeFromSuperlayer];
    self.glass = nil; self.iconView = nil; self.sign = nil; self.flashView = nil; self.deco = nil;
    self.speedLabel = nil; self.unitLabel = nil; self.tickLabels = nil;
    self.parts = [NSMutableDictionary dictionary];
    self.bits = [NSMutableDictionary dictionary];
    if (style < 0 || style >= SPP_STYLE_COUNT) style = SPPStyleDrop;

    UIView *flash = [[UIView alloc] init];
    flash.backgroundColor = SPPOver();
    flash.alpha = 0;
    flash.userInteractionEnabled = NO;
    self.flashView = flash;

    // Nen kinh. Kieu the / thanh (Vien kinh, The Harmony, Kinh dem, Dai HUD): nhay phu kin nen (tren nen, duoi chu);
    // kieu tron va khong nen: quang do nhay quanh hinh chinh (nam sau hinh)
    SPPGlassView *g = [[SPPGlassView alloc] init];
    BOOL flashInside = (style == SPPStylePill || style == SPPStyleTile || style == SPPStyleNight || style == SPPStyleHUD);
    if (flashInside) { [card addSubview:g]; [g addSubview:flash]; }
    else { [card addSubview:flash]; [card addSubview:g]; }
    g.hidden = (style == SPPStyleMin || style == SPPStyleDash);
    self.glass = g;

    UIColor *ink = SPPMk(), *unit = SPPMk2();
    CGFloat num = 32, unitSize = 10;
    switch (style) {
    case SPPStyleDrop: {
        num = 36;
        CAGradientLayer *ring = SPPStrokeGradient(YES, 3);
        [g.layer addSublayer:ring];
        self.parts[@"ring"] = ring;
        CAGradientLayer *shine = [CAGradientLayer layer];   // vet sang nua tren nhu giot nuoc
        shine.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.75].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
        shine.masksToBounds = YES;
        [g.layer addSublayer:shine];
        self.parts[@"shine"] = shine;
        break;
    }
    case SPPStylePill: {
        num = 32;
        UIView *dot = [self addBit:@"dot" to:card];
        dot.layer.cornerRadius = 4;
        UIView *bar = [self addBit:@"bar" to:card];
        bar.backgroundColor = [SPPMk() colorWithAlphaComponent:0.18];
        bar.layer.cornerRadius = 0.75;
        break;
    }
    case SPPStyleTwin:
        num = 30;
        [self shapePart:@"nearRing" in:g.layer stroke:SPPNear() width:3];
        break;
    case SPPStyleArc: {
        num = 34;
        CAShapeLayer *track = [self shapePart:@"track" in:g.layer stroke:[SPPMk() colorWithAlphaComponent:0.12] width:7];
        track.lineCap = kCALineCapRound;
        CAGradientLayer *fill = SPPStrokeGradient(NO, 7);
        [g.layer addSublayer:fill];
        self.parts[@"fill"] = fill;
        break;
    }
    case SPPStyleTile: {
        num = 40;
        g.fill.startPoint = CGPointMake(0, 0); g.fill.endPoint = CGPointMake(1, 1);
        CAGradientLayer *mesh = [CAGradientLayer layer];   // nen 4 mau logo: cheo tim -> bac ha + cheo xanh troi -> hong
        mesh.startPoint = CGPointMake(1, 0); mesh.endPoint = CGPointMake(0, 1);
        mesh.colors = @[(id)SPPRGB(0xA6, 0xDD, 0xFD, 0.9).CGColor, (id)SPPRGB(0xA6, 0xDD, 0xFD, 0).CGColor,
                        (id)SPPRGB(0xFE, 0xC4, 0xD8, 0).CGColor, (id)SPPRGB(0xFE, 0xC4, 0xD8, 0.9).CGColor];
        mesh.locations = @[@0, @0.5, @0.5, @1];
        [g.fill insertSublayer:mesh atIndex:0];
        self.parts[@"mesh"] = mesh;
        g.fill.borderColor = [UIColor whiteColor].CGColor;
        g.layer.shadowColor = SPPRGB(80, 70, 160, 1).CGColor; g.layer.shadowOpacity = 0.28; g.layer.shadowRadius = 12;
        UIView *track = [self addBit:@"track" to:card];
        track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.55];
        track.layer.cornerRadius = 3;
        track.clipsToBounds = YES;
        UIView *fill = [self addBit:@"fill" to:track];
        fill.layer.cornerRadius = 3;
        fill.clipsToBounds = YES;
        CAGradientLayer *fg = [CAGradientLayer layer];
        fg.startPoint = CGPointMake(0, 0.5); fg.endPoint = CGPointMake(1, 0.5);
        fg.colors = @[(id)SPPRGB(0x9B, 0x87, 0xF8, 1).CGColor, (id)SPPRGB(0x5D, 0xB4, 0xF6, 1).CGColor];
        [fill.layer addSublayer:fg];
        self.parts[@"fillGrad"] = fg;
        break;
    }
    case SPPStyleMin: {
        num = 48; unitSize = 12;
        ink = SPPMk(); unit = SPPMk();
        UIView *track = [self addBit:@"track" to:card];
        track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.8];
        track.layer.cornerRadius = 2.5;
        track.layer.shadowColor = [UIColor blackColor].CGColor;
        track.layer.shadowOpacity = 0.15; track.layer.shadowRadius = 2; track.layer.shadowOffset = CGSizeMake(0, 1);
        UIView *fill = [self addBit:@"fill" to:track];
        fill.layer.cornerRadius = 2.5;
        fill.clipsToBounds = YES;
        CAGradientLayer *fg = [CAGradientLayer layer];
        fg.startPoint = CGPointMake(0, 0.5); fg.endPoint = CGPointMake(1, 0.5);
        fg.colors = SPPTrioColors();
        [fill.layer addSublayer:fg];
        self.parts[@"fillGrad"] = fg;
        break;
    }
    case SPPStyleNight: {
        num = 30;
        ink = [UIColor whiteColor]; unit = [UIColor colorWithWhite:1 alpha:0.6];
        [g setTop:SPPRGB(18, 20, 30, 0.82) bottom:SPPRGB(12, 13, 20, 0.86)];
        g.fill.borderWidth = 0;
        g.sheen.hidden = YES;
        g.layer.shadowColor = [UIColor blackColor].CGColor; g.layer.shadowOpacity = 0.35;
        CAShapeLayer *glow = [self shapePart:@"glow" in:card.layer stroke:SPPRGB(0xA7, 0x8B, 0xFA, 1) width:1.5];   // quang neon
        glow.shadowColor = SPPRGB(0xA7, 0x8B, 0xFA, 1).CGColor;
        glow.shadowRadius = 4; glow.shadowOpacity = 0.9; glow.shadowOffset = CGSizeZero;
        CAGradientLayer *ring = SPPStrokeGradient(YES, 1.5);
        [card.layer addSublayer:ring];
        self.parts[@"ring"] = ring;
        break;
    }
    case SPPStyleHUD: {
        num = 30;
        UIView *ticks = [self addBit:@"ticks" to:card];
        ticks.backgroundColor = [SPPMk() colorWithAlphaComponent:0.16];
        CAShapeLayer *mask = [CAShapeLayer layer];   // vach doc cao dan ve phia bien (hinh nem)
        ticks.layer.mask = mask;
        self.parts[@"ticksMask"] = mask;
        UIView *fill = [self addBit:@"fill" to:ticks];
        fill.clipsToBounds = YES;
        CAGradientLayer *fg = [CAGradientLayer layer];
        fg.startPoint = CGPointMake(0, 0.5); fg.endPoint = CGPointMake(1, 0.5);
        fg.colors = SPPTrioColors();
        [fill.layer addSublayer:fg];
        self.parts[@"fillGrad"] = fg;
        break;
    }
    case SPPStyleDash: {
        num = 24; unitSize = 9;
        ink = [UIColor whiteColor]; unit = [UIColor colorWithWhite:1 alpha:0.6];
        UIView *deco = [[UIView alloc] init];
        deco.userInteractionEnabled = NO;
        deco.layer.shadowColor = [UIColor blackColor].CGColor;
        deco.layer.shadowOpacity = 0.35; deco.layer.shadowRadius = 8; deco.layer.shadowOffset = CGSizeMake(0, 4);
        [card addSubview:deco];
        self.deco = deco;
        CAGradientLayer *face = [CAGradientLayer layer];
        face.type = kCAGradientLayerRadial;
        face.colors = @[(id)SPPRGB(0x2A, 0x2E, 0x45, 1).CGColor, (id)SPPRGB(0x0C, 0x0D, 0x14, 1).CGColor];
        face.masksToBounds = YES;
        [deco.layer addSublayer:face];
        self.parts[@"face"] = face;
        CAGradientLayer *ring = SPPStrokeGradient(YES, 3);
        [deco.layer addSublayer:ring];
        self.parts[@"ring"] = ring;
        [self shapePart:@"inner" in:deco.layer stroke:[UIColor colorWithWhite:1 alpha:0.08] width:1];
        CAShapeLayer *zone = [self shapePart:@"zone" in:deco.layer stroke:[SPPOver() colorWithAlphaComponent:0.9] width:3.5];
        zone.lineCap = kCALineCapButt;
        CAShapeLayer *limTick = [self shapePart:@"limTick" in:deco.layer stroke:SPPOver() width:2.5];
        limTick.lineCap = kCALineCapRound;
        CAShapeLayer *minor = [self shapePart:@"minor" in:deco.layer stroke:[UIColor colorWithWhite:1 alpha:0.45] width:1.2];
        CAShapeLayer *major = [self shapePart:@"major" in:deco.layer stroke:[UIColor colorWithWhite:1 alpha:0.9] width:2];
        minor.lineCap = kCALineCapRound; major.lineCap = kCALineCapRound;
        NSMutableArray *labels = [NSMutableArray array];
        for (int i = 0; i <= 8; i++) {
            UILabel *l = SPPLabel(SPPUnitFont(9), [UIColor colorWithWhite:1 alpha:0.85], NSTextAlignmentCenter);
            l.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
            [deco addSubview:l];
            [labels addObject:l];
        }
        self.tickLabels = labels;
        CAGradientLayer *prog = SPPStrokeGradient(NO, 3);
        prog.startPoint = CGPointMake(0, 1); prog.endPoint = CGPointMake(1, 0);
        [deco.layer addSublayer:prog];
        self.parts[@"prog"] = prog;
        CAShapeLayer *needle = [self shapePart:@"needle" in:deco.layer stroke:nil width:0];
        needle.fillColor = SPPRGB(0xFF, 0x5A, 0x36, 1).CGColor;
        needle.shadowColor = SPPRGB(0xFF, 0x5A, 0x36, 1).CGColor;
        needle.shadowRadius = 3; needle.shadowOpacity = 0.8; needle.shadowOffset = CGSizeZero;
        CAShapeLayer *hub = [self shapePart:@"hub" in:deco.layer stroke:[UIColor colorWithWhite:1 alpha:0.85] width:1.5];
        hub.fillColor = SPPRGB(0x23, 0x26, 0x3A, 1).CGColor;
        break;
    }
    }
    self.speedLabel = SPPLabel(SPPNumFont(num), ink, NSTextAlignmentCenter);
    self.unitLabel = SPPLabel(SPPUnitFont(unitSize), unit, NSTextAlignmentCenter);
    if (style == SPPStyleMin) for (UILabel *l in @[self.speedLabel, self.unitLabel]) SPPGlow(l, [UIColor whiteColor], 4);
    if (style == SPPStyleNight || style == SPPStyleDash) SPPGlow(self.speedLabel, SPPRGB(140, 190, 255, 0.7), 8);
    [card addSubview:self.speedLabel];
    [card addSubview:self.unitLabel];
    self.sign = [[SPPSignView alloc] init];
    [card addSubview:self.sign];
    self.iconView = [[SPPIconView alloc] init];
    self.iconView.shape = SPPIconCircle;
    [card addSubview:self.iconView];
    self.iconApp = -1;
    self.builtStyle = style;
    SPPLog("bubble: kieu %ld", (long)style);
}

// Vuot gioi han (moi kieu): nen / quang do nhay, bien gioi han dap theo nhip
- (void)setOverLimitWarning:(BOOL)on
{
    UIView *f = self.flashView;
    BOOL running = [f.layer animationForKey:@"sppFlash"] != nil;
    if (on == running) return;
    if (on) {
        CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
        blink.fromValue = @0.0; blink.toValue = @0.5;
        blink.duration = 0.5; blink.autoreverses = YES; blink.repeatCount = HUGE_VALF;
        blink.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        f.alpha = 1; f.layer.opacity = 0;
        [f.layer addAnimation:blink forKey:@"sppFlash"];
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @1.0; pulse.toValue = @1.1;
        pulse.duration = 0.5; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
        [self.sign.layer addAnimation:pulse forKey:@"sppPulse"];
        SPPLog("bubble: vuot gioi han -> nhay canh bao");
    } else {
        [f.layer removeAnimationForKey:@"sppFlash"];
        f.alpha = 0;
        [self.sign.layer removeAnimationForKey:@"sppPulse"];
    }
}

// Mau so: kinh trang -> cham / ho phach / do; nen toi -> trang / vang nhat / hong do; nen mau (Cap doi vuot, The gan / vuot) -> trang
- (UIColor *)numberColor
{
    int st = [self speedState];
    switch (self.builtStyle) {
    case SPPStyleNight: case SPPStyleDash:
        return st == 2 ? SPPRGB(0xFF, 0x8A, 0x8D, 1) : st == 1 ? SPPRGB(0xFF, 0xD5, 0x8A, 1) : [UIColor whiteColor];
    case SPPStyleTwin: if (st == 2) return [UIColor whiteColor]; break;
    case SPPStyleTile: if (st > 0) return [UIColor whiteColor]; break;
    }
    return st == 2 ? SPPOverText() : st == 1 ? SPPNearText() : SPPMk();
}

// So hien tren bong bong: app nguon luon gui km/h; mph thi doi + lam tron. So sanh gan / vuot gioi han van tren
// km/h goc (self.speed / self.limit) nen khong lech do lam tron
static int SPPShown(int kmh, BOOL mph)
{
    if (kmh < 0 || !mph) return kmh;
    return (int)lround(kmh / 1.609344);
}

static void SPPPlace(UIView *v, CGFloat cx, CGFloat cy, CGFloat size)
{
    v.bounds = CGRectMake(0, 0, size, size);
    v.center = CGPointMake(cx, cy);
    [v setNeedsLayout];
}

// So + don vi xep doc, can giua theo cx, dinh o top (khoi cao = so + 1 + don vi)
- (void)stackNumberAt:(CGFloat)cx top:(CGFloat)top width:(CGFloat)w
{
    CGFloat nh = ceil(self.speedLabel.font.lineHeight), uh = ceil(self.unitLabel.font.lineHeight);
    self.speedLabel.frame = CGRectMake(cx - w / 2, top, w, nh);
    self.unitLabel.frame = CGRectMake(cx - w / 2, top + nh - 3, w, uh);
}
- (CGFloat)stackHeight { return ceil(self.speedLabel.font.lineHeight) - 3 + ceil(self.unitLabel.font.lineHeight); }

// km/h cung dong day (baseline) voi so, ngay sau so
static void SPPUnitAfter(UILabel *unit, UILabel *number, CGFloat gap)
{
    CGFloat base = CGRectGetMinY(number.frame) + number.font.ascender + (number.frame.size.height - number.font.lineHeight) / 2;
    CGFloat uw = ceil([unit sizeThatFits:CGSizeMake(200, 40)].width);
    unit.frame = CGRectMake(CGRectGetMaxX(number.frame) + gap, base - unit.font.ascender, uw, unit.font.lineHeight);
}

// Thanh tien do co hieu ung (khong lam moi khi dang ve)
static void SPPAnimateWidth(UIView *fill, CGFloat w, NSTimeInterval duration)
{
    CGRect f = fill.frame;
    if (fabs(f.size.width - w) < 0.25) return;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{ fill.frame = CGRectMake(0, 0, w, fill.superview.bounds.size.height); } completion:nil];
}

// Dat so + mau + bo cuc theo kieu, giu tam the co dinh
- (void)renderStyle
{
    BOOL hasLimit = self.limit > 0;
    BOOL showIcon = [SPPPrefs showAppIcon];
    int state = [self speedState];
    UIColor *sc = [self stateColor];
    BOOL mph = [SPPPrefs useMph];
    CGFloat ratio = [self speedRatio];
    self.speedLabel.text = self.speed >= 0 ? [NSString stringWithFormat:@"%d", SPPShown(self.speed, mph)] : @"--";
    self.speedLabel.textColor = [self numberColor];
    self.unitLabel.text = mph ? @"mph" : @"km/h";
    self.sign.usStyle = [SPPPrefs usSign];
    self.sign.label.text = hasLimit ? [NSString stringWithFormat:@"%d", SPPShown(self.limit, mph)] : @"--";
    self.sign.muted = !hasLimit;
    self.iconView.hidden = !showIcon;
    if (showIcon && self.iconApp != self.app) { self.iconView.imageView.image = SPPAppIcon(self.app); self.iconApp = self.app; }

    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGPoint c = self.card.center;
    CGSize size = CGSizeZero;
    UIView *halo = nil;   // hinh chinh de ve quang do nhay xung quanh (nil = nhay trong nen)
    switch (self.builtStyle) {
    case SPPStylePill: {
        CGFloat h = 60, x = 10, mid = h / 2;
        UIView *dot = [self bit:@"dot"];
        dot.hidden = showIcon;
        dot.backgroundColor = state == 0 ? SPPRGB(0x5E, 0xDD, 0xB6, 1) : sc;
        if (showIcon) { SPPPlace(self.iconView, x + 11, mid, 22); x += 22 + 10; }
        else { dot.frame = CGRectMake(x, mid - 4, 8, 8); x += 8 + 6; }
        CGFloat cw = MAX(52, ceil([self.speedLabel sizeThatFits:CGSizeMake(200, 40)].width));
        [self stackNumberAt:x + cw / 2 top:mid - [self stackHeight] / 2 width:cw];
        x += cw + 10;
        [self bit:@"bar"].frame = CGRectMake(x, mid - 16, 1.5, 32);
        x += 1.5 + 10;
        SPPPlace(self.sign, x + 22, mid, 44);
        size = CGSizeMake(x + 44 + 8, h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = h / 2;
        break;
    }
    case SPPStyleTwin: {
        CGFloat d = 76, o = 4, sg = 72;
        self.glass.frame = CGRectMake(o, o, d, d); self.glass.corner = d / 2;
        if (state == 2) [self.glass setTop:SPPOver() bottom:SPPRGB(0xF0, 0x40, 0x46, 1)];
        else [self.glass setTop:SPPRGB(255, 255, 255, 0.9) bottom:SPPRGB(0xF1, 0xF0, 0xFB, 0.9)];
        CAShapeLayer *nr = (CAShapeLayer *)self.parts[@"nearRing"];
        nr.hidden = state != 1;
        nr.frame = CGRectMake(0, 0, d, d);
        nr.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1.5, 1.5, d - 3, d - 3)].CGPath;
        self.unitLabel.textColor = state == 2 ? [UIColor whiteColor] : SPPMk2();
        [self stackNumberAt:o + d / 2 top:o + d / 2 - [self stackHeight] / 2 width:d - 12];
        SPPPlace(self.iconView, 10, 10, 20);
        SPPPlace(self.sign, o + d + 8 + sg / 2, o + d / 2, sg);
        size = CGSizeMake(o + d + 8 + sg, o + d);
        halo = self.glass;
        break;
    }
    case SPPStyleArc: {
        CGFloat d = 104, r = d / 2, sg = 46;
        CGPoint m = CGPointMake(r, r);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        UIBezierPath *arc = SPPArc(m, 46, 135, 405);
        CAShapeLayer *track = (CAShapeLayer *)self.parts[@"track"];
        track.frame = CGRectMake(0, 0, d, d); track.path = arc.CGPath;
        CAGradientLayer *fill = (CAGradientLayer *)self.parts[@"fill"];
        SPPStrokePath(fill, CGRectMake(0, 0, d, d), arc);
        fill.colors = state == 0 ? SPPTrioColors() : @[(id)sc.CGColor, (id)sc.CGColor];
        [CATransaction setDisableActions:NO]; [CATransaction setAnimationDuration:0.6];
        ((CAShapeLayer *)fill.mask).strokeEnd = ratio;
        [CATransaction setDisableActions:YES];
        [self stackNumberAt:r top:r - 6 - [self stackHeight] / 2 width:d - 24];
        SPPPlace(self.iconView, 10, 12, 20);
        SPPPlace(self.sign, r, d + 18 - sg / 2, sg);
        size = CGSizeMake(d, d + 18);
        halo = self.glass;
        break;
    }
    case SPPStyleTile: {
        CGFloat w = 124, pad = 12, sg = 48;
        self.glass.frame = CGRectMake(0, 0, w, w); self.glass.corner = 28;
        CAGradientLayer *mesh = (CAGradientLayer *)self.parts[@"mesh"];
        mesh.frame = CGRectMake(0, 0, w, w);
        mesh.hidden = state != 0;
        if (state == 2) [self.glass setTop:SPPRGB(0xFF, 0x8A, 0x8D, 1) bottom:SPPRGB(0xFF, 0x4F, 0x55, 1)];
        else if (state == 1) [self.glass setTop:SPPRGB(0xFF, 0xD5, 0x8A, 1) bottom:SPPNear()];
        else [self.glass setTop:SPPRGB(0xC9, 0xBA, 0xFC, 0.97) bottom:SPPRGB(0xA0, 0xF1, 0xD9, 0.97)];
        self.glass.sheen.hidden = state != 0;
        if (showIcon) SPPPlace(self.iconView, pad + 11, pad + 11, 22);
        SPPPlace(self.sign, w - pad - sg / 2, pad + sg / 2, sg);
        self.unitLabel.textColor = state ? [UIColor whiteColor] : SPPMk2();
        CGFloat nw = ceil([self.speedLabel sizeThatFits:CGSizeMake(200, 50)].width);
        self.speedLabel.frame = CGRectMake(pad, 83 - 24, nw, 48);
        SPPUnitAfter(self.unitLabel, self.speedLabel, 4);
        UIView *track = [self bit:@"track"], *fill = [self bit:@"fill"];
        track.frame = CGRectMake(pad, w - pad - 6, w - 2 * pad, 6);
        ((CAGradientLayer *)self.parts[@"fillGrad"]).frame = CGRectMake(0, 0, track.bounds.size.width, 6);
        ((CAGradientLayer *)self.parts[@"fillGrad"]).hidden = state != 0;
        fill.backgroundColor = state ? [UIColor whiteColor] : [UIColor clearColor];
        [CATransaction setDisableActions:NO];
        SPPAnimateWidth(fill, track.bounds.size.width * ratio, 0.6);
        [CATransaction setDisableActions:YES];
        size = CGSizeMake(w, w);
        break;
    }
    case SPPStyleMin: {
        CGFloat y = showIcon ? 24 : 0, sg = 40;
        if (showIcon) SPPPlace(self.iconView, 10, 10, 20);
        self.unitLabel.textColor = SPPMk();
        CGFloat nw = ceil([self.speedLabel sizeThatFits:CGSizeMake(220, 60)].width);
        self.speedLabel.frame = CGRectMake(0, y, nw, 52);
        SPPUnitAfter(self.unitLabel, self.speedLabel, 4);
        CGFloat colW = MAX(CGRectGetMaxX(self.unitLabel.frame), 92), ly = y + 52 + 3;
        UIView *track = [self bit:@"track"], *fill = [self bit:@"fill"];
        track.frame = CGRectMake(0, ly, 92, 5);
        CAGradientLayer *fg = (CAGradientLayer *)self.parts[@"fillGrad"];
        fg.frame = CGRectMake(0, 0, 92, 5);
        fg.colors = state == 0 ? SPPTrioColors() : @[(id)sc.CGColor, (id)sc.CGColor];
        [CATransaction setDisableActions:NO];
        SPPAnimateWidth(fill, 92 * ratio, 0.6);
        [CATransaction setDisableActions:YES];
        SPPPlace(self.sign, colW + 8 + sg / 2, ly + 5 - 8 - sg / 2, sg);
        size = CGSizeMake(colW + 8 + sg, ly + 5);
        halo = self.speedLabel;
        break;
    }
    case SPPStyleNight: {
        CGFloat w = 70, sg = 50, y = 8 + sg + 8;
        SPPPlace(self.sign, w / 2, 8 + sg / 2, sg);
        [self stackNumberAt:w / 2 top:y width:w - 8];
        y += [self stackHeight];
        if (showIcon) { SPPPlace(self.iconView, w / 2, y + 8 + 9, 18); y += 8 + 18; }
        size = CGSizeMake(w, y + 12);
        self.glass.frame = CGRectMake(0, 0, w, size.height); self.glass.corner = w / 2;
        UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.75, 0.75, w - 1.5, size.height - 1.5) cornerRadius:w / 2 - 0.75];
        CAGradientLayer *ring = (CAGradientLayer *)self.parts[@"ring"];
        SPPStrokePath(ring, CGRectMake(0, 0, w, size.height), rim);
        ring.colors = state == 0 ? SPPAuroraColors() : @[(id)sc.CGColor, (id)sc.CGColor];
        CAShapeLayer *glow = (CAShapeLayer *)self.parts[@"glow"];
        glow.frame = CGRectMake(0, 0, w, size.height); glow.path = rim.CGPath;
        glow.strokeColor = (state == 0 ? SPPRGB(0xA7, 0x8B, 0xFA, 1) : sc).CGColor;
        glow.shadowColor = glow.strokeColor;
        self.speedLabel.layer.shadowColor = (state == 2 ? SPPOver() : state == 1 ? SPPNear() : SPPRGB(140, 190, 255, 0.7)).CGColor;
        break;
    }
    case SPPStyleHUD: {
        CGFloat h = 58, mid = h / 2, x = 10, tw = 61, th = 24, sg = 50;
        if (showIcon) { SPPPlace(self.iconView, 6 + 11, mid, 22); x = 6 + 22 + 8; }
        CGFloat cw = MAX(ceil([self.speedLabel sizeThatFits:CGSizeMake(200, 40)].width), ceil([self.unitLabel sizeThatFits:CGSizeMake(200, 20)].width));
        [self stackNumberAt:x + cw / 2 top:mid - [self stackHeight] / 2 width:cw];
        x += cw + 8;
        UIView *ticks = [self bit:@"ticks"], *fill = [self bit:@"fill"];
        ticks.frame = CGRectMake(x, mid - th / 2, tw, th);
        UIBezierPath *mp = [UIBezierPath bezierPath];
        for (CGFloat tx = 0; tx + 5 <= tw + 0.5; tx += 8) {   // vach 5 pt cach 3 pt, dinh theo duong nem
            CGFloat top = th * 0.62 * (1 - (tx + 2.5) / tw);
            [mp appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(tx, top, 5, th - top) cornerRadius:1.5]];
        }
        CAShapeLayer *mask = (CAShapeLayer *)self.parts[@"ticksMask"];
        mask.frame = ticks.bounds; mask.path = mp.CGPath;
        CAGradientLayer *fg = (CAGradientLayer *)self.parts[@"fillGrad"];
        fg.frame = CGRectMake(0, 0, tw, th);
        fg.colors = state == 2 ? @[(id)SPPOver().CGColor, (id)SPPOver().CGColor]
                  : state == 1 ? @[(id)SPPRGB(0xFF, 0xD5, 0x8A, 1).CGColor, (id)SPPNear().CGColor] : SPPTrioColors();
        [CATransaction setDisableActions:NO];
        SPPAnimateWidth(fill, tw * ratio, 0.9);   // vach sang chay dan toi bien gioi han
        [CATransaction setDisableActions:YES];
        x += tw + 8;
        SPPPlace(self.sign, x + sg / 2, mid, sg);
        size = CGSizeMake(x + sg + 4, h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = h / 2;
        break;
    }
    case SPPStyleDash: {
        // Goc 150 do (duoi trai) -> 390 do (duoi phai), quet 240 do theo chieu kim dong ho
        CGFloat d = 140, r = d / 2, sg = 66, top = mph ? 100 : 160;
        CGPoint m = CGPointMake(r, r);
        CGFloat (^ang)(CGFloat) = ^CGFloat(CGFloat v) { return 150 + 240 * MIN(1.04, MAX(0, v) / top); };
        CGPoint (^pt)(CGFloat, CGFloat) = ^CGPoint(CGFloat rad, CGFloat deg) { return CGPointMake(r + rad * cos(deg * M_PI / 180), r + rad * sin(deg * M_PI / 180)); };
        self.deco.frame = CGRectMake(0, 0, d, d);
        self.deco.layer.shadowPath = SPPCircle(m, r).CGPath;
        CAGradientLayer *face = (CAGradientLayer *)self.parts[@"face"];
        face.frame = CGRectMake(0, 0, d, d); face.cornerRadius = r;
        face.startPoint = CGPointMake(0.5, 0.42); face.endPoint = CGPointMake(1.1, 1.02);
        SPPStrokePath((CAGradientLayer *)self.parts[@"ring"], CGRectMake(0, 0, d, d), SPPCircle(m, 67));
        ((CAShapeLayer *)self.parts[@"inner"]).path = SPPCircle(m, 64).CGPath;
        UIBezierPath *minor = [UIBezierPath bezierPath], *major = [UIBezierPath bezierPath];
        NSInteger li = 0;
        for (int v = 0; v <= (int)top; v += 10) {
            BOOL big = v % 20 == 0;
            CGFloat a = ang(v);
            UIBezierPath *bp = big ? major : minor;
            [bp moveToPoint:pt(big ? 53 : 57, a)]; [bp addLineToPoint:pt(61, a)];
            if (big && li < (NSInteger)self.tickLabels.count) {
                UILabel *l = self.tickLabels[li++];
                l.hidden = NO;
                l.text = [NSString stringWithFormat:@"%d", v];
                CGPoint p = pt(43, a);
                l.frame = CGRectMake(p.x - 12, p.y - 6, 24, 12);
            }
        }
        for (; li < (NSInteger)self.tickLabels.count; li++) self.tickLabels[li].hidden = YES;
        ((CAShapeLayer *)self.parts[@"minor"]).path = minor.CGPath;
        ((CAShapeLayer *)self.parts[@"major"]).path = major.CGPath;
        CGFloat cl = hasLimit ? SPPShown(self.limit, mph) : 0, cv = MAX(0, SPPShown(self.speed, mph));
        CAShapeLayer *zone = (CAShapeLayer *)self.parts[@"zone"], *limTick = (CAShapeLayer *)self.parts[@"limTick"];
        zone.hidden = limTick.hidden = !(hasLimit && cl < top);
        if (!zone.hidden) {
            zone.path = SPPArc(m, 63, ang(cl), ang(top)).CGPath;
            UIBezierPath *lt = [UIBezierPath bezierPath];
            [lt moveToPoint:pt(52, ang(cl))]; [lt addLineToPoint:pt(65, ang(cl))];
            limTick.path = lt.CGPath;
        }
        CAGradientLayer *prog = (CAGradientLayer *)self.parts[@"prog"];
        SPPStrokePath(prog, CGRectMake(0, 0, d, d), SPPArc(m, 49, 150, 390));
        prog.colors = state == 0 ? SPPTrioColors() : @[(id)sc.CGColor, (id)sc.CGColor];
        CAShapeLayer *needle = (CAShapeLayer *)self.parts[@"needle"];
        needle.bounds = CGRectMake(0, 0, d, d);   // lop dang xoay: dat bounds + position (khong dat frame)
        needle.position = m;
        UIBezierPath *np = [UIBezierPath bezierPath];
        [np moveToPoint:CGPointMake(58, 67.8)]; [np addLineToPoint:CGPointMake(117, 70)]; [np addLineToPoint:CGPointMake(58, 72.2)]; [np closePath];
        needle.path = np.CGPath;
        ((CAShapeLayer *)self.parts[@"hub"]).path = SPPCircle(m, 7).CGPath;
        [CATransaction setDisableActions:NO]; [CATransaction setAnimationDuration:0.6];
        ((CAShapeLayer *)prog.mask).strokeEnd = MIN(1.0, (ang(cv) - 150) / 240);
        needle.transform = CATransform3DMakeRotation(ang(cv) * M_PI / 180, 0, 0, 1);
        [CATransaction setDisableActions:YES];
        self.speedLabel.frame = CGRectMake(r - 40, 86, 80, 28);
        self.unitLabel.frame = CGRectMake(r - 30, 112, 60, 11);
        self.speedLabel.layer.shadowColor = (state == 2 ? SPPOver() : state == 1 ? SPPNear() : SPPRGB(140, 190, 255, 0.6)).CGColor;
        SPPPlace(self.iconView, 2 + 12, 2 + 12, 24);
        SPPPlace(self.sign, d + 24 - sg / 2, d + 18 - sg / 2, sg);
        size = CGSizeMake(d + 24, d + 18);
        halo = self.deco;
        break;
    }
    case SPPStyleDrop:
    default: {
        CGFloat d = 100, o = 16, lp = 4, sg = 50;
        self.glass.frame = CGRectMake(lp, o, d, d); self.glass.corner = d / 2;
        CAGradientLayer *ring = (CAGradientLayer *)self.parts[@"ring"];
        SPPStrokePath(ring, CGRectMake(0, 0, d, d), [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1.5, 1.5, d - 3, d - 3)]);
        ring.colors = state == 0 ? SPPAuroraColors() : @[(id)sc.CGColor, (id)sc.CGColor];
        CAGradientLayer *shine = (CAGradientLayer *)self.parts[@"shine"];
        shine.frame = CGRectMake(d * 0.16, d * 0.09, d * 0.46, d * 0.26);
        shine.cornerRadius = d * 0.13;
        [self stackNumberAt:lp + d / 2 top:o + d / 2 + 2 - [self stackHeight] / 2 width:d - 16];
        SPPPlace(self.iconView, 11, o + d + 2 - 11, 22);
        SPPPlace(self.sign, lp + d + o - sg / 2, sg / 2, sg);
        size = CGSizeMake(lp + d + o, o + d + 2);
        halo = self.glass;
        break;
    }
    }

    // Vung nhay: quang tron quanh hinh chinh, hoac phu kin nen
    if (halo) {
        CGRect hr = CGRectInset(halo.frame, -6, -6);
        self.flashView.frame = hr;
        self.flashView.layer.cornerRadius = halo == self.speedLabel ? 16 : MIN(hr.size.width, hr.size.height) / 2;
    } else {
        self.flashView.frame = self.glass.bounds;
        self.flashView.layer.cornerRadius = self.glass.corner;
    }
    // Hinh chinh de ve vien "giu de thoat": ca the (Toi gian), mat dong ho (Dong ho taplo), con lai la nen kinh
    if (self.builtStyle == SPPStyleMin) { self.outlineRect = CGRectMake(0, 0, size.width, size.height); self.outlineCorner = 16; }
    else if (self.builtStyle == SPPStyleDash) { self.outlineRect = self.deco.frame; self.outlineCorner = self.deco.frame.size.width / 2; }
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
        if (!SPPIsGPSSource(self.app)) [self startHold];   // GPS iPhone: khong co app de thoat, giu chi de keo
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
    if (SPPIsGPSSource(self.app)) return;
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
    if (SPPIsGPSSource(self.app)) return;   // GPS iPhone: khong co app de mo
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

#pragma mark - Auto test (developer only)

#if OMC_AUTOTEST
#import "OMCTest.h"

// Bo test "speedBubble" (Core/OMCTest.h), chay trong SpringBoard khi xe da ket noi: bom toc do gia vao dung duong
// app dan duong gui (updateSpeed:...), kiem bong bong hien tren xe, so dung, trang thai gan / vuot gioi han, an khi
// Split Screen chiem man xe, ve dung moi kieu, co lon, an khi mat nguon. Kieu / co lon cua nguoi dung duoc tra lai.
static NSTimer *sSPPTestTimer;   // gia lam "Xem thu" (demoTimer): bo qua dieu kien "app da duoc mo"
static id sSPPTestStyle, sSPPTestSizeCar;

static void SPPTestFeed(int speed, int limit)
{
    SPPBubble *b = [SPPBubble shared];
    if (!sSPPTestTimer) sSPPTestTimer = [NSTimer timerWithTimeInterval:1e6 repeats:NO block:^(NSTimer *t) {}];
    b.demoTimer = sSPPTestTimer;
    [b updateSpeed:speed limit:limit appForeground:NO app:b.app];
}

static void SPPTestEnd(void)
{
    SPPBubble *b = [SPPBubble shared];
    if (b.demoTimer == sSPPTestTimer) b.demoTimer = nil;
    sSPPTestTimer = nil;
    b.speed = -1; b.limit = -1; b.speedAt = 0; b.limitAt = 0; b.lastUpdate = 0;
    [b refresh];
}

static void SPPTestSetPref(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, OMC_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

static NSString *SPPTestState(void)
{
    SPPBubble *b = [SPPBubble shared];
    return OMCTestFormat(@"window=%d hidden=%d alpha=%.2f onPhone=%d speed=%d limit=%d state=%d style=%ld/%ld scale=%.2f card=%@ carBusy=%d fg=%d",
        b.window != nil, b.window.hidden, b.card.alpha, b.onPhone, b.speed, b.limit, [b speedState], (long)b.builtStyle, (long)[SPPPrefs style],
        b.scale, NSStringFromCGRect(b.card.frame), b.carBusy, [b anyAppForeground]);
}

static NSString *SPPTestWhy(NSString *why) { return why ? [NSString stringWithFormat:@"%@ || %@", why, SPPTestState()] : nil; }

static NSString *SPPTestVisibleOnCar(void)
{
    SPPBubble *b = [SPPBubble shared];
    if (!b.window || b.window.hidden || b.card.alpha < 0.9) return SPPTestWhy(@"bong bong khong hien");
    if (b.onPhone) return SPPTestWhy(@"bong bong dang o iPhone, khong o man xe");
    if ([b anyAppForeground]) return SPPTestWhy(@"app dan duong dang mo tren man hinh (bong bong co tinh an)");
    CGRect inWin = [b.card convertRect:b.card.bounds toView:b.window];
    if (inWin.size.width < 20 || !CGRectIntersectsRect(inWin, b.window.bounds)) return SPPTestWhy(@"the bong bong ra ngoai man xe");
    return nil;
}

static NSArray<NSDictionary *> *SPPTestSteps(void)
{
    NSMutableArray *steps = [NSMutableArray array];
    SPPBubble *b = [SPPBubble shared];
    sSPPTestStyle = OMCPref(SB_KEY_STYLE, nil);
    sSPPTestSizeCar = OMCPref(SB_KEY_SIZE_CAR, nil);

    [steps addObject:OMCTestStep(@"Moi truong: bat bong bong, co man xe", 0, 0, nil, ^NSString *{
        if (![SPPPrefs enabled]) return @"Bong bong toc do dang tat";
        if (!SPPGetCarPlayCADisplay()) return @"khong thay man CarPlay";
        return nil;
    })];
    if (![SPPPrefs enabled]) return steps;

    [steps addObject:OMCTestStep(@"Hien tren xe khi co toc do (50 / 60)", 1, 5, ^NSString *{ SPPTestFeed(50, 60); return nil; },
        ^NSString *{ SPPTestFeed(50, 60); return SPPTestVisibleOnCar(); })];
    [steps addObject:OMCTestStep(@"So toc do dung", 0.5, 3, ^NSString *{ SPPTestFeed(57, 60); return nil; }, ^NSString *{
        SPPTestFeed(57, 60);
        if (b.speed != 57 || b.limit != 60) return SPPTestWhy(@"toc do / gioi han khong khop");
        NSString *want = [NSString stringWithFormat:@"%d", SPPShown(57, [SPPPrefs useMph])];   // mph: 35
        if (b.speedLabel && ![b.speedLabel.text isEqualToString:want]) return SPPTestWhy(OMCTestFormat(@"chu hien '%@', can %@", b.speedLabel.text, want));
        return nil;
    })];
    [steps addObject:OMCTestStep(@"Gan gioi han (57 / 60) -> canh bao", 0.5, 3, nil, ^NSString *{
        SPPTestFeed(57, 60);
        return [b speedState] == 1 ? nil : SPPTestWhy(@"khong o trang thai gan gioi han");
    })];
    [steps addObject:OMCTestStep(@"Vuot gioi han (75 / 60) -> do", 0.5, 3, nil, ^NSString *{
        SPPTestFeed(75, 60);
        return [b speedState] == 2 ? nil : SPPTestWhy(@"khong o trang thai vuot gioi han");
    })];
    [steps addObject:OMCTestStep(@"Duoi gioi han (40 / 60) -> binh thuong", 0.5, 3, nil, ^NSString *{
        SPPTestFeed(40, 60);
        return [b speedState] == 0 ? nil : SPPTestWhy(@"van canh bao khi da cham lai");
    })];
    [steps addObject:OMCTestStep(@"Split Screen chiem man xe -> an", 0.8, 3, ^NSString *{ [b setCarBusy:YES]; return nil; }, ^NSString *{
        SPPTestFeed(40, 60);
        return (b.window.hidden || b.card.alpha < 0.1) ? nil : SPPTestWhy(@"van hien khi man xe ban");
    })];
    [steps addObject:OMCTestStep(@"Man xe ranh -> hien lai", 0.8, 4, ^NSString *{ [b setCarBusy:NO]; return nil; },
        ^NSString *{ SPPTestFeed(40, 60); return SPPTestVisibleOnCar(); })];

    for (NSInteger style = 0; style < SPP_STYLE_COUNT; style++) {
        [steps addObject:OMCTestStep(OMCTestFormat(@"Kieu %ld", (long)style), 0.8, 4, ^NSString *{
            SPPTestSetPref(SB_KEY_STYLE, @(style));
            SPPTestFeed(style % 3 == 2 ? 72 : 48, 60);   // vai kieu ve luc vuot gioi han
            return nil;
        }, ^NSString *{
            SPPTestFeed(style % 3 == 2 ? 72 : 48, 60);
            if (b.builtStyle != style) return SPPTestWhy(OMCTestFormat(@"dang ve kieu %ld", (long)b.builtStyle));
            return SPPTestVisibleOnCar();
        })];
    }
    [steps addObject:OMCTestStep(@"Tra lai kieu cua nguoi dung", 0.5, 3, ^NSString *{ SPPTestSetPref(SB_KEY_STYLE, sSPPTestStyle); return nil; },
        ^NSString *{ SPPTestFeed(48, 60); return b.builtStyle == [SPPPrefs style] ? nil : SPPTestWhy(@"kieu chua ve lai"); })];

    for (NSNumber *pct in @[@60, @220]) {
        [steps addObject:OMCTestStep(OMCTestFormat(@"Co %@%% tren xe", pct), 0.8, 4, ^NSString *{ SPPTestSetPref(SB_KEY_SIZE_CAR, pct); return nil; },
            ^NSString *{
            SPPTestFeed(48, 60);
            CGFloat want = SPP_SCALE_BASE * pct.doubleValue / 100.0;
            if (fabs(b.scale - want) > 0.02) return SPPTestWhy(OMCTestFormat(@"ti le %.2f, can %.2f", b.scale, want));
            return SPPTestVisibleOnCar();
        })];
    }
    [steps addObject:OMCTestStep(@"Tra lai co cua nguoi dung", 0.5, 3, ^NSString *{ SPPTestSetPref(SB_KEY_SIZE_CAR, sSPPTestSizeCar); return nil; },
        ^NSString *{ SPPTestFeed(48, 60); return SPPTestVisibleOnCar(); })];

    [steps addObject:OMCTestStep(@"Mat nguon toc do -> an", 1, 4, ^NSString *{ SPPTestEnd(); return nil; },
        ^NSString *{ return (!b.window || b.window.hidden || b.card.alpha < 0.1) ? nil : SPPTestWhy(@"van hien khi khong con nguon"); })];
    return steps;
}

void SPPAutoTestInstall(void)
{
    OMCTestRegister(SB_FEATURE, ^BOOL { return SPPGetCarPlayCADisplay() != nil; }, ^NSArray<NSDictionary *> *{ return SPPTestSteps(); }, ^NSArray<UIWindow *> *{
        UIWindow *w = [SPPBubble shared].window;
        return w ? @[w] : @[];
    });
}
#endif
