#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

// Preferences: keys, state bits and defaults live in TikTok.h (shared with the settings page);
// the old TikTokX names are kept as aliases so the hooks below stay unchanged.
#import "TikTok.h"
#define kTTXPrefsChanged     TTK_DARWIN_STATE
#define kTTXStateValid       TTK_STATE_VALID
#define kTTXStateBackground  TTK_STATE_BACKGROUND
#define kTTXStateAutoNext    TTK_STATE_AUTO_NEXT
#define kTTXStateRemoteScroll TTK_STATE_REMOTE_SCROLL
#define kTTXStateClearDisplay TTK_STATE_CLEAR_DISPLAY
#define kTTXStateEnabled     TTK_STATE_ENABLED
#define kTTXDefaultEnabled         TTK_DEFAULT_ENABLED
#define kTTXDefaultBackgroundAudio TTK_DEFAULT_BACKGROUND_AUDIO
#define kTTXDefaultAutoNext        TTK_DEFAULT_AUTO_NEXT
#define kTTXDefaultRemoteScroll    TTK_DEFAULT_REMOTE_SCROLL
#define kTTXDefaultClearDisplay    TTK_DEFAULT_CLEAR_DISPLAY

// TikTok private classes
@interface AWEPlayVideoPlayerController : NSObject
@property (nonatomic, weak) UIViewController *container;
@end

@interface AWENewFeedTableViewController : UIViewController
- (void)scrollToNextVideo;
@end
