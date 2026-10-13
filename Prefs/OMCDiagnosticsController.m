// Diagnostics page (Support > Diagnostics on the root page): phone, last car screen, each feature's
// On / Off and hook check on this iOS, rescue mode, other CarPlay tweaks. Read only; the share button in
// the nav bar sends the same data plus OmniCar.log (OMCShareReport). Data comes from OMCDiagSections.
#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import "OMCDiagnostics.h"
#import "OMCTheme.h"

@interface PSViewController (OMCDiagnostics)
- (PSSpecifier *)specifier;
@end

@interface OMCDiagnosticsController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@end

@implementation OMCDiagnosticsController

- (void)loadView {
	_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_table.dataSource = self;
	_table.delegate = self;
	_table.allowsSelection = NO;
	self.view = _table;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	OMCLoadStrings();
	self.title = self.specifier.name ?: L(@"DIAGNOSTICS");
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
	_sections = OMCDiagSections();   // car / thermal may have changed since last time
	[_table reloadData];
}

- (void)shareReport:(UIBarButtonItem *)sender {
	OMCShareReport(self, sender);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return _sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [_sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return _sections[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return _sections[section][@"footer"];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	OMCStyleHeaderFooter(view, YES);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	OMCStyleHeaderFooter(view, NO);
}

// Label on the left, value on the right; long values wrap under the label instead of being cut.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"diag"]
		?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"diag"];
	NSDictionary *row = _sections[indexPath.section][@"rows"][indexPath.row];
	OMCStyleCell(cell);
	cell.textLabel.text = row[@"label"];
	cell.detailTextLabel.text = row[@"value"];
	cell.detailTextLabel.numberOfLines = 0;
	cell.detailTextLabel.textAlignment = NSTextAlignmentRight;
	return cell;
}

@end
