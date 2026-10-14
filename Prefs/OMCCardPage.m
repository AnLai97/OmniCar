#import "OMCCardPage.h"
#import "OMCTheme.h"
#import <objc/runtime.h>
#import <notify.h>

static char kOMCCardKey;

@interface OMCCardPage ()
@property (nonatomic, strong, readwrite) UITableView *table;
@end

@implementation OMCCardPage

- (void)loadView
{
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.view = _table;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    OMCLoadStrings();
    self.view.tintColor = OMCAccentColor();
    OMCStyleTable(_table);
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    CFPreferencesAppSynchronize(kPrefsDomain);   // gia tri tweak / trang con vua ghi
    if (self.specifier.name.length) self.title = self.specifier.name;
    [_table reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous
{
    [super traitCollectionDidChange:previous];
    if (self.traitCollection.userInterfaceStyle != previous.userInterfaceStyle) OMCStyleTable(_table);
}

#pragma mark - Prefs

- (id)prefForKey:(NSString *)key def:(id)def
{
    id v = key ? CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain)) : nil;
    return v ?: def;
}

- (NSInteger)intForKey:(NSString *)key def:(NSInteger)def
{
    id v = [self prefForKey:key def:nil];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : def;
}

- (void)storeValue:(id)value forKey:(NSString *)key
{
    if (!key) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
    CFPreferencesAppSynchronize(kPrefsDomain);
    notify_post("com.anlai.omnicar/prefschanged");
}

- (void)prefChanged:(NSString *)key {}
- (void)prefChanging:(NSString *)key {}

#pragma mark - Cells and controls

- (UITableViewCell *)cellWithId:(NSString *)rid
{
    UITableViewCell *c = [_table dequeueReusableCellWithIdentifier:rid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
    OMCStyleCell(c);
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.imageView.image = nil;
    c.textLabel.text = nil; c.detailTextLabel.text = nil;
    c.textLabel.textColor = [UIColor labelColor];
    c.textLabel.alpha = 1;
    c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    c.detailTextLabel.numberOfLines = 2;
    return c;
}

- (UIView *)boxInCell:(UITableViewCell *)c
{
    UIView *box = [c.contentView viewWithTag:0x4258];
    if (!box) {
        box = [[UIView alloc] initWithFrame:c.contentView.bounds];
        box.tag = 0x4258;
        box.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [c.contentView addSubview:box];
    }
    return box;
}

- (void)setAccessory:(UIView *)v onCell:(UITableViewCell *)c { c.accessoryView = v; }

- (UISwitch *)switchForKey:(NSString *)key def:(BOOL)def
{
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = OMCSwitchColor();
    sw.on = [[self prefForKey:key def:@(def)] boolValue];
    objc_setAssociatedObject(sw, &kOMCCardKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(omcSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (void)omcSwitchChanged:(UISwitch *)sw
{
    NSString *key = objc_getAssociatedObject(sw, &kOMCCardKey);
    [self storeValue:@(sw.on) forKey:key];
    [self prefChanged:key];
}

- (UISegmentedControl *)segmentForKey:(NSString *)key titles:(NSArray<NSString *> *)titles def:(NSInteger)def
{
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:titles];
    NSInteger v = [self intForKey:key def:def];
    seg.selectedSegmentIndex = (v >= 0 && v < (NSInteger)titles.count) ? v : def;
    objc_setAssociatedObject(seg, &kOMCCardKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [seg addTarget:self action:@selector(omcSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    return seg;
}

- (void)omcSegmentChanged:(UISegmentedControl *)seg
{
    NSString *key = objc_getAssociatedObject(seg, &kOMCCardKey);
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self storeValue:@(seg.selectedSegmentIndex) forKey:key];
    [self prefChanged:key];
}

// Thanh keo + so ben phai (format nhan 1 so nguyen, vd "%ld%%"); ghi prefs khi tha tay, -prefChanged: ca luc keo
- (UIView *)sliderForKey:(NSString *)key min:(NSInteger)mn max:(NSInteger)mx def:(NSInteger)def format:(NSString *)format width:(CGFloat)w
{
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 32)];
    UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(w - 62, 0, 62, 32)];
    val.textAlignment = NSTextAlignmentRight;
    val.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    val.textColor = [UIColor secondaryLabelColor];
    val.adjustsFontSizeToFitWidth = YES;
    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, w - 68, 32)];
    sl.minimumValue = mn; sl.maximumValue = mx;
    sl.value = MIN(mx, MAX(mn, [self intForKey:key def:def]));
    sl.minimumTrackTintColor = OMCAccentColor();
    val.text = [NSString stringWithFormat:format, (long)lround(sl.value)];
    objc_setAssociatedObject(sl, &kOMCCardKey, @[key, format, val], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sl addTarget:self action:@selector(omcSliderMoved:) forControlEvents:UIControlEventValueChanged];
    [sl addTarget:self action:@selector(omcSliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [box addSubview:sl];
    [box addSubview:val];
    return box;
}

- (void)omcSliderMoved:(UISlider *)sl
{
    NSArray *info = objc_getAssociatedObject(sl, &kOMCCardKey);
    ((UILabel *)info[2]).text = [NSString stringWithFormat:info[1], (long)lround(sl.value)];
    CFPreferencesSetAppValue((__bridge CFStringRef)info[0], (__bridge CFPropertyListRef)@(lround(sl.value)), kPrefsDomain);
    [self prefChanging:info[0]];
}

- (void)omcSliderDone:(UISlider *)sl
{
    NSArray *info = objc_getAssociatedObject(sl, &kOMCCardKey);
    [self storeValue:@(lround(sl.value)) forKey:info[0]];
    [self prefChanged:info[0]];
}

- (void)toast:(NSString *)text
{
    UIView *host = self.navigationController.view ?: self.view;
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    l.textColor = [UIColor whiteColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 2;
    l.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    l.layer.cornerRadius = 16;
    l.clipsToBounds = YES;
    CGSize fit = [l sizeThatFits:CGSizeMake(host.bounds.size.width - 64, 60)];
    l.frame = CGRectMake((host.bounds.size.width - fit.width - 28) / 2, host.bounds.size.height - host.safeAreaInsets.bottom - fit.height - 40,
                         fit.width + 28, fit.height + 14);
    [host addSubview:l];
    [UIView animateWithDuration:0.3 delay:1.6 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) { [l removeFromSuperview]; }];
}

- (void)reloadSection:(NSInteger)section
{
    if (section < [_table numberOfSections]) [_table reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Table (lop con ghi de)

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return 0; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip { return [self cellWithId:@"empty"]; }
- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, YES); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, NO); }

@end
