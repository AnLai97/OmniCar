// App Bridge feature contract - shared by the SpringBoard host (ABHost.mm, SpringBoard.xm), the
// Split Screen feature (its CarPlay side sends pane frames here) and the settings page. Only macros.
//
// App Bridge shows iPhone apps (no CarPlay interface) on the car screen the way carplay-cast does:
// SpringBoard creates the app's scene (SBAppViewController) inside its own window on the car display
// and lays it out at the frame CarPlay asks for, so a pane can be resized live and several apps can
// be shown at once. It replaces CarBridge for Split Screen.

#pragma once

// Key prefix: OMCFeatureEnabled(AB_FEATURE) reads the master switch + appBridgeEnabled.
#define AB_FEATURE           @"appBridge"
#define AB_KEY_ENABLED       @"appBridgeEnabled"     // BOOL, default YES
// The app renders at (pane size / zoom) and is scaled down by zoom, so iPhone text and buttons do not
// look huge on the car screen. 60..100 %, default 80.
#define AB_KEY_ZOOM          @"appBridgeZoom"
// The iPhone apps the user picked for the car screen (settings page "Apps on the car screen",
// Prefs/OMCAppBridgeAppsController.m): NSArray of bundle ids. Only these are offered as iPhone apps on
// CarPlay - the iPhone-app section of Split Screen's box picker (on the car and in Settings) and, once
// SCPAppIcons injects icons, the home screen. Unset / empty = no iPhone app on the car.
#define AB_KEY_APPS          @"appBridgeApps"
// Apple apps worth bridging besides user-installed ones (other system apps are left out of the list).
#define AB_APPLE_PHONE_APPS  @[@"com.apple.mobilesafari", @"com.apple.mobileslideshow", @"com.apple.tv", \
                               @"com.apple.mobilenotes", @"com.apple.weather", @"com.apple.stocks"]

// CarPlay process -> SpringBoard (distributed notifications, userInfo keys):
//   OPEN     identifier, x, y, w, h (car-screen points): host the app at that frame; already hosted -> frame update
//   FRAME    identifier, x, y, w, h, live (0/1), handle (0/1): move / resize. live = 1 only moves the box (while a
//            divider is dragged); live = 0 also resizes the app's scene. w < 2 hides the box. handle = 1 draws a
//            translucent "•••" pill at the top of the box (CarPlay's own pill is under the window).
//            pt, pl, pb, pr (optional, points): touches within that distance of the box edge fall through to
//            CarPlay (divider drags along edges shared with another pane).
//   CLOSE    identifier, terminate (0/1): remove the app from the car screen (and quit it)
//   CLOSEALL (no keys)
#define AB_NOTIF_OPEN        @"com.anlai.omnicar/appbridge.open"
#define AB_NOTIF_FRAME       @"com.anlai.omnicar/appbridge.frame"
#define AB_NOTIF_CLOSE       @"com.anlai.omnicar/appbridge.close"
#define AB_NOTIF_CLOSEALL    @"com.anlai.omnicar/appbridge.closeall"
// SpringBoard -> CarPlay process: identifier, state = "ready" (app is on screen) | "failed" (could not host) |
// "gone" (the app quit / its scene was destroyed)
#define AB_NOTIF_STATE       @"com.anlai.omnicar/appbridge.state"
// SpringBoard -> CarPlay process: the "•••" pill over the hosted app was tapped (identifier)
#define AB_NOTIF_HANDLE_TAP  @"com.anlai.omnicar/appbridge.handletap"
