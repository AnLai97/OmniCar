// Diagnostics page (Support > Diagnostics on the root page): a health check anyone can read. A summary card
// ("Everything looks good" / "2 things need attention"), then the phone, CarPlay and each feature as rows with
// a status icon, the result in plain words and what to do when something is off; rows with a fix the page can do
// itself (respring, turn rescued features back on) are tappable. Raw values live one level down under
// "Technical details" (same class, details = YES). The share button sends everything plus OmniCar.log.
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
	if (self.details) self.sections = OMCDiagSections();
	else {
		self.groups = OMCDiagChecks();
		self.checkedAt = [NSDate date];
		self.table.tableHeaderView = [self summaryView];
	}
	[self.table reloadData];
}

- (void)shareReport:(UIBarButtonItem *)sender {
	OMCShareReport(self, sender);
}

#pragma mark - Summary card

// One line verdict over every check, colored by the worst status, with "Check again"
- (UIView *)summaryView {
	NSDictionary *sum = OMCDiagSummary(self.groups);
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 112)];
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

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text, again]];
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 14;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	[card addSubview:row];

	UILayoutGuide *m = container.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[card.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
		[card.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
		[card.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
		[card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
		[icon.widthAnchor constraintEqualToConstant:36],
		[again.widthAnchor constraintEqualToConstant:36],
		[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
		[row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
		[row.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
	]];
	return container;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.details ? self.sections.count : self.groups.count + 1;   // + "Technical details"
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.details) return [self.sections[section][@"rows"] count];
	return section < (NSInteger)self.groups.count ? [self.groups[section][@"checks"] count] : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (self.details) return self.sections[section][@"title"];
	return section < (NSInteger)self.groups.count ? self.groups[section][@"title"] : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (self.details) return self.sections[section][@"footer"];
	return section == (NSInteger)self.groups.count ? L(@"CHK_FOOTER") : nil;
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
	if (ip.section == (NSInteger)self.groups.count) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"more"]
			?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"more"];
		OMCStyleCell(cell);
		cell.textLabel.text = L(@"DIAG_DETAILS");
		cell.imageView.image = OMCIcon(@"list.bullet.rectangle", nil);
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	// Check row: [status icon]  title             (action ›)
	//                            result
	//                            what to do (orange / red)
	NSDictionary *c = self.groups[ip.section][@"checks"][ip.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"check"];
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
		[cell.contentView addSubview:row];
		UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
		[NSLayoutConstraint activateConstraints:@[
			[icon.widthAnchor constraintEqualToConstant:26],
			[icon.heightAnchor constraintEqualToConstant:22],
			[row.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
			[row.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
			[row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
			[row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
		]];
	}
	OMCStyleCell(cell);
	NSString *status = c[@"status"];
	((UIImageView *)[cell.contentView viewWithTag:1]).image = OMCStatusIcon(status, 18);
	((UILabel *)[cell.contentView viewWithTag:2]).text = c[@"title"];
	((UILabel *)[cell.contentView viewWithTag:3]).text = c[@"value"];
	UILabel *fix = (UILabel *)[cell.contentView viewWithTag:4];
	fix.text = c[@"fix"];
	fix.hidden = ![c[@"fix"] length];
	fix.textColor = ([status isEqualToString:@"warn"] || [status isEqualToString:@"bad"]) ? OMCStatusColor(status) : [UIColor secondaryLabelColor];
	cell.accessoryType = c[@"action"] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	cell.selectionStyle = c[@"action"] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@. %@", c[@"title"], c[@"value"], c[@"fix"] ?: @""];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tableView deselectRowAtIndexPath:ip animated:YES];
	if (self.details) return;
	if (ip.section == (NSInteger)self.groups.count) {
		OMCDiagnosticsController *more = [OMCDiagnosticsController new];
		more.details = YES;
		[self.navigationController pushViewController:more animated:YES];
		return;
	}
	NSString *action = self.groups[ip.section][@"checks"][ip.row][@"action"];
	if ([action isEqualToString:@"respring"]) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"RESPRING_CONFIRM") message:nil preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"RESPRING") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { OMCRespring(); }]];
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
