// App Bridge feature contract - shared by the SpringBoard host (ABHost.mm, SpringBoard.xm), the
// Split Screen feature (its CarPlay side sends pane frames here) and the settings page. Only macros.
//
// App Bridge shows iPhone apps (no CarPlay interface) on the car screen the way carplay-cast does:
// SpringBoard creates the app's scene (SBAppViewController) inside its own window on the car display
// and lays it out at the frame CarPlay asks for, so a pane can be resized live and several apps can
// be shown at once. It replaces CarBridge for Split Screen.

#pragma once
#import <Foundation/Foundation.h>   // ABBundleHash below (every includer is Objective-C)

// Key prefix: OMCFeatureEnabled(AB_FEATURE) reads the master switch + appBridgeEnabled.
#define AB_FEATURE           @"appBridge"
#define AB_KEY_ENABLED       @"appBridgeEnabled"     // BOOL, default YES
// The app renders at (pane size / zoom) and is scaled down by zoom, so iPhone text and buttons do not
// look huge on the car screen. 60..100 %, default 80.
#define AB_KEY_ZOOM          @"appBridgeZoom"
// The iPhone apps the user picked for the car screen (root page "Apps" > "Apps on the car screen",
// Prefs/OMCAppBridgeAppsController.m, which also holds the switch and zoom above - App Bridge has no feature
// page of its own): NSArray of bundle ids, user apps and system apps alike. Only these are offered as iPhone
// apps on CarPlay - home screen icons (SCPAppIcons) and the iPhone-app section of Split Screen's box picker
// (on the car and in Settings). Unset / empty = no iPhone app on the car.
#define AB_KEY_APPS          @"appBridgeApps"

// CarPlay process -> SpringBoard (distributed notifications, userInfo keys):
//   OPEN     identifier, x, y, w, h (car-screen points): host the app at that frame; already hosted -> frame update
//   FRAME    identifier, x, y, w, h, live (0/1), handle (0/1): move / resize. live = 1 only moves the box (while a
//            divider is dragged); live = 0 also resizes the app's scene. w < 2 hides the box. handle = 1 draws a
//            translucent "•••" pill at the top of the box (CarPlay's own pill is under the window).
//            pt, pl, pb, pr (optional, points): touches within that distance of the box edge fall through to
//            CarPlay (divider drags along edges shared with another pane).
//            bar (0/1): SpringBoard draws the pane's button bar (change app, float/dock, full screen, close) over the
//            app, under the "•••" pill; a CarPlay-drawn bar could never show above the host window. pop = 1 float
//            glyph, 2 dock glyph; popDim = 1 draws the float button dimmed (tap still reports). Also on OPEN.
//            r, corners (optional): corner radius and CACornerMask of the CarPlay pane under the box, so the
//            hosted app is clipped exactly like a native pane (12 pt on the corners shared with another pane).
//   CLOSE    identifier, terminate (0/1): remove the app from the car screen (and quit it)
//   CLOSEALL except (optional bundle id kept, e.g. the app that is becoming full screen)
#define AB_NOTIF_OPEN        @"com.anlai.omnicar/appbridge.open"
#define AB_NOTIF_FRAME       @"com.anlai.omnicar/appbridge.frame"
#define AB_NOTIF_CLOSE       @"com.anlai.omnicar/appbridge.close"
#define AB_NOTIF_CLOSEALL    @"com.anlai.omnicar/appbridge.closeall"
// SpringBoard -> CarPlay process: identifier, state = "ready" (app is on screen) | "failed" (could not host) |
// "gone" (the app quit / its scene was destroyed)
#define AB_NOTIF_STATE       @"com.anlai.omnicar/appbridge.state"
// SpringBoard -> CarPlay process: the "•••" pill over the hosted app was tapped (identifier)
#define AB_NOTIF_HANDLE_TAP  @"com.anlai.omnicar/appbridge.handletap"
// Dragging the "•••" handle SpringBoard draws over an iPhone app (swap panes / move the floating window): phase 0 began,
// 1 moved, 2 ended, 3 cancelled; x / y in car-screen points. CarPlay runs the same drag as for its own panes.
#define AB_NOTIF_HANDLE_DRAG @"com.anlai.omnicar/appbridge.handledrag"
// CarPlay process -> SpringBoard: the split's divider knobs (knobs = array of @[x, y, active, dividerIndex] in car-screen points,
// empty = none). The host window sits above CarPlay and would hide a knob next to an iPhone-app box, so SpringBoard
// draws the same knobs on top of its window. A touch on such a knob lands in SpringBoard (never in CarPlay), so the
// knob view takes the touch and relays it with AB_NOTIF_KNOB_TOUCH.
#define AB_NOTIF_KNOBS       @"com.anlai.omnicar/appbridge.knobs"
// SpringBoard -> CarPlay process: a touch on a knob SpringBoard drew (index = divider index, phase = 0 began /
// 1 moved / 2 ended / 3 cancelled, x, y = car-screen points). CarPlay drives the divider as if its own knob was touched.
#define AB_NOTIF_KNOB_TOUCH  @"com.anlai.omnicar/appbridge.knobtouch"
// SpringBoard -> CarPlay process: a button of the bar drawn over the hosted app was tapped
// (identifier, action = replace | pop | full | close)
#define AB_NOTIF_BAR_ACTION  @"com.anlai.omnicar/appbridge.baraction"
// Orientation model (from CarDuo 1.0, which ran YouTube fine): the scene of a hosted app is PORTRAIT by default
// whatever the box shape (a wide box is a wide portrait window), because an app whose main UI is portrait-only
// (YouTube, TikTok) draws sideways in a landscape scene. The app itself may ask for landscape (YouTube full-screen
// video); then the host rotates the scene for it. The app side (App.xm, loaded into apps) never forces an
// orientation the app does not allow.
//   SpringBoard -> app (distributed notification, object = bundle id): orientation = the box's base
//   UIInterfaceOrientation (-1 = no longer hosted), device = the fake device orientation the app should report.
#define AB_NOTIF_ORIENTATION @"com.anlai.omnicar/appbridge.orientation"
//   app -> SpringBoard (Darwin notify with state, gets through the app sandbox): the app just changed what it wants.
//   state = (ABBundleHash(bundle id) << 24) | (supported orientation mask << 8) | code
//   code = the UIInterfaceOrientation the app asks for, 0 = back to the box's orientation, 0xFF = the supported mask
//   changed, SpringBoard derives the orientation from the mask.
#define AB_DARWIN_APP_ORIENT "com.anlai.omnicar/appbridge.apporient"
// Car-screen keyboard: a hosted app's text field has no keyboard on the car (the system one belongs to the phone), so the
// app side (App.xm) gives the focused field an empty inputView and tells SpringBoard, which draws its own keyboard on
// the car screen (ABKeyboard.mm, Telex for Vietnamese) and sends the keys back.
//   app -> SpringBoard (Darwin notify with state): state = (ABBundleHash(bundle id) << 24) | (returnKeyType << 8) |
//   (keyboardType << 1) | show (1 = a field got focus, 0 = it lost it).
//   SpringBoard -> app (distributed notification, object = bundle id): action = type (del = characters to delete
//   first, text = characters to insert: Telex rewrites the word being typed) | return | dismiss.
#define AB_DARWIN_APP_KEYBOARD "com.anlai.omnicar/appbridge.keyboard"
#define AB_NOTIF_KEY         @"com.anlai.omnicar/appbridge.key"
// Keyboard language on the car: 0 English, 1 Vietnamese (Telex). Remembered by SpringBoard.
#define AB_KEY_KEYBOARD_LANG @"appBridgeKeyboardLang"
// Frame rate cap for iPhone apps on the car: 0 none (default), 30, 24. With none, the cap is 30 while Lite mode is on or
// CarPlay is wireless (OMCCarWireless). SpringBoard sends the cap with every AB_NOTIF_ORIENTATION (userInfo "fps",
// 0 = none); the app side (App.xm) caps the app's CADisplayLinks, which drive its animations / scrolling / games
// (video playback runs at the video's own rate).
#define AB_KEY_FPS           @"appBridgeFps"
// CarPlay home screen (Settings: App on the car screen, one page in OMCAppBridgeAppsController.m; car side:
// Features/SplitScreen/SCPHomeScreen.mm). CarPlay's own home screen stays as it is; OmniCar only adds two things to it:
// an icon size (SBIconListGridLayoutConfiguration -iconImageInfo scaled, AppIcons.xm) and a wallpaper view slipped under
// CarPlay's icon grid. At 100 % with no wallpaper nothing is touched. The first builds' own icon grid, app sorting, dock,
// folders, widgets, icon packs and day / night wallpaper were dropped in 10/2026; their homeScreen* keys
// (homeScreenEnabled, homeScreenOrder, homeScreenHidden, homeScreenCols, homeScreenRows, homeScreenNames, homeScreenDock
// ...) are no longer read. Columns / rows / names came back on CarPlay's own grid with the new keys below.
#define HS_KEY_ICON_SIZE     @"homeScreenIconSize"    // 60..130 %, default 100 (icon image size on CarPlay's grid)
// CarPlay's own grid (SBIconListGridLayoutConfiguration numberOf{Portrait,Landscape}{Columns,Rows}, AppIcons.xm): 0 = Auto
// (CarPlay's count). Only the home grid is changed (a config with at least 2 columns and 2 rows), never a 1-row / 1-column dock.
#define HS_KEY_COLS          @"homeScreenGridCols"    // 0 Auto, 3..8
#define HS_KEY_ROWS          @"homeScreenGridRows"    // 0 Auto, 1..4
#define HS_COLS_VALUES       @[@0, @3, @4, @5, @6, @7, @8]
#define HS_ROWS_VALUES       @[@0, @1, @2, @3, @4]
// BOOL, default YES: app names under the icons (-[SBIconView setLabelHidden:], AppIcons.xm)
#define HS_KEY_NAMES         @"homeScreenShowNames"
// [bundle id] CarPlay apps whose icon is left off CarPlay's own home screen (Settings: App on the car screen > CarPlay
// apps tab; car side: -[SBIconModel isIconVisible:] in AppIcons.xm). Only the icon goes: the app still opens by itself
// (a call, directions, Siri). A new key, not the dropped homeScreenHidden of the first builds.
#define HS_KEY_HIDDEN_APPS   @"homeScreenHiddenApps"
// [@{id, name}] the CarPlay apps on CarPlay's home screen, in the car's order, written by the CarPlay process
// (SCPHomeScreen.mm) from the home grid's icon model each time the home screen lays out: includes CarPlay's own icons
// (Now Playing, Settings, the car maker's app) that have no iPhone app proxy, hence the name. Apps OmniCar hides keep
// their place (merged back from the previous list); apps removed in iOS Settings > CarPlay > Customize drop out.
// splitScreenCarPlayApps (SPL_KEY_CARPLAY_APPS) is a different list: only apps Split Screen can put in a pane.
#define HS_KEY_CAR_APPS      @"homeScreenCarApps"
// Apps CarPlay itself never lets you hide (Settings > General > CarPlay > Customize): Phone, Music, Maps, Messages and
// CarPlay's own Now Playing / car (OEM) / Settings icons. OmniCar keeps them too: no switch in Settings, never hidden on
// the car even if HS_KEY_HIDDEN_APPS lists them.
static inline BOOL HSIsLockedCarPlayApp(NSString *bid)
{
    if (![bid isKindOfClass:[NSString class]] || !bid.length) return NO;
    if ([@[@"com.apple.mobilephone", @"com.apple.Music", @"com.apple.Maps", @"com.apple.MobileSMS", @"com.apple.InCallService"] containsObject:bid])
        return YES;
    return [bid hasPrefix:@"com.apple.CarPlay"] || [bid rangeOfString:@"NowPlaying"].location != NSNotFound;
}
#define HS_KEY_WALLPAPER     @"homeScreenWallpaper"   // BOOL: use HS_WALLPAPER_PATH (picked in Settings) as the home wallpaper
#define HS_KEY_WALLPAPER_STYLE @"homeScreenWallpaperStyle" // 0 default, 1..6 built-in picture, 7 the user's photo, 8 the user's video (HS_VIDEO_PATH)
#define HS_KEY_BLUR          @"homeScreenBlur"        // 0..30, default 0
#define HS_KEY_DIM           @"homeScreenDim"         // 0..70 %, default 25
#define HS_WALLPAPER_PATH    [OMC_DATA_ROOT stringByAppendingPathComponent:@"HomeScreen/wallpaper.jpg"]
#define HS_PHOTO_PATH        [OMC_DATA_ROOT stringByAppendingPathComponent:@"HomeScreen/photo.jpg"]   // last photo picked (its own tile)
#define HS_VIDEO_PATH        [OMC_DATA_ROOT stringByAppendingPathComponent:@"HomeScreen/video.mp4"]   // last video picked (≤ 20 s, 1280 px, no sound)
#define HS_VIDEO_THUMB_PATH  [OMC_DATA_ROOT stringByAppendingPathComponent:@"HomeScreen/video.jpg"]   // its first frame (tile, preview)
// A video (style 8) plays muted in a loop and pauses while the phone is hot, Lite mode is on, the screen is split or the
// home screen is covered.
// Base scene orientation for hosted apps: 1 portrait (default), 3 landscape.
#define AB_KEY_ORIENTATION   @"appBridgeOrientation"
static inline unsigned long long ABBundleHash(NSString *bid)
{
    unsigned int h = 2166136261u;
    for (const char *c = bid.UTF8String; c && *c; c++) { h ^= (unsigned char)*c; h *= 16777619u; }
    return h;
}
