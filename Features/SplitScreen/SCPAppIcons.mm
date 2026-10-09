#import "SCPAppIcons.h"

// =====================================================================
//  Icon app iPhone tren man chinh CarPlay. Buoc 1 (ban nay): chan doan cau truc thu vien app cua CarPlay 16.5
//  (CarPlayUIServices / DashBoard) qua log, vi khong co header. Buoc 2: chen CARApplicationInfo gia cho app iPhone.
// =====================================================================

static NSMutableSet<NSString *> *sInjected;

BOOL SCPIsInjectedPhoneApp(NSString *bid)
{
    return bid && [sInjected containsObject:bid];
}

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

static id SCPTryGet(id obj, NSString *sel)
{
    if (!obj || ![obj respondsToSelector:NSSelectorFromString(sel)]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel)); } @catch (NSException *e) { return nil; }
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
        for (NSString *cn in @[@"CARApplication", @"CARApplicationLibrary", @"CARApplicationInfo", @"CARApplicationDeclaration",
                               @"CARApplicationLaunchInfo", @"DBApplicationLibrary", @"DBApplicationInfo", @"DBApplicationLaunchInfo",
                               @"DBDashboard", @"DBIconModel", @"DBApplicationIcon", @"DBIconController", @"SBIconModel"]) {
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
