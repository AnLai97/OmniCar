// OmniCarCore.dylib - loaded into SpringBoard only. Hosts the process-wide services the feature
// dylibs cannot own without duplicating them: the log relay for sandboxed apps and the rescue-mode
// notice (CarPlay turned a feature off after crashing, see OMCCrashGuard).

#import "OmniCar.h"
#import <dlfcn.h>
#import <notify.h>

// CFUserNotificationDisplayNotice: exported by CoreFoundation and usable from SpringBoard, but marked
// unavailable on iOS in the SDK headers, so it is looked up at runtime.
typedef SInt32 (*OMCDisplayNoticeFn)(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL, CFURLRef soundURL,
	CFURLRef localizationURL, CFStringRef alertHeader, CFStringRef alertMessage, CFStringRef defaultButtonTitle);

// Same language rule as the settings page (OMCLanguage in Prefs/OMCTheme.m).
static BOOL OMCCoreVietnamese(void) {
	NSString *lang = OMCPref(@"language", nil);
	if ([lang isKindOfClass:[NSString class]] && lang.length) return [lang isEqualToString:@"vi"];
	return [[NSLocale preferredLanguages].firstObject hasPrefix:@"vi"];
}

static NSString *OMCCoreFeatureName(NSString *feature, BOOL vi) {
	NSDictionary *names = vi
		? @{@"splitScreen": @"Chia màn hình", @"startupScreen": @"Màn hình khởi động", @"speedBubble": @"Bong bóng tốc độ", @"appBridge": @"App trên màn xe"}
		: @{@"splitScreen": @"Split Screen", @"startupScreen": @"Startup Screen", @"speedBubble": @"Speed Bubble", @"appBridge": @"Apps on the car screen"};
	return names[feature] ?: feature;
}

static void OMCShowRescueNotice(void) {
	OMCPrefsSync();
	NSArray *features = OMCPref(OMC_KEY_RESCUE, nil);
	if (![features isKindOfClass:[NSArray class]] || !features.count) return;
	BOOL vi = OMCCoreVietnamese();
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *f in features) [names addObject:OMCCoreFeatureName(f, vi)];
	NSString *list = [names componentsJoinedByString:@", "];
	NSString *title = vi ? @"OmniCar: chế độ cứu" : @"OmniCar: rescue mode";
	NSString *message = vi
		? [NSString stringWithFormat:@"CarPlay bị sập %d lần liền ngay sau khi cắm, nên OmniCar đã tắt: %@.\n\nVào Cài đặt > OmniCar để bật lại hoặc gửi log cho tác giả.", OMC_RESCUE_CRASHES, list]
		: [NSString stringWithFormat:@"CarPlay crashed %d times in a row right after connecting, so OmniCar turned off: %@.\n\nOpen Settings > OmniCar to turn it back on or send the log to the developer.", OMC_RESCUE_CRASHES, list];
	OMCDisplayNoticeFn notice = (OMCDisplayNoticeFn)dlsym(RTLD_DEFAULT, "CFUserNotificationDisplayNotice");
	OMCLog(@"Core", @"thong bao che do cuu: %@ (notice=%d)", list, notice != NULL);
	if (!notice) return;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{   // the call blocks until dismissed
		notice(0, 0, NULL, NULL, NULL, (__bridge CFStringRef)title, (__bridge CFStringRef)message, CFSTR("OK"));
	});
}

%ctor {
	@autoreleasepool {
		OMCLogRelayStart();
		OMCLog(@"Core", @"loaded into %@ enabled=%d", [NSBundle mainBundle].bundleIdentifier, OMCEnabled());
		static int token;
		notify_register_dispatch(OMC_DARWIN_RESCUE, &token, dispatch_get_main_queue(), ^(int t) { OMCShowRescueNotice(); });
	}
}
