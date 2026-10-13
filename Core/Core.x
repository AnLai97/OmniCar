// OmniCarCore.dylib - loaded into SpringBoard only. Hosts the process-wide services the feature
// dylibs cannot own without duplicating them: the log relay for sandboxed apps, the rescue-mode
// notice (CarPlay turned a feature off after crashing, see OMCCrashGuard) and freeing memory when
// the car connects (OMC_KEY_CLEAN_RAM).

#import "OmniCar.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <notify.h>
#import <objc/message.h>

// CFUserNotificationDisplayNotice: exported by CoreFoundation and usable from SpringBoard, but marked
// unavailable on iOS in the SDK headers, so it is looked up at runtime.
typedef SInt32 (*OMCDisplayNoticeFn)(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL, CFURLRef soundURL,
	CFURLRef localizationURL, CFStringRef alertHeader, CFStringRef alertMessage, CFStringRef defaultButtonTitle);

static NSString *OMCCoreFeatureName(NSString *feature) {
	if ([feature isEqualToString:@"splitScreen"]) return OMCTr(@"Chia màn hình", @"Split Screen");
	if ([feature isEqualToString:@"startupScreen"]) return OMCTr(@"Màn hình khởi động", @"Startup Screen");
	if ([feature isEqualToString:@"speedBubble"]) return OMCTr(@"Bong bóng tốc độ", @"Speed Bubble");
	if ([feature isEqualToString:@"appBridge"]) return OMCTr(@"App trên màn xe", @"Apps on the car screen");
	return feature;
}

static void OMCShowRescueNotice(void) {
	OMCPrefsSync();
	NSArray *features = OMCPref(OMC_KEY_RESCUE, nil);
	if (![features isKindOfClass:[NSArray class]] || !features.count) return;
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *f in features) [names addObject:OMCCoreFeatureName(f)];
	NSString *list = [names componentsJoinedByString:@", "];
	NSString *title = OMCTr(@"OmniCar: chế độ cứu", @"OmniCar: rescue mode");
	NSString *message = [NSString stringWithFormat:OMCTr(
		@"CarPlay bị sập %d lần liền ngay sau khi cắm, nên OmniCar đã tắt: %@.\n\nVào Cài đặt > OmniCar để bật lại hoặc gửi log cho tác giả.",
		@"CarPlay crashed %d times in a row right after connecting, so OmniCar turned off: %@.\n\nOpen Settings > OmniCar to turn it back on or send the log to the developer."),
		OMC_RESCUE_CRASHES, list];
	OMCDisplayNoticeFn notice = (OMCDisplayNoticeFn)dlsym(RTLD_DEFAULT, "CFUserNotificationDisplayNotice");
	OMCLog(@"Core", @"thong bao che do cuu: %@ (notice=%d)", list, notice != NULL);
	if (!notice) return;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{   // the call blocks until dismissed
		notice(0, 0, NULL, NULL, NULL, (__bridge CFStringRef)title, (__bridge CFStringRef)message, CFSTR("OK"));
	});
}

#pragma mark - Free memory when the car connects

static id OMCSend(id target, NSString *selector) {
	SEL sel = NSSelectorFromString(selector);
	return [target respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(target, sel) : nil;
}

// Apps never quit, with the reason (logged): what is on screen and what is playing, calls / messages / Settings, and
// while a car is connected (or on connect) the apps the car needs: music / maps, every app with a CarPlay interface
// (Split Screen recorded them), the iPhone apps chosen for the car screen and the Speed Bubble sources. "Free memory
// now" with no car closes those too: it was the reason nothing closed when they were the apps left open.
static NSDictionary<NSString *, NSString *> *OMCCleanKeep(BOOL forCar) {
	NSMutableDictionary *keep = [NSMutableDictionary dictionary];
	for (NSString *bid in @[@"com.apple.mobilephone", @"com.apple.MobileSMS", @"com.apple.InCallService", @"com.apple.Preferences",
		@"com.apple.facetime", @"com.anlai.omnicar"]) keep[bid] = @"system";
	if (forCar) {
		for (NSString *bid in @[@"com.apple.Music", @"com.apple.Maps", @"com.apple.podcasts", @"vn.vietmap.live", @"com.lumi.GOFA"]) keep[bid] = @"car";
		for (NSString *key in @[@"splitScreenCarPlayApps", @"appBridgeApps"]) {
			NSArray *ids = OMCPref(key, nil);
			if ([ids isKindOfClass:[NSArray class]]) for (NSString *bid in ids) keep[bid] = key;
		}
	}
	NSString *playing = OMCSend(OMCSend(OMCSend(objc_getClass("SBMediaController"), @"sharedInstance"), @"nowPlayingApplication"), @"bundleIdentifier");
	if (playing) keep[playing] = @"playing";
	NSString *front = OMCSend(OMCSend([UIApplication sharedApplication], @"_accessibilityFrontMostApplication"), @"bundleIdentifier");
	if (front) keep[front] = @"front";
	return keep;
}

// Apps with a home screen icon: user apps and Apple apps that are not hidden (web sheets, system services)
static BOOL OMCIsClosableApp(NSString *bid) {
	id proxy = nil;
	Class cls = objc_getClass("LSApplicationProxy");
	SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
	if ([cls respondsToSelector:sel]) proxy = ((id (*)(id, SEL, id))objc_msgSend)(cls, sel, bid);
	NSString *type = OMCSend(proxy, @"applicationType");
	if ([type isEqual:@"User"]) return YES;
	if (![type isEqual:@"System"]) return NO;
	NSArray *tags = OMCSend(proxy, @"appTags");
	return !([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]);
}

static BOOL OMCAppRunning(id app) {
	SEL isRunning = NSSelectorFromString(@"isRunning");
	if ([app respondsToSelector:isRunning]) return ((BOOL (*)(id, SEL))objc_msgSend)(app, isRunning);
	return OMCSend(app, @"processState") != nil;
}

static NSArray *OMCRunningApps(void) {
	id controller = OMCSend(objc_getClass("SBApplicationController"), @"sharedInstance");
	NSArray *running = OMCSend(controller, @"runningApplications");
	if ([running isKindOfClass:[NSArray class]] && running.count) return running;
	NSMutableArray *found = [NSMutableArray array];   // no such method on this iOS (or empty): check every app
	for (id app in OMCSend(controller, @"allApplications")) if (OMCAppRunning(app)) [found addObject:app];
	return found;
}

// BackBoardServices first (what the app switcher's swipe-up ends in), FrontBoardServices as the fallback
static BOOL OMCTerminateApp(NSString *bid) {
	typedef void (*BKSTerminateFn)(CFStringRef, int, bool, CFStringRef);
	static BKSTerminateFn bks;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
		bks = (BKSTerminateFn)dlsym(RTLD_DEFAULT, "BKSTerminateApplicationForReasonAndReportWithDescription");
	});
	if (bks) { bks((__bridge CFStringRef)bid, 5, false, CFSTR("OmniCar: free memory")); return YES; }
	id service = OMCSend(objc_getClass("FBSSystemService"), @"sharedService");
	SEL terminate = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
	if (![service respondsToSelector:terminate]) return NO;
	((void (*)(id, SEL, id, int, BOOL, id))objc_msgSend)(service, terminate, bid, 1, NO, @"OmniCar: free memory");
	return YES;
}

// force = "Free memory now" from Diagnostics (ignores the switch)
static void OMCCleanRam(BOOL force) {
	OMCPrefsSync();
	if (!force && (!OMCEnabled() || ![OMCPref(OMC_KEY_CLEAN_RAM, @NO) boolValue])) return;
	BOOL car = OMCSend(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice") != nil;
	NSArray *running = OMCRunningApps();
	NSDictionary *keep = OMCCleanKeep(!force || car);
	NSMutableArray *closed = [NSMutableArray array], *kept = [NSMutableArray array];
	for (id app in running) {
		NSString *bid = OMCSend(app, @"bundleIdentifier");
		if (![bid isKindOfClass:[NSString class]]) continue;
		if (keep[bid]) { [kept addObject:[NSString stringWithFormat:@"%@ (%@)", bid, keep[bid]]]; continue; }
		if (!OMCIsClosableApp(bid)) continue;
		if (OMCTerminateApp(bid)) [closed addObject:bid];
	}
	CFPreferencesSetAppValue((__bridge CFStringRef)OMC_KEY_DIAG_CLEAN,
		(__bridge CFPropertyListRef)@{@"date": [NSDate date], @"closed": closed, @"running": @(running.count)}, OMC_PREFS_DOMAIN);
	OMCPrefsSync();
	OMCLog(@"Core", @"don RAM (%@, xe=%d): %lu app dang chay, dong %lu: %@ | giu lai: %@", force ? @"bam tay" : @"cam xe", car,
		(unsigned long)running.count, (unsigned long)closed.count, [closed componentsJoinedByString:@", "], [kept componentsJoinedByString:@", "]);
	// Did they really quit? (the log says which did not)
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		NSMutableArray *alive = [NSMutableArray array];
		for (id app in OMCRunningApps()) {
			NSString *bid = OMCSend(app, @"bundleIdentifier");
			if ([closed containsObject:bid]) [alive addObject:bid];
		}
		if (alive.count) OMCLog(@"Core", @"don RAM: van con chay sau 2s: %@", [alive componentsJoinedByString:@", "]);
	});
}

#pragma mark - Shortcuts / Siri (omnicar:// URLs that are not one feature's)

// omnicar://feature/<splitScreen | appBridge | speedBubble | startupScreen | all>?on=1|0|toggle
// omnicar://lite?mode=off|auto|always      omnicar://cleanram      omnicar://startup?style=video|logo|greeting|weather
// (omnicar://splitscreen/... is Split Screen's own, see Features/SplitScreen/SpringBoard.xm)
static void OMCCoreHandleURL(NSString *urlString) {
	NSURL *url = [urlString isKindOfClass:[NSString class]] ? [NSURL URLWithString:urlString] : nil;
	if (![url.scheme isEqualToString:@"omnicar"]) return;
	NSMutableDictionary *q = [NSMutableDictionary dictionary];
	for (NSURLQueryItem *it in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) if (it.value) q[it.name] = it.value;
	NSString *host = url.host.lowercaseString;
	OMCPrefsSync();
	if ([host isEqualToString:@"feature"]) {
		NSString *name = url.pathComponents.count > 1 ? url.pathComponents[1] : @"";
		NSDictionary *keys = @{@"splitscreen": @"splitScreenEnabled", @"appbridge": @"appBridgeEnabled", @"speedbubble": @"speedBubbleEnabled",
			@"startupscreen": @"startupScreenEnabled", @"all": @"enabled"};
		NSString *key = keys[name.lowercaseString];
		if (!key) { OMCLog(@"Core", @"URL: khong co tinh nang %@", name); return; }
		NSString *on = [q[@"on"] lowercaseString] ?: @"toggle";
		BOOL value = [on isEqualToString:@"toggle"] ? ![OMCPref(key, @YES) boolValue] : [on boolValue];
		CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)@(value), OMC_PREFS_DOMAIN);
		OMCLog(@"Core", @"URL: %@ = %d", key, value);
	} else if ([host isEqualToString:@"lite"]) {
		NSDictionary *modes = @{@"off": @0, @"always": @1, @"on": @1, @"auto": @2};
		NSNumber *mode = modes[[q[@"mode"] lowercaseString] ?: @""];
		if (!mode) return;
		CFPreferencesSetAppValue((__bridge CFStringRef)OMC_KEY_LITE_MODE, (__bridge CFPropertyListRef)mode, OMC_PREFS_DOMAIN);
		OMCLog(@"Core", @"URL: che do nhe = %@", mode);
	} else if ([host isEqualToString:@"startup"]) {   // omnicar://startup?style=video|logo|greeting|weather
		NSDictionary *styles = @{@"video": @0, @"logo": @1, @"greeting": @2, @"weather": @3};
		NSNumber *style = styles[[q[@"style"] lowercaseString] ?: @""];
		if (!style) return;
		CFPreferencesSetAppValue(CFSTR("startupScreenStyle"), (__bridge CFPropertyListRef)style, OMC_PREFS_DOMAIN);
		OMCLog(@"Core", @"URL: kieu khoi dong = %@", style);
	} else if ([host isEqualToString:@"cleanram"]) {
		notify_post(OMC_DARWIN_CLEAN_NOW);
		return;
	} else {
		return;
	}
	OMCPrefsSync();
	notify_post("com.anlai.omnicar/prefschanged");
}

%ctor {
	@autoreleasepool {
		OMCLogRelayStart();
		OMCLog(@"Core", @"loaded into %@ enabled=%d", [NSBundle mainBundle].bundleIdentifier, OMCEnabled());
		static int token;
		notify_register_dispatch(OMC_DARWIN_RESCUE, &token, dispatch_get_main_queue(), ^(int t) { OMCShowRescueNotice(); });
		// The car just connected: wait until CarPlay has launched its apps (and recorded them), then free memory
		static int carToken;
		notify_register_dispatch(OMC_DARWIN_CAR_CONNECTED, &carToken, dispatch_get_main_queue(), ^(int t) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OMCCleanRam(NO); });
		});
		[(NSNotificationCenter *)[objc_getClass("NSDistributedNotificationCenter") defaultCenter] addObserverForName:@"com.anlai.omnicar/url"
			object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { OMCCoreHandleURL(note.userInfo[@"url"]); }];
		static int nowToken;
		notify_register_dispatch(OMC_DARWIN_CLEAN_NOW, &nowToken, dispatch_get_main_queue(), ^(int t) { OMCCleanRam(YES); });
	}
}
