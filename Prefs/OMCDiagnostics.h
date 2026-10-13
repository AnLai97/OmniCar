// Support data for the settings pages: the Diagnostics page (OMCDiagnosticsController), the one-tap
// "Send log" report, conflicting tweaks and rescue mode. The tweak side writes what only it can see
// (car screen, hook checks, rescue list: OMC_KEY_* in Core/OmniCar.h); this reads it back.
#import <UIKit/UIKit.h>
#import "OmniCar.h"

// Health checks, in plain words: @[@{@"title", @"checks": @[@{@"title", @"status": ok | warn | bad | info, @"value",
// @"fix" (what to do, optional), @"action" (respring | rescue, optional)}]}] for the phone, CarPlay and each feature.
NSArray<NSDictionary *> *OMCDiagChecks(void);
// One line over all checks: @{@"status", @"title" ("Everything looks good" / "2 things need attention"), @"subtitle"}.
NSDictionary *OMCDiagSummary(NSArray<NSDictionary *> *groups);
// Technical details (raw values) as sections: @{@"title", @"rows": @[@{@"label", @"value"}], @"footer"}, localized.
NSArray<NSDictionary *> *OMCDiagSections(void);
// Restart SpringBoard (Respring button, "OmniCar needs a respring" check).
void OMCRespring(void);

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
