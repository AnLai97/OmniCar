// Speed Bubble (ex CarSpeed) - floating speed + limit bubble fed by the nav app (Vietmap Live, GOFA, Waze, Wyn).
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

// App dan duong ho tro (thu tu = chi so app gui trong Darwin state; them app moi thi them CUOI danh sach + Filter.plist
// + ten vao SB_SOURCE_NAMES trong SpeedBubble.h). Toi da 8 (3 bit trong Darwin state).
#define SPP_APP_VIETMAP         @"vn.vietmap.live"
#define SPP_APP_GOFA            @"com.lumi.GOFA"
// Waze: toc do tu GPS rieng trong app, gioi han quet tren man hinh (vong do / ten anh / chu); chi quet khi app la nguon
// dang chon (SPP_DARWIN_SOURCE) vi gan nhu may nao cung co.
#define SPP_APP_WAZE            @"com.waze.iphone"
// Wyn (WYN Auto, Flutter "Runner" nhu Vietmap): toc do tu GPS rieng, gioi han tu cay accessibility / kenh Flutter.
// Chua biet kenh nao co toc do -> nghe moi kenh (SPPListenAllChannels) va ghi ten kenh + method lan dau ra log.
#define SPP_APP_WYN             @"com.wynauto.wyn"
#define SPP_APP_INDEX_WYN       3
#define SPP_NAV_APPS            (@[SPP_APP_VIETMAP, SPP_APP_GOFA, SPP_APP_WAZE, SPP_APP_WYN])
#define SPP_NAV_APP_NAMES       (@[@"Vietmap", @"GOFA", @"Waze", @"Wyn"])
#define SPP_NAV_APP_COUNT       4
// Nguon dang chon de app quet biet (app sandbox khong doc duoc prefs): SpringBoard dat state = chi so SB_KEY_SOURCE,
// 0xFF = Bong bong toc do dang tat. App tu index SPP_FIRST_GATED_APP tro di chi quet khi state = chinh no.
#define SPP_DARWIN_SOURCE       "com.anlai.omnicar/speedbubble.source"
#define SPP_FIRST_GATED_APP     2

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

// Private API calls, checked like Split Screen / App Bridge: a missing method (other iOS) is logged once and
// gives nil / 0 instead of "unrecognized selector". objcCall_1 is for void methods (objcInvoke on a void
// method makes ARC release garbage).
#define objcInvokeT(a, b, t) ({ id _o = (a); SEL _s = NSSelectorFromString(b); t _r = {}; if ([_o respondsToSelector:_s]) _r = ((t (*)(id, SEL))objc_msgSend)(_o, _s); else OMCMissingSelector(@"SpeedBubble", _o, b); _r; })
#define objcInvoke(a, b) objcInvokeT(a, b, id)
#define objcInvoke_1(a, b, c) ({ id _o = (a); SEL _s = NSSelectorFromString(b); id _r = nil; if ([_o respondsToSelector:_s]) _r = ((id (*)(id, SEL, __typeof__(c)))objc_msgSend)(_o, _s, c); else OMCMissingSelector(@"SpeedBubble", _o, b); _r; })
#define objcInvoke_2(a, b, c, d) ({ id _o = (a); SEL _s = NSSelectorFromString(b); id _r = nil; if ([_o respondsToSelector:_s]) _r = ((id (*)(id, SEL, __typeof__(c), __typeof__(d)))objc_msgSend)(_o, _s, c, d); else OMCMissingSelector(@"SpeedBubble", _o, b); _r; })
#define objcCall_1(a, b, c) ({ id _o = (a); SEL _s = NSSelectorFromString(b); if ([_o respondsToSelector:_s]) ((void (*)(id, SEL, __typeof__(c)))objc_msgSend)(_o, _s, c); else OMCMissingSelector(@"SpeedBubble", _o, b); })

