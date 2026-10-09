#import <Preferences/PSListController.h>

// One settings page per feature. The row in Root.plist that opens it is a PSLinkCell with
// detail = OMCFeatureListController and a "plist" property naming Resources/<plist>.plist,
// which follows the same rules as Root.plist. See FeatureTemplate.plist for a starting point.
@interface OMCFeatureListController : PSListController
// Simple alert titled "OmniCar" with an OK button, for feature-page actions.
- (void)showMessage:(NSString *)message;
@end
