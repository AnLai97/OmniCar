#import "OmniCar.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <fcntl.h>
#import <notify.h>
#import <signal.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>

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

static void OMCGuardNote(void);

void OMCLogWrite(NSString *feature, NSString *message) {
	OMCGuardNote();
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
	// Diagnostics page: one key per feature and process, summed over this process's OMCCheckHooks calls.
	static NSMutableDictionary<NSString *, NSMutableDictionary *> *sums;
	if (!sums) sums = [NSMutableDictionary dictionary];
	NSString *key = [NSString stringWithFormat:@"%@%@@%@", OMC_KEY_DIAG_HOOKS, feature, [NSProcessInfo processInfo].processName];
	NSMutableDictionary *sum = sums[key] ?: (sums[key] = [@{@"total": @0, @"missing": [NSMutableArray array]} mutableCopy]);
	sum[@"ios"] = ios;
	sum[@"total"] = @([sum[@"total"] unsignedIntegerValue] + hooks.count);
	[sum[@"missing"] addObjectsFromArray:missing];
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)sum, OMC_PREFS_DOMAIN);
	CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
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

#pragma mark - Crash guard (rescue mode, CarPlay)

// Every feature dylib carries its own copy of this file, so the state the crash handlers need is one
// block per process: the first OMCCrashGuard call allocates it and parks its address in an environment
// variable (process wide), the other dylibs find it there. lastFeature is a breadcrumb: the dylib that
// logged last, the suspect when the backtrace shows no OmniCar frame (an Apple assert we triggered).
typedef struct {
	char path[1024];
	char lastFeature[64];
	time_t launch;
} OMCGuardState;

static OMCGuardState *sGuard;
static NSUncaughtExceptionHandler *sGuardPrevHandler;
#define OMC_GUARD_ENV "OMC_CRASHGUARD"

static OMCGuardState *OMCGuardShared(void) {
	if (sGuard) return sGuard;
	const char *env = getenv(OMC_GUARD_ENV);
	if (env) sGuard = (OMCGuardState *)(uintptr_t)strtoull(env, NULL, 16);
	return sGuard;
}

static void OMCGuardNote(void) {
	OMCGuardState *g = OMCGuardShared();
	if (g && strcmp(OMC_FEATURE, "Core") != 0) strlcpy(g->lastFeature, OMC_FEATURE, sizeof g->lastFeature);
}

static BOOL OMCIsCarPlay(void) {
	static BOOL is;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ is = [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"]; });
	return is;
}

// First OmniCar<Name>.dylib in the backtrace -> <Name>.
static void OMCGuardSuspect(void *const *frames, int count, char *out, size_t size) {
	out[0] = 0;
	for (int i = 0; i < count; i++) {
		Dl_info info;
		if (!dladdr(frames[i], &info) || !info.dli_fname) continue;
		const char *base = strrchr(info.dli_fname, '/');
		base = base ? base + 1 : info.dli_fname;
		size_t len = strlen(base);
		if (strncmp(base, "OmniCar", 7) != 0 || len <= 13 || strcmp(base + len - 6, ".dylib") != 0) continue;
		size_t n = len - 13 < size - 1 ? len - 13 : size - 1;
		memcpy(out, base + 7, n);
		out[n] = 0;
		return;
	}
}

static void OMCGuardWriteHeader(int fd, const char *how, void *const *frames, int count) {
	char suspect[64];
	OMCGuardSuspect(frames, count, suspect, sizeof suspect);
	dprintf(fd, "omc-crash age=%ld suspect=%s last=%s how=%s\n", (long)(time(NULL) - sGuard->launch), suspect, sGuard->lastFeature, how);
}

// Apple frameworks write why they stop (assert -> SIGTRAP) into their image's __crash_info section
// (CRSetCrashLogMessage): the "Application Specific Information" line of the system crash log.
struct OMCCrashAnnotations { uint64_t version, message, signature, backtrace, message2, thread, dialogMode, abortCause; };
static void OMCGuardWriteCrashMessages(int fd) {
	for (uint32_t i = 0; i < _dyld_image_count(); i++) {
		const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(i);
		if (!mh) continue;
		unsigned long size = 0;
		struct OMCCrashAnnotations *a = (struct OMCCrashAnnotations *)getsectiondata(mh, "__DATA", "__crash_info", &size);
		if (!a) a = (struct OMCCrashAnnotations *)getsectiondata(mh, "__DATA_DIRTY", "__crash_info", &size);
		if (!a || size < sizeof(uint64_t) * 5) continue;
		const char *msgs[2] = { (const char *)a->message, (const char *)a->message2 };
		for (int k = 0; k < 2; k++) {
			if (!msgs[k] || !msgs[k][0]) continue;
			const char *name = _dyld_get_image_name(i);
			const char *slash = name ? strrchr(name, '/') : NULL;
			dprintf(fd, "crash_info [%s]: %s\n", slash ? slash + 1 : (name ?: "?"), msgs[k]);
		}
	}
}

// Written straight to the file (OMCLog is async: the process is gone before it would write).
// O_APPEND: an uncaught exception writes first, then abort() lands here with the signal.
static void OMCGuardSignal(int sig, siginfo_t *si, void *ctx) {
	int fd = open(sGuard->path, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd >= 0) {
		void *frames[64];
		int count = backtrace(frames, 64);
		char how[48];
		snprintf(how, sizeof how, "signal-%d", sig);
		OMCGuardWriteHeader(fd, how, frames, count);
		dprintf(fd, "signal %d (code %d) addr %p pid %d\n", sig, si ? (int)si->si_code : 0, si ? si->si_addr : NULL, (int)getpid());
		backtrace_symbols_fd(frames, count, fd);
		OMCGuardWriteCrashMessages(fd);
		close(fd);
	}
	signal(sig, SIG_DFL);   // the system still writes its own crash log
	raise(sig);
}

static void OMCGuardException(NSException *e) {
	int fd = open(sGuard->path, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd >= 0) {
		void *frames[64];
		int count = 0;
		for (NSNumber *a in e.callStackReturnAddresses) {
			if (count == 64) break;
			frames[count++] = (void *)(uintptr_t)a.unsignedLongLongValue;
		}
		OMCGuardWriteHeader(fd, "exception", frames, count);
		NSString *text = [NSString stringWithFormat:@"uncaught %@: %@\n%@\n", e.name, e.reason, [e.callStackSymbols componentsJoinedByString:@"\n"]];
		dprintf(fd, "%s", text.UTF8String);
		close(fd);
	}
	if (sGuardPrevHandler) sGuardPrevHandler(e);
}

static void OMCGuardStore(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, OMC_PREFS_DOMAIN);
}

static NSString *OMCGuardStatePath(void) {
	return [NSTemporaryDirectory() stringByAppendingPathComponent:@"OmniCar-crashguard.plist"];
}

// "SplitScreen" (dylib) -> "splitScreen" (pref key prefix).
static NSString *OMCGuardPrefix(NSString *dylibName) {
	if (!dylibName.length) return nil;
	return [[dylibName substringToIndex:1].lowercaseString stringByAppendingString:[dylibName substringFromIndex:1]];
}

static void OMCGuardRescue(NSArray<NSString *> *suspects, NSArray<NSString *> *carFeatures) {
	OMCPrefsSync();
	NSMutableOrderedSet<NSString *> *off = [NSMutableOrderedSet orderedSet];
	for (NSString *s in suspects) if ([carFeatures containsObject:s]) [off addObject:s];
	if (!off.count) {   // no OmniCar frame and no breadcrumb: every CarPlay feature that is on
		for (NSString *f in carFeatures)
			if ([OMCPref([f stringByAppendingString:@"Enabled"], @YES) boolValue]) [off addObject:f];
	}
	if (!off.count) return;
	NSArray *old = OMCPref(OMC_KEY_RESCUE, nil);
	NSMutableOrderedSet<NSString *> *list = [NSMutableOrderedSet orderedSetWithArray:[old isKindOfClass:[NSArray class]] ? old : @[]];
	for (NSString *f in off) {
		OMCGuardStore([f stringByAppendingString:@"Enabled"], @NO);
		[list addObject:f];
	}
	OMCGuardStore(OMC_KEY_RESCUE, list.array);
	OMCGuardStore(OMC_KEY_RESCUE_DATE, [NSDate date]);
#if OMC_AUTOTEST
	OMCGuardStore(OMC_KEY_CRASH_TEST, nil);
#endif
	OMCPrefsSync();
	OMCLog(@"Core", @"CHE DO CUU: CarPlay sap %d lan lien trong %ds dau -> tat %@", OMC_RESCUE_CRASHES, OMC_RESCUE_SECONDS,
		[off.array componentsJoinedByString:@", "]);
	notify_post(OMC_DARWIN_RESCUE);
	notify_post("com.anlai.omnicar/prefschanged");
}

static NSString *OMCScreenSize(CGSize s) {
	return [NSString stringWithFormat:@"%.0fx%.0f", s.width, s.height];
}

// Properties of a private object as short strings (CarKit session / configuration: car name, wired or
// wireless ...). The names differ between iOS versions, so the whole list is kept and the Diagnostics
// page picks what it knows.
static NSDictionary<NSString *, NSString *> *OMCDumpProperties(id obj) {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	for (Class cls = [obj class]; cls && cls != [NSObject class] && out.count < 80; cls = class_getSuperclass(cls)) {
		unsigned int count = 0;
		objc_property_t *props = class_copyPropertyList(cls, &count);
		for (unsigned int i = 0; i < count; i++) {
			NSString *name = @(property_getName(props[i]));
			const char *attrs = property_getAttributes(props[i]);
			// objects, numbers, BOOL and structs; never blocks or raw pointers
			if (!attrs || attrs[0] != 'T' || attrs[1] == '^' || strncmp(attrs, "T@?", 3) == 0 || out[name]) continue;
			if ([name hasPrefix:@"_"] || [@[@"description", @"debugDescription", @"hash", @"superclass"] containsObject:name]) continue;
			@try {
				id value = [obj valueForKey:name];
				NSString *text = [value description] ?: @"nil";
				text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
				out[name] = text.length > 160 ? [[text substringToIndex:160] stringByAppendingString:@"..."] : text;
			} @catch (NSException *e) {}
		}
		free(props);
	}
	return out;
}

// Car screen (CarPlay process: every screen but the phone's) + the CarKit session, for the Diagnostics page.
static void OMCRecordCarScreen(UIScreen *screen) {
	if (!screen || screen == [UIScreen mainScreen]) return;
	NSMutableDictionary *car = [NSMutableDictionary dictionary];
	car[@"date"] = [NSDate date];
	car[@"ios"] = [UIDevice currentDevice].systemVersion;
	car[@"points"] = OMCScreenSize(screen.bounds.size);
	car[@"pixels"] = OMCScreenSize(screen.nativeBounds.size);
	car[@"scale"] = @(screen.scale);
	car[@"maxFPS"] = @(screen.maximumFramesPerSecond);
	@try {
		dlopen("/System/Library/PrivateFrameworks/CarKit.framework/CarKit", RTLD_LAZY);
		static id status;   // kept: the session is filled in asynchronously
		Class cls = NSClassFromString(@"CARSessionStatus");
		if (!status && cls) status = [cls new];
		id session = [status respondsToSelector:NSSelectorFromString(@"currentSession")] ? [status valueForKey:@"currentSession"] : nil;
		if (session) {
			car[@"session"] = OMCDumpProperties(session);
			id config = [session respondsToSelector:NSSelectorFromString(@"configuration")] ? [session valueForKey:@"configuration"] : nil;
			if (config) car[@"configuration"] = OMCDumpProperties(config);
		}
	} @catch (NSException *e) { OMCLog(@"Core", @"CarKit loi: %@", e); }
	OMCGuardStore(OMC_KEY_DIAG_CAR, car);
	OMCPrefsSync();
	OMCLog(@"Core", @"man xe %@ pt, %@ px, %@ fps, session=%d", car[@"points"], car[@"pixels"], car[@"maxFPS"], car[@"session"] != nil);
}

static void OMCRecordCarScreensSoon(void) {
	// The session and the final screen size settle a moment after the screen appears.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		for (UIScreen *screen in [UIScreen screens]) OMCRecordCarScreen(screen);
	});
}

static void OMCGuardStart(void) {
	sGuard = calloc(1, sizeof(OMCGuardState));
	sGuard->launch = time(NULL);
	char env[32];
	snprintf(env, sizeof env, "%llx", (unsigned long long)(uintptr_t)sGuard);
	setenv(OMC_GUARD_ENV, env, 1);
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OmniCar-CarPlay-crash.txt"];
	strlcpy(sGuard->path, path.fileSystemRepresentation, sizeof sGuard->path);

	// How did the last launch end? A crash file = it crashed; "age" = seconds after it started.
	NSMutableDictionary *state = [NSMutableDictionary dictionaryWithContentsOfFile:OMCGuardStatePath()] ?: [NSMutableDictionary dictionary];
	NSInteger early = [state[@"early"] integerValue];
	NSMutableArray<NSString *> *suspects = [NSMutableArray arrayWithArray:state[@"suspects"] ?: @[]];
	NSString *prev = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	BOOL crashedEarly = NO;
	if (prev.length) {
		OMCLog(@"Core", @"CARPLAY SAP LAN TRUOC:\n%@", prev);
		unlink(sGuard->path);
		long age = LONG_MAX;
		NSString *suspect = nil, *last = nil;
		for (NSString *line in [prev componentsSeparatedByString:@"\n"]) {
			if (![line hasPrefix:@"omc-crash "]) continue;
			for (NSString *field in [line componentsSeparatedByString:@" "]) {
				if ([field hasPrefix:@"age="]) age = MIN(age, (long)[[field substringFromIndex:4] integerValue]);
				else if ([field hasPrefix:@"suspect="] && field.length > 8 && !suspect) suspect = [field substringFromIndex:8];
				else if ([field hasPrefix:@"last="] && field.length > 5 && !last) last = [field substringFromIndex:5];
			}
		}
		crashedEarly = age < OMC_RESCUE_SECONDS;
		NSString *who = OMCGuardPrefix(suspect ?: last);
		if (crashedEarly && who && ![suspects containsObject:who]) [suspects addObject:who];
	}
#if OMC_AUTOTEST
	NSDictionary *autoTest = OMCPref(OMC_KEY_AUTOTEST, nil);
	if (crashedEarly && [autoTest isKindOfClass:[NSDictionary class]] && [autoTest[@"state"] isEqual:@"running"]) {
		OMCLog(@"Core", @"CarPlay sap trong luc tu kiem tra: khong tinh vao che do cuu");
		crashedEarly = NO;
	}
#endif
	if (crashedEarly) early++;
	else { early = 0; [suspects removeAllObjects]; }   // a run without an early crash breaks the streak
	if (early >= OMC_RESCUE_CRASHES) {
		OMCGuardRescue(suspects, state[@"features"] ?: @[]);
		early = 0;
		[suspects removeAllObjects];
	} else if (early) {
		OMCLog(@"Core", @"CarPlay sap som %ld/%d lan lien (nghi: %@)", (long)early, OMC_RESCUE_CRASHES, [suspects componentsJoinedByString:@", "]);
	}
	state[@"early"] = @(early);
	state[@"suspects"] = suspects;
	[state writeToFile:OMCGuardStatePath() atomically:YES];

	sGuardPrevHandler = NSGetUncaughtExceptionHandler();
	NSSetUncaughtExceptionHandler(OMCGuardException);
	struct sigaction sa = {};
	sa.sa_sigaction = OMCGuardSignal;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	int sigs[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE };
	for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) sigaction(sigs[i], &sa, NULL);

	[[NSNotificationCenter defaultCenter] addObserverForName:UIScreenDidConnectNotification object:nil
		queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { OMCRecordCarScreensSoon(); }];
	OMCRecordCarScreensSoon();
}

BOOL OMCCrashGuard(NSString *feature) {
	if (!OMCIsCarPlay() || !feature.length) return YES;
	if (!OMCGuardShared()) OMCGuardStart();

	// Remember which features run in CarPlay: the fallback list when a crash names none.
	NSMutableDictionary *state = [NSMutableDictionary dictionaryWithContentsOfFile:OMCGuardStatePath()] ?: [NSMutableDictionary dictionary];
	NSArray *features = state[@"features"] ?: @[];
	if (![features containsObject:feature]) {
		state[@"features"] = [features arrayByAddingObject:feature];
		[state writeToFile:OMCGuardStatePath() atomically:YES];
	}

	OMCPrefsSync();
	NSArray *rescued = OMCPref(OMC_KEY_RESCUE, nil);
	if ([rescued isKindOfClass:[NSArray class]] && [rescued containsObject:feature]) {
		if (![OMCPref([feature stringByAppendingString:@"Enabled"], @YES) boolValue]) {
			OMCLog(@"Core", @"%@ dang tat boi che do cuu (tu %@): khong cai hook trong CarPlay", feature, OMCPref(OMC_KEY_RESCUE_DATE, nil));
			return NO;
		}
		NSMutableArray *rest = [rescued mutableCopy];   // turned back on in Settings
		[rest removeObject:feature];
		OMCGuardStore(OMC_KEY_RESCUE, rest.count ? rest : nil);
		OMCPrefsSync();
		OMCLog(@"Core", @"%@ bat lai sau che do cuu", feature);
	}

#if OMC_AUTOTEST
	// The block is compiled into this feature's dylib, so the crash backtrace names it as the suspect.
	if ([OMCPref(OMC_KEY_CRASH_TEST, nil) isEqual:feature]) {
		OMCLog(@"Core", @"THU CHE DO CUU: CarPlay se sap sau 5s (%@)", feature);
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ abort(); });
	}
#endif
	return YES;
}
