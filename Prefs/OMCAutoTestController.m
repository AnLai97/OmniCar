// Developer auto test page (Support > Auto test, only when OMC_AUTOTEST is 1): tick the features to test,
// start / stop, follow the run, read every step's result, and arm the rescue-mode crash test. The runner and
// the test cases live with the features (Core/OMCTest.h); this page only writes the request and reads back.
#import "OMCDiagnostics.h"

#if OMC_AUTOTEST
#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import "OMCTheme.h"

@interface PSViewController (OMCAutoTest)
- (PSSpecifier *)specifier;
@end

typedef NS_ENUM(NSInteger, OMCATSection) { OMCATSuites, OMCATAction, OMCATStatus, OMCATResults, OMCATRescue, OMCATCount };

@interface OMCAutoTestController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *suites;
@property (nonatomic, strong) NSDictionary *run;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation OMCAutoTestController

- (void)loadView {
	_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_table.dataSource = self;
	_table.delegate = self;
	self.view = _table;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	OMCLoadStrings();
	self.title = L(@"AUTOTEST");
	self.view.tintColor = OMCAccentColor();
	_table.backgroundColor = OMCBackgroundColor();
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
	__weak typeof(self) weakSelf = self;
	self.timer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) { [weakSelf reload]; }];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.timer invalidate];
	self.timer = nil;
}

- (void)reload {
	self.suites = OMCAutoTestSuites();
	self.run = OMCAutoTestState();
	[self.table reloadData];
}

- (BOOL)running { return [self.run[@"state"] isEqual:@"running"]; }

#pragma mark - Picked suites (default: all)

- (NSArray<NSString *> *)picked {
	NSArray *p = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)OMC_KEY_AUTOTEST_PICK, kPrefsDomain));
	if ([p isKindOfClass:[NSArray class]]) return p;
	return [self.suites valueForKey:@"suite"];
}

- (void)suiteSwitched:(UISwitch *)sw {
	NSString *suite = self.suites[sw.tag][@"suite"];
	NSMutableArray *p = [[self picked] mutableCopy];
	[p removeObject:suite];
	if (sw.on) [p addObject:suite];
	CFPreferencesSetAppValue((__bridge CFStringRef)OMC_KEY_AUTOTEST_PICK, (__bridge CFPropertyListRef)p, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
}

- (void)startOrStop {
	if ([self running]) { OMCAutoTestStop(); [self reload]; return; }
	NSArray *picked = [self picked];
	NSMutableArray *order = [NSMutableArray array];   // page order, not tick order
	for (NSDictionary *s in self.suites) if ([picked containsObject:s[@"suite"]]) [order addObject:s[@"suite"]];
	if (!order.count) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"AUTOTEST") message:L(@"AUTOTEST_CONFIRM")
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"AUTOTEST_START") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		OMCAutoTestStart(order);
		[self reload];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Rescue-mode test (needs 3 car connections, so it is not a step of the run)

- (void)armCrashTest {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:L(@"CRASH_TEST_TITLE") message:L(@"CRASH_TEST_MESSAGE")
		preferredStyle:UIAlertControllerStyleActionSheet];
	for (NSString *f in @[@"splitScreen", @"startupScreen", @"speedBubble"]) {
		[sheet addAction:[UIAlertAction actionWithTitle:OMCFeatureDisplayName(f) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
			[self setCrashTest:f];
		}]];
	}
	id armed = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)OMC_KEY_CRASH_TEST, kPrefsDomain));
	if (armed) [sheet addAction:[UIAlertAction actionWithTitle:L(@"CRASH_TEST_STOP") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		[self setCrashTest:nil];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	NSIndexPath *ip = [NSIndexPath indexPathForRow:0 inSection:OMCATRescue];
	UITableViewCell *cell = [self.table cellForRowAtIndexPath:ip];
	sheet.popoverPresentationController.sourceView = cell ?: self.table;   // iPad
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectZero;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)setCrashTest:(NSString *)feature {
	CFPreferencesSetAppValue((__bridge CFStringRef)OMC_KEY_CRASH_TEST, (__bridge CFPropertyListRef)feature, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	if (!feature) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"OmniCar" message:L(@"CRASH_TEST_ARMED") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table

- (NSArray *)results { return self.run[@"results"] ?: @[]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return OMCATCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case OMCATSuites: return MAX(1, (NSInteger)self.suites.count);
		case OMCATAction: return 1;
		case OMCATStatus: return self.run ? 2 : 0;
		case OMCATResults: return [self results].count;
		case OMCATRescue: return 1;
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case OMCATSuites: return L(@"AUTOTEST_SUITES");
		case OMCATStatus: return self.run ? L(@"AUTOTEST_LAST") : nil;
		case OMCATResults: return [self results].count ? L(@"AUTOTEST_STEPS") : nil;
		case OMCATRescue: return L(@"RESCUE_GROUP");
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	switch (section) {
		case OMCATSuites: return self.suites.count ? L(@"AUTOTEST_SUITES_FOOTER") : L(@"AUTOTEST_NO_SUITES");
		case OMCATAction: return L(@"AUTOTEST_ACTION_FOOTER");
		case OMCATResults: return [self results].count ? L(@"AUTOTEST_FOOTER") : nil;
		case OMCATRescue: return L(@"CRASH_TEST_MESSAGE");
	}
	return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, YES); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, NO); }

- (UITableViewCell *)cellWithStyle:(UITableViewCellStyle)style id:(NSString *)rid {
	UITableViewCell *c = [self.table dequeueReusableCellWithIdentifier:rid] ?: [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:rid];
	OMCStyleCell(c);
	c.accessoryView = nil;
	c.accessoryType = UITableViewCellAccessoryNone;
	c.selectionStyle = UITableViewCellSelectionStyleNone;
	c.textLabel.textColor = [UIColor labelColor];
	c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	c.detailTextLabel.numberOfLines = 0;
	return c;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == OMCATSuites) {
		UITableViewCell *c = [self cellWithStyle:UITableViewCellStyleSubtitle id:@"suite"];
		if (!self.suites.count) { c.textLabel.text = L(@"AUTOTEST_NO_SUITES_ROW"); c.detailTextLabel.text = nil; return c; }
		NSDictionary *s = self.suites[ip.row];
		c.textLabel.text = s[@"name"];
		c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", s[@"suite"], s[@"process"]];
		UISwitch *sw = [UISwitch new];
		sw.tag = ip.row;
		sw.on = [[self picked] containsObject:s[@"suite"]];
		sw.enabled = ![self running];
		[sw addTarget:self action:@selector(suiteSwitched:) forControlEvents:UIControlEventValueChanged];
		c.accessoryView = sw;
		return c;
	}
	if (ip.section == OMCATAction) {
		UITableViewCell *c = [self cellWithStyle:UITableViewCellStyleDefault id:@"action"];
		c.textLabel.text = L([self running] ? @"AUTOTEST_STOP" : @"AUTOTEST_START");
		c.textLabel.textColor = [self running] ? [UIColor systemRedColor] : [UIColor labelColor];
		c.selectionStyle = UITableViewCellSelectionStyleDefault;
		return c;
	}
	if (ip.section == OMCATStatus) {
		UITableViewCell *c = [self cellWithStyle:UITableViewCellStyleValue1 id:@"status"];
		NSArray *suites = self.run[@"suites"];
		NSUInteger i = [self.run[@"suite"] unsignedIntegerValue];
		if (ip.row == 0) {
			c.textLabel.text = L([NSString stringWithFormat:@"AUTOTEST_STATE_%@", [self.run[@"state"] uppercaseString]]);
			NSString *date = [self.run[@"run"] isKindOfClass:[NSDate class]]
				? [NSDateFormatter localizedStringFromDate:self.run[@"run"] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @"";
			c.detailTextLabel.text = [self running] && i < suites.count
				? [NSString stringWithFormat:@"%@ · %@ %ld", OMCFeatureDisplayName(suites[i]), L(@"AUTOTEST_STEP"), (long)[self.run[@"step"] integerValue] + 1]
				: date;
		} else {
			NSUInteger pass = 0, fail = 0, skip = 0;
			for (NSDictionary *r in [self results]) {
				NSString *st = r[@"status"];
				if ([st isEqualToString:@"pass"]) pass++; else if ([st isEqualToString:@"skip"]) skip++; else fail++;
			}
			c.textLabel.text = L(@"AUTOTEST_RESULT");
			c.detailTextLabel.text = [NSString stringWithFormat:L(@"AUTOTEST_COUNTS"), (unsigned long)pass, (unsigned long)fail, (unsigned long)skip];
			c.detailTextLabel.textColor = fail ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];
		}
		return c;
	}
	if (ip.section == OMCATResults) {
		UITableViewCell *c = [self cellWithStyle:UITableViewCellStyleSubtitle id:@"result"];
		NSDictionary *r = [self results][ip.row];
		NSString *st = r[@"status"];
		NSDictionary *mark = @{@"pass": @"✓", @"fail": @"✗", @"crash": @"✗", @"skip": @"–"};
		c.textLabel.text = [NSString stringWithFormat:@"%@ %@ · %@", mark[st] ?: @"?", OMCFeatureDisplayName(r[@"suite"]), r[@"name"]];
		c.textLabel.numberOfLines = 0;
		c.textLabel.textColor = [st isEqualToString:@"pass"] ? [UIColor labelColor]
			: ([st isEqualToString:@"skip"] ? [UIColor secondaryLabelColor] : [UIColor systemRedColor]);
		NSString *detail = r[@"detail"];
		NSRange cut = [detail rangeOfString:@" || "];   // the split state after "||" is for the log, not this list
		c.detailTextLabel.text = cut.location != NSNotFound ? [detail substringToIndex:cut.location] : detail;
		return c;
	}
	UITableViewCell *c = [self cellWithStyle:UITableViewCellStyleDefault id:@"rescue"];
	c.textLabel.text = L(@"CRASH_TEST_TITLE");
	c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	c.selectionStyle = UITableViewCellSelectionStyleDefault;
	return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tableView deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == OMCATAction) [self startOrStop];
	else if (ip.section == OMCATRescue) [self armCrashTest];
}

@end
#endif
