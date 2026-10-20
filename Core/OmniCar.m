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
#import <mach/mach.h>
#import <os/proc.h>
#import <stdatomic.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Preferences

void OMCPrefsSync(void) {
	CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

id OMCPref(NSString *key, id fallback) {
	id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, OMC_PREFS_DOMAIN);
	return value ?: fallback;
}

BOOL OMCEnabled(void) {
	return !OMCExpired() && [OMCPref(@"enabled", @YES) boolValue];
}

BOOL OMCFeatureEnabled(NSString *feature) {
	return OMCEnabled() && [OMCPref([feature stringByAppendingString:@"Enabled"], @YES) boolValue];
}

// Asked on every Speed Bubble redraw: the answer is kept for 3 s (prefs sync + notify state per call otherwise).
BOOL OMCLiteActive(void) {
	static BOOL cached;
	static CFAbsoluteTime checkedAt;
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if (checkedAt && now - checkedAt < 3) return cached;
	checkedAt = now;
	OMCPrefsSync();
	NSInteger mode = [OMCPref(OMC_KEY_LITE_MODE, @2) integerValue];
	if (mode == 1 || mode != 2 || !OMCEnabled()) return cached = (mode == 1 && OMCEnabled());
	if ([NSProcessInfo processInfo].thermalState >= NSProcessInfoThermalStateSerious) return cached = YES;
	static int token = -1;
	if (token == -1 && notify_register_check(OMC_DARWIN_LITE, &token) != NOTIFY_STATUS_OK) {
		token = -1;
		return cached = NO;
	}
	uint64_t state = 0;
	notify_get_state(token, &state);
	return cached = (state != 0);
}

int OMCCarWireless(void) {
	NSDictionary *car = OMCPref(OMC_KEY_DIAG_CAR, nil);
	if (![car isKindOfClass:[NSDictionary class]]) return -1;
	for (NSString *group in @[@"session", @"configuration"]) {
		NSDictionary *props = car[group];
		if (![props isKindOfClass:[NSDictionary class]]) continue;
		for (NSString *name in props) {
			if (![name isKindOfClass:[NSString class]]) continue;
			NSString *lower = name.lowercaseString, *v = [props[name] description].lowercaseString;
			if ([lower containsString:@"wireless"] && ([v isEqualToString:@"1"] || [v isEqualToString:@"0"])) return [v isEqualToString:@"1"];
			if ([lower containsString:@"wired"] && ([v isEqualToString:@"1"] || [v isEqualToString:@"0"])) return ![v isEqualToString:@"1"];
			if ([lower containsString:@"transport"]) {
				if ([v containsString:@"wifi"] || [v containsString:@"wireless"] || [v containsString:@"wi-fi"]) return 1;
				if ([v containsString:@"usb"] || [v containsString:@"wired"]) return 0;
			}
		}
	}
	return -1;
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

static BOOL OMCLogOnQueue(void) {
	return dispatch_get_specific(&OMCLogQueue) != NULL;
}

// YES until the main queue first runs, i.e. while dylib constructors run under dyld's lock. Set up from the first log line.
static atomic_bool sLogDirectOver;
static BOOL OMCLogDirect(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dispatch_queue_set_specific(OMCLogQueue(), &OMCLogQueue, (void *)1, NULL);
		dispatch_async(dispatch_get_main_queue(), ^{ atomic_store(&sLogDirectOver, true); });
	});
	return !atomic_load(&sLogDirectOver);
}

// Plain C, one write() with O_APPEND: no Foundation file API, no lock, so it is safe inside a constructor.
static BOOL OMCLogAppendDirect(const char *s) {
	if (!s) return NO;
	int fd = open("/var/mobile/Documents/OmniCar.log", O_WRONLY | O_APPEND | O_CREAT, 0644);
	if (fd < 0) return NO;
	size_t len = strlen(s);
	BOOL ok = write(fd, s, len) == (ssize_t)len;
	close(fd);
	return ok;
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
	// Constructor phase: write on this thread, never wait for the queue (see OMCLogFlush). A sandboxed process that
	// cannot open the file falls through to the queue, which relays the line to SpringBoard.
	if (OMCLogDirect() && OMCLogAppendDirect(line.UTF8String)) return;
	dispatch_async(OMCLogQueue(), ^{
		if (OMCIsSpringBoard()) OMCLogRotateIfNeeded();
		if (OMCLogAppend(line) || OMCIsSpringBoard()) return;
		[OMCDistributedCenter() postNotificationName:OMC_LOG_RELAY object:nil userInfo:@{@"line": line}];
	});
}

// 20/10 21:20, iPhone 7 Plus 15.8.4: build e258fb5 hung SpringBoard at the Apple logo without one SpringBoard line in the
// log. OMCLogFlush was a dispatch_sync on the log queue called from %ctor, i.e. while dyld runs initializers holding its
// lock, and in SpringBoard the queued block goes through NSFileManager (log rotation), which can need that same lock.
// Now nothing in a constructor waits on another thread: lines are already on disk (OMCLogWrite writes them directly),
// so flushing is a no-op then, and only later, outside dyld's lock, it waits for the queue.
void OMCLogFlush(void) {
	if (OMCLogDirect()) return;
	if (!OMCLogOnQueue()) dispatch_sync(OMCLogQueue(), ^{});
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

// First OmniCar<Name>.dylib in the backtrace -> <Name>. Frames of the crash guard itself are skipped: the signal handler
// runs in whichever feature dylib installed it (frame 0 of every crash), which named Speed Bubble for a Split Screen
// assert on 19/10 (log 21:59, iPhone 8 15.6: frame 0 OmniCarSpeedBubble OMCCrashGuard, frame 4 OmniCarSplitScreen).
static void OMCGuardSuspect(void *const *frames, int count, char *out, size_t size) {
	out[0] = 0;
	for (int i = 0; i < count; i++) {
		Dl_info info;
		if (!dladdr(frames[i], &info) || !info.dli_fname) continue;
		if (info.dli_sname && strncmp(info.dli_sname, "OMCGuard", 8) == 0) continue;
		if (info.dli_sname && strncmp(info.dli_sname, "OMCCrashGuard", 13) == 0) continue;
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
static void OMCPerfBegin(UIScreen *screen);
static void OMCPerfEnd(void);
static void OMCProfileSwitch(NSDictionary *car);

static void OMCRecordCarScreen(UIScreen *screen) {
	if (!screen || screen == [UIScreen mainScreen]) return;
	OMCPerfBegin(screen);
	NSMutableDictionary *car = [NSMutableDictionary dictionary];
	car[@"date"] = [NSDate date];
	car[@"connected"] = @YES;
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
	OMCProfileSwitch(car);
	OMCLog(@"Core", @"man xe %@ pt, %@ px, %@ fps, session=%d", car[@"points"], car[@"pixels"], car[@"maxFPS"], car[@"session"] != nil);
}

#pragma mark - Car profiles

static NSString *OMCCarValue(NSDictionary *car, NSArray<NSString *> *names) {
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

static NSDictionary *OMCProfileSnapshot(void) {
	NSMutableDictionary *values = [NSMutableDictionary dictionary];
	for (NSString *key in OMCProfileKeys()) {
		id v = OMCPref(key, nil);
		if (v) values[key] = v;
	}
	return values;
}

// A car just connected: save the settings into the car that was in use, load this car's (see OMC_KEY_PROFILES)
static void OMCProfileSwitch(NSDictionary *car) {
	OMCPrefsSync();
	if (![OMCPref(OMC_KEY_PROFILES_ON, @NO) boolValue]) return;
	NSString *name = OMCCarValue(car, @[@"modelName", @"name", @"vehicleName", @"accessoryName", @"model"]);
	NSString *ident = OMCCarValue(car, @[@"vehicleIdentifier", @"identifier", @"uniqueIdentifier", @"accessoryID", @"deviceID", @"serialNumber"]);
	NSString *key = ident ?: [NSString stringWithFormat:@"%@|%@", name ?: @"?", car[@"pixels"] ?: @"?"];
	NSMutableDictionary *all = [NSMutableDictionary dictionary];
	NSDictionary *stored = OMCPref(OMC_KEY_PROFILES, nil);
	if ([stored isKindOfClass:[NSDictionary class]])
		for (NSString *k in stored) if ([stored[k] isKindOfClass:[NSDictionary class]]) all[k] = [stored[k] mutableCopy];
	NSString *current = OMCPref(OMC_KEY_PROFILE_CURRENT, nil);
	if ([current isKindOfClass:[NSString class]] && all[current] && ![current isEqualToString:key])
		all[current][@"values"] = OMCProfileSnapshot();   // what the user set while in the previous car
	NSMutableDictionary *profile = all[key];
	if (!profile) {
		profile = [@{@"values": OMCProfileSnapshot()} mutableCopy];
		all[key] = profile;
		OMCLog(@"Core", @"ho so xe moi: %@ (%@)", name ?: @"?", key);
	} else if (![current isEqual:key]) {
		NSDictionary *values = profile[@"values"];
		for (NSString *k in OMCProfileKeys()) {
			id v = [values isKindOfClass:[NSDictionary class]] ? values[k] : nil;
			CFPreferencesSetAppValue((__bridge CFStringRef)k, (__bridge CFPropertyListRef)v, OMC_PREFS_DOMAIN);
		}
		OMCLog(@"Core", @"nap ho so xe %@ (%@)", name ?: @"?", key);
	}
	profile[@"name"] = name ?: OMCTr(@"Xe", @"Car");
	profile[@"lastSeen"] = [NSDate date];
	OMCGuardStore(OMC_KEY_PROFILES, all);
	OMCGuardStore(OMC_KEY_PROFILE_CURRENT, key);
	OMCPrefsSync();
	notify_post("com.anlai.omnicar/prefschanged");
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
		NSDate *when = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileModificationDate ?: [NSDate date];
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
		NSMutableDictionary *crash = [@{@"date": when} mutableCopy];   // Diagnostics: "CarPlay crashed at ..."
		if (age != LONG_MAX) crash[@"age"] = @(age);
		if (who) crash[@"suspect"] = who;
		OMCGuardStore(OMC_KEY_DIAG_CRASH, crash);
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
	// Car unplugged: Diagnostics shows "last connected at" instead of "connected"
	[[NSNotificationCenter defaultCenter] addObserverForName:UIScreenDidDisconnectNotification object:nil
		queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		if (note.object == [UIScreen mainScreen]) return;
		OMCPerfEnd();
		NSMutableDictionary *car = [OMCPref(OMC_KEY_DIAG_CAR, nil) mutableCopy];
		if (![car isKindOfClass:[NSMutableDictionary class]]) return;
		car[@"connected"] = @NO;
		car[@"disconnected"] = [NSDate date];
		OMCGuardStore(OMC_KEY_DIAG_CAR, car);
		OMCPrefsSync();
	}];
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

#pragma mark - Performance monitor (Diagnostics, CarPlay)

// How smooth CarPlay ran on the last drive, for the Diagnostics page (OMC_KEY_DIAG_PERF). Runs in the CarPlay
// process from the dylib that started the crash guard (once per process), while a car screen is connected.
// Cheap on purpose: a 4 Hz ping to the main thread (hangs), CPU / memory every 5 s, and a display link on the
// car screen only 10 s of every minute (late frames). Everything but the watchdog runs on the main thread.

static UIScreen *sPerfScreen;
static CADisplayLink *sPerfLink;
static NSUInteger sPerfGeneration;
static dispatch_source_t sPerfTimer;
static atomic_bool sPerfPending;
static NSDate *sPerfStart;
static NSArray<NSString *> *sPerfTweaks;
static NSMutableDictionary<NSString *, NSNumber *> *sPerfHangWho;
static double sPerfFrameTime, sPerfLastFrame, sPerfFrames, sPerfLate, sPerfWorstMs;
static double sPerfHangs, sPerfFreezes, sPerfHangMaxMs;
static double sPerfCpuSum, sPerfCpuMax, sPerfMem, sPerfMemMax, sPerfAvailMin, sPerfSysFreeMin;
static NSUInteger sPerfSamples;
static NSInteger sPerfThermalMax;
static BOOL sPerfLowPower;
// Auto lite mode: late frames of the last 10 s window (%, -1 = none yet), the last three hangs, current state
static double sPerfWinFrames, sPerfWinLate, sPerfLastWinPct;
static double sPerfHangAt[3];
static BOOL sPerfLite;
static double sPerfLiteAt;
static NSUInteger sPerfLiteCount;
static NSString *sPerfLiteReason;

static double OMCNow(void) {
	static mach_timebase_info_data_t tb;
	if (!tb.denom) mach_timebase_info(&tb);
	return (double)mach_absolute_time() * tb.numer / tb.denom / 1e9;
}

// % of one core, all threads of this process
static double OMCPerfCPU(void) {
	thread_act_array_t threads;
	mach_msg_type_number_t count = 0;
	if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) return -1;
	double total = 0;
	for (mach_msg_type_number_t i = 0; i < count; i++) {
		thread_basic_info_data_t info;
		mach_msg_type_number_t n = THREAD_BASIC_INFO_COUNT;
		if (thread_info(threads[i], THREAD_BASIC_INFO, (thread_info_t)&info, &n) == KERN_SUCCESS && !(info.flags & TH_FLAGS_IDLE))
			total += info.cpu_usage * 100.0 / TH_USAGE_SCALE;
		mach_port_deallocate(mach_task_self(), threads[i]);
	}
	vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_t));
	return total;
}

static double OMCPerfFootprintMB(void) {
	task_vm_info_data_t info;
	mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &n) != KERN_SUCCESS) return -1;
	return info.phys_footprint / 1048576.0;
}

// Free + inactive pages: what the phone can hand out without killing an app
static double OMCPerfSysFreeMB(void) {
	static mach_port_t host;
	static vm_size_t page;
	if (!host) { host = mach_host_self(); host_page_size(host, &page); }
	vm_statistics64_data_t vm;
	mach_msg_type_number_t n = HOST_VM_INFO64_COUNT;
	if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &n) != KERN_SUCCESS) return -1;
	return (double)(vm.free_count + vm.inactive_count) * page / 1048576.0;
}

// Other tweaks the loader injected into CarPlay (each one is code on CarPlay's event and drawing paths)
static NSArray<NSString *> *OMCPerfTweaks(void) {
	NSMutableOrderedSet<NSString *> *out = [NSMutableOrderedSet orderedSet];
	for (uint32_t i = 0; i < _dyld_image_count(); i++) {
		const char *path = _dyld_get_image_name(i);
		if (!path || (!strstr(path, "/DynamicLibraries/") && !strstr(path, "/TweakInject/"))) continue;
		NSString *name = @(path).lastPathComponent.stringByDeletingPathExtension;
		if (![name hasPrefix:@"OmniCar"]) [out addObject:name];
	}
	return out.array;
}

static void OMCPerfSave(void) {
	double seconds = sPerfStart ? -[sPerfStart timeIntervalSinceNow] : 0;
	if (seconds < 30) return;   // a quick plug-in-and-out keeps the previous drive
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	d[@"start"] = sPerfStart;
	d[@"updated"] = [NSDate date];
	d[@"seconds"] = @(lround(seconds));
	d[@"fps"] = @(lround(1 / sPerfFrameTime));
	d[@"frames"] = @(lround(sPerfFrames));
	d[@"late"] = @(lround(sPerfLate));
	d[@"worstMs"] = @(lround(sPerfWorstMs));
	d[@"hangs"] = @(lround(sPerfHangs));
	d[@"freezes"] = @(lround(sPerfFreezes));
	d[@"hangMaxMs"] = @(lround(sPerfHangMaxMs));
	if (sPerfHangWho.count) d[@"hangWho"] = [sPerfHangWho copy];
	if (sPerfSamples) {
		d[@"cpuAvg"] = @(lround(sPerfCpuSum / sPerfSamples));
		d[@"cpuMax"] = @(lround(sPerfCpuMax));
		d[@"memMB"] = @(lround(sPerfMem));
		d[@"memMaxMB"] = @(lround(sPerfMemMax));
		d[@"availMinMB"] = @(sPerfAvailMin < DBL_MAX ? lround(sPerfAvailMin) : 0);
		d[@"sysFreeMinMB"] = @(sPerfSysFreeMin < DBL_MAX ? lround(sPerfSysFreeMin) : 0);
	}
	d[@"thermalMax"] = @(sPerfThermalMax);
	d[@"lowPower"] = @(sPerfLowPower);
	d[@"tweaks"] = sPerfTweaks ?: @[];
	d[@"liteCount"] = @(sPerfLiteCount);
	if (sPerfLiteReason) d[@"liteReason"] = sPerfLiteReason;
	OMCGuardStore(OMC_KEY_DIAG_PERF, d);
	OMCPrefsSync();
}

static void OMCPerfHang(double seconds) {
	sPerfHangs++;
	if (seconds >= 2) sPerfFreezes++;
	sPerfHangMaxMs = MAX(sPerfHangMaxMs, seconds * 1000);
	// A weak hint for the developer only: the OmniCar dylib that logged last
	OMCGuardState *g = OMCGuardShared();
	NSString *who = g && g->lastFeature[0] ? @(g->lastFeature) : @"-";
	sPerfHangWho[who] = @(sPerfHangWho[who].integerValue + 1);
	sPerfHangAt[0] = sPerfHangAt[1];
	sPerfHangAt[1] = sPerfHangAt[2];
	sPerfHangAt[2] = OMCNow();
	if (seconds >= 2) OMCLog(@"Core", @"CarPlay do %.1fs (OmniCar gan nhat: %@)", seconds, who);
}

static void OMCPerfFrame(void) {
	double now = OMCNow();
	if (sPerfLastFrame > 0) {
		double gap = now - sPerfLastFrame;
		double missed = gap > sPerfFrameTime * 1.5 ? round(gap / sPerfFrameTime) - 1 : 0;
		sPerfFrames += 1 + missed;
		sPerfLate += missed;
		sPerfWorstMs = MAX(sPerfWorstMs, gap * 1000);
	}
	sPerfLastFrame = now;
}

// The display link needs a target object; Core has no classes (it is compiled into every dylib), so one is
// made at runtime. Only the dylib running the monitor (one per process) ever creates it.
static id OMCPerfTicker(void) {
	static id ticker;
	if (ticker) return ticker;
	Class cls = objc_getClass("OMCPerfTicker");
	if (!cls) {
		cls = objc_allocateClassPair([NSObject class], "OMCPerfTicker", 0);
		class_addMethod(cls, sel_registerName("tick:"), imp_implementationWithBlock(^(id me, id link) { OMCPerfFrame(); }), "v@:@");
		objc_registerClassPair(cls);
	}
	ticker = [cls new];
	return ticker;
}

static void OMCPerfFrameWindow(void) {
	if (!sPerfScreen || sPerfLink) return;
	sPerfLink = [sPerfScreen displayLinkWithTarget:OMCPerfTicker() selector:sel_registerName("tick:")];
	sPerfLastFrame = 0;
	sPerfWinFrames = sPerfFrames;
	sPerfWinLate = sPerfLate;
	[sPerfLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	NSUInteger generation = sPerfGeneration;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (generation != sPerfGeneration) return;
		[sPerfLink invalidate];
		sPerfLink = nil;
		double frames = sPerfFrames - sPerfWinFrames;
		if (frames >= 100) sPerfLastWinPct = (sPerfLate - sPerfWinLate) * 100 / frames;
	});
}

static void OMCPerfPublishLite(BOOL on) {
	static int token = -1;
	if (token == -1 && notify_register_check(OMC_DARWIN_LITE, &token) != NOTIFY_STATUS_OK) token = -1;
	if (token != -1) notify_set_state(token, on ? 1 : 0);
	notify_post(OMC_DARWIN_LITE);
}

static void OMCPerfSetLite(BOOL on, NSString *reason) {
	if (on == sPerfLite) return;
	sPerfLite = on;
	sPerfLiteAt = OMCNow();
	if (on) { sPerfLiteCount++; sPerfLiteReason = reason; }
	OMCPerfPublishLite(on);
	OMCLog(@"Core", @"che do nhe tu dong: %@%@", on ? @"BAT" : @"tat", on ? [@" vi " stringByAppendingString:reason] : @"");
}

// Auto lite mode, every 5 s: on when the phone is hot, CarPlay hung 3 times within 2 minutes or the last frame
// window had >= 15 % late frames; off after 3 calm minutes (cool, no hang, smooth frames).
static void OMCPerfLiteCheck(NSProcessInfoThermalState thermal) {
	if (!OMCEnabled() || [OMCPref(OMC_KEY_LITE_MODE, @2) integerValue] != 2) { OMCPerfSetLite(NO, nil); return; }
	double now = OMCNow();
	NSString *reason = nil;
	if (thermal >= NSProcessInfoThermalStateSerious) reason = @"heat";
	else if (sPerfHangAt[0] > 0 && now - sPerfHangAt[0] < 120) reason = @"hangs";
	else if (sPerfLastWinPct >= 15) reason = @"frames";
	if (reason) { OMCPerfSetLite(YES, reason); return; }
	BOOL calm = thermal <= NSProcessInfoThermalStateFair && (sPerfHangAt[2] == 0 || now - sPerfHangAt[2] > 180) && sPerfLastWinPct < 5;
	if (sPerfLite && calm && now - sPerfLiteAt > 180) OMCPerfSetLite(NO, nil);
}

static void OMCPerfSample(double cpu, double mem, double avail, double sysFree) {
	if (!sPerfScreen) return;
	sPerfSamples++;
	if (cpu >= 0) { sPerfCpuSum += cpu; sPerfCpuMax = MAX(sPerfCpuMax, cpu); }
	if (mem >= 0) { sPerfMem = mem; sPerfMemMax = MAX(sPerfMemMax, mem); }
	if (avail > 0) sPerfAvailMin = MIN(sPerfAvailMin, avail);
	if (sysFree >= 0) sPerfSysFreeMin = MIN(sPerfSysFreeMin, sysFree);
	NSProcessInfo *info = [NSProcessInfo processInfo];
	sPerfThermalMax = MAX(sPerfThermalMax, (NSInteger)info.thermalState);
	if (info.lowPowerModeEnabled) sPerfLowPower = YES;
	if (sPerfSamples % 2 == 0) OMCPrefsSync();   // lite mode switched in Settings while driving
	OMCPerfLiteCheck(info.thermalState);
	// Frames from the 20th second (the startup screen is done), then every minute; saved every 30 s
	if (sPerfSamples % 12 == 4) OMCPerfFrameWindow();
	if (sPerfSamples % 6 == 0) OMCPerfSave();
}

// Watchdog queue, 4 Hz: is the main thread answering? Every 5 s: CPU and memory.
static void OMCPerfWatch(void) {
	static unsigned tick;
	double sent = OMCNow();
	bool idle = false;
	if (atomic_compare_exchange_strong(&sPerfPending, &idle, true)) {
		dispatch_async(dispatch_get_main_queue(), ^{
			double stuck = OMCNow() - sent;
			atomic_store(&sPerfPending, false);
			if (stuck >= 0.5 && sPerfScreen) OMCPerfHang(stuck);
		});
	}
	if (++tick % 20) return;
	double cpu = OMCPerfCPU(), mem = OMCPerfFootprintMB(), sysFree = OMCPerfSysFreeMB();
	double avail = os_proc_available_memory() / 1048576.0;
	dispatch_async(dispatch_get_main_queue(), ^{ OMCPerfSample(cpu, mem, avail, sysFree); });
}

static void OMCPerfBegin(UIScreen *screen) {
	if (sPerfScreen) return;
	sPerfScreen = screen;
	sPerfGeneration++;
	sPerfStart = [NSDate date];
	sPerfTweaks = OMCPerfTweaks();
	sPerfHangWho = [NSMutableDictionary dictionary];
	sPerfFrameTime = 1.0 / MAX(screen.maximumFramesPerSecond, 1);
	sPerfLastFrame = sPerfFrames = sPerfLate = sPerfWorstMs = 0;
	sPerfHangs = sPerfFreezes = sPerfHangMaxMs = 0;
	sPerfCpuSum = sPerfCpuMax = sPerfMem = sPerfMemMax = 0;
	sPerfAvailMin = sPerfSysFreeMin = DBL_MAX;
	sPerfSamples = 0;
	sPerfThermalMax = 0;
	sPerfLowPower = NO;
	sPerfWinFrames = sPerfWinLate = 0;
	sPerfLastWinPct = -1;
	memset(sPerfHangAt, 0, sizeof sPerfHangAt);
	sPerfLiteCount = 0;
	sPerfLiteReason = nil;
	sPerfLite = NO;
	OMCPerfPublishLite(NO);   // a state left by a CarPlay that crashed while lite was on
	atomic_store(&sPerfPending, false);
	dispatch_queue_t queue = dispatch_queue_create("com.anlai.omnicar.perf", DISPATCH_QUEUE_SERIAL);
	sPerfTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
	dispatch_source_set_timer(sPerfTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), NSEC_PER_SEC / 4, NSEC_PER_SEC / 20);
	dispatch_source_set_event_handler(sPerfTimer, ^{ OMCPerfWatch(); });
	dispatch_resume(sPerfTimer);
	notify_post(OMC_DARWIN_CAR_CONNECTED);   // SpringBoard: free memory (Core.x)
	OMCLog(@"Core", @"do hieu nang: bat dau, %lu tweak khac trong CarPlay: %@", (unsigned long)sPerfTweaks.count,
		[sPerfTweaks componentsJoinedByString:@", "]);
}

static void OMCPerfEnd(void) {
	if (!sPerfScreen) return;
	if (sPerfTimer) dispatch_source_cancel(sPerfTimer);
	sPerfTimer = nil;
	[sPerfLink invalidate];
	sPerfLink = nil;
	sPerfGeneration++;
	OMCPerfSave();
	OMCLog(@"Core", @"do hieu nang: %.0fs, tre %.0f/%.0f khung, do %.0f lan (max %.0f ms), CPU tb %.0f%%, RAM %.0f MB",
		-[sPerfStart timeIntervalSinceNow], sPerfLate, sPerfFrames, sPerfHangs, sPerfHangMaxMs,
		sPerfSamples ? sPerfCpuSum / sPerfSamples : 0, sPerfMemMax);
	OMCPerfSetLite(NO, nil);
	sPerfScreen = nil;
}

#pragma mark - Loaded heartbeat (Diagnostics)

#ifndef TWEAK_VERSION
#define TWEAK_VERSION "dev"
#endif
#ifndef OMC_BUILD
#define OMC_BUILD "dev"
#endif

// Every dylib records that it loaded into SpringBoard / CarPlay and which build it is. Other processes (App Bridge
// loads into every app, many sandboxed) are skipped: they cannot write the prefs domain and are not what Settings checks.
__attribute__((constructor)) static void OMCDiagLoaded(void) {
	NSString *process = [NSProcessInfo processInfo].processName;
	if (![process isEqualToString:@"SpringBoard"] && ![process isEqualToString:@"CarPlay"]) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		OMCLog(@OMC_FEATURE, @"build %s (%s) loaded into %@", OMC_BUILD, TWEAK_VERSION, process);
		NSString *key = [NSString stringWithFormat:@"%@%s@%@", OMC_KEY_DIAG_LOADED, OMC_FEATURE, process];
		NSDictionary *value = @{@"version": @TWEAK_VERSION, @"build": @OMC_BUILD, @"date": [NSDate date]};
		CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, OMC_PREFS_DOMAIN);
		CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
	});
}
