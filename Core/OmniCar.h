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
// Settings page are built in; 0 for a release build. `make OMC_AUTOTEST=0` overrides it without editing.
#ifndef OMC_AUTOTEST
#define OMC_AUTOTEST 1
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
// Master switch ("enabled", default YES).
BOOL OMCEnabled(void);
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
// Rescue-mode test (Settings > Auto test > Test rescue mode): feature key prefix whose CarPlay %ctor crashes
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
#define OMC_AUTOTEST_DIR       @"/var/mobile/Documents/OmniCar-AutoTest"   // snapshots + autotest.txt
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

#ifdef __cplusplus
}
#endif
