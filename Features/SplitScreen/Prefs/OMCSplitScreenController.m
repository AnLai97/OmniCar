#import "OMCSplitScreenController.h"
#import "OMCTheme.h"
#import "../SplitScreen.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface UIImage (OMCSplitPagePrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(double)scale;
@end

static NSString *OMCSplitName(NSString *bid)
{
    Class LSProxy = objc_getClass("LSApplicationProxy");
    id proxy = LSProxy ? ((id (*)(id, SEL, id))objc_msgSend)(LSProxy, NSSelectorFromString(@"applicationProxyForIdentifier:"), bid) : nil;
    NSString *name = proxy ? ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"localizedName")) : nil;
    return [name isKindOfClass:[NSString class]] && name.length ? name : bid;
}

static UIImage *OMCSplitIcon(NSString *bid, CGFloat side)
{
    if (![bid isKindOfClass:[NSString class]] || !bid.length || ![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
    if (!icon) return nil;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.23] addClip];
        [icon drawInRect:CGRectMake(0, 0, side, side)];
    }];
}

// O cua bo cuc (2, 3, 13 = 1 lon + 2, 31 = 2 + 1 lon) trong khung w x h
static NSArray<NSValue *> *OMCSplitBoxes(NSInteger layout, CGFloat w, CGFloat h, CGFloat g)
{
    NSMutableArray *boxes = [NSMutableArray array];
    if (layout == 13 || layout == 31) {
        CGFloat mw = floor((w - g) * 0.55), th = floor((h - g) / 2);
        [boxes addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, mw, h)]];
        [boxes addObject:[NSValue valueWithCGRect:CGRectMake(mw + g, 0, w - mw - g, th)]];
        [boxes addObject:[NSValue valueWithCGRect:CGRectMake(mw + g, th + g, w - mw - g, h - th - g)]];
        if (layout == 31) for (NSUInteger i = 0; i < boxes.count; i++) {
            CGRect b = [boxes[i] CGRectValue]; b.origin.x = w - CGRectGetMaxX(b); boxes[i] = [NSValue valueWithCGRect:b];
        }
    } else {
        NSInteger n = layout == 3 ? 3 : 2;
        CGFloat bw = (w - g * (n - 1)) / n;
        for (NSInteger i = 0; i < n; i++) [boxes addObject:[NSValue valueWithCGRect:CGRectMake(i * (bw + g), 0, bw, h)]];
    }
    return boxes;
}

// So do bo cuc thu nho co icon app trong tung o
static UIImage *OMCSplitLayoutPicture(NSInteger layout, NSArray *apps, CGSize size)
{
    NSArray *boxes = OMCSplitBoxes(layout, size.width - 4, size.height - 4, 2);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithWhite:0.5 alpha:0.12] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:7] fill];
        for (NSUInteger i = 0; i < boxes.count; i++) {
            CGRect b = CGRectOffset([boxes[i] CGRectValue], 2, 2);
            [[UIColor colorWithWhite:0.5 alpha:0.22] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:5] fill];
            UIImage *icon = i < apps.count ? OMCSplitIcon(apps[i], MIN(16, MIN(b.size.width, b.size.height) - 3)) : nil;
            if (icon) [icon drawInRect:CGRectMake(CGRectGetMidX(b) - icon.size.width / 2, CGRectGetMidY(b) - icon.size.height / 2, icon.size.width, icon.size.height)];
        }
    }];
}

// Xem truoc man xe: dock trai + 2 o (app dung gan nhat | o ghim co ghim), tat thi chu mo
@interface OMCSplitPreview : UIView
@property (nonatomic, copy) NSString *left, *pinned;
@property (nonatomic) BOOL on;
@property (nonatomic, copy) NSString *offText;
@end

@implementation OMCSplitPreview
- (instancetype)initWithFrame:(CGRect)f
{
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor colorWithRed:0.055 green:0.06 blue:0.075 alpha:1];
        self.layer.cornerRadius = 14; self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}
- (void)drawRect:(CGRect)rect
{
    CGSize s = self.bounds.size;
    [[UIColor colorWithRed:0.086 green:0.09 blue:0.106 alpha:1] setFill];
    UIRectFill(CGRectMake(0, 0, 30, s.height));
    NSArray *dock = @[OMCColorFromHex(@"#8B7CFF"), OMCColorFromHex(@"#2E9CF5"), OMCColorFromHex(@"#FA2D55")];
    for (NSUInteger i = 0; i < dock.count; i++) {
        [dock[i] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7, 10 + i * 22, 16, 16) cornerRadius:5] fill];
    }
    if (!self.on) {
        NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:13], NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.55]};
        CGSize ts = [self.offText sizeWithAttributes:a];
        [self.offText drawAtPoint:CGPointMake(15 + (s.width - ts.width) / 2, (s.height - ts.height) / 2) withAttributes:a];
        return;
    }
    CGRect area = CGRectMake(34, 4, s.width - 38, s.height - 8);
    CGFloat lw = floor((area.size.width - 4) * 0.46);
    CGRect panes[2] = { CGRectMake(area.origin.x, area.origin.y, lw, area.size.height),
                        CGRectMake(area.origin.x + lw + 4, area.origin.y, area.size.width - lw - 4, area.size.height) };
    NSArray *apps = @[self.left ?: @"", self.pinned ?: @""];
    for (int i = 0; i < 2; i++) {
        [[UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:1] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:panes[i] cornerRadius:10] fill];
        UIImage *icon = OMCSplitIcon(apps[i], MIN(44, panes[i].size.height * 0.42));
        if (icon) [icon drawInRect:CGRectMake(CGRectGetMidX(panes[i]) - icon.size.width / 2, CGRectGetMidY(panes[i]) - icon.size.height / 2, icon.size.width, icon.size.height)];
    }
    if ([self.pinned length]) {
        UIImage *pin = [[UIImage systemImageNamed:@"pin.fill"] imageWithTintColor:OMCColorFromHex(@"#FFB340") renderingMode:UIImageRenderingModeAlwaysOriginal];
        [pin drawInRect:CGRectMake(CGRectGetMaxX(panes[1]) - 18, panes[1].origin.y + 6, 12, 13)];
    }
}
@end

enum { SPPreview = 0, SPMain, SPLayout, SPFavs, SPPanel, SPHelp, SPCount };
static char kOMCSplitIndex;

@interface OMCSplitScreenController () <UITextFieldDelegate>
@property (nonatomic, strong) OMCSplitPreview *preview;
@property (nonatomic) NSInteger editing;          // yeu thich dang sua (1..3), 0 = khong
@property (nonatomic) BOOL showGestures, showSiri;
@end

@implementation OMCSplitScreenController

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (!self.title.length) self.title = L(@"SPLITSCREEN");
}

#pragma mark - Gia tri

- (BOOL)on { return [[self prefForKey:SPL_KEY_ENABLED def:@YES] boolValue]; }
- (NSString *)stringForKey:(NSString *)key { id v = [self prefForKey:key def:nil]; return [v isKindOfClass:[NSString class]] && [v length] ? v : nil; }
- (NSInteger)layoutOf:(NSInteger)n { NSInteger l = [self intForKey:SPL_KEY_FAV(n, @"Layout") def:2]; return (l == 3 || l == 13 || l == 31) ? l : 2; }
- (NSInteger)boxCount:(NSInteger)layout { return layout == 2 ? 2 : 3; }
- (NSArray *)appsOf:(NSInteger)n
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *part in @[@"Left", @"Right", @"Third"]) [a addObject:[self stringForKey:SPL_KEY_FAV(n, part)] ?: @""];
    return a;
}
- (NSString *)nameOf:(NSInteger)n
{
    return [self stringForKey:SPL_KEY_FAV(n, @"Name")] ?: L([NSString stringWithFormat:@"SPLITSCREEN_FAV%ld_PLACEHOLDER", (long)n]);
}
- (NSArray<NSString *> *)urls
{
    return [L(@"SPLITSCREEN_SHORTCUTS_FOOTER") componentsSeparatedByString:@"\n"];
}

- (void)prefChanged:(NSString *)key
{
    if ([key isEqualToString:SPL_KEY_ENABLED]) [self.table reloadData];
}

#pragma mark - Bang

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SPCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s
{
    switch (s) {
        case SPMain: return 2;
        case SPFavs: return 3 + (self.editing ? 4 : 0);   // 3 yeu thich + khung sua (ten, bo cuc, app, xong) duoi dong dang sua
        case SPHelp: return 2 + (self.showGestures ? 1 : 0) + (self.showSiri ? (NSInteger)[self urls].count : 0);
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s
{
    switch (s) {
        case SPLayout: return L(@"SPLITSCREEN_LAYOUT_GROUP");
        case SPFavs: return L(@"SPLITSCREEN_FAV_GROUP");
        case SPPanel: return L(@"SPLITSCREEN_PANEL_GROUP");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    switch (s) {
        case SPLayout: return L(@"SPLITSCREEN_PINNED_FOOTER");
        case SPFavs: return L(@"SPLITSCREEN_FAV_FOOTER");
        case SPHelp: return L(@"SPLITSCREEN_CREDITS_FOOTER");
    }
    return nil;
}

// Dong trong the Yeu thich: 0..2 = yeu thich 1..3; khung sua chen ngay sau dong dang sua
- (void)favRow:(NSInteger)row fav:(NSInteger *)fav part:(NSInteger *)part
{
    NSInteger e = self.editing;
    if (!e || row < e) { *fav = row + 1; *part = -1; return; }
    if (row < e + 4) { *fav = e; *part = row - e; return; }
    *fav = row - 4 + 1; *part = -1;
}

// Dong trong the Tro giup: cu chi (gap) [+ chu], Siri (gap) [+ URL]
- (NSInteger)helpKind:(NSInteger)row index:(NSInteger *)idx
{
    if (row == 0) return 0;
    if (self.showGestures && row == 1) return 1;
    NSInteger siriRow = self.showGestures ? 2 : 1;
    if (row == siriRow) return 2;
    *idx = row - siriRow - 1;
    return 3;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip
{
    CGFloat w = tv.bounds.size.width - 40;
    if (ip.section == SPPreview) return MAX(118, round(w * 0.36));
    if (ip.section == SPMain) return 60;
    if (ip.section == SPLayout) return 60;
    if (ip.section == SPFavs) {
        NSInteger fav, part; [self favRow:ip.row fav:&fav part:&part];
        return part == 1 || part == 3 ? 48 : part == 2 ? 58 : 60;
    }
    if (ip.section == SPHelp) {
        NSInteger idx = 0, k = [self helpKind:ip.row index:&idx];
        if (k == 1) {
            CGSize s = [L(@"SPLITSCREEN_GUIDE_CAR_TEXT") boundingRectWithSize:CGSizeMake(w - 32, 1000) options:NSStringDrawingUsesLineFragmentOrigin
                                                                  attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12.5]} context:nil].size;
            return ceil(s.height) + 20;
        }
        if (k == 3) return 40;
    }
    return 52;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    CGFloat w = tv.bounds.size.width - 40;
    BOOL on = [self on];
    UITableViewCell *c = nil;
    switch (ip.section) {
    case SPPreview: {
        c = [self cellWithId:@"preview"];
        if (!self.preview || self.preview.superview != c.contentView) {
            [self.preview removeFromSuperview];
            self.preview = [OMCSplitPreview new];
            [c.contentView addSubview:self.preview];
        }
        self.preview.frame = CGRectMake(8, 8, w - 16, [self tableView:tv heightForRowAtIndexPath:ip] - 16);
        self.preview.on = on;
        self.preview.offText = L(@"SPLITSCREEN_OFF");
        self.preview.pinned = [self stringForKey:SPL_KEY_PINNED_APP];
        NSString *left = [self stringForKey:SPL_KEY_LAST_LEFT];
        if ([left isEqualToString:self.preview.pinned]) left = [self stringForKey:SPL_KEY_LAST_RIGHT];
        self.preview.left = left ?: @"com.apple.Music";
        if (!self.preview.pinned) self.preview.pinned = @"com.apple.Maps";
        [self.preview setNeedsDisplay];
        return c;
    }
    case SPMain: {
        BOOL main = ip.row == 0;
        c = [self cellWithId:main ? @"enable" : @"auto"];
        c.textLabel.text = L(main ? @"SPLITSCREEN_ENABLE" : @"SPLITSCREEN_AUTO_LAUNCH");
        c.detailTextLabel.text = L(main ? @"SPLITSCREEN_ENABLE_SUB" : @"SPLITSCREEN_AUTO_LAUNCH_SUB");
        c.imageView.image = OMCIcon(main ? @"rectangle.split.2x1.fill" : @"bolt.fill", OMCColorFromHex(main ? @"#8B7CFF" : @"#2BC79A"));
        [self setAccessory:main ? [self switchForKey:SPL_KEY_ENABLED def:YES] : [self switchForKey:SPL_KEY_AUTO_LAUNCH def:NO] onCell:c];
        break;
    }
    case SPLayout: {
        c = [self cellWithId:@"pinned"];
        NSString *pinned = [self stringForKey:SPL_KEY_PINNED_APP];
        c.textLabel.text = L(@"SPLITSCREEN_PINNED");
        c.detailTextLabel.text = pinned ? OMCSplitName(pinned) : L(@"SPLITSCREEN_PICKER_NONE");
        c.imageView.image = pinned ? OMCSplitIcon(pinned, 30) : OMCIcon(@"pin.fill", OMCColorFromHex(@"#FFB340"));
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        break;
    }
    case SPFavs: {
        NSInteger fav, part; [self favRow:ip.row fav:&fav part:&part];
        if (part < 0) {
            c = [self cellWithId:@"fav"];
            NSInteger layout = [self layoutOf:fav];
            NSArray *apps = [[self appsOf:fav] subarrayWithRange:NSMakeRange(0, [self boxCount:layout])];
            NSMutableArray *names = [NSMutableArray array];
            for (NSString *b in apps) if (b.length) [names addObject:OMCSplitName(b)];
            NSString *layoutName = L([NSString stringWithFormat:@"SPLITSCREEN_LAYOUT_%ld", (long)layout]);
            c.textLabel.text = [self nameOf:fav];
            c.detailTextLabel.text = names.count ? [NSString stringWithFormat:@"%@ · %@", layoutName, [names componentsJoinedByString:@", "]]
                                                 : [NSString stringWithFormat:@"%@ · %@", layoutName, L(@"SPLITSCREEN_APP_NOT_SET")];
            c.imageView.image = OMCSplitLayoutPicture(layout, apps, CGSizeMake(54, 32));
            UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.editing == fav ? @"chevron.down" : @"chevron.right"]];
            chev.tintColor = [UIColor tertiaryLabelColor];
            c.accessoryView = chev;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else c = [self editorCell:part fav:fav width:w];
        break;
    }
    case SPPanel: {
        c = [self cellWithId:@"panel"];
        c.textLabel.text = L(@"SPLITSCREEN_PANEL_SHOW");
        c.imageView.image = OMCIcon(@"list.bullet.rectangle.fill", OMCColorFromHex(@"#FF7FA8"));
        UIStackView *chips = [[UIStackView alloc] initWithArrangedSubviews:@[[self chip:L(@"SPLITSCREEN_SHOW_RECENT") key:SPL_KEY_SHOW_RECENT],
                                                                             [self chip:L(@"SPLITSCREEN_SHOW_FAVORITES") key:SPL_KEY_SHOW_FAVORITES]]];
        chips.spacing = 6;
        CGSize cs = [chips systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        chips.frame = CGRectMake(0, 0, cs.width, 30);
        [self setAccessory:chips onCell:c];
        break;
    }
    case SPHelp:
    default: {
        NSInteger idx = 0, k = [self helpKind:ip.row index:&idx];
        if (k == 0 || k == 2) {
            BOOL g = k == 0, open = g ? self.showGestures : self.showSiri;
            c = [self cellWithId:@"fold"];
            c.textLabel.text = L(g ? @"SPLITSCREEN_GESTURES" : @"SPLITSCREEN_SIRI");
            c.imageView.image = OMCIcon(g ? @"hand.tap.fill" : @"command", OMCColorFromHex(g ? @"#5AB8FF" : @"#4A4F80"));
            UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:open ? @"chevron.down" : @"chevron.right"]];
            chev.tintColor = [UIColor tertiaryLabelColor];
            c.accessoryView = chev;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (k == 1) {
            c = [self cellWithId:@"gestures"];
            UIView *box = [self boxInCell:c];
            UILabel *l = (UILabel *)[box viewWithTag:0x47];
            if (!l) { l = [UILabel new]; l.tag = 0x47; l.numberOfLines = 0; l.font = [UIFont systemFontOfSize:12.5]; l.textColor = [UIColor secondaryLabelColor]; [box addSubview:l]; }
            l.text = L(@"SPLITSCREEN_GUIDE_CAR_TEXT");
            l.frame = CGRectMake(16, 10, w - 32, [self tableView:tv heightForRowAtIndexPath:ip] - 20);
        } else {
            c = [self cellWithId:@"url"];
            UIView *box = [self boxInCell:c];
            for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
            NSString *url = [self urls][idx];
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, 6, w - 32 - 60, 28)];
            l.text = url;
            l.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
            l.textColor = [UIColor secondaryLabelColor];
            l.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [box addSubview:l];
            UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
            [copy setTitle:L(@"SPLITSCREEN_COPY") forState:UIControlStateNormal];
            copy.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            copy.frame = CGRectMake(w - 16 - 56, 6, 56, 28);
            copy.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
            objc_setAssociatedObject(copy, &kOMCSplitIndex, url, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [copy addTarget:self action:@selector(copyURL:) forControlEvents:UIControlEventTouchUpInside];
            [box addSubview:copy];
        }
        break;
    }
    }
    BOOL dim = !on && ip.section > SPMain && ip.section != SPHelp;
    c.contentView.alpha = dim ? 0.4 : 1;
    c.accessoryView.alpha = dim ? 0.4 : 1;
    c.userInteractionEnabled = !dim;
    return c;
}

// Nut bat / tat nho (Gan day / Yeu thich): nen gradient khi bat
- (UIButton *)chip:(NSString *)title key:(NSString *)key
{
    BOOL on = [[self prefForKey:key def:@YES] boolValue];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    [b setTitleColor:on ? [UIColor whiteColor] : [UIColor secondaryLabelColor] forState:UIControlStateNormal];
    b.backgroundColor = on ? OMCColorFromHex(@"#8B7CFF") : [UIColor colorWithWhite:0.5 alpha:0.14];
    b.layer.cornerRadius = 10;
    CGFloat tw = ceil([title sizeWithAttributes:@{NSFontAttributeName: b.titleLabel.font}].width);
    [b.widthAnchor constraintEqualToConstant:tw + 20].active = YES;
    [b.heightAnchor constraintEqualToConstant:30].active = YES;
    objc_setAssociatedObject(b, &kOMCSplitIndex, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [b addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)chipTapped:(UIButton *)b
{
    NSString *key = objc_getAssociatedObject(b, &kOMCSplitIndex);
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self storeValue:@(![[self prefForKey:key def:@YES] boolValue]) forKey:key];
    [self reloadSection:SPPanel];
}

#pragma mark - Khung sua yeu thich

- (UITableViewCell *)editorCell:(NSInteger)part fav:(NSInteger)n width:(CGFloat)w
{
    UITableViewCell *c = [self cellWithId:[NSString stringWithFormat:@"edit%ld", (long)part]];
    UIView *box = [self boxInCell:c];
    for (UIView *v in [box.subviews copy]) [v removeFromSuperview];
    c.backgroundColor = [OMCAccentColor() colorWithAlphaComponent:0.06];
    switch (part) {
    case 0: {   // ten
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, 80, 60)];
        l.text = L(@"SPLITSCREEN_PAIR_NAME");
        [box addSubview:l];
        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(96, 14, w - 96 - 14, 32)];
        tf.text = [self stringForKey:SPL_KEY_FAV(n, @"Name")];
        tf.placeholder = L([NSString stringWithFormat:@"SPLITSCREEN_FAV%ld_PLACEHOLDER", (long)n]);
        tf.textAlignment = NSTextAlignmentRight;
        tf.borderStyle = UITextBorderStyleNone;
        tf.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
        tf.layer.cornerRadius = 9;
        tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)]; tf.leftViewMode = UITextFieldViewModeAlways;
        tf.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)]; tf.rightViewMode = UITextFieldViewModeAlways;
        tf.returnKeyType = UIReturnKeyDone;
        tf.delegate = self;
        tf.tag = n;
        [tf addTarget:self action:@selector(nameEdited:) forControlEvents:UIControlEventEditingChanged];
        [box addSubview:tf];
        break;
    }
    case 1: {   // bo cuc
        NSArray *values = @[@2, @3, @13, @31];
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[L(@"SPLITSCREEN_LAYOUT_2"), L(@"SPLITSCREEN_LAYOUT_3"), L(@"SPLITSCREEN_LAYOUT_13"), L(@"SPLITSCREEN_LAYOUT_31")]];
        seg.selectedSegmentIndex = [values indexOfObject:@([self layoutOf:n])];
        seg.frame = CGRectMake(12, 8, w - 24, 32);
        seg.tag = n;
        [seg addTarget:self action:@selector(layoutPicked:) forControlEvents:UIControlEventValueChanged];
        [box addSubview:seg];
        break;
    }
    case 2: {   // app tung o: cham de chon
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, 6, 140, 46)];
        l.numberOfLines = 2;
        NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:L(@"SPLITSCREEN_APPS_GROUP") attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15]}];
        [t appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:L(@"SPLITSCREEN_FAV_APPS_HINT")]
                                                                  attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11], NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}]];
        l.attributedText = t;
        [box addSubview:l];
        NSInteger count = [self boxCount:[self layoutOf:n]];
        NSArray *apps = [self appsOf:n], *parts = @[@"Left", @"Right", @"Third"];
        CGFloat x = w - 14 - count * 40 + 6;
        for (NSInteger i = 0; i < count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(x + i * 40, 12, 34, 34);
            UIImage *icon = OMCSplitIcon(apps[i], 34);
            if (icon) [b setImage:icon forState:UIControlStateNormal];
            else {
                b.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.2];
                b.layer.cornerRadius = 8;
                [b setTitle:@"+" forState:UIControlStateNormal];
                [b setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
            }
            objc_setAssociatedObject(b, &kOMCSplitIndex, @[SPL_KEY_FAV(n, parts[i]), L([NSString stringWithFormat:@"SPLITSCREEN_BOX_%ld", (long)i + 1])],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [b addTarget:self action:@selector(boxTapped:) forControlEvents:UIControlEventTouchUpInside];
            [box addSubview:b];
        }
        break;
    }
    default: {   // xong
        UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
        [done setTitle:L(@"SPLITSCREEN_FAV_DONE") forState:UIControlStateNormal];
        done.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        done.frame = CGRectMake(16, 4, w - 32, 40);
        done.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [done addTarget:self action:@selector(doneEditing) forControlEvents:UIControlEventTouchUpInside];
        [box addSubview:done];
        break;
    }
    }
    return c;
}

- (void)nameEdited:(UITextField *)tf
{
    NSString *t = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [self storeValue:t.length ? t : nil forKey:SPL_KEY_FAV(tf.tag, @"Name")];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self reloadSection:SPFavs]; return YES; }

- (void)layoutPicked:(UISegmentedControl *)seg
{
    NSArray *values = @[@2, @3, @13, @31];
    [self storeValue:values[seg.selectedSegmentIndex] forKey:SPL_KEY_FAV(seg.tag, @"Layout")];
    [self reloadSection:SPFavs];
}

// Chon app cho 1 o: bang chon app cua Chia man hinh (app CarPlay + app iPhone), ghi thang vao key cua o
- (void)pickAppForKey:(NSString *)key title:(NSString *)title
{
    Class picker = NSClassFromString(@"OMCSplitScreenAppPickerController");
    if (!picker) return;
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title target:self set:NULL get:NULL detail:picker cell:PSLinkCell edit:Nil];
    [spec setProperty:key forKey:@"key"];
    PSViewController *vc = [[picker alloc] init];
    [vc setSpecifier:spec];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)boxTapped:(UIButton *)b
{
    NSArray *info = objc_getAssociatedObject(b, &kOMCSplitIndex);
    [self pickAppForKey:info[0] title:info[1]];
}

- (void)doneEditing
{
    [self.view endEditing:YES];
    self.editing = 0;
    [self reloadSection:SPFavs];
}

- (void)copyURL:(UIButton *)b
{
    [UIPasteboard generalPasteboard].string = objc_getAssociatedObject(b, &kOMCSplitIndex);
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [self toast:L(@"SPLITSCREEN_COPIED")];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SPLayout) { [self pickAppForKey:SPL_KEY_PINNED_APP title:L(@"SPLITSCREEN_PINNED")]; return; }
    if (ip.section == SPFavs) {
        NSInteger fav, part; [self favRow:ip.row fav:&fav part:&part];
        if (part >= 0) return;
        [self.view endEditing:YES];
        self.editing = self.editing == fav ? 0 : fav;
        [self reloadSection:SPFavs];
        return;
    }
    if (ip.section == SPHelp) {
        NSInteger idx = 0, k = [self helpKind:ip.row index:&idx];
        if (k == 0) self.showGestures = !self.showGestures;
        else if (k == 2) self.showSiri = !self.showSiri;
        else return;
        [self reloadSection:SPHelp];
    }
}

@end
