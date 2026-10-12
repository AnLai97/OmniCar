#import "OmniCar.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>

#pragma mark - Preferences

void OMCPrefsSync(void) {
	CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

id OMCPref(NSString *key, id fallback) {
	id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, OMC_PREFS_DOMAIN);
	return value ?: fallback;
}

BOOL OMCEnabled(void) {
	return [OMCPref(@"enabled", @YES) boolValue];
}

BOOL OMCFeatureEnabled(NSString *feature) {
	return OMCEnabled() && [OMCPref([feature stringByAppendingString:@"Enabled"], @YES) boolValue];
}

#pragma mark - Logging

// One file for every feature and process, readable with Filza. A process that cannot write it
// (sandboxed apps: Vietmap Live, GOFA) relays the line to SpringBoard, where the
// OmniCarCore dylib appends it (OMCLogRelayStart). The file is rotated at OMC_LOG_MAX_BYTES.
static NSString *const kLogPath = @"/var/mobile/Documents/OmniCar.log";
static const unsigned long long OMC_LOG_MAX_BYTES = 2 * 1024 * 1024;

static dispatch_queue_t OMCLogQueue(void) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.anlai.omnicar.log", DISPATCH_QUEUE_SERIAL); });
	return queue;
}

static BOOL OMCLogAppend(NSString *line) {
	FILE *f = fopen(kLogPath.fileSystemRepresentation, "a");
	if (!f) return NO;
	fputs(line.UTF8String, f);
	fclose(f);
	return YES;
}

static void OMCLogRotateIfNeeded(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	unsigned long long size = [[fm attributesOfItemAtPath:kLogPath error:nil] fileSize];
	if (size < OMC_LOG_MAX_BYTES) return;
	NSString *old = [kLogPath stringByAppendingString:@".old"];
	[fm removeItemAtPath:old error:nil];
	[fm moveItemAtPath:kLogPath toPath:old error:nil];
}

static BOOL OMCIsSpringBoard(void) {
	static BOOL is;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ is = [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]; });
	return is;
}

// NSDistributedNotificationCenter is private on iOS but is an NSNotificationCenter subclass,
// so the public NSNotificationCenter API drives it.
static NSNotificationCenter *OMCDistributedCenter(void) {
	Class cls = NSClassFromString(@"NSDistributedNotificationCenter");
	return cls ? (NSNotificationCenter *)[cls defaultCenter] : nil;
}

void OMCLogWrite(NSString *feature, NSString *message) {
	NSLog(@"[OmniCar/%@] %@", feature, message);

	static NSDateFormatter *df;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		df = [NSDateFormatter new];
		df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
	});
	NSString *line = [NSString stringWithFormat:@"%@ [%@:%d] %@: %@\n", [df stringFromDate:[NSDate date]],
		[NSProcessInfo processInfo].processName, getpid(), feature, message];
	dispatch_async(OMCLogQueue(), ^{
		if (OMCIsSpringBoard()) OMCLogRotateIfNeeded();
		if (OMCLogAppend(line) || OMCIsSpringBoard()) return;
		[OMCDistributedCenter() postNotificationName:OMC_LOG_RELAY object:nil userInfo:@{@"line": line}];
	});
}

void OMCLogRelayStart(void) {
	if (!OMCIsSpringBoard()) return;
	[OMCDistributedCenter() addObserverForName:OMC_LOG_RELAY object:nil queue:nil usingBlock:^(NSNotification *note) {
		NSString *line = note.userInfo[@"line"];
		if (![line isKindOfClass:[NSString class]]) return;
		dispatch_async(OMCLogQueue(), ^{
			OMCLogRotateIfNeeded();
			OMCLogAppend(line);
		});
	}];
}

#pragma mark - Hook check

BOOL OMCHasMethod(const char *className, NSString *selector) {
	Class cls = OMCCarClass(className);
	if (!cls) return NO;
	BOOL classMethod = [selector hasPrefix:@"+"];
	SEL sel = NSSelectorFromString(classMethod ? [selector substringFromIndex:1] : selector);
	return classMethod ? class_getClassMethod(cls, sel) != NULL : class_getInstanceMethod(cls, sel) != NULL;
}

void OMCCheckHooks(NSString *feature, NSArray<NSString *> *hooks) {
	NSMutableArray<NSString *> *missing = [NSMutableArray array];
	NSMutableOrderedSet<NSString *> *renamed = [NSMutableOrderedSet orderedSet];
	for (NSString *hook in hooks) {
		NSArray<NSString *> *parts = [hook componentsSeparatedByString:@" "];
		if (parts.count != 2) continue;
		Class cls = OMCCarClass(parts[0].UTF8String);
		if (cls && ![NSStringFromClass(cls) isEqualToString:parts[0]])
			[renamed addObject:[NSString stringWithFormat:@"%@=%@", parts[0], NSStringFromClass(cls)]];
		NSString *sel = parts[1];
		if ([sel hasPrefix:@"-"]) sel = [sel substringFromIndex:1];
		if (!OMCHasMethod(parts[0].UTF8String, sel)) [missing addObject:hook];
	}
	NSString *ios = [UIDevice currentDevice].systemVersion;
	if (renamed.count) OMCLog(feature, @"iOS %@: lop CarPlay %@", ios, [renamed.array componentsJoinedByString:@", "]);
	if (missing.count) OMCLog(feature, @"iOS %@: %lu/%lu hook KHONG co tren iOS nay (tinh nang lien quan se khong chay): %@",
		ios, (unsigned long)missing.count, (unsigned long)hooks.count, [missing componentsJoinedByString:@", "]);
	else OMCLog(feature, @"iOS %@: du %lu hook", ios, (unsigned long)hooks.count);
}

void OMCMissingSelector(NSString *feature, id obj, NSString *selector) {
	if (!obj) return;
	static NSMutableSet<NSString *> *seen;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
	NSString *key = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([obj class]), selector];
	@synchronized (seen) {
		if ([seen containsObject:key]) return;
		[seen addObject:key];
	}
	OMCLog(feature, @"THIEU METHOD (iOS %@): %@ -> bo qua", [UIDevice currentDevice].systemVersion, key);
}

#pragma mark - CarPlay classes (iOS 16 DashBoard / iOS 14-15 CarPlay.app)

Class OMCCarClass(const char *name) {
	Class cls = objc_getClass(name);
	if (cls) return cls;
	NSString *n = @(name);
	NSString *rest = nil;
	if ([n isEqualToString:@"DashBoard"]) return objc_getClass("CARApplication");
	if ([n hasPrefix:@"DB"]) rest = [n substringFromIndex:2];
	if (!rest) return nil;
	cls = objc_getClass([@"CAR" stringByAppendingString:rest].UTF8String);
	return cls ?: objc_getClass([@"_CAR" stringByAppendingString:rest].UTF8String);
}

id OMCCarLaunchInfo(id appInfo) {
	if (!appInfo) return nil;
	Class cls = OMCCarClass("DBApplicationLaunchInfo");
	SEL one = NSSelectorFromString(@"launchInfoForApplication:");
	SEL two = NSSelectorFromString(@"launchInfoForApplication:withActivationSettings:");
	if ([cls respondsToSelector:one]) return ((id (*)(id, SEL, id))objc_msgSend)(cls, one, appInfo);
	if ([cls respondsToSelector:two]) return ((id (*)(id, SEL, id, id))objc_msgSend)(cls, two, appInfo, nil);
	OMCLog(@"Core", @"THIEU METHOD: %@ khong tao duoc launchInfo", cls);
	return nil;
}
