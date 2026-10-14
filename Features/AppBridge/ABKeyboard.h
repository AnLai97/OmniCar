#import <UIKit/UIKit.h>

// Keyboard on the car screen for iPhone apps hosted by App Bridge (their text fields have no keyboard there). App.xm
// reports the focused field (AB_DARWIN_APP_KEYBOARD), SpringBoard shows this keyboard in its own window over the car
// screen and sends every key back to the app (AB_NOTIF_KEY). English QWERTY + Vietnamese Telex, numbers / symbols page.
@interface ABKeyboard : NSObject
+ (instancetype)shared;
// keyboardType / returnKeyType: the field's UIKeyboardType / UIReturnKeyType (number pads open on the numbers page)
- (void)showForApp:(NSString *)bid keyboardType:(NSInteger)type returnType:(NSInteger)ret;
- (void)hideForApp:(NSString *)bid;   // nil = whatever app it is showing for
- (NSString *)app;                    // app the keyboard is showing for, nil when hidden
- (void)key:(UIButton *)key pressed:(BOOL)down;   // letter key down / up: the enlarged-letter bubble above it
@end

#ifdef __cplusplus
extern "C" {
#endif
// Telex: `word` (the Vietnamese word typed so far) after typing `key` - tone marks (s f r x j, z clears), aa ee oo
// dd -> â ê ô đ, w -> ă ơ ư (uo + w -> ươ). Returns nil when the key is not a Telex edit (plain letter appended).
NSString *ABTelexApply(NSString *word, NSString *key);
#ifdef __cplusplus
}
#endif
