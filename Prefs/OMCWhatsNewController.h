// "What's new" page (ROADMAP-DEV.md: Có gì mới): after an update, shown once over Settings > OmniCar; Support >
// "What's new" opens it any time. Content: Resources/WhatsNew.plist {version: [{symbol, titleKey, textKey}]},
// strings in <lang>.lproj/Backup.strings (WN_*). The pref "whatsNewSeen" holds the version last shown.
#import <UIKit/UIKit.h>

@interface OMCWhatsNewController : UIViewController
// YES when the installed version has an entry in WhatsNew.plist and it has not been shown yet.
+ (BOOL)shouldShow;
// Remember the installed version as seen (also used on a fresh install, where the first-run guide shows instead).
+ (void)markSeen;
// The page inside its own navigation controller, ready to present as a sheet; marks the version as seen.
+ (UINavigationController *)whatsNewNavigationController;
@end
