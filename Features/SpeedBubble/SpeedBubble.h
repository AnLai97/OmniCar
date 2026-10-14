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
#define SB_KEY_STYLE         @"speedBubbleStyle"         // 0..17, see SPPBubble.mm
#define SB_KEY_SHOW_APP_ICON @"speedBubbleShowAppIcon"   // BOOL, default YES
#define SB_KEY_SIZE_PHONE    @"speedBubbleSizePhone"     // 60..220 %, default 100
#define SB_KEY_SIZE_CAR      @"speedBubbleSizeCar"       // 60..220 %, default 100
#define SB_KEY_UNIT          @"speedBubbleUnit"          // don vi: 0 tu dong theo vung, 1 km/h, 2 mph (app nguon luon gui km/h)
#define SB_KEY_SIGN          @"speedBubbleSign"          // bien gioi han: 0 tu dong theo vung, 1 Vienna (tron vien do), 2 My (chu nhat "SPEED LIMIT")
#define SB_KEY_SOURCE        @"speedBubbleSource"        // nguon toc do duy nhat: 0 Vietmap Live, 1 GOFA, 2 GPS iPhone (chi so SPP_NAV_APPS)
// Ten cac nguon cho danh sach "Nguon" trong Cai dat, cung thu tu SPP_NAV_APPS (common.h): them app dan duong moi
// thi them ten vao CUOI ca hai. Ten GPS iPhone duoc Cai dat dich lai (SPEEDBUBBLE_SOURCE_GPS).
#define SB_SOURCE_NAMES      (@[@"Vietmap Live", @"GOFA", @"iPhone GPS"])
// Nguon "GPS iPhone": khong phai app - SpringBoard tu doc toc do bang CoreLocation (SPPGPS.mm) khi xe dang ket noi.
// Chi co toc do, KHONG co gioi han (bien hien "--", khong canh bao qua toc do).
#define SB_SOURCE_GPS        2
// SpringBoard ghi lai quyen vi tri cua chinh no (CLAuthorizationStatus: 0 chua hoi, 1 bi han che, 2 bi tu choi,
// 3 luon cho phep, 4 khi dung) de Cai dat bao "GPS iPhone khong dung duoc" (1, 2). Chua co = chua tung bat GPS.
#define SB_KEY_GPS_STATUS    @"speedBubbleGPSStatus"
// Canh bao qua toc do (chi tren man xe): toc do > gioi han + nguong -> vien do phat sang nhay quanh man CarPlay
#define SB_KEY_WARN_MODE     @"speedBubbleWarnMode"      // 0 tat, 1 chi vien (im lang), 2 vien + 1 tieng ngan (mac dinh)
#define SB_KEY_WARN_OVER     @"speedBubbleWarnOver"      // nguong 0..20, mac dinh 5, theo don vi dang hien (km/h hoac mph)
// Truoc day moi app 1 cong tac (bat ca hai duoc); chi con doc de chuyen sang SB_KEY_SOURCE khi chua co
#define SB_KEY_APP_VIETMAP   @"speedBubbleAppVietmap"    // BOOL, default YES
#define SB_KEY_APP_GOFA      @"speedBubbleAppGOFA"       // BOOL, default YES

// Nav app -> SpringBoard: speed + limit (notify state = flags<<16 | speed<<8 | limit).
#define SB_DARWIN_SPEED      "com.anlai.omnicar/speedbubble.speed"
// SpringBoard -> tinh nang khac (vd Che do lai cua Split Screen): toc do hien tai cua nguon dang chon (moi nguon, ke ca
// GPS iPhone). state = toc do km/h (0..255), 0xFFFF = khong biet (mat nguon / so cu qua 5 giay). Chi gui khi doi;
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
