// Speed Bubble feature contract - shared by the hooks (SPPPrefs.mm, *.xm) and the settings page
// (Prefs/OMCSpeedBubbleController.m): pref keys and Darwin notification names. Only macros here,
// so both the tweak (ObjC++) and the prefs bundle can include it.
//
// The floating speed bubble (current speed + posted limit from Vietmap Live / GOFA) was the
// standalone CarSpeed tweak; its SPP* code lives in this folder mostly unchanged.

#pragma once

// Key prefix: OMCFeatureEnabled(SB_FEATURE) reads the master switch + speedBubbleEnabled.
#define SB_FEATURE           @"speedBubble"
#define SB_KEY_ENABLED       @"speedBubbleEnabled"       // BOOL, default YES
// Kieu bong bong 0..SB_STYLE_COUNT-1 (SPPStyle trong SPPBubble.mm, ban duyet tools/preview/speedbubble.html). Key moi tu bo
// 9 kieu nay: so cua 18 kieu cu (speedBubbleStyle) khong con nghia, ai cung ve kieu mac dinh Giot kinh.
#define SB_KEY_STYLE         @"speedBubbleLook"
#define SB_STYLE_COUNT       9
#define SB_KEY_SHOW_APP_ICON @"speedBubbleShowAppIcon"   // BOOL, default YES
#define SB_KEY_SIZE_PHONE    @"speedBubbleSizePhone"     // 60..220 %, default 100
#define SB_KEY_SIZE_CAR      @"speedBubbleSizeCar"       // 60..220 %, default 100
#define SB_KEY_UNIT          @"speedBubbleUnit"          // don vi: 0 tu dong theo vung, 1 km/h, 2 mph (app nguon luon gui km/h)
#define SB_KEY_SIGN          @"speedBubbleSign"          // bien gioi han: 0 tu dong theo vung, 1 Vienna (tron vien do), 2 My (chu nhat "SPEED LIMIT")
#define SB_KEY_SOURCE        @"speedBubbleSource"        // nguon toc do duy nhat: 0 Vietmap Live, 1 GOFA, 2 Waze (chi so SPP_NAV_APPS)
// Ban truoc co 6 nguon (2 GPS iPhone, 3 Google Maps, 4 Waze, 5 Apple Maps): lan dau doc sau ban nay, SPPPrefs / Cai dat doi
// 4 -> 2 (Waze), cac so khac ngoai 0..1 -> 0, roi ghi SB_KEY_SOURCE_V2 = YES.
#define SB_KEY_SOURCE_V2     @"speedBubbleSourceV2"
// Ten cac nguon cho danh sach "Nguon" trong Cai dat, cung thu tu SPP_NAV_APPS (common.h): them app dan duong moi
// thi them ten vao CUOI ca hai.
#define SB_SOURCE_NAMES      (@[@"Vietmap Live", @"GOFA", @"Waze"])
// Canh bao qua toc do (chi tren man xe): toc do > gioi han + nguong -> vien do phat sang nhay quanh man CarPlay (nguong am:
// bao tu truoc khi cham gioi han)
#define SB_KEY_WARN_MODE     @"speedBubbleWarnMode"      // 0 tat, 1 canh bao (vien do, im lang), 2 am thanh (vien + 1 tieng ngan, mac dinh)
#define SB_KEY_WARN_OVER     @"speedBubbleWarnOver"      // nguong -10..10 so voi gioi han (am = bao truoc khi cham), mac dinh 5, theo don vi dang hien
// Truoc day moi app 1 cong tac (bat ca hai duoc); chi con doc de chuyen sang SB_KEY_SOURCE khi chua co
#define SB_KEY_APP_VIETMAP   @"speedBubbleAppVietmap"    // BOOL, default YES
#define SB_KEY_APP_GOFA      @"speedBubbleAppGOFA"       // BOOL, default YES

// Nav app -> SpringBoard: speed + limit (notify state = flags<<16 | speed<<8 | limit).
#define SB_DARWIN_SPEED      "com.anlai.omnicar/speedbubble.speed"
// SpringBoard -> tinh nang khac (hien chua ai nghe): toc do hien tai cua nguon dang chon (moi nguon, ke ca
// moi nguon). state = toc do km/h (0..255), 0xFFFF = khong biet (mat nguon / so cu qua 5 giay). Chi gui khi doi;
// nguoi nghe doc notify_get_state luc bat dau (gia tri cuoi van con). Toc do gia cua "Xem thu" khong gui.
#define SB_DARWIN_SPEED_NOW  "com.anlai.omnicar/speed"
#define SB_SPEED_UNKNOWN     0xFFFF
// Settings -> SpringBoard: preview the bubble / reset its position and size.
#define SB_DARWIN_DEMO       "com.anlai.omnicar/speedbubble.demo"
#define SB_DARWIN_RESET      "com.anlai.omnicar/speedbubble.resetlayout"
// Any pref change (posted by every stored cell of the settings bundle) -> redraw.
#define SB_DARWIN_PREFS      "com.anlai.omnicar/prefschanged"
// SpringBoard -> CarPlay process: open the nav app on the car screen (state = app index).
#define SB_DARWIN_OPEN_CAR   "com.anlai.omnicar/speedbubble.opencar"
