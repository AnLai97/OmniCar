#import "common.h"
#import "OMCTest.h"
#import <notify.h>

// Phan cua App Bridge chay TRONG app (dylib nap vao moi process UIKit, xem Filter.plist). Port tu CarDuo 1.0
// (src/hooks/UIApplication.xm), bo thiet ke da chay duoc YouTube tren xe:
//  - SpringBoard gui huong GOC cua o (AB_NOTIF_ORIENTATION: orientation, mac dinh doc) + huong "thiet bi" gia (device).
//    App chi bi xoay ve huong do khi no CON CHO PHEP huong do; app chi cho ngang (video fullscreen) thi de UIKit theo app.
//  - App xin huong khac (YouTube fullscreen: requestGeometryUpdateWithPreferences:, setOrientation:, doi mask
//    supportedInterfaceOrientations) -> bao SpringBoard qua Darwin notify + state (AB_DARWIN_APP_ORIENT), SpringBoard
//    doi huong scene cho app. Huong "thiet bi" gia + su kien xoay gia de YouTube bam fullscreen thi xin ngang that.
//  - -1 = khong host nua: thoi moi can thiep.

static int orientationOverride = -1;        // huong goc cua o SpringBoard gui, -1 = khong host
static int fpsCap = 0;                      // khung hinh / giay toi da khi tren xe (SpringBoard gui, AB_KEY_FPS), 0 = khong gioi han
static long long appWantsOrientation = 0;   // huong app TU XIN (fullscreen video -> ngang); 0 = theo huong cua o
static int fakeDeviceOrientation = 0;       // huong "thiet bi" gia (SpringBoard gui), 0 = dung huong that
// iOS 15 (nhom APPS15): khong co requestGeometryUpdate / setNeedsUpdateOfSupportedInterfaceOrientations, nen SpringBoard
// chi biet app doi huong qua hook UIDevice setOrientation va luc ep xoay bi bo qua. Co nay bat cac duong bao rieng cho iOS 15;
// iOS 16 giu nguyen (log 19/10 17:45 va 21:59, 7 Plus 15.8.4 + iPhone 8 15.6: YouTube ve xoay 90 do / video thu vao 1 goc
// vi trinh phat chi cho ngang ma scene van doc; cam bien doc / nam ngua lam scene lac 0.3 s mot lan).
static BOOL abLegacyRotation = NO;
static BOOL abToldLandscape = NO;           // iOS 15: da bao SpringBoard "app chi cho ngang" -> khi app cho doc lai thi bao lai
static NSUInteger ABAppEffectiveMask(void);

// Phat su kien "thiet bi vua xoay" (gia) sau `delay` giay
static void ABPostFakeDeviceRotation(double delay)
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (fakeDeviceOrientation <= 0) return;
        NSUInteger m = ABAppEffectiveMask();
        if (!(m & UIInterfaceOrientationMaskPortrait)) { ABLog("bo qua su kien xoay gia: app dang chi cho mask %lu", (unsigned long)m); return; }
        [[NSNotificationCenter defaultCenter] postNotificationName:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
    });
}

static long long ABEffectiveOrientation(void)
{
    return appWantsOrientation > 0 ? appWantsOrientation : orientationOverride;
}

// Mask huong ma cua so DANG cho phep: VC tren cung cua chuoi present
static NSUInteger ABWindowMask(UIWindow *w)
{
    UIViewController *vc = w.rootViewController;
    if (!vc) return UIInterfaceOrientationMaskAll;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    NSUInteger mask = vc.supportedInterfaceOrientations;
    return mask ? mask : UIInterfaceOrientationMaskAll;
}

// Duyet cay VC (con + presented) dang hien: co VC nao chi cho NGANG -> tra mask do (YouTube fullscreen: VC goc van
// tra "doc", nhung VC con fullscreen tra "ngang")
static NSUInteger ABLandscapeOnlyMaskInTree(UIViewController *vc, int depth)
{
    if (!vc || depth > 12) return 0;
    if (vc.isViewLoaded && vc.view.window && !vc.view.hidden) {
        NSUInteger m = vc.supportedInterfaceOrientations;
        if (m && !(m & UIInterfaceOrientationMaskPortrait) && (m & UIInterfaceOrientationMaskLandscape)) return m;
    }
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        NSUInteger m = ABLandscapeOnlyMaskInTree(vc.presentedViewController, depth + 1);
        if (m) return m;
    }
    for (UIViewController *c in vc.childViewControllers) {
        NSUInteger m = ABLandscapeOnlyMaskInTree(c, depth + 1);
        if (m) return m;
    }
    return 0;
}

static UIWindow *ABBestWindow(void)
{
    UIWindow *best = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) {
            if (!w.rootViewController || w.hidden) continue;
            if (w.isKeyWindow) { best = w; break; }
            if (!best) best = w;
        }
        if (best && best.isKeyWindow) break;
    }
    return best;
}

// Mask hieu luc cua ca app: uu tien VC chi-cho-ngang dang hien, khong thi VC tren cung cua cua so key
static NSUInteger ABAppEffectiveMask(void)
{
    UIWindow *best = ABBestWindow();
    if (!best) return UIInterfaceOrientationMaskAll;
    NSUInteger landscapeOnly = ABLandscapeOnlyMaskInTree(best.rootViewController, 0);
    if (landscapeOnly) return landscapeOnly;
    return ABWindowMask(best);
}

// Bao SpringBoard (Darwin notify + state): app vua doi yeu cau xoay. Gom cac lan goi lien tiep, gui mask cuoi sau 0.25s
static void ABTellSpringBoardNow(long long o)
{
    static int token = 0;
    if (!token) notify_register_check(AB_DARWIN_APP_ORIENT, &token);
    NSUInteger mask = ABAppEffectiveMask();
    uint64_t state = (ABBundleHash([[NSBundle mainBundle] bundleIdentifier]) << 24) | (((uint64_t)mask & 0xFFFF) << 8) | ((uint64_t)o & 0xFF);
    notify_set_state(token, state);
    notify_post(AB_DARWIN_APP_ORIENT);
    ABLog("bao SpringBoard: ma %lld, mask %lu", o, (unsigned long)mask);
}

static void ABTellSpringBoard(long long o)
{
    static dispatch_block_t pending = nil;
    if (pending) { dispatch_block_cancel(pending); pending = nil; }
    pending = dispatch_block_create((dispatch_block_flags_t)0, ^{
        pending = nil;
        ABTellSpringBoardNow(o);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), pending);
}

// Mask app xin -> 1 huong cu the. Co doc thi coi nhu "tra ve binh thuong" (0)
static long long ABOrientationFromMask(NSUInteger mask)
{
    if (mask & UIInterfaceOrientationMaskPortrait) return 0;
    if (mask & UIInterfaceOrientationMaskLandscapeLeft)  return UIInterfaceOrientationLandscapeLeft;
    if (mask & UIInterfaceOrientationMaskLandscapeRight) return UIInterfaceOrientationLandscapeRight;
    if (mask & UIInterfaceOrientationMaskPortraitUpsideDown) return UIInterfaceOrientationPortraitUpsideDown;
    return 0;
}

// ---- Ban phim tren man xe (AB_DARWIN_APP_KEYBOARD / AB_NOTIF_KEY, ve o SpringBoard: ABKeyboard.mm) ----
// O nhap dang duoc chon trong luc app nam tren xe; ban phim iPhone bi thay bang inputView rong (danh dau de tra lai khi
// o mat chon / app roi xe, iPhone lai co ban phim binh thuong)
static __weak UIResponder *abField;
static char kABEmptyInputKey;

static BOOL ABHosted(void) { return orientationOverride > 0; }

static void ABTellKeyboard(BOOL show, UIResponder *field)
{
    static int token = 0;
    if (!token) notify_register_check(AB_DARWIN_APP_KEYBOARD, &token);
    uint64_t flags = show ? 1 : 0;
    id<UITextInputTraits> traits = (id<UITextInputTraits>)field;
    if (show && [field respondsToSelector:@selector(keyboardType)]) flags |= ((uint64_t)traits.keyboardType & 0x7F) << 1;
    if (show && [field respondsToSelector:@selector(returnKeyType)]) flags |= ((uint64_t)traits.returnKeyType & 0xFF) << 8;
    notify_set_state(token, (ABBundleHash([[NSBundle mainBundle] bundleIdentifier]) << 24) | flags);
    notify_post(AB_DARWIN_APP_KEYBOARD);
    ABLog("ban phim xe: %@ (%@)", show ? @"hien" : @"an", field ? NSStringFromClass([field class]) : @"-");
}

// Truoc becomeFirstResponder: dang tren xe -> khong hien ban phim iPhone
static void ABPrepareField(UIResponder *field)
{
    if (!ABHosted() || ![field respondsToSelector:@selector(setInputView:)] || [(id)field inputView]) return;
    [(id)field setInputView:[[UIView alloc] initWithFrame:CGRectZero]];
    objc_setAssociatedObject(field, &kABEmptyInputKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ABFieldFocused(UIResponder *field)
{
    if (!ABHosted()) return;
    abField = field;
    ABTellKeyboard(YES, field);
}

static void ABFieldResigned(UIResponder *field)
{
    if (objc_getAssociatedObject(field, &kABEmptyInputKey)) {
        objc_setAssociatedObject(field, &kABEmptyInputKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [(id)field setInputView:nil];
    }
    if (abField != field) return;
    abField = nil;
    ABTellKeyboard(NO, nil);
}

// Phim tu SpringBoard: type (xoa del ky tu roi chen text: Telex sua lai chu dang go) | return | dismiss
static void ABHandleKey(NSDictionary *info)
{
    UIResponder<UIKeyInput> *f = (UIResponder<UIKeyInput> *)abField;
    if (!f || !f.isFirstResponder || ![f conformsToProtocol:@protocol(UIKeyInput)]) return;
    NSString *action = info[@"action"];
    if ([action isEqualToString:@"type"]) {
        for (int i = [info[@"del"] intValue]; i > 0; i--) [f deleteBackward];
        NSString *text = info[@"text"];
        if ([text isKindOfClass:[NSString class]] && text.length) [f insertText:text];
    } else if ([action isEqualToString:@"return"]) {
        if ([f isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)f;
            id<UITextFieldDelegate> d = tf.delegate;
            BOOL go = ![d respondsToSelector:@selector(textFieldShouldReturn:)] || [d textFieldShouldReturn:tf];
            if (go) [tf sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
        } else {
            [f insertText:@"\n"];
        }
    } else if ([action isEqualToString:@"dismiss"]) {
        [f resignFirstResponder];
    }
}

// SpringBoard gui huong cua o
static void ABHandleOrientationRequest(NSDictionary *info)
{
    int newOverride = [info[@"orientation"] intValue];
    if (newOverride <= 0 && abField) [abField resignFirstResponder];   // roi xe: tra ban phim iPhone
    BOOL changed = (newOverride != orientationOverride);
    orientationOverride = newOverride;
    appWantsOrientation = 0;
    fakeDeviceOrientation = (orientationOverride > 0) ? [info[@"device"] intValue] : 0;
    ABLog("huong o %d, thiet bi gia %d (doi=%d)", orientationOverride, fakeDeviceOrientation, (int)changed);
    if (!changed) return;   // khong doi -> khong ep xoay, khong phat su kien xoay (tranh YouTube tu vao/ra fullscreen)
    // YouTube chi xin ngang khi bam fullscreen neu truoc do DA nhan 1 su kien xoay thiet bi. Phat vai lan sau khi app len
    if (fakeDeviceOrientation > 0) for (NSNumber *d in @[@0.3, @1.5, @4.0]) ABPostFakeDeviceRotation(d.doubleValue);

    int o = orientationOverride;
    if (o == -1) o = MAX(1, (int)[[UIDevice currentDevice] orientation]);
    // Khong ep sang huong app dang khong cho phep (vd fullscreen video chi ngang)
    NSUInteger mask = ABAppEffectiveMask();
    if (o > 0 && !(mask & (1u << o))) {
        ABLog("bo qua ep xoay %d: app chi cho mask %lu", o, (unsigned long)mask);
        // iOS 15: app chi cho ngang (YouTube dang o trinh phat toan man) ma khong co API nao bao SpringBoard -> bao ngay
        // de scene xoay ngang va doi khung theo (iOS 16 lam viec nay qua setNeedsUpdateOfSupportedInterfaceOrientations)
        if (abLegacyRotation && !(mask & UIInterfaceOrientationMaskPortrait)) { ABTellSpringBoard(0xFF); abToldLandscape = YES; }
        return;
    }
    UIWindow *key = ABBestWindow();
    SEL sel = NSSelectorFromString(@"_setRotatableViewOrientation:duration:force:");
    if (key && [key respondsToSelector:sel]) ((void (*)(id, SEL, long long, double, BOOL))objc_msgSend)(key, sel, (long long)o, 0.0, YES);
}

// Gioi han khung hinh: nho gia tri app tu dat cho moi CADisplayLink (hoat anh, cuon, game), dat lai = min(app, fpsCap);
// fpsCap = 0 tra lai dung gia tri cua app. Video phat theo khung hinh cua video, khong bi anh huong.
static char kABWantFps, kABWantRange;
static BOOL fpsApplying;

static NSHashTable<CADisplayLink *> *ABDisplayLinks(void)
{
    static NSHashTable *t;
    if (!t) t = [NSHashTable weakObjectsHashTable];
    return t;
}

static void ABCapLink(CADisplayLink *l)
{
    fpsApplying = YES;
    NSArray<NSNumber *> *range = objc_getAssociatedObject(l, &kABWantRange);
    if (range.count == 3) {
        float mn = range[0].floatValue, mx = range[1].floatValue, pr = range[2].floatValue;
        if (fpsCap > 0) {
            mx = mx > 0 ? MIN(mx, (float)fpsCap) : fpsCap;
            pr = pr > 0 ? MIN(pr, mx) : 0;
            mn = MIN(mn, mx);
        }
        l.preferredFrameRateRange = CAFrameRateRangeMake(mn, mx, pr);
    } else {
        NSInteger f = [objc_getAssociatedObject(l, &kABWantFps) integerValue];
        if (fpsCap > 0) f = f > 0 ? MIN(f, (NSInteger)fpsCap) : fpsCap;
        l.preferredFramesPerSecond = f;
    }
    fpsApplying = NO;
}

static void ABSetFpsCap(int fps)
{
    if (fps == fpsCap) return;
    fpsCap = fps;
    for (CADisplayLink *l in ABDisplayLinks().allObjects) ABCapLink(l);
    ABLog("gioi han khung hinh: %d", fps);
}


#if OMC_AUTOTEST
// ---- Tu kiem tra (Core/OMCTest.h): cham TRONG app theo lenh cua process CarPlay (OMC_NOTIF_AUTOTEST_TOUCH) ----
// App tu ve ngon tay va gui cham qua UIKit (OMCTestTouch*), roi tra loi bang Darwin notify + state
// (hash bundle << 24 | seq << 8 | bit ket qua OMC_AT_TOUCH_*). Khong lien quan toi viec app co duoc host hay khong:
// app CarPlay (Google Maps, GOFA) nhan cham vao cua so CarPlay cua no (target = car), app iPhone tren xe nhan vao cua so
// App Bridge dang hien (target = host).
static NSTimeInterval abScreenAppearedAt;   // luc VC chiem >= nua cua so vua hien (hook viewDidAppear, chi khi dang host)

static void ABAutoTestReply(NSUInteger seq, NSUInteger bits)
{
    static int token = 0;
    if (!token) notify_register_check(OMC_DARWIN_AUTOTEST_TOUCH, &token);
    notify_set_state(token, (ABBundleHash([[NSBundle mainBundle] bundleIdentifier]) << 24) | ((uint64_t)(seq & 0xFFFF) << 8) | (bits & 0xFF));
    notify_post(OMC_DARWIN_AUTOTEST_TOUCH);
    ABLog("tu kiem tra: tra loi seq %lu bit %lu", (unsigned long)seq, (unsigned long)bits);
}

// Cua so de cham: car = cua so tren man xe (scene khong phai man iPhone: CPWindow cua app CarPlay), host = cua so iPhone
// App Bridge dang hien
static UIWindow *ABAutoTestWindow(NSString *target)
{
    if ([target isEqualToString:@"car"]) {
        UIWindow *best = nil;
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]] || ((UIWindowScene *)sc).screen == [UIScreen mainScreen]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w.hidden || w.bounds.size.width < 50) continue;
                if (!best || w.bounds.size.width * w.bounds.size.height > best.bounds.size.width * best.bounds.size.height) best = w;
            }
        }
        return best;
    }
    return ABBestWindow();
}

// YouTube: view giong o video nhat trong cua so (nhan tro nang "play video" / "phat video" / "views" / "luot xem", hay lop
// co "Thumbnail" / "Video"), tron ven trong cua so, cao nhat man. nil = khong thay
static UIView *ABAutoTestFindVideo(UIView *v, CGRect win, UIView *best, int depth)
{
    if (depth > 40 || v.hidden || v.alpha < 0.05) return best;
    CGRect r = [v convertRect:v.bounds toView:nil];
    CGFloat area = r.size.width * r.size.height, winArea = win.size.width * win.size.height;
    if (area >= winArea * 0.04 && area <= winArea * 0.7 && CGRectContainsRect(CGRectInset(win, -2, -2), r) && CGRectGetMinY(r) > 40) {
        NSString *label = [v.accessibilityLabel lowercaseString] ?: @"";
        NSString *cls = NSStringFromClass(v.class);
        id node = [v respondsToSelector:NSSelectorFromString(@"asyncdisplaykit_node")] ? [v valueForKey:@"asyncdisplaykit_node"] : nil;
        if (node) cls = [cls stringByAppendingFormat:@"/%@", NSStringFromClass([node class])];
        BOOL video = [label containsString:@"play video"] || [label containsString:@"phát video"] || [label containsString:@"phat video"]
                  || [label containsString:@" views"] || [label containsString:@"lượt xem"]
                  || [cls containsString:@"Thumbnail"] || [cls containsString:@"VideoWithContext"] || [cls containsString:@"VideoCell"];
        if (video && (!best || CGRectGetMinY(r) < CGRectGetMinY([best convertRect:best.bounds toView:nil]))) best = v;
    }
    for (UIView *c in v.subviews) best = ABAutoTestFindVideo(c, win, best, depth + 1);
    return best;
}

static void ABAutoTestTouch(NSDictionary *info)
{
    NSUInteger seq = [info[@"seq"] unsignedIntegerValue];
    NSString *kind = info[@"kind"] ?: @"tap", *target = info[@"target"] ?: @"host";
    UIWindow *w = ABAutoTestWindow(target);
    if (!w) {
        ABLog("tu kiem tra: khong co cua so %@ de cham (%@)", target, kind);
        ABAutoTestReply(seq, OMC_AT_TOUCH_NOWINDOW);
        return;
    }
    CGRect b = w.bounds;
    CGPoint p = CGPointMake(b.size.width * [info[@"fx"] doubleValue], b.size.height * [info[@"fy"] doubleValue]);
    CGPoint p2 = CGPointMake(b.size.width * [info[@"fx2"] doubleValue], b.size.height * [info[@"fy2"] doubleValue]);
    NSString *found = @"";
    if ([info[@"find"] isEqualToString:@"video"]) {
        UIView *v = ABAutoTestFindVideo(w, b, nil, 0);
        if (v) {
            CGRect r = [v convertRect:v.bounds toView:nil];
            p = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
            found = [NSString stringWithFormat:@", o video %@ \"%@\" %@", NSStringFromClass(v.class), v.accessibilityLabel ?: @"", NSStringFromCGRect(r)];
        } else found = @", khong thay o video nao -> cham diem mac dinh";
    }
    ABLog("tu kiem tra: %@ tai %@ trong %@ %@ (%@)%@", kind, NSStringFromCGPoint(p), NSStringFromClass(w.class), NSStringFromCGRect(b), target, found);
    NSString *(^name)(UIView *) = ^NSString *(UIView *v) { return v ? NSStringFromClass(v.class) : @"khong view nao"; };
    if ([kind isEqualToString:@"finger"]) { OMCTestFingerTap(w, p, nil); return; }   // chi ngon tay: CarPlay tu lam viec con lai
    if ([kind isEqualToString:@"drag"]) {
        BOOL back = [info[@"back"] boolValue];
        OMCTestTouchDrag(w, p, p2, 0.7, ^(UIView *hit, BOOL gesture) {
            NSUInteger bits = (hit ? OMC_AT_TOUCH_HIT : 0) | (gesture ? OMC_AT_TOUCH_GESTURE : 0);
            ABLog("tu kiem tra: keo %@ -> %@ toi %@, gesture %d", NSStringFromCGPoint(p), NSStringFromCGPoint(p2), name(hit), gesture);
            if (!back) { ABAutoTestReply(seq, bits); return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                OMCTestTouchDrag(w, p2, p, 0.7, ^(UIView *hit2, BOOL gesture2) {
                    ABLog("tu kiem tra: keo ve toi %@, gesture %d", name(hit2), gesture2);
                    ABAutoTestReply(seq, bits | (hit2 ? OMC_AT_TOUCH_HIT : 0) | (gesture2 ? OMC_AT_TOUCH_GESTURE : 0));
                });
            });
        });
        return;
    }
    NSTimeInterval t0 = [[NSProcessInfo processInfo] systemUptime];
    UIView *before = [w hitTest:p withEvent:nil];
    OMCTestTouchTap(w, p, ^(UIView *hit, BOOL gesture) {
        // 3 s sau: man hinh co doi khong (VC lon vua hien, hay view khac tai diem do)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *after = [w hitTest:p withEvent:nil];
            BOOL changed = abScreenAppearedAt > t0 || (after && before && after.class != before.class);
            NSUInteger bits = (hit ? OMC_AT_TOUCH_HIT : 0) | (gesture ? OMC_AT_TOUCH_GESTURE : 0) | (changed ? OMC_AT_TOUCH_CHANGED : 0);
            ABLog("tu kiem tra: cham toi %@ (trong %@), gesture %d, man hinh %@ (truoc %@, sau %@)", name(hit), name(hit.superview), gesture,
                  changed ? @"da doi" : @"khong doi", name(before), name(after));
            ABAutoTestReply(seq, bits);
        });
    });
}
#endif

%group APPS

%hook CADisplayLink
+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel
{
    CADisplayLink *l = %orig;
    if (l) {
        [ABDisplayLinks() addObject:l];
        if (fpsCap > 0) ABCapLink(l);
    }
    return l;
}
- (void)setPreferredFramesPerSecond:(NSInteger)fps
{
    if (fpsApplying) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, &kABWantFps, @(fps), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kABWantRange, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fpsCap > 0) ABCapLink(self); else %orig;
}
- (void)setPreferredFrameRateRange:(CAFrameRateRange)r
{
    if (fpsApplying) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, &kABWantRange, @[@(r.minimum), @(r.maximum), @(r.preferred)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fpsCap > 0) ABCapLink(self); else %orig;
}
%end

%hook UIWindow

- (void)_setRotatableViewOrientation:(long long)orientation duration:(double)duration force:(BOOL)force
{
    long long target = ABEffectiveOrientation();
    NSUInteger mask = ABWindowMask(self);
    // Chi ep ve huong cua o khi app con cho phep huong do; app dang chi cho ngang (fullscreen video) -> theo app
    BOOL canForce = target > 0 && (mask & (1u << target)) != 0;
    if (canForce && orientation != target) {
        %orig(target, duration, force);
    } else {
        %orig;
        // iOS 15: UIKit tu xoay cua so sang huong app cho phep (khong phai huong o) -> SpringBoard phai xoay scene theo,
        // khong thi noi dung ve xoay 90 do trong o (log 19/10 17:45)
        if (abLegacyRotation && orientationOverride > 0) {
            // chi bao 1 lan (SpringBoard lay scene -> app bo cuc lai -> UIKit goi lai ham nay: khong duoc bao vong)
            if (!canForce && orientation != target && orientation > 0 && !abToldLandscape) { ABTellSpringBoard(0xFF); abToldLandscape = YES; }
            else if (canForce && abToldLandscape) { ABTellSpringBoard(0xFF); abToldLandscape = NO; }   // app cho doc lai -> ve huong o
        }
    }
}

// Dau vet cham khi dang tren xe (log 19/10 16:04: chia man thi khong nhan duoc video YouTube, log khong co dong nao ve
// cham trong o): moi lan dat tay / nhac tay / bi huy, ghi vi tri trong cua so, khung cua so va man hinh, view nhan cham.
// Khong co dong nao = cham chua toi app (SpringBoard / CarPlay giu, hay backboardd bo).
- (void)sendEvent:(UIEvent *)event
{
    if (orientationOverride > 0 && event.type == UIEventTypeTouches) {
        for (UITouch *t in event.allTouches) {
            NSString *phase = t.phase == UITouchPhaseBegan ? @"xuong" : t.phase == UITouchPhaseEnded ? @"len" : t.phase == UITouchPhaseCancelled ? @"huy" : nil;
            if (!phase) continue;
            UIView *v = t.view;
            ABLog("cham %@ tai %@ trong %@ %@ (key=%d, man %@, app state %ld) -> %@ trong %@",
                  phase, NSStringFromCGPoint([t locationInView:self]), NSStringFromClass(self.class), NSStringFromCGRect(self.bounds),
                  self.isKeyWindow, NSStringFromCGSize(self.screen.bounds.size), (long)[UIApplication sharedApplication].applicationState,
                  v ? NSStringFromClass(v.class) : @"khong view nao", v.superview ? NSStringFromClass(v.superview.class) : @"-");
        }
    }
    %orig;
}

%end

// Dau vet man hinh: VC chiem >= nua cua so vua hien (trang xem video cua YouTube co mo sau khi cham hay khong)
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated
{
    %orig;
    if (orientationOverride <= 0 || !self.isViewLoaded) return;
    UIWindow *w = self.view.window;
    if (!w) return;
    CGRect r = [self.view convertRect:self.view.bounds toView:w];
    CGFloat area = w.bounds.size.width * w.bounds.size.height;
    if (area <= 0 || r.size.width * r.size.height < area * 0.5) return;
    ABLog("man hinh %@ hien: %@ trong cua so %@", NSStringFromClass(self.class), NSStringFromCGRect(r), NSStringFromCGRect(w.bounds));
#if OMC_AUTOTEST
    abScreenAppearedAt = [[NSProcessInfo processInfo] systemUptime];
#endif
}

%end

// App cu: ep xoay bang [UIDevice setOrientation:]; app hoi huong thiet bi -> tra loi theo huong dang ap
%hook UIDevice

- (void)beginGeneratingDeviceOrientationNotifications
{
    %orig;
    if (fakeDeviceOrientation > 0) ABPostFakeDeviceRotation(0.2);
}

- (void)setOrientation:(long long)orientation animated:(BOOL)animated
{
    if (orientationOverride > 0) {
        long long want = (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) ? orientation : 0;
        BOOL skip = NO;
        if (abLegacyRotation) {
            // iOS 15: UIKit goi ham nay cho moi lan cam bien doi (1 doc, 5 nam ngua, 6 up, 0 khong ro), khong chi khi app ep xoay.
            // Chi bao SpringBoard khi huong app muon thuc su doi; gia tri khong phai doc / ngang bo qua (log 19/10 17:45:
            // 14 cap 1 / 5 trong 6 s tu cam bien lam scene lac lien tuc)
            // (mot %orig duy nhat o cuoi: Logos khong dich duoc "%orig; return;" nam trong ngoac con)
            BOOL interface = orientation >= UIDeviceOrientationPortrait && orientation <= UIDeviceOrientationLandscapeRight;
            if (!interface) skip = YES;
            else if (want == appWantsOrientation) {
                // App roi trinh phat toan man (cho doc lai) ma khong gui tin nao khac -> bao lai theo mask hien tai
                if (abToldLandscape && (ABAppEffectiveMask() & UIInterfaceOrientationMaskPortrait)) { ABTellSpringBoard(0xFF); abToldLandscape = NO; }
                skip = YES;
            }
        }
        if (!skip) {
            appWantsOrientation = want;
            ABLog("app setOrientation %lld -> %lld", orientation, appWantsOrientation);
            ABTellSpringBoard(appWantsOrientation);
        }
    }
    %orig;
}

- (long long)orientation
{
    if (appWantsOrientation > 0) return appWantsOrientation;   // gia tri so trung nhau giua UIInterface / UIDeviceOrientation
    if (fakeDeviceOrientation > 0) return fakeDeviceOrientation;
    return %orig;
}

%end

// O nhap trong app tren xe: ban phim ve tren man xe thay cho ban phim iPhone
%hook UITextField
- (BOOL)becomeFirstResponder
{
    ABPrepareField(self);
    BOOL ok = %orig;
    if (ok) ABFieldFocused(self);
    return ok;
}
- (BOOL)resignFirstResponder
{
    BOOL ok = %orig;
    if (ok) ABFieldResigned(self);
    return ok;
}
%end

%hook UITextView
- (BOOL)becomeFirstResponder
{
    if (self.editable) ABPrepareField(self);
    BOOL ok = %orig;
    if (ok && self.editable) ABFieldFocused(self);
    return ok;
}
- (BOOL)resignFirstResponder
{
    BOOL ok = %orig;
    if (ok) ABFieldResigned(self);
    return ok;
}
%end

%end // APPS

// iOS 16+ only (iOS 15 has neither method; YouTube there rotates through [UIDevice setOrientation:]),
// installed only when the method exists.
%group APPS16

// iOS 16: app xin xoay bang requestGeometryUpdateWithPreferences: (YouTube fullscreen)
%hook UIWindowScene

- (void)requestGeometryUpdateWithPreferences:(id)prefs errorHandler:(id)handler
{
    if (orientationOverride > 0 && [prefs respondsToSelector:@selector(interfaceOrientations)]) {
        NSUInteger mask = ((NSUInteger (*)(id, SEL))objc_msgSend)(prefs, @selector(interfaceOrientations));
        appWantsOrientation = ABOrientationFromMask(mask);
        ABLog("app xin huong mask=%lu -> %lld", (unsigned long)mask, appWantsOrientation);
        ABTellSpringBoard(appWantsOrientation);
    }
    %orig;
}

%end

// App doi danh sach huong ho tro (iOS 16) -> SpringBoard lay lai scene
%hook UIViewController

- (void)setNeedsUpdateOfSupportedInterfaceOrientations
{
    %orig;
    if (orientationOverride > 0) ABTellSpringBoard(0xFF);
}

%end

%end // APPS16

// iOS 15: the same signal before setNeedsUpdateOfSupportedInterfaceOrientations existed
%group APPS15

%hook UIViewController

+ (void)attemptRotationToDeviceOrientation
{
    %orig;
    if (orientationOverride > 0) ABTellSpringBoard(0xFF);
}

%end

%end // APPS15

%ctor
{
    NSBundle *mb = [NSBundle mainBundle];
    NSString *bid = mb.bundleIdentifier;
    // Moi app co the duoc chon (app nguoi dung lan app he thong); khong dong vao SpringBoard / CarPlay / daemon
    if (!bid.length || ![mb.bundlePath containsString:@".app"]) return;
    if ([@[@"com.apple.springboard", @"com.apple.CarPlayApp", @"com.apple.CarPlayTemplateUIHost", @"com.apple.CarPlaySettings",
           @"com.apple.InCallService", @"com.apple.Preferences"] containsObject:bid]) return;
    // Hooks only once SpringBoard hosts this app on the car (its first orientation message): every hook above acts only
    // while orientationOverride / fakeDeviceOrientation are set, which only that message does, so an app that is never
    // put on the car screen (nearly all of them) runs without any OmniCar hook, just this observer.
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:AB_NOTIF_ORIENTATION object:bid queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        static BOOL hooked;
        if (!hooked) {
            hooked = YES;
            %init(APPS);
            if (OMCHasMethod("UIWindowScene", @"requestGeometryUpdateWithPreferences:errorHandler:")) %init(APPS16);
            else { %init(APPS15); abLegacyRotation = YES; }
            ABLog("%@: dua len xe, cai hook", bid);
        }
        @try { ABHandleOrientationRequest(note.userInfo); } @catch (NSException *e) { ABLog("%@: xoay loi %@", bid, e); }
        ABSetFpsCap([note.userInfo[@"orientation"] intValue] > 0 ? [note.userInfo[@"fps"] intValue] : 0);
    }];
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:AB_NOTIF_KEY object:bid queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        @try { ABHandleKey(note.userInfo); } @catch (NSException *e) { ABLog("%@: phim loi %@", bid, e); }
    }];
#if OMC_AUTOTEST
    // Tu kiem tra: process CarPlay nho app cham vao chinh no (cua so CarPlay hay cua so App Bridge)
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
        addObserverForName:OMC_NOTIF_AUTOTEST_TOUCH object:bid queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        @try { ABAutoTestTouch(note.userInfo); }
        @catch (NSException *e) { ABLog("%@: cham tu kiem tra loi %@", bid, e); ABAutoTestReply([note.userInfo[@"seq"] unsignedIntegerValue], 0); }
    }];
#endif
}
