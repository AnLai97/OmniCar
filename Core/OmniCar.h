// OmniCar core - what every feature's hooks can rely on: the prefs domain, a prefs reader, the
// master switch and a shared logger. Core/OmniCar.m is compiled into every feature dylib.
//
// A feature lives in Features/<Name>/ and builds to OmniCar<Name>.dylib: <Name>.h (keys, paths,
// notification names shared with its settings page), <Name>.x (hooks in %group <Name>, installed by
// its own %ctor), Filter.plist (processes), feature.mk (frameworks), Prefs/ (its settings page).
// Every pref key is prefixed with the feature name in lower camel case ("startupScreenVideoName");
// "<feature>Enabled" is the feature's own switch. Core/Core.x is the OmniCarCore dylib (SpringBoard).

#import <Foundation/Foundation.h>
#import <rootless.h>

#ifndef OMC_FEATURE
#define OMC_FEATURE "Prefs"
#endif

// Developer auto test on the car (Core/OMCTest.h): 1 = the test runner, every feature's test cases and the
// Settings page are built in; 0 leaves all of it out. Off since 20/10/2026 (builds also go to other people's cars);
// `make package OMC_AUTOTEST=1` while the author tests on the car.
#ifndef OMC_AUTOTEST
#define OMC_AUTOTEST 0
#endif

// Free period: every feature works through this day (yyyy-MM-dd, Vietnam time) and turns itself off after it,
// with no notice before. "" = never expires. `make package OMC_EXPIRY=2027-06-30` (or OMC_EXPIRY=) overrides it.
#ifndef OMC_EXPIRY
#define OMC_EXPIRY "2027-04-30"
#endif

#define OMC_PREFS_DOMAIN  CFSTR("com.anlai.omnicar")
#define OMC_PREFS_CHANGED CFSTR("com.anlai.omnicar/prefschanged")
// Data root; features keep their files under OMC_DATA_ROOT/<Name>/.
#define OMC_DATA_ROOT     ROOT_PATH_NS(@"/var/mobile/Library/OmniCar")

#ifdef __cplusplus
extern "C" {
#endif

// Re-read the prefs domain (call before reading a batch of values at a decision point).
void OMCPrefsSync(void);
id OMCPref(NSString *key, id fallback);
// Master switch ("enabled", default YES); NO once the free period is over (OMCExpired).
BOOL OMCEnabled(void);
// Past the end of OMC_EXPIRY. "Now" is the later of the device clock and the last time read from a web
// server (OMC_KEY_TRUSTED_TIME, kept by SpringBoard), so setting the clock back does not reopen it.
// Shared by every dylib and the settings bundle (Core/OMCCommon.m).
BOOL OMCExpired(void);
#define OMC_KEY_TRUSTED_TIME @"trustedTime"   // NSNumber, seconds since 1970
// SpringBoard only: read the time from a web server now and every few hours, store it, and post
// OMC_PREFS_CHANGED the moment the free period ends so running features stop.
void OMCTrustedTimeStart(void);
// Master switch AND "<feature>Enabled" (default YES). `feature` is the key prefix, e.g. @"startupScreen".
BOOL OMCFeatureEnabled(NSString *feature);

// Logs "[OmniCar/<feature>] message" to syslog and to /var/mobile/Documents/OmniCar.log. A process
// that cannot write there (sandboxed app) relays the line to SpringBoard over OMC_LOG_RELAY.
void OMCLogWrite(NSString *feature, NSString *message);
#define OMCLog(feature, fmt, ...) OMCLogWrite(feature, [NSString stringWithFormat:fmt, ##__VA_ARGS__])
#define OMC_LOG_RELAY     @"com.anlai.omnicar/log"
// Darwin notification a feature posts while it owns the car screen (Split Screen: split active, layout
// panel or app picker open), state 1 then 0. Overlays on the car screen (Speed Bubble) hide while it is 1.
#define OMC_DARWIN_CAR_BUSY "com.anlai.omnicar/car.busy"
// SpringBoard only (called by the OmniCarCore dylib): append relayed lines to the log file.
void OMCLogRelayStart(void);

// Logos hooks on a class / method this iOS lacks are skipped without a word. A feature lists what its
// %hooks need ("DBDashboard -_handleHomeEvent:", "DashBoard +_newApplicationLibrary") right after %init;
// what is missing on this iOS goes to the log with the iOS version (iOS 15 / 17 / 18 field reports).
void OMCCheckHooks(NSString *feature, NSArray<NSString *> *hooks);
// Selector exists on the class (instance method; "+" prefix for class methods). For %hooks that only
// exist on newer iOS: install that %group only when it is there.
BOOL OMCHasMethod(const char *className, NSString *selector);
// A runtime call found the object (non-nil) without the method: log once per class + selector.
void OMCMissingSelector(NSString *feature, id obj, NSString *selector);

// CarPlay process classes by their iOS 16+ name (DashBoard.framework: DashBoard, DBDashboard, DBEvent ...).
// iOS 14 / 15 have the same classes in CarPlay.app under a CAR prefix (CARApplication, CARDashboard,
// CAREvent, _CARDashboardHomeViewController ...), which this falls back to. Nil when neither exists.
// Hooks: %init(GROUP, DBDashboard = OMCCarClass("DBDashboard"), ...).
Class OMCCarClass(const char *name);
// [DBApplicationLaunchInfo launchInfoForApplication:] (iOS 16) or
// [CARApplicationLaunchInfo launchInfoForApplication:withActivationSettings:nil] (iOS 14 / 15).
id OMCCarLaunchInfo(id appInfo);

// Rescue mode (CarPlay process). First line of a feature's CarPlay %ctor, before %init:
//   if (!OMCCrashGuard(SPL_FEATURE)) return;
// The first call in the process installs the crash logger (signal + uncaught exception -> a file in tmp,
// copied into OmniCar.log on the next launch) and records the car screen for the Diagnostics page.
// CarPlay crashing OMC_RESCUE_CRASHES times in a row within OMC_RESCUE_SECONDS of starting turns the
// feature seen in the crash backtrace off (every CarPlay feature when none is), lists it under
// OMC_KEY_RESCUE and posts OMC_DARWIN_RESCUE (SpringBoard tells the user). NO = this feature is off by
// rescue mode: skip its hooks. Turning the feature back on in Settings takes it off the list.
BOOL OMCCrashGuard(NSString *feature);
#define OMC_RESCUE_CRASHES   2
#define OMC_RESCUE_SECONDS   60
#define OMC_KEY_RESCUE       @"rescueFeatures"     // [feature key prefix] turned off by rescue mode
#define OMC_KEY_RESCUE_DATE  @"rescueDate"
#define OMC_DARWIN_RESCUE    "com.anlai.omnicar/rescue"
#if OMC_AUTOTEST
// Rescue-mode test (Settings > Developer > Autotest > Test rescue mode): feature key prefix whose CarPlay %ctor crashes
// CarPlay a few seconds after it starts, until rescue mode turns that feature off.
#define OMC_KEY_CRASH_TEST   @"debugCrashTest"
// Auto test run (Core/OMCTest.m): {state: running | done | stopped, run (NSDate), suites: [suite], suite (index),
// step (index), inStep, results: [{suite, name, status: pass | fail | skip | crash, detail, seconds, shot}], ios}.
// Settings writes a new run (state running) or state stopped and posts OMC_DARWIN_AUTOTEST; the process owning
// the current suite runs it. Crashes while it runs never count toward rescue mode.
#define OMC_KEY_AUTOTEST       @"autoTest"
#define OMC_KEY_AUTOTEST_PICK  @"autoTestPick"     // suites ticked in Settings
#define OMC_KEY_AUTOTEST_AVAIL @"autoTestAvail."   // + suite: {process, date}, written when a suite registers
#define OMC_DARWIN_AUTOTEST    "com.anlai.omnicar/autotest"
#define OMC_AUTOTEST_DIR       @"/var/mobile/Documents/OmniCar-AutoTest"   // autotest.txt
// A touch inside an app on the car, made by the app itself (OMCTestTouch* in OMCTest.m; Features/AppBridge/App.xm, loaded
// into every app, listens). CarPlay process -> app (distributed notification, object = bundle id, userInfo):
//   seq      number, echoed in the reply
//   kind     tap | drag
//   target   host (the iPhone window App Bridge shows on the car) | car (the app's own CarPlay window)
//   fx, fy   0..1 of the window (tap point / drag start); fx2, fy2: drag end; back = 1: drag there and back
//   find     video: tap the first video thumbnail found in the window instead of fx / fy (YouTube)
// The app draws a finger at the point, sends the touch through UIKit and replies with a Darwin notification whose state is
// (ABBundleHash(bundle id) << 24) | (seq << 8) | result bits.
#define OMC_NOTIF_AUTOTEST_TOUCH  @"com.anlai.omnicar/autotest.touch"
#define OMC_DARWIN_AUTOTEST_TOUCH "com.anlai.omnicar/autotest.touchdone"
#define OMC_AT_TOUCH_HIT       1   // the touch reached a view of the app
#define OMC_AT_TOUCH_GESTURE   2   // a gesture recognizer of that view (or a parent) took it: the map panned / the cell was tapped
#define OMC_AT_TOUCH_CHANGED   4   // the screen changed within 3 s of a tap (another view at the point / a big view controller appeared)
#define OMC_AT_TOUCH_NOWINDOW  8   // the app has no such window (not on the car)
#endif
// Diagnostics written by the tweak, read by Settings (Diagnostics page, Send log):
// last car screen and session (dictionary, see OMCRecordCarScreen in OmniCar.m) ...
#define OMC_KEY_DIAG_CAR     @"diagCar"
// ... and one key per feature and process with the OMCCheckHooks result: {ios, total, missing}.
#define OMC_KEY_DIAG_HOOKS   @"diagHooks."
// ... one key per dylib and process it loaded into (SpringBoard, CarPlay): {version, date}. Settings compares the
// version with the installed one (respring needed after an update) and sees which features never loaded ...
#define OMC_KEY_DIAG_LOADED  @"diagLoaded."
// ... and the last CarPlay crash the crash guard caught: {date, age (s after start), suspect (feature key prefix)}.
#define OMC_KEY_DIAG_CRASH   @"diagLastCrash"
// ... and how CarPlay ran on the last drive (performance monitor, started with the crash guard, runs while a car
// screen is connected): {start, updated, seconds, fps (car screen max), frames, late (frames > 1.5x the frame time,
// counted 10 s of every minute), worstMs, hangs (main thread stuck >= 0.5 s), freezes (>= 2 s), hangMaxMs,
// hangWho ({dylib that logged last: count}), cpuAvg, cpuMax (% of one core), memMB, memMaxMB (CarPlay footprint),
// availMinMB (memory CarPlay can still use before iOS kills it, 0 = unknown), sysFreeMinMB (phone free RAM),
// thermalMax (NSProcessInfoThermalState), lowPower, tweaks ([other dylibs injected into CarPlay])}.
#define OMC_KEY_DIAG_PERF    @"diagPerf"

// Lite mode (Diagnostics > Optimize): features drop what costs the most while driving - Split Screen draws its
// panels without blur and offers 2 panes only, Speed Bubble refreshes once a second without shadows, the startup
// screen is skipped. OMC_KEY_LITE_MODE: 0 off, 1 always, 2 auto (default): on while the phone is hot (thermal
// serious or worse) or while the CarPlay performance monitor sees it struggle (repeated hangs, many late frames),
// which it publishes as the state of OMC_DARWIN_LITE (1 = on, 0 = off) and posts on every change.
#define OMC_KEY_LITE_MODE    @"liteMode"
#define OMC_DARWIN_LITE      "com.anlai.omnicar/lite"
BOOL OMCLiteActive(void);
// The car connection from the CarKit session CarPlay records on every connect (OMC_KEY_DIAG_CAR): 1 wireless, 0 wired,
// -1 unknown (property names change between iOS versions; Diagnostics reads the same fields).
int OMCCarWireless(void);
// Free memory when the car connects (Diagnostics > Optimize, default off): SpringBoard (Core.x) quits the user apps
// running in the background except music / navigation / CarPlay apps, the apps chosen for the car screen and the
// Speed Bubble source. The CarPlay process posts OMC_DARWIN_CAR_CONNECTED when a car screen appears.
#define OMC_KEY_CLEAN_RAM    @"cleanRamOnConnect"
#define OMC_DARWIN_CAR_CONNECTED "com.anlai.omnicar/car.connected"
// Last position of the phone, relayed by the navigation app the Speed Bubble runs in (its own GPS fix, at most once a
// minute) for features that have no location access of their own (SpringBoard and CarPlay.app are not authorised on
// iOS 16.6 - log 18/10 12:07: status 0, kCLErrorDomain 1 - and cannot ask). State = latitude and longitude rounded to
// 2 decimals (about 1 km) as two signed 32-bit integers (x100); 0 = none. Readers keep their own copy on disk.
#define OMC_DARWIN_LOCATION  "com.anlai.omnicar/location"
static inline uint64_t OMCLocationPack(double lat, double lon) {
    int32_t a = (int32_t)lround(lat * 100), b = (int32_t)lround(lon * 100);
    return ((uint64_t)(uint32_t)a << 32) | (uint64_t)(uint32_t)b;
}
static inline BOOL OMCLocationUnpack(uint64_t state, double *lat, double *lon) {
    if (!state) return NO;
    *lat = (int32_t)(uint32_t)(state >> 32) / 100.0;
    *lon = (int32_t)(uint32_t)(state & 0xFFFFFFFF) / 100.0;
    return YES;
}
#define OMC_DARWIN_CLEAN_NOW "com.anlai.omnicar/cleanram.now"   // Settings: free memory now (whatever the switch)
// Profiles per car (Settings > Car profiles, off by default): when a car connects the CarPlay process saves the
// OMCProfileKeys() values into the previous car's profile and loads the new car's (or starts one from the current
// values). OMC_KEY_PROFILES = {car key: {name, lastSeen, values: {pref key: value}}}; OMC_KEY_PROFILE_CURRENT = car key.
#define OMC_KEY_PROFILES_ON      @"carProfilesEnabled"
#define OMC_KEY_PROFILES         @"carProfiles"
#define OMC_KEY_PROFILE_CURRENT  @"carProfileCurrent"
NSArray<NSString *> *OMCProfileKeys(void);
// Last RAM cleanup: {date, closed: [bundle id]} (Diagnostics shows it).
#define OMC_KEY_DIAG_CLEAN   @"diagCleanRam"

// Languages: vi and en are written in the code; the others come from the settings bundle's <lang>.lproj tables.
// OMCCurrentLanguage: the "language" pref (Settings), else the device language when OmniCar has it, else "en".
// OMCTr: text shown on the car / in notices, written as OMCTr(@"Vietnamese", @"English"); other languages look the
// English text up in <lang>.lproj/Car.strings (keys are the English text), falling back to English.
// App cua jailbreak (Dopamine, Sileo, Zebra, Filza, palera1n, NewTerm...) khong bao gio dua len man xe: bo khoi bang chon app
// cua App Bridge, danh sach app iPhone cua Chia man hinh va danh sach chen icon (log 19/10 21:59: nguoi dung chon app Dopamine,
// CarPlay chet ngay sau khi chen icon). bid theo tien to; path (bundle, co the nil) nam trong goc rootless cung tinh.
static inline BOOL OMCIsJailbreakApp(NSString *bid, NSString *path) {
	static NSArray<NSString *> *prefixes;
	if (!prefixes) prefixes = @[@"com.opa334.", @"org.coolstar.", @"xyz.willy.", @"com.saurik.", @"org.palera1n", @"com.palera1n",
	                            @"com.tigisoftware.", @"ws.hbang.", @"com.rpetrich.", @"com.anlai.omnicar", @"com.roothide.", @"io.roothide.",
	                            @"com.serena.", @"com.nito.", @"com.ichitaso.", @"net.angelxwind."];
	for (NSString *p in prefixes) if ([bid hasPrefix:p]) return YES;
	return path.length > 0 && ([path containsString:@"/.jbroot"] || [path hasPrefix:@"/var/jb/"] || [path containsString:@"/procursus/"]);
}

NSArray<NSString *> *OMCSupportedLanguages(void);
NSString *OMCCurrentLanguage(void);
NSString *OMCTr(NSString *vi, NSString *en);

// Background of the OmniCar logo (DESIGN.md, tools/preview/index.html#overview): a 4-corner pastel mesh - lavender top left,
// sky top right, pink bottom left, mint bottom right. Small image meant to be stretched (scale to fill) under the car
// panels. solid NO: slightly see-through (on frosted glass); YES: opaque (the dock button tile).
@class UIImage;
UIImage *OMCLogoMeshImage(BOOL solid);

#ifdef __cplusplus
}
#endif
