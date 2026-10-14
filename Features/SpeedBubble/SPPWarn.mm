#import "SPPWarn.h"
#import "SPPBubble.h"
#import "SPPPrefs.h"
#import <AudioToolbox/AudioToolbox.h>

#define SPP_WARN_REARM   5.0     // giay duoi nguong lien tuc -> lan vuot sau lai keu
#define SPP_WARN_SOUND   1052    // SystemSoundID he thong: tieng bip ngan, nhe (SIMToolkitGeneralBeep)
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

@interface SPPOverspeed ()
@property (nonatomic, strong) UIWindow *window;     // cua so tren man xe (nil = chua tao / xe ngat)
@property (nonatomic, strong) UIImageView *glow;
@property (nonatomic, copy) NSString *displayID;    // uniqueId cua man xe ung voi cua so
@property (nonatomic) int speed, limit;
@property (nonatomic) BOOL enabled;                 // bat bong bong (canh bao di kem tinh nang)
@property (nonatomic) NSInteger mode;               // SB_KEY_WARN_MODE
@property (nonatomic) double marginKmh;             // nguong da doi ra km/h
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
        s.speed = -1; s.limit = -1; s.armed = YES;
        [s loadPrefs];
    });
    return s;
}

- (void)loadPrefs
{
    self.enabled = [SPPPrefs enabled];
    self.mode = [SPPPrefs warnMode];
    self.marginKmh = [SPPPrefs warnMarginKmh];
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
        if (self.armed && self.mode == 2) {
            AudioServicesPlaySystemSound(SPP_WARN_SOUND);
            SPPLog("canh bao: phat tieng");
        }
        self.armed = NO;   // ca che do im lang: tinh la 1 lan vuot
    }
    [self showBorder:over];
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
    w.hidden = YES;
    self.window = w; self.glow = glow; self.displayID = uid;
    SPPLog("canh bao: cua so vien tren xe tao xong (%.0fx%.0f)", w.bounds.size.width, w.bounds.size.height);
    return YES;
}

- (void)dropWindow
{
    if (!self.window) return;
    [self.glow.layer removeAllAnimations];
    self.window.hidden = YES;
    self.window = nil; self.glow = nil; self.displayID = nil;
}

- (void)showBorder:(BOOL)on
{
    if (on) {
        if (![self ensureWindow]) return;
        if (!self.window.hidden && [self.glow.layer animationForKey:@"sppWarnPulse"]) return;
        self.window.hidden = NO;
        self.glow.alpha = 1;
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @1.0; pulse.toValue = @0.3;
        pulse.duration = 0.5; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.glow.layer addAnimation:pulse forKey:@"sppWarnPulse"];
        return;
    }
    if (!self.window || self.window.hidden) return;
    UIWindow *win = self.window; UIImageView *glow = self.glow;
    [glow.layer removeAnimationForKey:@"sppWarnPulse"];
    [UIView animateWithDuration:0.25 animations:^{ glow.alpha = 0; }
                     completion:^(BOOL f) { if (glow.alpha < 0.01) win.hidden = YES; }];
}

@end
