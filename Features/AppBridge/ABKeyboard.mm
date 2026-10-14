#import "ABKeyboard.h"
#import "ABHost.h"
#import "common.h"
#import <ctype.h>

// Ban phim tren man xe cho app iPhone (App Bridge). Ve trong cua so cua ABHost (cung cua so voi cac o app, tao lai
// UIRootSceneWindow thi cua so moi khong hien). Moi phim -> AB_NOTIF_KEY gui app: "type" (xoa del ky tu roi chen text).
// Tieng Viet go kieu Telex: giu chu dang go (word) ben nay, moi lan Telex sua chu thi xoa chu cu trong app, chen chu moi.

#pragma mark - Telex

// Moi hang: nguyen am + 5 dau (sac, huyen, hoi, nga, nang). Hang: 0 a 1 ă 2 â 3 e 4 ê 5 i 6 o 7 ô 8 ơ 9 u 10 ư 11 y
static NSArray<NSString *> *ABVowelRows(void)
{
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[@"aáàảãạ", @"ăắằẳẵặ", @"âấầẩẫậ", @"eéèẻẽẹ", @"êếềểễệ", @"iíìỉĩị",
                 @"oóòỏõọ", @"ôốồổỗộ", @"ơớờởỡợ", @"uúùủũụ", @"ưứừửữự", @"yýỳỷỹỵ"];
    });
    return rows;
}

static BOOL ABVowel(unichar c, int *row, int *tone, BOOL *upper)
{
    NSString *s = [NSString stringWithCharacters:&c length:1];
    NSString *lower = s.lowercaseString;
    unichar l = lower.length == 1 ? [lower characterAtIndex:0] : c;
    NSArray<NSString *> *rows = ABVowelRows();
    for (int r = 0; r < (int)rows.count; r++) {
        NSRange f = [rows[r] rangeOfString:[NSString stringWithCharacters:&l length:1]];
        if (f.location == NSNotFound) continue;
        if (row) *row = r;
        if (tone) *tone = (int)f.location;
        if (upper) *upper = (l != c);
        return YES;
    }
    return NO;
}

static unichar ABVowelMake(int row, int tone, BOOL upper)
{
    unichar c = [ABVowelRows()[row] characterAtIndex:tone];
    if (!upper) return c;
    NSString *u = [NSString stringWithCharacters:&c length:1].uppercaseString;
    return u.length == 1 ? [u characterAtIndex:0] : c;
}

static int ABVowelBase(int row)   // 0 a, 3 e, 5 i, 6 o, 9 u, 11 y
{
    static const int base[] = {0, 0, 0, 3, 3, 5, 6, 6, 6, 9, 9, 11};
    return base[row];
}

static BOOL ABIsModified(int row) { return row == 1 || row == 2 || row == 4 || row == 7 || row == 8 || row == 10; }

// Vi tri dat dau trong cum nguyen am [start, end)
static NSUInteger ABTonePosition(NSMutableString *w, NSUInteger start, NSUInteger end, BOOL hasFinal)
{
    NSUInteger len = end - start;
    NSInteger modified = -1;
    for (NSUInteger i = start; i < end; i++) {
        int row = 0;
        ABVowel([w characterAtIndex:i], &row, NULL, NULL);
        if (ABIsModified(row)) modified = (NSInteger)i;   // ươ: cai sau (ơ)
    }
    if (modified >= 0) return (NSUInteger)modified;
    if (len == 1) return start;
    if (len == 2) {
        NSString *pair = [w substringWithRange:NSMakeRange(start, 2)].lowercaseString;
        if (hasFinal || [@[@"oa", @"oe", @"uy"] containsObject:pair]) return start + 1;
        return start;
    }
    return start + 1;
}

NSString *ABTelexApply(NSString *word, NSString *key)
{
    if (key.length != 1) return nil;
    unichar kc = [key characterAtIndex:0];
    NSString *lowerKey = key.lowercaseString;
    unichar k = [lowerKey characterAtIndex:0];
    BOOL keyUpper = (k != kc);
    NSMutableString *w = [word mutableCopy];

    // Cum nguyen am cuoi chu (bo "u" cua qu, "i" cua gi khi con nguyen am phia sau)
    NSInteger end = -1, start = -1;
    for (NSInteger i = (NSInteger)w.length - 1; i >= 0; i--) {
        BOOL v = ABVowel([w characterAtIndex:(NSUInteger)i], NULL, NULL, NULL);
        if (v && end < 0) end = i + 1;
        if (end >= 0) { if (v) start = i; else break; }
    }
    if (start >= 0 && end - start > 1 && start > 0) {
        unichar prev = (unichar)tolower([w characterAtIndex:(NSUInteger)start - 1]);
        int row = 0;
        ABVowel([w characterAtIndex:(NSUInteger)start], &row, NULL, NULL);
        if ((prev == 'q' && ABVowelBase(row) == 9) || (prev == 'g' && row == 5)) start++;
    }
    BOOL hasCluster = start >= 0;
    BOOL hasFinal = hasCluster && end < (NSInteger)w.length;

    // Dau thanh
    int newTone = -1;
    switch (k) { case 's': newTone = 1; break; case 'f': newTone = 2; break; case 'r': newTone = 3; break;
                 case 'x': newTone = 4; break; case 'j': newTone = 5; break; case 'z': newTone = 0; break; }
    if (newTone >= 0) {
        if (!hasCluster) return nil;
        int current = 0;
        for (NSInteger i = start; i < end; i++) {
            int row = 0, tone = 0; BOOL up = NO;
            ABVowel([w characterAtIndex:(NSUInteger)i], &row, &tone, &up);
            if (tone) current = tone;
            unichar plain = ABVowelMake(row, 0, up);
            [w replaceCharactersInRange:NSMakeRange((NSUInteger)i, 1) withString:[NSString stringWithCharacters:&plain length:1]];
        }
        if (newTone == 0) return current ? w : nil;
        if (current == newTone) { [w appendString:key]; return w; }   // go lai cung dau: bo dau, giu chu (vd "ss")
        NSUInteger pos = ABTonePosition(w, (NSUInteger)start, (NSUInteger)end, hasFinal);
        int row = 0; BOOL up = NO;
        ABVowel([w characterAtIndex:pos], &row, NULL, &up);
        unichar c = ABVowelMake(row, newTone, up);
        [w replaceCharactersInRange:NSMakeRange(pos, 1) withString:[NSString stringWithCharacters:&c length:1]];
        return w;
    }

    // aa ee oo -> â ê ô (go them lan nua: bo mu, giu chu)
    if (k == 'a' || k == 'e' || k == 'o') {
        if (!hasCluster) return nil;
        int base = k == 'a' ? 0 : (k == 'e' ? 3 : 6), hat = k == 'a' ? 2 : (k == 'e' ? 4 : 7);
        for (NSInteger i = end - 1; i >= start; i--) {
            int row = 0, tone = 0; BOOL up = NO;
            ABVowel([w characterAtIndex:(NSUInteger)i], &row, &tone, &up);
            if (row != base && row != hat) continue;
            unichar c = ABVowelMake(row == base ? hat : base, tone, up);
            [w replaceCharactersInRange:NSMakeRange((NSUInteger)i, 1) withString:[NSString stringWithCharacters:&c length:1]];
            if (row == hat) [w appendString:key];
            return w;
        }
        return nil;
    }

    // w -> ă ơ ư, uo -> ươ; "w" dung mot minh -> ư
    if (k == 'w') {
        if (!hasCluster) { unichar c = ABVowelMake(10, 0, keyUpper); [w appendString:[NSString stringWithCharacters:&c length:1]]; return w; }
        for (NSInteger i = start; i + 1 < end; i++) {
            int r1 = 0, t1 = 0, r2 = 0, t2 = 0; BOOL u1 = NO, u2 = NO;
            ABVowel([w characterAtIndex:(NSUInteger)i], &r1, &t1, &u1);
            ABVowel([w characterAtIndex:(NSUInteger)i + 1], &r2, &t2, &u2);
            if (r1 == 9 && (r2 == 6 || r2 == 8)) {
                unichar a = ABVowelMake(10, t1, u1), b = ABVowelMake(8, t2, u2);
                [w replaceCharactersInRange:NSMakeRange((NSUInteger)i, 2) withString:[NSString stringWithFormat:@"%C%C", a, b]];
                return w;
            }
        }
        for (NSInteger i = end - 1; i >= start; i--) {
            int row = 0, tone = 0; BOOL up = NO;
            ABVowel([w characterAtIndex:(NSUInteger)i], &row, &tone, &up);
            int to = row == 0 ? 1 : row == 6 ? 8 : row == 9 ? 10 : row == 1 ? 0 : row == 8 ? 6 : row == 10 ? 9 : -1;
            if (to < 0) continue;
            unichar c = ABVowelMake(to, tone, up);
            [w replaceCharactersInRange:NSMakeRange((NSUInteger)i, 1) withString:[NSString stringWithCharacters:&c length:1]];
            if (row == 1 || row == 8 || row == 10) [w appendString:key];   // ăw -> aw
            return w;
        }
        return nil;
    }

    // dd -> đ (chu cai dau)
    if (k == 'd' && w.length) {
        unichar f = [w characterAtIndex:0];
        if (f == 'd' || f == 'D') { [w replaceCharactersInRange:NSMakeRange(0, 1) withString:f == 'd' ? @"đ" : @"Đ"]; return w; }
        if (f == 0x0111 || f == 0x0110) { [w replaceCharactersInRange:NSMakeRange(0, 1) withString:f == 0x0111 ? @"d" : @"D"]; [w appendString:key]; return w; }
    }
    return nil;
}

#pragma mark - Keyboard view

static NSString *ABKT(NSString *vi, NSString *en) { return OMCTr(vi, en); }

// Bo cuc ban phim HarmonyOS (hang so rieng, goi y nho goc phim, phim , . rieng), mau giao dien moi (DESIGN.md,
// tools/preview/theme.html): nen logo 4 mau tren kinh mo, phim trang khong vien, phim chuc nang kinh trong vien trang,
// chu mau cham diu, Shift dang bat / Enter = gradient tim -> xanh troi chu trang; cham phim chu -> bong bong phong to.
static UIColor *ABKHex(uint32_t v, CGFloat a) { return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:a]; }
#define ABK_KEY     ABKHex(0xFFFFFF, 0.9)
#define ABK_FN      ABKHex(0xFFFFFF, 0.5)
#define ABK_SOFT    ABKHex(0xFFFFFF, 0.5)
#define ABK_DOWN    ABKHex(0xFFFFFF, 1)
#define ABK_TEXT    ABKHex(0x4A4F80, 1)
#define ABK_FN_TEXT ABKHex(0x4A4F80, 1)
#define ABK_HINT    ABKHex(0x4A4F80, 0.55)
#define ABK_ACC1    ABKHex(0x9B87F8, 1)
#define ABK_ACC2    ABKHex(0x5DB4F6, 1)
#define ABK_SHADOW  ABKHex(0x6E64C8, 1)


// Goi y goc phim: tieng Viet = chu / dau Telex phim do tao; tieng Anh = ky hieu nhu ban phim HarmonyOS
static NSString *ABKHint(NSString *c, BOOL vietnamese)
{
    static NSDictionary *telex, *sym;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        telex = @{@"s": @"´", @"f": @"`", @"r": @"?", @"x": @"~", @"j": @".", @"w": @"ư", @"d": @"đ", @"a": @"â", @"e": @"ê", @"o": @"ô"};
        sym = @{@"q": @"%", @"w": @"\\", @"e": @"|", @"r": @"=", @"t": @"[", @"y": @"]", @"u": @"<", @"i": @">", @"o": @"{", @"p": @"}",
                @"a": @"@", @"s": @"#", @"d": @"&", @"f": @"*", @"g": @"-", @"h": @"+", @"j": @"(", @"k": @")", @"l": @"\"",
                @"z": @"_", @"x": @"$", @"c": @"'", @"v": @":", @"b": @";", @"n": @"!", @"m": @"?"};
    });
    return (vietnamese ? telex : sym)[c.lowercaseString];
}

// Phim: chu (ky tu), hoac lenh: shift, del, mode (doi trang chu / ky hieu), lang (EN / VI), space, ret
@interface ABKey : UIButton
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *command;
@property (nonatomic) CGFloat weight;
@property (nonatomic) BOOL lit;                    // mau nhan khi khong cham (Shift dang bat, Enter)
@property (nonatomic, strong) UIColor *restColor;  // nen khi khong cham
@property (nonatomic, strong) UIColor *restTint;   // mau chu / icon khi khong to mau nhan
@property (nonatomic, strong) UILabel *hint;       // ky tu goi y goc tren phai
@property (nonatomic, strong) CAGradientLayer *accent;   // gradient mau nhan (lit)
@end
@implementation ABKey
- (void)paint:(BOOL)down
{
    if (self.lit && !self.accent) {
        self.accent = [CAGradientLayer layer];
        self.accent.colors = @[(id)ABK_ACC1.CGColor, (id)ABK_ACC2.CGColor];
        self.accent.startPoint = CGPointZero; self.accent.endPoint = CGPointMake(1, 1);
        self.accent.cornerRadius = 7;
        [self.layer insertSublayer:self.accent atIndex:0];
        self.layer.shadowColor = ABK_ACC1.CGColor;
        self.layer.shadowOpacity = 0.4; self.layer.shadowRadius = 6; self.layer.shadowOffset = CGSizeMake(0, 3);
    }
    self.accent.opacity = down ? 0.82 : 1;
    self.backgroundColor = self.lit ? [UIColor clearColor] : (down ? ABK_DOWN : self.restColor);
    self.tintColor = self.lit ? [UIColor whiteColor] : self.restTint;
}
- (void)setHighlighted:(BOOL)h
{
    if (h == self.highlighted) return;
    [super setHighlighted:h];
    [self paint:h];
    // HarmonyOS: phim lun nhe 0,96 roi nay lai; phim chu: bong bong phong to ky tu phia tren
    [UIView animateWithDuration:h ? 0.08 : 0.3 delay:0 usingSpringWithDamping:h ? 1 : 0.6 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = h ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity; } completion:nil];
    if (!self.command && self.value.length) [[ABKeyboard shared] key:self pressed:h];
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.accent.frame = self.bounds;
    [CATransaction commit];
    if (self.hint) self.hint.frame = CGRectMake(self.bounds.size.width - 13, 0, 11, 11);
}
@end

@interface ABKeyboard ()
@property (nonatomic, copy) NSString *app;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIVisualEffectView *glass;   // nen kinh trang cua panel (panel giu bong)
@property (nonatomic, strong) UILabel *bubble;            // bong bong phong to khi cham phim chu
@property (nonatomic, strong) UIView *field;        // vien chua chu da go
@property (nonatomic, strong) UILabel *preview;     // chu da go trong lan nay (o nhap cua app bi ban phim che)
@property (nonatomic, strong) UIButton *langButton; // chip VI / EN
@property (nonatomic, strong) UIButton *hideButton;
@property (nonatomic, strong) UIView *keysView;
@property (nonatomic, strong) NSMutableArray<NSArray<ABKey *> *> *rows;
@property (nonatomic) BOOL numbers, shift, vietnamese;
@property (nonatomic) NSInteger returnType;
@property (nonatomic, strong) NSMutableString *word;   // chu dang go (Telex)
@property (nonatomic, strong) NSMutableString *typed;  // xem truoc
@end

@implementation ABKeyboard

+ (instancetype)shared
{
    static ABKeyboard *kb;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ kb = [ABKeyboard new]; });
    return kb;
}

- (void)showForApp:(NSString *)bid keyboardType:(NSInteger)type returnType:(NSInteger)ret
{
    UIWindow *window = [[ABHost shared] carWindow];
    if (!bid || !window) { ABLog("ban phim xe: khong co cua so (%@)", bid); return; }
    BOOL fresh = ![self.app isEqualToString:bid] || !self.panel.superview;
    self.app = bid;
    self.returnType = ret;
    self.vietnamese = [OMCPref(AB_KEY_KEYBOARD_LANG, @([OMCCurrentLanguage() isEqualToString:@"vi"] ? 1 : 0)) intValue] == 1;
    // UIKeyboardTypeNumberPad 4, PhonePad 5, DecimalPad 8, NumbersAndPunctuation 2, ASCIICapableNumberPad 11
    self.numbers = (type == 2 || type == 4 || type == 5 || type == 8 || type == 11);
    self.shift = NO;
    if (fresh) { self.word = [NSMutableString string]; self.typed = [NSMutableString string]; }
    if (!self.panel) [self buildPanel];
    if (self.panel.superview != window) [window addSubview:self.panel];
    [self layoutPanelIn:window];
    [window bringSubviewToFront:self.panel];
    [self rebuildKeys];
    [self updatePreview];
    if (fresh) {   // HarmonyOS: truot len tu mep duoi (duong cong friction 0.2, 0, 0.2, 1; 350 ms)
        self.panel.transform = CGAffineTransformMakeTranslation(0, self.panel.bounds.size.height + 12);
        UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:0.35
            timingParameters:[[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.2, 0) controlPoint2:CGPointMake(0.2, 1)]];
        [a addAnimations:^{ self.panel.transform = CGAffineTransformIdentity; }];
        [a startAnimation];
    }
    ABLog("ban phim xe: hien cho %@ (kieu %ld, phim enter %ld)", bid, (long)type, (long)ret);
}

- (void)hideForApp:(NSString *)bid
{
    if (!self.app || (bid && ![bid isEqualToString:self.app])) return;
    ABLog("ban phim xe: an (%@)", self.app);
    self.app = nil;
    UIView *panel = self.panel;
    [self key:nil pressed:NO];
    UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:0.25
        timingParameters:[[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.2, 0) controlPoint2:CGPointMake(0.2, 1)]];
    [a addAnimations:^{ panel.transform = CGAffineTransformMakeTranslation(0, panel.bounds.size.height + 12); }];
    [a addCompletion:^(UIViewAnimatingPosition pos) { if (!self.app) [panel removeFromSuperview]; panel.transform = CGAffineTransformIdentity; }];
    [a startAnimation];
}

// Khung nhu ban phim HarmonyOS: the noi bo tron ca 4 goc (20), cach mep 6 pt, trai theo ca vung app cua man xe (khong
// tinh dock) - ke ca khi app dang o 1 o chia, ban phim van to nhu luc 1 app (nguoi dung); cao ~78% man.
#define ABK_RADIUS 20.0
#define ABK_MARGIN 6.0
- (void)layoutPanelIn:(UIWindow *)window
{
    CGRect b = window.bounds;
    CGRect carArea = [[ABHost shared] carAppArea];
    CGRect area = carArea.size.width > 100 ? CGRectIntersection(carArea, b) : b;
    if (CGRectIsEmpty(area)) area = b;
    CGFloat w = MAX(200, area.size.width - 2 * ABK_MARGIN);
    CGFloat x = MIN(MAX(CGRectGetMinX(area) + ABK_MARGIN, 0), b.size.width - w);
    CGFloat h = MIN(floor(b.size.height * 0.78), 280);
    self.panel.frame = CGRectMake(x, CGRectGetMaxY(b) - h - ABK_MARGIN, w, h);
    self.glass.frame = self.panel.bounds;
    self.panel.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.panel.bounds cornerRadius:ABK_RADIUS].CGPath;
}

// Bong bong phong to kieu HarmonyOS: o trang 1.3 x 1.45 phim, day ngang mep tren phim, chu to; nam trong ban phim
// theo chieu ngang. key nil / down NO: an.
- (void)key:(UIButton *)key pressed:(BOOL)down
{
    if (!down || !key.superview || !self.panel) {
        [UIView animateWithDuration:0.12 animations:^{ self.bubble.alpha = 0; }];
        return;
    }
    if (!self.bubble) {
        UILabel *l = [UILabel new];
        l.backgroundColor = [UIColor whiteColor];
        l.textColor = ABK_TEXT;
        l.textAlignment = NSTextAlignmentCenter;
        l.layer.cornerRadius = 9;
        l.layer.cornerCurve = kCACornerCurveContinuous;
        l.layer.masksToBounds = NO;
        l.layer.shadowColor = ABK_SHADOW.CGColor;
        l.layer.shadowOpacity = 0.3; l.layer.shadowRadius = 9; l.layer.shadowOffset = CGSizeMake(0, 6);
        l.userInteractionEnabled = NO;
        self.bubble = l;
    }
    UILabel *l = self.bubble;
    if (l.superview != self.panel) [self.panel addSubview:l];
    // Khung that cua phim (phim co the dang lun 0,96): tam phim + kich thuoc bounds
    CGRect seen = [self.panel convertRect:key.bounds fromView:key];
    CGRect kf = CGRectMake(CGRectGetMidX(seen) - key.bounds.size.width / 2, CGRectGetMidY(seen) - key.bounds.size.height / 2,
                           key.bounds.size.width, key.bounds.size.height);
    CGFloat bw = round(kf.size.width * 1.3), bh = round(kf.size.height * 1.45);
    CGFloat bx = MIN(MAX(CGRectGetMidX(kf) - bw / 2, 2), self.panel.bounds.size.width - bw - 2);
    l.transform = CGAffineTransformIdentity;
    l.layer.anchorPoint = CGPointMake(0.5, 1);   // phong ra tu mep duoi (cho phim)
    l.frame = CGRectMake(bx, CGRectGetMinY(kf) - bh + 2, bw, bh);
    l.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:l.bounds cornerRadius:9].CGPath;
    l.font = [UIFont systemFontOfSize:round(kf.size.height * 0.85)];
    l.text = [key titleForState:UIControlStateNormal];
    [self.panel bringSubviewToFront:l];
    l.alpha = 1;
    l.transform = CGAffineTransformMakeScale(0.7, 0.7);
    [UIView animateWithDuration:0.18 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ l.transform = CGAffineTransformIdentity; } completion:nil];
}

- (void)buildPanel
{
    // Kinh trang mo, the noi bo tron 4 goc nhu ban phim HarmonyOS (ABK_RADIUS, cach mep ABK_MARGIN), bong tim nhat
    UIView *p = [UIView new];
    p.backgroundColor = [UIColor clearColor];
    p.layer.shadowColor = ABK_SHADOW.CGColor;
    p.layer.shadowOpacity = 0.3; p.layer.shadowRadius = 20; p.layer.shadowOffset = CGSizeMake(0, 6);
    p.autoresizingMask = UIViewAutoresizingNone;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight]];
    // Nen logo 4 mau tren kinh mo, cung nen voi khay bo cuc / bang chon app
    glass.contentView.backgroundColor = [UIColor clearColor];
    UIImageView *mesh = [[UIImageView alloc] initWithImage:OMCLogoMeshImage(NO)];
    mesh.frame = glass.contentView.bounds;
    mesh.contentMode = UIViewContentModeScaleToFill;
    mesh.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [glass.contentView addSubview:mesh];
    glass.layer.cornerRadius = 20;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.borderWidth = 1;
    glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
    glass.clipsToBounds = YES;
    glass.userInteractionEnabled = NO;
    [p addSubview:glass];
    self.glass = glass;

    // Hang tren: o chu da go | chip VI / EN | nut an ban phim
    UIView *field = [UIView new];
    field.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
    field.layer.cornerRadius = 12;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.layer.borderWidth = 1;
    field.layer.borderColor = [UIColor whiteColor].CGColor;
    [p addSubview:field];
    self.field = field;
    UILabel *preview = [UILabel new];
    preview.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    preview.lineBreakMode = NSLineBreakByTruncatingHead;   // giu phan vua go
    [field addSubview:preview];
    self.preview = preview;

    UIButton *lang = [UIButton buttonWithType:UIButtonTypeCustom];
    lang.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    [lang setTitleColor:ABK_FN_TEXT forState:UIControlStateNormal];
    lang.layer.borderWidth = 1;
    lang.layer.borderColor = [ABK_TEXT colorWithAlphaComponent:0.25].CGColor;
    lang.layer.cornerRadius = 6;
    [lang addTarget:self action:@selector(langTapped) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:lang];
    self.langButton = lang;

    UIButton *hide = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    [hide setImage:[UIImage systemImageNamed:@"keyboard.chevron.compact.down" withConfiguration:cfg] forState:UIControlStateNormal];
    hide.tintColor = ABK_FN_TEXT;
    [hide addTarget:self action:@selector(hideTapped) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:hide];
    self.hideButton = hide;

    UIView *keys = [UIView new];
    [p addSubview:keys];
    self.keysView = keys;
    self.panel = p;
}

// title: chu tren phim; symbol: SF Symbol thay cho chu. Kieu: chu (trang), chuc nang (tim nhat), soft (, .), nhan (Enter)
- (ABKey *)key:(NSString *)title symbol:(NSString *)symbol value:(NSString *)value command:(NSString *)command weight:(CGFloat)weight
{
    ABKey *k = [ABKey buttonWithType:UIButtonTypeCustom];
    k.value = value;
    k.command = command;
    k.weight = weight;
    BOOL space = [command isEqualToString:@"space"], ret = [command isEqualToString:@"ret"];
    BOOL fn = command != nil && !space && !ret, soft = !command && ([value isEqualToString:@","] || [value isEqualToString:@"."]);
    k.restColor = fn ? ABK_FN : soft ? ABK_SOFT : ABK_KEY;
    k.lit = ret || ([command isEqualToString:@"shift"] && self.shift);
    k.restTint = fn ? ABK_FN_TEXT : ABK_TEXT;
    k.layer.cornerRadius = 7;
    k.layer.cornerCurve = kCACornerCurveContinuous;
    if (!k.lit) {   // phim trang noi tren nen logo: khong vien, bong tim mong duoi phim; phim chuc nang / , . = kinh trong vien trang
        k.layer.borderWidth = (fn || soft) ? 1 : 0;
        k.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
        k.layer.shadowColor = ABK_SHADOW.CGColor;
        k.layer.shadowOpacity = 0.18; k.layer.shadowRadius = 1; k.layer.shadowOffset = CGSizeMake(0, 1);
    }
    if (symbol) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
        [k setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    } else {
        [k setTitle:title forState:UIControlStateNormal];
    }
    [k setTitleColor:space ? ABK_HINT : (k.lit ? [UIColor whiteColor] : k.restTint) forState:UIControlStateNormal];
    k.titleLabel.font = space ? [UIFont systemFontOfSize:10] : fn ? [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold] : [UIFont systemFontOfSize:17];
    k.titleLabel.adjustsFontSizeToFitWidth = YES;
    [k paint:NO];
    [k addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
    return k;
}

- (ABKey *)key:(NSString *)title value:(NSString *)value command:(NSString *)command weight:(CGFloat)weight
{
    return [self key:title symbol:nil value:value command:command weight:weight];
}

- (void)rebuildKeys
{
    for (UIView *v in [self.keysView.subviews copy]) [v removeFromSuperview];
    self.rows = [NSMutableArray array];
    [self.langButton setTitle:self.vietnamese ? @"VI" : @"EN" forState:UIControlStateNormal];
    // Hang so rieng nhu ban phim HarmonyOS; trang ky hieu: 4 hang ky hieu
    NSArray<NSString *> *lines = self.numbers ? @[@"1234567890", @"[]{}#%^*+=", @"-/:;()$&@\"", @".,?!'"]
                                              : @[@"1234567890", @"qwertyuiop", @"asdfghjkl", @"zxcvbnm"];
    for (NSUInteger r = 0; r < lines.count; r++) {
        NSMutableArray *row = [NSMutableArray array];
        BOOL letters = !self.numbers && r > 0;
        NSString *line = lines[r];
        for (NSUInteger i = 0; i < line.length; i++) {
            NSString *c = [line substringWithRange:NSMakeRange(i, 1)];
            NSString *shown = (letters && self.shift) ? c.uppercaseString : c;
            ABKey *k = [self key:shown value:shown command:nil weight:1];
            NSString *hint = letters ? ABKHint(c, self.vietnamese) : nil;
            if (hint) {
                UILabel *h = [UILabel new];
                h.text = hint;
                h.font = [UIFont systemFontOfSize:8];
                h.textColor = ABK_HINT;
                h.textAlignment = NSTextAlignmentCenter;
                h.userInteractionEnabled = NO;
                [k addSubview:h];
                k.hint = h;
            }
            [row addObject:k];
        }
        if (r == lines.count - 1) {
            [row insertObject:self.numbers ? [self key:@"#" value:@"#" command:nil weight:1.5]
                                           : [self key:nil symbol:self.shift ? @"shift.fill" : @"shift" value:nil command:@"shift" weight:1.5] atIndex:0];
            [row addObject:[self key:nil symbol:@"delete.left" value:nil command:@"del" weight:1.5]];
        }
        [self.rows addObject:row];
    }
    [self.rows addObject:@[
        [self key:self.numbers ? @"ABC" : @"#+=" value:nil command:@"mode" weight:1.4],
        [self key:nil symbol:@"globe" value:nil command:@"lang" weight:1.1],
        [self key:@"," value:@"," command:nil weight:1],
        [self key:self.vietnamese ? @"Tiếng Việt · Telex" : @"space" value:@" " command:@"space" weight:4.2],
        [self key:@"." value:@"." command:nil weight:1],
        [self key:nil symbol:@"return" value:nil command:@"ret" weight:1.8],
    ]];
    for (NSArray *row in self.rows) for (ABKey *k in row) [self.keysView addSubview:k];
    [self layoutKeys];
}

- (void)layoutKeys
{
    // Hang tren cao 24 (o chu, chip VI / EN, nut an); duoi: 5 hang phim, khe 5 (tools/preview/keyboard.html, theme.html)
    CGRect b = self.panel.bounds;
    CGFloat pad = 5, top = 33, gap = 5, bar = 24, langW = 26, hideW = 34;
    self.hideButton.frame = CGRectMake(b.size.width - pad - hideW, 5, hideW, bar);
    self.langButton.frame = CGRectMake(CGRectGetMinX(self.hideButton.frame) - 4 - langW, 5 + (bar - 16) / 2, langW, 16);
    self.field.frame = CGRectMake(pad, 5, CGRectGetMinX(self.langButton.frame) - 8 - pad, bar);
    self.preview.frame = CGRectInset(self.field.bounds, 10, 0);
    self.keysView.frame = CGRectMake(pad, top, b.size.width - pad * 2, b.size.height - top - pad);
    CGSize area = self.keysView.bounds.size;
    NSUInteger n = self.rows.count;
    CGFloat rowH = floor((area.height - gap * (n - 1)) / n);
    CGFloat unit = (area.width - gap * 9) / 10;   // 10 phim tren hang so / hang dau
    UIFont *letterFont = [UIFont systemFontOfSize:MAX(14, floor(rowH * 0.56))];
    for (NSUInteger r = 0; r < n; r++) {
        NSArray<ABKey *> *row = self.rows[r];
        CGFloat total = 0;
        for (ABKey *k in row) total += k.weight;
        CGFloat avail = area.width - gap * (row.count - 1);
        CGFloat u = (r >= n - 2 || row.count >= 10) ? avail / total : MIN(unit, avail / total);   // hang asdf thut vao
        CGFloat x = (area.width - (u * total + gap * (row.count - 1))) / 2;
        for (ABKey *k in row) {
            k.frame = CGRectMake(x, r * (rowH + gap), u * k.weight, rowH);
            if (!k.command) k.titleLabel.font = letterFont;
            x += u * k.weight + gap;
        }
    }
}

- (void)updatePreview
{
    if (self.typed.length) {
        self.preview.text = self.typed;
        self.preview.textColor = ABK_TEXT;
    } else {
        self.preview.text = self.vietnamese ? ABKT(@"Gõ tiếng Việt kiểu Telex", @"Vietnamese (Telex)") : ABKT(@"Gõ để nhập vào app", @"Type into the app");
        self.preview.textColor = ABK_HINT;
    }
}

- (void)langTapped
{
    [self keyTapped:[self key:nil value:nil command:@"lang" weight:1]];
}

- (void)send:(NSString *)action del:(NSUInteger)del text:(NSString *)text
{
    if (!self.app) return;
    NSMutableDictionary *info = [@{@"action": action, @"del": @(del)} mutableCopy];
    if (text) info[@"text"] = text;
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:AB_NOTIF_KEY object:self.app userInfo:info];
}

- (void)typeCharacter:(NSString *)c
{
    NSString *rewritten = (self.vietnamese && self.word.length + 1 < 12) ? ABTelexApply(self.word, c) : nil;
    BOOL letter = [[NSCharacterSet letterCharacterSet] characterIsMember:[c characterAtIndex:0]];
    if (rewritten) {
        [self send:@"type" del:self.word.length text:rewritten];
        if (self.typed.length >= self.word.length) [self.typed deleteCharactersInRange:NSMakeRange(self.typed.length - self.word.length, self.word.length)];
        [self.typed appendString:rewritten];
        [self.word setString:rewritten];
    } else {
        [self send:@"type" del:0 text:c];
        [self.typed appendString:c];
        if (letter) [self.word appendString:c]; else [self.word setString:@""];
    }
}

- (void)keyTapped:(ABKey *)k
{
    @try {
        NSString *cmd = k.command;
        if (!cmd || [cmd isEqualToString:@"space"]) {
            [self typeCharacter:k.value];
            if (self.shift) { self.shift = NO; [self rebuildKeys]; }
        } else if ([cmd isEqualToString:@"del"]) {
            [self send:@"type" del:1 text:nil];
            if (self.typed.length) [self.typed deleteCharactersInRange:NSMakeRange(self.typed.length - 1, 1)];
            if (self.word.length) [self.word deleteCharactersInRange:NSMakeRange(self.word.length - 1, 1)];
        } else if ([cmd isEqualToString:@"shift"]) {
            self.shift = !self.shift;
            [self rebuildKeys];
        } else if ([cmd isEqualToString:@"mode"]) {
            self.numbers = !self.numbers;
            self.shift = NO;
            [self rebuildKeys];
        } else if ([cmd isEqualToString:@"lang"]) {
            self.vietnamese = !self.vietnamese;
            [self.word setString:@""];
            CFPreferencesSetAppValue((__bridge CFStringRef)AB_KEY_KEYBOARD_LANG, (__bridge CFPropertyListRef)@(self.vietnamese ? 1 : 0), OMC_PREFS_DOMAIN);
            OMCPrefsSync();
            [self rebuildKeys];
        } else if ([cmd isEqualToString:@"ret"]) {
            [self.word setString:@""];
            [self send:@"return" del:0 text:nil];
        }
        [self updatePreview];
        [self.panel.superview bringSubviewToFront:self.panel];   // o app moi mo co the vua nam len tren
    } @catch (NSException *e) { ABLog("ban phim xe: loi phim %@", e); }
}

- (void)hideTapped
{
    [self send:@"dismiss" del:0 text:nil];   // app bo chon o nhap -> AB_DARWIN_APP_KEYBOARD an -> hideForApp
    [self hideForApp:nil];
}

@end
