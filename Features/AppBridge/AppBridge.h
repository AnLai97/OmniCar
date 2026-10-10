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
// Hosted apps run as iPad (App.xm reports UIUserInterfaceIdiomPad to the app when it was launched for the car): a wide
// box then gets the real iPad layout (YouTube with its sidebar) instead of a stretched phone layout. SpringBoard sets
// this Darwin notify state to ABBundleHash(bundle id) right before launching the app and clears it 20 s later; an app
// already running in phone mode is terminated first so it relaunches in iPad mode.
#define AB_DARWIN_LAUNCHING  "com.anlai.omnicar/appbridge.launching"
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
// Base scene orientation for hosted apps: 1 portrait (default), 3 landscape.
#define AB_KEY_ORIENTATION   @"appBridgeOrientation"
// The bundled "Web" app (App/Web, com.anlai.omnicar.web): a bare WKWebView with a desktop user agent, for sites whose
// PC layout is wanted on the car (YouTube). Page URL and page zoom in percent (30..150), set on the Apps page.
#define AB_WEB_BUNDLE        @"com.anlai.omnicar.web"
#define AB_KEY_WEB_URL       @"appBridgeWebURL"
#define AB_KEY_WEB_ZOOM      @"appBridgeWebZoom"
#define AB_WEB_DEFAULT_URL   @"https://www.youtube.com"
#define AB_WEB_DEFAULT_ZOOM  60
static inline unsigned long long ABBundleHash(NSString *bid)
{
    unsigned int h = 2166136261u;
    for (const char *c = bid.UTF8String; c && *c; c++) { h ^= (unsigned char)*c; h *= 16777619u; }
    return h;
}
