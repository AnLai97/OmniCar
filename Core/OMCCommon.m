// Shared by every dylib and the settings bundle: languages (OMCCurrentLanguage, OMCTr) and the license state
// (OMCLicenseState). Only CFPreferences directly: the settings bundle does not have Core/OmniCar.m.
#import "OmniCar.h"

#pragma mark - Languages

NSArray<NSString *> *OMCSupportedLanguages(void) {
	return @[@"vi", @"en", @"es", @"pt-BR", @"de", @"fr", @"it", @"ru", @"zh-Hans", @"ja", @"ko", @"ar", @"th", @"id"];
}

// The "language" pref, else the first device language OmniCar has (pt-PT -> pt-BR, zh-Hans-CN -> zh-Hans), else English
NSString *OMCCurrentLanguage(void) {
	NSArray<NSString *> *supported = OMCSupportedLanguages();
	NSString *chosen = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("language"), OMC_PREFS_DOMAIN));
	if ([chosen isKindOfClass:[NSString class]] && [supported containsObject:chosen]) return chosen;
	for (NSString *pref in [NSLocale preferredLanguages]) {
		for (NSString *lang in supported)
			if ([pref isEqualToString:lang] || [pref hasPrefix:[lang stringByAppendingString:@"-"]]) return lang;
		NSString *code = [pref componentsSeparatedByString:@"-"].firstObject;
		if ([code isEqualToString:@"zh"]) continue;   // zh-Hant: not translated, keep looking
		for (NSString *lang in supported)
			if ([[lang componentsSeparatedByString:@"-"].firstObject isEqualToString:code]) return lang;
	}
	return @"en";
}

// <lang>.lproj/Car.strings of the settings bundle (readable from SpringBoard and CarPlay), keyed by the English text
static NSDictionary<NSString *, NSString *> *OMCCarTable(NSString *lang) {
	static NSMutableDictionary *tables;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ tables = [NSMutableDictionary dictionary]; });
	@synchronized (tables) {
		NSDictionary *t = tables[lang];
		if (!t) {
			NSString *path = [NSString stringWithFormat:@"%@/%@.lproj/Car.strings", ROOT_PATH_NS(@"/Library/PreferenceBundles/OmniCarPrefs.bundle"), lang];
			t = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
			tables[lang] = t;
		}
		return t;
	}
}

NSString *OMCTr(NSString *vi, NSString *en) {
	NSString *lang = OMCCurrentLanguage();
	if ([lang isEqualToString:@"vi"]) return vi;
	if ([lang isEqualToString:@"en"] || !en) return en;
	return OMCCarTable(lang)[en] ?: en;
}

#pragma mark - License

// dpkg database: "Package: <id>" ... "Status: install ok installed" in the same paragraph
static BOOL OMCPackageInstalled(NSString *package) {
	NSString *db = [NSString stringWithContentsOfFile:ROOT_PATH_NS(@"/var/lib/dpkg/status") encoding:NSUTF8StringEncoding error:nil];
	NSString *wanted = [@"Package: " stringByAppendingString:package];
	for (NSString *entry in [db componentsSeparatedByString:@"\n\n"]) {
		NSArray<NSString *> *lines = [entry componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
		if (![lines containsObject:wanted]) continue;
		return [lines containsObject:@"Status: install ok installed"];
	}
	return NO;
}

static NSDate *OMCTrialStart(void) {
	NSString *file = [OMC_DATA_ROOT stringByAppendingPathComponent:@".trial"];
	NSDate *fromPrefs = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)OMC_KEY_TRIAL_START, OMC_PREFS_DOMAIN));
	NSDate *fromFile = [[NSFileManager defaultManager] attributesOfItemAtPath:file error:nil].fileCreationDate;
	NSDate *start = fromFile;
	if ([fromPrefs isKindOfClass:[NSDate class]] && (!start || [fromPrefs compare:start] == NSOrderedAscending)) start = fromPrefs;
	if (!start) {   // first run: only SpringBoard / Settings write it (sandboxed processes cannot)
		start = [NSDate date];
		[[NSFileManager defaultManager] createDirectoryAtPath:OMC_DATA_ROOT withIntermediateDirectories:YES attributes:nil error:nil];
		[[NSData data] writeToFile:file atomically:NO];
		CFPreferencesSetAppValue((__bridge CFStringRef)OMC_KEY_TRIAL_START, (__bridge CFPropertyListRef)start, OMC_PREFS_DOMAIN);
		CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
	}
	return start;
}

// Asked at feature start-up and by Settings: the dpkg database is read at most once a minute
OMCLicense OMCLicenseState(void) {
	static OMCLicense cached;
	static CFAbsoluteTime at;
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if (at && now - at < 60) return cached;
	at = now;
	if (OMCPackageInstalled(OMC_PRO_PACKAGE)) return cached = OMCLicensePro;
	return cached = OMCTrialDaysLeft() > 0 ? OMCLicenseTrial : OMCLicenseLite;
}

NSInteger OMCTrialDaysLeft(void) {
	NSTimeInterval used = -[OMCTrialStart() timeIntervalSinceNow];
	return MAX(0, OMC_TRIAL_DAYS - (NSInteger)floor(used / 86400));
}

BOOL OMCIsPro(void) {
	return OMCLicenseState() != OMCLicenseLite;
}

BOOL OMCFeatureNeedsPro(NSString *feature) {
	static NSSet *pro;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ pro = [NSSet set]; });   // decided with the Lite / Pro split (ROADMAP Phat hanh 3 / 4)
	return [pro containsObject:feature] && !OMCIsPro();
}
