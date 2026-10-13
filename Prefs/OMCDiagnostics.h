// Support data for the settings pages: the Diagnostics page (OMCDiagnosticsController), the one-tap
// "Send log" report, conflicting tweaks and rescue mode. The tweak side writes what only it can see
// (car screen, hook checks, rescue list: OMC_KEY_* in Core/OmniCar.h); this reads it back.
#import <UIKit/UIKit.h>
#import "OmniCar.h"

// Diagnostics as sections: @{@"title", @"rows": @[@{@"label", @"value"}], @"footer"}, localized.
NSArray<NSDictionary *> *OMCDiagSections(void);

// Other tweaks that also change CarPlay: @{@"name", @"active"} (active = its dylib is installed and
// not disabled, so it loads next to OmniCar; otherwise only the package is installed).
NSArray<NSDictionary *> *OMCConflictingTweaks(void);

// Feature key prefixes rescue mode turned off ("splitScreen" ...), their names, and turning them back on.
NSArray<NSString *> *OMCRescueFeatures(void);
NSString *OMCFeatureDisplayName(NSString *prefix);
void OMCRescueRestore(void);

#if OMC_AUTOTEST
// Developer auto test (Core/OMCTest.h). The stored run (OMC_KEY_AUTOTEST) or nil; the suites some process
// registered: @{@"suite", @"name", @"process"}; start a run of `suites` in that order; stop it.
NSDictionary *OMCAutoTestState(void);
NSArray<NSDictionary *> *OMCAutoTestSuites(void);
void OMCAutoTestStart(NSArray<NSString *> *suites);
void OMCAutoTestStop(void);
#endif

// Writes the report (device, features, car, conflicts, packages, OmniCar.log) to a .txt in tmp and opens the
// share sheet from `vc` (Zalo, Mail, Files ...). Dev builds add the auto test results and car-screen snapshots.
void OMCShareReport(UIViewController *vc, UIBarButtonItem *barItem);
