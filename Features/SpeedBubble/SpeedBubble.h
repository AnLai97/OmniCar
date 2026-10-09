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
#define SB_KEY_APP_VIETMAP   @"speedBubbleAppVietmap"    // BOOL, default YES
#define SB_KEY_APP_GOFA      @"speedBubbleAppGOFA"       // BOOL, default YES

// Nav app -> SpringBoard: speed + limit (notify state = flags<<16 | speed<<8 | limit).
#define SB_DARWIN_SPEED      "com.anlai.omnicar/speedbubble.speed"
// Settings -> SpringBoard: preview the bubble / reset its position and size.
#define SB_DARWIN_DEMO       "com.anlai.omnicar/speedbubble.demo"
#define SB_DARWIN_RESET      "com.anlai.omnicar/speedbubble.resetlayout"
// Any pref change (posted by every stored cell of the settings bundle) -> redraw.
#define SB_DARWIN_PREFS      "com.anlai.omnicar/prefschanged"
// SpringBoard -> CarPlay process: open the nav app on the car screen (state = app index).
#define SB_DARWIN_OPEN_CAR   "com.anlai.omnicar/speedbubble.opencar"
