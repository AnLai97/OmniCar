#import "OMCRootListController.h"
#import "OMCTheme.h"
#import "OMCDiagnostics.h"
#import "OMCOnboardingController.h"
#import <Preferences/PSTableCell.h>
#import <dlfcn.h>
#import <notify.h>
#import <objc/message.h>
#import <spawn.h>

#pragma mark - Header card

// Dark glass card in the OmniCar look (DESIGN.md, same colors as the logo): logo, name, slogan, status line
// ("● On", the dot glows white when on) and the master switch, so the enable row is gone. The version
// lives in the footer card, not here.
@interface OMCHeaderCard : UIView
@property (nonatomic, strong) UIView *card, *clip, *dot;
@property (nonatomic, strong) CAGradientLayer *gradient, *sheen;
@property (nonatomic, strong) UIImageView *logo;
@property (nonatomic, strong) UILabel *nameLabel, *taglineLabel, *statusLabel;
@property (nonatomic, strong) UISwitch *toggle;
- (void)updateWithTagline:(NSString *)tagline status:(NSString *)status enabled:(BOOL)enabled;
@end

@implementation OMCHeaderCard

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.preservesSuperviewLayoutMargins = YES;

	// card carries the shadow, clip rounds the content
	_card = [UIView new];
	_card.layer.cornerRadius = 22;
	_card.layer.cornerCurve = kCACornerCurveContinuous;
	_card.layer.shadowColor = UIColor.blackColor.CGColor;
	_card.layer.shadowOpacity = 0.18;
	_card.layer.shadowRadius = 12;
	_card.layer.shadowOffset = CGSizeMake(0, 5);
	[self addSubview:_card];

	_clip = [UIView new];
	_clip.layer.cornerRadius = 22;
	_clip.layer.cornerCurve = kCACornerCurveContinuous;
	_clip.layer.borderWidth = 0.5;
	_clip.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
	_clip.clipsToBounds = YES;
	[_card addSubview:_clip];

	_gradient = [CAGradientLayer layer];
	_gradient.colors = @[(id)OMCColorFromHex(@"#353A43").CGColor, (id)OMCColorFromHex(@"#101216").CGColor];
	[_clip.layer addSublayer:_gradient];
	_sheen = [CAGradientLayer layer];   // vet sang kinh nua tren
	_sheen.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.08].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
	[_clip.layer addSublayer:_sheen];

	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	_logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo" inBundle:bundle compatibleWithTraitCollection:nil]];
	[_clip addSubview:_logo];

	_nameLabel = [UILabel new];
	_nameLabel.text = @"OmniCar";
	_nameLabel.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
	_nameLabel.textColor = UIColor.whiteColor;
	[_clip addSubview:_nameLabel];

	_taglineLabel = [UILabel new];
	_taglineLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
	_taglineLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
	_taglineLabel.adjustsFontSizeToFitWidth = YES;
	_taglineLabel.minimumScaleFactor = 0.8;
	[_clip addSubview:_taglineLabel];

	_dot = [UIView new];
	_dot.layer.cornerRadius = 3.5;
	_dot.layer.shadowColor = UIColor.whiteColor.CGColor;
	_dot.layer.shadowRadius = 4;
	_dot.layer.shadowOffset = CGSizeZero;
	[_clip addSubview:_dot];

	_statusLabel = [UILabel new];
	_statusLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
	_statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
	[_clip addSubview:_statusLabel];

	_toggle = [UISwitch new];
	_toggle.onTintColor = UIColor.whiteColor;
	_toggle.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];   // ray khi tat tren nen toi
	_toggle.layer.cornerRadius = 15.5;
	[_clip addSubview:_toggle];
	return self;
}

- (void)updateWithTagline:(NSString *)tagline status:(NSString *)status enabled:(BOOL)enabled {
	_taglineLabel.text = tagline;
	_statusLabel.text = status;
	_dot.backgroundColor = [UIColor colorWithWhite:1 alpha:enabled ? 1 : 0.35];
	_dot.layer.shadowOpacity = enabled ? 0.9 : 0;
	_toggle.on = enabled;
	// Ray trang khi bat -> nut tron toi cho noi; tat -> nut trang nhu thuong
	_toggle.thumbTintColor = enabled ? OMCColorFromHex(@"#1B1D22") : UIColor.whiteColor;
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	// Lines up with the inset-grouped rows below
	UIEdgeInsets m = self.layoutMargins;
	CGRect r = CGRectMake(m.left, 8, self.bounds.size.width - m.left - m.right, self.bounds.size.height - 24);
	_card.frame = r;
	_clip.frame = _card.bounds;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_gradient.frame = _clip.bounds;
	_sheen.frame = CGRectMake(0, 0, r.size.width, r.size.height / 2);
	[CATransaction commit];
	_card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_card.bounds cornerRadius:22].CGPath;

	CGFloat W = r.size.width, H = r.size.height;
	const CGFloat side = 58;
	_logo.frame = CGRectMake(16, (H - side) / 2, side, side);
	CGSize ts = [_toggle sizeThatFits:CGSizeZero];
	_toggle.frame = CGRectMake(W - 16 - ts.width, (H - ts.height) / 2, ts.width, ts.height);
	CGFloat x = CGRectGetMaxX(_logo.frame) + 14, w = CGRectGetMinX(_toggle.frame) - 10 - x;
	// Name, slogan and status as one block (28 + 18 + 18), centered vertically
	CGFloat top = (H - 64) / 2;
	_nameLabel.frame = CGRectMake(x, top, w, 28);
	_taglineLabel.frame = CGRectMake(x, top + 28, w, 18);
	_statusLabel.frame = CGRectMake(x + 13, top + 46, w - 13, 18);
	_dot.frame = CGRectMake(x, top + 46 + 5.5, 7, 7);
}

@end

#pragma mark - Feature row

// Feature row on the main page: name on the left, the feature's On / Off on the right (read from the
// first switch of its Feature*.plist: featureKey / featureDefault set by insertFeatureSpecifiers).
@interface OMCFeatureStatusCell : PSTableCell
@end

@implementation OMCFeatureStatusCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
	return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier specifier:specifier];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	NSString *key = [specifier propertyForKey:@"featureKey"];
	if (key) {
		id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain);
		BOOL on = value ? [value boolValue] : [[specifier propertyForKey:@"featureDefault"] boolValue];
		self.detailTextLabel.text = L(on ? @"FEATURE_ON" : @"FEATURE_OFF");
	}
	self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

@end

@interface OMCRootListController ()
@property (nonatomic, strong) OMCHeaderCard *headerCard;
@property (nonatomic, copy) NSString *supportState;   // rescue + conflicts the rows were built for
@end

@implementation OMCRootListController

#pragma mark - Specifiers

- (NSArray *)specifiers {
	if (!_specifiers) {
		OMCLoadStrings();
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		[self insertFeatureSpecifiers];
		OMCLocalizeSpecifiers(_specifiers);
		[self applySupportState];
#if OMC_AUTOTEST
		[self insertAutoTestSpecifier];
#endif
	}
	return _specifiers;
}

#if OMC_AUTOTEST
// Developer builds only: Support > Auto test (Prefs/OMCAutoTestController.m), right after Send log.
- (void)insertAutoTestSpecifier {
	PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:L(@"AUTOTEST") target:self set:NULL get:NULL
		detail:NSClassFromString(@"OMCAutoTestController") cell:PSLinkCell edit:Nil];
	UIImage *icon = OMCIcon(@"checklist", nil);
	if (icon) [spec setProperty:icon forKey:@"iconImage"];
	NSUInteger index = _specifiers.count;
	for (NSUInteger i = 0; i < _specifiers.count; i++)
		if ([[_specifiers[i] identifier] isEqualToString:@"sendLog"]) { index = i + 1; break; }
	[_specifiers insertObject:spec atIndex:index];
}
#endif

// Rescue and conflict cards (Root.plist rows tagged "omcGroup"): dropped when there is nothing to say,
// otherwise filled with the feature / tweak names.
- (NSString *)currentSupportState {
	NSMutableArray *active = [NSMutableArray array];
	for (NSDictionary *t in OMCConflictingTweaks()) if ([t[@"active"] boolValue]) [active addObject:t[@"name"]];
	return [NSString stringWithFormat:@"%@|%@", [OMCRescueFeatures() componentsJoinedByString:@","], [active componentsJoinedByString:@", "]];
}

- (void)applySupportState {
	self.supportState = [self currentSupportState];
	NSArray *parts = [self.supportState componentsSeparatedByString:@"|"];
	NSString *rescued = parts[0], *conflicts = parts[1];
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *f in rescued.length ? [rescued componentsSeparatedByString:@","] : @[]) [names addObject:OMCFeatureDisplayName(f)];

	for (PSSpecifier *spec in [_specifiers copy]) {
		NSString *group = [spec propertyForKey:@"omcGroup"];
		if (!group) continue;
		if (([group isEqualToString:@"rescue"] && !names.count) || ([group isEqualToString:@"conflicts"] && !conflicts.length)) {
			[_specifiers removeObject:spec];
			continue;
		}
		if ([spec.identifier isEqualToString:@"rescueGroup"])
			[spec setProperty:[NSString stringWithFormat:L(@"RESCUE_FOOTER"), [names componentsJoinedByString:@", "]] forKey:@"footerText"];
		else if ([spec.identifier isEqualToString:@"conflictsGroup"])
			[spec setProperty:L(@"CONFLICTS_FOOTER") forKey:@"footerText"];
		else if ([spec.identifier isEqualToString:@"conflictsRow"])
			spec.name = conflicts;
	}
}

// One PSLinkCell per Feature*.plist in the bundle, after the "features" group cell of Root.plist.
// Each feature plist describes its row at the top level: featureLabel (strings key), featureIcon
// (image in the bundle) or featureSymbol, featureController (page class, default
// OMCFeatureListController) and featureOrder (sort key, then the file name). The row shows the
// feature's On / Off from the first switch of the page.
- (void)insertFeatureSpecifiers {
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSMutableArray<NSDictionary *> *features = [NSMutableArray array];
	for (NSString *path in [bundle pathsForResourcesOfType:@"plist" inDirectory:nil]) {
		NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
		if (![name hasPrefix:@"Feature"]) continue;
		NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
		if (!plist[@"featureLabel"]) continue;
		[features addObject:@{@"plist": name, @"info": plist}];
	}
	[features sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
		NSInteger oa = [a[@"info"][@"featureOrder"] integerValue], ob = [b[@"info"][@"featureOrder"] integerValue];
		if (oa != ob) return oa < ob ? NSOrderedAscending : NSOrderedDescending;
		return [a[@"plist"] compare:b[@"plist"]];
	}];

	NSUInteger index = NSNotFound;
	for (NSUInteger i = 0; i < _specifiers.count; i++) {
		if ([[_specifiers[i] identifier] isEqualToString:@"features"]) { index = i + 1; break; }
	}
	if (index == NSNotFound) index = _specifiers.count;

	for (NSDictionary *feature in features) {
		NSDictionary *info = feature[@"info"];
		Class detail = NSClassFromString(info[@"featureController"] ?: @"OMCFeatureListController") ?: NSClassFromString(@"OMCFeatureListController");
		PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:info[@"featureLabel"] target:self set:NULL get:NULL detail:detail cell:PSLinkCell edit:Nil];
		[spec setProperty:feature[@"plist"] forKey:@"plist"];
		[spec setProperty:[OMCFeatureStatusCell class] forKey:@"cellClass"];
		if (info[@"featureIcon"]) [spec setProperty:info[@"featureIcon"] forKey:@"icon"];
		if (info[@"featureSymbol"]) [spec setProperty:info[@"featureSymbol"] forKey:@"symbol"];
		for (NSDictionary *item in info[@"items"]) {   // first switch of the page = the feature's on/off
			if (![item[@"cell"] isEqualToString:@"PSSwitchCell"] || !item[@"key"]) continue;
			[spec setProperty:item[@"key"] forKey:@"featureKey"];
			[spec setProperty:item[@"default"] ?: @YES forKey:@"featureDefault"];
			break;
		}
		[_specifiers insertObject:spec atIndex:index++];
	}
}

#pragma mark - Appearance

- (void)viewDidLoad {
	[super viewDidLoad];
	// Scoped to this controller so the rest of Settings keeps its own look.
	[UISwitch appearanceWhenContainedInInstancesOfClasses:@[[self class]]].onTintColor = OMCAccentColor();
	[UISlider appearanceWhenContainedInInstancesOfClasses:@[[self class]]].minimumTrackTintColor = OMCAccentColor();
	[self applyLanguage];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// Pick up values the tweak wrote from another process (e.g. SpringBoard) since last time, and the
	// On / Off of the feature pages just left.
	CFPreferencesAppSynchronize(kPrefsDomain);
	if (![[self currentSupportState] isEqualToString:self.supportState ?: @""]) _specifiers = nil;   // rescue / conflict cards changed
	[self reloadSpecifiers];
	[self updateHeaderStatus];
	self.table.backgroundColor = OMCBackgroundColor();
	self.table.tintColor = OMCAccentColor();
}

// First open of Settings > OmniCar: the guide, once (Prefs/OMCOnboardingController.m, pref "onboardingDone").
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	static BOOL offered;
	if (offered || self.presentedViewController || ![OMCOnboardingController shouldShow]) return;
	offered = YES;
	[self showGuide];
}

- (void)applyLanguage {
	OMCLoadStrings();
	self.title = @"OmniCar";
	self.table.tableHeaderView = [self headerView];
	self.table.tableFooterView = [self footerView];
	// Respring and Language as two small nav bar buttons instead of rows (rightmost first)
	UIBarButtonItem *respring = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(respring)];
	respring.tintColor = [UIColor labelColor];
	respring.accessibilityLabel = L(@"RESPRING");
	self.navigationItem.rightBarButtonItems = @[respring, [self languageButton]];
}

- (UIBarButtonItem *)languageButton {
	NSString *current = OMCLanguage();
	NSMutableArray *actions = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;
	for (NSString *lang in OMCLanguages()) {
		UIAction *action = [UIAction actionWithTitle:OMCLanguageName(lang) image:nil identifier:nil handler:^(UIAction *a) {
			[weakSelf setLanguage:lang];
		}];
		action.state = [lang isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
		[actions addObject:action];
	}
	UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"globe"] style:UIBarButtonItemStylePlain target:nil action:nil];
	item.menu = [UIMenu menuWithTitle:L(@"LANGUAGE") children:actions];
	item.tintColor = [UIColor labelColor];
	return item;
}

- (void)setLanguage:(NSString *)lang {
	CFPreferencesSetAppValue(kLanguageKey, (__bridge CFStringRef)lang, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self applyLanguage];
	_specifiers = nil;
	[self reloadSpecifiers];
}

// Top card with the master switch (see OMCHeaderCard).
- (UIView *)headerView {
	if (!self.headerCard) {
		self.headerCard = [[OMCHeaderCard alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 132)];
		self.headerCard.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.headerCard.toggle addTarget:self action:@selector(masterToggled:) forControlEvents:UIControlEventValueChanged];
	}
	[self updateHeaderStatus];
	return self.headerCard;
}

- (void)updateHeaderStatus {
	[self updateHeaderStatusEnabled:OMCEnabled()];
}

- (void)updateHeaderStatusEnabled:(BOOL)enabled {
	[self.headerCard updateWithTagline:L(@"HEADER_TAGLINE") status:L(enabled ? @"STATUS_ON" : @"STATUS_OFF") enabled:enabled];
}

// Master switch: same key and notification as the old "Enable OmniCar" row.
- (void)masterToggled:(UISwitch *)sw {
	CFPreferencesSetAppValue(kEnabledKey, (__bridge CFPropertyListRef)@(sw.on), kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	notify_post("com.anlai.omnicar/prefschanged");
	[self updateHeaderStatusEnabled:sw.on];
}

// A full-width table footer holding one rounded card: an image beside a column of text lines.
// The card follows the table's layout margins so it lines up with the inset-grouped rows.
- (UIView *)cardContainerWithHeight:(CGFloat)height insets:(UIEdgeInsets)insets image:(UIImage *)image side:(CGFloat)side lines:(NSArray<UILabel *> *)lines {
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, height)];
	container.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	container.preservesSuperviewLayoutMargins = YES;

	UIView *card = [UIView new];
	card.backgroundColor = OMCCardColor();
	card.layer.cornerRadius = 20;
	card.layer.cornerCurve = kCACornerCurveContinuous;
	card.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:card];

	UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
	imageView.layer.cornerRadius = side * 0.22;
	imageView.layer.cornerCurve = kCACornerCurveContinuous;
	imageView.clipsToBounds = YES;
	imageView.translatesAutoresizingMaskIntoConstraints = NO;

	UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:lines];
	text.axis = UILayoutConstraintAxisVertical;
	text.spacing = 3;

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[imageView, text]];
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 14;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	[card addSubview:row];

	UILayoutGuide *margins = container.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[card.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[card.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[card.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top],
		[card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom],
		[imageView.widthAnchor constraintEqualToConstant:side],
		[imageView.heightAnchor constraintEqualToConstant:side],
		[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
		[row.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],
		[row.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
	]];
	return container;
}

- (UILabel *)labelWithText:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
	UILabel *label = [UILabel new];
	label.text = text;
	label.font = [UIFont systemFontOfSize:size weight:weight];
	label.textColor = color;
	label.numberOfLines = 0;
	return label;
}

// Bottom card: author logo (AL), app name, version and copyright.
- (UIView *)footerView {
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	UIImage *avatar = [UIImage imageNamed:@"avatar" inBundle:bundle compatibleWithTraitCollection:nil];
	return [self cardContainerWithHeight:136 insets:UIEdgeInsetsMake(8, 0, 32, 0) image:avatar side:56 lines:@[
		[self labelWithText:@"OmniCar" size:16 weight:UIFontWeightSemibold color:[UIColor labelColor]],
		[self labelWithText:[NSString stringWithFormat:L(@"VERSION_FORMAT"), @TWEAK_VERSION] size:13 weight:UIFontWeightRegular color:[UIColor secondaryLabelColor]],
		[self labelWithText:L(@"COPYRIGHT") size:13 weight:UIFontWeightRegular color:[UIColor secondaryLabelColor]],
	]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	OMCStyleCell(cell);
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayHeaderView:view forSection:section];
	OMCStyleHeaderFooter(view, YES);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayFooterView:view forSection:section];
	OMCStyleHeaderFooter(view, NO);
}

#pragma mark - Helpers for actions

- (void)showMessage:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"OmniCar" message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

// Support > Send log: report + OmniCar.log straight into the share sheet (Zalo, Mail ...).
- (void)sendLog {
	OMCShareReport(self, nil);
}

// Support > Show guide again (also the first-run guide from viewDidAppear). Reload afterwards: page 3 can
// turn Speed Bubble on / off, which the feature row shows.
- (void)showGuide {
	if (self.presentedViewController) return;
	__weak typeof(self) weakSelf = self;
	UINavigationController *guide = [OMCOnboardingController guideNavigationControllerWithCompletion:^{
		[weakSelf reloadSpecifiers];
		[weakSelf updateHeaderStatus];
	}];
	[self presentViewController:guide animated:YES completion:nil];
}

// Rescue card: turn the features rescue mode switched off back on.
- (void)rescueRestore {
	OMCRescueRestore();
	_specifiers = nil;
	[self reloadSpecifiers];
	[self showMessage:L(@"RESCUE_RESTORED")];
}

// Respring button (nav bar): confirm, then restart SpringBoard.
- (void)respring {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"RESPRING_CONFIRM") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:L(@"RESPRING") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		[weakSelf performRespring];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

// Userspace respring (FBSSystemService + SBSRelaunchAction), falls back to killall SpringBoard: OMCRespring.
- (void)performRespring {
	OMCRespring();
}

@end
