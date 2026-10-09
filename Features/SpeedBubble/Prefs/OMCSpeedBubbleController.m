#import "OMCSpeedBubbleController.h"
#import "OMCTheme.h"
#import "../SpeedBubble.h"
#import <notify.h>

@implementation OMCSpeedBubbleController

#pragma mark - Actions
// Darwin notifications handled by SpringBoard (../SpringBoard.xm).

// Show the bubble for 10 seconds.
- (void)bubbleDemo {
	notify_post(SB_DARWIN_DEMO);
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

// Default position, 100% size. SpringBoard writes the sizes back to 100, so re-read the sliders.
- (void)resetLayout {
	notify_post(SB_DARWIN_RESET);
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		CFPreferencesAppSynchronize(kPrefsDomain);
		[weakSelf reloadSpecifiers];
	});
}

@end
