// TikTok feature contract (ex TikTokX) - shared by the hooks (TikTok.x) and the settings page
// (Prefs/OMCTikTokController.m): pref keys, defaults, and the notification whose *state* carries
// the switches, because TikTok is sandboxed and cannot read the prefs plist. Only macros and
// static inline helpers here, so both the tweak and the prefs bundle can include it.
//
// Who publishes the state: the settings page on every switch (Prefs/OMCTikTokController.m) and
// the SpringBoard side of TikTok.x on every OmniCar pref change (covers the master switch).

#pragma once
#import <Foundation/Foundation.h>
#import <notify.h>

#define TTK_FEATURE              @"tiktok"
#define TTK_KEY_ENABLED          @"tiktokEnabled"          // BOOL, default YES
#define TTK_KEY_BACKGROUND_AUDIO @"tiktokBackgroundAudio"  // BOOL, default YES
#define TTK_KEY_AUTO_NEXT        @"tiktokAutoNext"         // BOOL, default YES
#define TTK_KEY_REMOTE_SCROLL    @"tiktokRemoteScroll"     // BOOL, default YES
#define TTK_KEY_CLEAR_DISPLAY    @"tiktokClearDisplay"     // BOOL, default NO

// Notification TikTok observes; its state holds the switches (see the bits below).
#define TTK_DARWIN_STATE         "com.anlai.omnicar/tiktok.state"
// TikTok -> SpringBoard: the in-sandbox log file changed, copy it to /var/mobile/Documents.
#define TTK_DARWIN_LOG           "com.anlai.omnicar/tiktok.log"
#define TTK_LOG_NAME             @"OmniCar-TikTok.txt"

// State bits. "Valid" marks a state written by this build; TikTok falls back to defaults without it.
#define TTK_STATE_VALID          (1ULL << 11)
#define TTK_STATE_BACKGROUND     (1ULL << 1)
#define TTK_STATE_AUTO_NEXT      (1ULL << 2)
#define TTK_STATE_REMOTE_SCROLL  (1ULL << 3)
#define TTK_STATE_CLEAR_DISPLAY  (1ULL << 4)
#define TTK_STATE_ENABLED        (1ULL << 6)   // master switch AND tiktokEnabled

#define TTK_DEFAULT_ENABLED          YES
#define TTK_DEFAULT_BACKGROUND_AUDIO YES
#define TTK_DEFAULT_AUTO_NEXT        YES
#define TTK_DEFAULT_REMOTE_SCROLL    YES
#define TTK_DEFAULT_CLEAR_DISPLAY    NO

static inline uint64_t TTKStateFromValues(BOOL enabled, BOOL backgroundAudio, BOOL autoNext, BOOL remoteScroll, BOOL clearDisplay) {
	uint64_t state = TTK_STATE_VALID;
	if (enabled) state |= TTK_STATE_ENABLED;
	if (backgroundAudio) state |= TTK_STATE_BACKGROUND;
	if (autoNext) state |= TTK_STATE_AUTO_NEXT;
	if (remoteScroll) state |= TTK_STATE_REMOTE_SCROLL;
	if (clearDisplay) state |= TTK_STATE_CLEAR_DISPLAY;
	return state;
}

// Write the state and tell TikTok to re-read it.
static inline void TTKPublishState(uint64_t state) {
	int token;
	if (notify_register_check(TTK_DARWIN_STATE, &token) == NOTIFY_STATUS_OK) {
		notify_set_state(token, state);
		notify_cancel(token);
	}
	notify_post(TTK_DARWIN_STATE);
}
