// CarSplash - play a short video over the CarPlay screen while CarPlay is starting.
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
// Logs are prefixed with "[OmniCar/CarSplash]" - filter for it in Console.app to debug.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "OmniCar.h"
#import "CarSplash.h"

#define CSLog(fmt, ...) OMCLog(@"CarSplash", fmt, ##__VA_ARGS__)

static const NSTimeInterval kFadeDuration = 0.4;
static const NSTimeInterval kMaxFullPlay  = 60.0;
static const NSUInteger kFrameBufferSize  = 4;
static char kSplashKey;
static char kShownKey;

#pragma mark - Preferences

static NSString *CSVideoName(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *name = OMCPref(CS_KEY_VIDEO_NAME, nil);
	if (name.length && [fm fileExistsAtPath:[CS_VIDEOS_DIR stringByAppendingPathComponent:name]]) return name;
	// Fall back to the first video in the folder.
	NSError *error = nil;
	NSArray *files = [[fm contentsOfDirectoryAtPath:CS_VIDEOS_DIR error:&error] sortedArrayUsingSelector:@selector(compare:)];
	if (error) CSLog(@"cannot list %@: %@", CS_VIDEOS_DIR, error);
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

static void CSPostNotification(CFStringRef name) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, YES);
}

static void CSAudioRestoreSession(void) {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
	if (gSavedCategory) [session setCategory:gSavedCategory withOptions:gSavedOptions error:nil];
	gSavedCategory = nil;
}

static void CSAudioStop(void) {
	AVAudioPlayer *player = gAudioPlayer;
	if (!player) return;
	gAudioPlayer = nil;
	[player setVolume:0 fadeDuration:kFadeDuration];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFadeDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[player stop];
		if (!gAudioPlayer) CSAudioRestoreSession();
	});
}

static void CSAudioPlay(void) {
	OMCPrefsSync();
	if (![OMCPref(CS_KEY_SOUND, @NO) boolValue]) return;
	NSString *name = CSVideoName();
	if (!name) return;
	NSString *path = [CS_FRAMES_DIR(name) stringByAppendingPathComponent:@"audio.m4a"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		CSLog(@"audio: no soundtrack for %@", name);
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
		CSLog(@"audio: cannot open %@: %@", path, error);
		CSAudioRestoreSession();
		return;
	}
	// Loop along with the frames unless the clip plays exactly once.
	gAudioPlayer.numberOfLoops = [OMCPref(CS_KEY_PLAY_FULL, @NO) boolValue] ? 0 : -1;
	BOOL ok = [gAudioPlayer play];
	CSLog(@"audio: playing %@ ok=%d route=%@", path.lastPathComponent, ok, session.currentRoute.outputs.firstObject.portType);
}

static void CSAudioNotification(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
	BOOL play = CFStringCompare(name, CS_NOTIFY_AUDIO_PLAY, 0) == kCFCompareEqualTo;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (play) CSAudioPlay();
		else CSAudioStop();
	});
}

#pragma mark - Frames

static UIImage *CSDecodeFrame(NSString *path) {
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
@interface CSSplashWindow : UIWindow
@end

@implementation CSSplashWindow
@end

@interface CSSplash : NSObject
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

@implementation CSSplash

- (instancetype)initWithScreen:(UIScreen *)screen scene:(UIWindowScene *)scene framesDir:(NSString *)framesDir
                    frameCount:(NSUInteger)frameCount fps:(double)fps {
	if ((self = [super init])) {
		_screen = screen;
		_framesDir = [framesDir copy];
		_frameCount = frameCount;
		_fps = fps;
		// Loop the clip until the configured duration is up, unless it should play exactly once.
		_loop = ![OMCPref(CS_KEY_PLAY_FULL, @NO) boolValue];
		_buffer = [NSMutableArray array];
		_decodeQueue = dispatch_queue_create("com.anlai.omnicar.carsplash.decode", DISPATCH_QUEUE_SERIAL);

		BOOL fit     = [OMCPref(CS_KEY_SCALE_MODE, @0) integerValue] == 1;
		BOOL tapSkip = [OMCPref(CS_KEY_TAP_TO_SKIP, @YES) boolValue];

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
			_window = [[CSSplashWindow alloc] initWithWindowScene:scene];
		} else {
			_window = [[CSSplashWindow alloc] initWithFrame:screen.bounds];
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
	CSLog(@"splash window shown: frame=%@ level=%.0f scene=%@ frames=%lu fps=%.0f loop=%d",
		NSStringFromCGRect(self.window.frame), self.window.windowLevel,
		self.window.windowScene.session.persistentIdentifier, (unsigned long)self.frameCount, self.fps, self.loop);

	self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
	[self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	[self decodeMore];

	// Safety net in case no frame ever decodes: never block CarPlay for long.
	__weak __typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (weakSelf && !weakSelf.shownFrames) {
			CSLog(@"no frame shown after 10s (failed=%lu), giving up", (unsigned long)weakSelf.failedFrames);
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
		UIImage *image = CSDecodeFrame(path);
		dispatch_async(dispatch_get_main_queue(), ^{
			self.decoding = NO;
			if (self.finished) return;
			if (image) {
				[self.buffer addObject:image];
			} else if (self.failedFrames++ == 0) {
				CSLog(@"cannot decode %@", path);
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
	NSTimeInterval limit = self.loop ? MAX(1.0, [OMCPref(CS_KEY_DURATION, @5) doubleValue]) : kMaxFullPlay;
	CSLog(@"first frame shown, playing for up to %.0fs", limit);
	CSPostNotification(CS_NOTIFY_AUDIO_PLAY);

	__weak __typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf dismiss];
	});
}

- (void)dismiss {
	if (self.finished) return;
	self.finished = YES;
	CSLog(@"dismissing after %lu frames", (unsigned long)self.shownFrames);
	CSPostNotification(CS_NOTIFY_AUDIO_STOP);

	[UIView animateWithDuration:kFadeDuration animations:^{
		self.window.alpha = 0.0;
	} completion:^(BOOL done) {
		[self tearDown];
	}];
}

- (void)tearDown {
	// Skipped by dismiss when CarPlay disconnects mid-splash.
	if (!self.finished && self.shownFrames) CSPostNotification(CS_NOTIFY_AUDIO_STOP);
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

static BOOL CSIsCarScreen(UIScreen *screen) {
	if (!screen) return NO;
	if (screen.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomCarPlay) return YES;
	return screen != [UIScreen mainScreen];
}

// Keyed on the car UIScreen: a new screen object is created every time the car connects,
// so this gives one splash per connection whether CarPlay uses scenes or plain windows.
static void CSShowSplash(UIScreen *screen, UIWindowScene *scene, NSString *source) {
	if (!CSIsCarScreen(screen)) return;
	if (objc_getAssociatedObject(screen, &kShownKey)) return;
	objc_setAssociatedObject(screen, &kShownKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	CSLog(@"car display detected via %@: screen=%@ scene=%@", source, screen, scene);

	OMCPrefsSync();
	if (!OMCFeatureEnabled(CS_FEATURE)) { CSLog(@"disabled in settings"); return; }

	NSString *name = CSVideoName();
	if (!name) { CSLog(@"no video found in %@", CS_VIDEOS_DIR); return; }

	NSString *framesDir = CS_FRAMES_DIR(name);
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[framesDir stringByAppendingPathComponent:@"info.plist"]];
	NSUInteger count = [info[@"count"] unsignedIntegerValue];
	double fps = [info[@"fps"] doubleValue];
	if (!count || fps <= 0) {
		CSLog(@"no frames for %@ - open Settings > OmniCar > CarSplash to convert it", name);
		return;
	}
	CSLog(@"playing %@ (%lu frames @ %.0ffps)", name, (unsigned long)count, fps);

	CSSplash *splash = [[CSSplash alloc] initWithScreen:screen scene:scene framesDir:framesDir frameCount:count fps:fps];
	objc_setAssociatedObject(screen, &kSplashKey, splash, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[splash start];
}

static NSString *CSDescribeScreen(UIScreen *screen) {
	if (!screen) return @"(nil)";
	return [NSString stringWithFormat:@"<%@ %p main=%d idiom=%ld bounds=%@>", NSStringFromClass([screen class]), screen,
		screen == [UIScreen mainScreen], (long)screen.traitCollection.userInterfaceIdiom, NSStringFromCGRect(screen.bounds)];
}

static void CSHandleScene(UIScene *scene, NSString *source) {
	CSLog(@"%@: %@ role=%@", source, NSStringFromClass([scene class]), scene.session.role);
	if (![scene isKindOfClass:[UIWindowScene class]]) return;
	UIWindowScene *windowScene = (UIWindowScene *)scene;
	CSLog(@"%@: idiom=%ld screen=%@", source, (long)windowScene.traitCollection.userInterfaceIdiom,
		CSDescribeScreen(windowScene.screen));
	CSShowSplash(windowScene.screen, windowScene, source);
}

static void CSTearDownScreen(UIScreen *screen) {
	if (!screen) return;
	CSSplash *splash = objc_getAssociatedObject(screen, &kSplashKey);
	[splash tearDown];
}

%group CarSplash

%hook UIWindow

// Fallback for CarPlay builds that put windows straight onto the car UIScreen without
// posting the UIScene lifecycle notifications.
- (void)setHidden:(BOOL)hidden {
	%orig;
	if (!gIsCarPlay || hidden || [self isKindOfClass:[CSSplashWindow class]]) return;
	UIScreen *screen = self.screen;

	// Diagnostics: record the first windows CarPlay shows and where they live.
	static int logged = 0;
	if (logged < 40) {
		logged++;
		CSLog(@"window shown: %@ level=%.0f scene=%@ %p %@ screen=%@", NSStringFromClass([self class]), self.windowLevel,
			self.windowScene ? NSStringFromClass([self.windowScene class]) : @"(nil)", self.windowScene,
			self.windowScene.session.persistentIdentifier, CSDescribeScreen(screen));
	}

	if (!CSIsCarScreen(screen)) return;
	UIWindowScene *scene = self.windowScene;
	// Let CarPlay finish building its own windows first so ours ends up on top.
	dispatch_async(dispatch_get_main_queue(), ^{ CSShowSplash(screen, scene, @"window"); });
}

%end

%end

%ctor {
	@autoreleasepool {
		NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;

		// SpringBoard side: only the soundtrack player.
		if ([bundleID isEqualToString:@"com.apple.springboard"]) {
			CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
			CFNotificationCenterAddObserver(darwin, NULL, CSAudioNotification, CS_NOTIFY_AUDIO_PLAY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			CFNotificationCenterAddObserver(darwin, NULL, CSAudioNotification, CS_NOTIFY_AUDIO_STOP, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			return;
		}
		if (![bundleID isEqualToString:@"com.apple.CarPlayApp"]) return;
		gIsCarPlay = YES;
		%init(CarSplash);

		for (UIScreen *screen in [UIScreen screens]) CSLog(@"existing screen: %@", CSDescribeScreen(screen));
		CSLog(@"videos dir %@ readable=%d", CS_VIDEOS_DIR, [[NSFileManager defaultManager] isReadableFileAtPath:CS_VIDEOS_DIR]);

		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		NSOperationQueue *main = [NSOperationQueue mainQueue];
		[nc addObserverForName:UISceneWillConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			UIScene *scene = note.object;
			dispatch_async(dispatch_get_main_queue(), ^{ CSHandleScene(scene, @"sceneConnect"); });
		}];
		// Trait collection may not be resolved at connect time; retry once the scene activates.
		[nc addObserverForName:UISceneDidActivateNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			CSHandleScene(note.object, @"sceneActivate");
		}];
		[nc addObserverForName:UIScreenDidConnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			CSLog(@"screen connected: %@", CSDescribeScreen(note.object));
		}];
		[nc addObserverForName:UIScreenDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			CSLog(@"screen disconnected: %@", CSDescribeScreen(note.object));
			CSTearDownScreen(note.object);
		}];
		[nc addObserverForName:UISceneDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note) {
			UIScene *scene = note.object;
			if ([scene isKindOfClass:[UIWindowScene class]]) CSTearDownScreen(((UIWindowScene *)scene).screen);
		}];
	}
}
