// First-run guide: four pages shown once over Settings > OmniCar (apps on the car screen, Split Screen,
// Speed Bubble, tips + where Support is). Support > "Show guide again" reopens it.
#import <UIKit/UIKit.h>

@interface OMCOnboardingController : UIViewController <UIScrollViewDelegate, UIAdaptivePresentationControllerDelegate>
// YES until the guide has been finished, skipped or swiped away once (pref "onboardingDone").
+ (BOOL)shouldShow;
// The guide inside its own navigation controller (the App Bridge chooser is pushed there), ready to present.
// completion runs once the sheet is gone (Skip, Done or swiped down), so the presenter can refresh its rows.
+ (UINavigationController *)guideNavigationControllerWithCompletion:(void (^)(void))completion;
@end
