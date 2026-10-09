// OmniCar core - what every feature's hooks can rely on: the prefs domain, a prefs reader, the
// master switch and a shared logger. Core/OmniCar.m is compiled into every feature dylib.
//
// A feature lives in Features/<Name>/ and builds to OmniCar<Name>.dylib: <Name>.h (keys, paths,
// notification names shared with its settings page), <Name>.x (hooks in %group <Name>, installed by
// its own %ctor), Filter.plist (processes), feature.mk (frameworks), Prefs/ (its settings page). Every pref key is prefixed with the feature name in lower camel case
// ("startupScreenVideoName"); "<feature>Enabled" is the feature's own switch.

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

// Logs "[OmniCar/<feature>] message" to syslog and to OmniCar.log (Documents, else /var/tmp).
void OMCLogWrite(NSString *feature, NSString *message);
#define OMCLog(feature, fmt, ...) OMCLogWrite(feature, [NSString stringWithFormat:fmt, ##__VA_ARGS__])

#ifdef __cplusplus
}
#endif
