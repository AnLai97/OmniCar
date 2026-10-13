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

static BOOL ABKVietnameseUI(void)
{
    NSString *lang = OMCPref(@"language", nil);
    if ([lang isKindOfClass:[NSString class]] && lang.length) return [lang isEqualToString:@"vi"];
    return [[NSLocale preferredLanguages].firstObject hasPrefix:@"vi"];
}

static NSString *ABKT(NSString *vi, NSString *en) { return ABKVietnameseUI() ? vi : en; }

// Phim: chu (ky tu), hoac lenh: shift, del, mode (doi trang chu / so), lang (EN / VI), space, ret, hide
@interface ABKey : UIButton
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *command;
@property (nonatomic) CGFloat weight;
@end
@implementation ABKey
- (void)setHighlighted:(BOOL)h
{
    [super setHighlighted:h];
    self.alpha = h ? 0.55 : 1;
}
@end

@interface ABKeyboard ()
@property (nonatomic, copy) NSString *app;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *preview;     // chu da go trong lan nay (o nhap co the nam duoi ban phim)
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
    self.vietnamese = [OMCPref(AB_KEY_KEYBOARD_LANG, @(ABKVietnameseUI() ? 1 : 0)) intValue] == 1;
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
    if (fresh) {
        self.panel.alpha = 0;
        self.panel.transform = CGAffineTransformMakeTranslation(0, 40);
        [UIView animateWithDuration:0.22 animations:^{ self.panel.alpha = 1; self.panel.transform = CGAffineTransformIdentity; }];
    }
    ABLog("ban phim xe: hien cho %@ (kieu %ld, phim enter %ld)", bid, (long)type, (long)ret);
}

- (void)hideForApp:(NSString *)bid
{
    if (!self.app || (bid && ![bid isEqualToString:self.app])) return;
    ABLog("ban phim xe: an (%@)", self.app);
    self.app = nil;
    UIView *panel = self.panel;
    [UIView animateWithDuration:0.18 animations:^{ panel.alpha = 0; panel.transform = CGAffineTransformMakeTranslation(0, 40); }
                     completion:^(BOOL f) { if (!self.app) [panel removeFromSuperview]; panel.transform = CGAffineTransformIdentity; }];
}

// Duoi man xe, giua o app dang go (trong man xe), cao toi da nua man
- (void)layoutPanelIn:(UIWindow *)window
{
    CGRect b = window.bounds;
    CGFloat w = MIN(b.size.width - 16, 720), h = MIN(floor(b.size.height * 0.52), 260);
    CGRect app = [[ABHost shared] frameOfApp:self.app];
    CGFloat mid = CGRectIsNull(app) ? CGRectGetMidX(b) : CGRectGetMidX(app);
    CGFloat x = MIN(MAX(mid - w / 2, 8), CGRectGetMaxX(b) - w - 8);
    self.panel.frame = CGRectMake(x, CGRectGetMaxY(b) - h - 6, w, h);
}

- (void)buildPanel
{
    UIView *p = [UIView new];
    p.backgroundColor = [UIColor colorWithWhite:0.11 alpha:0.97];
    p.layer.cornerRadius = 18;
    p.layer.cornerCurve = kCACornerCurveContinuous;
    p.layer.borderWidth = 0.5;
    p.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    p.clipsToBounds = YES;
    p.autoresizingMask = UIViewAutoresizingNone;

    UILabel *preview = [UILabel new];
    preview.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    preview.textColor = [UIColor whiteColor];
    preview.lineBreakMode = NSLineBreakByTruncatingHead;   // giu phan vua go
    [p addSubview:preview];
    self.preview = preview;

    UIButton *hide = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    [hide setImage:[UIImage systemImageNamed:@"keyboard.chevron.compact.down" withConfiguration:cfg] forState:UIControlStateNormal];
    hide.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
    hide.tag = 7;
    [hide addTarget:self action:@selector(hideTapped) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:hide];

    UIView *keys = [UIView new];
    [p addSubview:keys];
    self.keysView = keys;
    self.panel = p;
}

- (ABKey *)key:(NSString *)title value:(NSString *)value command:(NSString *)command weight:(CGFloat)weight
{
    ABKey *k = [ABKey buttonWithType:UIButtonTypeCustom];
    k.value = value;
    k.command = command;
    k.weight = weight;
    BOOL special = command != nil && ![command isEqualToString:@"space"];
    k.backgroundColor = special ? [UIColor colorWithWhite:0.32 alpha:1] : [UIColor colorWithWhite:0.45 alpha:1];
    if ([command isEqualToString:@"ret"]) k.backgroundColor = [UIColor colorWithRed:0.04 green:0.35 blue:0.97 alpha:1];
    if ([command isEqualToString:@"shift"] && self.shift) k.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
    k.layer.cornerRadius = 8;
    k.layer.cornerCurve = kCACornerCurveContinuous;
    [k setTitle:title forState:UIControlStateNormal];
    [k setTitleColor:([command isEqualToString:@"shift"] && self.shift) ? [UIColor blackColor] : [UIColor whiteColor] forState:UIControlStateNormal];
    k.titleLabel.font = [UIFont systemFontOfSize:command ? 17 : 22 weight:command ? UIFontWeightSemibold : UIFontWeightRegular];
    k.titleLabel.adjustsFontSizeToFitWidth = YES;
    [k addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
    return k;
}

- (NSString *)returnTitle
{
    switch (self.returnType) {
        case UIReturnKeyGo:     return ABKT(@"Đi", @"Go");
        case UIReturnKeySearch: return ABKT(@"Tìm", @"Search");
        case UIReturnKeySend:   return ABKT(@"Gửi", @"Send");
        case UIReturnKeyDone:   return ABKT(@"Xong", @"Done");
        case UIReturnKeyNext:   return ABKT(@"Tiếp", @"Next");
        default:                return @"↵";
    }
}

- (void)rebuildKeys
{
    for (UIView *v in [self.keysView.subviews copy]) [v removeFromSuperview];
    self.rows = [NSMutableArray array];
    NSArray<NSString *> *lines = self.numbers ? @[@"1234567890", @"-/:;()&@\"", @".,?!'"] : @[@"qwertyuiop", @"asdfghjkl", @"zxcvbnm"];
    for (NSUInteger r = 0; r < lines.count; r++) {
        NSMutableArray *row = [NSMutableArray array];
        if (r == 2) [row addObject:self.numbers ? [self key:@"#" value:@"#" command:nil weight:1.5]
                                                : [self key:@"⇧" value:nil command:@"shift" weight:1.5]];
        NSString *line = lines[r];
        for (NSUInteger i = 0; i < line.length; i++) {
            NSString *c = [line substringWithRange:NSMakeRange(i, 1)];
            NSString *shown = (self.shift && !self.numbers) ? c.uppercaseString : c;
            [row addObject:[self key:shown value:shown command:nil weight:1]];
        }
        if (r == 2) [row addObject:[self key:@"⌫" value:nil command:@"del" weight:1.5]];
        [self.rows addObject:row];
    }
    [self.rows addObject:@[
        [self key:self.numbers ? @"ABC" : @"123" value:nil command:@"mode" weight:1.5],
        [self key:self.vietnamese ? @"VI" : @"EN" value:nil command:@"lang" weight:1.2],
        [self key:self.vietnamese ? @"Telex" : @"space" value:@" " command:@"space" weight:4.5],
        [self key:@"." value:@"." command:nil weight:1],
        [self key:[self returnTitle] value:nil command:@"ret" weight:2],
    ]];
    for (NSArray *row in self.rows) for (ABKey *k in row) [self.keysView addSubview:k];
    [self layoutKeys];
}

- (void)layoutKeys
{
    CGRect b = self.panel.bounds;
    CGFloat pad = 8, top = 40, gap = 6;
    self.preview.frame = CGRectMake(pad + 6, 4, b.size.width - pad * 2 - 56, top - 6);
    [self.panel viewWithTag:7].frame = CGRectMake(b.size.width - 50, 2, 44, top - 4);
    self.keysView.frame = CGRectMake(pad, top, b.size.width - pad * 2, b.size.height - top - pad);
    CGSize area = self.keysView.bounds.size;
    NSUInteger n = self.rows.count;
    CGFloat rowH = floor((area.height - gap * (n - 1)) / n);
    CGFloat unit = (area.width - gap * 9) / 10;   // 10 phim chu tren hang dau
    for (NSUInteger r = 0; r < n; r++) {
        NSArray<ABKey *> *row = self.rows[r];
        CGFloat total = 0;
        for (ABKey *k in row) total += k.weight;
        CGFloat avail = area.width - gap * (row.count - 1);
        CGFloat u = (r == n - 1 || r == 2) ? avail / total : MIN(unit, avail / total);   // hang 2 thut vao nhu ban phim that
        CGFloat x = (area.width - (u * total + gap * (row.count - 1))) / 2;
        for (ABKey *k in row) {
            k.frame = CGRectMake(x, r * (rowH + gap), u * k.weight, rowH);
            x += u * k.weight + gap;
        }
    }
}

- (void)updatePreview
{
    if (self.typed.length) {
        self.preview.text = self.typed;
        self.preview.textColor = [UIColor whiteColor];
    } else {
        self.preview.text = self.vietnamese ? ABKT(@"Gõ tiếng Việt kiểu Telex", @"Vietnamese (Telex)") : ABKT(@"Gõ để nhập vào app", @"Type into the app");
        self.preview.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    }
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
