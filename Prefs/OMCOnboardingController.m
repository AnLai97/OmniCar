// First-run guide (ROADMAP-DEV.md: Hướng dẫn lần đầu). A horizontal paging scroll view with page dots, Skip and
// Next / Done, presented as a page sheet by OMCRootListController the first time Settings > OmniCar opens:
//   1. Welcome + choose the iPhone apps for the car screen (pushes OMCAppBridgeAppsController in the sheet)
//   2. How Split Screen works in the car (OmniCar button on the dock, long-press an app icon)
//   3. Speed Bubble switch (speedBubbleEnabled, needs Vietmap Live or GOFA)
//   4. Tips: the layout panel, and where Diagnostics / Send log are
// Strings: <lang>.lproj/Onboarding.strings (ONB_*). The pref "onboardingDone" keeps it from showing again.
#import "OMCOnboardingController.h"
#import "OMCTheme.h"
#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

#define kOnboardingDoneKey CFSTR("onboardingDone")
// SB_KEY_ENABLED of Features/SpeedBubble/SpeedBubble.h (default YES, like FeatureSpeedBubble.plist).
#define kSpeedBubbleKey    CFSTR("speedBubbleEnabled")

@interface PSViewController (OMCOnboarding)
- (void)setSpecifier:(PSSpecifier *)specifier;
@end

static id OMCOnbPref(CFStringRef key) {
	return CFBridgingRelease(CFPreferencesCopyAppValue(key, kPrefsDomain));
}

@interface OMCOnboardingController ()
@property (nonatomic, strong) UIScrollView *pager;
@property (nonatomic, strong) UIPageControl *dots;
@property (nonatomic, strong) UIButton *skipButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, assign) NSInteger page;
@property (nonatomic, assign) NSInteger pageCount;
@property (nonatomic, assign) CGFloat laidOutWidth;   // pager width the offset was last fitted to
@property (nonatomic, assign) BOOL closed;
@property (nonatomic, copy) void (^completion)(void);
@end

@implementation OMCOnboardingController

#pragma mark - Entry points

+ (BOOL)shouldShow {
	CFPreferencesAppSynchronize(kPrefsDomain);
	return ![OMCOnbPref(kOnboardingDoneKey) boolValue];
}

+ (UINavigationController *)guideNavigationControllerWithCompletion:(void (^)(void))completion {
	OMCOnboardingController *guide = [OMCOnboardingController new];
	guide.completion = completion;
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:guide];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	nav.navigationBar.tintColor = OMCAccentColor();
	// Swiping the sheet down counts as skipping the guide.
	nav.presentationController.delegate = guide;
	return nav;
}

#pragma mark - View

- (void)viewDidLoad {
	[super viewDidLoad];
	OMCLoadStrings();
	self.view.backgroundColor = OMCBackgroundColor();
	self.view.tintColor = OMCAccentColor();

	NSArray<UIView *> *pages = @[[self welcomePage], [self splitPage], [self speedPage], [self tipsPage]];
	self.pageCount = (NSInteger)pages.count;

	_pager = [UIScrollView new];
	_pager.translatesAutoresizingMaskIntoConstraints = NO;
	_pager.pagingEnabled = YES;
	_pager.showsHorizontalScrollIndicator = NO;
	_pager.showsVerticalScrollIndicator = NO;
	_pager.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	_pager.delegate = self;
	[self.view addSubview:_pager];

	UIStackView *strip = [[UIStackView alloc] initWithArrangedSubviews:pages];
	strip.translatesAutoresizingMaskIntoConstraints = NO;
	strip.axis = UILayoutConstraintAxisHorizontal;
	strip.distribution = UIStackViewDistributionFillEqually;
	[_pager addSubview:strip];
	for (UIView *p in pages) [p.widthAnchor constraintEqualToAnchor:_pager.frameLayoutGuide.widthAnchor].active = YES;

	_dots = [UIPageControl new];
	_dots.translatesAutoresizingMaskIntoConstraints = NO;
	_dots.numberOfPages = self.pageCount;
	_dots.currentPageIndicatorTintColor = OMCAccentColor();
	_dots.pageIndicatorTintColor = [UIColor tertiaryLabelColor];
	[_dots addTarget:self action:@selector(dotsChanged:) forControlEvents:UIControlEventValueChanged];
	[self.view addSubview:_dots];

	UIButtonConfiguration *skip = [UIButtonConfiguration plainButtonConfiguration];
	skip.title = L(@"ONB_SKIP");
	skip.baseForegroundColor = [UIColor secondaryLabelColor];
	_skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_skipButton.translatesAutoresizingMaskIntoConstraints = NO;
	_skipButton.configuration = skip;
	[_skipButton addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_skipButton];

	UIButtonConfiguration *next = [UIButtonConfiguration filledButtonConfiguration];
	next.title = L(@"ONB_NEXT");
	next.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	next.baseBackgroundColor = OMCAccentColor();
	next.baseForegroundColor = OMCCardColor();
	next.contentInsets = NSDirectionalEdgeInsetsMake(10, 24, 10, 24);
	_nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_nextButton.translatesAutoresizingMaskIntoConstraints = NO;
	_nextButton.configuration = next;
	[_nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_nextButton];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[_pager.topAnchor constraintEqualToAnchor:safe.topAnchor],
		[_pager.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_pager.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_pager.bottomAnchor constraintEqualToAnchor:_nextButton.topAnchor constant:-12],

		[strip.topAnchor constraintEqualToAnchor:_pager.contentLayoutGuide.topAnchor],
		[strip.bottomAnchor constraintEqualToAnchor:_pager.contentLayoutGuide.bottomAnchor],
		[strip.leadingAnchor constraintEqualToAnchor:_pager.contentLayoutGuide.leadingAnchor],
		[strip.trailingAnchor constraintEqualToAnchor:_pager.contentLayoutGuide.trailingAnchor],
		[strip.heightAnchor constraintEqualToAnchor:_pager.frameLayoutGuide.heightAnchor],

		[_nextButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
		[_nextButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
		[_skipButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
		[_skipButton.centerYAnchor constraintEqualToAnchor:_nextButton.centerYAnchor],
		[_dots.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_dots.centerYAnchor constraintEqualToAnchor:_nextButton.centerYAnchor],
	]];

	[self updateControls];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	// The App Bridge chooser pushed from page 1 needs the bar (back button, search field).
	[self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	// Keep the current page in place when the sheet changes width (rotation, iPad split view).
	CGFloat width = _pager.bounds.size.width;
	if (width > 0 && width != self.laidOutWidth) {
		self.laidOutWidth = width;
		_pager.contentOffset = CGPointMake(self.page * width, 0);
	}
}

#pragma mark - Pages

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color alignment:(NSTextAlignment)alignment {
	UILabel *label = [UILabel new];
	label.font = font;
	label.adjustsFontForContentSizeCategory = YES;
	label.textColor = color;
	label.textAlignment = alignment;
	label.numberOfLines = 0;
	return label;
}

// Bullet lists ("• " at the start of each line) get a hanging indent; plain text is centered.
- (UILabel *)bodyLabelWithText:(NSString *)text {
	UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	BOOL bullets = [text hasPrefix:@"• "];
	UILabel *label = [self labelWithFont:font color:[UIColor secondaryLabelColor] alignment:bullets ? NSTextAlignmentNatural : NSTextAlignmentCenter];
	NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
	style.alignment = label.textAlignment;
	style.lineSpacing = 3;
	style.paragraphSpacing = bullets ? 10 : 0;
	if (bullets) style.headIndent = [@"• " sizeWithAttributes:@{NSFontAttributeName: font}].width;
	label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
		NSFontAttributeName: font,
		NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
		NSParagraphStyleAttributeName: style,
	}];
	return label;
}

// One page: symbol tile, title, body, an optional control (button / switch card) and a small note,
// in a vertical scroll view so large text sizes still fit.
- (UIView *)pageWithSymbol:(NSString *)symbol title:(NSString *)title body:(NSString *)body extra:(UIView *)extra note:(NSString *)note {
	UIScrollView *page = [UIScrollView new];
	page.showsVerticalScrollIndicator = NO;
	page.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

	UIStackView *stack = [UIStackView new];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentFill;
	stack.spacing = 14;
	[page addSubview:stack];

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightSemibold];
	UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config] ?: [UIImage systemImageNamed:@"car.fill" withConfiguration:config];
	UIImageView *glyph = [[UIImageView alloc] initWithImage:image];
	glyph.translatesAutoresizingMaskIntoConstraints = NO;
	glyph.tintColor = OMCCardColor();
	glyph.contentMode = UIViewContentModeCenter;

	UIView *tile = [UIView new];
	tile.translatesAutoresizingMaskIntoConstraints = NO;
	tile.backgroundColor = OMCAccentColor();
	tile.layer.cornerRadius = 24;
	tile.layer.cornerCurve = kCACornerCurveContinuous;
	[tile addSubview:glyph];

	UIView *tileRow = [UIView new];
	[tileRow addSubview:tile];
	[NSLayoutConstraint activateConstraints:@[
		[tile.widthAnchor constraintEqualToConstant:88],
		[tile.heightAnchor constraintEqualToConstant:88],
		[tile.topAnchor constraintEqualToAnchor:tileRow.topAnchor],
		[tile.bottomAnchor constraintEqualToAnchor:tileRow.bottomAnchor],
		[tile.centerXAnchor constraintEqualToAnchor:tileRow.centerXAnchor],
		[glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
		[glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
	]];
	[stack addArrangedSubview:tileRow];
	[stack setCustomSpacing:24 afterView:tileRow];

	UIFont *titleFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle1] scaledFontForFont:[UIFont systemFontOfSize:26 weight:UIFontWeightBold]];
	UILabel *titleLabel = [self labelWithFont:titleFont color:[UIColor labelColor] alignment:NSTextAlignmentCenter];
	titleLabel.text = title;
	[stack addArrangedSubview:titleLabel];

	UILabel *bodyLabel = [self bodyLabelWithText:body];
	[stack addArrangedSubview:bodyLabel];

	if (extra) {
		[stack setCustomSpacing:24 afterView:bodyLabel];
		[stack addArrangedSubview:extra];
	}
	if (note.length) {
		UILabel *noteLabel = [self labelWithFont:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote] color:[UIColor tertiaryLabelColor] alignment:NSTextAlignmentCenter];
		noteLabel.text = note;
		[stack addArrangedSubview:noteLabel];
	}

	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:page.contentLayoutGuide.topAnchor constant:40],
		[stack.bottomAnchor constraintEqualToAnchor:page.contentLayoutGuide.bottomAnchor constant:-20],
		[stack.leadingAnchor constraintEqualToAnchor:page.contentLayoutGuide.leadingAnchor constant:28],
		[stack.trailingAnchor constraintEqualToAnchor:page.contentLayoutGuide.trailingAnchor constant:-28],
		[stack.widthAnchor constraintEqualToAnchor:page.frameLayoutGuide.widthAnchor constant:-56],
	]];
	return page;
}

- (UIView *)welcomePage {
	UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
	config.title = L(@"ONB_P1_BUTTON");
	config.image = [UIImage systemImageNamed:@"square.grid.2x2.fill"];
	config.imagePadding = 8;
	config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
	config.baseBackgroundColor = OMCAccentColor();
	config.baseForegroundColor = OMCCardColor();
	config.contentInsets = NSDirectionalEdgeInsetsMake(14, 20, 14, 20);
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.configuration = config;
	[button addTarget:self action:@selector(openApps) forControlEvents:UIControlEventTouchUpInside];
	return [self pageWithSymbol:@"car.fill" title:L(@"ONB_P1_TITLE") body:L(@"ONB_P1_BODY") extra:button note:L(@"ONB_P1_NOTE")];
}

- (UIView *)splitPage {
	return [self pageWithSymbol:@"rectangle.split.2x1.fill" title:L(@"ONB_P2_TITLE") body:L(@"ONB_P2_BODY") extra:nil note:L(@"ONB_P2_NOTE")];
}

- (UIView *)speedPage {
	UIImageView *icon = [[UIImageView alloc] initWithImage:OMCIcon(@"speedometer", nil)];
	[icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	UILabel *label = [self labelWithFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody] color:[UIColor labelColor] alignment:NSTextAlignmentNatural];
	label.text = L(@"ONB_P3_SWITCH");

	id value = OMCOnbPref(kSpeedBubbleKey);
	UISwitch *toggle = [UISwitch new];
	toggle.onTintColor = OMCAccentColor();
	toggle.on = value ? [value boolValue] : YES;
	[toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[toggle addTarget:self action:@selector(speedBubbleToggled:) forControlEvents:UIControlEventValueChanged];

	UIStackView *card = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label, toggle]];
	card.axis = UILayoutConstraintAxisHorizontal;
	card.alignment = UIStackViewAlignmentCenter;
	card.spacing = 12;
	card.layoutMarginsRelativeArrangement = YES;
	card.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(12, 16, 12, 16);
	card.backgroundColor = OMCCardColor();
	card.layer.cornerRadius = 14;
	card.layer.cornerCurve = kCACornerCurveContinuous;
	return [self pageWithSymbol:@"speedometer" title:L(@"ONB_P3_TITLE") body:L(@"ONB_P3_BODY") extra:card note:L(@"ONB_P3_NOTE")];
}

- (UIView *)tipsPage {
	return [self pageWithSymbol:@"lifepreserver" title:L(@"ONB_P4_TITLE") body:L(@"ONB_P4_BODY") extra:nil note:L(@"ONB_P4_NOTE")];
}

#pragma mark - Paging

- (void)updateControls {
	BOOL last = self.page >= self.pageCount - 1;
	_dots.currentPage = self.page;
	_skipButton.hidden = last;
	UIButtonConfiguration *config = _nextButton.configuration;
	config.title = L(last ? @"ONB_DONE" : @"ONB_NEXT");
	_nextButton.configuration = config;
}

- (void)showPage:(NSInteger)page animated:(BOOL)animated {
	self.page = MAX(0, MIN(page, self.pageCount - 1));
	[self updateControls];
	[_pager setContentOffset:CGPointMake(self.page * _pager.bounds.size.width, 0) animated:animated];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != _pager || !(scrollView.dragging || scrollView.decelerating)) return;
	CGFloat width = scrollView.bounds.size.width;
	if (width <= 0) return;
	NSInteger page = MAX(0, MIN((NSInteger)lround(scrollView.contentOffset.x / width), self.pageCount - 1));
	if (page == self.page) return;
	self.page = page;
	[self updateControls];
}

- (void)dotsChanged:(UIPageControl *)dots {
	[self showPage:dots.currentPage animated:YES];
}

#pragma mark - Actions

- (void)nextTapped {
	if (self.page >= self.pageCount - 1) [self finish];
	else [self showPage:self.page + 1 animated:YES];
}

// Page 1: the same chooser as the root row "Apps on the car screen" (Features/AppBridge/Prefs), pushed in the
// sheet so the guide carries on when the user comes back.
- (void)openApps {
	Class cls = NSClassFromString(@"OMCAppBridgeAppsController");
	if (!cls || ![cls isSubclassOfClass:[UIViewController class]]) return;
	UIViewController *chooser = [cls new];
	if ([chooser respondsToSelector:@selector(setSpecifier:)]) {
		// The chooser takes its title from the specifier, like when it is opened from the root page.
		PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:L(@"APPS") target:nil set:NULL get:NULL detail:cls cell:PSLinkCell edit:Nil];
		[(PSViewController *)chooser setSpecifier:spec];
	}
	[self.navigationController pushViewController:chooser animated:YES];
}

- (void)speedBubbleToggled:(UISwitch *)toggle {
	CFPreferencesSetAppValue(kSpeedBubbleKey, (__bridge CFPropertyListRef)@(toggle.on), kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	notify_post("com.anlai.omnicar/prefschanged");
}

// Skip / Done: remember the guide was seen, then close the sheet.
- (void)finish {
	[self markDone];
	// self is held by the block on purpose: the sheet may be released before the completion runs.
	UIViewController *sheet = self.navigationController ?: self;
	[sheet dismissViewControllerAnimated:YES completion:^{
		[self runCompletion];
	}];
}

- (void)markDone {
	CFPreferencesSetAppValue(kOnboardingDoneKey, kCFBooleanTrue, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
}

- (void)runCompletion {
	if (self.closed) return;
	self.closed = YES;
	if (self.completion) self.completion();
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
	[self markDone];
	[self runCompletion];
}

@end
