// CarSplash feature contract - shared by the hooks (CarSplash.x) and the settings page
// (Prefs/OMCCarSplashController.m): pref keys, where videos live, Darwin notification names.
// Only macros here, so both the tweak and the prefs bundle can include it.

#import <Foundation/Foundation.h>
#import <rootless.h>

// Key prefix: OMCFeatureEnabled(CS_FEATURE) reads the master switch + carsplashEnabled.
#define CS_FEATURE          @"carsplash"
#define CS_KEY_ENABLED      @"carsplashEnabled"      // BOOL, default YES
#define CS_KEY_VIDEO_NAME   @"carsplashVideoName"    // file name in CS_VIDEOS_DIR
#define CS_KEY_DURATION     @"carsplashDuration"     // seconds 1-30, default 5
#define CS_KEY_PLAY_FULL    @"carsplashPlayFull"     // BOOL, default NO
#define CS_KEY_SCALE_MODE   @"carsplashScaleMode"    // 0 fill, 1 fit
#define CS_KEY_SOUND        @"carsplashSound"        // BOOL, default NO
#define CS_KEY_TAP_TO_SKIP  @"carsplashTapToSkip"    // BOOL, default YES

// Videos the user added; frames extracted by the settings page go to .frames/<video>/.
#define CS_VIDEOS_DIR       ROOT_PATH_NS(@"/var/mobile/Library/OmniCar/CarSplash/Videos")
#define CS_FRAMES_DIR(name) [[CS_VIDEOS_DIR stringByAppendingPathComponent:@".frames"] stringByAppendingPathComponent:(name)]

// CarPlay.app asks SpringBoard to play / stop the soundtrack.
#define CS_NOTIFY_AUDIO_PLAY CFSTR("com.anlai.omnicar/carsplash.audio.play")
#define CS_NOTIFY_AUDIO_STOP CFSTR("com.anlai.omnicar/carsplash.audio.stop")
