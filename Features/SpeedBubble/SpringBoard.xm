#import "common.h"
#import "SPPBubble.h"
#import "SPPPrefs.h"
#import <notify.h>

// Inject vao SpringBoard: nhan toc do tu app dan duong (Vietmap / GOFA) -> ve bong bong; nhan lenh tu Cai dat
%group SPRINGBOARD

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)app
{
    %orig;
    SPPLog("SpringBoard ready");

    int tokSpeed = 0, tokDemo = 0, tokPrefs = 0, tokReset = 0;
    // App dan duong gui toc do + gioi han (kem chi so app); app bi tat trong Cai dat -> bo qua
    notify_register_dispatch(SPP_DARWIN_SPEED, &tokSpeed, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0; notify_get_state(t, &state);
        int flags = (int)((state >> 16) & 0xFF), speed = (int)((state >> 8) & 0xFF), limit = (int)(state & 0xFF);
        int app = (flags >> 3) & 7;
        if (![SPPPrefs appEnabled:app]) return;
        [[SPPBubble shared] updateSpeed:((flags & 1) ? speed : -1) limit:((flags & 2) ? limit : -1)
                          appForeground:(flags & 4) != 0 app:app];
    });
    notify_register_dispatch(SPP_DARWIN_DEMO, &tokDemo, dispatch_get_main_queue(), ^(int t) { [[SPPBubble shared] runDemo]; });
    notify_register_dispatch(SPP_DARWIN_RESET, &tokReset, dispatch_get_main_queue(), ^(int t) { [[SPPBubble shared] resetLayout]; });
    // Doi kieu / bat tat trong Cai dat -> ve lai ngay
    notify_register_dispatch(SPP_DARWIN_PREFS, &tokPrefs, dispatch_get_main_queue(), ^(int t) { [[SPPBubble shared] refresh]; });

    // Xe ket noi / ngat: bong bong chuyen cua so giua man xe va iPhone
    [[NSNotificationCenter defaultCenter] addObserverForName:@"CarPlayIsConnectedDidChange" object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [[SPPBubble shared] refresh];
    }];
}

%end

%end // SPRINGBOARD

%ctor
{
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
    SPPLog("loaded into SpringBoard");
    %init(SPRINGBOARD);
}
