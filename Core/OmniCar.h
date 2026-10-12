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

#ifdef __cplusplus
}
#endif
