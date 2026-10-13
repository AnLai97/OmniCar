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

#pragma mark - Health checks

// Feature contracts (keys, folders) - macros only, safe to include here
#import "../Features/AppBridge/AppBridge.h"
#import "../Features/SplitScreen/SplitScreen.h"
#import "../Features/SpeedBubble/SpeedBubble.h"
#import "../Features/StartupScreen/StartupScreen.h"
#import <objc/message.h>
#import <dlfcn.h>
#import <spawn.h>

static NSDictionary *OMCCheck(NSString *title, NSString *status, NSString *value, NSString *fix, NSString *action) {
	NSMutableDictionary *d = [@{@"title": title, @"status": status, @"value": value ?: @""} mutableCopy];
	if (fix.length) d[@"fix"] = fix;
	if (action) d[@"action"] = action;
	return d;
}

// A check whose fix is something the user does for performance (listed by Optimize as "you can also")
static NSDictionary *OMCPerf(NSDictionary *check) {
	NSMutableDictionary *d = [check mutableCopy];
	d[@"perf"] = @YES;
	return d;
}

static NSString *OMCTimeText(NSDate *date) {
	if (![date isKindOfClass:[NSDate class]]) return @"?";
	BOOL today = [[NSCalendar currentCalendar] isDateInToday:date];
	return [NSDateFormatter localizedStringFromDate:date dateStyle:today ? NSDateFormatterNoStyle : NSDateFormatterShortStyle
		timeStyle:NSDateFormatterShortStyle];
}

static BOOL OMCAppInstalled(NSString *bid) {
	Class ws = NSClassFromString(@"LSApplicationWorkspace");
	id workspace = [ws respondsToSelector:NSSelectorFromString(@"defaultWorkspace")] ? ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"defaultWorkspace")) : nil;
	SEL sel = NSSelectorFromString(@"applicationIsInstalled:");
	if (![workspace respondsToSelector:sel]) return YES;   // cannot tell: do not warn
	return ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, sel, bid);
}

// 1 = a car is connected now, 0 = none, -1 = cannot tell from Settings
static int OMCCarConnectedNow(void) {
	Class dev = NSClassFromString(@"AVExternalDevice");
	SEL sel = NSSelectorFromString(@"currentCarPlayExternalDevice");
	if (![dev respondsToSelector:sel]) return -1;
	return ((id (*)(id, SEL))objc_msgSend)(dev, sel) ? 1 : 0;
}

static NSArray<NSString *> *OMCInstalledDylibs(void) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ROOT_PATH_NS(@"/Library/MobileSubstrate/DynamicLibraries") error:nil])
		if ([f hasPrefix:@"OmniCar"] && [f.pathExtension isEqualToString:@"dylib"]) [out addObject:[f.stringByDeletingPathExtension substringFromIndex:7]];
	return [out sortedArrayUsingSelector:@selector(compare:)];
}

static NSDictionary *OMCLoaded(NSString *dylib, NSString *process) {
	NSDictionary *d = OMCDiagPref([NSString stringWithFormat:@"%@%@@%@", OMC_KEY_DIAG_LOADED, dylib, process]);
	return [d isKindOfClass:[NSDictionary class]] ? d : nil;
}

// Was this dylib loaded into `process` with the installed build? @"ok" / @"old" / @"none"; latest load date out.
static NSString *OMCLoadState(NSArray<NSString *> *dylibs, NSString *process, NSDate **latest) {
	BOOL any = NO, old = NO, missing = NO;
	for (NSString *d in dylibs) {
		NSDictionary *l = OMCLoaded(d, process);
		if (!l) { missing = YES; continue; }
		any = YES;
		if (![l[@"version"] isEqual:@TWEAK_VERSION]) old = YES;
		if (latest && (!*latest || [l[@"date"] compare:*latest] == NSOrderedDescending)) *latest = l[@"date"];
	}
	if (!any) return @"none";
	return (old || missing) ? @"old" : @"ok";
}

static NSString *OMCStartupVideo(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *name = OMCDiagPref(SS_KEY_VIDEO_NAME);
	if ([name isKindOfClass:[NSString class]] && name.length && [fm fileExistsAtPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name]]) return name;
	for (NSString *f in [[fm contentsOfDirectoryAtPath:SS_VIDEOS_DIR error:nil] sortedArrayUsingSelector:@selector(compare:)])
		if (![f hasPrefix:@"."]) return f;
	return nil;
}

static unsigned long long OMCLogBytes(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	return [fm attributesOfItemAtPath:kLogPath error:nil].fileSize + [fm attributesOfItemAtPath:[kLogPath stringByAppendingString:@".old"] error:nil].fileSize;
}

// The most likely reason CarPlay was slow on that drive, as advice (heat, Low Power Mode, memory, other tweaks, CPU)
static NSString *OMCPerfCause(NSDictionary *perf) {
	NSInteger room = [perf[@"availMinMB"] integerValue] ?: [perf[@"sysFreeMinMB"] integerValue];
	NSUInteger tweaks = [perf[@"tweaks"] count];
	if ([perf[@"thermalMax"] integerValue] >= NSProcessInfoThermalStateSerious) return L(@"CHK_PERF_HEAT_FIX");
	if ([perf[@"lowPower"] boolValue]) return L(@"CHK_LOWPOWER_FIX");
	if (perf[@"memMB"] && room < 200) return L(@"CHK_PERF_RAM_FIX");
	if (tweaks >= 4) return [NSString stringWithFormat:L(@"CHK_PERF_TWEAKS_FIX"), (unsigned long)tweaks];
	if ([perf[@"cpuAvg"] integerValue] >= 30) return L(@"CHK_PERF_CPU_FIX");
	return L(@"CHK_PERF_GENERIC_FIX");
}

// Performance on the last drive (OMC_KEY_DIAG_PERF, measured by the CarPlay process)
static NSArray<NSDictionary *> *OMCPerfChecks(BOOL connected) {
	NSMutableArray *out = [NSMutableArray array];
	NSDictionary *perf = OMCDiagPref(OMC_KEY_DIAG_PERF);
	if (![perf isKindOfClass:[NSDictionary class]] || ![perf[@"start"] isKindOfClass:[NSDate class]]) {
		[out addObject:OMCCheck(L(@"CHK_PERF_DRIVE"), @"info", L(@"CHK_CP_NONE"), L(@"CHK_PERF_NONE_FIX"), nil)];
	} else {
		long minutes = MAX(1, lround([perf[@"seconds"] doubleValue] / 60));
		BOOL live = connected && [perf[@"updated"] isKindOfClass:[NSDate class]] && -[perf[@"updated"] timeIntervalSinceNow] < 90;
		NSString *drive = live ? [NSString stringWithFormat:L(@"CHK_PERF_LIVE"), minutes]
			: [NSString stringWithFormat:L(@"CHK_PERF_AT"), OMCTimeText(perf[@"start"]), minutes];
		[out addObject:OMCCheck(L(@"CHK_PERF_DRIVE"), @"info", drive, L(@"CHK_PERF_RESET"), @"perfReset")];
		NSString *cause = OMCPerfCause(perf);

		// Smoothness: frames the car screen's display link fired late (main thread busy)
		double frames = [perf[@"frames"] doubleValue], late = [perf[@"late"] doubleValue];
		if (frames < 300) [out addObject:OMCCheck(L(@"CHK_PERF_SMOOTH"), @"info", L(@"CHK_PERF_FEW"), nil, nil)];
		else {
			double pct = late * 100 / frames;
			NSString *status = pct < 3 ? @"ok" : (pct < 10 ? @"warn" : @"bad");
			NSString *v = [NSString stringWithFormat:L(@"CHK_PERF_SMOOTH_VALUE"), pct, perf[@"fps"] ?: @"?", [perf[@"worstMs"] longValue]];
			[out addObject:OMCCheck(L(@"CHK_PERF_SMOOTH"), status, v, [status isEqualToString:@"ok"] ? nil : cause, nil)];
		}

		// Touch response: main thread stuck >= 0.5 s (hangs) / >= 2 s (freezes)
		long hangs = [perf[@"hangs"] longValue], freezes = [perf[@"freezes"] longValue];
		NSString *hangStatus = !hangs ? @"ok" : ((freezes || hangs > 10) ? @"bad" : @"warn");
		NSString *hangValue = hangs ? [NSString stringWithFormat:L(@"CHK_PERF_HANG_VALUE"), hangs, [perf[@"hangMaxMs"] doubleValue] / 1000] : L(@"CHK_PERF_HANG_NONE");
		[out addObject:OMCCheck(L(@"CHK_PERF_HANG"), hangStatus, hangValue,
			hangs ? [NSString stringWithFormat:L(@"CHK_PERF_HANG_FIX"), cause] : nil, nil)];

		if (perf[@"cpuAvg"]) {
			long avg = [perf[@"cpuAvg"] longValue];
			NSString *status = avg < 30 ? @"ok" : (avg < 60 ? @"warn" : @"bad");
			[out addObject:OMCCheck(L(@"CHK_PERF_CPU"), status, [NSString stringWithFormat:L(@"CHK_PERF_CPU_VALUE"), avg, [perf[@"cpuMax"] longValue]],
				[status isEqualToString:@"ok"] ? nil : L(@"CHK_PERF_CPU_FIX"), nil)];

			// Memory: room CarPlay had left before iOS kills it (the phone's free RAM when iOS does not say)
			long room = [perf[@"availMinMB"] longValue] ?: [perf[@"sysFreeMinMB"] longValue];
			NSString *memStatus = !room ? @"info" : (room < 100 ? @"bad" : (room < 200 ? @"warn" : @"ok"));
			NSString *memValue = room ? [NSString stringWithFormat:L(@"CHK_PERF_RAM_VALUE"), [perf[@"memMaxMB"] longValue], room]
				: [NSString stringWithFormat:L(@"CHK_PERF_RAM_USED"), [perf[@"memMaxMB"] longValue]];
			[out addObject:OMCCheck(L(@"CHK_PERF_RAM"), memStatus, memValue,
				([memStatus isEqualToString:@"warn"] || [memStatus isEqualToString:@"bad"]) ? L(@"CHK_PERF_RAM_FIX") : nil, nil)];
		}

		NSInteger heat = [perf[@"thermalMax"] integerValue];
		NSArray *heatNames = @[L(@"DIAG_THERMAL_NOMINAL"), L(@"DIAG_THERMAL_FAIR"), L(@"DIAG_THERMAL_SERIOUS"), L(@"DIAG_THERMAL_CRITICAL")];
		NSString *heatStatus = heat >= NSProcessInfoThermalStateCritical ? @"bad" : (heat >= NSProcessInfoThermalStateSerious ? @"warn" : @"ok");
		[out addObject:OMCCheck(L(@"CHK_PERF_HEAT"), heatStatus, heatNames[(NSUInteger)MIN(MAX(heat, 0), 3)],
			[heatStatus isEqualToString:@"ok"] ? nil : L(@"CHK_PERF_HEAT_FIX"), nil)];

		if ([perf[@"lowPower"] boolValue])
			[out addObject:OMCCheck(L(@"CHK_PERF_LOWPOWER"), @"warn", L(@"CHK_PERF_LOWPOWER_ON"), L(@"CHK_LOWPOWER_FIX"), nil)];

		// Other tweaks injected into CarPlay: each adds start-up time and work on every event
		NSArray *tweaks = [perf[@"tweaks"] isKindOfClass:[NSArray class]] ? perf[@"tweaks"] : @[];
		NSString *names = [[tweaks subarrayWithRange:NSMakeRange(0, MIN(tweaks.count, 5))] componentsJoinedByString:@", "];
		if (tweaks.count > 5) names = [names stringByAppendingFormat:@" +%lu", (unsigned long)(tweaks.count - 5)];
		NSString *tweakStatus = tweaks.count < 4 ? @"ok" : (tweaks.count < 8 ? @"warn" : @"bad");
		NSString *tweakValue = tweaks.count ? [NSString stringWithFormat:@"%lu · %@", (unsigned long)tweaks.count, names] : L(@"CHK_PERF_TWEAKS_NONE");
		[out addObject:OMCCheck(L(@"CHK_PERF_TWEAKS"), tweakStatus, tweakValue,
			[tweakStatus isEqualToString:@"ok"] ? nil : [NSString stringWithFormat:L(@"CHK_PERF_TWEAKS_FIX"), (unsigned long)tweaks.count], nil)];
	}

	// OmniCar's own log: written by every process on every logged line
	unsigned long long bytes = OMCLogBytes();
	if (bytes > 1024 * 1024)
		[out addObject:OMCCheck(L(@"CHK_PERF_LOG"), @"info", [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0], L(@"CHK_PERF_LOG_FIX"), @"clearLog")];
	NSMutableArray *marked = [NSMutableArray array];
	for (NSDictionary *c in out) [marked addObject:OMCPerf(c)];
	return marked;
}

#pragma mark - Optimize

NSInteger OMCLiteMode(void) {
	id v = OMCDiagPref(OMC_KEY_LITE_MODE);
	return v ? [v integerValue] : 2;
}

static void OMCPrefsChanged(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	notify_post([(__bridge NSString *)OMC_PREFS_CHANGED UTF8String]);
}

void OMCSetLiteMode(NSInteger mode) {
	OMCDiagStore(OMC_KEY_LITE_MODE, @(mode));
	OMCPrefsChanged();
}

NSString *OMCLiteStatus(void) {
	NSInteger mode = OMCLiteMode();
	if (mode == 0) return L(@"LITE_STATUS_OFF");
	if (mode == 1) return L(@"LITE_STATUS_ALWAYS");
	if ([NSProcessInfo processInfo].thermalState >= NSProcessInfoThermalStateSerious) return L(@"LITE_STATUS_ON_HEAT");
	int token;
	uint64_t state = 0;
	if (notify_register_check(OMC_DARWIN_LITE, &token) == NOTIFY_STATUS_OK) {
		notify_get_state(token, &state);
		notify_cancel(token);
	}
	if (state) {
		NSDictionary *perf = OMCDiagPref(OMC_KEY_DIAG_PERF);
		NSString *reason = [perf isKindOfClass:[NSDictionary class]] ? perf[@"liteReason"] : nil;
		NSString *key = [@"LITE_REASON_" stringByAppendingString:[reason uppercaseString] ?: @""];
		return [NSString stringWithFormat:L(@"LITE_STATUS_ON"), [reason length] ? L(key) : @""];
	}
	return L(@"LITE_STATUS_AUTO");
}

BOOL OMCCleanRamOn(void) {
	return [OMCDiagPref(OMC_KEY_CLEAN_RAM) boolValue];
}

void OMCSetCleanRam(BOOL on) {
	OMCDiagStore(OMC_KEY_CLEAN_RAM, @(on));
	OMCPrefsChanged();
}

void OMCCleanRamNow(void) {
	notify_post(OMC_DARWIN_CLEAN_NOW);
}

NSDictionary *OMCCleanRamLast(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	NSDictionary *last = OMCDiagPref(OMC_KEY_DIAG_CLEAN);
	return [last isKindOfClass:[NSDictionary class]] ? last : nil;
}

NSString *OMCCleanRamStatus(void) {
	NSDictionary *last = OMCDiagPref(OMC_KEY_DIAG_CLEAN);
	if (![last isKindOfClass:[NSDictionary class]] || ![last[@"date"] isKindOfClass:[NSDate class]]) return L(@"CLEAN_RAM_NEVER");
	return [NSString stringWithFormat:L(@"CLEAN_RAM_LAST"), (unsigned long)[last[@"closed"] count], OMCTimeText(last[@"date"])];
}

// What "Optimize" can do by itself (ids: lite, cleanNow, cleanOn, log, reset) and what only the user can do (the fixes of
// the failing performance / phone checks that have no button).
NSDictionary *OMCOptimizePlan(NSArray<NSDictionary *> *groups) {
	NSMutableArray *steps = [NSMutableArray array];
	if (OMCLiteMode() == 0) [steps addObject:@{@"id": @"lite", @"title": L(@"OPT_LITE")}];
	NSDictionary *perf = OMCDiagPref(OMC_KEY_DIAG_PERF);
	if (![perf isKindOfClass:[NSDictionary class]]) perf = nil;
	long room = [perf[@"availMinMB"] longValue] ?: [perf[@"sysFreeMinMB"] longValue];
	if (perf[@"memMB"] && room && room < 200) {
		[steps addObject:@{@"id": @"cleanNow", @"title": L(@"OPT_CLEAN_NOW")}];
		if (!OMCCleanRamOn()) [steps addObject:@{@"id": @"cleanOn", @"title": L(@"OPT_CLEAN_ON")}];
	}
	unsigned long long bytes = OMCLogBytes();
	if (bytes > 1024 * 1024) [steps addObject:@{@"id": @"log", @"title": [NSString stringWithFormat:L(@"OPT_LOG"), bytes / 1048576.0]}];
	if (steps.count && perf) [steps addObject:@{@"id": @"reset", @"title": L(@"OPT_RESET")}];

	NSMutableOrderedSet *manual = [NSMutableOrderedSet orderedSet];
	for (NSDictionary *g in groups) for (NSDictionary *c in g[@"checks"]) {
		NSString *s = c[@"status"];
		if (c[@"action"] || ![c[@"fix"] length] || !([s isEqualToString:@"warn"] || [s isEqualToString:@"bad"])) continue;
		if ([c[@"perf"] boolValue]) [manual addObject:c[@"fix"]];
	}
	return @{@"steps": steps, @"manual": manual.array};
}

void OMCOptimizeApply(NSArray<NSDictionary *> *steps) {
	for (NSDictionary *step in steps) {
		NSString *i = step[@"id"];
		if ([i isEqualToString:@"lite"]) OMCDiagStore(OMC_KEY_LITE_MODE, @2);
		else if ([i isEqualToString:@"cleanOn"]) OMCDiagStore(OMC_KEY_CLEAN_RAM, @YES);
		else if ([i isEqualToString:@"cleanNow"]) OMCCleanRamNow();
		else if ([i isEqualToString:@"log"]) OMCClearLog();
		else if ([i isEqualToString:@"reset"]) OMCDiagStore(OMC_KEY_DIAG_PERF, nil);
	}
	OMCPrefsChanged();
}

void OMCPerfReset(void) {
	OMCDiagStore(OMC_KEY_DIAG_PERF, nil);
	CFPreferencesAppSynchronize(kPrefsDomain);
}

void OMCClearLog(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:[kLogPath stringByAppendingString:@".old"] error:nil];
	[[NSData data] writeToFile:kLogPath atomically:NO];   // truncate: processes keep appending to the same path
}

NSArray<NSDictionary *> *OMCDiagChecks(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *ios = [UIDevice currentDevice].systemVersion;
	NSInteger major = ios.integerValue;
	NSArray *packages = OMCInstalledPackages();
	NSMutableSet *pkgIDs = [NSMutableSet set];
	for (NSDictionary *p in packages) [pkgIDs addObject:[p[@"id"] lowercaseString]];

	// ---------------- Phone
	NSMutableArray *phone = [NSMutableArray array];
	NSString *iosValue = [NSString stringWithFormat:@"iOS %@ · %@", ios, OMCDeviceModel()];
	if (major < 15) [phone addObject:OMCCheck(L(@"CHK_IOS"), @"bad", iosValue, L(@"CHK_IOS_OLD"), nil)];
	else if (major <= 16) [phone addObject:OMCCheck(L(@"CHK_IOS"), @"ok", iosValue, nil, nil)];
	else [phone addObject:OMCCheck(L(@"CHK_IOS"), @"warn", iosValue, L(@"CHK_IOS_NEW"), nil)];

	BOOL rootless = [fm fileExistsAtPath:@"/var/jb"];
	[phone addObject:OMCCheck(L(@"CHK_JB"), rootless ? @"ok" : @"bad", OMCJailbreak(), rootless ? nil : L(@"CHK_JB_ROOTFUL"), nil)];

	NSString *loader = nil;
	for (NSString *id_ in @[@"ellekit", @"mobilesubstrate", @"com.opa334.libhooker", @"org.coolstar.libhooker", @"com.ex.substitute"])
		if ([pkgIDs containsObject:id_]) { loader = id_; break; }
	BOOL loaderFile = [fm fileExistsAtPath:ROOT_PATH_NS(@"/usr/lib/ellekit/libinjector.dylib")] || [fm fileExistsAtPath:ROOT_PATH_NS(@"/usr/lib/libellekit.dylib")]
		|| [fm fileExistsAtPath:ROOT_PATH_NS(@"/usr/lib/libsubstrate.dylib")] || [fm fileExistsAtPath:ROOT_PATH_NS(@"/usr/lib/TweakInject.dylib")];
	if (loader || loaderFile) [phone addObject:OMCCheck(L(@"CHK_LOADER"), @"ok", [loader isEqualToString:@"ellekit"] || !loader ? @"ElleKit" : loader, nil, nil)];
	else [phone addObject:OMCCheck(L(@"CHK_LOADER"), @"bad", L(@"CHK_LOADER_NONE"), L(@"CHK_LOADER_FIX"), nil)];

	// Package: every dylib with a world-readable filter plist (a 0600 plist = the dylib never loads)
	NSArray<NSString *> *dylibs = OMCInstalledDylibs();
	NSMutableArray *broken = [NSMutableArray array];
	for (NSString *d in dylibs) {
		NSString *plist = [NSString stringWithFormat:@"%@/OmniCar%@.plist", ROOT_PATH_NS(@"/Library/MobileSubstrate/DynamicLibraries"), d];
		NSNumber *perm = [fm attributesOfItemAtPath:plist error:nil][NSFilePosixPermissions];
		if (!perm || !(perm.unsignedShortValue & 0004)) [broken addObject:d];
	}
	if (!dylibs.count) [phone addObject:OMCCheck(L(@"CHK_PACKAGE"), @"bad", L(@"CHK_PACKAGE_NONE"), L(@"CHK_PACKAGE_FIX"), nil)];
	else if (broken.count) [phone addObject:OMCCheck(L(@"CHK_PACKAGE"), @"bad", [NSString stringWithFormat:L(@"CHK_PACKAGE_BROKEN"), [broken componentsJoinedByString:@", "]], L(@"CHK_PACKAGE_FIX"), nil)];
	else [phone addObject:OMCCheck(L(@"CHK_PACKAGE"), @"ok", [NSString stringWithFormat:L(@"CHK_PACKAGE_OK"), @TWEAK_VERSION, (unsigned long)dylibs.count], nil, nil)];

	NSDate *sbDate = nil;
	NSString *sb = OMCLoadState(dylibs, @"SpringBoard", &sbDate);
	if ([sb isEqualToString:@"ok"]) [phone addObject:OMCCheck(L(@"CHK_RUNNING"), @"ok", [NSString stringWithFormat:L(@"CHK_RUNNING_OK"), OMCTimeText(sbDate)], nil, nil)];
	else if ([sb isEqualToString:@"old"]) [phone addObject:OMCCheck(L(@"CHK_RUNNING"), @"warn", L(@"CHK_RUNNING_OLD"), L(@"CHK_RUNNING_RESPRING"), @"respring")];
	else [phone addObject:OMCCheck(L(@"CHK_RUNNING"), @"bad", L(@"CHK_RUNNING_NONE"), L(@"CHK_RUNNING_NONE_FIX"), @"respring")];

	if (!OMCEnabled()) [phone addObject:OMCCheck(L(@"CHK_MASTER"), @"warn", L(@"STATUS_OFF"), L(@"CHK_MASTER_FIX"), nil)];

	NSNumber *freeBytes = [fm attributesOfFileSystemForPath:@"/var" error:nil][NSFileSystemFreeSize];
	double gb = freeBytes.doubleValue / 1e9;
	NSString *freeText = [NSString stringWithFormat:L(@"CHK_STORAGE_FREE"), gb];
	if (freeBytes && gb < 0.5) [phone addObject:OMCCheck(L(@"CHK_STORAGE"), @"bad", freeText, L(@"CHK_STORAGE_FIX"), nil)];
	else if (freeBytes && gb < 2) [phone addObject:OMCCheck(L(@"CHK_STORAGE"), @"warn", freeText, L(@"CHK_STORAGE_FIX"), nil)];
	else [phone addObject:OMCCheck(L(@"CHK_STORAGE"), @"ok", freeBytes ? freeText : L(@"DIAG_UNKNOWN"), nil, nil)];

	UIDevice *dev = [UIDevice currentDevice];
	dev.batteryMonitoringEnabled = YES;
	NSString *battery = dev.batteryLevel >= 0 ? [NSString stringWithFormat:@"%.0f%%", dev.batteryLevel * 100] : @"?";
	if (dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull)
		battery = [battery stringByAppendingFormat:@" · %@", L(@"CHK_BATTERY_CHARGING")];
	if ([NSProcessInfo processInfo].lowPowerModeEnabled)
		[phone addObject:OMCPerf(OMCCheck(L(@"CHK_BATTERY"), @"warn", [battery stringByAppendingFormat:@" · %@", L(@"CHK_LOWPOWER")], L(@"CHK_LOWPOWER_FIX"), nil))];
	else [phone addObject:OMCCheck(L(@"CHK_BATTERY"), @"ok", battery, nil, nil)];

	NSProcessInfoThermalState th = [NSProcessInfo processInfo].thermalState;
	NSString *thStatus = th >= NSProcessInfoThermalStateCritical ? @"bad" : (th >= NSProcessInfoThermalStateSerious ? @"warn" : @"ok");
	[phone addObject:OMCPerf(OMCCheck(L(@"DIAG_THERMAL"), thStatus, OMCThermal(), [thStatus isEqualToString:@"ok"] ? nil : L(@"CHK_THERMAL_FIX"), nil))];

	NSMutableArray *active = [NSMutableArray array], *idle = [NSMutableArray array];
	for (NSDictionary *t in OMCConflictingTweaks()) [([t[@"active"] boolValue] ? active : idle) addObject:t[@"name"]];
	if (active.count) [phone addObject:OMCCheck(L(@"CHK_CONFLICT"), @"bad", [NSString stringWithFormat:L(@"CHK_CONFLICT_ACTIVE"), [active componentsJoinedByString:@", "]], L(@"CONFLICTS_FOOTER"), nil)];
	else [phone addObject:OMCCheck(L(@"CHK_CONFLICT"), @"ok", idle.count ? [NSString stringWithFormat:L(@"CHK_CONFLICT_IDLE"), [idle componentsJoinedByString:@", "]] : L(@"DIAG_CONFLICTS_NONE"), nil, nil)];

	// ---------------- CarPlay
	NSMutableArray *carplay = [NSMutableArray array];
	NSDictionary *car = OMCDiagPref(OMC_KEY_DIAG_CAR);
	if (![car isKindOfClass:[NSDictionary class]]) car = nil;
	int now = OMCCarConnectedNow();
	BOOL connected = now == 1 || (now == -1 && [car[@"connected"] boolValue]);
	NSString *carName = OMCCarField(car, @[@"modelName", @"name", @"vehicleName", @"accessoryName", @"model"]);
	if (connected) {
		NSString *v = car ? [NSString stringWithFormat:@"%@ · %@", carName ?: L(@"CHK_CAR_UNKNOWN"), OMCCarConnection(car)] : L(@"CHK_CAR_CONNECTED");
		[carplay addObject:OMCCheck(L(@"CHK_CAR"), @"ok", v, nil, nil)];
	} else if (car) {
		NSDate *last = car[@"disconnected"] ?: car[@"date"];
		[carplay addObject:OMCCheck(L(@"CHK_CAR"), @"info", [NSString stringWithFormat:L(@"CHK_CAR_LAST"), OMCTimeText(last)], nil, nil)];
	} else {
		[carplay addObject:OMCCheck(L(@"CHK_CAR"), @"info", L(@"CHK_CAR_NEVER"), L(@"CHK_CAR_NEVER_FIX"), nil)];
	}

	NSMutableArray *carDylibs = [NSMutableArray array];
	for (NSString *d in dylibs) if (OMCLoaded(d, @"CarPlay")) [carDylibs addObject:d];
	NSDate *cpDate = nil;
	NSString *cp = carDylibs.count ? OMCLoadState(carDylibs, @"CarPlay", &cpDate) : @"none";
	if ([cp isEqualToString:@"ok"]) [carplay addObject:OMCCheck(L(@"CHK_CP_RUNNING"), @"ok", [NSString stringWithFormat:L(@"CHK_RUNNING_OK"), OMCTimeText(cpDate)], nil, nil)];
	else if ([cp isEqualToString:@"old"]) [carplay addObject:OMCCheck(L(@"CHK_CP_RUNNING"), @"warn", L(@"CHK_RUNNING_OLD"), L(@"CHK_CP_RECONNECT"), nil)];
	else [carplay addObject:OMCCheck(L(@"CHK_CP_RUNNING"), @"info", L(@"CHK_CP_NONE"), L(@"CHK_CAR_NEVER_FIX"), nil)];

	// Hooks this iOS lacks, by feature name (the exact list is in the technical details / log)
	NSDictionary *names = OMCFeatureNames();
	NSDictionary *hooks = OMCHookResults();
	NSUInteger total = 0;
	NSMutableArray *lacking = [NSMutableArray array];
	for (NSString *dylib in hooks) {
		NSUInteger miss = 0;
		for (NSDictionary *e in hooks[dylib]) { total += [e[@"total"] unsignedIntegerValue]; miss += [e[@"missing"] count]; }
		NSString *prefix = [[dylib substringToIndex:1].lowercaseString stringByAppendingString:[dylib substringFromIndex:1]];
		if (miss) [lacking addObject:[NSString stringWithFormat:@"%@ (%lu)", names[prefix] ?: dylib, (unsigned long)miss]];
	}
	if (!total) [carplay addObject:OMCCheck(L(@"CHK_HOOKS"), @"info", L(@"CHK_CP_NONE"), L(@"CHK_CAR_NEVER_FIX"), nil)];
	else if (lacking.count) [carplay addObject:OMCCheck(L(@"CHK_HOOKS"), @"warn", [NSString stringWithFormat:L(@"CHK_HOOKS_MISSING"), [lacking componentsJoinedByString:@", "]],
		[NSString stringWithFormat:L(@"CHK_HOOKS_MISSING_FIX"), ios], nil)];
	else [carplay addObject:OMCCheck(L(@"CHK_HOOKS"), @"ok", [NSString stringWithFormat:L(@"CHK_HOOKS_OK"), (unsigned long)total, ios], nil, nil)];

	NSDictionary *crash = OMCDiagPref(OMC_KEY_DIAG_CRASH);
	if ([crash isKindOfClass:[NSDictionary class]] && [crash[@"date"] isKindOfClass:[NSDate class]]) {
		NSString *who = crash[@"suspect"] ? [NSString stringWithFormat:L(@"CHK_CRASH_SUSPECT"), OMCFeatureDisplayName(crash[@"suspect"])] : @"";
		NSString *v = [NSString stringWithFormat:L(@"CHK_CRASH_AT"), OMCTimeText(crash[@"date"]), who];
		BOOL recent = -[crash[@"date"] timeIntervalSinceNow] < 7 * 86400;
		[carplay addObject:OMCCheck(L(@"CHK_CRASH"), recent ? @"warn" : @"ok", v, recent ? L(@"CHK_CRASH_FIX") : nil, nil)];
	} else {
		[carplay addObject:OMCCheck(L(@"CHK_CRASH"), @"ok", L(@"CHK_CRASH_NONE"), nil, nil)];
	}

	NSArray *rescued = OMCRescueFeatures();
	if (rescued.count) {
		NSMutableArray *n = [NSMutableArray array];
		for (NSString *f in rescued) [n addObject:OMCFeatureDisplayName(f)];
		[carplay addObject:OMCCheck(L(@"RESCUE_GROUP"), @"bad", [NSString stringWithFormat:L(@"CHK_RESCUE_ON"), [n componentsJoinedByString:@", "]],
			L(@"CHK_RESCUE_FIX"), @"rescue")];
	}

	if (car[@"pixels"]) {
		CGSize px = OMCSizeFromString(car[@"pixels"]);
		NSString *v = [NSString stringWithFormat:@"%@ · %@ · %@ FPS", OMCPretty(car[@"pixels"]), OMCRatio(px), car[@"maxFPS"] ?: @"?"];
		[carplay addObject:OMCCheck(L(@"DIAG_CAR"), @"info", v, [NSString stringWithFormat:L(@"CHK_SCREEN_VIDEO"), OMCVideoHint(px)], nil)];
	}

	// ---------------- Features
	NSMutableArray *features = [NSMutableArray array];
	BOOL master = OMCEnabled();
	#define OMC_FEATURE_OFF(prefix) (!master || !OMCFeatureOn(prefix))

	NSString *splitName = OMCFeatureDisplayName(SPL_FEATURE);
	NSArray *carApps = OMCDiagPref(SPL_KEY_CARPLAY_APPS);
	NSUInteger carCount = [carApps isKindOfClass:[NSArray class]] ? carApps.count : 0;
	if (OMC_FEATURE_OFF(SPL_FEATURE)) [features addObject:OMCCheck(splitName, @"info", L(@"FEATURE_OFF"), nil, nil)];
	else if (!carApps) [features addObject:OMCCheck(splitName, @"info", L(@"FEATURE_ON"), L(@"CHK_CAR_NEVER_FIX"), nil)];
	else if (carCount < 2) [features addObject:OMCCheck(splitName, @"warn", [NSString stringWithFormat:L(@"CHK_SPLIT_APPS"), (unsigned long)carCount], L(@"CHK_SPLIT_FEW"), nil)];
	else [features addObject:OMCCheck(splitName, @"ok", [NSString stringWithFormat:L(@"CHK_SPLIT_APPS"), (unsigned long)carCount], nil, nil)];

	NSString *bridgeName = OMCFeatureDisplayName(AB_FEATURE);
	NSArray *chosen = OMCDiagPref(AB_KEY_APPS);
	if (![chosen isKindOfClass:[NSArray class]]) chosen = @[];
	NSMutableArray *gone = [NSMutableArray array];
	for (NSString *b in chosen) if (!OMCAppInstalled(b)) [gone addObject:b];
	if (OMC_FEATURE_OFF(AB_FEATURE)) [features addObject:OMCCheck(bridgeName, @"info", L(@"FEATURE_OFF"), nil, nil)];
	else if (!chosen.count) [features addObject:OMCCheck(bridgeName, @"warn", L(@"CHK_BRIDGE_NONE"), L(@"CHK_BRIDGE_NONE_FIX"), nil)];
	else if (gone.count) [features addObject:OMCCheck(bridgeName, @"warn", [NSString stringWithFormat:L(@"CHK_BRIDGE_APPS"), (unsigned long)chosen.count],
		[NSString stringWithFormat:L(@"CHK_BRIDGE_GONE"), [gone componentsJoinedByString:@", "]], nil)];
	else [features addObject:OMCCheck(bridgeName, @"ok", [NSString stringWithFormat:L(@"CHK_BRIDGE_APPS"), (unsigned long)chosen.count], nil, nil)];

	NSString *bubbleName = OMCFeatureDisplayName(SB_FEATURE);
	NSArray *sources = SB_SOURCE_NAMES, *sourceIDs = @[@"vn.vietmap.live", @"com.lumi.GOFA"];   // same order as SPP_NAV_APPS
	NSInteger src = [OMCDiagPref(SB_KEY_SOURCE) integerValue];
	if (src < 0 || src >= (NSInteger)sources.count) src = 0;
	NSString *srcText = [NSString stringWithFormat:L(@"CHK_BUBBLE_SOURCE"), sources[src]];
	if (OMC_FEATURE_OFF(SB_FEATURE)) [features addObject:OMCCheck(bubbleName, @"info", L(@"FEATURE_OFF"), nil, nil)];
	else if (src < (NSInteger)sourceIDs.count && !OMCAppInstalled(sourceIDs[src]))
		[features addObject:OMCCheck(bubbleName, @"warn", srcText, [NSString stringWithFormat:L(@"CHK_BUBBLE_MISSING"), sources[src]], nil)];
	else [features addObject:OMCCheck(bubbleName, @"ok", srcText, nil, nil)];

	NSString *startName = OMCFeatureDisplayName(SS_FEATURE);
	NSString *video = OMCStartupVideo();
	NSDictionary *frames = video ? [NSDictionary dictionaryWithContentsOfFile:[SS_FRAMES_DIR(video) stringByAppendingPathComponent:@"info.plist"]] : nil;
	if (OMC_FEATURE_OFF(SS_FEATURE)) [features addObject:OMCCheck(startName, @"info", L(@"FEATURE_OFF"), nil, nil)];
	else if (!video) [features addObject:OMCCheck(startName, @"warn", L(@"CHK_START_NONE"), L(@"CHK_START_NONE_FIX"), nil)];
	else if (![frames[@"count"] unsignedIntegerValue]) [features addObject:OMCCheck(startName, @"warn", video, L(@"CHK_START_FRAMES_FIX"), nil)];
	else [features addObject:OMCCheck(startName, @"ok", [NSString stringWithFormat:@"%@ · %@ fps", video, frames[@"fps"] ?: @"?"], nil, nil)];
	#undef OMC_FEATURE_OFF

	return @[
		@{@"title": L(@"DIAG_DEVICE"), @"checks": phone},
		@{@"title": @"CarPlay", @"checks": carplay},
		@{@"title": L(@"CHK_PERF_GROUP"), @"checks": OMCPerfChecks(connected)},
		@{@"title": L(@"FEATURES_GROUP"), @"checks": features},
	];
}

NSDictionary *OMCDiagSummary(NSArray<NSDictionary *> *groups) {
	NSUInteger bad = 0, warn = 0, ok = 0;
	for (NSDictionary *g in groups) for (NSDictionary *c in g[@"checks"]) {
		NSString *s = c[@"status"];
		if ([s isEqualToString:@"bad"]) bad++; else if ([s isEqualToString:@"warn"]) warn++; else if ([s isEqualToString:@"ok"]) ok++;
	}
	NSString *status = bad ? @"bad" : (warn ? @"warn" : @"ok");
	NSString *title = bad ? [NSString stringWithFormat:L(@"CHK_SUM_BAD"), (unsigned long)bad]
		: (warn ? [NSString stringWithFormat:L(@"CHK_SUM_WARN"), (unsigned long)warn] : L(@"CHK_SUM_OK"));
	NSString *sub = [NSString stringWithFormat:L(@"CHK_SUM_COUNTS"), (unsigned long)ok, (unsigned long)warn, (unsigned long)bad];
	return @{@"status": status, @"title": title, @"subtitle": sub};
}

void OMCRespring(void) {
	dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
	dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
	Class relaunch = NSClassFromString(@"SBSRelaunchAction"), service = NSClassFromString(@"FBSSystemService");
	if (relaunch && service) {
		id action = ((id (*)(Class, SEL, NSString *, NSUInteger, NSURL *))objc_msgSend)(relaunch,
			NSSelectorFromString(@"actionWithReason:options:targetURL:"), @"RestartRenderServer", 4 /* FadeToBlack */, nil);
		id shared = ((id (*)(Class, SEL))objc_msgSend)(service, NSSelectorFromString(@"sharedService"));
		if (action && shared) {
			((void (*)(id, SEL, NSSet *, id))objc_msgSend)(shared, NSSelectorFromString(@"sendActions:withResult:"), [NSSet setWithObject:action], nil);
			return;
		}
	}
	for (NSString *path in @[@"/var/jb/usr/bin/killall", @"/usr/bin/killall"]) {   // no relaunch API: killall
		if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) continue;
		pid_t pid;
		const char *argv[] = {path.fileSystemRepresentation, "-9", "SpringBoard", NULL};
		posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, NULL);
		return;
	}
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

	// Health checks first: what the user saw, with the verdict of each line
	NSArray *groups = OMCDiagChecks();
	NSDictionary *sum = OMCDiagSummary(groups);
	[out appendFormat:@"\n== %@ (%@) ==\n", sum[@"title"], sum[@"subtitle"]];
	NSDictionary *marks = @{@"ok": @"OK  ", @"warn": @"WARN", @"bad": @"BAD ", @"info": @"INFO"};
	for (NSDictionary *g in groups) {
		[out appendFormat:@"-- %@\n", g[@"title"]];
		for (NSDictionary *c in g[@"checks"])
			[out appendFormat:@"[%@] %@: %@%@\n", marks[c[@"status"]], c[@"title"], c[@"value"], c[@"fix"] ? [@" -> " stringByAppendingString:c[@"fix"]] : @""];
	}

	for (NSDictionary *section in OMCDiagSections()) {
		[out appendFormat:@"\n== %@ ==\n", section[@"title"]];
		for (NSDictionary *row in section[@"rows"]) [out appendFormat:@"%@: %@\n", row[@"label"], row[@"value"]];
		if ([section[@"footer"] length]) [out appendFormat:@"(%@)\n", section[@"footer"]];
	}

	// Raw car data: CarKit property names differ per iOS, the developer reads them here
	NSDictionary *car = OMCDiagPref(OMC_KEY_DIAG_CAR);
	if ([car isKindOfClass:[NSDictionary class]]) [out appendFormat:@"\n== Car (raw) ==\n%@\n", car];
	NSDictionary *perf = OMCDiagPref(OMC_KEY_DIAG_PERF);
	if ([perf isKindOfClass:[NSDictionary class]]) [out appendFormat:@"\n== Performance, last drive (raw) ==\n%@\n", perf];

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
