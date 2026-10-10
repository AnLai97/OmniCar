#import "SCPAppIcons.h"

// =====================================================================
//  Icon app iPhone tren man chinh CarPlay (iOS 16, theo carplay-cast nhanh ios16).
//  DashBoard chi ve icon cho DBApplicationInfo co _carPlayDeclaration. +[DashBoard _newApplicationLibrary] goc chi
//  gom app CarPlay; hook (AppIcons.xm) thay bang SCPNewLibraryWithPhoneApps(): FBSApplicationLibrary gom moi app,
//  roi SCPAddPhoneAppDeclarations() gan CRCarPlayAppDeclaration gia (khong template, "supportsMaps" de DashBoard
//  mo nhu app UIKit) cho app trong AB_KEY_APPS. Tag "OmniCarAppBridge" danh dau app da chen.
// =====================================================================

#define SCP_INJECT_TAG @"OmniCarAppBridge"

static NSMutableSet<NSString *> *sInjected;
static NSSet<NSString *> *sBuiltChosen;   // danh sach chon luc gan declaration lan cuoi (de biet prefschanged co doi gi khong)
static __weak id sHomeVC;

BOOL SCPIsInjectedPhoneApp(NSString *bid)
{
    return bid && [sInjected containsObject:bid];
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

void SCPAddPhoneAppDeclarations(id library)
{
    NSSet *chosen = SCPChosenPhoneApps();
    NSMutableSet *injected = [NSMutableSet set];
    sBuiltChosen = chosen;
    Class Decl = objc_getClass("CRCarPlayAppDeclaration");
    if (!Decl) { SCPLog("AppIcons: khong co lop CRCarPlayAppDeclaration"); sInjected = injected; return; }
    NSArray *all = SCPTryGet(library, @"allInstalledApplications");
    NSUInteger kept = 0;
    for (id info in all) {
        NSString *bid = SCPTryGet(info, @"bundleIdentifier");
        if (!bid.length) continue;
        NSArray *tags = SCPTryGet(info, @"tags");
        if ([tags containsObject:SCP_INJECT_TAG]) {   // da chen tu lan truoc (DashBoard goi lai sau khi cai / go app)
            if ([chosen containsObject:bid]) { [injected addObject:bid]; kept++; }
            continue;
        }
        if (![chosen containsObject:bid] || SCPIvar(info, @"_carPlayDeclaration")) continue;   // app CarPlay that: de yen
        id decl = [[Decl alloc] init];
        objcCall_1(decl, @"setSupportsTemplates:", (BOOL)NO);   // khong template: CarPlayTemplateUIHost se khong tim template roi sap
        objcCall_1(decl, @"setSupportsMaps:", (BOOL)YES);
        objcCall_1(decl, @"setBundleIdentifier:", bid);
        // iOS 16.5: _bundlePath la NSString (DIAG), carplay-cast truyen NSURL -> DashBoard goi method chuoi len NSURL -> sap
        id bundleURL = SCPTryGet(info, @"bundleURL");
        NSString *bundlePath = [bundleURL isKindOfClass:[NSURL class]] ? [(NSURL *)bundleURL path] : ([bundleURL isKindOfClass:[NSString class]] ? bundleURL : nil);
        if (bundlePath) objcCall_1(decl, @"setBundlePath:", bundlePath);
        if (!SCPSetIvar(info, @"_carPlayDeclaration", decl)) continue;
        NSArray *newTags = [@[SCP_INJECT_TAG] arrayByAddingObjectsFromArray:[tags isKindOfClass:[NSArray class]] ? tags : @[]];
        SCPSetIvar(info, @"_tags", newTags);
        [injected addObject:bid];
        SCPLog("AppIcons: chen %@: valid=%d hidden=%d installed=%d fullScreen=%d path=%@", bid,
               objcInvokeT(info, @"isValid", BOOL), objcInvokeT(info, @"isHidden", BOOL), objcInvokeT(info, @"isInstalled", BOOL),
               objcInvokeT(info, @"presentsFullScreen", BOOL), bundlePath);
    }
    sInjected = injected;
    SCPLog("AppIcons: %lu app iPhone tren man chinh (%lu moi, %lu da co), %lu app chon",
           (unsigned long)injected.count, (unsigned long)(injected.count - kept), (unsigned long)kept, (unsigned long)chosen.count);
}

// ---------------------------------------------------------------------
//  Cau dao chong crash-loop: ghi "dang chen" vao prefs truoc khi thay thu vien, xoa khi man xe hien (carScreenAppeared).
//  Lan khoi dong sau ma con "dang chen" = CarPlay sap sau khi chen -> ghi version bi sap, khong chen nua cho den khi
//  nguoi dung doi danh sach app (prefschanged) hoac cai ban moi (version khac).
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

id SCPNewLibraryWithPhoneApps(void)
{
    Class Config = objc_getClass("FBSApplicationLibraryConfiguration"), Lib = objc_getClass("FBSApplicationLibrary"),
          Info = objc_getClass("DBApplicationInfo"), Placeholder = objc_getClass("FBSApplicationPlaceholder");
    if (!Config || !Lib || !Info) {
        SCPLog("AppIcons: thieu lop (config %d lib %d info %d)", Config != nil, Lib != nil, Info != nil);
        return nil;
    }
    id config = [[Config alloc] init];
    objcCall_1(config, @"setApplicationInfoClass:", Info);
    if (Placeholder) objcCall_1(config, @"setApplicationPlaceholderClass:", Placeholder);
    objcCall_1(config, @"setAllowConcurrentLoading:", (BOOL)YES);
    BOOL (^filter)(id, NSSet *) = ^BOOL(id appProxy, NSSet *arg2) {
        NSArray *appTags = SCPTryGet(appProxy, @"appTags");
        return ![appTags containsObject:@"hidden"];   // app an (he thong) khong vao thu vien
    };
    objcCall_1(config, @"setInstalledApplicationFilter:", filter);
    id library = objcInvoke_1([Lib alloc], @"initWithConfiguration:", config);
    if (!library) { SCPLog("AppIcons: khong tao duoc FBSApplicationLibrary"); return nil; }
    SCPAddPhoneAppDeclarations(library);
    // App he thong cua CarPlay bi loc "hidden" o tren: them lai nhu thu vien goc (carplay-cast)
    Class Proxy = objc_getClass("LSApplicationProxy");
    for (NSString *ident in @[@"com.apple.CarPlayTemplateUIHost", @"com.apple.MusicUIService", @"com.apple.springboard",
                              @"com.apple.InCallService", @"com.apple.CarPlaySettings", @"com.apple.CarPlayApp",
                              @"com.apple.CarPlayWallpaper"]) {
        id proxy = Proxy ? objcInvoke_1(Proxy, @"applicationProxyForIdentifier:", ident) : nil;
        id state = SCPTryGet(proxy, @"appState");
        if (state && objcInvokeT(state, @"isValid", BOOL)) objcCall_2(library, @"addApplicationProxy:withOverrideURL:", proxy, (id)nil);
    }
    return library;
}

void SCPSetHomeViewController(id vc)
{
    sHomeVC = vc;
}

// Danh sach app chon doi trong Settings: thu vien moi + ve lai man chinh (debounce 0.8s vi moi cong tac mot prefschanged)
void SCPRefreshAppIconsSoon(void)
{
    static NSUInteger gen;
    NSUInteger my = ++gen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (my != gen) return;
        id home = sHomeVC;
        if (!home) return;
        if ([SCPChosenPhoneApps() isEqualToSet:sBuiltChosen ?: [NSSet set]]) return;   // khong doi (prefs khac)
        SCPAppIconsRetry();
        @try {
            Class DashBoard = objc_getClass("DashBoard");
            id lib = DashBoard ? objcInvoke(DashBoard, @"_newApplicationLibrary") : nil;   // qua hook -> co app iPhone
            if (!lib) return;
            objcCall_1(home, @"setLibrary:", lib);
            objcCall(home, @"_handleAppLibraryRefresh");
            SCPLog("AppIcons: ve lai man chinh sau khi doi danh sach app");
        } @catch (NSException *e) { SCPLog("AppIcons: ve lai man chinh loi %@", e); }
    });
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
        NSArray *all = SCPTryGet(lib, @"allInstalledApplications");
        SCPLog("DIAG allInstalledApplications: %lu muc", (unsigned long)[all count]);
        id info = nil;
        for (id i in all) { if (SCPTryGet(i, @"carPlayDeclaration")) { info = i; break; } }
        if (!info) info = all.firstObject;
        SCPDumpObj(@"app info", info);
        SCPDumpObj(@"declaration", SCPTryGet(info, @"carPlayDeclaration"));
        for (NSString *cn in @[@"DashBoard", @"CRCarPlayAppDeclaration", @"DBApplicationInfo", @"DBApplicationLaunchInfo",
                               @"DBDashboardHomeViewController", @"DBDashboard", @"DBIconModel", @"DBIconView",
                               @"FBSApplicationLibrary", @"FBSApplicationLibraryConfiguration"]) {
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
