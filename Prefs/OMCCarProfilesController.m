// Car profiles page (root page > Car profiles): the switch (OMC_KEY_PROFILES_ON) and every car OmniCar has seen with
// its own split layout, Speed Bubble and startup screen (OMCProfileKeys, switched by the CarPlay process on connect,
// see OMCProfileSwitch in Core/OmniCar.m). Swipe a car to forget it.
#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import "OMCTheme.h"
#import "OmniCar.h"
#import <notify.h>

@interface PSViewController (OMCCarProfiles)
- (PSSpecifier *)specifier;
@end

@interface OMCCarProfilesController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSString *> *keys;   // car keys, most recently seen first
@property (nonatomic, strong) NSDictionary *profiles;
@end

static id OMCProfilePref(NSString *key) {
	return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain));
}

static void OMCProfileStore(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	notify_post("com.anlai.omnicar/prefschanged");
}

@implementation OMCCarProfilesController

- (void)loadView {
	_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_table.dataSource = self;
	_table.delegate = self;
	self.view = _table;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	OMCLoadStrings();
	self.title = self.specifier.name ?: L(@"PROFILES");
	self.view.tintColor = OMCAccentColor();
	_table.backgroundColor = OMCBackgroundColor();
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)reload {
	CFPreferencesAppSynchronize(kPrefsDomain);
	NSDictionary *all = OMCProfilePref(OMC_KEY_PROFILES);
	self.profiles = [all isKindOfClass:[NSDictionary class]] ? all : @{};
	self.keys = [self.profiles.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		NSDate *da = self.profiles[a][@"lastSeen"], *db = self.profiles[b][@"lastSeen"];
		if (![da isKindOfClass:[NSDate class]] || ![db isKindOfClass:[NSDate class]]) return NSOrderedSame;
		return [db compare:da];
	}];
	[self.table reloadData];
}

- (void)enabledChanged:(UISwitch *)sw {
	OMCProfileStore(OMC_KEY_PROFILES_ON, @(sw.on));
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 1 : MAX(1, (NSInteger)self.keys.count);
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
	return section == 1 ? L(@"PROFILES_CARS") : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return section == 0 ? L(@"PROFILES_FOOTER") : (self.keys.count ? L(@"PROFILES_CARS_FOOTER") : nil);
}

- (void)tableView:(UITableView *)tv willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, YES); }
- (void)tableView:(UITableView *)tv willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OMCStyleHeaderFooter(view, NO); }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 0) {
		UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"switch"];
		if (!c) {
			c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"switch"];
			UISwitch *sw = [UISwitch new];
			sw.onTintColor = OMCAccentColor();
			[sw addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
			c.accessoryView = sw;
			c.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		OMCStyleCell(c);
		c.textLabel.text = L(@"PROFILES_ENABLE");
		c.imageView.image = OMCIcon(@"car.2.fill", nil);
		((UISwitch *)c.accessoryView).on = [OMCProfilePref(OMC_KEY_PROFILES_ON) boolValue];
		return c;
	}
	UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"car"]
		?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"car"];
	OMCStyleCell(c);
	c.selectionStyle = UITableViewCellSelectionStyleNone;
	c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	if (!self.keys.count) {
		c.textLabel.text = L(@"PROFILES_NONE");
		c.textLabel.textColor = [UIColor secondaryLabelColor];
		c.detailTextLabel.text = nil;
		c.imageView.image = nil;
		c.accessoryType = UITableViewCellAccessoryNone;
		return c;
	}
	NSString *key = self.keys[ip.row];
	NSDictionary *p = self.profiles[key];
	c.textLabel.textColor = [UIColor labelColor];
	c.textLabel.text = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : key;
	NSDate *seen = p[@"lastSeen"];
	c.detailTextLabel.text = [seen isKindOfClass:[NSDate class]] ? [NSString stringWithFormat:L(@"PROFILES_LAST_SEEN"),
		[NSDateFormatter localizedStringFromDate:seen dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]] : nil;
	c.imageView.image = OMCIcon(@"car.fill", nil);
	c.accessoryType = [OMCProfilePref(OMC_KEY_PROFILE_CURRENT) isEqual:key] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return c;
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
	return ip.section == 1 && self.keys.count;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
	if (style != UITableViewCellEditingStyleDelete || ip.row >= (NSInteger)self.keys.count) return;
	NSString *key = self.keys[ip.row];
	NSMutableDictionary *all = [self.profiles mutableCopy];
	[all removeObjectForKey:key];
	OMCProfileStore(OMC_KEY_PROFILES, all.count ? all : nil);
	if ([OMCProfilePref(OMC_KEY_PROFILE_CURRENT) isEqual:key]) OMCProfileStore(OMC_KEY_PROFILE_CURRENT, nil);
	[self reload];
}

@end
