#import "OMCFeatureListController.h"

// Split Screen settings page (Resources/FeatureSplitScreen.plist): on/off, open on connect, dock panel
// sections, one row per favorite layout (OMCSplitFavCell) opening SplitScreenFav<n>.plist (name, layout,
// one app per box picked in OMCSplitScreenAppPicker.m), and a Guide page (SplitScreenGuide.plist).
@interface OMCSplitScreenController : OMCFeatureListController
@end
