#import "SPPWarn.h"
#import "SPPBubble.h"
#import "SPPPrefs.h"
#import "SPPSound.h"

#define SPP_WARN_REARM   5.0     // giay duoi nguong lien tuc -> lan vuot sau lai keu
#define SPP_WARN_EDGE    36.0    // diem: be rong vung sang tinh tu mep man vao trong
#define SPP_WARN_CORNER  18.0    // bo goc vien (gan bo goc man xe)
#define SPP_WARN_LEVEL   65      // UIWindowLevelStatusBar + 65: duoi bong bong (+70), tren CarPlay

// Vien phat sang ve 1 lan thanh anh nho co the gian (9 o): net do sat mep + quang do mo dan vao trong.
// Gian anh thay vi bong dong (shadow) -> khong ve lai moi khung hinh khi nhay.
static UIImage *SPPWarnGlowImage(void)
{
    static UIImage *img;
    if (img) return img;
    CGFloat e = SPP_WARN_EDGE, side = e * 2 + 2;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *raw = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        UIColor *red = [UIColor colorWithRed:1 green:0.17 blue:0.18 alpha:1];
        CGRect rect = CGRectMake(0, 0, side, side);
        UIBezierPath *edge = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 3, 3) cornerRadius:SPP_WARN_CORNER];
        edge.lineWidth = 6;
        // Quang mo: bong cua net do toa vao trong (phan toa ra ngoai bi cat o mep anh)
        CGContextSaveGState(c);
        CGContextSetShadowWithColor(c, CGSizeZero, 20, red.CGColor);
        [red setStroke];
        [edge stroke];
        [edge stroke];
        CGContextRestoreGState(c);
        // Net sang o giua vien
        UIBezierPath *core = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 3, 3) cornerRadius:SPP_WARN_CORNER];
        core.lineWidth = 2;
        [[UIColor colorWithRed:1 green:0.55 blue:0.55 alpha:0.9] setStroke];
        [core stroke];
    }];
    img = [raw resizableImageWithCapInsets:UIEdgeInsetsMake(e, e, e, e) resizingMode:UIImageResizingModeStretch];
    return img;
}

// Kieu "Phat sang": quang do diu toa tu mep vao, khong net (nhu inset 0 0 46px 12px rgba(255,59,48,.6) trong ban duyet)
#define SPP_SOFT_EDGE    60.0
static UIImage *SPPWarnSoftImage(void)
{
    static UIImage *img;
    if (img) return img;
    CGFloat e = SPP_SOFT_EDGE, side = e * 2 + 2;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *raw = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        for (CGFloat i = 0; i < e; i += 1) {
            CGFloat k = 1 - i / e;
            UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectMake(0, 0, side, side), i + 0.5, i + 0.5)
                                                         cornerRadius:MAX(2, SPP_WARN_CORNER + 12 - i * 0.5)];
            p.lineWidth = 1.2;
            [[UIColor colorWithRed:1 green:0.23 blue:0.19 alpha:0.6 * k * k] setStroke];
            [p stroke];
        }
    }];
    img = [raw resizableImageWithCapInsets:UIEdgeInsetsMake(e, e, e, e) resizingMode:UIImageResizingModeStretch];
    return img;
}

@interface SPPOverspeed ()
@property (nonatomic, strong) UIWindow *window;     // cua so tren man xe (nil = chua tao / xe ngat)
@property (nonatomic, strong) UIImageView *glow;   // Vien nhay / Phat sang (anh theo kieu)
@property (nonatomic, strong) UIView *flash;       // Nhay man: lop do phu kin man
@property (nonatomic) NSInteger shownFx;           // kieu dang hien tren cua so (-1 = khong)
@property (nonatomic, copy) NSString *displayID;    // uniqueId cua man xe ung voi cua so
@property (nonatomic) int speed, limit;
@property (nonatomic) BOOL enabled;                 // bat bong bong (canh bao di kem tinh nang)
@property (nonatomic) NSInteger mode;               // SB_KEY_WARN_MODE
@property (nonatomic) double marginKmh;             // nguong da doi ra km/h
@property (nonatomic) NSInteger fx;                 // SB_KEY_WARN_FX
@property (nonatomic) BOOL voice;                   // am thanh: giong noi (khong thi am bao)
@property (nonatomic) NSInteger tone, voiceLine;
@property (nonatomic, copy) NSString *voiceText;
@property (nonatomic) BOOL mph;                     // gioi han doc theo don vi dang hien
@property (nonatomic) BOOL over;                    // dang vuot (dang hien vien)
@property (nonatomic) BOOL armed;                   // lan vuot ke tiep duoc keu
@property (nonatomic) CFAbsoluteTime belowSince;    // luc bat dau xuong duoi gioi han (0 = dang tren / khong biet)
@end

@implementation SPPOverspeed

+ (instancetype)shared
{
    static SPPOverspeed *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [SPPOverspeed new];
        s.speed = -1; s.limit = -1; s.armed = YES; s.shownFx = -1;
        [s loadPrefs];
    });
    return s;
}

- (void)loadPrefs
{
    self.enabled = [SPPPrefs enabled];
    self.mode = [SPPPrefs warnMode];
    self.marginKmh = [SPPPrefs warnMarginKmh];
    self.fx = [SPPPrefs warnFx];
    self.voice = [SPPPrefs warnVoice];
    self.tone = [SPPPrefs warnTone];
    self.voiceLine = [SPPPrefs warnVoiceLine];
    self.voiceText = [SPPPrefs warnVoiceText];
    self.mph = [SPPPrefs useMph];
}

- (void)reloadPrefs
{
    [self loadPrefs];
    [self evaluate];
}

- (void)carChanged
{
    if (!SPPGetCarPlayCADisplay()) [self dropWindow];
    [self evaluate];
}

- (void)updateSpeed:(int)speed limit:(int)limit
{
    self.speed = speed; self.limit = limit;
    [self evaluate];
}

- (void)evaluate
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    int speed = self.speed, limit = self.limit;
    BOOL known = speed >= 0 && limit > 0;
    double threshold = limit + self.marginKmh;   // nguong canh bao (co the thap hon gioi han)
    // Keu lai: chi sau khi o duoi nguong lien tuc SPP_WARN_REARM giay (khong keu lien hoi khi dao dong quanh nguong)
    if (known && speed <= threshold) {
        if (self.belowSince <= 0) self.belowSince = now;
        if (!self.armed && now - self.belowSince >= SPP_WARN_REARM) { self.armed = YES; SPPLog("canh bao: da cham lai duoi nguong -> lan vuot sau se keu"); }
    } else self.belowSince = 0;

    BOOL car = SPPGetCarPlayCADisplay() != nil;
    BOOL over = self.enabled && self.mode > 0 && car && known && speed > threshold;
    if (over != self.over) {
        if (over) SPPLog("canh bao: %d km/h > gioi han %d %+.0f -> vien do (che do %ld)", speed, limit, self.marginKmh, (long)self.mode);
        else SPPLog("canh bao: het vuot (toc do %d, gioi han %d)", speed, limit);
    }
    self.over = over;
    if (over) {
        if (self.armed && (self.mode & 2)) {
            if (self.voice) {
                NSString *line = SPPVoiceLine(self.voiceLine, self.voiceText, self.mph ? (int)lround(limit / 1.609344) : limit);
                SPPSpeak(line);
                SPPLog("canh bao: noi \"%@\"", line);
            } else {
                SPPPlayTone(self.tone);
                SPPLog("canh bao: phat am bao %ld", (long)self.tone);
            }
        }
        self.armed = NO;   // ca che do im lang: tinh la 1 lan vuot
    }
    BOOL visual = over && (self.mode & 1);   // bit 2 = chi am thanh
    [[SPPBubble shared] setWarnShake:visual && self.fx == 3];
    [self showFx:visual && self.fx != 3 ? self.fx : -1];
}

// ---------------------------------------------------------------------
//  Cua so vien tren man xe: phu kin man, khong nhan cham (xuyen xuong CarPlay / bong bong)
// ---------------------------------------------------------------------
- (BOOL)ensureWindow
{
    id display = SPPGetCarPlayCADisplay();
    if (!display) { [self dropWindow]; return NO; }
    NSString *uid = [display respondsToSelector:NSSelectorFromString(@"uniqueId")] ? objcInvoke(display, @"uniqueId") : nil;
    if (self.window && (!uid || [uid isEqualToString:self.displayID])) return YES;
    [self dropWindow];
    CGFloat ds = 2;
    UIWindow *w = SPPMakeCarWindow(&ds);
    if (!w) return NO;
    SPPMakeWindowPassThrough(w);
    w.userInteractionEnabled = NO;
    w.windowLevel = UIWindowLevelStatusBar + SPP_WARN_LEVEL;
    w.backgroundColor = [UIColor clearColor];
    UIImageView *glow = [[UIImageView alloc] initWithFrame:w.bounds];
    glow.image = SPPWarnGlowImage();
    glow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glow.userInteractionEnabled = NO;
    glow.alpha = 0;
    [w addSubview:glow];
    UIView *flash = [[UIView alloc] initWithFrame:w.bounds];
    flash.backgroundColor = [UIColor colorWithRed:1 green:0.23 blue:0.19 alpha:0.32];
    flash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    flash.userInteractionEnabled = NO;
    flash.alpha = 0;
    [w addSubview:flash];
    w.hidden = YES;
    self.window = w; self.glow = glow; self.flash = flash; self.displayID = uid; self.shownFx = -1;
    SPPLog("canh bao: cua so vien tren xe tao xong (%.0fx%.0f)", w.bounds.size.width, w.bounds.size.height);
    return YES;
}

- (void)dropWindow
{
    if (!self.window) return;
    [self.glow.layer removeAllAnimations];
    [self.flash.layer removeAllAnimations];
    self.window.hidden = YES;
    self.window = nil; self.glow = nil; self.flash = nil; self.displayID = nil; self.shownFx = -1;
}

// Kieu tren man xe (nhip nhu ban duyet): 0 vien nhay 0.7 s, 1 phat sang diu 1.6 s, 2 lop do nhay ca man 0.45 s; -1 = tat
- (void)showFx:(NSInteger)fx
{
    if (fx >= 0) {
        if (![self ensureWindow]) return;
        if (fx == self.shownFx && !self.window.hidden) return;
        [self.glow.layer removeAllAnimations]; [self.flash.layer removeAllAnimations];
        self.window.hidden = NO;
        UIView *v = fx == 2 ? self.flash : self.glow;
        self.glow.alpha = fx == 2 ? 0 : 1;
        self.flash.alpha = fx == 2 ? 1 : 0;
        if (fx != 2) self.glow.image = fx == 1 ? SPPWarnSoftImage() : SPPWarnGlowImage();
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @1.0; pulse.toValue = fx == 2 ? @0.0 : @0.25;
        pulse.duration = fx == 2 ? 0.45 : fx == 1 ? 1.6 : 0.7;
        pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [v.layer addAnimation:pulse forKey:@"sppWarnPulse"];
        self.shownFx = fx;
        return;
    }
    self.shownFx = -1;
    if (!self.window || self.window.hidden) return;
    UIWindow *win = self.window; UIView *glow = self.glow, *flash = self.flash;
    [glow.layer removeAnimationForKey:@"sppWarnPulse"]; [flash.layer removeAnimationForKey:@"sppWarnPulse"];
    [UIView animateWithDuration:0.25 animations:^{ glow.alpha = 0; flash.alpha = 0; }
                     completion:^(BOOL f) { if (glow.alpha < 0.01 && flash.alpha < 0.01) win.hidden = YES; }];
}

@end
