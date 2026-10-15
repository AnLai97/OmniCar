// Bong bong toc do: ve 1 bong bong theo kieu (SPPStyle, SB_KEY_STYLE) - so toc do, don vi, bien gioi han, icon app nguon,
// trang thai binh thuong / sap cham / vuot. Dung chung: tweak (SPPBubble.mm dat no trong the tren man xe / iPhone) va trang
// Cai dat (Prefs/SPPBubbleViewPrefs.m: xem truoc song + dai chon kieu), nen Cai dat ve dung nhu tren xe.
// Ban duyet: tools/preview/index.html#bubble. Chi UIKit / QuartzCore, khong doc prefs, khong ghi log truc tiep (log).
#import "SPPBubbleView.h"
#import "SpeedBubble.h"
#import <QuartzCore/QuartzCore.h>

#define SPPBVLog(fmt, ...) do { if (self.log) self.log([NSString stringWithFormat:fmt, ##__VA_ARGS__]); } while (0)

typedef NS_ENUM(NSInteger, SPPStyle) {
    SPPStyleDrop = 0, SPPStylePill, SPPStyleTwin, SPPStyleArc, SPPStyleTile, SPPStyleMin, SPPStyleNight, SPPStyleHUD, SPPStyleDash,
};

// ---------------------------------------------------------------------
//  Thanh phan ve bong bong (mau, font, nen kinh, icon app, bien gioi han)
// ---------------------------------------------------------------------
static UIColor *SPPRGB(int r, int g, int b, CGFloat a) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a]; }
static UIColor *SPPSignRed(void) { return SPPRGB(229, 38, 45, 1); }
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



@interface SPPBubbleView ()
@property (nonatomic, readwrite) NSInteger builtStyle;
@property (nonatomic, readwrite) CGRect outlineRect;
@property (nonatomic, readwrite) CGFloat outlineCorner;
@property (nonatomic) CGSize contentSize;
@property (nonatomic, strong) SPPGlassView *glass;   // nen kinh cua kieu dang ve
@property (nonatomic, strong) SPPIconView *iconView; // icon app nguon
@property (nonatomic, strong) SPPSignView *sign;     // bien gioi han toc do
@property (nonatomic, strong, readwrite) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@property (nonatomic, strong) UIView *deco;                          // Dong ho taplo: mat dong ho (lop ve rieng duoi chu)
@property (nonatomic, strong) NSMutableDictionary<NSString *, CALayer *> *parts;   // lop ve rieng cua kieu dang ve, theo ten
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *bits;     // view rieng (thanh tien do, vach, cham...)
@property (nonatomic, strong) NSArray<UILabel *> *tickLabels;        // Dong ho taplo: so tren mat
@property (nonatomic, strong) UIView *flashView;     // nen / quang do nhay khi vuot gioi han (moi kieu)
@end

@implementation SPPBubbleView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _builtStyle = -1; _speed = -1; _limit = -1; _showIcon = YES;
        self.userInteractionEnabled = NO;   // cu chi do the chua no xu ly
    }
    return self;
}

// =====================================================================
//  Cac kieu bong bong (Settings > OmniCar > Speed Bubble > Style), ban duyet: tools/preview/index.html#bubble.
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
    UIView *card = self;
    for (UIView *v in [card.subviews copy]) [v removeFromSuperview];
    for (CALayer *l in [card.layer.sublayers copy]) [l removeFromSuperlayer];
    self.glass = nil; self.iconView = nil; self.sign = nil; self.flashView = nil; self.deco = nil;
    self.speedLabel = nil; self.unitLabel = nil; self.tickLabels = nil;
    self.parts = [NSMutableDictionary dictionary];
    self.bits = [NSMutableDictionary dictionary];
    if (style < 0 || style >= SB_STYLE_COUNT) style = SPPStyleDrop;

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
    self.iconView.shape = SPPIconSquircle;   // icon nguon: o vuong bo goc
    [card addSubview:self.iconView];
    self.iconView.imageView.image = nil;   // render dat lai icon
    self.builtStyle = style;
    SPPBVLog(@"bubble: kieu %ld", (long)style);
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
        SPPBVLog(@"bubble: vuot gioi han -> nhay canh bao");
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
    BOOL showIcon = self.showIcon;
    int state = [self speedState];
    UIColor *sc = [self stateColor];
    BOOL mph = self.mph;
    CGFloat ratio = [self speedRatio];
    self.speedLabel.text = self.speed >= 0 ? [NSString stringWithFormat:@"%d", SPPShown(self.speed, mph)] : @"--";
    self.speedLabel.textColor = [self numberColor];
    self.unitLabel.text = mph ? @"mph" : @"km/h";
    self.sign.usStyle = self.usSign;
    self.sign.label.text = hasLimit ? [NSString stringWithFormat:@"%d", SPPShown(self.limit, mph)] : @"--";
    self.sign.muted = !hasLimit;
    self.iconView.hidden = !showIcon;
    if (showIcon && self.iconView.imageView.image != self.iconImage) self.iconView.imageView.image = self.iconImage;

    [CATransaction begin]; [CATransaction setDisableActions:YES];
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
    self.contentSize = size;
    [self setOverLimitWarning:(state == 2)];
}

// Ve theo cac thuoc tinh hien tai (dung lai kieu neu doi), tra ve kich thuoc noi dung (diem, ti le 1)
- (CGSize)render
{
    NSInteger style = (self.style >= 0 && self.style < SB_STYLE_COUNT) ? self.style : SPPStyleDrop;
    if (style != self.builtStyle) [self buildStyle:style];
    [self renderStyle];
    return self.contentSize;
}

- (void)rebuild { self.builtStyle = -1; }

@end
