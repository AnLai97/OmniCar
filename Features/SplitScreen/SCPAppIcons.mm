#import "SCPAppIcons.h"

// =====================================================================
//  Icon app iPhone tren man chinh CarPlay (iOS 16.5). DashBoard chi ve icon cho DBApplicationInfo co _carPlayDeclaration.
//  Cach lam (nhe hon carplay-cast, giu nguyen thu vien goc cua DashBoard):
//    1. +[DashBoard _newApplicationLibrary] (AppIcons.xm): lay thu vien goc roi addApplicationProxy:withOverrideURL: cho
//       tung app trong AB_KEY_APPS (them tuong minh thi khong qua bo loc "chi app CarPlay" cua thu vien).
//    2. -[DBApplicationInfo _loadFromProxy:] (AppIcons.xm): sau %orig, app da chon ma khong co declaration thi gan
//       CRCarPlayAppDeclaration gia (khong template, supportsMaps -> DashBoard coi nhu app UIKit) + tag "OmniCarAppBridge".
//       Chay ngay luc thu vien tao info nen DashBoard thay app nhu app CarPlay that tu dau.
//  Doi danh sach trong Settings: them / bo proxy tren thu vien dang dung roi _handleAppLibraryRefresh (SCPRefreshAppIconsSoon).
// =====================================================================

#define SCP_INJECT_TAG @"OmniCarAppBridge"

static NSMutableSet<NSString *> *sInjected;   // bundle id da gan declaration gia (doc / ghi tren nhieu queue -> @synchronized)
static NSSet<NSString *> *sBuiltChosen;       // danh sach chon luc them proxy lan cuoi (de biet prefschanged co doi gi khong)
static __weak id sHomeVC;

static NSMutableSet<NSString *> *SCPInjectedSet(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sInjected = [NSMutableSet set]; });
    return sInjected;
}

BOOL SCPIsInjectedPhoneApp(NSString *bid)
{
    if (!bid) return NO;
    @synchronized (SCPInjectedSet()) { return [sInjected containsObject:bid]; }
}

NSSet<NSString *> *SCPChosenPhoneApps(void)
{
    if (!OMCFeatureEnabled(AB_FEATURE)) return [NSSet set];
    OMCPrefsSync();
    id v = OMCPref(AB_KEY_APPS, nil);
    return [v isKindOfClass:[NSArray class]] ? [NSSet setWithArray:v] : [NSSet set];
}

static id SCPTryGet(id obj, NSString *sel)
{
    if (!obj || ![obj respondsToSelector:NSSelectorFromString(sel)]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel)); } @catch (NSException *e) { return nil; }
}

static id SCPIvar(id obj, NSString *name)
{
    @try { return [obj valueForKey:name]; } @catch (NSException *e) { return nil; }
}

static BOOL SCPSetIvar(id obj, NSString *name, id value)
{
    @try { [obj setValue:value forKey:name]; return YES; }
    @catch (NSException *e) { SCPLog("AppIcons: khong dat duoc %@ cua %@: %@", name, [obj class], e); return NO; }
}

// -[DBApplicationInfo _loadFromProxy:] vua chay: app da chon ma khong co declaration -> gan declaration gia
void SCPInjectDeclarationIfChosen(id info)
{
    NSString *bid = SCPTryGet(info, @"bundleIdentifier");
    if (!bid.length) return;
    NSSet *chosen = SCPChosenPhoneApps();
    if (![chosen containsObject:bid]) return;
    if (SCPIvar(info, @"_carPlayDeclaration")) {
        NSArray *tags = SCPTryGet(info, @"tags");
        if (![tags containsObject:SCP_INJECT_TAG]) SCPLog("AppIcons: %@ da co declaration that (app CarPlay) -> khong chen", bid);
        return;
    }
    Class Decl = objc_getClass("CRCarPlayAppDeclaration");
    if (!Decl) { SCPLog("AppIcons: khong co lop CRCarPlayAppDeclaration"); return; }
    id decl = [[Decl alloc] init];
    objcCall_1(decl, @"setSupportsTemplates:", (BOOL)NO);   // khong template: CarPlayTemplateUIHost se khong tim template roi sap
    objcCall_1(decl, @"setSupportsMaps:", (BOOL)YES);
    objcCall_1(decl, @"setBundleIdentifier:", bid);
    // iOS 16.5: _bundlePath la NSString (DIAG); carplay-cast truyen NSURL
    id bundleURL = SCPTryGet(info, @"bundleURL");
    NSString *bundlePath = [bundleURL isKindOfClass:[NSURL class]] ? [(NSURL *)bundleURL path] : ([bundleURL isKindOfClass:[NSString class]] ? bundleURL : nil);
    if (bundlePath) objcCall_1(decl, @"setBundlePath:", bundlePath);
    if (!SCPSetIvar(info, @"_carPlayDeclaration", decl)) return;
    NSArray *tags = SCPTryGet(info, @"tags");
    SCPSetIvar(info, @"_tags", [@[SCP_INJECT_TAG] arrayByAddingObjectsFromArray:[tags isKindOfClass:[NSArray class]] ? tags : @[]]);
    BOOL valid = objcInvokeT(info, @"isValid", BOOL);
    if (!valid) SCPSetIvar(info, @"_valid", @YES);   // DashBoard co the bo qua info "khong hop le"
    @synchronized (SCPInjectedSet()) { [sInjected addObject:bid]; }
    SCPLog("AppIcons: chen %@: valid=%d hidden=%d installed=%d fullScreen=%d path=%@", bid, valid,
           objcInvokeT(info, @"isHidden", BOOL), objcInvokeT(info, @"isInstalled", BOOL), objcInvokeT(info, @"presentsFullScreen", BOOL), bundlePath);
}

static id SCPProxyFor(NSString *bid)
{
    Class Proxy = objc_getClass("LSApplicationProxy");
    id proxy = Proxy ? objcInvoke_1(Proxy, @"applicationProxyForIdentifier:", bid) : nil;
    id state = SCPTryGet(proxy, @"appState");
    return (state && objcInvokeT(state, @"isValid", BOOL)) ? proxy : nil;
}

// Them app da chon vao thu vien (bo qua app da co trong thu vien: app CarPlay that)
void SCPAddChosenAppsToLibrary(id library)
{
    NSSet *chosen = SCPChosenPhoneApps();
    sBuiltChosen = chosen;
    NSUInteger added = 0;
    for (NSString *bid in chosen) {
        if (objcInvoke_1(library, @"applicationInfoForBundleIdentifier:", bid)) continue;
        id proxy = SCPProxyFor(bid);
        if (!proxy) { SCPLog("AppIcons: %@ khong cai / khong hop le -> bo qua", bid); continue; }
        objcCall_2(library, @"addApplicationProxy:withOverrideURL:", proxy, (id)nil);
        added++;
    }
    SCPLog("AppIcons: them %lu / %lu app da chon vao thu vien %@", (unsigned long)added, (unsigned long)chosen.count, [library class]);
}

void SCPSetHomeViewController(id vc)
{
    sHomeVC = vc;
}

static id SCPCurrentLibrary(void)
{
    id home = sHomeVC;
    id lib = home ? SCPTryGet(home, @"library") : nil;
    return lib ?: SCPTryGet([UIApplication sharedApplication], @"sharedApplicationLibrary");
}

// Danh sach app chon doi trong Settings: them / bo proxy tren thu vien dang dung roi ve lai man chinh (debounce 0.8s vi
// moi cong tac mot prefschanged)
void SCPRefreshAppIconsSoon(void)
{
    static NSUInteger gen;
    NSUInteger my = ++gen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (my != gen) return;
        NSSet *chosen = SCPChosenPhoneApps();
        if ([chosen isEqualToSet:sBuiltChosen ?: [NSSet set]]) return;   // khong doi (prefs khac)
        SCPAppIconsRetry();
        @try {
            id lib = SCPCurrentLibrary();
            if (!lib) { SCPLog("AppIcons: chua co thu vien de cap nhat"); return; }
            NSMutableSet *removed = [NSMutableSet set];
            @synchronized (SCPInjectedSet()) {
                for (NSString *bid in sInjected) if (![chosen containsObject:bid]) [removed addObject:bid];
                [sInjected minusSet:removed];
            }
            for (NSString *bid in removed) {
                id proxy = SCPProxyFor(bid);
                if (proxy) objcCall_1(lib, @"removeApplicationProxy:", proxy);
            }
            SCPAddChosenAppsToLibrary(lib);
            SCPLog("AppIcons: danh sach doi -> bo %lu app, ve lai man chinh", (unsigned long)removed.count);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                @try { objcCall(sHomeVC, @"_handleAppLibraryRefresh"); } @catch (NSException *e) { SCPLog("AppIcons: refresh loi %@", e); }
            });
        } @catch (NSException *e) { SCPLog("AppIcons: cap nhat thu vien loi %@", e); }
    });
}

// ---------------------------------------------------------------------
//  Cau dao chong crash-loop: ghi "dang chen" vao prefs truoc khi them app vao thu vien, xoa khi man xe hien
//  (carScreenAppeared). Lan khoi dong sau ma con "dang chen" = CarPlay sap sau khi chen -> ghi version bi sap, khong chen
//  nua cho den khi nguoi dung doi danh sach app (prefschanged) hoac cai ban moi (version khac).
// ---------------------------------------------------------------------
#define SCP_KEY_ICONS_PENDING  @"splitScreenIconsPending"
#define SCP_KEY_ICONS_CRASHED  @"splitScreenIconsCrashed"
#ifndef TWEAK_VERSION
#define TWEAK_VERSION "dev"
#endif

static void SCPIconsStore(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, OMC_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

// YES = duoc phep chen lan nay (va da danh dau "dang chen")
BOOL SCPAppIconsBeginInjection(void)
{
    OMCPrefsSync();
    NSString *ver = @TWEAK_VERSION;
    if ([OMCPref(SCP_KEY_ICONS_PENDING, nil) boolValue]) {
        SCPLog("AppIcons: lan truoc CarPlay sap sau khi chen icon -> tat chen icon o ban %@ (doi danh sach app de thu lai)", ver);
        SCPIconsStore(SCP_KEY_ICONS_CRASHED, ver);
        SCPIconsStore(SCP_KEY_ICONS_PENDING, nil);
    }
    if ([OMCPref(SCP_KEY_ICONS_CRASHED, nil) isEqual:ver]) {
        SCPLog("AppIcons: dang tat vi tung sap o ban %@", ver);
        return NO;
    }
    SCPIconsStore(SCP_KEY_ICONS_PENDING, @YES);
    return YES;
}

void SCPAppIconsCarScreenOK(void)
{
    OMCPrefsSync();
    if ([OMCPref(SCP_KEY_ICONS_PENDING, nil) boolValue]) {
        SCPIconsStore(SCP_KEY_ICONS_PENDING, nil);
        SCPLog("AppIcons: man xe hien binh thuong sau khi chen icon");
    }
}

void SCPAppIconsRetry(void)
{
    OMCPrefsSync();
    if (OMCPref(SCP_KEY_ICONS_CRASHED, nil)) {
        SCPIconsStore(SCP_KEY_ICONS_CRASHED, nil);
        SCPLog("AppIcons: danh sach app doi -> cho phep chen icon lai");
    }
}

// =====================================================================
//  Chan doan (giu lai): log lop / method / ivar cua thu vien app, info, declaration, icon tren man chinh
// =====================================================================

static NSString *SCPMethodNames(Class c)
{
    unsigned n = 0;
    Method *ms = class_copyMethodList(c, &n);
    NSMutableArray *a = [NSMutableArray array];
    for (unsigned i = 0; i < n; i++) [a addObject:NSStringFromSelector(method_getName(ms[i]))];
    free(ms);
    return [[a sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "];
}

static NSString *SCPIvarNames(Class c)
{
    unsigned n = 0;
    Ivar *iv = class_copyIvarList(c, &n);
    NSMutableArray *a = [NSMutableArray array];
    for (unsigned i = 0; i < n; i++) {
        const char *name = ivar_getName(iv[i]), *type = ivar_getTypeEncoding(iv[i]);
        [a addObject:[NSString stringWithFormat:@"%s(%s)", name ?: "?", type ?: "?"]];
    }
    free(iv);
    return [a componentsJoinedByString:@" "];
}

static void SCPDumpClass(NSString *tag, Class c)
{
    if (!c) { SCPLog("DIAG %@: khong co lop", tag); return; }
    NSMutableArray *chain = [NSMutableArray array];
    for (Class k = c; k && k != [NSObject class]; k = class_getSuperclass(k)) [chain addObject:NSStringFromClass(k)];
    SCPLog("DIAG %@: %@ | ivars: %@", tag, [chain componentsJoinedByString:@" < "], SCPIvarNames(c));
    SCPLog("DIAG %@: -%@", tag, SCPMethodNames(c));
    SCPLog("DIAG %@: +%@", tag, SCPMethodNames(object_getClass(c)));
    Class sup = class_getSuperclass(c);
    if (sup && sup != [NSObject class]) {
        SCPLog("DIAG %@ (lop cha %@): ivars %@ | -%@", tag, NSStringFromClass(sup), SCPIvarNames(sup), SCPMethodNames(sup));
    }
}

static void SCPDumpObj(NSString *tag, id obj)
{
    if (!obj) { SCPLog("DIAG %@: nil", tag); return; }
    SCPDumpClass(tag, object_getClass(obj));
    NSString *desc = nil;
    @try { desc = [obj description]; } @catch (NSException *e) { desc = @"(description loi)"; }
    SCPLog("DIAG %@ description: %@", tag, desc.length > 1500 ? [desc substringToIndex:1500] : desc);
}

// Icon dau tien tren man chinh (model cua *IconListView)
static id SCPFirstHomeIcon(UIView *v, int depth)
{
    if (!v || depth > 14) return nil;
    if ([NSStringFromClass([v class]) hasSuffix:@"IconListView"]) {
        id model = SCPTryGet(v, @"model");
        NSArray *lists = SCPTryGet(SCPTryGet(model, @"folder"), @"lists");
        NSArray *icons = ([lists isKindOfClass:[NSArray class]] && lists.count) ? SCPTryGet(lists.firstObject, @"icons") : SCPTryGet(model, @"icons");
        if ([icons isKindOfClass:[NSArray class]] && icons.count) {
            SCPDumpObj(@"icon list view", v);
            SCPDumpObj(@"icon model", model);
            return icons.firstObject;
        }
    }
    for (UIView *c in v.subviews) { id r = SCPFirstHomeIcon(c, depth + 1); if (r) return r; }
    return nil;
}

void SCPDumpAppLibraryOnce(void)
{
    static BOOL done;
    if (done) return;
    done = YES;
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        id lib = SCPTryGet(app, @"sharedApplicationLibrary");
        SCPDumpObj(@"thu vien app (sharedApplicationLibrary)", lib);
        SCPDumpObj(@"cau hinh thu vien", SCPIvar(lib, @"_configuration"));
        NSArray *all = SCPTryGet(lib, @"allInstalledApplications");
        SCPLog("DIAG allInstalledApplications: %lu muc", (unsigned long)[all count]);
        id info = nil;
        for (id i in all) { if (SCPTryGet(i, @"carPlayDeclaration")) { info = i; break; } }
        if (!info) info = all.firstObject;
        SCPDumpObj(@"app info", info);
        SCPDumpObj(@"declaration", SCPTryGet(info, @"carPlayDeclaration"));
        for (NSString *cn in @[@"DashBoard", @"DBDashboardHomeViewController", @"DBIconModel", @"DBIconView", @"DBApplicationIcon",
                               @"SBApplicationIcon", @"FBSApplicationLibraryConfiguration"]) {
            Class c = objc_getClass(cn.UTF8String);
            if (c) SCPDumpClass([@"lop " stringByAppendingString:cn], c);
            else SCPLog("DIAG lop %@: khong co", cn);
        }
        id icon = nil;
        for (UIScene *s in app.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) { icon = SCPFirstHomeIcon(w, 0); if (icon) break; }
            if (icon) break;
        }
        SCPDumpObj(@"icon man chinh", icon);
        SCPDumpObj(@"icon.application", SCPTryGet(icon, @"application"));
        id dashboard = SCPTryGet(app, @"_currentDashboard");
        SCPDumpObj(@"dashboard", dashboard);
    } @catch (NSException *e) { SCPLog("DIAG thu vien app loi %@", e); }
}
