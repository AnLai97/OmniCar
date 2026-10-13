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

// Apps never quit: phone / messages / music / maps, every app with a CarPlay interface (Split Screen recorded them),
// the iPhone apps chosen for the car screen, the Speed Bubble sources, what is playing and what is on screen.
static NSSet<NSString *> *OMCCleanKeep(void) {
	NSMutableSet *keep = [NSMutableSet setWithArray:@[@"com.apple.mobilephone", @"com.apple.MobileSMS", @"com.apple.Music",
		@"com.apple.Maps", @"com.apple.podcasts", @"com.apple.InCallService", @"com.apple.Preferences", @"com.anlai.omnicar",
		@"vn.vietmap.live", @"com.lumi.GOFA"]];
	for (NSString *key in @[@"splitScreenCarPlayApps", @"appBridgeApps"]) {
		NSArray *ids = OMCPref(key, nil);
		if ([ids isKindOfClass:[NSArray class]]) [keep addObjectsFromArray:ids];
	}
	NSString *playing = OMCSend(OMCSend(OMCSend(objc_getClass("SBMediaController"), @"sharedInstance"), @"nowPlayingApplication"), @"bundleIdentifier");
	if (playing) [keep addObject:playing];
	NSString *front = OMCSend(OMCSend([UIApplication sharedApplication], @"_accessibilityFrontMostApplication"), @"bundleIdentifier");
	if (front) [keep addObject:front];
	return keep;
}

static BOOL OMCIsUserApp(NSString *bid) {
	id proxy = nil;
	Class cls = objc_getClass("LSApplicationProxy");
	SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
	if ([cls respondsToSelector:sel]) proxy = ((id (*)(id, SEL, id))objc_msgSend)(cls, sel, bid);
	return [OMCSend(proxy, @"applicationType") isEqual:@"User"];
}

// force = "Free memory now" from Diagnostics (ignores the switch)
static void OMCCleanRam(BOOL force) {
	OMCPrefsSync();
	if (!force && (!OMCEnabled() || ![OMCPref(OMC_KEY_CLEAN_RAM, @NO) boolValue])) return;
	id controller = OMCSend(objc_getClass("SBApplicationController"), @"sharedInstance");
	NSArray *running = OMCSend(controller, @"runningApplications");
	if (!running) {   // no such method on this iOS: every app, keep the running ones
		NSMutableArray *found = [NSMutableArray array];
		SEL isRunning = NSSelectorFromString(@"isRunning");
		for (id app in OMCSend(controller, @"allApplications"))
			if ([app respondsToSelector:isRunning] && ((BOOL (*)(id, SEL))objc_msgSend)(app, isRunning)) [found addObject:app];
		running = found;
	}
	if (![running isKindOfClass:[NSArray class]]) { OMCLog(@"Core", @"don RAM: khong lay duoc danh sach app dang chay"); return; }
	id service = OMCSend(objc_getClass("FBSSystemService"), @"sharedService");
	SEL terminate = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
	if (![service respondsToSelector:terminate]) { OMCLog(@"Core", @"don RAM: khong co FBSSystemService"); return; }
	NSSet *keep = OMCCleanKeep();
	NSMutableArray *closed = [NSMutableArray array];
	for (id app in running) {
		NSString *bid = OMCSend(app, @"bundleIdentifier");
		if (![bid isKindOfClass:[NSString class]] || [keep containsObject:bid] || !OMCIsUserApp(bid)) continue;
		((void (*)(id, SEL, id, int, BOOL, id))objc_msgSend)(service, terminate, bid, 1, NO, @"OmniCar: free memory for CarPlay");
		[closed addObject:bid];
	}
	CFPreferencesSetAppValue((__bridge CFStringRef)OMC_KEY_DIAG_CLEAN,
		(__bridge CFPropertyListRef)@{@"date": [NSDate date], @"closed": closed}, OMC_PREFS_DOMAIN);
	OMCPrefsSync();
	OMCLog(@"Core", @"don RAM (%@): dong %lu app (%@)", force ? @"bam tay" : @"cam xe", (unsigned long)closed.count, [closed componentsJoinedByString:@", "]);
}

%ctor {
	@autoreleasepool {
		OMCLogRelayStart();
		OMCLog(@"Core", @"loaded into %@ enabled=%d license=%ld trial=%ld", [NSBundle mainBundle].bundleIdentifier, OMCEnabled(),
			(long)OMCLicenseState(), (long)OMCTrialDaysLeft());   // first run: starts the trial clock
		static int token;
		notify_register_dispatch(OMC_DARWIN_RESCUE, &token, dispatch_get_main_queue(), ^(int t) { OMCShowRescueNotice(); });
		// The car just connected: wait until CarPlay has launched its apps (and recorded them), then free memory
		static int carToken;
		notify_register_dispatch(OMC_DARWIN_CAR_CONNECTED, &carToken, dispatch_get_main_queue(), ^(int t) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OMCCleanRam(NO); });
		});
		static int nowToken;
		notify_register_dispatch(OMC_DARWIN_CLEAN_NOW, &nowToken, dispatch_get_main_queue(), ^(int t) { OMCCleanRam(YES); });
	}
}
