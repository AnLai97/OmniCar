#import "OMCWhatsNewController.h"
#import "OMCTheme.h"

#ifndef TWEAK_VERSION
#define TWEAK_VERSION "dev"
#endif

#define kWhatsNewSeenKey CFSTR("whatsNewSeen")

@interface OMCWhatsNewController ()
@property (nonatomic, copy) NSString *version;          // entry shown
@property (nonatomic, copy) NSArray<NSDictionary *> *items;
@end

@implementation OMCWhatsNewController

#pragma mark - Content

static NSDictionary *OMCWhatsNewPlist(void) {
	NSBundle *bundle = [NSBundle bundleForClass:[OMCWhatsNewController class]];
	NSString *path = [bundle pathForResource:@"WhatsNew" ofType:@"plist"];
	NSDictionary *plist = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
	return [plist isKindOfClass:[NSDictionary class]] ? plist : @{};
}

// The installed version's entry, else (opened from the Support row on a version with no entry) the newest one.
static NSString *OMCWhatsNewVersion(NSDictionary *plist, BOOL exactOnly) {
	if ([plist[@TWEAK_VERSION] isKindOfClass:[NSArray class]]) return @TWEAK_VERSION;
	if (exactOnly) return nil;
	NSString *newest = nil;
	for (NSString *v in plist)
		if ([plist[v] isKindOfClass:[NSArray class]] && (!newest || [v compare:newest options:NSNumericSearch] == NSOrderedDescending)) newest = v;
	return newest;
}

+ (BOOL)shouldShow {
	CFPreferencesAppSynchronize(kPrefsDomain);
	NSString *seen = CFBridgingRelease(CFPreferencesCopyAppValue(kWhatsNewSeenKey, kPrefsDomain));
	if ([seen isKindOfClass:[NSString class]] && [seen isEqualToString:@TWEAK_VERSION]) return NO;
	return OMCWhatsNewVersion(OMCWhatsNewPlist(), YES) != nil;
}

+ (void)markSeen {
	CFPreferencesSetAppValue(kWhatsNewSeenKey, (__bridge CFStringRef)@TWEAK_VERSION, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
}

+ (UINavigationController *)whatsNewNavigationController {
	[self markSeen];
	OMCWhatsNewController *page = [OMCWhatsNewController new];
	NSDictionary *plist = OMCWhatsNewPlist();
	page.version = OMCWhatsNewVersion(plist, NO) ?: @TWEAK_VERSION;
	NSMutableArray *items = [NSMutableArray array];
	for (id item in plist[page.version]) if ([item isKindOfClass:[NSDictionary class]]) [items addObject:item];
	page.items = items;
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	nav.navigationBar.tintColor = OMCAccentColor();
	return nav;
}

#pragma mark - View

- (void)viewDidLoad {
	[super viewDidLoad];
	OMCLoadStrings();
	self.view.backgroundColor = OMCBackgroundColor();
	self.view.tintColor = OMCAccentColor();

	UIScrollView *scroll = [UIScrollView new];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	scroll.showsVerticalScrollIndicator = NO;
	[self.view addSubview:scroll];

	UIStackView *stack = [UIStackView new];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentFill;
	stack.spacing = 18;
	[scroll addSubview:stack];

	UIView *header = [self tileWithSymbol:@"sparkles" side:72 pointSize:32 radius:20];
	UIView *headerRow = [UIView new];
	[headerRow addSubview:header];
	[NSLayoutConstraint activateConstraints:@[
		[header.topAnchor constraintEqualToAnchor:headerRow.topAnchor],
		[header.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor],
		[header.centerXAnchor constraintEqualToAnchor:headerRow.centerXAnchor],
	]];
	[stack addArrangedSubview:headerRow];

	UIFont *titleFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle1] scaledFontForFont:[UIFont systemFontOfSize:26 weight:UIFontWeightBold]];
	UILabel *title = [self labelWithFont:titleFont color:[UIColor labelColor]];
	title.textAlignment = NSTextAlignmentCenter;
	title.text = [NSString stringWithFormat:L(@"WN_TITLE"), self.version];
	[stack addArrangedSubview:title];
	[stack setCustomSpacing:28 afterView:title];

	for (NSDictionary *item in self.items) [stack addArrangedSubview:[self rowForItem:item]];

	UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
	config.title = L(@"WN_CONTINUE");
	config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	config.baseBackgroundColor = OMCAccentColor();
	config.baseForegroundColor = OMCCardColor();
	config.contentInsets = NSDirectionalEdgeInsetsMake(12, 24, 12, 24);
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.configuration = config;
	[button addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:button];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
		[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[scroll.bottomAnchor constraintEqualToAnchor:button.topAnchor constant:-12],

		[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:36],
		[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
		[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],
		[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],
		[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48],

		[button.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
		[button.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
		[button.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
	]];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
	UILabel *label = [UILabel new];
	label.font = font;
	label.adjustsFontForContentSizeCategory = YES;
	label.textColor = color;
	label.numberOfLines = 0;
	return label;
}

// Rounded accent tile with the symbol in the card color (same look as the guide's page tiles).
- (UIView *)tileWithSymbol:(NSString *)symbol side:(CGFloat)side pointSize:(CGFloat)pointSize radius:(CGFloat)radius {
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
	// Symbols newer than iOS 15 (steeringwheel ...) fall back to a sparkle.
	UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config] ?: [UIImage systemImageNamed:@"sparkles" withConfiguration:config];
	UIImageView *glyph = [[UIImageView alloc] initWithImage:image];
	glyph.translatesAutoresizingMaskIntoConstraints = NO;
	glyph.tintColor = OMCCardColor();
	glyph.contentMode = UIViewContentModeCenter;

	UIView *tile = [UIView new];
	tile.translatesAutoresizingMaskIntoConstraints = NO;
	tile.backgroundColor = OMCAccentColor();
	tile.layer.cornerRadius = radius;
	tile.layer.cornerCurve = kCACornerCurveContinuous;
	[tile addSubview:glyph];
	[NSLayoutConstraint activateConstraints:@[
		[tile.widthAnchor constraintEqualToConstant:side],
		[tile.heightAnchor constraintEqualToConstant:side],
		[glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
		[glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
	]];
	return tile;
}

// One change: tile on the leading side, bold title over the secondary text.
- (UIView *)rowForItem:(NSDictionary *)item {
	NSString *symbol = [item[@"symbol"] isKindOfClass:[NSString class]] ? item[@"symbol"] : @"sparkles";
	UIView *tile = [self tileWithSymbol:symbol side:40 pointSize:18 radius:11];

	UILabel *title = [self labelWithFont:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] color:[UIColor labelColor]];
	title.text = L(item[@"titleKey"] ?: @"");
	UILabel *text = [self labelWithFont:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline] color:[UIColor secondaryLabelColor]];
	text.text = L(item[@"textKey"] ?: @"");

	UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[title, text]];
	column.axis = UILayoutConstraintAxisVertical;
	column.spacing = 2;

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[tile, column]];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentTop;
	row.spacing = 14;
	return row;
}

#pragma mark - Actions

- (void)close {
	UIViewController *sheet = self.navigationController ?: self;
	[sheet dismissViewControllerAnimated:YES completion:nil];
}

@end
