// Split Screen feature contract - shared by the hooks (SCPPrefs.mm, SCPCarSplit.mm, *.xm), the
// settings page (Prefs/OMCSplitScreenController.m, OMCSplitScreenAppPicker.m) and the companion app
// (App/main.m): pref keys and notification names. Only macros here, so the tweak (ObjC++), the prefs
// bundle and the app can all include it.
//
// Two or three CarPlay apps side by side on the car screen was the standalone CarDuo tweak; its SCP*
// code lives in this folder mostly unchanged (split runs inside the CarPlay process, SpringBoard
// only relays URL requests and places the CarBridge window).

#pragma once

// Key prefix: OMCFeatureEnabled(SPL_FEATURE) reads the master switch + splitScreenEnabled.
#define SPL_FEATURE              @"splitScreen"
#define SPL_KEY_ENABLED          @"splitScreenEnabled"          // BOOL, default YES
#define SPL_KEY_AUTO_LAUNCH      @"splitScreenAutoLaunch"       // BOOL, default NO: reopen the last split on connect
#define SPL_KEY_SHOW_RECENT      @"splitScreenShowRecent"       // BOOL, default YES: Recent section of the dock button panel
#define SPL_KEY_SHOW_FAVORITES   @"splitScreenShowFavorites"    // BOOL, default YES: Favorites section
#define SPL_KEY_TIP_COUNT        @"splitScreenTipCount"         // tips shown on the car screen so far (max 3)
#define SPL_KEY_PANE_ORIENTATION @"splitScreenPaneOrientation"  // 1 portrait, 3 landscape
#define SPL_KEY_SPLIT_RATIO      @"splitScreenSplitRatio"       // 0.2..0.8, width of the first pane
#define SPL_KEY_SPLIT_DIRECTION  @"splitScreenSplitDirection"   // 0 left/right, 1 top/bottom
#define SPL_KEY_LAST_LEFT        @"splitScreenLastLeft"         // last pair used on the car (reopened on connect)
#define SPL_KEY_LAST_RIGHT       @"splitScreenLastRight"
#define SPL_KEY_CARPLAY_APPS     @"splitScreenCarPlayApps"      // written by the CarPlay process for the app picker
#define SPL_KEY_CARBRIDGE_APPS   @"splitScreenCarBridgeApps"
#define SPL_KEY_RECENT_LAYOUTS   @"splitScreenRecentLayouts"    // @[ @{layout, apps}, ... ] newest first, max 3
#define SPL_KEY_PAIR_RATIOS      @"splitScreenPairRatios"       // @{ "left|right": ratio }
// Favorite layouts 1..3: splitScreenFav<n>Name / Layout (2, 3, 13, 31) / Left / Right / Third
#define SPL_KEY_FAV(n, part)     ([NSString stringWithFormat:@"splitScreenFav%ld%@", (long)(n), part])

// Companion app (omnicar://<feature>/<action>?...) -> SpringBoard, distributed notification, userInfo @{url}.
// Split Screen handles omnicar://splitscreen/open?left=..&right=.. | fav?n=1..3 | close | picker
#define OMC_URL_NOTIFY           @"com.anlai.omnicar/url"
#define SPL_URL_HOST             @"splitscreen"

// SpringBoard -> CarPlay process: open / change the split (action = open | pair | picker | close | fav | closeApp;
// identifier, slot, left, right, index)
#define SPL_NOTIF_NATIVE         @"com.anlai.omnicar/splitscreen.native"
// CarPlay process -> SpringBoard: place the CarBridge CBWindow on a pane (identifier, x, y, w, h; w=0 hides it)
#define SPL_NOTIF_CBFRAME        @"com.anlai.omnicar/splitscreen.cbframe"
// SpringBoard -> CarPlay process: CarBridge closed its CBWindow (identifier) -> bridge the app again
#define SPL_NOTIF_CBLOST         @"com.anlai.omnicar/splitscreen.cblost"
// SpringBoard -> CarPlay process: the "•••" handle SpringBoard draws over the CarBridge window was tapped
// (identifier) -> show that pane's button bar
#define SPL_NOTIF_HANDLE_TAP     @"com.anlai.omnicar/splitscreen.handletap"
// CarPlay process -> SpringBoard: [x] on a pane -> terminate the app (identifier)
#define SPL_NOTIF_KILL           @"com.anlai.omnicar/splitscreen.kill"
// CarPlay process -> SpringBoard: request received (ACK) / car screen just appeared (READY: resend a held request)
#define SPL_NOTIF_ACK            @"com.anlai.omnicar/splitscreen.ack"
#define SPL_NOTIF_READY          @"com.anlai.omnicar/splitscreen.ready"
