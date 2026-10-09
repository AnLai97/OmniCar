// Startup Screen feature contract - shared by the hooks (StartupScreen.x) and the settings page
// (Prefs/OMCStartupScreenController.m): pref keys, where videos live, Darwin notification names.
// Only macros here, so both the tweak and the prefs bundle can include it.

#import <Foundation/Foundation.h>
#import <rootless.h>

// Key prefix: OMCFeatureEnabled(SS_FEATURE) reads the master switch + startupScreenEnabled.
#define SS_FEATURE          @"startupScreen"
#define SS_KEY_ENABLED      @"startupScreenEnabled"      // BOOL, default YES
#define SS_KEY_VIDEO_NAME   @"startupScreenVideoName"    // file name in SS_VIDEOS_DIR
#define SS_KEY_DURATION     @"startupScreenDuration"     // seconds 1-30, default 5
#define SS_KEY_PLAY_FULL    @"startupScreenPlayFull"     // BOOL, default NO
#define SS_KEY_SCALE_MODE   @"startupScreenScaleMode"    // 0 fill, 1 fit
#define SS_KEY_SOUND        @"startupScreenSound"        // BOOL, default NO
#define SS_KEY_TAP_TO_SKIP  @"startupScreenTapToSkip"    // BOOL, default YES

// Videos the user added; frames extracted by the settings page go to .frames/<video>/.
#define SS_VIDEOS_DIR       ROOT_PATH_NS(@"/var/mobile/Library/OmniCar/StartupScreen/Videos")
#define SS_FRAMES_DIR(name) [[SS_VIDEOS_DIR stringByAppendingPathComponent:@".frames"] stringByAppendingPathComponent:(name)]

// CarPlay.app asks SpringBoard to play / stop the soundtrack.
#define SS_NOTIFY_AUDIO_PLAY CFSTR("com.anlai.omnicar/startupscreen.audio.play")
#define SS_NOTIFY_AUDIO_STOP CFSTR("com.anlai.omnicar/startupscreen.audio.stop")
