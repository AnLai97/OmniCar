// Startup Screen feature contract - shared by the hooks (StartupScreen.x), the car-screen renderer
// (SSStartupView.m, also built into the settings bundle) and the settings page
// (Prefs/OMCStartupScreenController.m): pref keys, where files live, Darwin notification names.
// Only macros here, so both the tweak and the prefs bundle can include it.

#import <Foundation/Foundation.h>
#import <rootless.h>

// Key prefix: OMCFeatureEnabled(SS_FEATURE) reads the master switch + startupScreenEnabled.
#define SS_FEATURE          @"startupScreen"
#define SS_KEY_ENABLED      @"startupScreenEnabled"      // BOOL, default YES
#define SS_KEY_STYLE        @"startupScreenStyle"        // SS_STYLE_*, default SS_STYLE_VIDEO
#define SS_KEY_VIDEO_NAME   @"startupScreenVideoName"    // file name in SS_VIDEOS_DIR
#define SS_KEY_DURATION     @"startupScreenDuration"     // seconds 1-30, default 5 (every style)
#define SS_KEY_PLAY_FULL    @"startupScreenPlayFull"     // BOOL, default NO (Video style)
#define SS_KEY_SCALE_MODE   @"startupScreenScaleMode"    // 0 fill, 1 fit (Video style)
#define SS_KEY_SOUND        @"startupScreenSound"        // BOOL, default NO: play the video's own audio (Video style)
#define SS_KEY_TAP_TO_SKIP  @"startupScreenTapToSkip"    // BOOL, default YES (every style)
#define SS_KEY_LOGO_EFFECT  @"startupScreenLogoEffect"   // SS_EFFECT_*, default SS_EFFECT_FADE (Logo style)
#define SS_KEY_GREET_NAME   @"startupScreenGreetingName" // string, "" = no name (Greeting / Weather style)
// Startup sound, any style: file name in SS_SOUNDS_DIR ("" / missing = none). In the Video style the
// video's own audio (SS_KEY_SOUND) wins when it is on and the video has a soundtrack.
#define SS_KEY_SOUND_FILE   @"startupScreenSoundFile"
#define SS_KEY_SOUND_VOLUME @"startupScreenSoundVolume"  // 0-100, default 100 (startup sound and video audio)
#define SS_KEY_SOUND_NO_CALL @"startupScreenSoundSkipCall" // BOOL, default YES: stay silent during a phone call

// Styles (SS_KEY_STYLE).
#define SS_STYLE_VIDEO      0   // the chosen video as a flipbook (the original behaviour)
#define SS_STYLE_LOGO       1   // the user's PNG on a dark background, with SS_KEY_LOGO_EFFECT
#define SS_STYLE_GREETING   2   // "Good morning, <name>" + time + date, colors by time of day
#define SS_STYLE_WEATHER    3   // Open-Meteo current weather; falls back to the greeting without data

// Logo effects (SS_KEY_LOGO_EFFECT).
#define SS_EFFECT_FADE      0
#define SS_EFFECT_ZOOM      1
#define SS_EFFECT_GLOW      2

// Everything the feature keeps on disk.
#define SS_DATA_DIR         ROOT_PATH_NS(@"/var/mobile/Library/OmniCar/StartupScreen")
// Videos the user added; frames extracted by the settings page go to .frames/<video>/.
#define SS_VIDEOS_DIR       ROOT_PATH_NS(@"/var/mobile/Library/OmniCar/StartupScreen/Videos")
#define SS_FRAMES_DIR(name) [[SS_VIDEOS_DIR stringByAppendingPathComponent:@".frames"] stringByAppendingPathComponent:(name)]
// The logo (always re-encoded to PNG, at most 1024 px) and the startup sound (one file).
#define SS_LOGO_PATH        ROOT_PATH_NS(@"/var/mobile/Library/OmniCar/StartupScreen/Logo/logo.png")
#define SS_SOUNDS_DIR       ROOT_PATH_NS(@"/var/mobile/Library/OmniCar/StartupScreen/Sounds")
// Last Open-Meteo result, written by CarPlay (see SSWeatherParse in SSStartupView.h for the keys).
#define SS_WEATHER_CACHE    ROOT_PATH_NS(@"/var/mobile/Library/OmniCar/StartupScreen/weather.plist")

// CarPlay.app asks SpringBoard to play / stop the soundtrack or startup sound.
#define SS_NOTIFY_AUDIO_PLAY CFSTR("com.anlai.omnicar/startupscreen.audio.play")
#define SS_NOTIFY_AUDIO_STOP CFSTR("com.anlai.omnicar/startupscreen.audio.stop")
