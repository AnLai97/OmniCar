// App Bridge - runtime helpers (carplay-cast style) for the SpringBoard host.
#pragma once
#import "AppBridge.h"
#import "OmniCar.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#define ABLog(fmt, ...) OMCLogWrite(@"AppBridge", [NSString stringWithFormat:@fmt, ##__VA_ARGS__])

// Private API calls. objcInvoke* return an object (nil when the method is missing, logged once);
// objcCall* are for void methods; objcInvokeT for scalars / structs.
#define ABSel(b) NSSelectorFromString(b)
#define objcInvokeT(a, b, t) ({ id _o = (a); SEL _s = ABSel(b); t _r = {};     if ([_o respondsToSelector:_s]) _r = ((t (*)(id, SEL))objc_msgSend)(_o, _s); else ABMissingSelector(_o, b); _r; })
#define objcInvoke(a, b) ({ id _o = (a); SEL _s = ABSel(b); id _r = nil;     if ([_o respondsToSelector:_s]) _r = ((id (*)(id, SEL))objc_msgSend)(_o, _s); else ABMissingSelector(_o, b); _r; })
#define objcInvoke_1(a, b, c) ({ id _o = (a); SEL _s = ABSel(b); id _r = nil;     if ([_o respondsToSelector:_s]) _r = ((id (*)(id, SEL, __typeof__(c)))objc_msgSend)(_o, _s, c); else ABMissingSelector(_o, b); _r; })
#define objcInvoke_2(a, b, c, d) ({ id _o = (a); SEL _s = ABSel(b); id _r = nil;     if ([_o respondsToSelector:_s]) _r = ((id (*)(id, SEL, __typeof__(c), __typeof__(d)))objc_msgSend)(_o, _s, c, d); else ABMissingSelector(_o, b); _r; })
#define objcInvoke_3(a, b, c, d, e) ({ id _o = (a); SEL _s = ABSel(b); id _r = nil;     if ([_o respondsToSelector:_s]) _r = ((id (*)(id, SEL, __typeof__(c), __typeof__(d), __typeof__(e)))objc_msgSend)(_o, _s, c, d, e); else ABMissingSelector(_o, b); _r; })
#define objcCall(a, b) ({ id _o = (a); SEL _s = ABSel(b);     if ([_o respondsToSelector:_s]) ((void (*)(id, SEL))objc_msgSend)(_o, _s); else ABMissingSelector(_o, b); })
#define objcCall_1(a, b, c) ({ id _o = (a); SEL _s = ABSel(b);     if ([_o respondsToSelector:_s]) ((void (*)(id, SEL, __typeof__(c)))objc_msgSend)(_o, _s, c); else ABMissingSelector(_o, b); })

// Object must be an instance of the named class, else raise (caught by the host -> "failed" state)
#define expectClass(obj, clsName) \
    ({ id _o = (obj); \
       if (!_o || ![_o isKindOfClass:objc_getClass(clsName)]) { \
           ABLog("UNEXPECTED %s: got %@ (%s:%d)", clsName, _o, __FILE__, __LINE__); \
           [NSException raise:@"AppBridge" format:@"expected %s got %@", clsName, _o]; \
       } _o; })

#ifdef __cplusplus
extern "C" {
#endif
void ABMissingSelector(id obj, NSString *sel);
#ifdef __cplusplus
}
#endif
