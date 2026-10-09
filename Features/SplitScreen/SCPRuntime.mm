#import "common.h"

// objcInvoke* / objcCall* (common.h) land here when the object lacks the method: log once per
// class + selector instead of crashing with "unrecognized selector".
void SCPMissingSelector(id obj, NSString *sel)
{
    if (!obj) return;   // goi tren nil la binh thuong (chua co doi tuong), khong can log
    static NSMutableSet<NSString *> *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    NSString *key = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([obj class]), sel];
    @synchronized (seen) {
        if ([seen containsObject:key]) return;
        [seen addObject:key];
    }
    SCPLog("THIEU METHOD: %@ khong co %@ -> bo qua", NSStringFromClass([obj class]), sel);
}
