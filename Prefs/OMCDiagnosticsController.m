// Diagnostics page (Support > Diagnostics on the root page): a health check anyone can read and act on.
//   Summary card: verdict colored by the worst status, "Optimize" (does what it can, lists what the user can do)
//                 and "Send log".
//   Needs attention: only the checks that are off, each with its fix and a button when the page can fix it itself
//                 (respring, turn rescued features back on, measure again, clear the log).
//   Optimize performance: lite mode (Off / Auto / Always), free memory when the car connects, free memory now.
//   Phone / CarPlay / CarPlay performance / Features: one row each with the counts; tap to open every check.
//   Technical details: raw values one level down (same class, details = YES).
#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import "OMCDiagnostics.h"
#import "OMCTheme.h"

@interface PSViewController (OMCDiagnostics)
- (PSSpecifier *)specifier;
@end

@interface OMCDiagnosticsController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) BOOL details;                         // YES = technical details page
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *groups;     // health checks (OMCDiagChecks)
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;   // technical details (OMCDiagSections)
@property (nonatomic, strong) NSArray<NSDictionary *> *model;      // main page: @{@"title", @"footer", @"rows": @[row]}
@property (nonatomic, strong) NSMutableSet<NSString *> *expanded;  // group titles opened
@property (nonatomic, strong) NSDate *checkedAt;
@end

static UIColor *OMCStatusColor(NSString *status) {
	if ([status isEqualToString:@"ok"]) return [UIColor systemGreenColor];
	if ([status isEqualToString:@"warn"]) return [UIColor systemOrangeColor];
	if ([status isEqualToString:@"bad"]) return [UIColor systemRedColor];
	return [UIColor systemGrayColor];
}

static UIImage *OMCStatusIcon(NSString *status, CGFloat size) {
	NSString *name = [status isEqualToString:@"ok"] ? @"checkmark.circle.fill"
		: [status isEqualToString:@"warn"] ? @"exclamationmark.triangle.fill"
		: [status isEqualToString:@"bad"] ? @"xmark.octagon.fill" : @"info.circle.fill";
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold];
	return [[UIImage systemImageNamed:name withConfiguration:cfg] imageWithTintColor:OMCStatusColor(status) renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static BOOL OMCIsProblem(NSDictionary *check) {
	return [check[@"status"] isEqualToString:@"warn"] || [check[@"status"] isEqualToString:@"bad"];
}

// Button title for a check's action
static NSString *OMCActionTitle(NSString *action) {
	if ([action isEqualToString:@"respring"]) return L(@"RESPRING");
	if ([action isEqualToString:@"rescue"]) return L(@"ACT_TURN_ON");
	if ([action isEqualToString:@"perfReset"]) return L(@"ACT_REMEASURE");
	if ([action isEqualToString:@"clearLog"]) return L(@"ACT_CLEAR");
	return nil;
}

static UIButton *OMCPillButton(NSString *title, NSString *symbol, UIColor *color, BOOL filled, CGFloat fontSize) {
	UIButtonConfiguration *cfg = filled ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration tintedButtonConfiguration];
	cfg.title = title;
	if (symbol) {
		cfg.image = [UIImage systemImageNamed:symbol];
		cfg.imagePadding = 6;
	}
	cfg.baseBackgroundColor = color;
	cfg.baseForegroundColor = filled ? [UIColor whiteColor] : color;
	cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
	cfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
	UIFont *font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
	cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
		NSMutableDictionary *m = [attrs mutableCopy];
		m[NSFontAttributeName] = font;
		return m;
	};
	return [UIButton buttonWithConfiguration:cfg primaryAction:nil];
}

@implementation OMCDiagnosticsController

- (void)loadView {
	_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_table.dataSource = self;
	_table.delegate = self;
	_table.estimatedRowHeight = 64;
	_table.rowHeight = UITableViewAutomaticDimension;
	self.view = _table;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	OMCLoadStrings();
	self.expanded = [NSMutableSet set];
	self.title = self.details ? L(@"DIAG_DETAILS") : (self.specifier.name ?: L(@"DIAGNOSTICS"));
	self.view.tintColor = OMCAccentColor();
	_table.backgroundColor = OMCBackgroundColor();
	UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
		style:UIBarButtonItemStylePlain target:self action:@selector(shareReport:)];
	share.tintColor = [UIColor labelColor];
	share.accessibilityLabel = L(@"SEND_LOG");
	self.navigationItem.rightBarButtonItem = share;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self runChecks];
}

- (void)runChecks {
	if (self.details) {
		self.sections = OMCDiagSections();
		[self.table reloadData];
		return;
	}
	self.groups = OMCDiagChecks();
	self.checkedAt = [NSDate date];
	[self buildModel];
	self.table.tableHeaderView = [self summaryView];
	[self.table reloadData];
}

// Sections of the main page from the checks: problems first, then the optimize settings, then the groups
- (void)buildModel {
	NSMutableArray *model = [NSMutableArray array];
	NSMutableArray *issues = [NSMutableArray array];
	for (NSDictionary *g in self.groups) for (NSDictionary *c in g[@"checks"]) if (OMCIsProblem(c)) [issues addObject:@{@"type": @"check", @"check": c}];
	if (issues.count) [model addObject:@{@"title": L(@"ISSUES_GROUP"), @"footer": L(@"ISSUES_FOOTER"), @"rows": issues}];

	[model addObject:@{@"title": L(@"OPT_GROUP"), @"footer": L(@"OPT_FOOTER"),
		@"rows": @[@{@"type": @"lite"}, @{@"type": @"cleanOn"}, @{@"type": @"cleanNow"}]}];

	NSArray *icons = @[@"iphone", @"car.fill", @"speedometer", @"square.grid.2x2.fill"];
	NSMutableArray *groupRows = [NSMutableArray array];
	for (NSUInteger i = 0; i < self.groups.count; i++) {
		NSDictionary *g = self.groups[i];
		[groupRows addObject:@{@"type": @"group", @"group": g, @"icon": icons[MIN(i, icons.count - 1)]}];
		if ([self.expanded containsObject:g[@"title"]])
			for (NSDictionary *c in g[@"checks"]) [groupRows addObject:@{@"type": @"check", @"check": c, @"nested": @YES}];
	}
	[model addObject:@{@"title": L(@"ALL_CHECKS_GROUP"), @"footer": L(@"ALL_CHECKS_FOOTER"), @"rows": groupRows}];
	[model addObject:@{@"footer": L(@"CHK_FOOTER"), @"rows": @[@{@"type": @"details"}]}];
	self.model = model;
}

- (void)shareReport:(id)sender {
	OMCShareReport(self, [sender isKindOfClass:[UIBarButtonItem class]] ? sender : self.navigationItem.rightBarButtonItem);
}

#pragma mark - Summary card

// Verdict over every check, colored by the worst status, with "Check again", "Optimize" and "Send log"
- (UIView *)summaryView {
	NSDictionary *sum = OMCDiagSummary(self.groups);
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 168)];
	container.preservesSuperviewLayoutMargins = YES;

	UIView *card = [UIView new];
	card.backgroundColor = OMCCardColor();
	card.layer.cornerRadius = 18;
	card.layer.cornerCurve = kCACornerCurveContinuous;
	card.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:card];

	UIImageView *icon = [[UIImageView alloc] initWithImage:OMCStatusIcon(sum[@"status"], 30)];
	icon.contentMode = UIViewContentModeCenter;
	UILabel *title = [UILabel new];
	title.text = sum[@"title"];
	title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
	title.numberOfLines = 0;
	UILabel *sub = [UILabel new];
	NSString *when = [NSDateFormatter localizedStringFromDate:self.checkedAt dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
	sub.text = [NSString stringWithFormat:@"%@ · %@", sum[@"subtitle"], [NSString stringWithFormat:L(@"CHK_CHECKED_AT"), when]];
	sub.font = [UIFont systemFontOfSize:13];
	sub.textColor = [UIColor secondaryLabelColor];
	sub.numberOfLines = 0;
	UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[title, sub]];
	text.axis = UILayoutConstraintAxisVertical;
	text.spacing = 2;

	UIButton *again = [UIButton buttonWithType:UIButtonTypeSystem];
	[again setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
	again.tintColor = [UIColor labelColor];
	again.accessibilityLabel = L(@"CHK_AGAIN");
	[again addTarget:self action:@selector(runChecks) forControlEvents:UIControlEventTouchUpInside];

	UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text, again]];
	top.alignment = UIStackViewAlignmentCenter;
	top.spacing = 14;

	UIButton *optimize = OMCPillButton(L(@"OPT_BUTTON"), @"bolt.fill", OMCAccentColor(), YES, 15);
	[optimize addTarget:self action:@selector(optimize) forControlEvents:UIControlEventTouchUpInside];
	UIButton *send = OMCPillButton(L(@"SEND_LOG"), @"square.and.arrow.up", [UIColor labelColor], NO, 15);
	[send addTarget:self action:@selector(shareReport:) forControlEvents:UIControlEventTouchUpInside];
	UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[optimize, send]];
	buttons.distribution = UIStackViewDistributionFillEqually;
	buttons.spacing = 10;

	UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[top, buttons]];
	column.axis = UILayoutConstraintAxisVertical;
	column.spacing = 14;
	column.translatesAutoresizingMaskIntoConstraints = NO;
	[card addSubview:column];

	UILayoutGuide *m = container.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[card.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
		[card.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
		[card.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
		[card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
		[icon.widthAnchor constraintEqualToConstant:36],
		[again.widthAnchor constraintEqualToConstant:36],
		[buttons.heightAnchor constraintEqualToConstant:44],
		[column.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
		[column.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
		[column.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
	]];
	return container;
}

#pragma mark - Optimize

// Bullet list, left aligned (an alert centers its message)
static void OMCSetAlertList(UIAlertController *alert, NSString *text) {
	NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
	p.alignment = NSTextAlignmentLeft;
	p.paragraphSpacing = 4;
	NSAttributedString *a = [[NSAttributedString alloc] initWithString:text attributes:@{
		NSParagraphStyleAttributeName: p, NSFontAttributeName: [UIFont systemFontOfSize:13]}];
	@try { [alert setValue:a forKey:@"attributedMessage"]; } @catch (NSException *e) { alert.message = text; }
}

- (void)optimize {
	NSDictionary *plan = OMCOptimizePlan(self.groups);
	NSArray<NSDictionary *> *steps = plan[@"steps"];
	NSArray<NSString *> *manual = plan[@"manual"];
	NSMutableString *text = [NSMutableString string];
	if (steps.count) {
		[text appendFormat:@"%@\n", L(@"OPT_WILL")];
		for (NSDictionary *s in steps) [text appendFormat:@"• %@\n", s[@"title"]];
	}
	if (manual.count) {
		[text appendFormat:@"%@%@\n", text.length ? @"\n" : @"", L(@"OPT_MANUAL")];
		for (NSString *m in manual) [text appendFormat:@"• %@\n", m];
	}
	if (!text.length) [text appendString:L(@"OPT_NOTHING")];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"OPT_BUTTON") message:nil preferredStyle:UIAlertControllerStyleAlert];
	OMCSetAlertList(alert, [text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
	if (steps.count) {
		[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
		UIAlertAction *go = [UIAlertAction actionWithTitle:L(@"OPT_APPLY") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
			OMCOptimizeApply(steps);
			[self runChecks];
			UIAlertController *done = [UIAlertController alertControllerWithTitle:L(@"OPT_DONE") message:nil preferredStyle:UIAlertControllerStyleAlert];
			[done addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
			[self presentViewController:done animated:YES completion:nil];
		}];
		[alert addAction:go];
		alert.preferredAction = go;
	} else {
		[alert addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	}
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)liteChanged:(UISegmentedControl *)seg {
	NSInteger modes[] = {0, 2, 1};   // segments: Off, Auto, Always
	OMCSetLiteMode(modes[MAX(0, MIN(2, seg.selectedSegmentIndex))]);
	[self reloadRowOfType:@"lite"];
}

- (void)cleanChanged:(UISwitch *)sw {
	OMCSetCleanRam(sw.on);
}

- (void)reloadRowOfType:(NSString *)type {
	for (NSUInteger s = 0; s < self.model.count; s++) {
		NSArray *rows = self.model[s][@"rows"];
		for (NSUInteger r = 0; r < rows.count; r++)
			if ([rows[r][@"type"] isEqualToString:type])
				[self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:r inSection:s]] withRowAnimation:UITableViewRowAnimationNone];
	}
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.details ? self.sections.count : self.model.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [(self.details ? self.sections : self.model)[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return (self.details ? self.sections : self.model)[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return (self.details ? self.sections : self.model)[section][@"footer"];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, YES); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, NO); }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (self.details) {   // label left, value right, long values wrap
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"detail"]
			?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"detail"];
		NSDictionary *row = self.sections[ip.section][@"rows"][ip.row];
		OMCStyleCell(cell);
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.text = row[@"label"];
		cell.detailTextLabel.text = row[@"value"];
		cell.detailTextLabel.numberOfLines = 0;
		cell.detailTextLabel.textAlignment = NSTextAlignmentRight;
		return cell;
	}
	NSDictionary *row = self.model[ip.section][@"rows"][ip.row];
	NSString *type = row[@"type"];
	if ([type isEqualToString:@"check"]) return [self checkCell:row[@"check"] nested:[row[@"nested"] boolValue]];
	if ([type isEqualToString:@"group"]) return [self groupCell:row];
	if ([type isEqualToString:@"lite"]) return [self liteCell];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:type]
		?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:type];
	OMCStyleCell(cell);
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	cell.detailTextLabel.numberOfLines = 0;
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	if ([type isEqualToString:@"cleanOn"]) {
		cell.textLabel.text = L(@"CLEAN_RAM");
		cell.detailTextLabel.text = OMCCleanRamStatus();
		cell.imageView.image = OMCIcon(@"memorychip", nil);
		UISwitch *sw = [UISwitch new];
		sw.on = OMCCleanRamOn();
		sw.onTintColor = OMCAccentColor();
		[sw addTarget:self action:@selector(cleanChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	} else if ([type isEqualToString:@"cleanNow"]) {
		cell.textLabel.text = L(@"CLEAN_RAM_NOW");
		cell.textLabel.textColor = OMCAccentColor();
		cell.detailTextLabel.text = L(@"CLEAN_RAM_NOW_SUB");
		cell.imageView.image = OMCIcon(@"sparkles", nil);
	} else {   // details
		cell.textLabel.text = L(@"DIAG_DETAILS");
		cell.detailTextLabel.text = nil;
		cell.imageView.image = OMCIcon(@"list.bullet.rectangle", nil);
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	return cell;
}

// Lite mode: title + what it is doing now, and Off / Auto / Always under it
- (UITableViewCell *)liteCell {
	UITableViewCell *cell = [self.table dequeueReusableCellWithIdentifier:@"lite"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"lite"];
		UIImageView *icon = [[UIImageView alloc] initWithImage:OMCIcon(@"leaf.fill", nil)];
		icon.contentMode = UIViewContentModeCenter;
		UILabel *title = [UILabel new];
		title.text = L(@"LITE_MODE");
		title.font = [UIFont systemFontOfSize:17];
		UILabel *status = [UILabel new]; status.tag = 2;
		status.font = [UIFont systemFontOfSize:13];
		status.textColor = [UIColor secondaryLabelColor];
		status.numberOfLines = 0;
		UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[title, status]];
		text.axis = UILayoutConstraintAxisVertical;
		text.spacing = 2;
		UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
		head.spacing = 12;
		head.alignment = UIStackViewAlignmentCenter;
		UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[L(@"LITE_OFF"), L(@"LITE_AUTO"), L(@"LITE_ALWAYS")]];
		seg.tag = 3;
		seg.selectedSegmentTintColor = OMCAccentColor();
		[seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
		[seg addTarget:self action:@selector(liteChanged:) forControlEvents:UIControlEventValueChanged];
		UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[head, seg]];
		column.axis = UILayoutConstraintAxisVertical;
		column.spacing = 10;
		column.translatesAutoresizingMaskIntoConstraints = NO;
		[cell.contentView addSubview:column];
		UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[icon.widthAnchor constraintEqualToConstant:29],
			[column.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
			[column.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[column.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
			[column.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
		]];
	}
	OMCStyleCell(cell);
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	((UILabel *)[cell.contentView viewWithTag:2]).text = OMCLiteStatus();
	NSInteger mode = OMCLiteMode();
	((UISegmentedControl *)[cell.contentView viewWithTag:3]).selectedSegmentIndex = mode == 0 ? 0 : (mode == 1 ? 2 : 1);
	return cell;
}

// Group row: [icon] Phone                 ✓ 9 · ⚠ 1  ⌄
- (UITableViewCell *)groupCell:(NSDictionary *)row {
	UITableViewCell *cell = [self.table dequeueReusableCellWithIdentifier:@"group"]
		?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"group"];
	OMCStyleCell(cell);
	NSDictionary *g = row[@"group"];
	NSUInteger ok = 0, warn = 0, bad = 0;
	for (NSDictionary *c in g[@"checks"]) {
		NSString *s = c[@"status"];
		if ([s isEqualToString:@"bad"]) bad++; else if ([s isEqualToString:@"warn"]) warn++; else if ([s isEqualToString:@"ok"]) ok++;
	}
	NSString *worst = bad ? @"bad" : (warn ? @"warn" : @"ok");
	cell.textLabel.text = g[@"title"];
	cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
	cell.imageView.image = OMCIcon(row[@"icon"], nil);
	NSMutableArray *parts = [NSMutableArray array];
	if (bad) [parts addObject:[NSString stringWithFormat:L(@"GROUP_BAD"), (unsigned long)bad]];
	if (warn) [parts addObject:[NSString stringWithFormat:L(@"GROUP_WARN"), (unsigned long)warn]];
	if (!bad && !warn) [parts addObject:ok ? [NSString stringWithFormat:L(@"GROUP_OK"), (unsigned long)ok] : L(@"GROUP_INFO")];
	cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
	cell.detailTextLabel.textColor = (bad || warn) ? OMCStatusColor(worst) : [UIColor secondaryLabelColor];
	BOOL open = [self.expanded containsObject:g[@"title"]];
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
	UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:open ? @"chevron.up" : @"chevron.down" withConfiguration:cfg]];
	chevron.tintColor = [UIColor tertiaryLabelColor];
	cell.accessoryView = chevron;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", g[@"title"], cell.detailTextLabel.text];
	return cell;
}

// Check row: [status icon]  title             [Fix]
//                            result
//                            what to do (orange / red)
- (UITableViewCell *)checkCell:(NSDictionary *)c nested:(BOOL)nested {
	UITableViewCell *cell = [self.table dequeueReusableCellWithIdentifier:@"check"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"check"];
		UIImageView *icon = [UIImageView new]; icon.tag = 1;
		icon.contentMode = UIViewContentModeCenter;
		UILabel *title = [UILabel new]; title.tag = 2;
		title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
		title.numberOfLines = 0;
		UILabel *value = [UILabel new]; value.tag = 3;
		value.font = [UIFont systemFontOfSize:14];
		value.textColor = [UIColor secondaryLabelColor];
		value.numberOfLines = 0;
		UILabel *fix = [UILabel new]; fix.tag = 4;
		fix.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
		fix.numberOfLines = 0;
		UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[title, value, fix]];
		text.axis = UILayoutConstraintAxisVertical;
		text.spacing = 2;
		UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
		row.alignment = UIStackViewAlignmentTop;
		row.spacing = 12;
		row.translatesAutoresizingMaskIntoConstraints = NO;
		row.tag = 5;
		[cell.contentView addSubview:row];
		UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
		NSLayoutConstraint *lead = [row.leadingAnchor constraintEqualToAnchor:m.leadingAnchor];
		lead.identifier = @"lead";
		[NSLayoutConstraint activateConstraints:@[
			[icon.widthAnchor constraintEqualToConstant:26],
			[icon.heightAnchor constraintEqualToConstant:22],
			lead,
			[row.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
			[row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
		]];
	}
	OMCStyleCell(cell);
	for (NSLayoutConstraint *k in cell.contentView.constraints)   // checks under an opened group sit indented
		if ([k.identifier isEqualToString:@"lead"]) k.constant = nested ? 12 : 0;
	NSString *status = c[@"status"];
	((UIImageView *)[cell.contentView viewWithTag:1]).image = OMCStatusIcon(status, 18);
	((UILabel *)[cell.contentView viewWithTag:2]).text = c[@"title"];
	((UILabel *)[cell.contentView viewWithTag:3]).text = c[@"value"];
	UILabel *fix = (UILabel *)[cell.contentView viewWithTag:4];
	fix.text = c[@"fix"];
	fix.hidden = ![c[@"fix"] length];
	fix.textColor = OMCIsProblem(c) ? OMCStatusColor(status) : [UIColor secondaryLabelColor];

	NSString *actionTitle = OMCActionTitle(c[@"action"]);
	if (actionTitle) {
		UIButton *b = OMCPillButton(actionTitle, nil, OMCAccentColor(), NO, 14);
		b.accessibilityIdentifier = c[@"action"];
		[b addTarget:self action:@selector(actionButton:) forControlEvents:UIControlEventTouchUpInside];
		[b sizeToFit];
		cell.accessoryView = b;
	} else {
		cell.accessoryView = nil;
	}
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = actionTitle ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@. %@", c[@"title"], c[@"value"], c[@"fix"] ?: @""];
	return cell;
}

- (void)actionButton:(UIButton *)sender {
	[self performAction:sender.accessibilityIdentifier];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tableView deselectRowAtIndexPath:ip animated:YES];
	if (self.details) return;
	NSDictionary *row = self.model[ip.section][@"rows"][ip.row];
	NSString *type = row[@"type"];
	if ([type isEqualToString:@"details"]) {
		OMCDiagnosticsController *more = [OMCDiagnosticsController new];
		more.details = YES;
		[self.navigationController pushViewController:more animated:YES];
	} else if ([type isEqualToString:@"group"]) {
		NSString *title = row[@"group"][@"title"];
		if ([self.expanded containsObject:title]) [self.expanded removeObject:title]; else [self.expanded addObject:title];
		[self buildModel];
		[tableView reloadSections:[NSIndexSet indexSetWithIndex:ip.section] withRowAnimation:UITableViewRowAnimationFade];
	} else if ([type isEqualToString:@"cleanNow"]) {
		[self performAction:@"cleanNow"];
	} else if ([type isEqualToString:@"check"]) {
		[self performAction:row[@"check"][@"action"]];
	}
}

- (void)performAction:(NSString *)action {
	if (!action) return;
	if ([action isEqualToString:@"respring"]) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"RESPRING_CONFIRM") message:nil preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"RESPRING") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { OMCRespring(); }]];
		[self presentViewController:alert animated:YES completion:nil];
	} else if ([action isEqualToString:@"perfReset"] || [action isEqualToString:@"clearLog"]) {
		BOOL reset = [action isEqualToString:@"perfReset"];
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(reset ? @"CHK_PERF_RESET_CONFIRM" : @"CHK_PERF_LOG_CONFIRM")
			message:nil preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:L(reset ? @"CHK_PERF_RESET_DO" : @"CHK_PERF_LOG_DO") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
			if (reset) OMCPerfReset(); else OMCClearLog();
			[self runChecks];
		}]];
		[self presentViewController:alert animated:YES completion:nil];
	} else if ([action isEqualToString:@"cleanNow"]) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"CLEAN_RAM_CONFIRM") message:L(@"CLEAN_RAM_NOW_SUB") preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"CLEAN_RAM_DO") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
			NSDate *asked = [NSDate date];
			OMCCleanRamNow();
			// SpringBoard writes the result a moment later: say how many apps it closed
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[self runChecks];
				NSDictionary *last = OMCCleanRamLast();
				NSString *msg;
				if (![last[@"date"] isKindOfClass:[NSDate class]] || [last[@"date"] compare:asked] == NSOrderedAscending) msg = L(@"CLEAN_RAM_NO_REPLY");
				else if ([last[@"closed"] count]) msg = [NSString stringWithFormat:L(@"CLEAN_RAM_RESULT"), (unsigned long)[last[@"closed"] count]];
				else msg = L(@"CLEAN_RAM_NOTHING");
				UIAlertController *done = [UIAlertController alertControllerWithTitle:L(@"CLEAN_RAM_NOW") message:msg preferredStyle:UIAlertControllerStyleAlert];
				[done addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
				[self presentViewController:done animated:YES completion:nil];
			});
		}]];
		[self presentViewController:alert animated:YES completion:nil];
	} else if ([action isEqualToString:@"rescue"]) {
		OMCRescueRestore();
		[self runChecks];
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"OmniCar" message:L(@"RESCUE_RESTORED") preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
	}
}

@end
