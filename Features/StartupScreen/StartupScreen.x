// Startup Screen - play a short video over the CarPlay screen while CarPlay is starting.
//
// Runs inside CarPlay.app (com.apple.CarPlayApp). Each time a car connects, a new UIScreen
// (and, depending on the iOS build, a UIWindowScene) is created for the car display. We put a
// high-level window on top of it, play the chosen video for the configured time, then fade it
// out to reveal the CarPlay home screen underneath.
//
// AVFoundation never finishes loading media inside CarPlay.app, so the settings page extracts
// each video into JPEG frames (Videos/.frames/<video>/) and we play those as a flipbook. The
// soundtrack (audio.m4a next to the frames) is played by the same tweak loaded into SpringBoard.
//
// Logs are prefixed with "[OmniCar/StartupScreen]" - filter for it in Console.app to debug.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "OmniCar.h"
#import "StartupScreen.h"

#define SSLog(fmt, ...) OMCLog(@"StartupScreen", fmt, ##__VA_ARGS__)

static const NSTimeInterval kFadeDuration = 0.4;
static const NSTimeInterval kMaxFullPlay  = 60.0;
static const NSUInteger kFrameBufferSize  = 4;
static char kSplashKey;
static char kShownKey;

#pragma mark - Preferences

static NSString *SSVideoName(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *name = OMCPref(SS_KEY_VIDEO_NAME, nil);
	if (name.length && [fm fileExistsAtPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name]]) return name;
	// Fall back to the first video in the folder.
	NSError *error = nil;
	NSArray *files = [[fm contentsOfDirectoryAtPath:SS_VIDEOS_DIR error:&error] sortedArrayUsingSelector:@selector(compare:)];
	if (error) SSLog(@"cannot list %@: %@", SS_VIDEOS_DIR, error);
	for (NSString *file in files) {
		if (![file hasPrefix:@"."]) return file;
	}
	return nil;
}

#pragma mark - Audio (SpringBoard)

// AVFoundation is unusable inside CarPlay.app, so the soundtrack is played by SpringBoard,
// whose audio goes to the car while CarPlay is connected. CarPlay.app drives it with
// Darwin notifications when the first frame appears and when the splash goes away.
static BOOL gIsCarPlay;
static AVAudioPlayer *gAudioPlayer;
static AVAudioSessionCategory gSavedCategory;
static AVAudioSessionCategoryOptions gSavedOptions;

static void SSPostNotification(CFStringRef name) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, YES);
}

static void SSAudioRestoreSession(void) {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
	if (gSavedCategory) [session setCategory:gSavedCategory withOptions:gSavedOptions error:nil];
	gSavedCategory = nil;
}

static void SSAudioStop(void) {
	AVAudioPlayer *player = gAudioPlayer;
	if (!player) return;
	gAudioPlayer = nil;
	[player setVolume:0 fadeDuration:kFadeDuration];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFadeDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[player stop];
		if (!gAudioPlayer) SSAudioRestoreSession();
	});
}

static void SSAudioPlay(void) {
	OMCPrefsSync();
	if (![OMCPref(SS_KEY_SOUND, @NO) boolValue]) return;
	NSString *name = SSVideoName();
	if (!name) return;
	NSString *path = [SS_FRAMES_DIR(name) stringByAppendingPathComponent:@"audio.m4a"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		SSLog(@"audio: no soundtrack for %@", name);
		return;
	}

	if (gAudioPlayer) [gAudioPlayer stop];
	AVAudioSession *session = [AVAudioSession sharedInstance];
	if (!gSavedCategory) {
		gSavedCategory = session.category;
		gSavedOptions = session.categoryOptions;
	}
	// Playback (not Ambient) so the ringer switch doesn't mute it; mix so car audio keeps going.
	[session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
	[session setActive:YES error:nil];

	NSError *error = nil;
	gAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
	if (!gAudioPlayer) {
		SSLog(@"audio: cannot open %@: %@", path, error);
		SSAudioRestoreSession();
		return;
	}
	// Loop along with the frames unless the clip plays exactly once.
	gAudioPlayer.numberOfLoops = [OMCPref(SS_KEY_PLAY_FULL, @NO) boolValue] ? 0 : -1;
	BOOL ok = [gAudioPlayer play];
	SSLog(@"audio: playing %@ ok=%d route=%@", path.lastPathComponent, ok, session.currentRoute.outputs.firstObject.portType);
}

static void SSAudioNotification(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
	BOOL play = CFStringCompare(name, SS_NOTIFY_AUDIO_PLAY, 0) == kCFCompareEqualTo;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (play) SSAudioPlay();
		else SSAudioStop();
	});
}

#pragma mark - Frames

static UIImage *SSDecodeFrame(NSString *path) {
	CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
	if (!source) return nil;
	// Decode now, on the background queue, rather than lazily on the main thread at draw time.
	NSDictionary *options = @{(__bridge id)kCGImageSourceShouldCacheImmediately: @YES};
	CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options);
	CFRelease(source);
	if (!cgImage) return nil;
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	return image;
}

#pragma mark - Splash

// Marker class so the window hook below ignores our own window.
@interface SSSplashWindow : UIWindow
@end

@implementation SSSplashWindow
@end

@interface SSSplash : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, weak) UIScreen *screen;
@property (nonatomic, copy) NSString *framesDir;
@property (nonatomic, assign) NSUInteger frameCount;
@property (nonatomic, assign) double fps;
@property (nonatomic, assign) BOOL loop;
@property (nonatomic, strong) NSMutableArray<UIImage *> *buffer;
@property (nonatomic, strong) dispatch_queue_t decodeQueue;
@property (nonatomic, assign) BOOL decoding;
@property (nonatomic, assign) NSUInteger queuedFrames;
@property (nonatomic, assign) NSUInteger shownFrames;
@property (nonatomic, assign) NSUInteger failedFrames;
@property (nonatomic, assign) CFTimeInterval startTime;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL finished;
@end

@implementation SSSplash

- (instancetype)initWithScreen:(UIScreen *)screen scene:(UIWindowScene *)scene framesDir:(NSString *)framesDir
                    frameCount:(NSUInteger)frameCount fps:(double)fps {
	if ((self = [super init])) {
		_screen = screen;
		_framesDir = [framesDir copy];
		_frameCount = frameCount;
		_fps = fps;
		// Loop the clip until the configured duration is up, unless it should play exactly once.
		_loop = ![OMCPref(SS_KEY_PLAY_FULL, @NO) boolValue];
		_buffer = [NSMutableArray array];
		_decodeQueue = dispatch_queue_create("com.anlai.omnicar.startupscreen.decode", DISPATCH_QUEUE_SERIAL);

		BOOL fit     = [OMCPref(SS_KEY_SCALE_MODE, @0) integerValue] == 1;
		BOOL tapSkip = [OMCPref(SS_KEY_TAP_TO_SKIP, @YES) boolValue];

		_imageView = [[UIImageView alloc] initWithFrame:screen.bounds];
		_imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_imageView.backgroundColor = [UIColor blackColor];
		_imageView.contentMode = fit ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
		_imageView.clipsToBounds = YES;
		_imageView.userInteractionEnabled = YES;

		UIViewController *vc = [UIViewController new];
		vc.view = _imageView;

		// CarPlay may or may not drive the car display through a UIWindowScene.
		if (scene) {
			_window = [[SSSplashWindow alloc] initWithWindowScene:scene];
		} else {
			_window = [[SSSplashWindow alloc] initWithFrame:screen.bounds];
			// No scene to attach to, so setScreen: is the only way onto the car display.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			_window.screen = screen;
#pragma clang diagnostic pop
		}
		_window.windowLevel = UIWindowLevelAlert + 1000;
		_window.backgroundColor = [UIColor blackColor];
		_window.rootViewController = vc;

		if (tapSkip) {
			UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
			[_imageView addGestureRecognizer:tap];
		}
	}
	return self;
}

- (void)start {
	self.window.hidden = NO;
	SSLog(@"splash window shown: frame=%@ level=%.0f scene=%@ frames=%lu fps=%.0f loop=%d",
		NSStringFromCGRect(self.window.frame), self.window.windowLevel,
		self.window.windowScene.session.persistentIdentifier, (unsigned long)self.frameCount, self.fps, self.loop);

	self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
	[self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	[self decodeMore];

	// Safety net in case no frame ever decodes: never block CarPlay for long.
	__weak __typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (weakSelf && !weakSelf.shownFrames) {
			SSLog(@"no frame shown after 10s (failed=%lu), giving up", (unsigned long)weakSelf.failedFrames);
			[weakSelf dismiss];
		}
	});
}

// Decodes frames one at a time on a background queue, keeping a few ready ahead of playback.
- (void)decodeMore {
	if (self.decoding || self.finished || self.buffer.count >= kFrameBufferSize) return;
	if (!self.loop && self.queuedFrames >= self.frameCount) return;
	// Every frame failing would otherwise spin forever.
	if (self.failedFrames >= self.frameCount) return;

	self.decoding = YES;
	NSUInteger index = self.queuedFrames % self.frameCount;
	self.queuedFrames++;
	NSString *path = [self.framesDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%05lu.jpg", (unsigned long)index]];
	dispatch_async(self.decodeQueue, ^{
		UIImage *image = SSDecodeFrame(path);
		dispatch_async(dispatch_get_main_queue(), ^{
			self.decoding = NO;
			if (self.finished) return;
			if (image) {
				[self.buffer addObject:image];
			} else if (self.failedFrames++ == 0) {
				SSLog(@"cannot decode %@", path);
			}
			[self decodeMore];
		});
	});
}

- (void)tick {
	if (self.finished || !self.buffer.count) return;

	CFTimeInterval now = CACurrentMediaTime();
	if (!self.shownFrames) {
		self.startTime = now;
		[self startCountdown];
	} else if (self.shownFrames > (NSUInteger)((now - self.startTime) * self.fps)) {
		return; // Next frame isn't due yet.
	}

	self.imageView.image = self.buffer.firstObject;
	[self.buffer removeObjectAtIndex:0];
	self.shownFrames++;

	if (!self.loop && self.shownFrames >= self.frameCount) {
		[self.displayLink invalidate];
		__weak __typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / self.fps)), dispatch_get_main_queue(), ^{
			[weakSelf dismiss];
		});
		return;
	}
	[self decodeMore];
}

// CarPlay's main thread can stall for seconds while it starts up, so the countdown only
// begins once the first frame is on screen.
- (void)startCountdown {
	NSTimeInterval limit = self.loop ? MAX(1.0, [OMCPref(SS_KEY_DURATION, @5) doubleValue]) : kMaxFullPlay;
	SSLog(@"first frame shown, playing for up to %.0fs", limit);
	SSPostNotification(SS_NOTIFY_AUDIO_PLAY);

	__weak __typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf dismiss];
	});
}

- (void)dismiss {
	if (self.finished) return;
	self.finished = YES;
	SSLog(@"dismissing after %lu frames", (unsigned long)self.shownFrames);
	SSPostNotification(SS_NOTIFY_AUDIO_STOP);

	[UIView animateWithDuration:kFadeDuration animations:^{
		self.window.alpha = 0.0;
	} completion:^(BOOL done) {
		[self tearDown];
	}];
}

- (void)tearDown {
	// Skipped by dismiss when CarPlay disconnects mid-splash.
	if (!self.finished && self.shownFrames) SSPostNotification(SS_NOTIFY_AUDIO_STOP);
	self.finished = YES;
	[self.displayLink invalidate];
	self.displayLink = nil;
	[self.buffer removeAllObjects];
	self.window.hidden = YES;
	self.window = nil;
	UIScreen *screen = self.screen;
	if (screen) objc_setAssociatedObject(screen, &kSplashKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

#pragma mark - Car display detection

static BOOL SSIsCarScreen(UIScreen *screen) {
	if (!screen) return NO;
	if (screen.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomCarPlay) return YES;
	return screen != [UIScreen mainScreen];
}

// Keyed on the car UIScreen: a new screen object is created every time the car connects,
// so this gives one splash per connection whether CarPlay uses scenes or plain windows.
static void SSShowSplash(UIScreen *screen, UIWindowScene *scene, NSString *source) {
	if (!SSIsCarScreen(screen)) return;
	if (objc_getAssociatedObject(screen, &kShownKey)) return;
	objc_setAssociatedObject(screen, &kShownKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	SSLog(@"car display detected via %@: screen=%@ scene=%@", source, screen, scene);

	OMCPrefsSync();
	if (!OMCFeatureEnabled(SS_FEATURE)) { SSLog(@"disabled in settings"); return; }

	NSString *name = SSVideoName();
	if (!name) { SSLog(@"no video found in %@", SS_VIDEOS_DIR); return; }

	NSString *framesDir = SS_FRAMES_DIR(name);
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[framesDir stringByAppendingPathComponent:@"info.plist"]];
	NSUInteger count = [info[@"count"] unsignedIntegerValue];
	double fps = [info[@"fps"] doubleValue];
	if (!count || fps <= 0) {
		SSLog(@"no frames for %@ - open Settings > OmniCar > Startup Screen to convert it", name);
		return;
	}
	SSLog(@"playing %@ (%lu frames @ %.0ffps)", name, (unsigned long)count, fps);

	SSSplash *splash = [[SSSplash alloc] initWithScreen:screen scene:scene framesDir:framesDir frameCount:count fps:fps];
	objc_setAssociatedObject(screen, &kSplashKey, splash, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[splash start];
}

static NSString *SSDescribeScreen(UIScreen *screen) {
	if (!screen) return @"(nil)";
	return [NSString stringWithFormat:@"<%@ %p main=%d idiom=%ld bounds=%@>", NSStringFromClass([screen class]), screen,
		screen == [UIScreen mainScreen], (long)screen.traitCollection.userInterfaceIdiom, NSStringFromCGRect(screen.bounds)];
}

static void SSHandleScene(UIScene *scene, NSString *source) {
	SSLog(@"%@: %@ role=%@", source, NSStringFromClass([scene class]), scene.session.role);
	if (![scene isKindOfClass:[UIWindowScene class]]) return;
	UIWindowScene *windowScene = (UIWindowScene *)scene;
	SSLog(@"%@: idiom=%ld screen=%@", source, (long)windowScene.traitCollection.userInterfaceIdiom,
		SSDescribeScreen(windowScene.screen));
	SSShowSplash(windowScene.screen, windowScene, source);
}

static void SSTearDownScreen(UIScreen *screen) {
	if (!screen) return;
	SSSplash *splash = objc_getAssociatedObject(screen, &kSplashKey);
	[splash tearDown];
}

%group StartupScreen

%hook UIWindow

// Fallback for CarPlay builds that put windows straight onto the car UIScreen without
// posting the UIScene lifecycle notifications.
- (void)setHidden:(BOOL)hidden {
	%orig;
	if (!gIsCarPlay || hidden || [self isKindOfClass:[SSSplashWindow class]]) return;
	UIScreen *screen = self.screen;

	// Diagnostics: record the first windows CarPlay shows and where they live.
	static int logged = 0;
	if (logged < 40) {
		logged++;
		SSLog(@"window shown: %@ level=%.0f scene=%@ %p %@ screen=%@", NSStringFromClass([self class]), self.windowLevel,
			self.windowScene ? NSStringFromClass([self.windowScene class]) : @"(nil)", self.windowScene,
			self.windowScene.session.persistentIdentifier, SSDescribeScreen(screen));
	}

	if (!SSIsCarScreen(screen)) return;
	UIWindowScene *scene = self.windowScene;
	// Let CarPlay finish building its own windows first so ours ends up on top.
	dispatch_async(dispatch_get_main_queue(), ^{ SSShowSplash(screen, scene, @"window"); });
}

%end

%end

%ctor {
	@autoreleasepool {
		NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;

		// SpringBoard side: only the soundtrack player.
		if ([bundleID isEqualToString:@"com.apple.springboard"]) {
			CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
			CFNotificationCenterAddObserver(darwin, NULL, SSAudioNotification, SS_NOTIFY_AUDIO_PLAY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			CFNotificationCenterAddObserver(darwin, NULL, SSAudioNotification, SS_NOTIFY_AUDIO_STOP, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			return;
		}
		if (![bundleID isEqualToString:@"com.apple.CarPlayApp"]) return;
		gIsCarPlay = YES;
		%init(StartupScreen);

		for (UIScreen *screen in [UIScreen screens]) SSLog(@"existing screen: %@", SSDescribeScreen(screen));
		SSLog(@"videos dir %@ readable=%d", SS_VIDEOS_DIR, [[NSFileManager defaultManager] isReadableFileAtPath:SS_VIDEOS_DIR]);

		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		NSOperationQueue *main = [NSOperationQueue mainQueue];
		[nc addObserverForName:UISceneWillConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			UIScene *scene = note.object;
			dispatch_async(dispatch_get_main_queue(), ^{ SSHandleScene(scene, @"sceneConnect"); });
		}];
		// Trait collection may not be resolved at connect time; retry once the scene activates.
		[nc addObserverForName:UISceneDidActivateNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			SSHandleScene(note.object, @"sceneActivate");
		}];
		[nc addObserverForName:UIScreenDidConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			SSLog(@"screen connected: %@", SSDescribeScreen(note.object));
		}];
		[nc addObserverForName:UIScreenDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			SSLog(@"screen disconnected: %@", SSDescribeScreen(note.object));
			SSTearDownScreen(note.object);
		}];
		[nc addObserverForName:UISceneDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			UIScene *scene = note.object;
			if ([scene isKindOfClass:[UIWindowScene class]]) SSTearDownScreen(((UIWindowScene *)scene).screen);
		}];
	}
}
