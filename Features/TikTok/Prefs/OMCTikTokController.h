#import "OMCFeatureListController.h"

// TikTok settings page (Resources/FeatureTikTok.plist). Every switch also goes into the
// notification state TikTok reads (see ../TikTok.h), since TikTok can't read the prefs plist.
@interface OMCTikTokController : OMCFeatureListController
@end
