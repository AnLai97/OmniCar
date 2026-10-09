// Shared look and localization for every OmniCar settings page (root + one page per feature).
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>

#define kPrefsDomain CFSTR("com.anlai.omnicar")
// Key the language choice is stored under.
#define kLanguageKey CFSTR("language")
// Enable switch key (same as the first switch in Root.plist); the header's status chip reads it.
#define kEnabledKey CFSTR("enabled")

#pragma mark - Localization

// The app language is picked in the nav bar, so strings come from <lang>.lproj by hand
// instead of following the system language.
NSArray<NSString *> *OMCLanguages(void);
NSString *OMCLanguageName(NSString *lang);
NSString *OMCLanguage(void);
void OMCLoadStrings(void);
NSString *L(NSString *key);

#pragma mark - HarmonyOS theme

UIColor *OMCAccentColor(void);
UIColor *OMCBackgroundColor(void);
UIColor *OMCCardColor(void);
UIColor *OMCColorFromHex(NSString *hex);
// Row icon: a white SF Symbol on a rounded, softly lit color tile.
UIImage *OMCIcon(NSString *symbol, UIColor *color);
BOOL OMCEnabled(void);

#pragma mark - Specifiers and cells

// Plists hold string keys; swap them for the chosen language and attach the row icons.
void OMCLocalizeSpecifiers(NSArray<PSSpecifier *> *specifiers);
// Card background, row font, and button rows (chevron, or red when "isDestructive").
void OMCStyleCell(UITableViewCell *cell);
// Section header / footer labels.
void OMCStyleHeaderFooter(UIView *view, BOOL isHeader);
