#import "OMCRootListController.h"
#import "OMCTheme.h"
#import <Preferences/PSTableCell.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <spawn.h>

#pragma mark - Header card

// Blue gradient card: app icon on the left, name + tagline in white, and an On/Off chip
// (no version - that lives in the footer card).
@interface OMCHeaderCard : UIView
@property (nonatomic, strong) UIView *card, *clip, *glowLarge, *glowSmall, *chip, *dot;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) UIImageView *logo;
@property (nonatomic, strong) UILabel *nameLabel, *taglineLabel, *statusLabel;
- (void)updateWithTagline:(NSString *)tagline status:(NSString *)status enabled:(BOOL)enabled;
@end

@implementation OMCHeaderCard

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.preservesSuperviewLayoutMargins = YES;

	// card carries the shadow, clip rounds the content
	_card = [UIView new];
	_card.layer.cornerRadius = 24;
	_card.layer.cornerCurve = kCACornerCurveContinuous;
	_card.layer.shadowColor = [UIColor colorWithRed:0.04 green:0.27 blue:0.88 alpha:1].CGColor;
	_card.layer.shadowOpacity = 0.30;
	_card.layer.shadowRadius = 14;
	_card.layer.shadowOffset = CGSizeMake(0, 6);
	[self addSubview:_card];

	_clip = [UIView new];
	_clip.layer.cornerRadius = 24;
	_clip.layer.cornerCurve = kCACornerCurveContinuous;
	_clip.clipsToBounds = YES;
	[_card addSubview:_clip];

	_gradient = [CAGradientLayer layer];
	_gradient.colors = @[(id)[UIColor colorWithRed:0.36 green:0.71 blue:1.00 alpha:1].CGColor,
	                     (id)[UIColor colorWithRed:0.12 green:0.42 blue:1.00 alpha:1].CGColor,
	                     (id)[UIColor colorWithRed:0.04 green:0.27 blue:0.88 alpha:1].CGColor];
	_gradient.locations = @[@0, @0.55, @1];
	_gradient.startPoint = CGPointZero;
	_gradient.endPoint = CGPointMake(1, 1);
	[_clip.layer addSublayer:_gradient];

	// Two soft circles on the right (glass highlight)
	_glowLarge = [UIView new];
	_glowLarge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
	[_clip addSubview:_glowLarge];
	_glowSmall = [UIView new];
	_glowSmall.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
	[_clip addSubview:_glowSmall];

	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	_logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo" inBundle:bundle compatibleWithTraitCollection:nil]];
	_logo.layer.shadowColor = UIColor.blackColor.CGColor;
	_logo.layer.shadowOpacity = 0.18;
	_logo.layer.shadowRadius = 8;
	_logo.layer.shadowOffset = CGSizeMake(0, 4);
	[_clip addSubview:_logo];

	_nameLabel = [UILabel new];
	_nameLabel.text = @"OmniCar";
	_nameLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
	_nameLabel.textColor = UIColor.whiteColor;
	[_clip addSubview:_nameLabel];

	_taglineLabel = [UILabel new];
	_taglineLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
	_taglineLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
	_taglineLabel.numberOfLines = 2;
	[_clip addSubview:_taglineLabel];

	_chip = [UIView new];
	_chip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
	_chip.layer.cornerRadius = 11;
	[_clip addSubview:_chip];

	_dot = [UIView new];
	_dot.layer.cornerRadius = 3.5;
	[_chip addSubview:_dot];

	_statusLabel = [UILabel new];
	_statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
	_statusLabel.textColor = UIColor.whiteColor;
	[_chip addSubview:_statusLabel];
	return self;
}

- (void)updateWithTagline:(NSString *)tagline status:(NSString *)status enabled:(BOOL)enabled {
	_taglineLabel.text = tagline;
	_statusLabel.text = status;
	_dot.backgroundColor = enabled ? [UIColor colorWithRed:0.45 green:0.95 blue:0.55 alpha:1]
	                               : [UIColor colorWithRed:1.00 green:0.55 blue:0.45 alpha:1];
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	// Lines up with the inset-grouped rows below
	UIEdgeInsets m = self.layoutMargins;
	CGRect r = CGRectMake(m.left, 16, self.bounds.size.width - m.left - m.right, self.bounds.size.height - 32);
	_card.frame = r;
	_clip.frame = _card.bounds;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_gradient.frame = _clip.bounds;
	[CATransaction commit];
	_card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_card.bounds cornerRadius:24].CGPath;

	CGFloat W = r.size.width, H = r.size.height;
	_glowLarge.frame = CGRectMake(W - 120, -50, 170, 170);
	_glowLarge.layer.cornerRadius = 85;
	_glowSmall.frame = CGRectMake(W - 60, H - 70, 110, 110);
	_glowSmall.layer.cornerRadius = 55;

	const CGFloat side = 64;
	_logo.frame = CGRectMake(20, (H - side) / 2, side, side);
	CGFloat x = CGRectGetMaxX(_logo.frame) + 16, w = W - x - 16;
	// Name, tagline (1-2 lines) and chip as one block, centered vertically
	CGFloat taglineH = ceil([_taglineLabel sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)].height);
	_nameLabel.frame = CGRectMake(x, (H - (32 + taglineH + 8 + 22)) / 2, w, 32);
	_taglineLabel.frame = CGRectMake(x, CGRectGetMaxY(_nameLabel.frame), w, taglineH);

	CGSize s = [_statusLabel sizeThatFits:CGSizeMake(w, 22)];
	_chip.frame = CGRectMake(x, CGRectGetMaxY(_taglineLabel.frame) + 8, s.width + 30, 22);
	_dot.frame = CGRectMake(10, 7.5, 7, 7);
	_statusLabel.frame = CGRectMake(22, 0, s.width, 22);
}

@end

@interface OMCRootListController ()
@property (nonatomic, strong) OMCHeaderCard *headerCard;
@end

@implementation OMCRootListController

#pragma mark - Specifiers

- (NSArray *)specifiers {
	if (!_specifiers) {
		OMCLoadStrings();
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		[self insertFeatureSpecifiers];
		OMCLocalizeSpecifiers(_specifiers);
	}
	return _specifiers;
}

// One PSLinkCell per Feature*.plist in the bundle, after the "features" group cell of Root.plist.
// Each feature plist describes its row at the top level: featureLabel (strings key), featureIcon
// (image in the bundle) or featureSymbol + featureSymbolColor, featureController (page class,
// default OMCFeatureListController) and featureOrder (sort key, then the file name).
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
		if (info[@"featureIcon"]) [spec setProperty:info[@"featureIcon"] forKey:@"icon"];
		if (info[@"featureSymbol"]) [spec setProperty:info[@"featureSymbol"] forKey:@"symbol"];
		if (info[@"featureSymbolColor"]) [spec setProperty:info[@"featureSymbolColor"] forKey:@"symbolColor"];
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
	// Pick up values the tweak wrote from another process (e.g. SpringBoard) since last time.
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self reloadSpecifiers];
	[self updateHeaderStatus];
	self.table.backgroundColor = OMCBackgroundColor();
	self.table.tintColor = OMCAccentColor();
}

- (void)applyLanguage {
	OMCLoadStrings();
	self.title = @"OmniCar";
	self.table.tableHeaderView = [self headerView];
	self.table.tableFooterView = [self footerView];
	self.navigationItem.rightBarButtonItem = [self languageButton];
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
	item.tintColor = OMCAccentColor();
	return item;
}

- (void)setLanguage:(NSString *)lang {
	CFPreferencesSetAppValue(kLanguageKey, (__bridge CFStringRef)lang, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self applyLanguage];
	_specifiers = nil;
	[self reloadSpecifiers];
}

// A full-width table header/footer holding one rounded card: an image beside a column of text lines.
// The card follows the table's layout margins so it lines up with the inset-grouped rows.
- (UIView *)cardContainerWithHeight:(CGFloat)height insets:(UIEdgeInsets)insets image:(UIImage *)image side:(CGFloat)side imageOnRight:(BOOL)imageOnRight lines:(NSArray<UILabel *> *)lines {
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
	imageView.translatesAutoresizingMaskIntoConstraints = NO;

	UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:lines];
	text.axis = UILayoutConstraintAxisVertical;
	text.spacing = 3;

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:imageOnRight ? @[text, imageView] : @[imageView, text]];
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
		imageOnRight ? [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16]
		             : [row.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],
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

// Top card (gradient, see OMCHeaderCard). The enable switch follows as the first row.
- (UIView *)headerView {
	if (!self.headerCard) {
		self.headerCard = [[OMCHeaderCard alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 150)];
		self.headerCard.autoresizingMask = UIViewAutoresizingFlexibleWidth;
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

// The chip follows the enable switch right away (uses the new value, not a possibly stale prefs read).
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
	if ([[specifier propertyForKey:@"key"] isEqualToString:(__bridge NSString *)kEnabledKey]) [self updateHeaderStatusEnabled:[value boolValue]];
}

// Bottom card: author logo, app name, version and copyright.
- (UIView *)footerView {
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	UIImage *avatar = [UIImage imageNamed:@"avatar" inBundle:bundle compatibleWithTraitCollection:nil];
	return [self cardContainerWithHeight:136 insets:UIEdgeInsetsMake(8, 0, 32, 0) image:avatar side:56 imageOnRight:NO lines:@[
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
// Tweak-specific PSButtonCell actions go here (one method per "action" in Root.plist).

// "Respring" row (action = respring): confirm, then restart SpringBoard.
- (void)respring {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"RESPRING_CONFIRM") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:L(@"RESPRING") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		[weakSelf performRespring];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

// Userspace respring (FBSSystemService + SBSRelaunchAction, like other tweaks' Respring buttons);
// falls back to killall SpringBoard.
- (void)performRespring {
	dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
	dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
	Class relaunch = NSClassFromString(@"SBSRelaunchAction"), service = NSClassFromString(@"FBSSystemService");
	if (relaunch && service) {
		id action = ((id (*)(Class, SEL, NSString *, NSUInteger, NSURL *))objc_msgSend)(relaunch,
			NSSelectorFromString(@"actionWithReason:options:targetURL:"), @"RestartRenderServer", 4 /* FadeToBlack */, nil);
		id shared = ((id (*)(Class, SEL))objc_msgSend)(service, NSSelectorFromString(@"sharedService"));
		if (action && shared) {
			((void (*)(id, SEL, NSSet *, id))objc_msgSend)(shared, NSSelectorFromString(@"sendActions:withResult:"),
				[NSSet setWithObject:action], nil);
			return;
		}
	}
	for (NSString *path in @[@"/var/jb/usr/bin/killall", @"/usr/bin/killall"]) {
		if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) continue;
		pid_t pid;
		const char *argv[] = {path.fileSystemRepresentation, "-9", "SpringBoard", NULL};
		posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, NULL);
		return;
	}
}

@end
