// Car Probe - developer only: a one-shot report of CarPlay's private home-screen classes and objects, for the
// ROADMAP-DEV level 2 items (hide / sort CarPlay home apps, icon size, rows / columns + labels, home wallpaper,
// custom dock, which pane plays audio, steering-wheel voice button) that need DashBoard.framework (iOS 16) or
// CarPlay.app's CAR* classes (iOS 14 / 15, see OMCCarClass) and no device to look at them.
//
// Runs inside CarPlay.app (com.apple.CarPlayApp) and writes /var/mobile/Documents/OmniCar-Probe.txt (3 MB max),
// then one line in OmniCar.log saying where. How to run it:
//   - connect the car: the report is written ~8 s after a car screen appears (once per connection);
//   - any time while CarPlay runs: post the Darwin notification "com.anlai.omnicar/probe" from any process,
//     e.g. notify_post("com.anlai.omnicar/probe") from a Diagnostics button later, or over SSH
//     `notifyutil -p com.anlai.omnicar/probe` when notifyutil is installed.
//
// Report: header (iOS, device, screens, OMCCarClass map) / every window on the car screen as a view tree (class,
// frame, hidden / alpha, accessibility id, owning view controller, label text, icon bundle id / name) / home icon
// order read from the icon list views' models / properties of the home views (icon lists, dock, wallpaper, layout,
// status bar) and of the view controllers on the car screen / the app library in use and its apps / CarKit session,
// configuration, paired vehicles / DBEvent (CAREvent) / CarPlay preference files / WHERE iOS KEEPS THE CARPLAY CUSTOMIZE
// LIST (files under /var/mobile that contain the bundle ids of the apps on the home screen, the key path inside each
// plist, and which of them changed since the previous probe: run once, change iOS Settings > General > CarPlay > car >
// Customize, run again) / the class names of DashBoard,
// CarPlay, CarPlayUIServices and CarKit / a method index by keyword (siri, voice, button, event, wallpaper, dock ...)
// / class details (superclass chain, protocols, ivars, properties, methods + type encodings) of every class seen on
// the car screen and of every class in those images whose name has Icon, Dock, Wallpaper, Home, Dashboard, Library,
// Layout, StatusBar, Siri, Voice, Audio, NowPlaying, Button or Event.
//
// Crash safety: nothing is hooked. Objects are only read through zero-argument getters named by their class's
// property list (plus a handful of named read-only accessors: sharedApplicationLibrary, library, currentSession,
// allInstalledApplications, icons ...), never one starting with set / remove / delete / launch / open / activate /
// perform (or another verb, see CPSafeGetterName), only when the return type can be boxed; each section runs in
// @try. +[DashBoard _newApplicationLibrary] is NOT called (it builds a second library): its encoding is listed and
// the library DashBoard already uses is dumped instead.
//
// Built only with OMC_AUTOTEST (Core/OmniCar.h): `make package OMC_AUTOTEST=0` gives an empty OmniCarCarProbe.dylib.
// No settings page and no plist entry: it never shows on the root page.

#import "OmniCar.h"

#if OMC_AUTOTEST
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <notify.h>
#import <sys/utsname.h>

#define CPLog(fmt, ...) OMCLog(@"CarProbe", fmt, ##__VA_ARGS__)

#define CP_REPORT_PATH  @"/var/mobile/Documents/OmniCar-Probe.txt"
#define CP_DARWIN_PROBE "com.anlai.omnicar/probe"
#define CP_MAX_BYTES    (3 * 1024 * 1024)
#define CP_AUTO_DELAY   8.0
#define CP_TREE_DEPTH   30     // view tree depth limit
#define CP_RUN_SHOWN    3      // siblings of one class in a row: the first 3 are shown in full
#define CP_OBJ_PROPS    150    // property values per object
#define CP_OBJ_SEEN     80     // objects per object dump (recursion)
#define CP_INDEX_LINES  5000   // method index
#define CP_FILES_PATH   @"/var/mobile/Documents/OmniCar-ProbeFiles.plist"   // last probe's matching files (path -> [mtime, size])
#define CP_SCAN_FILES   60000  // files looked at per scan
#define CP_SCAN_BYTES   (4 * 1024 * 1024)   // bigger files are skipped

#ifndef TWEAK_VERSION
#define TWEAK_VERSION "dev"
#endif

static NSMutableString *sOut;
static BOOL sFull;
static BOOL sRunning;
static id sSessionStatus;   // CARSessionStatus, kept: it fills currentSession in asynchronously
static NSMutableOrderedSet<NSString *> *sHomeBundles;   // bundle ids of the home icons (CPDumpIconLists), for the file scan

#pragma mark - Report text

static void CPAppend(NSString *s) {
	if (sFull || !s) return;
	// UTF-16 units: the report is ASCII but for names and labels, the UTF-8 data is cut at 3 MB again on write.
	if (sOut.length + s.length > CP_MAX_BYTES - 4096) {
		sFull = YES;
		[sOut appendString:@"\n[REPORT TRUNCATED: 3 MB cap]\n"];
		return;
	}
	[sOut appendString:s];
}

static void CPLine(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void CPLine(NSString *fmt, ...) {
	if (sFull) return;
	va_list ap;
	va_start(ap, fmt);
	NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
	va_end(ap);
	CPAppend([s stringByAppendingString:@"\n"]);
}

static void CPSection(NSString *title) {
	CPLine(@"\n==================== %@ ====================", title);
}

static NSString *CPShort(NSString *s, NSUInteger max) {
	if (!s) return @"nil";
	s = [[s componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
	return s.length > max ? [[s substringToIndex:max] stringByAppendingString:@"..."] : s;
}

static NSString *CPIndent(NSUInteger n) {
	return [@"" stringByPaddingToLength:n withString:@" " startingAtIndex:0];
}

static NSString *CPClassChain(Class cls) {
	NSMutableArray *chain = [NSMutableArray array];
	for (Class c = cls; c; c = class_getSuperclass(c)) [chain addObject:NSStringFromClass(c)];
	return [chain componentsJoinedByString:@" < "];
}

static NSString *CPImageOf(Class cls) {
	const char *image = cls ? class_getImageName(cls) : NULL;
	return image ? @(image).lastPathComponent : @"?";
}

// UIKit / Foundation / QuartzCore classes: their properties are not dumped and their objects not followed.
static BOOL CPSystemClass(Class cls) {
	if (!cls) return YES;
	NSString *n = NSStringFromClass(cls);
	for (NSString *p in @[@"NS", @"__NS", @"_NS", @"UI", @"_UI", @"CA", @"OS_", @"__"]) if ([n hasPrefix:p]) return YES;
	return NO;
}

static BOOL CPNameMatches(NSString *name, NSArray<NSString *> *words) {
	NSString *low = name.lowercaseString;
	for (NSString *w in words) if ([low containsString:w]) return YES;
	return NO;
}

static NSArray<NSString *> *CPClassWords(void) {
	return @[@"icon", @"dock", @"wallpaper", @"home", @"dashboard", @"library", @"layout", @"statusbar", @"siri", @"voice",
		@"audio", @"nowplaying", @"button", @"event"];
}

#pragma mark - Safe getters

// A getter the probe may call: no argument, and not a verb. set / remove / delete / launch / open / activate /
// perform are refused as any prefix ("settings" too); the other verbs only as a whole word, i.e. followed by an
// uppercase letter, "_" or nothing ("startMonitoring", "reloadData" refused; "started", "handler", "showsLabel" pass).
static BOOL CPSafeGetterName(NSString *name) {
	if (!name.length || [name containsString:@":"]) return NO;
	static NSSet *exact;
	static NSArray *strict, *verbs;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		exact = [NSSet setWithArray:@[@"description", @"debugDescription", @"hash", @"superclass", @"class", @"self", @"retain",
			@"release", @"autorelease", @"dealloc", @"retainCount", @"zone", @"copy", @"mutableCopy", @"new", @"init", @"alloc",
			@"layoutIfNeeded", @"layoutSubviews", @"becomeFirstResponder", @"resignFirstResponder"]];
		strict = @[@"set", @"remove", @"delete", @"launch", @"open", @"activate", @"perform"];
		verbs = @[@"new", @"copy", @"mutableCopy", @"init", @"alloc", @"dealloc", @"invalidate", @"reset", @"reload", @"start",
			@"stop", @"clear", @"dismiss", @"present", @"show", @"hide", @"add", @"insert", @"send", @"post", @"request", @"load",
			@"update", @"save", @"write", @"cancel", @"terminate", @"kill", @"suspend", @"resume", @"toggle", @"begin", @"end",
			@"play", @"pause", @"register", @"unregister", @"lock", @"unlock", @"make", @"create", @"flush", @"handle",
			@"dispatch", @"trigger", @"fire", @"run", @"invoke", @"exit", @"quit", @"restart", @"reboot", @"purge", @"prune",
			@"deactivate", @"close", @"connect", @"disconnect", @"enable", @"disable", @"commit", @"apply", @"notify",
			@"select", @"deselect", @"animate", @"become", @"resign", @"sync", @"fetch", @"refresh"];
	});
	if ([exact containsObject:name]) return NO;
	NSString *bare = name;
	while ([bare hasPrefix:@"_"]) bare = [bare substringFromIndex:1];
	if (!bare.length) return NO;
	for (NSString *verb in strict) if ([bare hasPrefix:verb]) return NO;
	for (NSString *verb in verbs) {
		if (![bare hasPrefix:verb]) continue;
		if (bare.length == verb.length) return NO;
		unichar next = [bare characterAtIndex:verb.length];
		if ((next >= 'A' && next <= 'Z') || next == '_') return NO;
	}
	return YES;
}

static const char *CPStripQualifiers(const char *t) {
	while (t && *t && strchr("rnNoORVA", *t)) t++;
	return t;
}

// Objects (not blocks), Class, SEL, scalars and small structs; never pointers, C strings, unions, arrays, bitfields.
static BOOL CPBoxableType(const char *t) {
	t = CPStripQualifiers(t);
	if (!t || !*t) return NO;
	if (t[0] == '@') return t[1] != '?';
	if (t[0] == '{') return YES;
	return strchr("#:BcCsSiIlLqQfd", t[0]) != NULL;
}

static NSString *CPGetterName(objc_property_t p) {
	char *g = property_copyAttributeValue(p, "G");
	NSString *name = g ? @(g) : @(property_getName(p));
	free(g);
	return name;
}

static BOOL CPPropertyBoxable(objc_property_t p) {
	char *t = property_copyAttributeValue(p, "T");
	BOOL ok = t && CPBoxableType(t);
	free(t);
	return ok;
}

static NSString *CPShortObject(id v) {
	if (!v) return @"nil";
	if (object_isClass(v)) return [NSString stringWithFormat:@"class %@", NSStringFromClass((Class)v)];
	NSString *desc = nil;
	@try {
		if ([v isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"\"%@\"", CPShort(v, 200)];
		desc = [v description];
	} @catch (NSException *e) { desc = [NSString stringWithFormat:@"<%@ %p: description threw>", NSStringFromClass(object_getClass(v)), v]; }
	return CPShort(desc, 220);
}

static NSString *CPDescribe(id v) {
	if (!v) return @"nil";
	@try {
		if (object_isClass(v)) return CPShortObject(v);
		if ([v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSSet class]] || [v isKindOfClass:[NSOrderedSet class]]) {
			NSMutableArray *parts = [NSMutableArray array];
			NSUInteger n = 0, count = [v count];
			for (id item in v) {
				if (n++ >= 6) break;
				[parts addObject:CPShortObject(item)];
			}
			return [NSString stringWithFormat:@"<%@ count=%lu> [%@%@]", NSStringFromClass(object_getClass(v)), (unsigned long)count,
				[parts componentsJoinedByString:@", "], count > 6 ? @", ..." : @""];
		}
		if ([v isKindOfClass:[NSDictionary class]]) {
			NSMutableArray *parts = [NSMutableArray array];
			NSUInteger n = 0, count = [v count];
			for (id key in v) {
				if (n++ >= 8) break;
				[parts addObject:[NSString stringWithFormat:@"%@: %@", CPShortObject(key), CPShort(CPShortObject(v[key]), 100)]];
			}
			return [NSString stringWithFormat:@"<%@ count=%lu> {%@%@}", NSStringFromClass(object_getClass(v)), (unsigned long)count,
				[parts componentsJoinedByString:@", "], count > 8 ? @", ..." : @""];
		}
	} @catch (NSException *e) {}
	return CPShortObject(v);
}

static NSString *CPStructText(const char *rt, const void *buf, NSUInteger len) {
	if (!strncmp(rt, "{CGRect=", 8) && len >= sizeof(CGRect)) { CGRect r; memcpy(&r, buf, sizeof r); return NSStringFromCGRect(r); }
	if (!strncmp(rt, "{CGSize=", 8) && len >= sizeof(CGSize)) { CGSize s; memcpy(&s, buf, sizeof s); return NSStringFromCGSize(s); }
	if (!strncmp(rt, "{CGPoint=", 9) && len >= sizeof(CGPoint)) { CGPoint p; memcpy(&p, buf, sizeof p); return NSStringFromCGPoint(p); }
	if (!strncmp(rt, "{UIEdgeInsets=", 14) && len >= sizeof(UIEdgeInsets)) {
		UIEdgeInsets i; memcpy(&i, buf, sizeof i); return NSStringFromUIEdgeInsets(i);
	}
	if (!strncmp(rt, "{NSDirectionalEdgeInsets=", 25) && len >= sizeof(NSDirectionalEdgeInsets)) {
		NSDirectionalEdgeInsets i; memcpy(&i, buf, sizeof i); return NSStringFromDirectionalEdgeInsets(i);
	}
	if (!strncmp(rt, "{CGAffineTransform=", 19) && len >= sizeof(CGAffineTransform)) {
		CGAffineTransform t; memcpy(&t, buf, sizeof t); return NSStringFromCGAffineTransform(t);
	}
	if (!strncmp(rt, "{_NSRange=", 10) && len >= sizeof(NSRange)) { NSRange r; memcpy(&r, buf, sizeof r); return NSStringFromRange(r); }
	// Other structs (SBIconImageInfo ...): name, then the bytes as doubles when they fit (most are CGFloat fields).
	const char *eq = strchr(rt, '=');
	NSString *name = eq ? [[NSString alloc] initWithBytes:rt + 1 length:(NSUInteger)(eq - rt - 1) encoding:NSUTF8StringEncoding] : @"?";
	NSMutableString *out = [NSMutableString stringWithFormat:@"{%@ %lu bytes:", name, (unsigned long)len];
	if (len % sizeof(double) == 0) {
		for (NSUInteger i = 0; i < len / sizeof(double) && i < 8; i++) {
			double d; memcpy(&d, (const uint8_t *)buf + i * sizeof(double), sizeof d);
			[out appendFormat:@" %g", d];
		}
	} else {
		for (NSUInteger i = 0; i < len && i < 32; i++) [out appendFormat:@" %02x", ((const uint8_t *)buf)[i]];
	}
	[out appendString:@"}"];
	return out;
}

// Calls a zero-argument getter of target (an object, or a Class for its class methods) and formats the result.
// *object gets the result when it is an object. nil: no such getter, or a type the probe does not box.
static NSString *CPCall(id target, SEL sel, id *object) {
	if (object) *object = nil;
	if (!target || !sel || !CPSafeGetterName(NSStringFromSelector(sel))) return nil;
	@try {
		Method m = class_getInstanceMethod(object_getClass(target), sel);
		if (!m || method_getNumberOfArguments(m) != 2) return nil;
		const char *types = method_getTypeEncoding(m);
		if (!types) return nil;
		NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:types];
		if (!sig || sig.numberOfArguments != 2) return nil;
		const char *rt = CPStripQualifiers(sig.methodReturnType);
		NSUInteger len = sig.methodReturnLength;
		if (!CPBoxableType(rt) || len > 256) return nil;
		NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
		inv.target = target;
		inv.selector = sel;
		[inv invoke];
		uint8_t buf[256];
		memset(buf, 0, sizeof buf);
		if (len) [inv getReturnValue:buf];
		switch (rt[0]) {
			case '@': {
				void *raw = NULL;
				memcpy(&raw, buf, sizeof raw);
				id value = (__bridge id)raw;
				if (object) *object = value;
				return CPDescribe(value);
			}
			case '#': { void *raw = NULL; memcpy(&raw, buf, sizeof raw); return raw ? NSStringFromClass((__bridge Class)raw) : @"Nil"; }
			case ':': { SEL s = NULL; memcpy(&s, buf, sizeof s); return s ? [@"@selector " stringByAppendingString:NSStringFromSelector(s)] : @"NULL"; }
			case 'B': { bool v; memcpy(&v, buf, sizeof v); return v ? @"YES" : @"NO"; }
			case 'c': { signed char v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%d", (int)v]; }
			case 'C': { unsigned char v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%u", (unsigned)v]; }
			case 's': { short v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%d", (int)v]; }
			case 'S': { unsigned short v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%u", (unsigned)v]; }
			case 'i': { int v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%d", v]; }
			case 'I': { unsigned int v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%u", v]; }
			case 'l': { long v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%ld", v]; }
			case 'L': { unsigned long v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%lu", v]; }
			case 'q': { long long v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%lld", v]; }
			case 'Q': { unsigned long long v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%llu", v]; }
			case 'f': { float v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%g", (double)v]; }
			case 'd': { double v; memcpy(&v, buf, sizeof v); return [NSString stringWithFormat:@"%g", v]; }
			case '{': return CPStructText(rt, buf, len);
			default: return nil;
		}
	} @catch (NSException *e) {
		return [NSString stringWithFormat:@"(threw %@: %@)", e.name, CPShort(e.reason, 120)];
	}
}

// Value of a declared property (looked up on the class and its superclasses).
static NSString *CPProp(id obj, NSString *name, id *object) {
	if (object) *object = nil;
	if (!obj || object_isClass(obj)) return nil;
	objc_property_t p = class_getProperty(object_getClass(obj), name.UTF8String);
	if (!p || !CPPropertyBoxable(p)) return nil;
	return CPCall(obj, NSSelectorFromString(CPGetterName(p)), object);
}

static id CPPropObject(id obj, NSString *name) {
	id value = nil;
	CPProp(obj, name, &value);
	return value;
}

// A read-only accessor named by the probe (property or plain method): sharedApplicationLibrary, library, icons ...
static id CPKnown(id obj, NSString *name) {
	if (!obj) return nil;
	id value = CPPropObject(obj, name);
	if (!value) CPCall(obj, NSSelectorFromString(name), &value);
	return value;
}

#pragma mark - Object dump

static BOOL CPFollow(id value) {
	return value && !object_isClass(value) && !CPSystemClass(object_getClass(value));
}

// Declared properties of obj with their values: its own classes up to the first UIKit / Foundation one.
// depth > 0 follows object values (and the first 3 items of collections) that are not UIKit / Foundation objects.
static void CPDumpObject(NSString *title, id obj, int depth, NSUInteger indent, NSMutableSet *seen) {
	NSString *pad = CPIndent(indent);
	if (!obj) { CPLine(@"%@%@: nil", pad, title); return; }
	NSValue *key = [NSValue valueWithNonretainedObject:obj];
	if ([seen containsObject:key]) { CPLine(@"%@%@: <%@ %p> (shown above)", pad, title, NSStringFromClass(object_getClass(obj)), obj); return; }
	if (seen.count >= CP_OBJ_SEEN) { CPLine(@"%@%@: <%@ %p> (object cap)", pad, title, NSStringFromClass(object_getClass(obj)), obj); return; }
	[seen addObject:key];
	CPLine(@"%@%@: <%@ %p> image %@", pad, title, CPClassChain(object_getClass(obj)), obj, CPImageOf(object_getClass(obj)));
	NSMutableSet *done = [NSMutableSet set];
	NSUInteger shown = 0;
	for (Class c = object_getClass(obj); c && !CPSystemClass(c) && shown < CP_OBJ_PROPS && !sFull; c = class_getSuperclass(c)) {
		unsigned int count = 0;
		objc_property_t *props = class_copyPropertyList(c, &count);
		for (unsigned int i = 0; i < count && shown < CP_OBJ_PROPS && !sFull; i++) {
			NSString *name = @(property_getName(props[i]));
			if ([done containsObject:name]) continue;
			[done addObject:name];
			if ([@[@"description", @"debugDescription", @"hash", @"superclass"] containsObject:name]) continue;
			NSString *getter = CPGetterName(props[i]);
			if (!CPSafeGetterName(getter)) { CPLine(@"%@  %@ (skipped: getter %@)", pad, name, getter); continue; }
			if (!CPPropertyBoxable(props[i])) continue;
			id value = nil;
			NSString *text = CPCall(obj, NSSelectorFromString(getter), &value);
			if (!text) continue;
			shown++;
			CPLine(@"%@  %@ = %@", pad, name, text);
			if (depth <= 0 || !value || CPNameMatches(name, @[@"delegate", @"parent", @"owner", @"datasource", @"environment", @"superview",
				@"window", @"observer", @"target"])) continue;
			@try {
				if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSOrderedSet class]] || [value isKindOfClass:[NSSet class]]) {
					NSUInteger n = 0;
					for (id item in value) {
						if (n >= 3) break;
						if (CPFollow(item)) CPDumpObject([NSString stringWithFormat:@"%@[%lu]", name, (unsigned long)n], item, depth - 1, indent + 4, seen);
						n++;
					}
				} else if ([value isKindOfClass:[NSDictionary class]]) {
					NSUInteger n = 0;
					for (id k in value) {
						if (n++ >= 3) break;
						id item = value[k];
						if (CPFollow(item)) CPDumpObject([NSString stringWithFormat:@"%@[%@]", name, CPShortObject(k)], item, depth - 1, indent + 4, seen);
					}
				} else if (CPFollow(value)) {
					CPDumpObject(name, value, depth - 1, indent + 4, seen);
				}
			} @catch (NSException *e) { CPLine(@"%@    (following %@ threw %@)", pad, name, e.name); }
		}
		free(props);
	}
}

// Class properties (+sharedInstance style) with their values.
static void CPDumpClassProperties(Class cls, NSUInteger indent) {
	if (!cls) return;
	NSString *pad = CPIndent(indent);
	unsigned int count = 0;
	objc_property_t *props = class_copyPropertyList(object_getClass(cls), &count);
	for (unsigned int i = 0; i < count; i++) {
		NSString *getter = CPGetterName(props[i]);
		if (!CPSafeGetterName(getter) || !CPPropertyBoxable(props[i])) {
			CPLine(@"%@+%s (skipped)", pad, property_getName(props[i]));
			continue;
		}
		NSString *text = CPCall(cls, NSSelectorFromString(getter), NULL);
		CPLine(@"%@+%s = %@", pad, property_getName(props[i]), text ?: @"(not boxable)");
	}
	free(props);
	if (!count) CPLine(@"%@(no class properties)", pad);
}

#pragma mark - Class details

static void CPDumpMethods(Class cls, NSString *sign, NSUInteger cap, NSString *pad) {
	unsigned int count = 0;
	Method *methods = class_copyMethodList(cls, &count);
	NSMutableArray *lines = [NSMutableArray arrayWithCapacity:count];
	for (unsigned int i = 0; i < count; i++) {
		const char *types = method_getTypeEncoding(methods[i]);
		[lines addObject:[NSString stringWithFormat:@"%@%@%@  %s", pad, sign, NSStringFromSelector(method_getName(methods[i])), types ?: "?"]];
	}
	free(methods);
	[lines sortUsingSelector:@selector(compare:)];
	CPLine(@"%@%@methods (%u):", pad, sign, count);
	for (NSUInteger i = 0; i < lines.count && i < cap; i++) CPLine(@"%@", lines[i]);
	if (lines.count > cap) CPLine(@"%@  ... %lu more", pad, (unsigned long)(lines.count - cap));
}

static void CPDumpClassInfo(Class cls, NSUInteger cap) {
	if (!cls || sFull) return;
	NSString *pad = @"    ";
	CPLine(@"\n-- %@  (image %@)", CPClassChain(cls), CPImageOf(cls));
	unsigned int count = 0;
	Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cls, &count);
	if (count) {
		NSMutableArray *names = [NSMutableArray array];
		for (unsigned int i = 0; i < count; i++) [names addObject:@(protocol_getName(protocols[i]))];
		CPLine(@"%@protocols: %@", pad, [names componentsJoinedByString:@", "]);
	}
	free(protocols);

	count = 0;
	Ivar *ivars = class_copyIvarList(cls, &count);
	CPLine(@"%@ivars (%u):", pad, count);
	for (unsigned int i = 0; i < count && i < cap; i++) {
		CPLine(@"%@  %s  %s  @%ld", pad, ivar_getName(ivars[i]) ?: "?", ivar_getTypeEncoding(ivars[i]) ?: "?", (long)ivar_getOffset(ivars[i]));
	}
	if (count > cap) CPLine(@"%@  ... %lu more", pad, (unsigned long)(count - cap));
	free(ivars);

	count = 0;
	objc_property_t *props = class_copyPropertyList(cls, &count);
	CPLine(@"%@properties (%u):", pad, count);
	for (unsigned int i = 0; i < count && i < cap; i++) {
		CPLine(@"%@  %s  %s", pad, property_getName(props[i]), property_getAttributes(props[i]) ?: "?");
	}
	if (count > cap) CPLine(@"%@  ... %lu more", pad, (unsigned long)(count - cap));
	free(props);

	count = 0;
	props = class_copyPropertyList(object_getClass(cls), &count);
	for (unsigned int i = 0; i < count && i < cap; i++) {
		CPLine(@"%@  (class) %s  %s", pad, property_getName(props[i]), property_getAttributes(props[i]) ?: "?");
	}
	free(props);

	CPDumpMethods(cls, @"-", cap * 2, pad);
	CPDumpMethods(object_getClass(cls), @"+", cap, pad);
}

#pragma mark - Car screen

static BOOL CPIsCarScreen(UIScreen *screen) {
	return screen && screen != [UIScreen mainScreen];
}

static BOOL CPCarConnected(void) {
	for (UIScreen *screen in [UIScreen screens]) if (CPIsCarScreen(screen)) return YES;
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if ([scene isKindOfClass:[UIWindowScene class]] && CPIsCarScreen(((UIWindowScene *)scene).screen)) return YES;
	}
	return NO;
}

// Bundle id / name / size of an icon-like view, from the properties it declares (and those of its icon / app).
static NSString *CPIconInfo(id view) {
	NSMutableArray *parts = [NSMutableArray array];
	for (NSString *n in @[@"applicationBundleIdentifier", @"bundleIdentifier", @"applicationIdentifier", @"leafIdentifier",
		@"displayName", @"iconImageInfo", @"iconSize", @"location", @"iconLocation"]) {
		NSString *t = CPProp(view, n, NULL);
		if (t) [parts addObject:[NSString stringWithFormat:@"%@=%@", n, CPShort(t, 80)]];
	}
	for (NSString *holder in @[@"icon", @"application", @"applicationInfo", @"appInfo"]) {
		id o = CPPropObject(view, holder);
		if (!o) continue;
		for (NSString *n in @[@"applicationBundleIdentifier", @"bundleIdentifier", @"displayName"]) {
			NSString *t = CPProp(o, n, NULL);
			if (t) [parts addObject:[NSString stringWithFormat:@"%@.%@=%@", holder, n, CPShort(t, 80)]];
		}
	}
	return [parts componentsJoinedByString:@" "];
}

typedef struct {
	__unsafe_unretained NSMutableDictionary *homeViews;   // class name -> first view of it (home-like classes)
	__unsafe_unretained NSMutableArray *iconLists;        // *IconListView
	__unsafe_unretained NSMutableArray *controllers;      // view controllers owning a view on the car screen
	__unsafe_unretained NSMutableOrderedSet *classes;     // non-UIKit classes seen on the car screen
} CPTreeState;

static void CPDumpView(UIView *v, NSUInteger depth, CPTreeState *st) {
	if (!v || sFull) return;
	NSString *pad = CPIndent(depth * 2);
	Class cls = object_getClass(v);
	NSString *name = NSStringFromClass(cls);
	NSMutableString *line = [NSMutableString stringWithFormat:@"%@%@ %@", pad, name, NSStringFromCGRect(v.frame)];
	@try {
		if (v.hidden) [line appendString:@" HIDDEN"];
		if (v.alpha < 0.999) [line appendFormat:@" alpha=%.2f", (double)v.alpha];
		NSString *ax = v.accessibilityIdentifier;
		if (ax.length) [line appendFormat:@" ax=\"%@\"", CPShort(ax, 80)];
		UIResponder *next = v.nextResponder;
		if ([next isKindOfClass:[UIViewController class]]) {
			[line appendFormat:@" vc=%@", NSStringFromClass(object_getClass(next))];
			if (![st->controllers containsObject:next]) [st->controllers addObject:next];
		}
		if ([v isKindOfClass:[UILabel class]]) [line appendFormat:@" text=\"%@\"", CPShort(((UILabel *)v).text, 60)];
		if ([name containsString:@"Icon"]) {
			NSString *info = CPIconInfo(v);
			if (info.length) [line appendFormat:@" [%@]", info];
		}
		if (!CPSystemClass(cls)) {
			[st->classes addObject:name];
			if (CPNameMatches(name, @[@"dock", @"wallpaper", @"iconlist", @"layout", @"statusbar", @"home", @"dashboard", @"nowplaying",
				@"siri", @"button"]) && !st->homeViews[name] && st->homeViews.count < 40) st->homeViews[name] = v;
			if ([name hasSuffix:@"IconListView"] && st->iconLists.count < 12) [st->iconLists addObject:v];
		}
	} @catch (NSException *e) { [line appendFormat:@" (threw %@)", e.name]; }
	CPLine(@"%@", line);

	NSArray<UIView *> *subs = v.subviews;
	if (!subs.count) return;
	if (depth >= CP_TREE_DEPTH) { CPLine(@"%@  ... %lu subviews (depth limit)", pad, (unsigned long)subs.count); return; }
	NSUInteger i = 0;
	while (i < subs.count && !sFull) {
		Class c = object_getClass(subs[i]);
		NSUInteger j = i;
		while (j < subs.count && object_getClass(subs[j]) == c) j++;
		NSUInteger run = j - i;
		for (NSUInteger k = i; k < i + MIN(run, (NSUInteger)CP_RUN_SHOWN); k++) CPDumpView(subs[k], depth + 1, st);
		if (run > CP_RUN_SHOWN) {
			NSMutableArray *ids = [NSMutableArray array];
			if ([NSStringFromClass(c) containsString:@"Icon"]) {
				for (NSUInteger k = i + CP_RUN_SHOWN; k < j && ids.count < 60; k++) {
					NSString *info = CPIconInfo(subs[k]);
					if (info.length) [ids addObject:CPShort(info, 120)];
				}
			}
			CPLine(@"%@  ... %lu more %@%@%@", pad, (unsigned long)(run - CP_RUN_SHOWN), NSStringFromClass(c),
				ids.count ? @": " : @"", [ids componentsJoinedByString:@" | "]);
		}
		i = j;
	}
}

static void CPDumpWindows(CPTreeState *st) {
	CPSection(@"WINDOWS ON THE CAR SCREEN");
	BOOL anyCar = CPCarConnected();
	if (!anyCar) CPLine(@"(no car screen right now: every window of every scene is dumped)");
	for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if (sFull) break;
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			CPLine(@"\nscene %@ (not a window scene) role=%@", NSStringFromClass(object_getClass(scene)), scene.session.role);
			continue;
		}
		UIWindowScene *ws = (UIWindowScene *)scene;
		BOOL car = CPIsCarScreen(ws.screen);
		CPLine(@"\nscene %@ role=%@ state=%ld screen=%@ %@ windows=%lu", NSStringFromClass(object_getClass(ws)), ws.session.role,
			(long)ws.activationState, car ? @"CAR" : @"phone", NSStringFromCGRect(ws.screen.bounds), (unsigned long)ws.windows.count);
		for (UIWindow *w in ws.windows) {
			CPLine(@"  window %@ %@ level=%.0f hidden=%d key=%d root=%@", NSStringFromClass(object_getClass(w)), NSStringFromCGRect(w.frame),
				(double)w.windowLevel, w.hidden, w.isKeyWindow, w.rootViewController ? NSStringFromClass(object_getClass(w.rootViewController)) : @"nil");
			if (car || !anyCar) {
				@try { CPDumpView(w, 2, st); } @catch (NSException *e) { CPLine(@"  (view tree threw %@: %@)", e.name, e.reason); }
			}
		}
	}
}

// Home icon order: model -> icons (or model -> folder -> lists -> icons) of each *IconListView.
static void CPDumpIconLists(NSArray *iconLists) {
	CPSection(@"HOME ICON ORDER (icon list views)");
	if (!iconLists.count) { CPLine(@"(no *IconListView on the car screen)"); return; }
	NSUInteger n = 0;
	for (UIView *list in iconLists) {
		CPLine(@"\n%@ %p %@", NSStringFromClass(object_getClass(list)), list, NSStringFromCGRect(list.frame));
		id model = CPKnown(list, @"model");
		CPLine(@"  model: %@", CPShortObject(model));
		NSArray *icons = CPKnown(model, @"icons");
		if (![icons isKindOfClass:[NSArray class]]) {
			NSArray *lists = CPKnown(CPKnown(model, @"folder"), @"lists");
			if ([lists isKindOfClass:[NSArray class]] && lists.count > n) icons = CPKnown(lists[n], @"icons");
		}
		if (![icons isKindOfClass:[NSArray class]]) { CPLine(@"  (no icons array)"); n++; continue; }
		CPLine(@"  %lu icons:", (unsigned long)icons.count);
		NSUInteger i = 0;
		for (id icon in icons) {
			if (i >= 120) { CPLine(@"  ..."); break; }
			NSMutableArray *parts = [NSMutableArray array];
			for (NSString *p in @[@"applicationBundleIdentifier", @"applicationBundleID", @"leafIdentifier", @"displayName", @"uniqueIdentifier"]) {
				NSString *t = CPProp(icon, p, NULL);
				if (t) [parts addObject:[NSString stringWithFormat:@"%@=%@", p, CPShort(t, 80)]];
				id raw = CPPropObject(icon, p);
				if (![p isEqualToString:@"displayName"] && ![p isEqualToString:@"uniqueIdentifier"] && [raw isKindOfClass:[NSString class]] && [raw containsString:@"."])
					[sHomeBundles addObject:raw];
			}
			CPLine(@"  %2lu. %@ %@", (unsigned long)i, NSStringFromClass(object_getClass(icon)), [parts componentsJoinedByString:@" "]);
			i++;
		}
		n++;
	}
}

#pragma mark - Sections

static void CPDumpHeader(NSString *reason) {
	struct utsname u;
	uname(&u);
	CPLine(@"OmniCar Car Probe (%s) - %@", TWEAK_VERSION, [NSDate date]);
	CPLine(@"trigger: %@", reason);
	CPLine(@"iOS %@ (%@), device %s, process %@ (%@) pid %d", [UIDevice currentDevice].systemVersion, [NSProcessInfo processInfo].operatingSystemVersionString,
		u.machine, [NSProcessInfo processInfo].processName, [NSBundle mainBundle].bundleIdentifier, getpid());
	CPLine(@"executable %@", [NSBundle mainBundle].executablePath);
	for (UIScreen *s in [UIScreen screens]) {
		CPLine(@"screen %@ %p %@ native %@ scale %.1f maxFPS %ld %@", NSStringFromClass(object_getClass(s)), s, NSStringFromCGRect(s.bounds),
			NSStringFromCGRect(s.nativeBounds), (double)s.scale, (long)s.maximumFramesPerSecond, CPIsCarScreen(s) ? @"CAR" : @"phone");
	}
	CPLine(@"\nOMCCarClass map (iOS 16 name -> class here, image):");
	for (NSString *n in @[@"DashBoard", @"DBDashboard", @"DBDashboardHomeViewController", @"DBHomeViewController", @"DBIconView",
		@"DBIconListView", @"DBIconModel", @"DBApplicationInfo", @"DBApplicationLaunchInfo", @"DBApplicationLibrary", @"DBEvent",
		@"DBWallpaper", @"DBWallpaperView", @"DBWallpaperController", @"DBDockView", @"DBDockViewController", @"DBStatusBar",
		@"DBStatusBarViewController", @"DBNowPlayingObserver", @"DBSiriPresentation", @"DBApplicationSceneViewController"]) {
		Class c = OMCCarClass(n.UTF8String);
		CPLine(@"  %@ -> %@%@", n, c ? NSStringFromClass(c) : @"-", c ? [NSString stringWithFormat:@" (%@)", CPImageOf(c)] : @"");
	}
}

static void CPDumpControllers(NSArray *controllers, NSDictionary *homeViews) {
	CPSection(@"HOME VIEWS (properties: icon lists, dock, wallpaper, layout, status bar ...)");
	for (NSString *name in [homeViews.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		if (sFull) break;
		CPLine(@"");
		CPDumpObject(name, homeViews[name], 0, 0, [NSMutableSet set]);
	}
	CPSection(@"VIEW CONTROLLERS ON THE CAR SCREEN (properties)");
	NSUInteger n = 0;
	for (UIViewController *vc in controllers) {
		if (sFull || n++ >= 20) break;
		CPLine(@"\nparent %@", vc.parentViewController ? NSStringFromClass(object_getClass(vc.parentViewController)) : @"nil");
		CPDumpObject(NSStringFromClass(object_getClass(vc)), vc, 1, 0, [NSMutableSet set]);
	}
}

static void CPDumpLibrary(NSArray *controllers) {
	CPSection(@"APP LIBRARY");
	UIApplication *app = [UIApplication sharedApplication];
	CPDumpObject(@"application", app, 0, 0, [NSMutableSet set]);
	Class db = OMCCarClass("DashBoard");
	Method nm = db ? class_getClassMethod(db, NSSelectorFromString(@"_newApplicationLibrary")) : NULL;
	CPLine(@"\n+[%@ _newApplicationLibrary] %s (not called: it builds a new library; the one in use follows)",
		db ? NSStringFromClass(db) : @"DashBoard?", nm ? (method_getTypeEncoding(nm) ?: "?") : "MISSING");

	NSMutableArray *libraries = [NSMutableArray array];
	id shared = CPKnown(app, @"sharedApplicationLibrary");
	if (shared) [libraries addObject:shared];
	for (UIViewController *vc in controllers) {
		id lib = [NSStringFromClass(object_getClass(vc)) containsString:@"Home"] ? CPKnown(vc, @"library") : nil;
		if (lib && ![libraries containsObject:lib]) [libraries addObject:lib];
	}
	if (!libraries.count) { CPLine(@"(no library: sharedApplicationLibrary / home view controller library are nil)"); return; }
	for (id lib in libraries) {
		CPLine(@"");
		CPDumpObject(lib == shared ? @"sharedApplicationLibrary" : @"home view controller library", lib, 1, 0, [NSMutableSet set]);
		CPDumpClassInfo(object_getClass(lib), 80);
		NSArray *apps = nil;
		for (NSString *getter in @[@"allInstalledApplications", @"allApplications", @"applications", @"applicationInfos"]) {
			apps = CPKnown(lib, getter);
			if ([apps isKindOfClass:[NSArray class]] || [apps isKindOfClass:[NSSet class]] || [apps isKindOfClass:[NSOrderedSet class]]) {
				CPLine(@"\n%@ (%lu, library order):", getter, (unsigned long)[apps count]);
				break;
			}
			apps = nil;
		}
		NSUInteger i = 0;
		id first = nil;
		for (id info in apps) {
			if (i >= 300 || sFull) break;
			if (!first) first = info;
			NSString *bid = CPProp(info, @"bundleIdentifier", NULL);
			NSString *name = CPProp(info, @"displayName", NULL) ?: CPProp(info, @"localizedDisplayName", NULL);
			NSString *decl = CPProp(info, @"carPlayDeclaration", NULL);
			CPLine(@"  %3lu. %@ %@ name=%@%@", (unsigned long)i, NSStringFromClass(object_getClass(info)), bid ?: @"?", name ?: @"?",
				decl && ![decl isEqualToString:@"nil"] ? @" (declaration)" : @"");
			i++;
		}
		if (first) {
			CPLine(@"");
			CPDumpObject(@"first app info", first, 1, 0, [NSMutableSet set]);
		}
	}
}

static void CPDumpCarKit(void) {
	CPSection(@"CARKIT SESSION / VEHICLES");
	CPLine(@"CarKit dlopen: %@", dlopen("/System/Library/PrivateFrameworks/CarKit.framework/CarKit", RTLD_LAZY) ? @"ok" : @(dlerror() ?: "failed"));
	Class statusClass = NSClassFromString(@"CARSessionStatus");
	if (!sSessionStatus && statusClass) sSessionStatus = [statusClass new];
	id session = CPKnown(sSessionStatus, @"currentSession");
	NSMutableSet *seen = [NSMutableSet set];
	CPDumpObject(@"CARSessionStatus", sSessionStatus, 0, 0, seen);
	CPDumpObject(@"currentSession", session, 2, 0, seen);
	id config = CPKnown(session, @"configuration");
	if (config) CPDumpObject(@"currentSession.configuration", config, 2, 0, seen);

	for (NSString *name in @[@"CARSessionStatus", @"CARSession", @"CARSessionConfiguration", @"CRPairedVehicleManager", @"CRVehicle",
		@"CRVehicleStore", @"CARDisplayInfo", @"CARScreenInfo"]) {
		Class c = NSClassFromString(name);
		CPLine(@"\n%@: %@", name, c ? [NSString stringWithFormat:@"%@ (%@)", CPClassChain(c), CPImageOf(c)] : @"missing");
		if (c) CPDumpClassProperties(c, 2);
	}
	Class managerClass = NSClassFromString(@"CRPairedVehicleManager");
	if (managerClass) {
		static id manager;   // kept: it may fill its vehicles in asynchronously (the next probe shows them)
		if (!manager) manager = [managerClass new];
		CPLine(@"");
		CPDumpObject(@"CRPairedVehicleManager (new)", manager, 2, 0, seen);
	}
}

static void CPDumpEvents(void) {
	CPSection(@"EVENTS (DBEvent / CAREvent) - hardware / Siri button path");
	Class ev = OMCCarClass("DBEvent");
	CPLine(@"DBEvent -> %@", ev ? NSStringFromClass(ev) : @"missing");
	if (ev) {
		CPDumpClassProperties(ev, 2);
		unsigned int count = 0;
		Method *methods = class_copyMethodList(object_getClass(ev), &count);
		for (unsigned int i = 0; i < count; i++) {
			NSString *sel = NSStringFromSelector(method_getName(methods[i]));
			if ([sel.lowercaseString containsString:@"type"]) CPLine(@"  enum-like +%@  %s (not called)", sel, method_getTypeEncoding(methods[i]) ?: "?");
		}
		free(methods);
		CPDumpClassInfo(ev, 400);
	}
	CPLine(@"\nC symbols (dlsym, not called):");
	for (NSString *sym in @[@"NSStringFromDBEventType", @"DBEventTypeDescription", @"DBStringFromEventType", @"NSStringFromCAREventType",
		@"CAREventTypeDescription", @"CARStringFromEventType", @"NSStringFromCARInputDeviceButton", @"CARInputDeviceButtonDescription"]) {
		CPLine(@"  %@: %@", sym, dlsym(RTLD_DEFAULT, sym.UTF8String) ? @"present" : @"-");
	}
}

static void CPDumpPreferenceFiles(void) {
	CPSection(@"CARPLAY PREFERENCE FILES");
	NSMutableOrderedSet *dirs = [NSMutableOrderedSet orderedSetWithObject:@"/var/mobile/Library/Preferences"];
	[dirs addObject:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"]];
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *dir in dirs) {
		NSError *error = nil;
		NSArray *files = [[fm contentsOfDirectoryAtPath:dir error:&error] sortedArrayUsingSelector:@selector(compare:)];
		if (!files) { CPLine(@"%@: %@", dir, error.localizedDescription); continue; }
		for (NSString *file in files) {
			if (sFull) return;
			if (!CPNameMatches(file, @[@"carplay", @"carkit", @"dashboard", @"com.apple.car"])) continue;
			NSString *path = [dir stringByAppendingPathComponent:file];
			NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
			NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
			CPLine(@"\n%@ (%llu bytes)%@", path, attrs.fileSize, plist ? @"" : @" (not readable here)");
			NSUInteger n = 0;
			for (NSString *key in [plist.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
				if (n++ >= 150) { CPLine(@"  ..."); break; }
				CPLine(@"  %@ = %@", key, CPShort(CPDescribe(plist[key]), 400));
			}
		}
	}
}

#pragma mark - CarPlay Customize storage (background)

// Duong dan key trong plist chua chuoi needle (vehicles[0].iconState.hidden[3] ...), toi da `cap` dong
static void CPFindKeyPaths(id obj, NSString *path, NSArray<NSString *> *needles, NSMutableArray<NSString *> *out, NSUInteger cap, int depth) {
	if (out.count >= cap || depth > 12 || !obj) return;
	if ([obj isKindOfClass:[NSString class]]) {
		for (NSString *n in needles) if ([obj containsString:n]) { [out addObject:[NSString stringWithFormat:@"%@ = %@", path.length ? path : @"(root)", CPShort(obj, 120)]]; return; }
	} else if ([obj isKindOfClass:[NSDictionary class]]) {
		for (id key in [[obj allKeys] sortedArrayUsingSelector:@selector(description)]) {
			NSString *k = [key description];
			for (NSString *n in needles) if ([k containsString:n]) { [out addObject:[NSString stringWithFormat:@"%@.<key %@>", path, CPShort(k, 120)]]; break; }
			CPFindKeyPaths(obj[key], path.length ? [path stringByAppendingFormat:@".%@", k] : k, needles, out, cap, depth + 1);
		}
	} else if ([obj isKindOfClass:[NSArray class]]) {
		NSUInteger i = 0;
		for (id v in obj) CPFindKeyPaths(v, [path stringByAppendingFormat:@"[%lu]", (unsigned long)i++], needles, out, cap, depth + 1);
	} else if ([obj isKindOfClass:[NSData class]] && [obj length] < CP_SCAN_BYTES) {   // plist long trong plist (NSKeyedArchiver ...)
		id inner = [NSPropertyListSerialization propertyListWithData:obj options:0 format:NULL error:nil];
		if (inner) CPFindKeyPaths(inner, [path stringByAppendingString:@"<data>"], needles, out, cap, depth + 1);
	}
}

// Tim noi iOS luu danh sach Cai dat > Chung > CarPlay > xe > Tuy chinh: moi file trong /var/mobile/Library va cac app group
// co chua ma bundle cua app tren man chinh xe; so voi lan probe truoc (CP_FILES_PATH) de biet file nao vua doi
static void CPDumpCustomizeStorage(NSArray<NSString *> *homeBundles) {
	CPSection(@"CARPLAY CUSTOMIZE STORAGE (files with the home apps' bundle ids, changes since the last probe)");
	NSMutableOrderedSet *needles = [NSMutableOrderedSet orderedSet];
	for (NSString *b in homeBundles) if (![b hasPrefix:@"com.apple."]) [needles addObject:b];   // app ben thu ba: hiem khi nam o file khac
	for (NSString *b in @[@"com.apple.podcasts", @"com.apple.iBooks", @"com.apple.mobilecal", @"com.apple.news"]) if ([homeBundles containsObject:b]) [needles addObject:b];
	if (needles.count > 8) [needles removeObjectsInRange:NSMakeRange(8, needles.count - 8)];
	if (!needles.count) { CPLine(@"(no third-party app on the home screen to look for: add one in iOS CarPlay Customize, probe again)"); return; }
	NSArray *find = needles.array;
	NSMutableArray *bytes = [NSMutableArray array];
	for (NSString *n in find) [bytes addObject:[n dataUsingEncoding:NSUTF8StringEncoding]];
	CPLine(@"looking for: %@", [find componentsJoinedByString:@", "]);

	NSFileManager *fm = [NSFileManager defaultManager];
	NSMutableArray *roots = [NSMutableArray arrayWithObject:@"/var/mobile/Library"];
	for (NSString *g in [fm contentsOfDirectoryAtPath:@"/var/mobile/Containers/Shared/AppGroup" error:nil] ?: @[])
		[roots addObject:[@"/var/mobile/Containers/Shared/AppGroup" stringByAppendingPathComponent:g]];
	NSSet *skipExt = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"heic", @"mov", @"mp4", @"m4a", @"caf", @"car", @"ktx", @"astc", @"ttf", @"otf", @"wal", @"shm", @"log"]];
	NSMutableDictionary *now = [NSMutableDictionary dictionary];   // path -> @[mtime, size]
	NSUInteger looked = 0, denied = 0;
	NSMutableArray *hits = [NSMutableArray array];
	for (NSString *root in roots) {
		NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLIsRegularFileKey]
		                                        options:0 errorHandler:^BOOL(NSURL *url, NSError *error) { return YES; }];
		for (NSURL *url in en) {
			if (looked >= CP_SCAN_FILES || sFull) break;
			NSString *path = url.path;
			if ([path containsString:@"/Caches/com.apple.dyld"] || [path containsString:@"/Logs/"] || [path containsString:@"/Media/"]) continue;
			NSNumber *regular = nil, *size = nil; NSDate *mtime = nil;
			[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
			if (!regular.boolValue || [skipExt containsObject:path.pathExtension.lowercaseString]) continue;
			[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
			[url getResourceValue:&mtime forKey:NSURLContentModificationDateKey error:nil];
			if (size.unsignedLongLongValue > CP_SCAN_BYTES) continue;
			looked++;
			NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
			if (!data) { denied++; continue; }
			NSMutableArray *found = [NSMutableArray array];
			for (NSUInteger i = 0; i < bytes.count; i++) if ([data rangeOfData:bytes[i] options:0 range:NSMakeRange(0, data.length)].location != NSNotFound) [found addObject:find[i]];
			BOOL named = CPNameMatches(path.lastPathComponent, @[@"carplay", @"carkit", @"dashboard", @"iconstate", @"vehicle"]);
			if (!found.count && !named) continue;
			now[path] = @[@(mtime.timeIntervalSince1970), size ?: @0];
			if (found.count) [hits addObject:@[path, found, mtime ?: [NSDate distantPast], size ?: @0]];
		}
	}
	CPLine(@"%lu files read, %lu not readable from CarPlay.app (sandbox), %lu contain a home app id", (unsigned long)looked, (unsigned long)denied, (unsigned long)hits.count);
	NSDateFormatter *df = [NSDateFormatter new];
	df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
	NSMutableArray *summary = [NSMutableArray array];
	for (NSArray *h in hits) {
		NSString *path = h[0];
		CPLine(@"\n%@ (%@ bytes, modified %@)\n  contains: %@", path, h[3], [df stringFromDate:h[2]], [h[1] componentsJoinedByString:@", "]);
		[summary addObject:path.lastPathComponent];
		NSData *data = [NSData dataWithContentsOfFile:path];
		id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil] : nil;
		if (!plist) { CPLine(@"  (not a property list: sqlite / json / other)"); continue; }
		NSMutableArray *paths = [NSMutableArray array];
		CPFindKeyPaths(plist, @"", find, paths, 40, 0);
		for (NSString *p in paths) CPLine(@"  %@", p);
	}
	// so voi lan truoc
	NSDictionary *before = [NSDictionary dictionaryWithContentsOfFile:CP_FILES_PATH];
	NSMutableArray *changed = [NSMutableArray array];
	if (before) {
		CPLine(@"\nChanged since the last probe (%lu files then):", (unsigned long)before.count);
		for (NSString *path in [[now allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			NSArray *b = before[path], *n = now[path];
			if (!b) { CPLine(@"  NEW      %@", path); [changed addObject:path.lastPathComponent]; }
			else if (![b isEqualToArray:n]) { CPLine(@"  CHANGED  %@ (size %@ -> %@)", path, b[1], n[1]); [changed addObject:path.lastPathComponent]; }
		}
		for (NSString *path in before) if (!now[path]) { CPLine(@"  GONE     %@", path); [changed addObject:path.lastPathComponent]; }
		if (!changed.count) CPLine(@"  (none)");
	} else CPLine(@"\n(first scan: change CarPlay Customize in iOS Settings, then probe again to see which file changes)");
	[now writeToFile:CP_FILES_PATH atomically:YES];
	dispatch_async(dispatch_get_main_queue(), ^{
		CPLog(@"Tuy chinh CarPlay: %lu file chua ma app (%@)%@", (unsigned long)summary.count, [summary componentsJoinedByString:@", "],
		      before ? [NSString stringWithFormat:@"; doi tu lan truoc: %@", changed.count ? [changed componentsJoinedByString:@", "] : @"khong"] : @"; lan dau, doi Tuy chinh roi probe lai");
	});
}

#pragma mark - Runtime (background)

static NSArray<NSString *> *CPTargetImages(void) {
	NSMutableArray *out = [NSMutableArray array];
	NSString *exe = [NSBundle mainBundle].executablePath;
	uint32_t n = _dyld_image_count();
	for (uint32_t i = 0; i < n; i++) {
		const char *path = _dyld_get_image_name(i);
		if (!path) continue;
		NSString *p = @(path);
		NSString *last = p.lastPathComponent, *dir = p.stringByDeletingLastPathComponent.lastPathComponent;
		BOOL framework = [@[@"DashBoard", @"CarPlayUIServices", @"CarKit"] containsObject:last] && [dir isEqualToString:[last stringByAppendingString:@".framework"]];
		BOOL app = ([last isEqualToString:@"CarPlay"] && [dir isEqualToString:@"CarPlay.app"]) || [p isEqualToString:exe];
		if ((framework || app) && ![out containsObject:p]) [out addObject:p];
	}
	return out;
}

static NSArray<NSString *> *CPClassNamesInImage(NSString *image) {
	unsigned int count = 0;
	const char **names = objc_copyClassNamesForImage(image.fileSystemRepresentation, &count);
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:count];
	for (unsigned int i = 0; i < count; i++) [out addObject:@(names[i])];
	free((void *)names);
	return [out sortedArrayUsingSelector:@selector(compare:)];
}

static void CPDumpRuntime(NSOrderedSet<NSString *> *seenClasses) {
	NSArray *images = CPTargetImages();
	CPSection(@"IMAGES AND CLASS NAMES");
	NSMutableDictionary<NSString *, NSArray *> *classesByImage = [NSMutableDictionary dictionary];
	for (NSString *image in images) {
		NSArray *names = CPClassNamesInImage(image);
		classesByImage[image] = names;
		CPLine(@"\n%@ (%lu classes):", image, (unsigned long)names.count);
		for (NSUInteger i = 0; i < names.count; i += 8) {
			CPLine(@"  %@", [[names subarrayWithRange:NSMakeRange(i, MIN((NSUInteger)8, names.count - i))] componentsJoinedByString:@", "]);
		}
	}
	if (!images.count) CPLine(@"(none of DashBoard / CarPlay / CarPlayUIServices / CarKit is loaded)");

	CPSection(@"METHOD INDEX (selectors with siri, voice, button, hardware, knob, event, wallpaper, dock, nowplaying, audio, hidden, order, rows, columns, iconsize, iconstate, layout, customiz, visible, applist)");
	NSArray *words = @[@"siri", @"voice", @"button", @"hardware", @"knob", @"event", @"wallpaper", @"dock", @"nowplaying", @"audio",
		@"hidden", @"order", @"rows", @"columns", @"iconsize", @"iconstate", @"iconlayout", @"layoutstate", @"customiz", @"visibleicon",
		@"applist", @"appidentifiers", @"bundleidentifiers"];
	NSUInteger lines = 0;
	for (NSString *image in images) {
		for (NSString *name in classesByImage[image]) {
			if (lines >= CP_INDEX_LINES || sFull) break;
			Class cls = objc_getClass(name.UTF8String);
			if (!cls) continue;
			for (int meta = 0; meta < 2; meta++) {
				unsigned int count = 0;
				Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
				for (unsigned int i = 0; i < count && lines < CP_INDEX_LINES; i++) {
					NSString *sel = NSStringFromSelector(method_getName(methods[i]));
					if (!CPNameMatches(sel, words)) continue;
					CPLine(@"%@[%@ %@]  %s", meta ? @"+" : @"-", name, sel, method_getTypeEncoding(methods[i]) ?: "?");
					lines++;
				}
				free(methods);
			}
		}
	}
	if (lines >= CP_INDEX_LINES) CPLine(@"... (index cap %d lines)", CP_INDEX_LINES);

	CPSection(@"CLASS DETAILS: classes seen on the car screen");
	NSMutableSet *dumped = [NSMutableSet set];
	for (NSString *name in seenClasses) {
		if (sFull) break;
		Class cls = objc_getClass(name.UTF8String);
		if (!cls || [dumped containsObject:name]) continue;
		[dumped addObject:name];
		CPDumpClassInfo(cls, 80);
	}
	CPSection(@"CLASS DETAILS: matching classes in DashBoard / CarPlay / CarPlayUIServices / CarKit");
	for (NSString *image in images) {
		CPLine(@"\n######## %@", image.lastPathComponent);
		for (NSString *name in classesByImage[image]) {
			if (sFull) break;
			if (!CPNameMatches(name, CPClassWords()) || [dumped containsObject:name]) continue;
			Class cls = objc_getClass(name.UTF8String);
			if (!cls) continue;
			[dumped addObject:name];
			CPDumpClassInfo(cls, 60);
		}
	}
}

#pragma mark - Run

static void CPPrepareSession(void) {
	@try {
		dlopen("/System/Library/PrivateFrameworks/CarKit.framework/CarKit", RTLD_LAZY);
		Class cls = NSClassFromString(@"CARSessionStatus");
		if (!sSessionStatus && cls) sSessionStatus = [cls new];
	} @catch (NSException *e) { CPLog(@"CARSessionStatus loi: %@", e); }
}

static void CPWrite(void) {
	NSData *data = [sOut dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
	if (data.length > CP_MAX_BYTES) data = [data subdataWithRange:NSMakeRange(0, CP_MAX_BYTES)];
	NSError *error = nil;
	BOOL ok = [data writeToFile:CP_REPORT_PATH options:NSDataWritingAtomic error:&error];
	NSUInteger size = data.length;
	BOOL full = sFull;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (ok) CPLog(@"bao cao probe: %@ (%lu KB%@)", CP_REPORT_PATH, (unsigned long)(size / 1024), full ? @", cat o 3 MB" : @"");
		else CPLog(@"khong ghi duoc %@: %@", CP_REPORT_PATH, error);
		sOut = nil;
		sRunning = NO;
	});
}

// Main thread: the UI and the objects. The runtime part (class lists, method index, class details) goes on a
// background queue, then the file is written.
static void CPRun(NSString *reason) {
	if (sRunning) { CPLog(@"probe dang chay, bo qua (%@)", reason); return; }
	sRunning = YES;
	sFull = NO;
	sOut = [NSMutableString stringWithCapacity:512 * 1024];
	CPLog(@"probe bat dau (%@)", reason);
	sHomeBundles = [NSMutableOrderedSet orderedSet];

	NSMutableDictionary *homeViews = [NSMutableDictionary dictionary];
	NSMutableArray *iconLists = [NSMutableArray array];
	NSMutableArray *controllers = [NSMutableArray array];
	NSMutableOrderedSet *classes = [NSMutableOrderedSet orderedSet];
	CPTreeState st = { homeViews, iconLists, controllers, classes };

	@try { CPDumpHeader(reason); } @catch (NSException *e) { CPLine(@"(header threw %@: %@)", e.name, e.reason); }
	@try { CPDumpWindows(&st); } @catch (NSException *e) { CPLine(@"(windows threw %@: %@)", e.name, e.reason); }
	@try { CPDumpIconLists(iconLists); } @catch (NSException *e) { CPLine(@"(icon lists threw %@: %@)", e.name, e.reason); }
	@try { CPDumpControllers(controllers, homeViews); } @catch (NSException *e) { CPLine(@"(controllers threw %@: %@)", e.name, e.reason); }
	@try { CPDumpLibrary(controllers); } @catch (NSException *e) { CPLine(@"(library threw %@: %@)", e.name, e.reason); }
	@try { CPDumpCarKit(); } @catch (NSException *e) { CPLine(@"(CarKit threw %@: %@)", e.name, e.reason); }
	@try { CPDumpEvents(); } @catch (NSException *e) { CPLine(@"(events threw %@: %@)", e.name, e.reason); }
	@try { CPDumpPreferenceFiles(); } @catch (NSException *e) { CPLine(@"(preference files threw %@: %@)", e.name, e.reason); }

	NSOrderedSet *seenClasses = [classes copy];
	NSArray *homeBundles = sHomeBundles.array;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		@try { CPDumpCustomizeStorage(homeBundles); } @catch (NSException *e) { CPLine(@"(customize storage threw %@: %@)", e.name, e.reason); }
		@try { CPDumpRuntime(seenClasses); } @catch (NSException *e) { CPLine(@"(runtime threw %@: %@)", e.name, e.reason); }
		CPLine(@"\n[end of report]");
		CPWrite();
	});
}

// Once per car connection, CP_AUTO_DELAY s after the car screen appears (the home screen is built by then).
static void CPScheduleAuto(void) {
	static NSUInteger gen;
	NSUInteger my = ++gen;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CP_AUTO_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (my != gen || !CPCarConnected()) return;
		CPRun(@"car screen appeared");
	});
}

__attribute__((constructor)) static void CPInit(void) {
	@autoreleasepool {
		if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.CarPlayApp"]) return;
		if (!OMCCrashGuard(@"carProbe")) return;
		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
		void (^appeared)(NSNotification *) = ^(NSNotification *note) {
			CPPrepareSession();
			CPScheduleAuto();
		};
		[nc addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:mainQueue usingBlock:appeared];
		[nc addObserverForName:UIScreenDidConnectNotification object:nil queue:mainQueue usingBlock:appeared];
		[nc addObserverForName:UISceneWillConnectNotification object:nil queue:mainQueue usingBlock:appeared];
		static int token;
		notify_register_dispatch(CP_DARWIN_PROBE, &token, dispatch_get_main_queue(), ^(int t) {
			CPPrepareSession();
			CPRun(@"Darwin notification " CP_DARWIN_PROBE);
		});
		CPLog(@"probe san sang: tu chay %.0f s sau khi man xe hien, hoac notify_post(\"%s\")", CP_AUTO_DELAY, CP_DARWIN_PROBE);
	}
}

#endif // OMC_AUTOTEST
