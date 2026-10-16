#import "OMCSpeedBubbleController.h"
#import "OMCTheme.h"
#import "../SpeedBubble.h"
#import "../SPPBubbleView.h"
#import "../SPPSound.h"
#import "OmniCar.h"
#import <notify.h>
#import <objc/runtime.h>

@interface UIImage (OMCSpeedBubblePrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(double)scale;
@end

// Cung thu tu SB_SOURCE_NAMES / SPP_NAV_APPS
static NSArray<NSString *> *OMCSBSourceBundles(void)
{
    return @[@"vn.vietmap.live", @"com.lumi.GOFA", @"com.waze.iphone"];
}

static UIImage *OMCSBRounded(UIImage *img, CGFloat side, CGFloat corner)
{
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:corner] addClip];
        [img drawInRect:CGRectMake(0, 0, side, side)];
    }];
}

// Icon nguon: icon app that (neu da cai), khong co thi o mau co chu viet tat
static UIImage *OMCSBSourceIcon(NSInteger i)
{
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache[@(i)]) return cache[@(i)];
    NSString *bid = i >= 0 && i < (NSInteger)OMCSBSourceBundles().count ? OMCSBSourceBundles()[i] : @"";
    UIImage *img = nil;
    if (bid.length && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        img = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
    if (!img) {
        UIColor *bg = @[OMCColorFromHex(@"#F07A12"), OMCColorFromHex(@"#1AA260"), OMCColorFromHex(@"#33CCFF")][MAX(0, MIN(2, i))];
        NSString *abbr = @[@"V", @"G", @"W"][MAX(0, MIN(2, i))];
        img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60, 60)] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [bg setFill]; UIRectFill(CGRectMake(0, 0, 60, 60));
            NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:28 weight:UIFontWeightHeavy], NSForegroundColorAttributeName: [UIColor whiteColor]};
            CGSize s = [abbr sizeWithAttributes:a];
            [abbr drawAtPoint:CGPointMake((60 - s.width) / 2, (60 - s.height) / 2) withAttributes:a];
        }];
    }
    cache[@(i)] = img;
    return img;
}

// Nen ban do sang cho o xem truoc / o chon kieu (giong tools/preview/index.html#bubble)
static UIImage *OMCSBMapImage(CGSize size)
{
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:f] imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef c = rc.CGContext;
        [OMCColorFromHex(@"#EEF0EA") setFill]; UIRectFill(CGRectMake(0, 0, size.width, size.height));
        [OMCColorFromHex(@"#CDECCF") setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(size.width * 0.68, -size.height * 0.15, size.height * 0.9, size.height * 0.9)] fill];
        [OMCColorFromHex(@"#C8E4F7") setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-size.height * 0.2, size.height * 0.45, size.height, size.height)] fill];
        CGContextSetLineCap(c, kCGLineCapRound);
        [OMCColorFromHex(@"#FFE9A8") setStroke];
        UIBezierPath *p = [UIBezierPath bezierPath]; p.lineWidth = size.height * 0.07;
        [p moveToPoint:CGPointMake(-10, size.height * 0.62)]; [p addLineToPoint:CGPointMake(size.width + 10, size.height * 0.2)]; [p stroke];
        [[UIColor whiteColor] setStroke];
        p = [UIBezierPath bezierPath]; p.lineWidth = size.height * 0.1;
        [p moveToPoint:CGPointMake(size.width * 0.38, size.height + 10)]; [p addLineToPoint:CGPointMake(size.width * 0.62, -10)]; [p stroke];
        [OMCColorFromHex(@"#3D8BFF") setStroke];
        p = [UIBezierPath bezierPath]; p.lineWidth = size.height * 0.045;
        [p moveToPoint:CGPointMake(size.width * 0.33, size.height + 10)]; [p addLineToPoint:CGPointMake(size.width * 0.56, -10)]; [p stroke];
    }];
}

// Dat bong bong vao giua khung, thu nho cho vua (khong phong to qua maxScale)
static void OMCSBFit(SPPBubbleView *bv, CGRect box, CGFloat maxScale)
{
    CGSize s = [bv render];
    if (s.width < 1 || s.height < 1) return;
    CGFloat k = MIN(maxScale, MIN((box.size.width - 12) / s.width, (box.size.height - 12) / s.height));
    bv.transform = CGAffineTransformIdentity;
    bv.bounds = CGRectMake(0, 0, s.width, s.height);
    bv.center = CGPointMake(CGRectGetMidX(box), CGRectGetMidY(box));
    bv.transform = CGAffineTransformMakeScale(k, k);
}

// Vien cau vong 4 mau logo quanh o dang chon
static void OMCSBRing(UIView *v, BOOL on, CGFloat corner)
{
    CALayer *old = nil;
    for (CALayer *l in v.layer.sublayers) if ([l.name isEqualToString:@"omcRing"]) old = l;
    [old removeFromSuperlayer];
    if (!on) return;
    CAGradientLayer *g = [CAGradientLayer layer];
    g.name = @"omcRing";
    g.type = kCAGradientLayerConic;
    g.frame = CGRectInset(v.bounds, -2.5, -2.5);
    g.startPoint = CGPointMake(0.5, 0.5); g.endPoint = CGPointMake(0, 1);
    g.colors = @[(id)OMCColorFromHex(@"#A78BFA").CGColor, (id)OMCColorFromHex(@"#60C5FA").CGColor, (id)OMCColorFromHex(@"#5EDDB6").CGColor,
                 (id)OMCColorFromHex(@"#F59AC0").CGColor, (id)OMCColorFromHex(@"#A78BFA").CGColor];
    CAShapeLayer *m = [CAShapeLayer layer];
    m.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(g.bounds, 1.25, 1.25) cornerRadius:corner + 1.25].CGPath;
    m.fillColor = nil; m.strokeColor = [UIColor blackColor].CGColor; m.lineWidth = 2.5;
    g.mask = m;
    [v.layer addSublayer:g];
}

// Thu tu nhu ban duyet: Giao dien (kieu, mau nen, icon), Co va vi tri, Nguon, Canh bao, Hien thi
enum { SBPreview = 0, SBEnable, SBStyle, SBSize, SBSource, SBWarn, SBDisplay, SBCount };
static char kOMCSBIndex;

// Mau nen (SB_KEY_COLOR, cung bang mau voi SPPBubbleView applyColor:): o chon tron; 0 = mac dinh (vong 4 mau logo)
static UIColor *OMCSBSwatchColor(NSInteger i)
{
    NSArray *hex = @[@"", @"#FFFFFF", @"#16182A", @"#7C5CF0", @"#2F8FE0", @"#16A87F", @"#E8558C"];
    return i > 0 && i < (NSInteger)hex.count ? OMCColorFromHex(hex[i]) : nil;
}

// Kieu canh bao: icon SF cho 4 o chon
static NSString *OMCSBFxSymbol(NSInteger i)
{
    return @[@"rectangle", @"sun.max.fill", @"rectangle.fill", @"circle.circle"][MAX(0, MIN(SB_WARN_FX_COUNT - 1, i))];
}

@interface OMCSpeedBubbleController () <UITextFieldDelegate>
@property (nonatomic, strong) SPPBubbleView *live;       // xem truoc song
@property (nonatomic, strong) UIImageView *liveMap;
@property (nonatomic, strong) NSTimer *liveTimer;
@property (nonatomic) CFTimeInterval liveStart;
@property (nonatomic, strong) UIScrollView *styleStrip;
@property (nonatomic) CGFloat stripOffset;
@property (nonatomic, strong) NSArray<NSString *> *warnRows;   // hang cua nhom Canh bao (xem -buildWarnRows)
@end

@implementation OMCSpeedBubbleController

// Chi con 1 nguon (SB_KEY_SOURCE). Lan dau mo sau ban cap nhat: chuyen 2 cong tac cu (chi tat Vietmap -> GOFA), cung
// quy tac SPPPrefs dung cho toi khi gia tri nay duoc ghi. Ban 6 nguon -> 3 nguon (SB_KEY_SOURCE_V2): 4 (Waze) -> 2, con lai
// ngoai 0..1 -> 0. Canh bao 3 che do -> 4 (SB_KEY_WARN_MODE_V2): 2 cu (vien + tieng) -> 3.
- (void)viewDidLoad
{
    CFPreferencesAppSynchronize(kPrefsDomain);
    id cur = [self prefForKey:SB_KEY_SOURCE def:nil];
    if (!cur) {
        id vm = [self prefForKey:SB_KEY_APP_VIETMAP def:nil], gf = [self prefForKey:SB_KEY_APP_GOFA def:nil];
        BOOL gofa = vm && ![vm boolValue] && !(gf && ![gf boolValue]);
        CFPreferencesSetAppValue((__bridge CFStringRef)SB_KEY_SOURCE, (__bridge CFPropertyListRef)@(gofa ? 1 : 0), kPrefsDomain);
    } else if (![[self prefForKey:SB_KEY_SOURCE_V2 def:@NO] boolValue]) {
        NSInteger i = [cur integerValue];
        CFPreferencesSetAppValue((__bridge CFStringRef)SB_KEY_SOURCE, (__bridge CFPropertyListRef)@(i == 4 ? 2 : (i >= 0 && i <= 1) ? i : 0), kPrefsDomain);
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)SB_KEY_SOURCE_V2, kCFBooleanTrue, kPrefsDomain);
    if (![[self prefForKey:SB_KEY_WARN_MODE_V2 def:@NO] boolValue]) {
        if ([[self prefForKey:SB_KEY_WARN_MODE def:nil] integerValue] == 2)
            CFPreferencesSetAppValue((__bridge CFStringRef)SB_KEY_WARN_MODE, (__bridge CFPropertyListRef)@3, kPrefsDomain);
        CFPreferencesSetAppValue((__bridge CFStringRef)SB_KEY_WARN_MODE_V2, kCFBooleanTrue, kPrefsDomain);
    }
    CFPreferencesAppSynchronize(kPrefsDomain);
    [super viewDidLoad];
    if (!self.title.length) self.title = L(@"SPEEDBUBBLE");
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.liveTimer invalidate];
    self.liveStart = CACurrentMediaTime();
    __weak OMCSpeedBubbleController *weakSelf = self;
    self.liveTimer = [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *t) { [weakSelf tickLive]; }];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.liveTimer invalidate];
    self.liveTimer = nil;
}

#pragma mark - Gia tri

- (BOOL)on { return [[self prefForKey:SB_KEY_ENABLED def:@YES] boolValue]; }
- (NSInteger)style { NSInteger s = [self intForKey:SB_KEY_STYLE def:0]; return (s >= 0 && s < SB_STYLE_COUNT) ? s : 0; }
- (NSInteger)source { NSInteger s = [self intForKey:SB_KEY_SOURCE def:0]; return (s >= 0 && s < (NSInteger)SB_SOURCE_NAMES.count) ? s : 0; }
- (BOOL)showIcon { return [[self prefForKey:SB_KEY_SHOW_APP_ICON def:@YES] boolValue]; }
- (NSInteger)warnMode { NSInteger m = [self intForKey:SB_KEY_WARN_MODE def:3]; return (m >= 0 && m <= 3) ? m : 3; }   // 0 tat, 1 canh bao, 2 am thanh, 3 ca hai
- (NSInteger)ranged:(NSString *)key def:(NSInteger)def count:(NSInteger)n { NSInteger v = [self intForKey:key def:def]; return (v >= 0 && v < n) ? v : def; }
- (NSInteger)color { return [self ranged:SB_KEY_COLOR def:0 count:SB_COLOR_COUNT]; }
- (NSInteger)warnFx { return [self ranged:SB_KEY_WARN_FX def:0 count:SB_WARN_FX_COUNT]; }
- (BOOL)voiceSound { return [self ranged:SB_KEY_WARN_SOUND def:0 count:2] == 1; }
- (NSInteger)tone { return [self ranged:SB_KEY_WARN_TONE def:0 count:SB_TONE_COUNT]; }
- (NSInteger)voiceLine { return [self ranged:SB_KEY_WARN_VOICE def:0 count:SB_VOICE_CUSTOM + 1]; }
- (NSString *)voiceText { id v = [self prefForKey:SB_KEY_WARN_VOICE_TEXT def:@""]; return [v isKindOfClass:[NSString class]] ? v : @""; }
- (int)shownLimit { return [self useMph] ? 40 : 60; }   // so tren bien trong cau "gioi han {L}" (nghe thu / danh sach)

// Cung quy tac SPPPrefs: tu dong = mph / bien My o vung dung
- (BOOL)useMph
{
    NSInteger u = [self intForKey:SB_KEY_UNIT def:0];
    if (u == 1) return NO;
    if (u == 2) return YES;
    NSString *cc = [[NSLocale currentLocale] countryCode].uppercaseString ?: @"";
    return ![[NSLocale currentLocale] usesMetricSystem] || [@[@"US", @"GB", @"LR", @"MM"] containsObject:cc];
}

- (BOOL)usSign
{
    NSInteger s = [self intForKey:SB_KEY_SIGN def:0];
    if (s == 1) return NO;
    if (s == 2) return YES;
    NSString *cc = [[NSLocale currentLocale] countryCode].uppercaseString ?: @"";
    return [@[@"US", @"PR", @"LR", @"MM"] containsObject:cc];
}

// Dong giai thich nguon dang chon
- (NSString *)sourceHint
{
    return [@"ⓘ  " stringByAppendingString:L([NSString stringWithFormat:@"SPEEDBUBBLE_SRC_HINT_%ld", (long)[self source]])];
}

- (NSString *)sourceName:(NSInteger)i
{
    return SB_SOURCE_NAMES[i];
}

// Bong bong theo cai dat hien tai (xem truoc song + o chon kieu)
- (void)configure:(SPPBubbleView *)bv style:(NSInteger)style speed:(int)speed limit:(int)limit
{
    bv.style = style;
    bv.speed = speed; bv.limit = limit;
    bv.showIcon = [self showIcon];
    bv.mph = [self useMph]; bv.usSign = [self usSign];
    bv.iconImage = OMCSBSourceIcon([self source]);
    bv.color = [self color];
}

- (void)tickLive
{
    if (!self.live.window) return;
    int limit = 60;
    CFTimeInterval t = CACurrentMediaTime() - self.liveStart;
    int speed = (int)lround(60 * (0.55 + 0.65 * (0.5 - 0.5 * cos(t * 0.45))));
    [self configure:self.live style:[self style] speed:speed limit:limit];
    OMCSBFit(self.live, self.liveMap.frame, 0.95);
}

- (void)prefChanged:(NSString *)key
{
    if ([key isEqualToString:SB_KEY_ENABLED]) { [self.table reloadData]; return; }
    if ([key isEqualToString:SB_KEY_SHOW_APP_ICON] || [key isEqualToString:SB_KEY_UNIT] || [key isEqualToString:SB_KEY_SIGN]) {
        self.stripOffset = self.styleStrip.contentOffset.x;
        [self reloadSection:SBStyle];
        [self reloadSection:SBWarn];   // nguong theo don vi
    }
    if ([key isEqualToString:SB_KEY_COLOR]) { self.stripOffset = self.styleStrip.contentOffset.x; [self reloadSection:SBStyle]; }
    if ([@[SB_KEY_WARN_MODE, SB_KEY_WARN_FX, SB_KEY_WARN_SOUND, SB_KEY_WARN_TONE, SB_KEY_WARN_VOICE] containsObject:key]) [self reloadSection:SBWarn];
    if ([key isEqualToString:SB_KEY_WARN_OVER]) [self reloadSection:SBWarn];   // chu thich theo nguong moi (tha tay)
    [self tickLive];
}

#pragma mark - Bang

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SBCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s
{
    switch (s) {
        case SBSource: case SBDisplay: return 2;
        case SBStyle: case SBSize: return 3;   // Kieu: dai kieu, mau nen, icon
        case SBWarn: return [self buildWarnRows].count;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s
{
    switch (s) {
        case SBStyle: return L(@"SPEEDBUBBLE_APPEARANCE");
        case SBSource: return L(@"SPEEDBUBBLE_SOURCE");
        case SBDisplay: return L(@"SPEEDBUBBLE_DISPLAY");
        case SBWarn: return L(@"SPEEDBUBBLE_WARN");
        case SBSize: return L(@"SPEEDBUBBLE_SIZE_GROUP");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    switch (s) {
        case SBStyle: return L(@"SPEEDBUBBLE_COLOR_FOOTER");
        case SBDisplay: return L(@"SPEEDBUBBLE_DISPLAY_FOOTER");
        case SBWarn: {
            NSInteger m = [self warnMode];
            if (!m) return L(@"SPEEDBUBBLE_WARN_OFF_FOOTER");
            // Nguong: +5 = qua gioi han 5, -5 = bao tu 5 duoi gioi han, 0 = ngay khi cham gioi han
            NSInteger margin = [self intForKey:SB_KEY_WARN_OVER def:5];
            NSString *amount = [NSString stringWithFormat:@"%ld %@", labs(margin), [self useMph] ? @"mph" : @"km/h"];
            NSString *when = margin > 0 ? [NSString stringWithFormat:L(@"SPEEDBUBBLE_WARN_TH_OVER"), amount]
                           : margin < 0 ? [NSString stringWithFormat:L(@"SPEEDBUBBLE_WARN_TH_UNDER"), amount] : L(@"SPEEDBUBBLE_WARN_TH_AT");
            // Khi chay <nguong>: <kieu canh bao> + <am thanh>
            NSMutableArray *parts = [NSMutableArray array];
            if (m & 1) [parts addObject:L([NSString stringWithFormat:@"SPEEDBUBBLE_FX_DESC_%ld", (long)[self warnFx]])];
            if (m & 2) [parts addObject:[self voiceSound]
                ? [NSString stringWithFormat:L(@"SPEEDBUBBLE_VOICE_DESC"), SPPVoiceLine([self voiceLine], [self voiceText], [self shownLimit])]
                : L([NSString stringWithFormat:@"SPEEDBUBBLE_TONE_DESC_%ld", (long)[self tone]])];
            return [NSString stringWithFormat:L(@"SPEEDBUBBLE_WARN_FOOTER"), when, [parts componentsJoinedByString:@" + "]];
        }
        case SBSize: return L(@"SPEEDBUBBLE_GESTURES_FOOTER");
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip
{
    CGFloat w = tv.bounds.size.width - 40;
    if (ip.section == SBPreview) return MAX(128, round(w * 0.4));
    if (ip.section == SBEnable) return 60;
    if (ip.section == SBStyle && ip.row == 0) return 112;
    if (ip.section == SBStyle && ip.row == 1) return 50 + 38;   // Mau nen: dong ten + hang o mau
    if (ip.section == SBWarn) {
        NSString *r = self.warnRows[ip.row];
        if ([r isEqualToString:@"fx"]) return 34 * 2 + 6 + 14;
        if ([r isEqualToString:@"kind"]) return 44;
        if ([r hasPrefix:@"h:"]) return 28;
        if ([r hasPrefix:@"tone:"] || [r hasPrefix:@"voice:"]) {
            CGSize s = [[self optionText:r] boundingRectWithSize:CGSizeMake(w - 60 - 50, 400) options:NSStringDrawingUsesLineFragmentOrigin
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]} context:nil].size;
            return MAX(42, ceil(s.height) + 22);
        }
        if ([r isEqualToString:@"custom"]) return 46;
        if ([r isEqualToString:@"sound"]) return 60;
    }
    if (ip.section == SBSource && ip.row == 0) return 24 + 70 + 8;
    if (ip.section == SBSource && ip.row == 1) {
        CGSize s = [[self sourceHint] boundingRectWithSize:CGSizeMake(w - 32, 400)
            options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12.5]} context:nil].size;
        return ceil(s.height) + 20;
    }
    return 52;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    CGFloat w = tv.bounds.size.width - 40;
    BOOL on = [self on];
    UITableViewCell *c = nil;
    switch (ip.section) {
    case SBPreview: {
        c = [self cellWithId:@"preview"];
        UIView *box = [self boxInCell:c];
        CGFloat h = [self tableView:tv heightForRowAtIndexPath:ip];
        if (!self.liveMap || self.liveMap.superview != box) {
            for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
            self.liveMap = [UIImageView new];
            self.liveMap.layer.cornerRadius = 14; self.liveMap.layer.cornerCurve = kCACornerCurveContinuous;
            self.liveMap.clipsToBounds = YES;
            [box addSubview:self.liveMap];
            self.live = [[SPPBubbleView alloc] initWithFrame:CGRectZero];
            [box addSubview:self.live];
            UIButton *tryBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            tryBtn.tag = 0x54;
            tryBtn.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
            [tryBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            tryBtn.layer.cornerRadius = 13;
            CAGradientLayer *g = [CAGradientLayer layer];
            g.startPoint = CGPointMake(0, 0); g.endPoint = CGPointMake(1, 1);
            g.colors = @[(id)OMCColorFromHex(@"#9B87F8").CGColor, (id)OMCColorFromHex(@"#5DB4F6").CGColor];
            g.cornerRadius = 13;
            [tryBtn.layer insertSublayer:g atIndex:0];
            [tryBtn addTarget:self action:@selector(tryOnCar) forControlEvents:UIControlEventTouchUpInside];
            [box addSubview:tryBtn];
        }
        self.liveMap.frame = CGRectMake(8, 8, w - 16, h - 16);
        self.liveMap.image = OMCSBMapImage(self.liveMap.bounds.size);
        self.liveMap.alpha = on ? 1 : 0.4;
        self.live.hidden = !on;
        UIButton *tryBtn = (UIButton *)[box viewWithTag:0x54];
        NSString *tt = L(@"SPEEDBUBBLE_TRY");
        [tryBtn setTitle:tt forState:UIControlStateNormal];
        CGFloat bw = ceil([tt sizeWithAttributes:@{NSFontAttributeName: tryBtn.titleLabel.font}].width) + 24;
        tryBtn.frame = CGRectMake(CGRectGetMaxX(self.liveMap.frame) - bw - 8, CGRectGetMaxY(self.liveMap.frame) - 26 - 8, bw, 26);
        ((CALayer *)tryBtn.layer.sublayers.firstObject).frame = tryBtn.bounds;
        tryBtn.hidden = !on;
        [self tickLive];
        return c;
    }
    case SBEnable:
        c = [self cellWithId:@"enable"];
        c.textLabel.text = L(@"SPEEDBUBBLE_ENABLE");
        c.detailTextLabel.text = L(@"SPEEDBUBBLE_ENABLE_SUB");
        c.imageView.image = OMCIcon(@"speedometer", OMCColorFromHex(@"#8B7CFF"));
        [self setAccessory:[self switchForKey:SB_KEY_ENABLED def:YES] onCell:c];
        return c;
    case SBStyle:
        if (ip.row == 0) { c = [self cellWithId:@"styles"]; [self layoutStylesIn:[self boxInCell:c] width:w]; }
        else if (ip.row == 1) { c = [self cellWithId:@"color"]; [self layoutColorsIn:[self boxInCell:c] width:w]; }
        else {
            c = [self cellWithId:@"icon"];
            c.textLabel.text = L(@"SPEEDBUBBLE_SHOW_APP_ICON");
            c.imageView.image = OMCIcon(@"app.badge.fill", OMCColorFromHex(@"#FF7FA8"));
            [self setAccessory:[self switchForKey:SB_KEY_SHOW_APP_ICON def:YES] onCell:c];
        }
        break;
    case SBSource:
        if (ip.row == 0) { c = [self cellWithId:@"sources"]; [self layoutSourcesIn:[self boxInCell:c] width:w]; }
        else {
            c = [self cellWithId:@"hint"];
            UIView *box = [self boxInCell:c];
            UILabel *l = (UILabel *)[box viewWithTag:0x48];
            if (!l) { l = [UILabel new]; l.tag = 0x48; l.numberOfLines = 0; l.font = [UIFont systemFontOfSize:12.5]; l.textColor = [UIColor secondaryLabelColor]; [box addSubview:l]; }
            l.text = [self sourceHint];
            l.frame = CGRectMake(16, 8, w - 32, [self tableView:tv heightForRowAtIndexPath:ip] - 16);
        }
        break;
    case SBDisplay: {
        BOOL unit = ip.row == 0;
        c = [self cellWithId:unit ? @"unit" : @"sign"];
        c.textLabel.text = L(unit ? @"SPEEDBUBBLE_UNIT_SHORT" : @"SPEEDBUBBLE_SIGN_SHORT");
        c.imageView.image = OMCIcon(unit ? @"speedometer" : @"nosign", OMCColorFromHex(unit ? @"#5AB8FF" : @"#E5262D"));
        UISegmentedControl *seg = unit ? [self segmentForKey:SB_KEY_UNIT titles:@[L(@"SPEEDBUBBLE_AUTO"), @"km/h", @"mph"] def:0]
                                       : [self segmentForKey:SB_KEY_SIGN titles:@[L(@"SPEEDBUBBLE_AUTO"), L(@"SPEEDBUBBLE_SIGN_ROUND"), L(@"SPEEDBUBBLE_SIGN_US")] def:0];
        [seg sizeToFit];
        [self setAccessory:seg onCell:c];
        break;
    }
    case SBWarn:
        c = [self warnCell:self.warnRows[ip.row] width:w];
        break;
    case SBSize:
    default:
        if (ip.row == 2) {
            c = [self cellWithId:@"reset"];
            c.textLabel.text = L(@"SPEEDBUBBLE_RESET_LAYOUT");
            c.textLabel.textColor = OMCAccentColor();
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            BOOL car = ip.row == 0;
            c = [self cellWithId:car ? @"sizecar" : @"sizephone"];
            c.textLabel.text = L(car ? @"SPEEDBUBBLE_SIZE_CAR_SHORT" : @"SPEEDBUBBLE_SIZE_PHONE_SHORT");
            c.imageView.image = OMCIcon(car ? @"car.fill" : @"iphone", OMCColorFromHex(@"#2BC79A"));
            [self setAccessory:[self sliderForKey:car ? SB_KEY_SIZE_CAR : SB_KEY_SIZE_PHONE min:60 max:220 def:100 format:@"%ld%%" width:MIN(210, w - 140)] onCell:c];
        }
        break;
    }
    // Tat tinh nang: cac the ben duoi mo di, khong cham duoc
    BOOL dim = !on && ip.section > SBEnable;
    c.contentView.alpha = dim ? 0.4 : 1;
    c.accessoryView.alpha = dim ? 0.4 : 1;
    c.userInteractionEnabled = !dim;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SBSize && ip.row == 2) [self resetLayout];
    if (ip.section == SBWarn) {
        NSString *r = self.warnRows[ip.row];
        if ([r hasPrefix:@"tone:"] || [r hasPrefix:@"voice:"]) [self pickOption:r];
        if ([r isEqualToString:@"custom"]) [(UITextField *)[[tv cellForRowAtIndexPath:ip] viewWithTag:0x56] becomeFirstResponder];
    }
}

- (void)warnSwitchChanged:(UISwitch *)sw
{
    NSInteger m = sw.on ? ([self warnMode] | sw.tag) : ([self warnMode] & ~sw.tag);
    [self storeValue:@(m) forKey:SB_KEY_WARN_MODE];
    [self prefChanged:SB_KEY_WARN_MODE];
}

#pragma mark - Canh bao

// Hang nhom Canh bao (nhu ban duyet): cong tac Canh bao [+ 4 o kieu], cong tac Am thanh [+ Am bao | Giong noi + danh sach chon],
// Nguong khi bat it nhat 1. "tone:i" / "voice:i" = 1 muc chon, "h:..." = tieu de nhom cau, "custom" = cau tu nhap.
- (NSArray<NSString *> *)buildWarnRows
{
    NSInteger m = [self warnMode];
    NSMutableArray *r = [NSMutableArray arrayWithObject:@"rim"];
    if (m & 1) [r addObject:@"fx"];
    [r addObject:@"sound"];
    if (m & 2) {
        [r addObject:@"kind"];
        if (![self voiceSound]) {
            for (NSInteger i = 0; i < SB_TONE_COUNT; i++) [r addObject:[NSString stringWithFormat:@"tone:%ld", (long)i]];
        } else {
            for (int fun = 0; fun < 2; fun++) {
                [r addObject:fun ? @"h:fun" : @"h:serious"];
                for (NSInteger i = 0; i < SB_VOICE_COUNT; i++)
                    if (SPPVoiceIsFun(i) == fun) [r addObject:[NSString stringWithFormat:@"voice:%ld", (long)i]];
            }
            [r addObject:@"h:custom"];
            [r addObject:@"custom"];
        }
    }
    if (m) [r addObject:@"over"];
    self.warnRows = r;
    return r;
}

- (NSInteger)optionIndex:(NSString *)r { return [[r substringFromIndex:[r rangeOfString:@":"].location + 1] integerValue]; }

- (NSString *)optionText:(NSString *)r
{
    NSInteger i = [self optionIndex:r];
    if ([r hasPrefix:@"tone:"]) return L([NSString stringWithFormat:@"SPEEDBUBBLE_TONE_%ld", (long)i]);
    return SPPVoiceLine(i, nil, [self shownLimit]);
}

- (BOOL)optionChosen:(NSString *)r
{
    if ([r isEqualToString:@"custom"]) return [self voiceLine] == SB_VOICE_CUSTOM;
    return [r hasPrefix:@"tone:"] ? [self tone] == [self optionIndex:r] : [self voiceLine] == [self optionIndex:r];
}

// Nut nghe thu ben phai muc chon (dang chon: dac mau nhan)
- (UIImageView *)playIcon:(BOOL)chosen
{
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:chosen ? @"play.circle.fill" : @"play.circle" withConfiguration:cfg]];
    iv.tintColor = chosen ? OMCAccentColor() : [OMCAccentColor() colorWithAlphaComponent:0.55];
    return iv;
}

- (UITableViewCell *)warnCell:(NSString *)r width:(CGFloat)w
{
    UITableViewCell *c = nil;
    if ([r isEqualToString:@"rim"] || [r isEqualToString:@"sound"]) {
        // 2 cong tac = 2 bit cua SB_KEY_WARN_MODE: 1 canh bao, 2 am thanh
        BOOL rim = [r isEqualToString:@"rim"];
        c = [self cellWithId:r];
        c.textLabel.text = L(rim ? @"SPEEDBUBBLE_WARN_SHORT_1" : @"SPEEDBUBBLE_WARN_SHORT_2");
        if (!rim) c.detailTextLabel.text = L(@"SPEEDBUBBLE_SOUND_SUB");
        c.imageView.image = OMCIcon(rim ? @"rectangle.dashed" : @"speaker.wave.2.fill", OMCColorFromHex(rim ? @"#FF5A5F" : @"#5AB8FF"));
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = OMCSwitchColor();
        sw.tag = rim ? 1 : 2;
        sw.on = ([self warnMode] & sw.tag) != 0;
        [sw addTarget:self action:@selector(warnSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        [self setAccessory:sw onCell:c];
    } else if ([r isEqualToString:@"fx"]) {
        c = [self cellWithId:@"fx"];
        [self layoutFxIn:[self boxInCell:c] width:w];
    } else if ([r isEqualToString:@"kind"]) {
        c = [self cellWithId:@"kind"];
        UIView *box = [self boxInCell:c];
        for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
        UISegmentedControl *seg = [self segmentForKey:SB_KEY_WARN_SOUND titles:@[L(@"SPEEDBUBBLE_SOUND_TONE"), L(@"SPEEDBUBBLE_SOUND_VOICE")] def:0];
        seg.frame = CGRectMake(60, 4, w - 60 - 16, 32);
        [box addSubview:seg];
    } else if ([r hasPrefix:@"h:"]) {
        c = [self cellWithId:@"head"];
        c.indentationWidth = 44; c.indentationLevel = 1;
        c.textLabel.text = [L([@"SPEEDBUBBLE_VOICE_GROUP_" stringByAppendingString:[r substringFromIndex:2].uppercaseString]) uppercaseString];
        c.textLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
        c.textLabel.textColor = [UIColor secondaryLabelColor];
    } else if ([r hasPrefix:@"tone:"] || [r hasPrefix:@"voice:"]) {
        BOOL on = [self optionChosen:r];
        c = [self cellWithId:@"opt"];
        c.indentationWidth = 44; c.indentationLevel = 1;
        c.textLabel.text = [self optionText:r];
        c.textLabel.numberOfLines = 0;
        c.textLabel.font = [UIFont systemFontOfSize:14 weight:on ? UIFontWeightSemibold : UIFontWeightRegular];
        c.textLabel.textColor = on ? OMCAccentColor() : [UIColor labelColor];
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        [self setAccessory:[self playIcon:on] onCell:c];
    } else if ([r isEqualToString:@"custom"]) {
        c = [self cellWithId:@"custom"];
        UIView *box = [self boxInCell:c];
        UITextField *f = (UITextField *)[box viewWithTag:0x56];
        if (!f) {
            f = [UITextField new];
            f.tag = 0x56;
            f.font = [UIFont systemFontOfSize:14];
            f.returnKeyType = UIReturnKeyDone;
            f.clearButtonMode = UITextFieldViewModeWhileEditing;
            f.delegate = self;
            [f addTarget:self action:@selector(customBegan:) forControlEvents:UIControlEventEditingDidBegin];
            [f addTarget:self action:@selector(customEnded:) forControlEvents:UIControlEventEditingDidEnd];
            [box addSubview:f];
        }
        f.frame = CGRectMake(60, 6, w - 60 - 50, 34);
        f.placeholder = L(@"SPEEDBUBBLE_VOICE_CUSTOM_PH");
        if (!f.isFirstResponder) f.text = [self voiceText];
        BOOL on = [self optionChosen:r];
        f.textColor = on ? OMCAccentColor() : [UIColor labelColor];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        UIImageView *play = [self playIcon:on];
        play.userInteractionEnabled = YES;
        [play addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(customPlay)]];
        [self setAccessory:play onCell:c];
    } else {
        c = [self cellWithId:@"warnover"];
        c.textLabel.text = L(@"SPEEDBUBBLE_WARN_WHEN");
        c.imageView.image = OMCIcon(@"exclamationmark.triangle.fill", OMCColorFromHex(@"#FFB340"));
        // -10..10: am = canh bao tu truoc khi cham gioi han
        NSString *fmt = [NSString stringWithFormat:@"%%+ld %@", [self useMph] ? @"mph" : @"km/h"];
        [self setAccessory:[self sliderForKey:SB_KEY_WARN_OVER min:-10 max:10 def:5 format:fmt width:MIN(210, w - 140)] onCell:c];
    }
    return c;
}

// 4 o kieu canh bao (2 x 2) ngay duoi cong tac, thang hang voi chu
- (void)layoutFxIn:(UIView *)box width:(CGFloat)w
{
    for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
    CGFloat x0 = 60, gap = 6, cw = floor((w - x0 - 16 - gap) / 2), ch = 34;
    NSInteger chosen = [self warnFx];
    for (NSInteger i = 0; i < SB_WARN_FX_COUNT; i++) {
        BOOL on = i == chosen;
        UIControl *t = [[UIControl alloc] initWithFrame:CGRectMake(x0 + (i % 2) * (cw + gap), 2 + (i / 2) * (ch + gap), cw, ch)];
        t.layer.cornerRadius = 11; t.layer.cornerCurve = kCACornerCurveContinuous;
        t.backgroundColor = on ? [UIColor systemBackgroundColor] : [UIColor colorWithRed:120 / 255.0 green:120 / 255.0 blue:140 / 255.0 alpha:0.1];
        t.layer.borderWidth = on ? 1.5 : 0;
        t.layer.borderColor = OMCColorFromHex(@"#8B7CFF").CGColor;
        objc_setAssociatedObject(t, &kOMCSBIndex, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [t addTarget:self action:@selector(fxTapped:) forControlEvents:UIControlEventTouchUpInside];
        UIColor *ink = on ? OMCColorFromHex(@"#4B3FD0") : [UIColor secondaryLabelColor];
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(9, (ch - 16) / 2, 16, 16)];
        iv.image = [UIImage systemImageNamed:OMCSBFxSymbol(i) withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]];
        iv.contentMode = UIViewContentModeCenter;
        iv.tintColor = ink;
        [t addSubview:iv];
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(31, 0, cw - 36, ch)];
        l.text = L([NSString stringWithFormat:@"SPEEDBUBBLE_FX_%ld", (long)i]);
        l.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        l.textColor = ink;
        l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.75;
        [t addSubview:l];
        for (UIView *v in t.subviews) v.userInteractionEnabled = NO;
        [box addSubview:t];
    }
}

- (void)fxTapped:(UIControl *)t
{
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self storeValue:objc_getAssociatedObject(t, &kOMCSBIndex) forKey:SB_KEY_WARN_FX];
    [self prefChanged:SB_KEY_WARN_FX];
}

// Nghe thu am / cau dang chon (cung code voi SpringBoard)
- (void)playPreview
{
    if ([self voiceSound]) SPPSpeak(SPPVoiceLine([self voiceLine], [self voiceText], [self shownLimit]));
    else SPPPlayTone([self tone]);
}

// Cham 1 muc: chon + nghe thu
- (void)pickOption:(NSString *)r
{
    BOOL tone = [r hasPrefix:@"tone:"];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self storeValue:@([self optionIndex:r]) forKey:tone ? SB_KEY_WARN_TONE : SB_KEY_WARN_VOICE];
    [self playPreview];
    [self prefChanged:tone ? SB_KEY_WARN_TONE : SB_KEY_WARN_VOICE];
}

// Cau tu nhap: bat dau go = chon cau nay (chua nap lai bang de giu ban phim); xong = luu + nap lai (chu thich, nut nghe)
- (void)customBegan:(UITextField *)f
{
    if ([self voiceLine] != SB_VOICE_CUSTOM) [self storeValue:@(SB_VOICE_CUSTOM) forKey:SB_KEY_WARN_VOICE];
}

- (void)customEnded:(UITextField *)f
{
    [self storeValue:f.text ?: @"" forKey:SB_KEY_WARN_VOICE_TEXT];
    [self reloadSection:SBWarn];
}

- (BOOL)textFieldShouldReturn:(UITextField *)f
{
    [f resignFirstResponder];
    [self playPreview];
    return NO;
}

- (BOOL)textField:(UITextField *)f shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)s
{
    return f.text.length - range.length + s.length <= 80;
}

- (void)customPlay
{
    UITextField *f = (UITextField *)[self.table viewWithTag:0x56];
    if (f.isFirstResponder) { [f resignFirstResponder]; [self playPreview]; return; }
    if ([self voiceLine] != SB_VOICE_CUSTOM) {
        [self storeValue:@(SB_VOICE_CUSTOM) forKey:SB_KEY_WARN_VOICE];
        [self prefChanged:SB_KEY_WARN_VOICE];
    }
    [self playPreview];
}

#pragma mark - Mau nen

// Dong "Mau nen" (icon, ten, mau dang chon) + hang 7 o tron: Mac dinh (vong 4 mau logo) va 6 mau
- (void)layoutColorsIn:(UIView *)box width:(CGFloat)w
{
    for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
    NSInteger chosen = [self color];
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(16, 11, 29, 29)];
    icon.image = OMCIcon(@"paintpalette.fill", OMCColorFromHex(@"#A78BFA"));
    [box addSubview:icon];
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(60, 0, w - 60 - 120, 50)];
    t.text = L(@"SPEEDBUBBLE_COLOR");
    t.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [box addSubview:t];
    UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(w - 16 - 116, 0, 116, 50)];
    v.text = L([NSString stringWithFormat:@"SPEEDBUBBLE_COLOR_%ld", (long)chosen]);
    v.font = [UIFont systemFontOfSize:15];
    v.textColor = [UIColor secondaryLabelColor];
    v.textAlignment = NSTextAlignmentRight;
    [box addSubview:v];
    CGFloat d = 26, x0 = 56, span = w - x0 - 20, step = (span - d) / (SB_COLOR_COUNT - 1);
    for (NSInteger i = 0; i < SB_COLOR_COUNT; i++) {
        UIControl *s = [[UIControl alloc] initWithFrame:CGRectMake(x0 + i * step, 50, d, d)];
        s.layer.cornerRadius = d / 2;
        s.layer.borderWidth = 1;
        s.layer.borderColor = [UIColor colorWithRed:31 / 255.0 green:34 / 255.0 blue:51 / 255.0 alpha:0.14].CGColor;
        s.accessibilityLabel = L([NSString stringWithFormat:@"SPEEDBUBBLE_COLOR_%ld", (long)i]);
        UIColor *c = OMCSBSwatchColor(i);
        if (c) s.backgroundColor = c;
        else {
            CAGradientLayer *g = [CAGradientLayer layer];
            g.type = kCAGradientLayerConic;
            g.frame = s.bounds; g.cornerRadius = d / 2;
            g.startPoint = CGPointMake(0.5, 0.5); g.endPoint = CGPointMake(0, 1);
            g.colors = @[(id)OMCColorFromHex(@"#A78BFA").CGColor, (id)OMCColorFromHex(@"#60C5FA").CGColor, (id)OMCColorFromHex(@"#5EDDB6").CGColor,
                         (id)OMCColorFromHex(@"#F59AC0").CGColor, (id)OMCColorFromHex(@"#A78BFA").CGColor];
            [s.layer insertSublayer:g atIndex:0];
        }
        if (i == chosen) {
            CAShapeLayer *ring = [CAShapeLayer layer];
            ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(s.bounds, -4, -4)].CGPath;
            ring.fillColor = nil; ring.strokeColor = OMCColorFromHex(@"#6F62F2").CGColor; ring.lineWidth = 2;
            [s.layer addSublayer:ring];
        }
        objc_setAssociatedObject(s, &kOMCSBIndex, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [s addTarget:self action:@selector(colorTapped:) forControlEvents:UIControlEventTouchUpInside];
        [box addSubview:s];
    }
}

- (void)colorTapped:(UIControl *)s
{
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self storeValue:objc_getAssociatedObject(s, &kOMCSBIndex) forKey:SB_KEY_COLOR];
    [self prefChanged:SB_KEY_COLOR];
}

#pragma mark - Kieu

// Dai cuon ngang: moi o la bong bong that (52 / 60 km/h) thu vua o + ten
- (void)layoutStylesIn:(UIView *)box width:(CGFloat)w
{
    if (!self.styleStrip || self.styleStrip.superview != box) {
        for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
        self.styleStrip = [UIScrollView new];
        self.styleStrip.showsHorizontalScrollIndicator = NO;
        self.styleStrip.alwaysBounceHorizontal = YES;
        [box addSubview:self.styleStrip];
    }
    UIScrollView *sc = self.styleStrip;
    for (UIView *v in [sc.subviews copy]) [v removeFromSuperview];
    sc.frame = CGRectMake(0, 0, w, 112);
    CGFloat tw = 86, th = 72, gap = 8, x = 12;
    UIImage *map = OMCSBMapImage(CGSizeMake(tw, th));
    NSInteger chosen = [self style];
    for (NSInteger i = 0; i < SB_STYLE_COUNT; i++) {
        UIControl *tile = [[UIControl alloc] initWithFrame:CGRectMake(x, 10, tw, th + 22)];
        objc_setAssociatedObject(tile, &kOMCSBIndex, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [tile addTarget:self action:@selector(styleTapped:) forControlEvents:UIControlEventTouchUpInside];
        UIImageView *bg = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, tw, th)];
        bg.image = map;
        bg.layer.cornerRadius = 14; bg.layer.cornerCurve = kCACornerCurveContinuous; bg.clipsToBounds = YES;
        bg.userInteractionEnabled = NO;
        [tile addSubview:bg];
        SPPBubbleView *bv = [[SPPBubbleView alloc] initWithFrame:CGRectZero];
        [self configure:bv style:i speed:52 limit:60];
        [tile addSubview:bv];
        OMCSBFit(bv, bg.frame, 0.9);
        UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(-4, th + 4, tw + 8, 16)];
        name.text = L([NSString stringWithFormat:@"SPEEDBUBBLE_LOOK_%ld", (long)i]);
        name.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
        name.textColor = i == chosen ? [UIColor labelColor] : [UIColor secondaryLabelColor];
        name.textAlignment = NSTextAlignmentCenter;
        name.adjustsFontSizeToFitWidth = YES; name.minimumScaleFactor = 0.75;
        [tile addSubview:name];
        [sc addSubview:tile];
        if (i == chosen) {   // vien cau vong nam ngoai o hinh (o hinh cat goc nen ve tren tile)
            UIView *ring = [[UIView alloc] initWithFrame:bg.frame];
            ring.userInteractionEnabled = NO;
            [tile addSubview:ring];
            OMCSBRing(ring, YES, 14);
        }
        x += tw + gap;
    }
    sc.contentSize = CGSizeMake(x + 4, 112);
    if (self.stripOffset > 0) sc.contentOffset = CGPointMake(MIN(self.stripOffset, MAX(0, sc.contentSize.width - w)), 0);
    else if (chosen > 2) sc.contentOffset = CGPointMake(MIN(12 + chosen * (tw + gap) - (w - tw) / 2, MAX(0, sc.contentSize.width - w)), 0);
}

- (void)styleTapped:(UIControl *)tile
{
    NSInteger i = [objc_getAssociatedObject(tile, &kOMCSBIndex) integerValue];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    self.stripOffset = self.styleStrip.contentOffset.x;
    [self storeValue:@(i) forKey:SB_KEY_STYLE];
    [self reloadSection:SBStyle];
    [self tickLive];
}

#pragma mark - Nguon

// 3 o (1 hang): icon app + ten, o dang chon co vien cau vong
- (void)layoutSourcesIn:(UIView *)box width:(CGFloat)w
{
    for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
    NSInteger n = SB_SOURCE_NAMES.count, cols = 3, chosen = [self source];
    CGFloat pad = 12, gap = 8, cw = floor((w - pad * 2 - gap * (cols - 1)) / cols), ch = 70;
    for (NSInteger i = 0; i < n; i++) {
        UIControl *t = [[UIControl alloc] initWithFrame:CGRectMake(pad + (i % cols) * (cw + gap), 12 + (i / cols) * (ch + gap), cw, ch)];
        t.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.1];
        t.layer.cornerRadius = 14; t.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(t, &kOMCSBIndex, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [t addTarget:self action:@selector(sourceTapped:) forControlEvents:UIControlEventTouchUpInside];
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((cw - 30) / 2, 10, 30, 30)];
        iv.image = OMCSBRounded(OMCSBSourceIcon(i), 30, 8);
        iv.userInteractionEnabled = NO;
        [t addSubview:iv];
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(4, 44, cw - 8, 18)];
        l.text = [self sourceName:i];
        l.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
        l.textAlignment = NSTextAlignmentCenter;
        l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.7;
        l.textColor = i == chosen ? [UIColor labelColor] : [UIColor secondaryLabelColor];
        [t addSubview:l];
        [box addSubview:t];
        OMCSBRing(t, i == chosen, 14);
    }
}

- (void)sourceTapped:(UIControl *)t
{
    NSInteger i = [objc_getAssociatedObject(t, &kOMCSBIndex) integerValue];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self storeValue:@(i) forKey:SB_KEY_SOURCE];
    [self.table beginUpdates];
    [self reloadSection:SBSource];
    [self.table endUpdates];
    self.stripOffset = self.styleStrip.contentOffset.x;
    [self reloadSection:SBStyle];   // icon nguon trong cac o kieu
    [self tickLive];
}

#pragma mark - Hanh dong (SpringBoard xu ly, ../SpringBoard.xm)

// Hien bong bong tren xe 10 giay
- (void)tryOnCar
{
    notify_post(SB_DARWIN_DEMO);
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self toast:L(@"SPEEDBUBBLE_TRY_SENT")];
}

// Vi tri mac dinh, co 100%. SpringBoard ghi lai co 100 nen doc lai thanh keo.
- (void)resetLayout
{
    notify_post(SB_DARWIN_RESET);
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    __weak OMCSpeedBubbleController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(kPrefsDomain);
        [weakSelf reloadSection:SBSize];
    });
}

@end
