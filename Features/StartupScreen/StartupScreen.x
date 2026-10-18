// Startup Screen - show a startup style over the CarPlay screen while CarPlay is starting.
//
// Runs inside CarPlay.app (com.apple.CarPlayApp). Each time a car connects, a new UIScreen
// (and, depending on the iOS build, a UIWindowScene) is created for the car display. We put a
// high-level window on top of it, show the chosen style for the configured time, then fade it
// out to reveal the CarPlay home screen underneath.
//
// Styles (SS_KEY_STYLE): Video plays the chosen video; every other style is drawn by SSStartupView (the
// same code draws the preview in Settings). The style is resolved once per connection (SSResolveStyle):
// on a special day (Tet, Mid-Autumn, Christmas, New Year, the user's birthday) the festive screen plays
// instead, at most SS_OCCASION_TIMES times that day; Random picks one of SS_KEY_RANDOM_SET. Weather and
// Briefing ask Open-Meteo for the current weather at the last known location (rounded to 2 decimals),
// only when the resolved style shows it. HUD shows real checks of this process (battery, heat, Lite
// mode, car profile); Briefing the next calendar event, only when iOS already allows calendar access.
//
// AVFoundation never finishes loading media inside CarPlay.app, so the settings page extracts
// each video into JPEG frames (Videos/.frames/<video>/) and we play those as a flipbook. The
// soundtrack (audio.m4a next to the frames) and the startup sound (Sounds/) are played by the
// same tweak loaded into SpringBoard.
//
// Logs are prefixed with "[OmniCar/StartupScreen]" - filter for it in Console.app to debug.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreLocation/CoreLocation.h>
#import <CallKit/CallKit.h>
#import <EventKit/EventKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import "OmniCar.h"
#import "StartupScreen.h"
#import "SSStartupView.h"
#import "OMCTest.h"

#define SSLog(fmt, ...) OMCLog(@"StartupScreen", fmt, ##__VA_ARGS__)

static const NSTimeInterval kFadeDuration = 0.4;
static const NSTimeInterval kMaxFullPlay  = 60.0;
static const NSUInteger kFrameBufferSize  = 4;
// Weather: request timeout, and how old a cached result may be to still be shown (with "updated at").
static const NSTimeInterval kWeatherTimeout = 3.0;
static const NSTimeInterval kWeatherMaxAge  = 12 * 3600;
static const NSTimeInterval kEventWindow   = 12 * 3600;   // Briefing: next calendar event within 12 h
static char kSplashKey;
static char kShownKey;
// CarPlay -> SpringBoard: the style actually shown this time (state = style + 1), so the audio side knows
// whether a Random / festive connection plays the video's soundtrack.
#define SS_NOTIFY_STYLE "com.anlai.omnicar/startupscreen.style"
#if OMC_AUTOTEST
static BOOL gSSTestNoOccasion;   // auto test replays never use up (or show) the festive screen
#endif

#pragma mark - Preferences

// The stored style: 0 ... SS_STYLE_RANDOM.
static NSInteger SSCurrentStyle(void) {
	NSInteger style = [OMCPref(SS_KEY_STYLE, @(SS_STYLE_VIDEO)) integerValue];
	return (style >= SS_STYLE_VIDEO && style < SS_STYLE_COUNT) ? style : SS_STYLE_VIDEO;
}

static NSTimeInterval SSDuration(void) {
	return MAX(1.0, [OMCPref(SS_KEY_DURATION, @5) doubleValue]);
}

static NSString *SSVideoName(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *name = OMCPref(SS_KEY_VIDEO_NAME, nil);
	if (name.length && [fm fileExistsAtPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name]]) return name;
	// Fall back to the first video in the folder.
	NSError *error = nil;
	NSArray *files = [[fm contentsOfDirectoryAtPath:SS_VIDEOS_DIR error:&error] sortedArrayUsingSelector:@selector(compare:)];
	if (error) SSLog(@"cannot list %@: %@", SS_VIDEOS_DIR, error);
	for (NSString *file in files) {
		if (![file hasPrefix:@"."]) return file;
	}
	return nil;
}

// The chosen video has been converted to frames (Video style can play).
static BOOL SSVideoReady(void) {
	NSString *name = SSVideoName();
	if (!name) return NO;
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[SS_FRAMES_DIR(name) stringByAppendingPathComponent:@"info.plist"]];
	return [info[@"count"] unsignedIntegerValue] > 0 && [info[@"fps"] doubleValue] > 0;
}

#pragma mark - Style for this connection

static NSString *SSDayKey(NSDate *date) {
	NSDateFormatter *df = [NSDateFormatter new];
	df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	df.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	df.dateFormat = @"yyyy-MM-dd";
	return [df stringFromDate:date];
}

// Today's occasion (SS_OCCASION_*): the birthday wins; Tet and Mid-Autumn by the lunar calendar.
static NSInteger SSOccasionForDate(NSDate *date) {
	NSCalendar *gregorian = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *g = [gregorian components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
	id birthday = OMCPref(SS_KEY_BIRTHDAY, nil);
	if ([birthday isKindOfClass:[NSString class]]) {
		NSArray<NSString *> *parts = [(NSString *)birthday componentsSeparatedByString:@"-"];
		if (parts.count == 2 && parts[0].integerValue == g.month && parts[1].integerValue == g.day) return SS_OCCASION_BIRTHDAY;
	}
	NSCalendar *lunar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierChinese];
	NSDateComponents *l = [lunar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
	if (!l.leapMonth && l.month == 1 && l.day >= 1 && l.day <= 3) return SS_OCCASION_TET;
	if (!l.leapMonth && l.month == 8 && l.day == 15) return SS_OCCASION_MIDAUTUMN;
	if (g.month == 1 && g.day == 1) return SS_OCCASION_NEWYEAR;
	if (g.month == 12 && (g.day == 24 || g.day == 25)) return SS_OCCASION_XMAS;
	return SS_OCCASION_NONE;
}

// Today's occasion if it may still play today (counted in SS_KEY_OCCASION_LOG, last 7 days kept), else none.
static NSInteger SSTakeOccasion(void) {
#if OMC_AUTOTEST
	if (gSSTestNoOccasion) return SS_OCCASION_NONE;
#endif
	if (![OMCPref(SS_KEY_OCCASIONS, @YES) boolValue]) return SS_OCCASION_NONE;
	NSDate *now = [NSDate date];
	NSInteger occasion = SSOccasionForDate(now);
	if (occasion == SS_OCCASION_NONE) return SS_OCCASION_NONE;

	NSString *today = SSDayKey(now);
	id stored = OMCPref(SS_KEY_OCCASION_LOG, nil);
	NSDictionary *log = [stored isKindOfClass:[NSDictionary class]] ? stored : @{};
	NSInteger shown = [log[today] isKindOfClass:[NSNumber class]] ? [log[today] integerValue] : 0;
	if (shown >= SS_OCCASION_TIMES) {
		SSLog(@"occasion %ld already shown %ld times today", (long)occasion, (long)shown);
		return SS_OCCASION_NONE;
	}
	NSCalendar *gregorian = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	NSMutableDictionary *next = [NSMutableDictionary dictionary];
	for (NSInteger back = 1; back < 7; back++) {
		NSString *key = SSDayKey([gregorian dateByAddingUnit:NSCalendarUnitDay value:-back toDate:now options:0]);
		if (log[key]) next[key] = log[key];
	}
	next[today] = @(shown + 1);
	CFPreferencesSetAppValue((__bridge CFStringRef)SS_KEY_OCCASION_LOG, (__bridge CFPropertyListRef)next, OMC_PREFS_DOMAIN);
	CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
	return occasion;
}

// Random: one of SS_KEY_RANDOM_SET (missing / empty = every drawn style), never Video without frames
// or Logo without a logo.
static NSInteger SSPickRandomStyle(void) {
	NSMutableArray<NSNumber *> *pool = [NSMutableArray array];
	id set = OMCPref(SS_KEY_RANDOM_SET, nil);
	if ([set isKindOfClass:[NSArray class]]) {
		for (id item in (NSArray *)set) {
			if (![item isKindOfClass:[NSNumber class]]) continue;
			NSInteger s = [item integerValue];
			if (s >= SS_STYLE_VIDEO && s < SS_STYLE_RANDOM && ![pool containsObject:@(s)]) [pool addObject:@(s)];
		}
	}
	if (!pool.count) for (NSInteger s = SS_STYLE_VIDEO; s < SS_STYLE_RANDOM; s++) [pool addObject:@(s)];
	if ([pool containsObject:@(SS_STYLE_VIDEO)] && !SSVideoReady()) [pool removeObject:@(SS_STYLE_VIDEO)];
	if ([pool containsObject:@(SS_STYLE_LOGO)] && ![[NSFileManager defaultManager] fileExistsAtPath:SS_LOGO_PATH]) [pool removeObject:@(SS_STYLE_LOGO)];
	if (!pool.count) return SS_STYLE_GREETING;
	return pool[arc4random_uniform((uint32_t)pool.count)].integerValue;
}

// The style shown for this connection; *occasion is set for SS_STYLE_FESTIVE. Uses up one festive showing.
static NSInteger SSResolveStyle(NSInteger *occasion) {
	if (occasion) *occasion = SS_OCCASION_NONE;
	NSInteger festive = SSTakeOccasion();
	if (festive != SS_OCCASION_NONE) {
		if (occasion) *occasion = festive;
		return SS_STYLE_FESTIVE;
	}
	NSInteger style = SSCurrentStyle();
	return style == SS_STYLE_RANDOM ? SSPickRandomStyle() : style;
}

#pragma mark - Live data (CarPlay)

// SS_KEY_CAR_NAME, else the car's own name from the last recorded CarPlay session (Core, OMC_KEY_DIAG_CAR).
static NSString *SSCarName(void) {
	NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	id custom = OMCPref(SS_KEY_CAR_NAME, nil);
	if ([custom isKindOfClass:[NSString class]] && [(NSString *)custom stringByTrimmingCharactersInSet:space].length)
		return [(NSString *)custom stringByTrimmingCharactersInSet:space];
	id car = OMCPref(OMC_KEY_DIAG_CAR, nil);
	if (![car isKindOfClass:[NSDictionary class]]) return nil;
	for (NSString *group in @[@"configuration", @"session"]) {
		NSDictionary *props = ((NSDictionary *)car)[group];
		if (![props isKindOfClass:[NSDictionary class]]) continue;
		for (NSString *key in @[@"modelName", @"name", @"vehicleName", @"accessoryName"]) {
			NSString *v = props[key];
			if (![v isKindOfClass:[NSString class]]) continue;
			v = [v stringByTrimmingCharactersInSet:space];
			if (v.length && ![v isEqualToString:@"nil"] && ![v isEqualToString:@"(null)"]) return v;
		}
	}
	return nil;
}

// iPhone battery 0-100 (-1 unknown); monitoring is switched back off if nobody had it on.
static NSInteger SSBatteryPercent(BOOL *charging) {
	UIDevice *device = [UIDevice currentDevice];
	BOOL wasOn = device.batteryMonitoringEnabled;
	if (!wasOn) device.batteryMonitoringEnabled = YES;
	float level = device.batteryLevel;
	UIDeviceBatteryState state = device.batteryState;
	if (!wasOn) device.batteryMonitoringEnabled = NO;
	if (charging) *charging = state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
	return level < 0 ? -1 : (NSInteger)lroundf(level * 100);
}

// HUD check lines from this process's real state.
static NSArray<NSDictionary *> *SSHudLines(void) {
	NSMutableArray<NSDictionary *> *lines = [NSMutableArray array];
	[lines addObject:@{@"text": OMCTr(@"Kết nối CarPlay", @"CarPlay connected"), @"ok": @YES}];

	BOOL charging = NO;
	NSInteger battery = SSBatteryPercent(&charging);
	if (battery >= 0) {
		NSString *text = charging
			? [NSString stringWithFormat:OMCTr(@"Pin iPhone %ld%% · đang sạc", @"iPhone battery %ld%% · charging"), (long)battery]
			: [NSString stringWithFormat:OMCTr(@"Pin iPhone %ld%%", @"iPhone battery %ld%%"), (long)battery];
		[lines addObject:@{@"text": text, @"ok": @(charging || battery >= 20)}];
	}

	NSProcessInfoThermalState thermal = [NSProcessInfo processInfo].thermalState;
	NSString *heat = thermal <= NSProcessInfoThermalStateFair ? OMCTr(@"Nhiệt độ máy: ổn", @"Phone temperature: OK")
		: thermal == NSProcessInfoThermalStateSerious ? OMCTr(@"Nhiệt độ máy: nóng", @"Phone temperature: hot")
		: OMCTr(@"Nhiệt độ máy: rất nóng", @"Phone temperature: very hot");
	[lines addObject:@{@"text": heat, @"ok": @(thermal <= NSProcessInfoThermalStateFair)}];

	NSInteger lite = [OMCPref(OMC_KEY_LITE_MODE, @2) integerValue];
	NSString *liteText = lite == 1 ? OMCTr(@"Chế độ nhẹ: bật", @"Lite mode: on")
		: lite == 0 ? OMCTr(@"Chế độ nhẹ: tắt", @"Lite mode: off") : OMCTr(@"Chế độ nhẹ: tự động", @"Lite mode: auto");
	[lines addObject:@{@"text": liteText, @"ok": @YES}];

	if ([OMCPref(OMC_KEY_PROFILES_ON, @NO) boolValue]) {
		id profiles = OMCPref(OMC_KEY_PROFILES, nil);
		id current = OMCPref(OMC_KEY_PROFILE_CURRENT, nil);
		NSDictionary *profile = [profiles isKindOfClass:[NSDictionary class]] && [current isKindOfClass:[NSString class]] ? ((NSDictionary *)profiles)[current] : nil;
		NSString *name = [profile isKindOfClass:[NSDictionary class]] ? profile[@"name"] : nil;
		if ([name isKindOfClass:[NSString class]] && name.length)
			[lines addObject:@{@"text": [NSString stringWithFormat:OMCTr(@"Hồ sơ xe: %@", @"Car profile: %@"), name], @"ok": @YES}];
	}
	return lines;
}

// Next timed calendar event starting within kEventWindow - only when iOS already lets this process read the
// calendar (never asks). nil otherwise.
static NSDictionary *SSNextEvent(void) {
	// 3 = EKAuthorizationStatusAuthorized before iOS 17 = EKAuthorizationStatusFullAccess from iOS 17
	// (written as a number so neither SDK warns about the other name).
	EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
	if ((NSInteger)status != 3) {
		SSLog(@"calendar: no access (status %ld), no event card", (long)status);
		return nil;
	}
	@try {
		EKEventStore *store = [EKEventStore new];
		NSDate *now = [NSDate date];
		NSPredicate *predicate = [store predicateForEventsWithStartDate:now endDate:[now dateByAddingTimeInterval:kEventWindow] calendars:nil];
		NSArray<EKEvent *> *events = [[store eventsMatchingPredicate:predicate] sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];
		for (EKEvent *event in events) {
			if (event.allDay || !event.startDate || [event.startDate compare:now] == NSOrderedAscending) continue;
			NSMutableDictionary *info = [NSMutableDictionary dictionary];
			info[@"title"] = event.title.length ? event.title : OMCTr(@"Lịch hẹn", @"Event");
			info[@"date"] = event.startDate;
			if (event.location.length) info[@"location"] = event.location;
			return info;
		}
	} @catch (NSException *e) {
		SSLog(@"calendar: %@", e);
	}
	return nil;
}

#pragma mark - Audio (SpringBoard)

// AVFoundation is unusable inside CarPlay.app, so the soundtrack is played by SpringBoard,
// whose audio goes to the car while CarPlay is connected. CarPlay.app drives it with
// Darwin notifications when the first frame appears and when the splash goes away.
static BOOL gIsCarPlay;
static AVAudioPlayer *gAudioPlayer;
static AVAudioSessionCategory gSavedCategory;
static AVAudioSessionCategoryOptions gSavedOptions;

static void SSPostNotification(CFStringRef name) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, YES);
}

static void SSAudioRestoreSession(void) {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
	if (gSavedCategory) [session setCategory:gSavedCategory withOptions:gSavedOptions error:nil];
	gSavedCategory = nil;
}

static void SSAudioStop(void) {
	AVAudioPlayer *player = gAudioPlayer;
	if (!player) return;
	gAudioPlayer = nil;
	[player setVolume:0 fadeDuration:kFadeDuration];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFadeDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[player stop];
		if (!gAudioPlayer) SSAudioRestoreSession();
	});
}

// A call ringing, dialing or in progress (the startup sound stays silent then, SS_KEY_SOUND_NO_CALL).
static CXCallObserver *gCallObserver;

static BOOL SSPhoneCallActive(void) {
	if (!gCallObserver) gCallObserver = [CXCallObserver new];
	for (CXCall *call in gCallObserver.calls) {
		if (!call.hasEnded) return YES;
	}
	return NO;
}

// The startup sound picked in Settings (any style), nil when none.
static NSString *SSStartupSoundPath(void) {
	id name = OMCPref(SS_KEY_SOUND_FILE, nil);
	if (![name isKindOfClass:[NSString class]] || ![(NSString *)name length]) return nil;
	NSString *path = [SS_SOUNDS_DIR stringByAppendingPathComponent:[(NSString *)name lastPathComponent]];
	if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
	SSLog(@"audio: startup sound %@ is missing", name);
	return nil;
}

// CarPlay: publish the style it is showing (before SS_NOTIFY_AUDIO_PLAY). The token stays registered so the state lasts.
static void SSPublishStyle(NSInteger style) {
	static int token = -1;
	if (token == -1 && notify_register_check(SS_NOTIFY_STYLE, &token) != NOTIFY_STATUS_OK) {
		token = -1;
		return;
	}
	notify_set_state(token, (uint64_t)(style + 1));
}

// SpringBoard: the style CarPlay is showing (Random / festive may differ from the setting).
static NSInteger SSShownStyle(void) {
	static int token = -1;
	if (token == -1 && notify_register_check(SS_NOTIFY_STYLE, &token) != NOTIFY_STATUS_OK) token = -1;
	uint64_t state = 0;
	if (token != -1) notify_get_state(token, &state);
	return state > 0 ? (NSInteger)state - 1 : SSCurrentStyle();
}

static void SSAudioPlay(void) {
	OMCPrefsSync();
	// Video style with "Video sound" on: the video's own soundtrack. Otherwise the startup sound, if any.
	NSString *path = nil;
	BOOL loop = NO;
	if (SSShownStyle() == SS_STYLE_VIDEO && [OMCPref(SS_KEY_SOUND, @NO) boolValue]) {
		NSString *name = SSVideoName();
		NSString *soundtrack = name ? [SS_FRAMES_DIR(name) stringByAppendingPathComponent:@"audio.m4a"] : nil;
		if (soundtrack && [[NSFileManager defaultManager] fileExistsAtPath:soundtrack]) {
			path = soundtrack;
			// Loop along with the frames unless the clip plays exactly once.
			loop = ![OMCPref(SS_KEY_PLAY_FULL, @NO) boolValue];
		} else {
			SSLog(@"audio: no soundtrack for %@", name);
		}
	}
	if (!path) path = SSStartupSoundPath();
	if (!path) return;
	if ([OMCPref(SS_KEY_SOUND_NO_CALL, @YES) boolValue] && SSPhoneCallActive()) {
		SSLog(@"audio: skipped, a phone call is in progress");
		return;
	}
	float volume = (float)(MAX(0.0, MIN(100.0, [OMCPref(SS_KEY_SOUND_VOLUME, @100) doubleValue])) / 100.0);
	if (volume <= 0) return;

	if (gAudioPlayer) [gAudioPlayer stop];
	AVAudioSession *session = [AVAudioSession sharedInstance];
	if (!gSavedCategory) {
		gSavedCategory = session.category;
		gSavedOptions = session.categoryOptions;
	}
	// Playback (not Ambient) so the ringer switch doesn't mute it; mix so car audio keeps going.
	[session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
	[session setActive:YES error:nil];

	NSError *error = nil;
	gAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
	if (!gAudioPlayer) {
		SSLog(@"audio: cannot open %@: %@", path, error);
		SSAudioRestoreSession();
		return;
	}
	gAudioPlayer.numberOfLoops = loop ? -1 : 0;
	gAudioPlayer.volume = volume;
	BOOL ok = [gAudioPlayer play];
	SSLog(@"audio: playing %@ ok=%d volume=%.2f route=%@", path.lastPathComponent, ok, volume, session.currentRoute.outputs.firstObject.portType);
}

static void SSAudioNotification(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
	BOOL play = CFStringCompare(name, SS_NOTIFY_AUDIO_PLAY, 0) == kCFCompareEqualTo;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (play) SSAudioPlay();
		else SSAudioStop();
	});
}

#pragma mark - Frames

static UIImage *SSDecodeFrame(NSString *path) {
	CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
	if (!source) return nil;
	// Decode now, on the background queue, rather than lazily on the main thread at draw time.
	NSDictionary *options = @{(__bridge id)kCGImageSourceShouldCacheImmediately: @YES};
	CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options);
	CFRelease(source);
	if (!cgImage) return nil;
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	return image;
}

#pragma mark - Weather (CarPlay, Weather style only)

// Current weather from Open-Meteo (no API key) at the last location iOS already knows - no new
// location request, nothing when location access is off. The position is rounded to 2 decimals
// (about 1 km) before it leaves the phone. done(nil) when there is no location or no answer within
// kWeatherTimeout; a good answer is cached in SS_WEATHER_CACHE first. done runs on the main queue.
static void SSWeatherFetchAt(double latitude, double longitude, void (^done)(NSDictionary *weather));

// CarPlay.app: own location when it happens to be authorised (never seen so far); otherwise SpringBoard fetches
// (SSWeatherAskSpringBoard) and the answer comes back through the shared cache.
static void (^gWeatherWaiter)(NSDictionary *weather);   // CarPlay: completion of the SpringBoard request in flight
static int gWeatherReadyToken, gWeatherSeq;

static void SSWeatherAskSpringBoard(void (^done)(NSDictionary *weather)) {
	if (!gWeatherReadyToken) {
		notify_register_dispatch(SS_NOTIFY_WEATHER_READY_C, &gWeatherReadyToken, dispatch_get_main_queue(), ^(int t) {
			void (^waiter)(NSDictionary *) = gWeatherWaiter;
			gWeatherWaiter = nil;
			if (!waiter) return;
			NSDictionary *weather = SSWeatherLoadCache(kWeatherMaxAge);
			SSLog(@"weather: SpringBoard answered (%@)", weather ? @"cache loaded" : @"nothing usable in the cache");
			waiter(weather);
		});
	}
	int seq = ++gWeatherSeq;
	gWeatherWaiter = done;
	SSLog(@"weather: no location access here, asking SpringBoard");
	notify_post(SS_NOTIFY_WEATHER_REQUEST_C);
	// After a respring CarPlay.app and its splash come up before SpringBoard has registered the observer (log 18/10
	// 11:56: asked at 40.5s, SpringBoard loaded the tweak at 40.7s, no answer) -> ask again at 2 s and 5 s while waiting.
	for (NSNumber *delay in @[@2, @5]) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (gWeatherSeq != seq || !gWeatherWaiter) return;
			SSLog(@"weather: no answer yet, asking SpringBoard again");
			notify_post(SS_NOTIFY_WEATHER_REQUEST_C);
		});
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (gWeatherSeq != seq || !gWeatherWaiter) return;
		void (^waiter)(NSDictionary *) = gWeatherWaiter;
		gWeatherWaiter = nil;
		SSLog(@"weather: SpringBoard did not answer in 10s");
		waiter(nil);
	});
}

static void SSWeatherFetch(void (^done)(NSDictionary *weather)) {
	CLLocationManager *manager = [CLLocationManager new];
	CLAuthorizationStatus status = manager.authorizationStatus;
	if (status != kCLAuthorizationStatusAuthorizedAlways && status != kCLAuthorizationStatusAuthorizedWhenInUse) {
		SSWeatherAskSpringBoard(done);
		return;
	}
	CLLocation *location = manager.location;
	if (!location) {
		SSLog(@"weather: no last known location, using the cache");
		done(nil);
		return;
	}
	SSWeatherFetchAt(location.coordinate.latitude, location.coordinate.longitude, done);
}

// SpringBoard: pre-authorised for location. Last fix if under 30 min old, else one fresh fix (Kilometer accuracy, 6 s
// at most, then whatever fix exists), then Open-Meteo -> SS_WEATHER_CACHE -> READY (also when nothing was found, so
// CarPlay stops waiting).
@interface SSLocationOnce : NSObject <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *manager;
@property (nonatomic, copy) void (^done)(CLLocation *location);
@end
@implementation SSLocationOnce
- (void)locationManager:(CLLocationManager *)m didUpdateLocations:(NSArray<CLLocation *> *)locations { [self finish:locations.lastObject]; }
- (void)locationManager:(CLLocationManager *)m didFailWithError:(NSError *)error {
	SSLog(@"weather: location failed: %@", error.localizedDescription);
	[self finish:m.location];
}
- (void)finish:(CLLocation *)location {
	[self.manager stopUpdatingLocation];
	void (^done)(CLLocation *) = self.done;
	self.done = nil;
	if (done) done(location);
}
@end
static SSLocationOnce *gLocating;

static void SSWeatherServe(void) {
	if (gLocating) { SSLog(@"weather: request while a fix is pending, ignored"); return; }
	SSLocationOnce *once = [SSLocationOnce new];
	CLLocationManager *manager = [CLLocationManager new];
	manager.desiredAccuracy = kCLLocationAccuracyKilometer;
	manager.delegate = once;
	once.manager = manager;
	CLLocation *last = manager.location;
	CLAuthorizationStatus status = manager.authorizationStatus;
	SSLog(@"weather: SpringBoard location status %d, last fix %@", (int)status,
		last ? [NSString stringWithFormat:@"%.0fs old", -[last.timestamp timeIntervalSinceNow]] : @"none");
	void (^fetch)(CLLocation *) = ^(CLLocation *location) {
		gLocating = nil;
		if (!location) {
			SSLog(@"weather: SpringBoard has no location, answering without weather");
			notify_post(SS_NOTIFY_WEATHER_READY_C);
			return;
		}
		SSWeatherFetchAt(location.coordinate.latitude, location.coordinate.longitude, ^(NSDictionary *weather) {
			notify_post(SS_NOTIFY_WEATHER_READY_C);
		});
	};
	if (last && -[last.timestamp timeIntervalSinceNow] < 1800) { fetch(last); return; }
	once.done = fetch;
	gLocating = once;
	if (status == kCLAuthorizationStatusNotDetermined) [manager requestWhenInUseAuthorization];
	[manager startUpdatingLocation];
	__weak SSLocationOnce *weakOnce = once;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		SSLocationOnce *o = weakOnce;
		if (o && gLocating == o) { SSLog(@"weather: no fresh fix in 6s, using the last one"); [o finish:o.manager.location]; }
	});
}

static void SSWeatherRequestNotification(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
	dispatch_async(dispatch_get_main_queue(), ^{ SSWeatherServe(); });
}

// Open-Meteo at a position rounded to 2 decimals (about 1 km) - the only thing that leaves the phone.
static void SSWeatherFetchAt(double latitude, double longitude, void (^done)(NSDictionary *weather)) {
	double lat = round(latitude * 100.0) / 100.0;
	double lon = round(longitude * 100.0) / 100.0;
	NSString *query = [NSString stringWithFormat:@"https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f"
		"&current=temperature_2m,weather_code,is_day"
		"&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max"
		"&timezone=auto&forecast_days=1", lat, lon];
	NSURL *url = [NSURL URLWithString:query];
	if (!url) {
		done(nil);
		return;
	}

	NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	config.timeoutIntervalForRequest = kWeatherTimeout;
	config.timeoutIntervalForResource = kWeatherTimeout;
	config.waitsForConnectivity = NO;
	config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
	NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
	CFTimeInterval started = CACurrentMediaTime();
	NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSDictionary *weather = nil;
		NSInteger httpStatus = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
		if (data && !error && httpStatus == 200) {
			weather = SSWeatherParse([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
			if (weather) SSWeatherSaveCache(weather);
		}
		SSLog(@"weather: %@ in %.1fs (http %ld, %@)", weather ? @"updated" : @"failed", CACurrentMediaTime() - started,
			(long)httpStatus, error.localizedDescription ?: @"no error");
		dispatch_async(dispatch_get_main_queue(), ^{ done(weather); });
	}];
	[task resume];
	[session finishTasksAndInvalidate];
}

#pragma mark - Splash

// Marker class so the window hook below ignores our own window.
@interface SSSplashWindow : UIWindow
@end

@implementation SSSplashWindow
@end

@interface SSSplash : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, assign) NSInteger style;
@property (nonatomic, strong) UIImageView *imageView;       // Video style
@property (nonatomic, strong) SSStartupView *startView;     // the other styles
@property (nonatomic, weak) UIScreen *screen;
@property (nonatomic, copy) NSString *framesDir;
@property (nonatomic, assign) NSUInteger frameCount;
@property (nonatomic, assign) double fps;
@property (nonatomic, assign) BOOL loop;
@property (nonatomic, strong) NSMutableArray<UIImage *> *buffer;
@property (nonatomic, strong) dispatch_queue_t decodeQueue;
@property (nonatomic, assign) BOOL decoding;
@property (nonatomic, assign) NSUInteger queuedFrames;
@property (nonatomic, assign) NSUInteger shownFrames;
@property (nonatomic, assign) NSUInteger failedFrames;
@property (nonatomic, assign) CFTimeInterval startTime;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, copy) NSString *endReason;             // why it ended (log + auto test): tap, timer, ...
@property (nonatomic, assign) CFTimeInterval shownAt;        // window put on screen (CACurrentMediaTime)
@end

static NSString *gSSLastEnd;   // the last splash's end, "<reason> after <s>s" (auto test reports it when a splash ends too early)

@implementation SSSplash

// style: SS_STYLE_*. framesDir / frameCount / fps are for the Video style only (nil / 0 otherwise).
- (instancetype)initWithScreen:(UIScreen *)screen scene:(UIWindowScene *)scene style:(NSInteger)style occasion:(NSInteger)occasion
                     framesDir:(NSString *)framesDir frameCount:(NSUInteger)frameCount fps:(double)fps {
	if ((self = [super init])) {
		_screen = screen;
		_style = style;
		_framesDir = [framesDir copy];
		_frameCount = frameCount;
		_fps = fps;
		// Loop the clip until the configured duration is up, unless it should play exactly once.
		_loop = ![OMCPref(SS_KEY_PLAY_FULL, @NO) boolValue];
		_buffer = [NSMutableArray array];
		_decodeQueue = dispatch_queue_create("com.anlai.omnicar.startupscreen.decode", DISPATCH_QUEUE_SERIAL);

		BOOL tapSkip = [OMCPref(SS_KEY_TAP_TO_SKIP, @YES) boolValue];
		UIView *root = nil;

		if (style == SS_STYLE_VIDEO) {
			BOOL fit = [OMCPref(SS_KEY_SCALE_MODE, @0) integerValue] == 1;
			_imageView = [[UIImageView alloc] initWithFrame:screen.bounds];
			_imageView.backgroundColor = [UIColor blackColor];
			_imageView.contentMode = fit ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
			_imageView.clipsToBounds = YES;
			root = _imageView;
		} else {
			_startView = [[SSStartupView alloc] initWithFrame:screen.bounds];
			_startView.style = style;
			_startView.occasion = occasion;
			id name = OMCPref(SS_KEY_GREET_NAME, nil);
			_startView.name = [name isKindOfClass:[NSString class]] ? name : nil;
			_startView.logoEffect = [OMCPref(SS_KEY_LOGO_EFFECT, @(SS_EFFECT_FADE)) integerValue];
			_startView.carName = SSCarName();
			_startView.tempo = [OMCPref(SS_KEY_TEMPO, @1) integerValue];
			_startView.duration = SSDuration();
			if (style == SS_STYLE_LOGO) {
				_startView.image = SSDecodeFrame(SS_LOGO_PATH);
				if (!_startView.image) SSLog(@"no logo at %@, showing the car glyph", SS_LOGO_PATH);
			}
			if (style == SS_STYLE_HUD) _startView.hud = SSHudLines();
			if (style == SS_STYLE_HUD || style == SS_STYLE_BRIEFING) _startView.batteryPercent = SSBatteryPercent(NULL);
			if (style == SS_STYLE_BRIEFING) _startView.nextEvent = SSNextEvent();
			// Weather / Briefing: the cached result right away (or the greeting / no weather card), refreshed by
			// -start when the network answers.
			if (style == SS_STYLE_WEATHER || style == SS_STYLE_BRIEFING) _startView.weather = SSWeatherLoadCache(kWeatherMaxAge);
			[_startView reload];
			root = _startView;
		}
		root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		root.userInteractionEnabled = YES;

		UIViewController *vc = [UIViewController new];
		vc.view = root;

		// CarPlay may or may not drive the car display through a UIWindowScene.
		if (scene) {
			_window = [[SSSplashWindow alloc] initWithWindowScene:scene];
		} else {
			_window = [[SSSplashWindow alloc] initWithFrame:screen.bounds];
			// No scene to attach to, so setScreen: is the only way onto the car display.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			_window.screen = screen;
#pragma clang diagnostic pop
		}
		_window.windowLevel = UIWindowLevelAlert + 1000;
		_window.backgroundColor = [UIColor blackColor];
		_window.rootViewController = vc;

		if (tapSkip) {
			UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
			[root addGestureRecognizer:tap];
		}
	}
	return self;
}

- (void)start {
	self.shownAt = CACurrentMediaTime();
	self.window.hidden = NO;
	SSLog(@"splash window shown: style=%ld frame=%@ level=%.0f scene=%@ frames=%lu fps=%.0f loop=%d", (long)self.style,
		NSStringFromCGRect(self.window.frame), self.window.windowLevel,
		self.window.windowScene.session.persistentIdentifier, (unsigned long)self.frameCount, self.fps, self.loop);

	self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
	[self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	if (self.style == SS_STYLE_VIDEO) [self decodeMore];
	else if (self.style == SS_STYLE_WEATHER || self.style == SS_STYLE_BRIEFING) [self refreshWeather];

	// Safety net in case no frame ever decodes: never block CarPlay for long.
	__weak __typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (weakSelf && !weakSelf.shownFrames) {
			SSLog(@"no frame shown after 10s (failed=%lu), giving up", (unsigned long)weakSelf.failedFrames);
			[weakSelf dismissBecause:@"no frame after 10s"];
		}
	});
}

// Decodes frames one at a time on a background queue, keeping a few ready ahead of playback.
- (void)decodeMore {
	if (!self.frameCount || self.decoding || self.finished || self.buffer.count >= kFrameBufferSize) return;
	if (!self.loop && self.queuedFrames >= self.frameCount) return;
	// Every frame failing would otherwise spin forever.
	if (self.failedFrames >= self.frameCount) return;

	self.decoding = YES;
	NSUInteger index = self.queuedFrames % self.frameCount;
	self.queuedFrames++;
	NSString *path = [self.framesDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%05lu.jpg", (unsigned long)index]];
	dispatch_async(self.decodeQueue, ^{
		UIImage *image = SSDecodeFrame(path);
		dispatch_async(dispatch_get_main_queue(), ^{
			self.decoding = NO;
			if (self.finished) return;
			if (image) {
				[self.buffer addObject:image];
			} else if (self.failedFrames++ == 0) {
				SSLog(@"cannot decode %@", path);
			}
			[self decodeMore];
		});
	});
}

// Weather / Briefing: swap in fresh numbers if Open-Meteo answers while the splash is still up
// (an animated scene carries on from the same moment of its timeline).
- (void)refreshWeather {
	__weak __typeof(self) weakSelf = self;
	SSWeatherFetch(^(NSDictionary *weather) {
		SSSplash *splash = weakSelf;
		if (!weather || !splash || splash.finished) return;
		SSStartupView *view = splash.startView;
		view.weather = weather;
		[UIView transitionWithView:view duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
			[view reload];
			[view layoutIfNeeded];
		} completion:nil];
	});
}

- (void)tick {
	if (self.finished) return;
	if (self.style != SS_STYLE_VIDEO) {
		// Drawn styles: the first display refresh puts the content on screen; one tick is all they need.
		[self.displayLink invalidate];
		self.displayLink = nil;
		self.startTime = CACurrentMediaTime();
		self.shownFrames = 1;
		[self.startView playIntro];
		[self startCountdown];
		return;
	}
	if (!self.buffer.count) return;

	CFTimeInterval now = CACurrentMediaTime();
	if (!self.shownFrames) {
		self.startTime = now;
		[self startCountdown];
	} else if (self.shownFrames > (NSUInteger)((now - self.startTime) * self.fps)) {
		return; // Next frame isn't due yet.
	}

	self.imageView.image = self.buffer.firstObject;
	[self.buffer removeObjectAtIndex:0];
	self.shownFrames++;

	if (!self.loop && self.shownFrames >= self.frameCount) {
		[self.displayLink invalidate];
		__weak __typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / self.fps)), dispatch_get_main_queue(), ^{
			[weakSelf dismissBecause:@"video ended"];
		});
		return;
	}
	[self decodeMore];
}

// CarPlay's main thread can stall for seconds while it starts up, so the countdown only
// begins once the first frame is on screen.
- (void)startCountdown {
	BOOL timed = self.style != SS_STYLE_VIDEO || self.loop;
	NSTimeInterval limit = timed ? SSDuration() : kMaxFullPlay;
	SSLog(@"first frame shown, playing for up to %.0fs", limit);
	SSPublishStyle(self.style);
	SSPostNotification(SS_NOTIFY_AUDIO_PLAY);

	__weak __typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf dismissBecause:[NSString stringWithFormat:@"%.0fs timer", limit]];
	});
}

// Tap to skip. A knob / button press also fires a tap recognizer (no touches), so the log says which one it was.
- (void)tapped:(UITapGestureRecognizer *)tap {
	[self dismissBecause:tap.numberOfTouches ? @"tap" : @"press (knob / button)"];
}

- (void)dismiss {
	[self dismissBecause:@"skip"];
}

- (void)dismissBecause:(NSString *)reason {
	if (self.finished) return;
	self.finished = YES;
	self.endReason = reason;
	gSSLastEnd = [NSString stringWithFormat:@"%@ after %.1fs", reason, CACurrentMediaTime() - self.shownAt];
	SSLog(@"dismissing after %lu frames: %@", (unsigned long)self.shownFrames, gSSLastEnd);
	SSPostNotification(SS_NOTIFY_AUDIO_STOP);

	[UIView animateWithDuration:kFadeDuration animations:^{
		self.window.alpha = 0.0;
	} completion:^(BOOL done) {
		[self tearDown];
	}];
}

- (void)tearDown {
	// Skipped by dismiss when CarPlay disconnects mid-splash.
	if (!self.finished && self.shownFrames) SSPostNotification(SS_NOTIFY_AUDIO_STOP);
	if (!self.finished) {
		self.endReason = @"torn down";
		gSSLastEnd = [NSString stringWithFormat:@"torn down after %.1fs", CACurrentMediaTime() - self.shownAt];
	}
	self.finished = YES;
	[self.displayLink invalidate];
	self.displayLink = nil;
	[self.buffer removeAllObjects];
	self.window.hidden = YES;
	self.window = nil;
	// Only our own slot: an older splash fading out (or its late timer) must not unhook a newer one on the same screen
	// (a replay, or the next connection), which would free it and blank the car screen mid-play.
	UIScreen *screen = self.screen;
	if (screen && objc_getAssociatedObject(screen, &kSplashKey) == self)
		objc_setAssociatedObject(screen, &kSplashKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

#pragma mark - Car display detection

static BOOL SSIsCarScreen(UIScreen *screen) {
	if (!screen) return NO;
	if (screen.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomCarPlay) return YES;
	return screen != [UIScreen mainScreen];
}

// Keyed on the car UIScreen: a new screen object is created every time the car connects,
// so this gives one splash per connection whether CarPlay uses scenes or plain windows.
static void SSShowSplash(UIScreen *screen, UIWindowScene *scene, NSString *source) {
	if (!SSIsCarScreen(screen)) return;
	if (objc_getAssociatedObject(screen, &kShownKey)) return;
	objc_setAssociatedObject(screen, &kShownKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	SSLog(@"car display detected via %@: screen=%@ scene=%@", source, screen, scene);

	OMCPrefsSync();
	if (!OMCFeatureEnabled(SS_FEATURE)) { SSLog(@"disabled in settings"); return; }

	NSInteger occasion = SS_OCCASION_NONE;
	NSInteger style = SSResolveStyle(&occasion);
	if (style != SSCurrentStyle()) SSLog(@"style %ld this time (setting %ld, occasion %ld)", (long)style, (long)SSCurrentStyle(), (long)occasion);
	SSSplash *splash = nil;
	// Video chosen but none ready (no file, or not converted yet): the OmniCar liquid screen instead of nothing.
	NSString *name = style == SS_STYLE_VIDEO ? SSVideoName() : nil;
	NSString *framesDir = name ? SS_FRAMES_DIR(name) : nil;
	NSDictionary *info = framesDir ? [NSDictionary dictionaryWithContentsOfFile:[framesDir stringByAppendingPathComponent:@"info.plist"]] : nil;
	NSUInteger count = [info[@"count"] unsignedIntegerValue];
	double fps = [info[@"fps"] doubleValue];
	if (style == SS_STYLE_VIDEO && (!name || !count || fps <= 0)) {
		if (!name) SSLog(@"no video found in %@ -> liquid style", SS_VIDEOS_DIR);
		else SSLog(@"no frames for %@ (open Settings > OmniCar > Startup Screen to convert it) -> liquid style", name);
		style = SS_STYLE_LIQUID;
	}
	if (style == SS_STYLE_VIDEO) {
		SSLog(@"playing %@ (%lu frames @ %.0ffps)", name, (unsigned long)count, fps);
		splash = [[SSSplash alloc] initWithScreen:screen scene:scene style:style occasion:SS_OCCASION_NONE framesDir:framesDir frameCount:count fps:fps];
	} else {
		SSLog(@"showing style %ld", (long)style);
		splash = [[SSSplash alloc] initWithScreen:screen scene:scene style:style occasion:occasion framesDir:nil frameCount:0 fps:0];
	}
	objc_setAssociatedObject(screen, &kSplashKey, splash, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[splash start];
}

static NSString *SSDescribeScreen(UIScreen *screen) {
	if (!screen) return @"(nil)";
	return [NSString stringWithFormat:@"<%@ %p main=%d idiom=%ld bounds=%@>", NSStringFromClass([screen class]), screen,
		screen == [UIScreen mainScreen], (long)screen.traitCollection.userInterfaceIdiom, NSStringFromCGRect(screen.bounds)];
}

static void SSHandleScene(UIScene *scene, NSString *source) {
	SSLog(@"%@: %@ role=%@", source, NSStringFromClass([scene class]), scene.session.role);
	if (![scene isKindOfClass:[UIWindowScene class]]) return;
	UIWindowScene *windowScene = (UIWindowScene *)scene;
	SSLog(@"%@: idiom=%ld screen=%@", source, (long)windowScene.traitCollection.userInterfaceIdiom,
		SSDescribeScreen(windowScene.screen));
	SSShowSplash(windowScene.screen, windowScene, source);
}

static void SSTearDownScreen(UIScreen *screen) {
	if (!screen) return;
	SSSplash *splash = objc_getAssociatedObject(screen, &kSplashKey);
	[splash tearDown];
}

#pragma mark - Auto test (developer only)

#if OMC_AUTOTEST
// Bo test "startupScreen" (Core/OMCTest.h): phat lai man hinh khoi dong tren xe nhu luc cam xe va kiem tra no hien,
// chay khung hinh, tu tat dung han, cham de bo qua, va khong phat khi tinh nang tat.
static UIScreen *SSTestCarScreen(UIWindowScene **outScene) {
	for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
		if ([sc isKindOfClass:[UIWindowScene class]] && SSIsCarScreen(((UIWindowScene *)sc).screen)) {
			if (outScene) *outScene = (UIWindowScene *)sc;
			return ((UIWindowScene *)sc).screen;
		}
	}
	if (outScene) *outScene = nil;
	for (UIScreen *screen in [UIScreen screens]) if (SSIsCarScreen(screen)) return screen;
	return nil;
}

static SSSplash *SSTestSplash(void) {
	UIScreen *screen = SSTestCarScreen(NULL);
	return screen ? objc_getAssociatedObject(screen, &kSplashKey) : nil;
}

// Nhu luc cam xe: bo dau "da phat" cua man xe roi goi dung ham phat
static NSString *SSTestReplay(void) {
	UIWindowScene *scene = nil;
	UIScreen *screen = SSTestCarScreen(&scene);
	if (!screen) return @"khong thay man xe";
	[SSTestSplash() tearDown];
	gSSLastEnd = nil;
	objc_setAssociatedObject(screen, &kShownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	// Le / sinh nhat: bo qua man hinh dip dac biet de kiem dung kieu da chon (va khong tieu luot hien trong ngay)
	gSSTestNoOccasion = YES;
	SSShowSplash(screen, scene, @"autotest");
	gSSTestNoOccasion = NO;
	return nil;
}

static NSDictionary *SSTestFramesInfo(void) {
	NSString *name = SSVideoName();
	return name ? [NSDictionary dictionaryWithContentsOfFile:[SS_FRAMES_DIR(name) stringByAppendingPathComponent:@"info.plist"]] : nil;
}

static NSString *SSTestShowing(void) {
	SSSplash *sp = SSTestSplash();
	if (!sp || sp.finished)
		return OMCTestFormat(@"khong co man hinh khoi dong dang phat (da tat: %@)", gSSLastEnd ?: @"khong ro, chua goi dismiss");
	if (!sp.window || sp.window.hidden || sp.window.alpha < 0.5) return @"cua so man hinh khoi dong dang an";
	if (!sp.shownFrames) return OMCTestFormat(@"chua hien khung nao (giai ma loi %lu)", (unsigned long)sp.failedFrames);
	return nil;
}

static NSArray<NSDictionary *> *SSTestSteps(void) {
	NSMutableArray *steps = [NSMutableArray array];
	NSInteger style = SSCurrentStyle();
	BOOL video = style == SS_STYLE_VIDEO;
	BOOL randomStyle = style == SS_STYLE_RANDOM;   // moi lan phat mot kieu, co the la video
	NSDictionary *info = (video || randomStyle) ? SSTestFramesInfo() : nil;
	double fps = [info[@"fps"] doubleValue];
	NSUInteger count = [info[@"count"] unsignedIntegerValue];
	BOOL playFull = [OMCPref(SS_KEY_PLAY_FULL, @NO) boolValue];
	BOOL loop = !video || !playFull;
	double fullLength = MIN(kMaxFullPlay, fps > 0 ? count / fps : kMaxFullPlay);
	double length = loop ? SSDuration() : fullLength;
	if (randomStyle && playFull && count && fps > 0) length = MAX(length, fullLength);   // Random co the boc trung video phat het

	[steps addObject:OMCTestStep(@"Moi truong: video va khung hinh", 0, 0, nil, ^NSString *{
		if (!OMCFeatureEnabled(SS_FEATURE)) return @"Man hinh khoi dong dang tat";
		if (!video) {
			OMCTestLog(@"kieu %ld (%@), phat toi da %.1fs", (long)style, randomStyle ? @"ngau nhien" : @"ve, khong phai video", length);
			return nil;
		}
		NSString *name = SSVideoName();
		if (!name) return OMCTestFormat(@"chua co video trong %@", SS_VIDEOS_DIR);
		if (!count || fps <= 0) return OMCTestFormat(@"%@ chua trich khung (mo Cai dat > Man hinh khoi dong)", name);
		OMCTestLog(@"video %@: %lu khung @ %.0f fps, phat %.1fs, lap=%d", name, (unsigned long)count, fps, length, loop);
		return nil;
	})];
	if (!OMCFeatureEnabled(SS_FEATURE) || (video && (!count || fps <= 0))) return steps;

	[steps addObject:OMCTestStep(@"Phat lai nhu luc cam xe", 1, 6, ^NSString *{ return SSTestReplay(); }, ^NSString *{ return SSTestShowing(); })];
	__block NSUInteger seen = 0;
	if (video) [steps addObject:OMCTestStep(@"Khung hinh chay (khong dung hinh)", 0, 3, ^NSString *{
		seen = SSTestSplash().shownFrames; return nil;
	}, ^NSString *{
		SSSplash *sp = SSTestSplash();
		if (!sp || sp.finished) return @"da tat truoc khi kiem";
		return sp.shownFrames > seen + 2 ? nil : OMCTestFormat(@"khung dung o %lu", (unsigned long)sp.shownFrames);
	})];
	[steps addObject:OMCTestStep(OMCTestFormat(@"Tu tat sau ~%.0fs", length), 1, length + 4, nil, ^NSString *{
		return SSTestSplash() ? @"van con man hinh khoi dong" : nil;
	})];

	if ([OMCPref(SS_KEY_TAP_TO_SKIP, @YES) boolValue]) {
		[steps addObject:OMCTestStep(@"Phat lai de thu cham bo qua", 1, 6, ^NSString *{ return SSTestReplay(); }, ^NSString *{ return SSTestShowing(); })];
		[steps addObject:OMCTestStep(@"Cham de bo qua", 0.2, 2, ^NSString *{
			SSSplash *sp = SSTestSplash();
			if (!sp) return @"khong co man hinh khoi dong";
			[sp dismiss];   // cung viec cu cham tren anh
			return nil;
		}, ^NSString *{ return SSTestSplash() ? @"chua tat sau khi cham" : nil; })];
	} else {
		[steps addObject:OMCTestStep(@"Cham de bo qua", 0, 0, ^NSString *{ return @"dang tat trong Cai dat"; }, nil)];
	}

	// Tat tinh nang -> khong phat; bat lai ngay trong cung buoc (khong de tinh nang tat neu bai test dung giua chung)
	[steps addObject:OMCTestStep(@"Tat tinh nang thi khong phat", 2.5, 2.5, ^NSString *{
		CFPreferencesSetAppValue((__bridge CFStringRef)SS_KEY_ENABLED, kCFBooleanFalse, OMC_PREFS_DOMAIN);
		CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
		return SSTestReplay();
	}, ^NSString *{
		BOOL shown = SSTestSplash() != nil;
		[SSTestSplash() tearDown];
		CFPreferencesSetAppValue((__bridge CFStringRef)SS_KEY_ENABLED, kCFBooleanTrue, OMC_PREFS_DOMAIN);
		CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
		return shown ? @"van phat khi tinh nang tat" : nil;
	})];
	return steps;
}

static void SSTestInstall(void) {
	OMCTestRegister(SS_FEATURE, ^BOOL { return SSTestCarScreen(NULL) != nil; }, ^NSArray<NSDictionary *> *{ return SSTestSteps(); }, nil);
}
#endif

%group StartupScreen

%hook UIWindow

// Fallback for CarPlay builds that put windows straight onto the car UIScreen without
// posting the UIScene lifecycle notifications.
- (void)setHidden:(BOOL)hidden {
	%orig;
	if (!gIsCarPlay || hidden || [self isKindOfClass:[SSSplashWindow class]]) return;
	UIScreen *screen = self.screen;

	// Diagnostics: record the first windows CarPlay shows and where they live.
	static int logged = 0;
	if (logged < 40) {
		logged++;
		SSLog(@"window shown: %@ level=%.0f scene=%@ %p %@ screen=%@", NSStringFromClass([self class]), self.windowLevel,
			self.windowScene ? NSStringFromClass([self.windowScene class]) : @"(nil)", self.windowScene,
			self.windowScene.session.persistentIdentifier, SSDescribeScreen(screen));
	}

	if (!SSIsCarScreen(screen)) return;
	UIWindowScene *scene = self.windowScene;
	// Let CarPlay finish building its own windows first so ours ends up on top.
	dispatch_async(dispatch_get_main_queue(), ^{ SSShowSplash(screen, scene, @"window"); });
}

%end

%end

%ctor {
	@autoreleasepool {
		NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;

		// SpringBoard side: the soundtrack player and the weather fetch (location) for the Weather / Briefing styles.
		if ([bundleID isEqualToString:@"com.apple.springboard"]) {
			CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
			CFNotificationCenterAddObserver(darwin, NULL, SSAudioNotification, SS_NOTIFY_AUDIO_PLAY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			CFNotificationCenterAddObserver(darwin, NULL, SSAudioNotification, SS_NOTIFY_AUDIO_STOP, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			CFNotificationCenterAddObserver(darwin, NULL, SSWeatherRequestNotification, CFSTR(SS_NOTIFY_WEATHER_REQUEST_C), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			// Warm the weather cache once SpringBoard is up: the first splash after a respring then has today's weather
			// even if its own request raced the registration above.
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				SSLog(@"weather: warming the cache at startup");
				SSWeatherServe();
			});
			// Create the call observer once SpringBoard is up, so its call list is filled in by the time a car connects.
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				if (!gCallObserver) gCallObserver = [CXCallObserver new];
			});
			return;
		}
		if (![bundleID isEqualToString:@"com.apple.CarPlayApp"]) return;
		if (!OMCCrashGuard(SS_FEATURE)) return;
		gIsCarPlay = YES;
		%init(StartupScreen);
#if OMC_AUTOTEST
		SSTestInstall();
#endif

		for (UIScreen *screen in [UIScreen screens]) SSLog(@"existing screen: %@", SSDescribeScreen(screen));
		SSLog(@"videos dir %@ readable=%d", SS_VIDEOS_DIR, [[NSFileManager defaultManager] isReadableFileAtPath:SS_VIDEOS_DIR]);

		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		NSOperationQueue *main = [NSOperationQueue mainQueue];
		[nc addObserverForName:UISceneWillConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			UIScene *scene = note.object;
			dispatch_async(dispatch_get_main_queue(), ^{ SSHandleScene(scene, @"sceneConnect"); });
		}];
		// Trait collection may not be resolved at connect time; retry once the scene activates.
		[nc addObserverForName:UISceneDidActivateNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			SSHandleScene(note.object, @"sceneActivate");
		}];
		[nc addObserverForName:UIScreenDidConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			SSLog(@"screen connected: %@", SSDescribeScreen(note.object));
		}];
		[nc addObserverForName:UIScreenDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			SSLog(@"screen disconnected: %@", SSDescribeScreen(note.object));
			SSTearDownScreen(note.object);
		}];
		[nc addObserverForName:UISceneDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			UIScene *scene = note.object;
			if ([scene isKindOfClass:[UIWindowScene class]]) SSTearDownScreen(((UIWindowScene *)scene).screen);
		}];
	}
}
