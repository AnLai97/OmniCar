#import "SCPAutoTest.h"

#if OMC_AUTOTEST
#import "SCPCarSplit.h"
#import "SCPPrefs.h"
#import "SCPHomeScreen.h"
#import "SCPAppIcons.h"
#import "OMCTest.h"
#import <notify.h>

// Phan rieng cua SCPCarSplit (SCPCarSplit.mm) ma bai test goi / doc. Cung la ham nut bam tren xe goi.
@interface SCPCarSplit (SCPAutoTest)
- (NSMutableArray *)slots;
- (void)setFractions:(NSMutableArray *)fractions;
- (id)floatPane;
- (NSString *)soloHostedBundle;
- (NSNumber *)zoomedSlot;
- (UIView *)pickerSheet;
- (UIView *)tray;
- (UIView *)popupShield;   // lop nhin cham khi co bang mo (SCPCTouchWatch): hitTest ngoai bang -> dong het
- (UIView *)container;
- (NSMutableDictionary *)pending;
- (int)layoutID;
- (int)paneCount;
- (BOOL)vertical;
- (CGRect)frameForSlot:(int)slot;
- (void)relayoutAnimated:(BOOL)animated;
- (void)switchToLayout:(int)layoutID;
- (void)swapSlot:(int)a with:(int)b;
- (void)closeSlot:(int)slot background:(BOOL)background;
- (void)popOutPane:(id)pane;
- (BOOL)canPopOutPane:(id)pane;
- (NSString *)popOutBlockReason:(id)pane;
- (void)floatDockBack;
- (void)soloBundle:(NSString *)bid;
- (void)showLayoutPanelForApp:(NSString *)app;
- (void)collapseAppTray;
- (void)removePickerSheet;
- (void)openSetupLayout:(int)layoutID apps:(NSArray *)apps;
- (void)endHostedSolo;
- (NSArray *)favoriteApps:(NSDictionary *)favorite;
// Nut Split Screen tren dock CarPlay (tren nut Home)
- (UIButton *)homeButton;
- (UIView *)tabParent;
- (CGRect)appAreaInParent:(UIView *)parent;
- (CGRect)homeGlyph;
- (UIColor *)homeInk;
- (NSString *)launcherWhere;
- (BOOL)launcherBare;
- (void)refreshHomeButton;
- (void)setBarVisible:(BOOL)visible forPane:(id)pane;   // thanh nut cua o (cham "•••")
- (void)hideBarsForTouchOn:(UIView *)v;                   // cham vao view v (hitTest cua container): thanh nut dang mo o cho khac -> an ngay
@end

#define SCPATF OMCTestFormat
static NSMutableDictionary<NSString *, NSString *> *sBridgeStates;   // AB_NOTIF_STATE moi nhat cua tung app iPhone
static NSMutableDictionary<NSString *, NSDictionary *> *sTouchReplies;   // bundle -> {seq, bits}: app tra loi cham (OMC_DARWIN_AUTOTEST_TOUCH)
static NSMutableDictionary<NSString *, NSNumber *> *sTouchSeq;           // seq cua lan cham moi nhat gui cho app
static NSUInteger sTouchCounter;

// App uu tien (19/10/2026): mo app thi YouTube va Google Maps truoc, chia man thi YouTube | Google Maps | GOFA
#define SCPAT_GMAPS @"com.google.Maps"
#define SCPAT_GOFA  @"com.lumi.GOFA"
#define SCPAT_YT    @"com.google.ios.youtube"

#pragma mark - Doc trang thai CarPlay

static id SCPATDashboard(void)
{
    UIApplication *app = [UIApplication sharedApplication];
    return [app respondsToSelector:NSSelectorFromString(@"_currentDashboard")] ? objcInvoke(app, @"_currentDashboard") : nil;
}

static UIViewController *SCPATBaseVC(void)
{
    id d = SCPATDashboard();
    id root = d ? objcInvoke(d, @"rootViewController") : nil;
    return [root respondsToSelector:NSSelectorFromString(@"currentBaseViewController")] ? objcInvoke(root, @"currentBaseViewController") : nil;
}

static NSString *SCPATBaseBundle(void)
{
    UIViewController *vc = SCPATBaseVC();
    if (![vc respondsToSelector:NSSelectorFromString(@"applicationInfo")]) return nil;
    id proxy = [vc respondsToSelector:NSSelectorFromString(@"proxyApplicationInfo")] ? objcInvoke(vc, @"proxyApplicationInfo") : nil;
    return SCPRealBundleForInfos(objcInvoke(vc, @"applicationInfo"), proxy);
}

// Man xe da hien va DashBoard da dung xong man chinh
static BOOL SCPATCarReady(void)
{
    id d = SCPATDashboard();
    UIViewController *root = d ? objcInvoke(d, @"rootViewController") : nil;
    return root && root.view.window && [SCPPrefs enabled];
}

// Nhu nut Home cua CarPlay (DBEvent 1); dang chia / app iPhone toan man thi dong dung cach cua split truoc
static void SCPATHome(void)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    if (s.active) { [s closeGoingHome:YES]; return; }
    if ([s soloHostedBundle]) [s endHostedSolo];
    id d = SCPATDashboard();
    id ev = objcInvoke_2(OMCCarClass("DBEvent"), @"eventWithType:context:", (unsigned long long)1, @"OmniCar AutoTest");
    if (d && ev) objcCall_1(d, @"handleEvent:", ev);
}

// Lenh nhu tu SpringBoard (omnicar://splitscreen/..., Siri, Shortcuts): cung duong CarPlay.xm nhan
static void SCPATCommand(NSDictionary *info)
{
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:SPL_NOTIF_NATIVE object:nil userInfo:info];
}

static id SCPATPane(id pane, NSString *key)
{
    @try { return [pane valueForKey:key]; } @catch (NSException *e) { return nil; }
}

static BOOL SCPATIsHosted(UIViewController *vc) { return [NSStringFromClass([vc class]) isEqualToString:@"SCPHostedAppVC"]; }

static CGSize SCPATSceneSize(UIViewController *vc)
{
    id scene = [[SCPCarSplit shared] sceneOfViewController:vc];
    id st = [scene respondsToSelector:NSSelectorFromString(@"settings")] ? objcInvoke(scene, @"settings") : nil;
    if (![st respondsToSelector:NSSelectorFromString(@"frame")]) return CGSizeZero;
    return ((CGRect (*)(id, SEL))objc_msgSend)(st, NSSelectorFromString(@"frame")).size;
}

static NSString *SCPATShort(NSString *bid) { return bid ? [bid componentsSeparatedByString:@"."].lastObject : @"-"; }

static NSString *SCPATPaneBundle(int slot)
{
    NSArray *slots = [[SCPCarSplit shared] slots];
    return slot < (int)slots.count ? SCPATPane(slots[slot], @"bundleID") : nil;
}

// Trang thai split mot dong (log khi FAIL): o nao, app nao, khung nao, scene that bao nhieu
static NSString *SCPATState(void)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    NSMutableString *o = [NSMutableString stringWithFormat:@"active=%d", s.active];
    if (s.active) [o appendFormat:@" layout=%d panes=%d vertical=%d area=%@", [s layoutID], [s paneCount], [s vertical],
        NSStringFromCGRect([s container].frame)];
    [o appendFormat:@" solo=%@ base=%@", SCPATShort([s soloHostedBundle]), SCPATShort(SCPATBaseBundle())];
    if ([s pending].count) [o appendFormat:@" pending=%@", [[s pending].allKeys componentsJoinedByString:@","]];
    NSMutableArray *panes = [NSMutableArray arrayWithArray:s.active ? ([s slots] ?: @[]) : @[]];
    if ([s floatPane]) [panes addObject:[s floatPane]];
    for (id p in panes) {
        UIViewController *vc = SCPATPane(p, @"vc");
        NSString *bid = SCPATPane(p, @"bundleID");
        [o appendFormat:@" | o%@ %@ vc=%@ frame=%@", SCPATPane(p, @"slot"), SCPATShort(bid), vc ? NSStringFromClass([vc class]) : @"nil",
            NSStringFromCGRect(((UIView *)SCPATPane(p, @"view")).frame)];
        if (vc && !SCPATIsHosted(vc)) [o appendFormat:@" scene=%@", NSStringFromCGSize(SCPATSceneSize(vc))];
        if (vc && SCPATIsHosted(vc)) [o appendFormat:@" bridge=%@", sBridgeStates[bid] ?: @"?"];
        if (SCPATPane(p, @"loader")) [o appendString:@" loader"];
        if (SCPATPane(p, @"picker")) [o appendString:@" picker"];
    }
    if ([s pickerSheet]) [o appendString:@" | pickerSheet"];
    if ([s tray]) [o appendString:@" | tray"];
    return o;
}

// Ly do FAIL kem trang thai split (de sua khong can thu lai)
static NSString *SCPATWhy(NSString *why) { return why ? [NSString stringWithFormat:@"%@ || %@", why, SCPATState()] : nil; }

#pragma mark - Kiem tra

static int SCPATPanesFor(int layout) { return (layout == 13 || layout == 31) ? 3 : layout; }

// Split dung bo cuc, du o, dung app theo thu tu (NSNull / thieu = bat ky), khung trong vung app va khong chong nhau,
// scene that cua app CarPlay dung co o, app iPhone da bao "ready"
static NSString *SCPATExpectLayout(int layout, NSArray *apps)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    if (!s.active) return SCPATWhy(@"split chua bat");
    if ([s layoutID] != layout) return SCPATWhy(SCPATF(@"bo cuc %d, can %d", [s layoutID], layout));
    if ([s paneCount] != SCPATPanesFor(layout)) return SCPATWhy(SCPATF(@"%d o, can %d", [s paneCount], SCPATPanesFor(layout)));
    if ([s pending].count) return SCPATWhy(SCPATF(@"con cho mo: %@", [[s pending].allKeys componentsJoinedByString:@", "]));
    CGRect area = CGRectInset([s container].bounds, -1, -1);
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    for (int i = 0; i < [s paneCount]; i++) {
        id p = [s slots][i];
        NSString *bid = SCPATPane(p, @"bundleID");
        UIViewController *vc = SCPATPane(p, @"vc");
        CGRect f = ((UIView *)SCPATPane(p, @"view")).frame;
        if (i < (int)apps.count && [apps[i] isKindOfClass:[NSString class]] && ![bid isEqualToString:apps[i]])
            return SCPATWhy(SCPATF(@"o %d la %@, can %@", i, bid, apps[i]));
        if (!vc) return SCPATWhy(SCPATF(@"o %d (%@) chua co app", i, bid));
        if (f.size.width < 40 || f.size.height < 40) return SCPATWhy(SCPATF(@"o %d qua nho", i));
        if (!CGRectContainsRect(area, f)) return SCPATWhy(SCPATF(@"o %d ra ngoai vung app", i));
        for (NSUInteger j = 0; j < frames.count; j++) {
            CGRect x = CGRectIntersection(f, frames[j].CGRectValue);
            if (!CGRectIsNull(x) && x.size.width > 2 && x.size.height > 2) return SCPATWhy(SCPATF(@"o %d chong len o %lu", i, (unsigned long)j));
        }
        [frames addObject:[NSValue valueWithCGRect:f]];
        if (SCPATIsHosted(vc)) {
            if (![sBridgeStates[bid] isEqualToString:@"ready"]) return SCPATWhy(SCPATF(@"App Bridge %@ chua hien (state=%@)", bid, sBridgeStates[bid] ?: @"chua bao"));
        } else {
            CGSize want = [s frameForSlot:i].size, cur = SCPATSceneSize(vc);
            BOOL ok = (fabs(cur.width - want.width) < 2 && fabs(cur.height - want.height) < 2)
                   || (fabs(cur.width - want.height) < 2 && fabs(cur.height - want.width) < 2);
            if (!ok) return SCPATWhy(SCPATF(@"scene o %d (%@) %@, o %@", i, bid, NSStringFromCGSize(cur), NSStringFromCGSize(want)));
        }
    }
    if ([s floatPane]) return SCPATWhy(@"con cua so noi");
    return nil;
}

static NSString *SCPATExpectRatio(CGFloat first)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    NSString *e = SCPATExpectLayout(2, nil);
    if (e) return e;
    CGRect a = [s frameForSlot:0], b = [s frameForSlot:1];
    CGFloat wa = [s vertical] ? a.size.height : a.size.width, wb = [s vertical] ? b.size.height : b.size.width;
    CGFloat r = wa / MAX((CGFloat)1, wa + wb);
    return fabs(r - first) < 0.04 ? nil : SCPATWhy(SCPATF(@"o 1 chiem %.2f, can %.2f", r, first));
}

static NSString *SCPATExpectHome(void)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    if (s.active) return SCPATWhy(@"split van bat");
    if ([s soloHostedBundle]) return SCPATWhy(SCPATF(@"app iPhone %@ van toan man", [s soloHostedBundle]));
    if ([s tray] || [s pickerSheet]) return SCPATWhy(@"bang bo cuc / chon app van mo");
    if (SCPATBaseVC()) return SCPATWhy(SCPATF(@"DashBoard van giu %@", NSStringFromClass([SCPATBaseVC() class])));
    return nil;
}

static NSString *SCPATExpectSolo(NSString *bid)
{
    if ([SCPCarSplit shared].active) return SCPATWhy(@"split van bat");
    NSString *base = SCPATBaseBundle();
    return [base isEqualToString:bid] ? nil : SCPATWhy(SCPATF(@"toan man la %@, can %@", base, bid));
}

// Nut "1 man hinh" (full) khi dang chia: phong to tam o cua app, split van bat (bam lai -> ve chia man)
static NSString *SCPATExpectZoomed(NSString *bid)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    if (!s.active) return SCPATWhy(@"split da tat (can giu split, chi phong to o)");
    NSNumber *z = [s zoomedSlot];
    if (!z) return SCPATWhy(@"khong co o nao phong to");
    NSString *zb = SCPATPaneBundle(z.intValue);
    if (![zb isEqualToString:bid]) return SCPATWhy(SCPATF(@"o phong to la %@, can %@", SCPATShort(zb), SCPATShort(bid)));
    CGSize area = [s container].bounds.size, got = ((UIView *)SCPATPane([s slots][z.intValue], @"view")).frame.size;
    if (fabs(area.width - got.width) > 2 || fabs(area.height - got.height) > 2)
        return SCPATWhy(SCPATF(@"o phong to %@, can phu ca vung app %@", NSStringFromCGSize(got), NSStringFromCGSize(area)));
    if (![sBridgeStates[bid] isEqualToString:@"ready"]) return SCPATWhy(SCPATF(@"App Bridge %@ chua hien (state=%@)", bid, sBridgeStates[bid] ?: @"chua bao"));
    return nil;
}

static NSString *SCPATExpectHostedSolo(NSString *bid)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    if (s.active) return SCPATWhy(@"split van bat");
    if (![[s soloHostedBundle] isEqualToString:bid]) return SCPATWhy(SCPATF(@"app iPhone toan man la %@, can %@", [s soloHostedBundle], bid));
    if (![sBridgeStates[bid] isEqualToString:@"ready"]) return SCPATWhy(SCPATF(@"App Bridge %@ chua hien (state=%@)", bid, sBridgeStates[bid] ?: @"chua bao"));
    return nil;
}

// Nut Split Screen tren dock CarPlay: dang hien; tren dai dock la hinh 2 o dac (anh template, khong o nen / bong) rong bang
// luoi app cua nut Home, nam sat ngay tren nut Home (cung truc giua), cung mau luoi Home, khong de len cum icon dock.
// Xe khong co dai dock (nut tron o goc vung app): chi can dang hien.
static NSString *SCPATExpectDockButton(void)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    UIButton *b = [s homeButton];
    UIView *parent = [s tabParent];
    if (!b || !b.superview || !b.window) return SCPATWhy(@"nut Split Screen khong co tren man xe");
    if (b.hidden || b.alpha < 0.9) return SCPATWhy(@"nut Split Screen bi an / mo");
    UIImage *img = [b imageForState:UIControlStateNormal];
    if (!img) return SCPATWhy(@"nut Split Screen khong co hinh");
    CGRect r = parent ? [parent convertRect:b.bounds fromView:b] : b.frame;
    if (![s launcherBare]) { OMCTestLog(@"nut Split Screen o %@ (khung %@)", [s launcherWhere] ?: @"?", NSStringFromCGRect(r)); return nil; }
    if (img.renderingMode != UIImageRenderingModeAlwaysTemplate) return SCPATWhy(@"hinh nut dock khong phai anh template (khong an mau nut Home)");
    if (b.backgroundColor && CGColorGetAlpha(b.backgroundColor.CGColor) > 0.05) return SCPATWhy(@"nut dock van co o nen");
    if (b.layer.shadowOpacity > 0.05) return SCPATWhy(@"nut dock van co bong");
    if (img.size.width < 8 || img.size.height < 4 || img.size.height > img.size.width) return SCPATWhy(SCPATF(@"hinh 2 o co %@ khong hop ly", NSStringFromCGSize(img.size)));
    CGRect home = [s homeGlyph];
    if (!CGRectIsNull(home) && home.size.width >= 8) {
        if (fabs(img.size.width - home.size.width) > 1) return SCPATWhy(SCPATF(@"hinh rong %.0f, luoi nut Home rong %.0f", img.size.width, home.size.width));
        if (fabs(CGRectGetMidX(r) - CGRectGetMidX(home)) > 2) return SCPATWhy(SCPATF(@"nut lech truc voi nut Home (%.0f, Home %.0f)", CGRectGetMidX(r), CGRectGetMidX(home)));
        if (CGRectGetMaxY(r) > CGRectGetMinY(home) + 1) return SCPATWhy(SCPATF(@"nut khong nam tren nut Home (day %.0f, dinh Home %.0f)", CGRectGetMaxY(r), CGRectGetMinY(home)));
        if (CGRectGetMinY(home) - CGRectGetMaxY(r) > 16) return SCPATWhy(SCPATF(@"nut cach nut Home %.0fpt, can sat", CGRectGetMinY(home) - CGRectGetMaxY(r)));
        UIColor *ink = [s homeInk];
        if (ink && ![b.tintColor isEqual:ink]) return SCPATWhy(@"mau nut khac mau luoi nut Home");
        // Mau theo giao dien dock: den khi sang, trang khi toi (ban dem)
        BOOL dark = b.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        CGFloat white = -1, alpha = 0;
        if (![[b.tintColor resolvedColorWithTraitCollection:b.traitCollection] getWhite:&white alpha:&alpha] || fabs(white - (dark ? 1 : 0)) > 0.1 || alpha < 0.95)
            return SCPATWhy(SCPATF(@"mau nut (trang %.2f) khong phai %@ nhu nut Home khi giao dien %@", white, dark ? @"trang" : @"den", dark ? @"toi" : @"sang"));
        OMCTestLog(@"nut Split Screen %@ hinh %@ tren nut Home %@", NSStringFromCGRect(r), NSStringFromCGSize(img.size), NSStringFromCGRect(home));
    } else OMCTestLog(@"khong do duoc luoi nut Home (%@), chi kiem tra nut dang hien", [s launcherWhere] ?: @"?");
    // Khong de len cum icon dock (cum icon da duoc day len neu khe hep)
    id d = SCPATDashboard();
    id root = d ? objcInvoke(d, @"rootViewController") : nil;
    id dockVC = root ? objcInvoke(root, @"appDockViewController") : nil;
    UIView *dock = dockVC ? objcInvoke(dockVC, @"view") : nil;
    if (parent && dock.window && parent.window) {
        CGRect cluster = [parent convertRect:dock.bounds fromView:dock];
        CGRect x = CGRectIntersection(r, cluster);
        if (!CGRectIsNull(x) && x.size.width > 2 && x.size.height > 2)
            return SCPATWhy(SCPATF(@"nut %@ de len cum icon dock %@", NSStringFromCGRect(r), NSStringFromCGRect(cluster)));
    }
    return nil;
}

#pragma mark - Ngon tay (OMCTestStepAt): diem tren man xe ma buoc cham vao

// p trong toa do cua v -> diem man xe (toa do man hinh), nil neu v khong tren man
static NSValue *SCPATScreenPoint(UIView *v, CGPoint p)
{
    if (!v || !v.window) return nil;
    return [NSValue valueWithCGPoint:[v.window convertPoint:[v convertPoint:p toView:nil] toWindow:nil]];
}

static NSValue *SCPATAtView(UIView *v) { return v ? SCPATScreenPoint(v, CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds))) : nil; }

// Nut Home cua CarPlay tren dock (luoi app)
static NSValue *SCPATAtHome(void)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    CGRect g = [s homeGlyph];
    if (![s tabParent] || CGRectIsNull(g) || g.size.width < 4) return nil;
    return SCPATScreenPoint([s tabParent], CGPointMake(CGRectGetMidX(g), CGRectGetMidY(g)));
}

static NSValue *SCPATAtDock(void) { return SCPATAtView([[SCPCarSplit shared] homeButton]); }   // nut Split Screen tren dock

// O slot: top = thanh "•••" o giua mep tren, khong thi giua o. (O app iPhone: cua so host cua SpringBoard che ngon tay nay,
// dung SCPATFingerThen de app tu ve.)
static NSValue *SCPATAtSlot(int slot, BOOL top)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    if (!s.active || slot >= [s paneCount]) return nil;
    UIView *v = SCPATPane([s slots][slot], @"view");
    return v ? SCPATScreenPoint(v, CGPointMake(CGRectGetMidX(v.bounds), top ? 14 : CGRectGetMidY(v.bounds))) : nil;
}

static NSValue *SCPATAtDivider(void)   // cham tron cua vach giua o 1 va o 2
{
    SCPCarSplit *s = [SCPCarSplit shared];
    if (!s.active || [s paneCount] < 2 || ![s container]) return nil;
    CGRect a = [s frameForSlot:0], b = [s frameForSlot:1];
    CGPoint p = [s vertical] ? CGPointMake(CGRectGetMidX(a), (CGRectGetMaxY(a) + CGRectGetMinY(b)) / 2)
                             : CGPointMake((CGRectGetMaxX(a) + CGRectGetMinX(b)) / 2, CGRectGetMidY(a));
    return SCPATScreenPoint([s container], p);
}

static NSValue *SCPATAtFloat(void) { return SCPATAtView(SCPATPane([[SCPCarSplit shared] floatPane], @"view")); }

#pragma mark - Cham trong app (Core/OMCTest.h, Features/AppBridge/App.xm)
// Process CarPlay khong cham duoc vao app (app CarPlay nhan cham thang tu backboardd, app iPhone nam trong cua so host cua
// SpringBoard), nen nho app tu cham: gui OMC_NOTIF_AUTOTEST_TOUCH, app ve ngon tay, gui cham qua UIKit cua no, tra loi
// bang Darwin notify (bit OMC_AT_TOUCH_*).

static void SCPATPostTouch(NSString *bid, NSDictionary *params)
{
    NSMutableDictionary *info = [params mutableCopy];
    info[@"seq"] = @(++sTouchCounter);
    sTouchSeq[bid] = info[@"seq"];
    [sTouchReplies removeObjectForKey:bid];
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:OMC_NOTIF_AUTOTEST_TOUCH object:bid userInfo:info];
}

// Chi ngon tay (khong cham) trong app iPhone dang hien tren xe, roi `then` sau 1 s: buoc tren o app iPhone (thanh nut, doi
// cho, cua so noi ...) ve ngon tay trong app vi cua so host cua SpringBoard che ngon tay cua process CarPlay
static NSString *SCPATFingerThen(NSString *bid, CGFloat fx, CGFloat fy, dispatch_block_t then)
{
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] postNotificationName:OMC_NOTIF_AUTOTEST_TOUCH object:bid
        userInfo:@{@"kind": @"finger", @"target": @"host", @"fx": @(fx), @"fy": @(fy)}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try { then(); } @catch (NSException *e) { OMCTestLog(@"buoc loi: %@", e); }
    });
    return nil;
}

// Bit tra loi cua app cho lan cham moi nhat (nil = chua tra loi)
static NSNumber *SCPATTouchBits(NSString *bid)
{
    NSDictionary *r = sTouchReplies[bid];
    return (r && [r[@"seq"] isEqual:sTouchSeq[bid]]) ? r[@"bits"] : nil;
}

static NSString *SCPATTouchWhy(NSString *bid, NSNumber *b, NSString *notEnough)
{
    if (!b) return SCPATWhy(SCPATF(@"%@ khong tra loi (dylib App Bridge chua nap vao app, hay app khong nhan thong bao)", SCPATShort(bid)));
    NSUInteger bits = b.unsignedIntegerValue;
    if (bits & OMC_AT_TOUCH_NOWINDOW) return SCPATWhy(SCPATF(@"%@ khong co cua so tren xe de cham", SCPATShort(bid)));
    if (!(bits & OMC_AT_TOUCH_HIT)) return SCPATWhy(SCPATF(@"cham khong toi view nao cua %@", SCPATShort(bid)));
    return SCPATWhy(notEnough);
}

// Buoc: cham vao 1 video trong YouTube (app tu tim o video, ve ngon tay, cham) -> man hinh phai doi (trang xem video mo)
static NSDictionary *SCPATTapVideoStep(NSString *bid, NSString *name)
{
    return OMCTestStep(name, 4.5, 16, ^NSString *{
        if (![bid isEqualToString:SCPAT_YT]) return @"chi thu voi YouTube";
        if (![sBridgeStates[bid] isEqualToString:@"ready"]) return SCPATF(@"%@ chua hien tren xe", SCPATShort(bid));
        SCPATPostTouch(bid, @{@"kind": @"tap", @"target": @"host", @"find": @"video", @"fx": @0.5, @"fy": @0.42});
        return nil;
    }, ^NSString *{
        NSNumber *b = SCPATTouchBits(bid);
        if (b && (b.unsignedIntegerValue & OMC_AT_TOUCH_CHANGED)) return nil;
        return SCPATTouchWhy(bid, b, @"cham toi app nhung man hinh khong doi (trang xem video khong mo; log AppBridge ghi view nhan cham)");
    });
}

// Buoc: keo ban do qua lai trong cua so CarPlay cua app (app tu ve ngon tay, keo sang phai roi keo ve)
static NSDictionary *SCPATDragMapStep(NSString *bid, NSString *name)
{
    return OMCTestStep(name, 4, 15, ^NSString *{
        SCPATPostTouch(bid, @{@"kind": @"drag", @"target": @"car", @"fx": @0.35, @"fy": @0.5, @"fx2": @0.65, @"fy2": @0.5, @"back": @1});
        return nil;
    }, ^NSString *{
        NSNumber *b = SCPATTouchBits(bid);
        if (b && (b.unsignedIntegerValue & OMC_AT_TOUCH_GESTURE)) return nil;
        return SCPATTouchWhy(bid, b, @"cham toi ban do nhung khong gesture nao nhan keo (ban do co the khong di chuyen; xem log AppBridge)");
    });
}

#pragma mark - App de thu

// App CarPlay: Google Maps va GOFA truoc (uu tien khi mo / chia man), roi app Apple (luon co, it bat ngo), roi app khac
static NSArray<NSString *> *SCPATCarApps(void)
{
    NSArray *all = [SCPPrefs carPlayApps] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *b in @[SCPAT_GMAPS, SCPAT_GOFA, @"com.apple.Maps", @"com.apple.Music", @"com.apple.podcasts", @"com.apple.MobileSMS", @"com.apple.mobilephone"])
        if ([all containsObject:b]) [out addObject:b];
    for (NSString *b in all) if (![out containsObject:b]) [out addObject:b];
    return out;
}

// App iPhone (App Bridge): app da chon, YouTube truoc (cham vao video), roi TikTok, toi da 3
static NSArray<NSString *> *SCPATPhoneApps(void)
{
    NSArray *chosen = OMCPref(AB_KEY_APPS, @[]);
    if (![chosen isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *b in @[SCPAT_YT, @"com.zhiliaoapp.musically"]) if ([chosen containsObject:b]) [out addObject:b];
    for (NSString *b in chosen) if (![out containsObject:b] && out.count < 3) [out addObject:b];
    return out;
}

static NSDictionary *SCPATSkip(NSString *name, NSString *why)
{
    return OMCTestStep(name, 0, 0, ^NSString *{ return why; }, nil);
}

#pragma mark - Bo test Chia man hinh

static NSArray<NSDictionary *> *SCPATSplitSteps(void)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    NSArray<NSString *> *car = SCPATCarApps();
    NSString *A = car.count > 0 ? car[0] : nil, *B = car.count > 1 ? car[1] : nil, *C = car.count > 2 ? car[2] : nil;
    NSMutableArray *steps = [NSMutableArray array];
    OMCTestBlock home = ^NSString *{ SCPATHome(); return nil; };
    OMCTestBlock atHome = ^NSString *{ return SCPATExpectHome(); };
    OMCTestPointBlock fHome = ^NSValue *{ return SCPATAtHome(); }, fDock = ^NSValue *{ return SCPATAtDock(); };
    OMCTestPointBlock fDivider = ^NSValue *{ return SCPATAtDivider(); };

    [steps addObject:OMCTestStep(@"Moi truong: hook va app CarPlay", 0, 0, nil, ^NSString *{
        NSDictionary *hooks = OMCPref([NSString stringWithFormat:@"%@SplitScreen@%@", OMC_KEY_DIAG_HOOKS, [NSProcessInfo processInfo].processName], nil);
        NSArray *missing = [hooks isKindOfClass:[NSDictionary class]] ? hooks[@"missing"] : nil;
        OMCTestLog(@"app CarPlay: %@", [car componentsJoinedByString:@", "]);
        if (car.count < 2) return SCPATF(@"chi co %lu app CarPlay, can it nhat 2", (unsigned long)car.count);
        return missing.count ? SCPATF(@"thieu hook: %@", [missing componentsJoinedByString:@", "]) : nil;
    })];
    [steps addObject:OMCTestStepAt(@"Ve man chinh", 1.5, 6, fHome, home, atHome)];

    // --- Mo app: Google Maps toan man tu man chinh, keo ban do qua lai (cham do app tu gui), ve Home
    if ([car containsObject:SCPAT_GMAPS]) {
        [steps addObject:OMCTestStep(@"Mo Google Maps toan man (icon tren man chinh)", 3, 14, ^NSString *{ SCPCarLaunchApp(SCPAT_GMAPS); return nil; },
            ^NSString *{ return SCPATExpectSolo(SCPAT_GMAPS); })];
        [steps addObject:SCPATDragMapStep(SCPAT_GMAPS, @"Google Maps: keo ban do qua lai")];
        [steps addObject:OMCTestStepAt(@"Home tu Google Maps", 1.5, 8, fHome, home, atHome)];
    } else {
        [steps addObject:SCPATSkip(@"Mo Google Maps toan man, keo ban do", @"Google Maps khong co tren man chinh CarPlay")];
    }

    // --- Nut Split Screen tren dock: hinh 2 o theo nut Home, bam mo / dong bang bo cuc
    OMCTestBlock tapDock = ^NSString *{
        if (![s homeButton]) return @"khong co nut Split Screen";
        [[s homeButton] sendActionsForControlEvents:UIControlEventTouchUpInside]; return nil;
    };
    [steps addObject:OMCTestStep(@"Nut Split Screen tren dock (2 o theo nut Home)", 1.5, 8, ^NSString *{ [s refreshHomeButton]; return nil; },
        ^NSString *{ return SCPATExpectDockButton(); })];
    [steps addObject:OMCTestStepAt(@"Bam nut Split Screen: hien bang bo cuc", 1.5, 6, fDock, tapDock,
        ^NSString *{ return [s tray] ? nil : SCPATWhy(@"bang bo cuc khong hien"); })];
    // Bang dang mo: cham bat ky cho khac (goc duoi vung app, ngoai bang) -> dong ngay (lop nhin cham, hitTest nhu cham that)
    OMCTestPointBlock fCorner = ^NSValue *{
        UIView *parent = [s tabParent];
        CGRect area = [s appAreaInParent:parent];
        return SCPATScreenPoint(parent, CGPointMake(CGRectGetMinX(area) + 12, CGRectGetMaxY(area) - 12));
    };
    [steps addObject:OMCTestStepAt(@"Bang bo cuc mo, cham cho khac -> dong ngay", 1, 5, fCorner, ^NSString *{
        UIView *shield = [s popupShield];
        if (![s tray]) return @"bang bo cuc chua mo";
        if (!shield || !shield.window) return SCPATWhy(@"khong co lop nhin cham khi bang mo");
        UIView *parent = [s tabParent];
        CGRect area = [parent convertRect:[s appAreaInParent:parent] toView:nil];
        CGPoint p = [shield convertPoint:CGPointMake(CGRectGetMinX(area) + 12, CGRectGetMaxY(area) - 12) fromView:nil];
        [shield hitTest:p withEvent:nil];
        return nil;
    }, ^NSString *{ return [s tray] ? SCPATWhy(@"bang bo cuc van con sau khi cham cho khac") : nil; })];
    [steps addObject:OMCTestStepAt(@"Bam nut Split Screen: hien lai bang bo cuc", 1.5, 6, fDock, tapDock,
        ^NSString *{ return [s tray] ? nil : SCPATWhy(@"bang bo cuc khong hien"); })];
    [steps addObject:OMCTestStepAt(@"Bam lai nut Split Screen: dong bang bo cuc", 1, 5, fDock, tapDock,
        ^NSString *{ return [s tray] ? SCPATWhy(@"bang bo cuc van con") : nil; })];
    if (!A || !B) return steps;
    NSString *a = SCPATShort(A), *b = SCPATShort(B);

    // --- 2 o: mo (Google Maps | GOFA khi co), keo ban do trong o, ti le, doi cho
    [steps addObject:OMCTestStepAt(SCPATF(@"2 o: %@ | %@", a, b), 3, 12, fDock, ^NSString *{ [s openSetupLayout:2 apps:@[A, B]]; return nil; },
        ^NSString *{ return SCPATExpectLayout(2, @[A, B]); })];
    if ([A isEqualToString:SCPAT_GMAPS]) [steps addObject:SCPATDragMapStep(A, @"Google Maps trong o: keo ban do qua lai")];
    [steps addObject:OMCTestStep(@"Nut Split Screen van hien khi dang chia", 1, 6, nil,
        ^NSString *{ return SCPATExpectDockButton() ?: SCPATExpectLayout(2, @[A, B]); })];
    for (NSNumber *r in @[@0.3, @0.7, @0.5]) {
        CGFloat first = r.doubleValue;
        [steps addObject:OMCTestStepAt(SCPATF(@"Ti le %.0f / %.0f (scene doi theo)", first * 100, (1 - first) * 100), 1.5, 6, fDivider, ^NSString *{
            if (!s.active) return @"split chua bat";
            [s setFractions:[NSMutableArray arrayWithObjects:@(first), @(1 - first), nil]];
            [s relayoutAnimated:NO];
            return nil;
        }, ^NSString *{ return SCPATExpectRatio(first); })];
    }
    [steps addObject:OMCTestStepAt(@"Doi cho 2 o", 1.5, 8, ^NSValue *{ return SCPATAtSlot(0, YES); }, ^NSString *{ [s swapSlot:0 with:1]; return nil; },
        ^NSString *{ return SCPATExpectLayout(2, @[B, A]); })];
    // Thanh nut (cham "•••") dang mo: cham bat ky cho khac tren man (o ben canh) -> an ngay, khong cho het 4 giay
    [steps addObject:OMCTestStepAt(@"Thanh nut mo, cham o ben canh -> an ngay", 1, 5, ^NSValue *{ return SCPATAtSlot(1, NO); }, ^NSString *{
        if (!s.active || [s paneCount] < 2) return @"split chua bat";
        id p0 = [s slots][0], p1 = [s slots][1];
        [s setBarVisible:YES forPane:p0];
        UIView *bar = SCPATPane(p0, @"bar");
        if (!bar || bar.hidden) return @"thanh nut cua o 1 khong mo";
        [s hideBarsForTouchOn:SCPATPane(p1, @"view")];   // = hitTest cua container tra ve view cua o 2
        return nil;
    }, ^NSString *{
        for (id p in [s slots]) { UIView *bar = SCPATPane(p, @"bar"); if (bar && !bar.hidden) return SCPATWhy(@"thanh nut van con sau khi cham cho khac"); }
        return nil;
    })];

    // --- 3 o va 2 kieu 1 lon + 2
    if (C) {
        NSString *c = SCPATShort(C);
        [steps addObject:OMCTestStepAt(SCPATF(@"3 o: %@ | %@ | %@", b, a, c), 3, 14, fDock, ^NSString *{ [s openSetupLayout:3 apps:@[B, A, C]]; return nil; },
            ^NSString *{ return SCPATExpectLayout(3, @[B, A, C]); })];
        [steps addObject:OMCTestStepAt(@"Doi sang 1 lon + 2", 2, 10, fDock, ^NSString *{ [s switchToLayout:13]; return nil; },
            ^NSString *{ return SCPATExpectLayout(13, @[B, A, C]); })];
        [steps addObject:OMCTestStepAt(@"1 lon + 2: doi cho o lon voi o nho", 2, 10, ^NSValue *{ return SCPATAtSlot(0, YES); }, ^NSString *{ [s swapSlot:0 with:2]; return nil; },
            ^NSString *{ return SCPATExpectLayout(13, @[C, A, B]); })];
        [steps addObject:OMCTestStepAt(@"Doi sang 2 + 1 lon", 2, 10, fDock, ^NSString *{ [s switchToLayout:31]; return nil; },
            ^NSString *{ return SCPATExpectLayout(31, @[C, A, B]); })];
        [steps addObject:OMCTestStepAt(@"Doi ve 3 o deu", 2, 10, fDock, ^NSString *{ [s switchToLayout:3]; return nil; },
            ^NSString *{ return SCPATExpectLayout(3, @[C, A, B]); })];
        [steps addObject:OMCTestStepAt(@"Dong o cuoi (3 -> 2)", 2, 10, ^NSValue *{ return SCPATAtSlot(2, YES); }, ^NSString *{ [s closeSlot:2 background:YES]; return nil; },
            ^NSString *{ return SCPATExpectLayout(2, @[C, A]); })];
        [steps addObject:OMCTestStepAt(@"Dong them 1 o (con 1 -> toan man)", 3, 12, ^NSValue *{ return SCPATAtSlot(1, YES); }, ^NSString *{ [s closeSlot:1 background:YES]; return nil; },
            ^NSString *{ return SCPATExpectSolo(C); })];
        [steps addObject:OMCTestStepAt(@"Home tu app toan man", 1.5, 8, fHome, home, atHome)];
    } else {
        [steps addObject:SCPATSkip(@"3 o / 1 lon + 2 / 2 + 1 lon", @"can 3 app CarPlay")];
    }

    // --- Cua so noi
    [steps addObject:OMCTestStepAt(@"Cua so noi: dua o 2 ra", 3, 12, fDock, ^NSString *{
        [s openSetupLayout:2 apps:@[A, B]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try { if (s.active && [s paneCount] == 2) [s popOutPane:[s slots][1]]; } @catch (NSException *e) {}
        });
        return nil;
    }, ^NSString *{
        id fp = [s floatPane];
        if (!fp) return SCPATWhy(@"khong co cua so noi");
        if (![SCPATPane(fp, @"bundleID") isEqualToString:B] || !SCPATPane(fp, @"vc")) return SCPATWhy(SCPATF(@"cua so noi khong chua %@", b));
        return nil;
    })];
    [steps addObject:OMCTestStepAt(@"Cua so noi: dua ve o", 2.5, 10, ^NSValue *{ return SCPATAtFloat(); }, ^NSString *{
        if (![s floatPane]) return @"khong co cua so noi";
        [s floatDockBack]; return nil;
    }, ^NSString *{ return SCPATExpectLayout(2, nil); })];

    // --- Bang chon app, bang bo cuc
    [steps addObject:OMCTestStepAt(@"O trong hien bang chon app", 2, 8, fDock, ^NSString *{
        if (!s.active) return @"split chua bat";
        [s switchToLayout:3]; return nil;
    }, ^NSString *{
        if ([s pickerSheet]) return nil;
        for (id p in [s slots]) if (SCPATPane(p, @"picker")) return nil;
        return SCPATWhy(@"khong thay bang chon app");
    })];
    [steps addObject:OMCTestStepAt(@"Dong bang chon, ve 2 o", 2, 8, fDock, ^NSString *{ [s removePickerSheet]; [s switchToLayout:2]; return nil; },
        ^NSString *{ return SCPATExpectLayout(2, nil); })];
    [steps addObject:OMCTestStepAt(@"Toan man tu split (giu o 1)", 3, 10, ^NSValue *{ return SCPATAtSlot(0, YES); }, ^NSString *{
        if (!SCPATPaneBundle(0)) return @"o 1 khong co app";
        [s soloBundle:SCPATPaneBundle(0)]; return nil;
    }, ^NSString *{
        NSString *base = SCPATBaseBundle();
        return (!s.active && base) ? nil : SCPATWhy(@"khong ve app toan man");
    })];
    [steps addObject:OMCTestStepAt(@"Home", 1.5, 8, fHome, home, atHome)];
    [steps addObject:OMCTestStepAt(@"Bang bo cuc (nut Split Screen)", 1.5, 6, fDock, ^NSString *{ [s showLayoutPanelForApp:nil]; return nil; },
        ^NSString *{ return [s tray] ? nil : SCPATWhy(@"bang bo cuc khong hien"); })];
    [steps addObject:OMCTestStepAt(@"Dong bang bo cuc", 1, 5, fDock, ^NSString *{ [s collapseAppTray]; return nil; },
        ^NSString *{ return [s tray] ? SCPATWhy(@"bang bo cuc van con") : nil; })];

    // --- Lenh URL / Siri / Shortcuts (cung duong SpringBoard gui sang)
    [steps addObject:OMCTestStep(@"Lenh URL: mo cap", 3, 12, ^NSString *{ SCPATCommand(@{@"action": @"pair", @"left": A, @"right": B}); return nil; },
        ^NSString *{ return SCPATExpectLayout(2, @[A, B]); })];
    [steps addObject:OMCTestStep(@"Lenh URL: dong 1 app (con app kia toan man)", 3, 12, ^NSString *{
        SCPATCommand(@{@"action": @"closeApp", @"identifier": B}); return nil;
    }, ^NSString *{ return SCPATExpectSolo(A); })];
    [steps addObject:OMCTestStep(@"Lenh URL: mo lai cap", 3, 12, ^NSString *{ SCPATCommand(@{@"action": @"pair", @"left": A, @"right": B}); return nil; },
        ^NSString *{ return SCPATExpectLayout(2, @[A, B]); })];
    [steps addObject:OMCTestStep(@"Lenh URL: tat split", 1.5, 8, ^NSString *{ SCPATCommand(@{@"action": @"close"}); return nil; }, atHome)];

    // --- Yeu thich, gan day
    for (NSInteger n = 1; n <= 3; n++) {
        NSDictionary *fav = [SCPPrefs favorite:n];
        NSArray *apps = fav ? [s favoriteApps:fav] : nil;
        if (!apps) { [steps addObject:SCPATSkip(SCPATF(@"Yeu thich %ld", (long)n), @"chua dat")]; continue; }
        int layout = [fav[@"layout"] intValue];
        [steps addObject:OMCTestStep(SCPATF(@"Yeu thich %ld (bo cuc %d)", (long)n, layout), 3.5, 16, ^NSString *{ [s openFavorite:n]; return nil; },
            ^NSString *{ return SCPATExpectLayout(layout, apps); })];
        [steps addObject:OMCTestStepAt(SCPATF(@"Home sau yeu thich %ld", (long)n), 1.5, 8, fHome, home, atHome)];
    }
    NSDictionary *recent = [SCPPrefs recentLayouts].firstObject;
    if (recent) {
        int layout = [recent[@"layout"] intValue];
        NSArray *apps = recent[@"apps"];
        [steps addObject:OMCTestStep(SCPATF(@"Gan day (bo cuc %d)", layout), 3.5, 16, ^NSString *{ [s openSetupLayout:layout apps:apps]; return nil; },
            ^NSString *{ return SCPATExpectLayout(layout, apps); })];
        [steps addObject:OMCTestStepAt(@"Home sau gan day", 1.5, 8, fHome, home, atHome)];
    }

    // --- Bam lien tuc nhu nguoi dung vo y: cuoi cung split phai on dinh
    [steps addObject:OMCTestStepAt(@"Bam nhanh lien tuc (doi bo cuc 5 lan)", 5, 16, fDock, ^NSString *{
        [s openSetupLayout:2 apps:@[A, B]];
        double d = 0.7;
        for (int i = 0; i < 5; i++, d += 0.6) {
            int layout = (i % 2 == 0 && C) ? 13 : (i % 2 == 0 ? 3 : 2);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try { if (s.active) [s switchToLayout:layout]; } @catch (NSException *e) { OMCTestLog(@"bam nhanh: %@", e); }
            });
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try { [s openSetupLayout:2 apps:@[A, B]]; } @catch (NSException *e) { OMCTestLog(@"bam nhanh: %@", e); }
        });
        return nil;
    }, ^NSString *{ return SCPATExpectLayout(2, @[A, B]); })];
    [steps addObject:OMCTestStepAt(@"Mo / tat split lien tuc 3 lan", 4, 14, fDock, ^NSString *{
        double d = 0;
        for (int i = 0; i < 3; i++, d += 1.6) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try { [s openSetupLayout:2 apps:@[A, B]]; } @catch (NSException *e) {}
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((d + 0.8) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try { [s closeGoingHome:YES]; } @catch (NSException *e) {}
            });
        }
        return nil;
    }, atHome)];
    [steps addObject:OMCTestStepAt(@"Ket thuc: ve man chinh", 1.5, 8, fHome, home, atHome)];
    [steps addObject:OMCTestStep(@"Nut Split Screen ve lai tren dock sau khi tat split", 1.5, 8, nil, ^NSString *{ return SCPATExpectDockButton(); })];
    return steps;
}

#pragma mark - Bo test App Bridge

static NSArray<NSDictionary *> *SCPATBridgeSteps(void)
{
    SCPCarSplit *s = [SCPCarSplit shared];
    NSArray<NSString *> *car = SCPATCarApps(), *phone = SCPATPhoneApps();
    NSString *A = car.firstObject, *B = car.count > 1 ? car[1] : nil;
    NSMutableArray *steps = [NSMutableArray array];
    OMCTestBlock home = ^NSString *{ SCPATHome(); return nil; };
    OMCTestBlock atHome = ^NSString *{ return SCPATExpectHome(); };
    OMCTestPointBlock fHome = ^NSValue *{ return SCPATAtHome(); }, fDock = ^NSValue *{ return SCPATAtDock(); };
    OMCTestPointBlock fDivider = ^NSValue *{ return SCPATAtDivider(); };

    [steps addObject:OMCTestStep(@"Moi truong: App Bridge va app iPhone", 0, 0, nil, ^NSString *{
        OMCTestLog(@"app iPhone: %@", [phone componentsJoinedByString:@", "]);
        if (!OMCFeatureEnabled(AB_FEATURE)) return @"App Bridge dang tat";
        if (!phone.count) return @"chua chon app iPhone nao (App tren man xe)";
        return A ? nil : @"khong co app CarPlay nao de ghep";
    })];
    if (!phone.count || !A || !OMCFeatureEnabled(AB_FEATURE)) return steps;
    [steps addObject:OMCTestStepAt(@"Ve man chinh", 1.5, 6, fHome, home, atHome)];

    for (NSString *P in phone) {
        NSString *p = SCPATShort(P);
        // Chia man: Google Maps | YouTube (A = Google Maps khi co). YouTube: cham vao 1 video nhu khi mo app; Google Maps: keo ban do
        [steps addObject:OMCTestStepAt(SCPATF(@"%@ trong o (ghep %@)", p, SCPATShort(A)), 3, 16, fDock, ^NSString *{
            [sBridgeStates removeObjectForKey:P];
            [s openSetupLayout:2 apps:@[A, P]]; return nil;
        }, ^NSString *{ return SCPATExpectLayout(2, @[A, P]); })];
        if ([P isEqualToString:SCPAT_YT]) [steps addObject:SCPATTapVideoStep(P, @"YouTube trong o: cham vao 1 video (mo xem)")];
        if ([A isEqualToString:SCPAT_GMAPS]) [steps addObject:SCPATDragMapStep(A, @"Google Maps trong o: keo ban do qua lai")];
        for (NSNumber *r in @[@0.7, @0.3]) {
            CGFloat first = r.doubleValue;
            [steps addObject:OMCTestStepAt(SCPATF(@"%@: ti le %.0f / %.0f", p, first * 100, (1 - first) * 100), 2, 8, fDivider, ^NSString *{
                if (!s.active) return @"split chua bat";
                [s setFractions:[NSMutableArray arrayWithObjects:@(first), @(1 - first), nil]];
                [s relayoutAnimated:NO]; return nil;
            }, ^NSString *{ return SCPATExpectRatio(first) ?: SCPATExpectLayout(2, @[A, P]); })];
        }
        [steps addObject:OMCTestStep(SCPATF(@"%@: doi cho voi app CarPlay", p), 3, 11, ^NSString *{
            return SCPATFingerThen(P, 0.5, 0.03, ^{ [s swapSlot:0 with:1]; });
        }, ^NSString *{ return SCPATExpectLayout(2, @[P, A]); })];
        // Moi app deu ra cua so noi duoc (tu 18/10): app iPhone noi (SpringBoard dua o len tren), roi app CarPlay noi tren o app
        // iPhone (SpringBoard khoet lo trong o). Cua so noi phai con sau khi lang (khong bi "che thi dong" nhu truoc).
        OMCTestBlock (^expectFloat)(NSString *, NSString *) = ^OMCTestBlock(NSString *floating, NSString *inSlot) {
            return ^NSString *{
                id fp = [s floatPane];
                if (!fp) return SCPATWhy(SCPATF(@"%@ khong ra cua so noi (%@)", SCPATShort(floating), [s popOutBlockReason:[s slots].firstObject] ?: @"?"));
                if (![SCPATPane(fp, @"bundleID") isEqualToString:floating] || !SCPATPane(fp, @"vc")) return SCPATWhy(SCPATF(@"cua so noi khong chua %@", SCPATShort(floating)));
                if ([s paneCount] != 1 || ![SCPATPaneBundle(0) isEqualToString:inSlot]) return SCPATWhy(SCPATF(@"o con lai khong phai %@", SCPATShort(inSlot)));
                return nil;
            };
        };
        [steps addObject:OMCTestStep(SCPATF(@"%@: app iPhone ra cua so noi", p), 4, 11, ^NSString *{
            if (!s.active) return @"split chua bat";
            return SCPATFingerThen(P, 0.5, 0.03, ^{ [s popOutPane:[s slots][0]]; });
        }, expectFloat(P, A))];
        [steps addObject:OMCTestStep(SCPATF(@"%@: cua so noi dua ve o", p), 3.5, 11, ^NSString *{
            if (![s floatPane]) return @"khong co cua so noi";
            return SCPATFingerThen(P, 0.5, 0.05, ^{ [s floatDockBack]; });
        }, ^NSString *{ return SCPATExpectLayout(2, @[P, A]); })];
        [steps addObject:OMCTestStepAt(SCPATF(@"%@ trong o, app CarPlay noi tren (khoet lo)", SCPATShort(A)), 3, 10, ^NSValue *{ return SCPATAtSlot(1, YES); }, ^NSString *{
            if (!s.active || [s paneCount] != 2) return @"split khong phai 2 o";
            [s popOutPane:[s slots][1]]; return nil;
        }, expectFloat(A, P))];
        [steps addObject:OMCTestStepAt(SCPATF(@"%@: cua so noi dua ve o", SCPATShort(A)), 2.5, 10, ^NSValue *{ return SCPATAtFloat(); }, ^NSString *{
            if (![s floatPane]) return @"khong co cua so noi";
            [s floatDockBack]; return nil;
        }, ^NSString *{ return SCPATExpectLayout(2, @[P, A]); })];
        if (B) {
            // 3 o: Google Maps | YouTube | GOFA khi co
            [steps addObject:OMCTestStepAt(SCPATF(@"%@ o giua 3 o (%@ | %@ | %@)", p, SCPATShort(A), p, SCPATShort(B)), 3, 16, fDock,
                ^NSString *{ [s openSetupLayout:3 apps:@[A, P, B]]; return nil; },
                ^NSString *{ return SCPATExpectLayout(3, @[A, P, B]); })];
            if ([P isEqualToString:SCPAT_YT]) [steps addObject:SCPATTapVideoStep(P, @"YouTube o giua 3 o: cham vao 1 video")];
            [steps addObject:OMCTestStepAt(SCPATF(@"%@ trong 1 lon + 2", p), 2.5, 12, fDock, ^NSString *{ [s switchToLayout:13]; return nil; },
                ^NSString *{ return SCPATExpectLayout(13, @[A, P, B]); })];
            [steps addObject:OMCTestStepAt(SCPATF(@"Ve 2 o (%@ | %@)", SCPATShort(A), p), 2.5, 12, ^NSValue *{ return SCPATAtSlot(2, YES); },
                ^NSString *{ [s closeSlot:2 background:YES]; return nil; },
                ^NSString *{ return SCPATExpectLayout(2, @[A, P]); })];
        }
        // Nut "1 man hinh / chia man hinh": khi dang chia chi phong to tam o (split giu nguyen), bam lai thi thu nho
        NSArray *pair = B ? @[A, P] : @[P, A];
        [steps addObject:OMCTestStep(SCPATF(@"%@: nut 1 man hinh tren thanh nut (phong to o)", p), 3, 11, ^NSString *{
            if (![s isCarPlayApp:P] || !s.active) return @"app khong o trong split";
            return SCPATFingerThen(P, 0.5, 0.03, ^{ [s bridgeBarAction:@"full" forBundle:P]; });
        }, ^NSString *{ return SCPATExpectZoomed(P); })];
        [steps addObject:OMCTestStep(SCPATF(@"%@: bam lai -> ve chia man", p), 3, 11, ^NSString *{
            if (!s.active) return @"split chua bat";
            return SCPATFingerThen(P, 0.5, 0.03, ^{ [s bridgeBarAction:@"full" forBundle:P]; });
        }, ^NSString *{ return [s zoomedSlot] ? SCPATWhy(@"o van phong to") : SCPATExpectLayout(2, pair); })];
        [steps addObject:OMCTestStepAt(SCPATF(@"Home tu %@ trong split", p), 1.5, 8, fHome, home, atHome)];
        [steps addObject:OMCTestStepAt(SCPATF(@"%@: nut dong tren thanh nut", p), 5, 18, fDock, ^NSString *{
            [sBridgeStates removeObjectForKey:P];
            [s openSetupLayout:2 apps:@[A, P]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SCPATFingerThen(P, 0.5, 0.03, ^{ [s bridgeBarAction:@"close" forBundle:P]; });
            });
            return nil;
        }, ^NSString *{ return SCPATExpectSolo(A); })];   // con 1 o -> app CarPlay toan man
        [steps addObject:OMCTestStepAt(@"Home", 1.5, 8, fHome, home, atHome)];
    }

    // Mo app: YouTube toan man tu icon tren man chinh, cham vao 1 video, roi chia man tu do
    NSString *P = phone[0];
    [steps addObject:OMCTestStep(SCPATF(@"Icon %@ tren man chinh (toan man)", SCPATShort(P)), 3, 14, ^NSString *{
        [sBridgeStates removeObjectForKey:P];
        return [s launchPhoneAppIfNeeded:P] ? nil : @"khong phai app App Bridge";
    }, ^NSString *{ return SCPATExpectHostedSolo(P); })];
    if ([P isEqualToString:SCPAT_YT]) [steps addObject:SCPATTapVideoStep(P, @"YouTube toan man: cham vao 1 video (mo xem)")];
    [steps addObject:OMCTestStepAt(@"Mo split tu app iPhone toan man (app vao o 1)", 3, 14, fDock, ^NSString *{
        [s openSetupLayout:2 apps:@[P, A]]; return nil;
    }, ^NSString *{ return SCPATExpectLayout(2, @[P, A]); })];
    [steps addObject:OMCTestStepAt(@"Home", 1.5, 8, fHome, home, atHome)];
    if (phone.count >= 2) {
        NSString *Q = phone[1];
        [steps addObject:OMCTestStepAt(SCPATF(@"2 app iPhone cung luc: %@ | %@", SCPATShort(P), SCPATShort(Q)), 3, 18, fDock, ^NSString *{
            [sBridgeStates removeObjectForKey:P]; [sBridgeStates removeObjectForKey:Q];
            [s openSetupLayout:2 apps:@[P, Q]]; return nil;
        }, ^NSString *{ return SCPATExpectLayout(2, @[P, Q]); })];
        [steps addObject:OMCTestStepAt(@"Home", 1.5, 8, fHome, home, atHome)];
    }
    return steps;
}

#pragma mark - Dang ky

// ---------------------------------------------------------------------
//  Bo "homeScreen" (Man chinh CarPlay): bo / them lai 1 app CarPlay, luoi 4 x 2, tat / bat ten app. Moi buoc doi prefs roi
//  bao prefschanged (nhu Cai dat); buoc sau tra lai gia tri cua nguoi dung (luu luc bat dau bo test).
// ---------------------------------------------------------------------
static NSDictionary *sHomeSaved;

static void SCPATHomeSet(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, OMC_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
    notify_post("com.anlai.omnicar/prefschanged");
}

static id SCPATHomeSaved(NSString *key) { id v = sHomeSaved[key]; return [v isKindOfClass:[NSNull class]] ? nil : v; }

static NSString *SCPATHomeShowing(void)
{
    NSArray *ids = SCPHomeVisibleBundles();
    if (!ids) return @"man chinh CarPlay khong hien (dang mo app / chia man?)";
    return ids.count ? nil : @"khong doc duoc icon nao tren man chinh";
}

static NSArray<NSDictionary *> *SCPATHomeSteps(void)
{
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *k in @[HS_KEY_HIDDEN_APPS, HS_KEY_COLS, HS_KEY_ROWS, HS_KEY_NAMES]) saved[k] = OMCPref(k, nil) ?: [NSNull null];
    sHomeSaved = saved;
    __block NSString *target = nil;
    NSMutableArray *steps = [NSMutableArray array];

    [steps addObject:OMCTestStep(@"Man chinh hien, doc duoc icon", 0, 6, nil, ^NSString *{
        NSString *why = SCPATHomeShowing();
        if (why) return why;
        NSArray *ids = SCPHomeVisibleBundles();
        for (NSString *b in ids) if (SCPHomeAppRemovable(b)) { target = b; break; }
        OMCTestLog(@"man chinh %lu app: %@ (thu bo: %@)", (unsigned long)ids.count, [ids componentsJoinedByString:@", "], target ?: @"khong co");
        return nil;
    })];
    [steps addObject:OMCTestStep(@"Bo 1 app CarPlay", 2, 8, ^NSString *{
        if (!target) return @"khong co app CarPlay nao bo duoc (chi app khoa)";
        NSMutableArray *hid = [NSMutableArray arrayWithArray:[SCPATHomeSaved(HS_KEY_HIDDEN_APPS) isKindOfClass:[NSArray class]] ? SCPATHomeSaved(HS_KEY_HIDDEN_APPS) : @[]];
        if (![hid containsObject:target]) [hid addObject:target];
        SCPATHomeSet(HS_KEY_HIDDEN_APPS, hid);
        return nil;
    }, ^NSString *{
        if (!target) return nil;
        NSArray *ids = SCPHomeVisibleBundles();
        return [ids containsObject:target] ? OMCTestFormat(@"%@ van tren man chinh (isIconVisible: khong co tac dung?)", target) : nil;
    })];
    [steps addObject:OMCTestStep(@"Them lai app", 2, 8, ^NSString *{
        if (!target) return @"khong co app de them lai";
        SCPATHomeSet(HS_KEY_HIDDEN_APPS, SCPATHomeSaved(HS_KEY_HIDDEN_APPS));
        return nil;
    }, ^NSString *{
        if (!target) return nil;
        NSArray *ids = SCPHomeVisibleBundles();
        if (![ids containsObject:target]) return OMCTestFormat(@"%@ chua ve man chinh", target);
        OMCTestLog(@"%@ ve o vi tri %lu / %lu", target, (unsigned long)[ids indexOfObject:target] + 1, (unsigned long)ids.count);
        return nil;
    })];
    [steps addObject:OMCTestStep(@"Luoi 4 x 2", 2, 8, ^NSString *{
        SCPATHomeSet(HS_KEY_COLS, @4); SCPATHomeSet(HS_KEY_ROWS, @2);
        return nil;
    }, ^NSString *{
        NSInteger n = SCPHomeFirstPageIconCount();
        if (n < 0) return @"khong doc duoc trang dau";
        return n <= 8 ? nil : OMCTestFormat(@"trang dau co %ld icon, can <= 8", (long)n);
    })];
    [steps addObject:OMCTestStep(@"Tra lai luoi cua nguoi dung", 2, 8, ^NSString *{
        SCPATHomeSet(HS_KEY_COLS, SCPATHomeSaved(HS_KEY_COLS)); SCPATHomeSet(HS_KEY_ROWS, SCPATHomeSaved(HS_KEY_ROWS));
        return nil;
    }, ^NSString *{
        NSInteger n = SCPHomeFirstPageIconCount();
        OMCTestLog(@"trang dau %ld icon", (long)n);
        return n > 0 ? nil : @"trang dau khong co icon";
    })];
    [steps addObject:OMCTestStep(@"Tat ten app", 1.5, 6, ^NSString *{ SCPATHomeSet(HS_KEY_NAMES, @NO); return nil; }, ^NSString *{
        NSInteger n = SCPHomeVisibleLabelCount();
        return n == 0 ? nil : OMCTestFormat(@"con %ld ten app dang hien", (long)n);
    })];
    [steps addObject:OMCTestStep(@"Tra lai ten app", 1.5, 6, ^NSString *{ SCPATHomeSet(HS_KEY_NAMES, SCPATHomeSaved(HS_KEY_NAMES)); return nil; }, ^NSString *{
        BOOL want = [SCPATHomeSaved(HS_KEY_NAMES) ?: @YES boolValue];
        NSInteger n = SCPHomeVisibleLabelCount();
        return (!want || n > 0) ? nil : @"ten app chua hien lai";
    })];
    return steps;
}

void SCPAutoTestInstall(void)
{
    sBridgeStates = [NSMutableDictionary dictionary];
    sTouchReplies = [NSMutableDictionary dictionary];
    sTouchSeq = [NSMutableDictionary dictionary];
    // App tra loi cham tu kiem tra (OMC_DARWIN_AUTOTEST_TOUCH): state = hash bundle << 24 | seq << 8 | bit ket qua
    static int touchToken;
    notify_register_dispatch(OMC_DARWIN_AUTOTEST_TOUCH, &touchToken, dispatch_get_main_queue(), ^(int t) {
        uint64_t st = 0;
        notify_get_state(t, &st);
        for (NSString *bid in sTouchSeq.allKeys) {
            if (ABBundleHash(bid) != (st >> 24)) continue;
            sTouchReplies[bid] = @{@"seq": @((st >> 8) & 0xFFFF), @"bits": @(st & 0xFF)};
            OMCTestLog(@"%@ tra loi cham: seq %llu, bit %llu", SCPATShort(bid), (st >> 8) & 0xFFFF, st & 0xFF);
        }
    });
    // Trang thai App Bridge (SpringBoard bao): ready / failed / gone cua tung app iPhone
    [[objc_getClass("NSDistributedNotificationCenter") defaultCenter] addObserverForName:AB_NOTIF_STATE object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSString *bid = note.userInfo[@"identifier"], *state = note.userInfo[@"state"];
        if ([bid isKindOfClass:[NSString class]] && [state isKindOfClass:[NSString class]]) sBridgeStates[bid] = state;
    }];
    OMCTestRegister(SPL_FEATURE, ^BOOL { return SCPATCarReady(); }, ^NSArray<NSDictionary *> *{ return SCPATSplitSteps(); }, nil);
    OMCTestRegister(AB_FEATURE, ^BOOL { return SCPATCarReady(); }, ^NSArray<NSDictionary *> *{ return SCPATBridgeSteps(); }, nil);
    OMCTestRegister(@"homeScreen", ^BOOL { return SCPATCarReady() && SCPHomeVisibleBundles() != nil; },
                    ^NSArray<NSDictionary *> *{ return SCPATHomeSteps(); }, nil);
}

#endif
