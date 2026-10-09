// Speed Bubble (ex CarSpeed) - floating speed + limit bubble fed by the nav app (Vietmap Live, GOFA).
#pragma once
#import "SpeedBubble.h"
#import "OmniCar.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// Logs go through Core: OmniCar.log, relayed to SpringBoard from the sandboxed nav apps.
#define SPPLogWrite(...) OMCLogWrite(@"SpeedBubble", __VA_ARGS__)
#define SPPLog(fmt, ...) SPPLogWrite([NSString stringWithFormat:@fmt, ##__VA_ARGS__])

// App dan duong ho tro (thu tu = chi so app gui trong Darwin state; them app moi thi them CUOI danh sach + CarSpeed.plist)
#define SPP_APP_VIETMAP         @"vn.vietmap.live"
#define SPP_APP_GOFA            @"com.lumi.GOFA"
#define SPP_NAV_APPS            (@[SPP_APP_VIETMAP, SPP_APP_GOFA])
#define SPP_NAV_APP_NAMES       (@[@"Vietmap", @"GOFA"])
#define SPP_NAV_APP_COUNT       2

static inline int SPPNavAppIndex(NSString *bid)
{
    NSUInteger i = bid ? [SPP_NAV_APPS indexOfObject:bid] : NSNotFound;
    return i == NSNotFound ? -1 : (int)i;
}
static inline NSString *SPPNavAppBundle(int i) { return (i >= 0 && i < SPP_NAV_APP_COUNT) ? SPP_NAV_APPS[i] : SPP_APP_VIETMAP; }
static inline NSString *SPPNavAppName(int i)   { return (i >= 0 && i < SPP_NAV_APP_COUNT) ? SPP_NAV_APP_NAMES[i] : @"?"; }

// App dan duong -> SpringBoard: toc do hien tai + gioi han (Darwin notify; state = flags<<16 | speed<<8 | limit)
// flags: bit 0 = co toc do, bit 1 = co gioi han, bit 2 = app dang hien (iPhone / CarPlay), bit 3..5 = chi so app
#define SPP_DARWIN_SPEED        SB_DARWIN_SPEED
// Cai dat -> SpringBoard: xem thu bong bong / cau hinh vua doi
#define SPP_DARWIN_DEMO         SB_DARWIN_DEMO
#define SPP_DARWIN_PREFS        SB_DARWIN_PREFS
#define SPP_DARWIN_RESET        SB_DARWIN_RESET   // dat lai vi tri + kich thuoc bong bong
// SpringBoard -> process CarPlay: mo app dan duong tren man xe (cham bong bong); state = chi so app
#define SPP_DARWIN_OPEN_CAR     SB_DARWIN_OPEN_CAR

#define objcInvokeT(a, b, t)            ((t (*)(id, SEL))objc_msgSend)(a, NSSelectorFromString(b))
#define objcInvoke(a, b)                objcInvokeT(a, b, id)
#define objcInvoke_1(a, b, c)           ((id (*)(id, SEL, __typeof__(c)))objc_msgSend)(a, NSSelectorFromString(b), c)
#define objcInvoke_2(a, b, c, d)        ((id (*)(id, SEL, __typeof__(c), __typeof__(d)))objc_msgSend)(a, NSSelectorFromString(b), c, d)

