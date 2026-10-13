#import "OMCDiagnostics.h"
#import "OMCTheme.h"
#import "OmniCar.h"
#import <notify.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

#ifndef TWEAK_VERSION
#define TWEAK_VERSION "dev"
#endif

static NSString *const kLogPath = @"/var/mobile/Documents/OmniCar.log";

static id OMCDiagPref(NSString *key) {
	return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain));
}

static void OMCDiagStore(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
}

#pragma mark - Device

static NSString *OMCDeviceModel(void) {
	struct utsname u;
	uname(&u);
	return @(u.machine);
}

static NSString *OMCSysctlString(const char *name) {
	char buf[64] = {0};
	size_t size = sizeof buf;
	return sysctlbyname(name, buf, &size, NULL, 0) == 0 ? @(buf) : nil;
}

static NSString *OMCJailbreak(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *kind = [fm fileExistsAtPath:@"/var/jb"] ? @"rootless" : @"rootful / roothide";
	if ([fm fileExistsAtPath:@"/var/jb/.installed_dopamine"] || [fm fileExistsAtPath:@"/var/jb/basebin"]) return [kind stringByAppendingString:@" (Dopamine)"];
	if ([fm fileExistsAtPath:@"/var/jb/.installed_palera1n"] || [fm fileExistsAtPath:@"/cores/binpack"]) return [kind stringByAppendingString:@" (palera1n)"];
	return kind;
}

static NSString *OMCThermal(void) {
	switch ([NSProcessInfo processInfo].thermalState) {
		case NSProcessInfoThermalStateNominal: return L(@"DIAG_THERMAL_NOMINAL");
		case NSProcessInfoThermalStateFair: return L(@"DIAG_THERMAL_FAIR");
		case NSProcessInfoThermalStateSerious: return L(@"DIAG_THERMAL_SERIOUS");
		case NSProcessInfoThermalStateCritical: return L(@"DIAG_THERMAL_CRITICAL");
	}
	return @"?";
}

#pragma mark - Features

// Feature key prefix -> name on the root page: every Feature*.plist (featureLabel + its first switch
// "<prefix>Enabled"), plus App Bridge whose page is the "Apps on the car screen" row.
static NSDictionary<NSString *, NSString *> *OMCFeatureNames(void) {
	NSMutableDictionary *names = [NSMutableDictionary dictionaryWithObject:L(@"APPS") forKey:@"appBridge"];
	NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(@"OMCRootListController")];
	for (NSString *path in [bundle pathsForResourcesOfType:@"plist" inDirectory:nil]) {
		if (![path.lastPathComponent hasPrefix:@"Feature"]) continue;
		NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
		if (!plist[@"featureLabel"]) continue;
		for (NSDictionary *item in plist[@"items"]) {
			NSString *key = item[@"key"];
			if (![item[@"cell"] isEqualToString:@"PSSwitchCell"] || ![key hasSuffix:@"Enabled"]) continue;
			names[[key substringToIndex:key.length - 7]] = L(plist[@"featureLabel"]);
			break;
		}
	}
	return names;
}

NSString *OMCFeatureDisplayName(NSString *prefix) {
	return OMCFeatureNames()[prefix] ?: prefix;
}

static BOOL OMCFeatureOn(NSString *prefix) {
	id value = OMCDiagPref([prefix stringByAppendingString:@"Enabled"]);
	return value ? [value boolValue] : YES;
}

// OMCCheckHooks results ("diagHooks.SplitScreen@CarPlay" -> {ios, total, missing}), by dylib name.
static NSDictionary<NSString *, NSArray<NSDictionary *> *> *OMCHookResults(void) {
	NSMutableDictionary *byFeature = [NSMutableDictionary dictionary];
	NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
	for (NSString *key in keys) {
		if (![key hasPrefix:OMC_KEY_DIAG_HOOKS]) continue;
		NSDictionary *value = OMCDiagPref(key);
		NSArray *parts = [[key substringFromIndex:OMC_KEY_DIAG_HOOKS.length] componentsSeparatedByString:@"@"];
		if (![value isKindOfClass:[NSDictionary class]] || parts.count != 2) continue;
		NSMutableDictionary *entry = [value mutableCopy];
		entry[@"process"] = parts[1];
		byFeature[parts[0]] = [(byFeature[parts[0]] ?: @[]) arrayByAddingObject:entry];
	}
	return byFeature;
}

#pragma mark - Car

static NSString *OMCCarField(NSDictionary *car, NSArray<NSString *> *names) {
	for (NSString *group in @[@"configuration", @"session"]) {
		NSDictionary *props = car[group];
		if (![props isKindOfClass:[NSDictionary class]]) continue;
		for (NSString *name in names) {
			NSString *v = props[name];
			if ([v isKindOfClass:[NSString class]] && v.length && ![v isEqualToString:@"nil"] && ![v isEqualToString:@"(null)"]) return v;
		}
	}
	return nil;
}

// Wired / wireless from whatever this iOS calls it (CarKit property names change between versions).
static NSString *OMCCarConnection(NSDictionary *car) {
	for (NSString *group in @[@"session", @"configuration"]) {
		NSDictionary *props = car[group];
		if (![props isKindOfClass:[NSDictionary class]]) continue;
		for (NSString *name in props) {
			NSString *lower = name.lowercaseString, *v = [props[name] description].lowercaseString;
			if ([lower containsString:@"wireless"] && ([v isEqualToString:@"1"] || [v isEqualToString:@"0"]))
				return L([v isEqualToString:@"1"] ? @"DIAG_CAR_WIRELESS" : @"DIAG_CAR_WIRED");
			if ([lower containsString:@"wired"] && ([v isEqualToString:@"1"] || [v isEqualToString:@"0"]))
				return L([v isEqualToString:@"1"] ? @"DIAG_CAR_WIRED" : @"DIAG_CAR_WIRELESS");
			if ([lower containsString:@"transport"]) {
				if ([v containsString:@"wifi"] || [v containsString:@"wireless"] || [v containsString:@"wi-fi"]) return L(@"DIAG_CAR_WIRELESS");
				if ([v containsString:@"usb"] || [v containsString:@"wired"]) return L(@"DIAG_CAR_WIRED");
			}
		}
	}
	return L(@"DIAG_UNKNOWN");
}

static CGSize OMCSizeFromString(NSString *s) {
	NSArray *p = [s componentsSeparatedByString:@"x"];
	return p.count == 2 ? CGSizeMake([p[0] doubleValue], [p[1] doubleValue]) : CGSizeZero;
}

static NSString *OMCRatio(CGSize s) {
	long w = lround(MAX(s.width, s.height)), h = lround(MIN(s.width, s.height));
	if (w <= 0 || h <= 0) return @"?";
	long a = w, b = h;
	while (b) { long t = a % b; a = b; b = t; }
	long rw = w / a, rh = h / a;
	NSString *decimal = [NSString stringWithFormat:@"%.2f:1", (double)w / h];
	return rw <= 32 ? [NSString stringWithFormat:@"%ld:%ld (%@)", rw, rh, decimal] : decimal;
}

// Startup video that fills the car screen without wasting decode time: the smallest standard size at
// least as wide as the screen in pixels.
static NSString *OMCVideoHint(CGSize px) {
	CGFloat w = MAX(px.width, px.height);
	if (w <= 0) return @"?";
	if (w <= 854) return @"480p (854×480)";
	if (w <= 1280) return @"720p (1280×720)";
	return @"1080p (1920×1080)";
}

static NSString *OMCPretty(NSString *size) {
	return [size stringByReplacingOccurrencesOfString:@"x" withString:@"×"];
}

#pragma mark - Conflicts

static NSString *OMCSquash(NSString *s) {
	NSCharacterSet *drop = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
	return [[s.lowercaseString componentsSeparatedByCharactersInSet:drop] componentsJoinedByString:@""];
}

// Installed dpkg packages: @{@"id", @"name", @"version"}.
static NSArray<NSDictionary *> *OMCInstalledPackages(void) {
	NSString *status = [NSString stringWithContentsOfFile:ROOT_PATH_NS(@"/var/lib/dpkg/status") encoding:NSUTF8StringEncoding error:nil];
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *para in [status componentsSeparatedByString:@"\n\n"]) {
		NSMutableDictionary *fields = [NSMutableDictionary dictionary];
		for (NSString *line in [para componentsSeparatedByString:@"\n"]) {
			NSRange colon = [line rangeOfString:@": "];
			if (colon.location == NSNotFound || [line hasPrefix:@" "]) continue;
			fields[[line substringToIndex:colon.location]] = [line substringFromIndex:NSMaxRange(colon)];
		}
		if (!fields[@"Package"] || ![fields[@"Status"] hasSuffix:@" installed"]) continue;
		[out addObject:@{@"id": fields[@"Package"], @"name": fields[@"Name"] ?: fields[@"Package"], @"version": fields[@"Version"] ?: @"?"}];
	}
	[out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"id"] compare:b[@"id"]]; }];
	return out;
}

NSArray<NSDictionary *> *OMCConflictingTweaks(void) {
	// display name, what its package / dylib name contains once lowercased without punctuation
	NSArray<NSArray<NSString *> *> *known = @[@[@"CarBridge", @"carbridge"], @[@"DuoDash", @"duodash"],
		@[@"TrueDash", @"truedash"], @[@"CarPlayEnable", @"carplayenable"]];
	NSMutableArray<NSString *> *dylibs = [NSMutableArray array];
	for (NSString *dir in @[ROOT_PATH_NS(@"/Library/MobileSubstrate/DynamicLibraries"), ROOT_PATH_NS(@"/usr/lib/TweakInject")]) {
		for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil])
			if ([file.pathExtension isEqualToString:@"dylib"]) [dylibs addObject:OMCSquash(file.stringByDeletingPathExtension)];
	}
	NSMutableArray<NSString *> *packages = [NSMutableArray array];
	for (NSDictionary *p in OMCInstalledPackages()) [packages addObject:[OMCSquash(p[@"id"]) stringByAppendingFormat:@" %@", OMCSquash(p[@"name"])]];

	NSMutableArray *out = [NSMutableArray array];
	for (NSArray<NSString *> *k in known) {
		BOOL active = NO, installed = NO;
		for (NSString *d in dylibs) if ([d containsString:k[1]]) { active = YES; break; }
		for (NSString *p in packages) if ([p containsString:k[1]]) { installed = YES; break; }
		if (active || installed) [out addObject:@{@"name": k[0], @"active": @(active)}];
	}
	return out;
}

#pragma mark - Rescue

NSArray<NSString *> *OMCRescueFeatures(void) {
	NSArray *list = OMCDiagPref(OMC_KEY_RESCUE);
	if (![list isKindOfClass:[NSArray class]]) return @[];
	// A feature switched back on by hand is no longer "off by rescue" (CarPlay drops it on its next start).
	NSMutableArray *off = [NSMutableArray array];
	for (NSString *f in list) if ([f isKindOfClass:[NSString class]] && !OMCFeatureOn(f)) [off addObject:f];
	return off;
}

void OMCRescueRestore(void) {
	for (NSString *f in OMCRescueFeatures()) OMCDiagStore([f stringByAppendingString:@"Enabled"], @YES);
	OMCDiagStore(OMC_KEY_RESCUE, nil);
	OMCDiagStore(OMC_KEY_RESCUE_DATE, nil);
	CFPreferencesAppSynchronize(kPrefsDomain);
	notify_post("com.anlai.omnicar/prefschanged");
}

#if OMC_AUTOTEST
NSDictionary *OMCAutoTestState(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	NSDictionary *d = OMCDiagPref(OMC_KEY_AUTOTEST);
	return [d isKindOfClass:[NSDictionary class]] ? d : nil;
}

NSArray<NSDictionary *> *OMCAutoTestSuites(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	NSMutableArray *out = [NSMutableArray array];
	NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
	for (NSString *key in keys) {
		if (![key hasPrefix:OMC_KEY_AUTOTEST_AVAIL]) continue;
		NSString *suite = [key substringFromIndex:OMC_KEY_AUTOTEST_AVAIL.length];
		NSDictionary *v = OMCDiagPref(key);
		[out addObject:@{@"suite": suite, @"name": OMCFeatureDisplayName(suite),
			@"process": [v isKindOfClass:[NSDictionary class]] ? v[@"process"] ?: @"?" : @"?"}];
	}
	// By name, like the feature rows
	[out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCompare:b[@"name"]]; }];
	return out;
}

void OMCAutoTestStart(NSArray<NSString *> *suites) {
	OMCDiagStore(OMC_KEY_AUTOTEST, @{@"state": @"running", @"run": [NSDate date], @"suites": suites ?: @[], @"suite": @0, @"step": @0,
		@"inStep": @NO, @"results": @[], @"ios": [UIDevice currentDevice].systemVersion});
	CFPreferencesAppSynchronize(kPrefsDomain);
	notify_post(OMC_DARWIN_AUTOTEST);
}

void OMCAutoTestStop(void) {
	NSMutableDictionary *d = [OMCAutoTestState() mutableCopy];
	if (!d) return;
	d[@"state"] = @"stopped";
	OMCDiagStore(OMC_KEY_AUTOTEST, d);
	CFPreferencesAppSynchronize(kPrefsDomain);
	notify_post(OMC_DARWIN_AUTOTEST);
}
#endif

static NSString *OMCDateText(NSDate *date) {
	if (![date isKindOfClass:[NSDate class]]) return @"?";
	return [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
}

#pragma mark - Sections

static NSDictionary *OMCRow(NSString *label, NSString *value) {
	return @{@"label": label, @"value": value ?: @"—"};
}

NSArray<NSDictionary *> *OMCDiagSections(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	NSMutableArray *sections = [NSMutableArray array];

	// Phone
	NSString *build = OMCSysctlString("kern.osversion");
	NSString *ios = [UIDevice currentDevice].systemVersion;
	[sections addObject:@{@"title": L(@"DIAG_DEVICE"), @"rows": @[
		OMCRow(@"OmniCar", @TWEAK_VERSION),
		OMCRow(@"iOS", build ? [NSString stringWithFormat:@"%@ (%@)", ios, build] : ios),
		OMCRow(L(@"DIAG_MODEL"), OMCDeviceModel()),
		OMCRow(L(@"DIAG_JAILBREAK"), OMCJailbreak()),
		OMCRow(L(@"DIAG_THERMAL"), OMCThermal()),
	]}];

	// Car screen (written by CarPlay on the last connection)
	NSDictionary *car = OMCDiagPref(OMC_KEY_DIAG_CAR);
	if ([car isKindOfClass:[NSDictionary class]] && car[@"pixels"]) {
		CGSize px = OMCSizeFromString(car[@"pixels"]);
		NSString *name = OMCCarField(car, @[@"modelName", @"name", @"vehicleName", @"accessoryName", @"model"]);
		NSString *maker = OMCCarField(car, @[@"manufacturerName", @"manufacturer", @"vehicleManufacturer", @"accessoryManufacturer"]);
		if (maker && name && ![name localizedCaseInsensitiveContainsString:maker]) name = [NSString stringWithFormat:@"%@ %@", maker, name];
		[sections addObject:@{@"title": L(@"DIAG_CAR"), @"rows": @[
			OMCRow(L(@"DIAG_CAR_NAME"), name ?: maker ?: L(@"DIAG_UNKNOWN")),
			OMCRow(L(@"DIAG_CAR_CONNECTION"), OMCCarConnection(car)),
			OMCRow(L(@"DIAG_CAR_RESOLUTION"), [NSString stringWithFormat:@"%@ px", OMCPretty(car[@"pixels"])]),
			OMCRow(L(@"DIAG_CAR_POINTS"), [NSString stringWithFormat:@"%@ pt @%@x", OMCPretty(car[@"points"] ?: @"?"), car[@"scale"] ?: @"?"]),
			OMCRow(L(@"DIAG_CAR_RATIO"), OMCRatio(px)),
			OMCRow(L(@"DIAG_CAR_FPS"), [NSString stringWithFormat:@"%@", car[@"maxFPS"] ?: @"?"]),
			OMCRow(L(@"DIAG_CAR_VIDEO"), OMCVideoHint(px)),
			OMCRow(L(@"DIAG_CAR_LAST"), OMCDateText(car[@"date"])),
		], @"footer": L(@"DIAG_CAR_FOOTER")}];
	} else {
		[sections addObject:@{@"title": L(@"DIAG_CAR"), @"rows": @[OMCRow(L(@"DIAG_CAR_NAME"), L(@"DIAG_CAR_NONE"))],
			@"footer": L(@"DIAG_CAR_NONE_FOOTER")}];
	}

	// Features: on / off, installed, hooks found on this iOS
	NSDictionary *names = OMCFeatureNames();
	NSDictionary *hooks = OMCHookResults();
	NSMutableArray *rows = [NSMutableArray array];
	NSMutableArray<NSString *> *notes = [NSMutableArray array];
	BOOL master = OMCEnabled();
	for (NSString *prefix in [names.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		NSString *dylibName = [[prefix substringToIndex:1].uppercaseString stringByAppendingString:[prefix substringFromIndex:1]];
		NSString *dylib = [NSString stringWithFormat:@"%@/OmniCar%@.dylib", ROOT_PATH_NS(@"/Library/MobileSubstrate/DynamicLibraries"), dylibName];
		NSMutableArray<NSString *> *parts = [NSMutableArray array];
		if (![[NSFileManager defaultManager] fileExistsAtPath:dylib]) [parts addObject:L(@"DIAG_NOT_INSTALLED")];
		else [parts addObject:L(master && OMCFeatureOn(prefix) ? @"FEATURE_ON" : @"FEATURE_OFF")];
		NSUInteger total = 0, missing = 0;
		for (NSDictionary *entry in hooks[dylibName]) {
			NSArray *miss = entry[@"missing"];
			total += [entry[@"total"] unsignedIntegerValue];
			missing += miss.count;
			if (miss.count) [notes addObject:[NSString stringWithFormat:@"%@ (%@, iOS %@): %@", names[prefix], entry[@"process"],
				entry[@"ios"], [miss componentsJoinedByString:@", "]]];
		}
		if (total) [parts addObject:missing ? [NSString stringWithFormat:L(@"DIAG_HOOKS_MISSING"), (unsigned long)missing, (unsigned long)total]
			: [NSString stringWithFormat:L(@"DIAG_HOOKS_OK"), (unsigned long)total]];
		[rows addObject:OMCRow(names[prefix], [parts componentsJoinedByString:@" · "])];
	}
	NSString *footer = notes.count ? [NSString stringWithFormat:@"%@\n%@", L(@"DIAG_HOOKS_FOOTER_MISSING"), [notes componentsJoinedByString:@"\n"]]
		: [NSString stringWithFormat:L(@"DIAG_FEATURES_FOOTER"), @TWEAK_VERSION];
	[sections addObject:@{@"title": L(@"FEATURES_GROUP"), @"rows": rows, @"footer": footer}];

	// Rescue mode
	NSArray *rescued = OMCRescueFeatures();
	if (rescued.count) {
		NSMutableArray *r = [NSMutableArray array];
		for (NSString *f in rescued) [r addObject:OMCRow(OMCFeatureDisplayName(f), L(@"DIAG_RESCUED"))];
		[sections addObject:@{@"title": L(@"RESCUE_GROUP"), @"rows": r,
			@"footer": [NSString stringWithFormat:L(@"DIAG_RESCUE_FOOTER"), OMCDateText(OMCDiagPref(OMC_KEY_RESCUE_DATE))]}];
	}

	// Other CarPlay tweaks
	NSMutableArray *c = [NSMutableArray array];
	for (NSDictionary *t in OMCConflictingTweaks())
		[c addObject:OMCRow(t[@"name"], L([t[@"active"] boolValue] ? @"DIAG_CONFLICT_ACTIVE" : @"DIAG_CONFLICT_INSTALLED"))];
	if (!c.count) [c addObject:OMCRow(L(@"DIAG_CONFLICTS_NONE"), @"")];
	[sections addObject:@{@"title": L(@"DIAG_CONFLICTS"), @"rows": c, @"footer": L(@"DIAG_CONFLICTS_FOOTER")}];
	return sections;
}

#pragma mark - Report

static void OMCAppendFile(NSMutableString *out, NSString *title, NSString *path) {
	NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	if (!text) text = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:path] encoding:NSISOLatin1StringEncoding];
	[out appendFormat:@"\n==== %@ (%@) ====\n%@\n", title, path, text.length ? text : @"(empty / not found)"];
}

static NSURL *OMCWriteReport(void) {
	NSMutableString *out = [NSMutableString string];
	NSDateFormatter *df = [NSDateFormatter new];
	df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
	[out appendFormat:@"OmniCar report %@\n", [df stringFromDate:[NSDate date]]];
	[out appendFormat:@"master switch: %@, language: %@\n", OMCEnabled() ? @"on" : @"off", OMCLanguage()];

	for (NSDictionary *section in OMCDiagSections()) {
		[out appendFormat:@"\n== %@ ==\n", section[@"title"]];
		for (NSDictionary *row in section[@"rows"]) [out appendFormat:@"%@: %@\n", row[@"label"], row[@"value"]];
		if ([section[@"footer"] length]) [out appendFormat:@"(%@)\n", section[@"footer"]];
	}

	// Raw car data: CarKit property names differ per iOS, the developer reads them here
	NSDictionary *car = OMCDiagPref(OMC_KEY_DIAG_CAR);
	if ([car isKindOfClass:[NSDictionary class]]) [out appendFormat:@"\n== Car (raw) ==\n%@\n", car];

#if OMC_AUTOTEST
	// Auto test: every step with its result and reason (the split state at each failure is in OmniCar.log)
	NSDictionary *test = OMCAutoTestState();
	if (test[@"results"]) {
		[out appendFormat:@"\n== Auto test (%@, %@, iOS %@) ==\n", test[@"run"], test[@"state"], test[@"ios"]];
		for (NSDictionary *r in test[@"results"])
			[out appendFormat:@"%@ [%@] %@ (%@s)%@%@\n", [r[@"status"] uppercaseString], r[@"suite"], r[@"name"], r[@"seconds"],
				r[@"detail"] ? [@" - " stringByAppendingString:r[@"detail"]] : @"",
				r[@"shot"] ? [NSString stringWithFormat:@" [%@]", r[@"shot"]] : @""];
	}
#endif

	[out appendString:@"\n== Installed packages ==\n"];
	for (NSDictionary *p in OMCInstalledPackages()) [out appendFormat:@"%@ %@ (%@)\n", p[@"id"], p[@"version"], p[@"name"]];

	OMCAppendFile(out, @"OmniCar.log.old", [kLogPath stringByAppendingString:@".old"]);
	OMCAppendFile(out, @"OmniCar.log", kLogPath);

	df.dateFormat = @"yyyyMMdd-HHmm";
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"OmniCar-log-%@.txt", [df stringFromDate:[NSDate date]]]];
	return [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil] ? [NSURL fileURLWithPath:path] : nil;
}

void OMCShareReport(UIViewController *vc, UIBarButtonItem *barItem) {
	NSURL *url = OMCWriteReport();
	if (!url) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"OmniCar" message:L(@"SEND_LOG_FAILED") preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[vc presentViewController:alert animated:YES completion:nil];
		return;
	}
	NSMutableArray *items = [NSMutableArray arrayWithObject:url];
#if OMC_AUTOTEST
	// Dev builds: the auto test's car-screen snapshots ride along (<suite>-<step>-<result>.jpg)
	if (OMCAutoTestState()[@"results"]) {
		NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:OMC_AUTOTEST_DIR error:nil] sortedArrayUsingSelector:@selector(compare:)];
		for (NSString *file in files)
			if ([file.pathExtension isEqualToString:@"jpg"]) [items addObject:[NSURL fileURLWithPath:[OMC_AUTOTEST_DIR stringByAppendingPathComponent:file]]];
	}
#endif
	UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
	UIPopoverPresentationController *pop = share.popoverPresentationController;   // iPad
	if (barItem) pop.barButtonItem = barItem;
	else {
		pop.sourceView = vc.view;
		pop.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
	}
	[vc presentViewController:share animated:YES completion:nil];
}
