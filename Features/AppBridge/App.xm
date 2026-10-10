#import "common.h"

// Phan cua App Bridge chay TRONG app nguoi dung (dylib nap vao moi process UIKit, xem Filter.plist). Chi lam mot viec:
// khi SpringBoard dang host app nay tren man xe, ep cua so cua app xoay theo huong cua o (AB_NOTIF_ORIENTATION), vi app ma
// giao dien chinh chi ho tro doc (YouTube, TikTok) se ve doc trong o ngang -> bi xoay 90 do. Theo carplay-cast (UIApplication.xm).
// Khong host nua (-1) thi thoi ep, app ve lai binh thuong tren iPhone.

static long long sForcedOrientation = -1;   // UIInterfaceOrientation dang ep, -1 = khong ep

static void ABApplyForcedOrientation(void)
{
    if (sForcedOrientation <= 0) return;
    UIWindow *key = nil, *any = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (!any) any = w;
            if (w.isKeyWindow) { key = w; break; }
        }
        if (key) break;
    }
    if (!key) key = any;
    SEL sel = NSSelectorFromString(@"_setRotatableViewOrientation:duration:force:");
    if (key && [key respondsToSelector:sel])
        ((void (*)(id, SEL, long long, double, BOOL))objc_msgSend)(key, sel, sForcedOrientation, 0.0, YES);
}

%group APPS

// UIKit sap xoay cua so (app tu xin, hay thiet bi xoay): dang ep thi luon xoay theo huong cua o
%hook UIWindow

- (void)_setRotatableViewOrientation:(long long)orientation duration:(double)duration force:(BOOL)force
{
    long long want = sForcedOrientation;
    if (want > 0 && orientation != want) {
        %orig(want, duration, force);
    } else {
        %orig;
    }
}

%end

%end // APPS

%ctor
{
    NSBundle *mb = [NSBundle mainBundle];
    NSString *bid = mb.bundleIdentifier;
    // Chi app nguoi dung (va app Apple trong AB_APPLE_PHONE_APPS); khong dong vao SpringBoard / CarPlay / daemon
    if (!bid.length || ![mb.bundlePath containsString:@".app"]) return;
    if ([bid hasPrefix:@"com.apple."] && ![AB_APPLE_PHONE_APPS containsObject:bid]) return;
    %init(APPS);
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:AB_NOTIF_ORIENTATION object:bid queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        long long o = [note.userInfo[@"orientation"] longLongValue];
        sForcedOrientation = (o > 0) ? o : -1;
        ABLog("%@: ep huong %lld", bid, sForcedOrientation);
        ABApplyForcedOrientation();
    }];
}
