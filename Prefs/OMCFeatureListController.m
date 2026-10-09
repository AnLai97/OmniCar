#import "OMCFeatureListController.h"
#import "OMCTheme.h"
#import <Preferences/PSTableCell.h>

@implementation OMCFeatureListController

#pragma mark - Specifiers

- (NSArray *)specifiers {
	if (!_specifiers) {
		OMCLoadStrings();
		NSString *plist = [self.specifier propertyForKey:@"plist"];
		_specifiers = (plist ? [self loadSpecifiersFromPlistName:plist target:self] : nil) ?: [NSMutableArray array];
		OMCLocalizeSpecifiers(_specifiers);
	}
	return _specifiers;
}

#pragma mark - Appearance

- (void)viewDidLoad {
	[super viewDidLoad];
	// Scoped to this controller so the rest of Settings keeps its own look.
	[UISwitch appearanceWhenContainedInInstancesOfClasses:@[[self class]]].onTintColor = OMCAccentColor();
	[UISlider appearanceWhenContainedInInstancesOfClasses:@[[self class]]].minimumTrackTintColor = OMCAccentColor();
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// Pick up values the tweak wrote from another process (e.g. SpringBoard) since last time.
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self reloadSpecifiers];
	// The root page already localized the row's label; it becomes this page's title.
	if (self.specifier.name.length) self.title = self.specifier.name;
	self.table.backgroundColor = OMCBackgroundColor();
	self.table.tintColor = OMCAccentColor();
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
// PSButtonCell actions of feature pages go here (one method per "action" in the feature plist).

@end
