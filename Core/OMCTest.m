// Auto test runner (developer only, see Core/OMCTest.h). Compiled into every feature dylib like OmniCar.m,
// so the runner of a process is shared through one dictionary on the main thread: the first dylib that
// registers a suite creates it and installs the listeners, the others only add their suites. No class is
// declared here (each dylib would carry its own copy of it); state is plain dictionaries and blocks.
#import "OMCTest.h"

#if OMC_AUTOTEST
#import <notify.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

#define OMC_TEST_POLL      0.5    // s between two checks of a step
#define OMC_TEST_TICK      2.0    // s between two looks at whose turn it is while a run is on
// Paced for a person watching the car screen (19/10/2026: "test slowly so I can see"): 3 s after a step before the
// next one, 4 s after a failed one (time to read the bar), plus the finger coming in (OMC_TEST_FINGER_IN) on each step.
#define OMC_TEST_GAP       3.0    // s after a step before the next one
#define OMC_TEST_FAIL_GAP  4.0
#define OMC_TEST_FINGER_IN 0.7    // s the finger takes to come to its point
#define OMC_TEST_FINGER_PRESS 0.25 // s pressed before the action (tap) / between press and the first move (drag)
#define OMC_TEST_FINGER_HOLD 0.5  // s the finger stays after the action before it lifts

NSString *OMCTestFormat(NSString *format, ...) {
	va_list ap;
	va_start(ap, format);
	NSString *s = [[NSString alloc] initWithFormat:format arguments:ap];
	va_end(ap);
	return s;
}

NSDictionary *OMCTestStep(NSString *name, double settle, double timeout, OMCTestBlock run, OMCTestBlock check) {
	NSMutableDictionary *d = [@{@"name": name ?: @"?", @"settle": @(settle), @"timeout": @(timeout)} mutableCopy];
	if (run) d[@"run"] = [run copy];
	if (check) d[@"check"] = [check copy];
	return d;
}

NSDictionary *OMCTestStepAt(NSString *name, double settle, double timeout, OMCTestPointBlock at, OMCTestBlock run, OMCTestBlock check) {
	NSMutableDictionary *d = [OMCTestStep(name, settle, timeout, run, check) mutableCopy];
	if (at) d[@"at"] = [at copy];
	return d;
}

#pragma mark - Shared state

// R[@"suites"] = {suite: {ready, build, windows}}, plus the running suite's state (running, gen, suite, steps,
// index, stepStart, banner, label, waiting).
static NSMutableDictionary *OMCTestR(void) {
	NSMutableDictionary *td = [NSThread mainThread].threadDictionary;
	NSMutableDictionary *r = td[@"OMCTestRunner"];
	if (!r) td[@"OMCTestRunner"] = r = [@{@"suites": [NSMutableDictionary dictionary], @"gen": @0} mutableCopy];
	return r;
}

static NSDictionary *OMCTestStored(void) {
	OMCPrefsSync();
	NSDictionary *d = OMCPref(OMC_KEY_AUTOTEST, nil);
	return [d isKindOfClass:[NSDictionary class]] ? d : nil;
}

static void OMCTestStore(NSDictionary *d) {
	CFPreferencesSetAppValue((__bridge CFStringRef)OMC_KEY_AUTOTEST, (__bridge CFPropertyListRef)d, OMC_PREFS_DOMAIN);
	CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

static BOOL OMCTestRunning(void) { return [OMCTestR()[@"running"] boolValue]; }
static NSInteger OMCTestGen(void) { return [OMCTestR()[@"gen"] integerValue]; }

static void OMCTestTick(void);
static void OMCTestNext(void);
static void OMCTestFinishStep(NSString *status, NSString *detail);

// Runs `block` later unless the run was stopped / paused / restarted meanwhile.
static void OMCTestAfter(double delay, dispatch_block_t block) {
	NSInteger gen = OMCTestGen();
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (!OMCTestRunning() || OMCTestGen() != gen) return;
		@try { block(); }
		@catch (NSException *e) { OMCTestFinishStep(@"fail", OMCTestFormat(@"exception: %@", e)); }
	});
}

#pragma mark - Car screen: progress bar
// (Khong chup anh man xe nua: ket qua chi nam trong OmniCar.log va trang Kiem thu tu dong.)

static UIWindowScene *OMCTestCarScene(void) {
	for (UIScene *sc in [UIApplication sharedApplication].connectedScenes)
		if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen != [UIScreen mainScreen]) return (UIWindowScene *)sc;
	return nil;
}

static void OMCTestBannerTapped(void);

// Small orange bar at the top of the car screen: suite + step, tap = stop. Only where this process has a
// UIScreen for the car (CarPlay); elsewhere the run is followed in OmniCar.log / Settings.
static void OMCTestShowBanner(NSString *text) {
	NSMutableDictionary *R = OMCTestR();
	UILabel *label = R[@"label"];
	if (!label) {
		UIWindowScene *scene = OMCTestCarScene();
		UIScreen *screen = scene.screen;
		if (!scene) for (UIScreen *sc in [UIScreen screens]) if (sc != [UIScreen mainScreen]) screen = sc;
		if (!screen) return;
		CGFloat w = MIN(380, screen.bounds.size.width - 40);
		CGRect f = CGRectMake((screen.bounds.size.width - w) / 2, 6, w, 28);
		UIWindow *win = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:f];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		if (!scene) win.screen = screen;
#pragma clang diagnostic pop
		win.frame = f;
		win.windowLevel = UIWindowLevelStatusBar + 60;
		win.backgroundColor = [UIColor colorWithRed:0.85 green:0.33 blue:0.1 alpha:0.92];
		win.layer.cornerRadius = 14;
		win.clipsToBounds = YES;
		UIViewController *vc = [UIViewController new];
		win.rootViewController = vc;
		label = [[UILabel alloc] initWithFrame:vc.view.bounds];
		label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		label.textAlignment = NSTextAlignmentCenter;
		label.textColor = [UIColor whiteColor];
		label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
		label.adjustsFontSizeToFitWidth = YES;
		label.minimumScaleFactor = 0.7;
		label.userInteractionEnabled = YES;
		// A gesture recognizer does not retain its target: the block operation is kept in R
		NSBlockOperation *target = [NSBlockOperation blockOperationWithBlock:^{ OMCTestBannerTapped(); }];
		[label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(main)]];
		R[@"tapTarget"] = target;
		[vc.view addSubview:label];
		win.hidden = NO;
		R[@"banner"] = win;
		R[@"label"] = label;
	}
	label.text = text;
}

static void OMCTestHideFingerWindow(void);

static void OMCTestHideBanner(void) {
	NSMutableDictionary *R = OMCTestR();
	((UIWindow *)R[@"banner"]).hidden = YES;
	[R removeObjectsForKeys:@[@"banner", @"label", @"tapTarget"]];
	OMCTestHideFingerWindow();
}

#pragma mark - Finger
// A hand (SF Symbol hand.point.up.left.fill, white with a dark shadow) plus a ring at the exact point, drawn in any view
// with plain UIKit objects (no class of our own: this file is in several dylibs of one process). The runner draws it in
// its own window on the car screen for the steps of the CarPlay process; an app draws it in its window for a touch made
// inside the app (OMCTestTouch*). Where an iPhone app is hosted, SpringBoard's host window covers CarPlay's windows, so a
// finger over such a pane can only come from the app itself.

#define OMC_FINGER_RING 34.0

static UIView *OMCTestFingerMake(UIView *host, CGPoint p) {
	UIView *f = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
	f.userInteractionEnabled = NO;
	f.center = p;
	UIView *ring = [[UIView alloc] initWithFrame:CGRectMake(-OMC_FINGER_RING / 2, -OMC_FINGER_RING / 2, OMC_FINGER_RING, OMC_FINGER_RING)];
	ring.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
	ring.layer.cornerRadius = OMC_FINGER_RING / 2;
	ring.layer.borderColor = [UIColor whiteColor].CGColor;
	ring.layer.borderWidth = 2;
	ring.layer.shadowColor = [UIColor blackColor].CGColor;
	ring.layer.shadowOpacity = 0.6;
	ring.layer.shadowRadius = 2;
	ring.layer.shadowOffset = CGSizeZero;
	ring.tag = 1;
	[f addSubview:ring];
	UIImage *img = nil;
	if (@available(iOS 13.0, *)) {
		img = [UIImage systemImageNamed:@"hand.point.up.left.fill"
			withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightRegular]];
	}
	UIImageView *hand = [[UIImageView alloc] initWithImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
	hand.tintColor = [UIColor whiteColor];
	hand.layer.shadowColor = [UIColor blackColor].CGColor;
	hand.layer.shadowOpacity = 0.9;
	hand.layer.shadowRadius = 2.5;
	hand.layer.shadowOffset = CGSizeMake(0, 1);
	// The symbol's fingertip is near its top-left corner: that point of the image sits on the touch point
	CGSize sz = hand.image.size;
	if (sz.width < 10) sz = CGSizeMake(44, 52);
	hand.frame = CGRectMake(-sz.width * 0.28, -sz.height * 0.05, sz.width, sz.height);
	hand.tag = 2;
	[f addSubview:hand];
	[host addSubview:f];
	return f;
}

static void OMCTestFingerPressAnim(UIView *f) {
	UIView *ring = [f viewWithTag:1], *hand = [f viewWithTag:2];
	ring.transform = CGAffineTransformMakeScale(0.4, 0.4);
	ring.alpha = 1;
	[UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
		ring.transform = CGAffineTransformIdentity;
		hand.transform = CGAffineTransformMakeScale(0.88, 0.88);
	} completion:nil];
}

static void OMCTestFingerLift(UIView *f) {
	UIView *ring = [f viewWithTag:1], *hand = [f viewWithTag:2];
	[UIView animateWithDuration:0.3 delay:OMC_TEST_FINGER_HOLD options:0 animations:^{
		hand.transform = CGAffineTransformIdentity;
		ring.transform = CGAffineTransformMakeScale(1.6, 1.6);
		ring.alpha = 0;
		hand.alpha = 0;
	} completion:^(BOOL done) { [f removeFromSuperview]; }];
}

// Comes in from below-right over OMC_TEST_FINGER_IN s, then `pressed` (the ring expands)
static void OMCTestFingerArrive(UIView *host, CGPoint p, void (^pressed)(UIView *finger)) {
	UIView *f = OMCTestFingerMake(host, CGPointMake(p.x + 60, p.y + 80));
	f.alpha = 0;
	[f viewWithTag:1].alpha = 0;
	[UIView animateWithDuration:OMC_TEST_FINGER_IN delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
		f.center = p;
		f.alpha = 1;
	} completion:^(BOOL done) {
		OMCTestFingerPressAnim(f);
		pressed(f);
	}];
}

void OMCTestFingerTap(UIView *host, CGPoint p, dispatch_block_t press) {
	if (!host) { if (press) press(); return; }
	OMCTestFingerArrive(host, p, ^(UIView *f) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(OMC_TEST_FINGER_PRESS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (press) press();
			OMCTestFingerLift(f);
		});
	});
}

void OMCTestFingerDrag(UIView *host, CGPoint from, CGPoint to, double duration, dispatch_block_t began, void (^move)(CGPoint), dispatch_block_t ended) {
	if (!host) { if (began) began(); if (move) move(to); if (ended) ended(); return; }
	OMCTestFingerArrive(host, from, ^(UIView *f) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(OMC_TEST_FINGER_PRESS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (began) began();
			int steps = MAX(6, (int)(duration / 0.025));
			double dt = duration / steps;
			__block int i = 0;
			__block dispatch_block_t tick = nil;
			dispatch_block_t t = ^{
				i++;
				double k = (double)i / steps;
				k = k < 0.5 ? 2 * k * k : 1 - 2 * (1 - k) * (1 - k);   // ease in-out
				CGPoint q = CGPointMake(from.x + (to.x - from.x) * k, from.y + (to.y - from.y) * k);
				f.center = q;
				if (move) move(q);
				if (i < steps) {
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(dt * NSEC_PER_SEC)), dispatch_get_main_queue(), tick);
				} else {
					if (ended) ended();
					OMCTestFingerLift(f);
					tick = nil;
				}
			};
			tick = [t copy];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(dt * NSEC_PER_SEC)), dispatch_get_main_queue(), tick);
		});
	});
}

#pragma mark - Synthetic touch (this process)
// A UITouch built with UIKit's private setters and sent through -[UIApplication sendEvent:] inside a UITouchesEvent, the way
// KIF (the UI test framework) does: it goes down the same path as a finger on the glass, so hit-testing, UIControl actions
// and gesture recognizers all run. Since iOS 9 UIKit reads the IOHIDEvent behind a touch, so one is built too
// (IOKit functions looked up with dlsym: no link dependency for the feature dylibs).

@interface UITouch (OMCTestPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)setIsTap:(BOOL)isTap;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)touchPhase;
- (void)setGestureView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)_setIsFirstTouchForView:(BOOL)firstTouchForView;
- (void)_setHidEvent:(void *)event;
@end
@interface UIEvent (OMCTestPrivate)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(void *)event;
@end
@interface UIApplication (OMCTestPrivate)
- (UIEvent *)_touchesEvent;
@end

typedef void *(*OMCHIDCreateDigitizer)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef void *(*OMCHIDCreateFinger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef void (*OMCHIDAppend)(void *, void *, uint32_t);
typedef void (*OMCHIDSetInt)(void *, uint32_t, CFIndex);

// IOHIDEvent for one touch (NULL if IOKit is not there). Caller releases.
static void *OMCTestHIDEvent(UITouch *touch) {
	static OMCHIDCreateDigitizer createHand;
	static OMCHIDCreateFinger createFinger;
	static OMCHIDAppend append;
	static OMCHIDSetInt setInt;
	static BOOL looked;
	if (!looked) {
		looked = YES;
		void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
		if (h) {
			createHand = (OMCHIDCreateDigitizer)dlsym(h, "IOHIDEventCreateDigitizerEvent");
			createFinger = (OMCHIDCreateFinger)dlsym(h, "IOHIDEventCreateDigitizerFingerEvent");
			append = (OMCHIDAppend)dlsym(h, "IOHIDEventAppendEvent");
			setInt = (OMCHIDSetInt)dlsym(h, "IOHIDEventSetIntegerValue");
		}
		if (!createHand || !createFinger || !append || !setInt) OMCTestLog(@"IOKit: khong tim thay ham IOHIDEvent (cham gia khong co HID event)");
	}
	if (!createHand || !createFinger || !append || !setInt) return NULL;
	uint64_t ts = mach_absolute_time();
	const uint32_t kHand = 3, kRange = 1, kTouch = 2, kPosition = 4, kIsDisplayIntegrated = (11 << 16) + 24;
	void *hand = createHand(kCFAllocatorDefault, ts, kHand, 0, 0, kTouch, 0, 0, 0, 0, 0, 0, false, false, 0);
	if (!hand) return NULL;
	setInt(hand, kIsDisplayIntegrated, 1);
	uint32_t mask = touch.phase == UITouchPhaseMoved ? kPosition : (kRange | kTouch);
	Boolean down = touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled;
	CGPoint p = [touch locationInView:touch.window];
	void *finger = createFinger(kCFAllocatorDefault, ts, 1, 2, mask, p.x, p.y, 0, 0, 0, down, down, 0);
	if (finger) {
		setInt(finger, kIsDisplayIntegrated, 1);
		append(hand, finger, 0);
		CFRelease(finger);
	}
	return hand;
}

static void OMCTestSendTouch(UITouch *touch, UITouchPhase phase, CGPoint p) {
	UIApplication *app = [UIApplication sharedApplication];
	if ([touch respondsToSelector:@selector(setTimestamp:)]) [touch setTimestamp:[[NSProcessInfo processInfo] systemUptime]];
	if (phase == UITouchPhaseMoved && [touch respondsToSelector:@selector(_setLocationInWindow:resetPrevious:)])
		[touch _setLocationInWindow:p resetPrevious:NO];
	[touch setPhase:phase];
	UIEvent *ev = [app respondsToSelector:@selector(_touchesEvent)] ? [app _touchesEvent] : nil;
	if (!ev) return;
	if ([ev respondsToSelector:@selector(_clearTouches)]) [ev _clearTouches];
	void *hid = OMCTestHIDEvent(touch);
	if (hid) {
		if ([touch respondsToSelector:@selector(_setHidEvent:)]) [touch _setHidEvent:hid];
		if ([ev respondsToSelector:@selector(_setHIDEvent:)]) [ev _setHIDEvent:hid];
		CFRelease(hid);
	}
	if ([ev respondsToSelector:@selector(_addTouch:forDelayedDelivery:)]) [ev _addTouch:touch forDelayedDelivery:NO];
	[app sendEvent:ev];
}

// Touch down at p: hit view found like UIKit does, touch built on it
static UITouch *OMCTestTouchDown(UIWindow *window, CGPoint p) {
	UITouch *t = [[UITouch alloc] init];
	UIView *hit = [window hitTest:p withEvent:nil] ?: window;
	if ([t respondsToSelector:@selector(setWindow:)]) [t setWindow:window];
	if ([t respondsToSelector:@selector(_setLocationInWindow:resetPrevious:)]) [t _setLocationInWindow:p resetPrevious:YES];
	if ([t respondsToSelector:@selector(setView:)]) [t setView:hit];
	if ([t respondsToSelector:@selector(setGestureView:)]) [t setGestureView:hit];
	if ([t respondsToSelector:@selector(_setIsFirstTouchForView:)]) [t _setIsFirstTouchForView:YES];
	if ([t respondsToSelector:@selector(setIsTap:)]) [t setIsTap:YES];
	if ([t respondsToSelector:@selector(setTapCount:)]) [t setTapCount:1];
	OMCTestSendTouch(t, UITouchPhaseBegan, p);
	return t;
}

// A recognizer of the hit view or a parent is on this touch (began / changed / ended)
static BOOL OMCTestGestureTaken(UIView *v) {
	for (; v; v = v.superview)
		for (UIGestureRecognizer *g in v.gestureRecognizers)
			if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged || g.state == UIGestureRecognizerStateEnded) return YES;
	return NO;
}

void OMCTestTouchTap(UIWindow *window, CGPoint p, void (^done)(UIView *hit, BOOL gesture)) {
	if (!window) { if (done) done(nil, NO); return; }
	OMCTestFingerTap(window, p, ^{
		__block UITouch *t = nil;
		__block BOOL gesture = NO;
		@try { t = OMCTestTouchDown(window, p); } @catch (NSException *e) { OMCTestLog(@"cham gia xuong loi: %@", e); }
		if (!t) { if (done) done(nil, NO); return; }
		UIView *hit = t.view;
		gesture = OMCTestGestureTaken(hit);
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			@try { OMCTestSendTouch(t, UITouchPhaseEnded, p); } @catch (NSException *e) { OMCTestLog(@"cham gia len loi: %@", e); }
			gesture = gesture || OMCTestGestureTaken(hit);
			if (done) done(hit, gesture);
		});
	});
}

void OMCTestTouchDrag(UIWindow *window, CGPoint from, CGPoint to, double duration, void (^done)(UIView *hit, BOOL gesture)) {
	if (!window) { if (done) done(nil, NO); return; }
	__block UITouch *t = nil;
	__block BOOL gesture = NO;
	__block CGPoint last = from;
	OMCTestFingerDrag(window, from, to, duration, ^{
		@try { t = OMCTestTouchDown(window, from); } @catch (NSException *e) { OMCTestLog(@"cham gia xuong loi: %@", e); }
	}, ^(CGPoint q) {
		if (!t) return;
		last = q;
		@try { OMCTestSendTouch(t, UITouchPhaseMoved, q); } @catch (NSException *e) { OMCTestLog(@"cham gia keo loi: %@", e); }
		gesture = gesture || OMCTestGestureTaken(t.view);
	}, ^{
		if (!t) { if (done) done(nil, NO); return; }
		UIView *hit = t.view;
		@try { OMCTestSendTouch(t, UITouchPhaseEnded, last); } @catch (NSException *e) { OMCTestLog(@"cham gia len loi: %@", e); }
		if (done) done(hit, gesture);
	});
}

#pragma mark - Car screen: finger window of the runner

// Full-screen transparent window on the car display (CarPlay process), above the banner, touches pass through
static UIWindow *OMCTestFingerWindow(void) {
	NSMutableDictionary *R = OMCTestR();
	UIWindow *win = R[@"fingerWindow"];
	if (win) return win;
	UIWindowScene *scene = OMCTestCarScene();
	UIScreen *screen = scene.screen;
	if (!scene) for (UIScreen *sc in [UIScreen screens]) if (sc != [UIScreen mainScreen]) screen = sc;
	if (!screen) return nil;
	win = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:screen.bounds];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	if (!scene) win.screen = screen;
#pragma clang diagnostic pop
	win.frame = screen.bounds;
	win.windowLevel = UIWindowLevelStatusBar + 70;
	win.backgroundColor = [UIColor clearColor];
	win.userInteractionEnabled = NO;
	win.rootViewController = [UIViewController new];
	win.hidden = NO;
	R[@"fingerWindow"] = win;
	return win;
}

static void OMCTestHideFingerWindow(void) {
	NSMutableDictionary *R = OMCTestR();
	((UIWindow *)R[@"fingerWindow"]).hidden = YES;
	[R removeObjectForKey:@"fingerWindow"];
}

#pragma mark - Run

static NSString *OMCTestSuiteName(void) { return OMCTestR()[@"suite"]; }
static NSArray<NSDictionary *> *OMCTestSteps(void) { return OMCTestR()[@"steps"]; }
static NSInteger OMCTestIndex(void) { return [OMCTestR()[@"index"] integerValue]; }

// Saves this process's progress into the run, unless Settings stopped / restarted it meanwhile (then stop here).
static BOOL OMCTestSave(NSDictionary *changes) {
	NSDictionary *d = OMCTestStored();
	NSMutableDictionary *R = OMCTestR();
	if (![d[@"state"] isEqual:@"running"] || ![d[@"run"] isEqual:R[@"run"]]) {
		OMCTestLog(@"lan chay da bi dung / thay tu Cai dat -> dung %@", OMCTestSuiteName());
		R[@"running"] = @NO;
		R[@"gen"] = @(OMCTestGen() + 1);
		OMCTestHideBanner();
		return NO;
	}
	NSMutableDictionary *m = [d mutableCopy];
	[m addEntriesFromDictionary:changes];
	OMCTestStore(m);
	return YES;
}

static NSString *OMCTestProgress(void) {
	return OMCTestFormat(@"OmniCar test · %@ %ld/%lu · tap to stop", OMCTestSuiteName(), (long)OMCTestIndex() + 1,
		(unsigned long)OMCTestSteps().count);
}

static void OMCTestStartSuite(NSDictionary *run) {
	NSMutableDictionary *R = OMCTestR();
	NSString *suite = run[@"suites"][[run[@"suite"] integerValue]];
	NSDictionary *entry = R[@"suites"][suite];
	NSArray *(^build)(void) = entry[@"build"];
	NSArray *steps = @[];
	@try { steps = build() ?: @[]; } @catch (NSException *e) { OMCTestLog(@"%@: tao buoc loi %@", suite, e); }
	R[@"suite"] = suite;
	R[@"steps"] = steps;
	R[@"windows"] = entry[@"windows"];
	R[@"run"] = run[@"run"];
	NSInteger index = [run[@"step"] integerValue];
	NSMutableArray *results = [NSMutableArray arrayWithArray:run[@"results"] ?: @[]];
	if ([run[@"inStep"] boolValue] && index < (NSInteger)steps.count) {   // this process died in that step
		NSString *name = steps[index][@"name"];
		[results addObject:@{@"suite": suite, @"name": name, @"status": @"crash", @"seconds": @0,
			@"detail": @"process sap / xe ngat trong buoc nay (xem CARPLAY SAP LAN TRUOC trong log)"}];
		OMCTestLog(@"[%@ %ld/%lu] CRASH %@", suite, (long)index + 1, (unsigned long)steps.count, name);
		index++;
	}
	R[@"index"] = @(index);
	R[@"running"] = @YES;
	R[@"gen"] = @(OMCTestGen() + 1);
	[R removeObjectForKey:@"waiting"];
	if (index == 0) OMCTestLog(@"===== %@: %lu buoc, iOS %@ =====", suite, (unsigned long)steps.count, [UIDevice currentDevice].systemVersion);
	else OMCTestLog(@"===== %@: chay tiep tu buoc %ld/%lu =====", suite, (long)index + 1, (unsigned long)steps.count);
	if (!OMCTestSave(@{@"step": @(index), @"inStep": @NO, @"results": results})) return;
	OMCTestShowBanner(OMCTestProgress());
	OMCTestAfter(OMC_TEST_GAP, ^{ OMCTestNext(); });
}

static void OMCTestEndSuite(void) {
	NSMutableDictionary *R = OMCTestR();
	NSString *suite = OMCTestSuiteName();
	R[@"running"] = @NO;
	R[@"gen"] = @(OMCTestGen() + 1);
	NSDictionary *d = OMCTestStored();
	NSUInteger next = [d[@"suite"] unsignedIntegerValue] + 1, count = [d[@"suites"] count];
	OMCTestLog(@"===== %@: xong =====", suite);
	BOOL last = next >= count;
	if (!OMCTestSave(last ? @{@"state": @"done", @"suite": @(next), @"step": @0, @"inStep": @NO}
	                      : @{@"suite": @(next), @"step": @0, @"inStep": @NO})) return;
	if (!last) {
		OMCTestHideBanner();
		notify_post(OMC_DARWIN_AUTOTEST);   // the process owning the next suite takes over
		return;
	}
	// Whole run done: summary file + log + a few seconds on the bar
	NSArray *results = OMCTestStored()[@"results"];
	NSUInteger pass = 0, fail = 0, skip = 0;
	NSMutableString *txt = [NSMutableString string];
	for (NSDictionary *r in results) {
		NSString *st = r[@"status"];
		if ([st isEqualToString:@"pass"]) pass++; else if ([st isEqualToString:@"skip"]) skip++; else fail++;
		[txt appendFormat:@"%@ [%@] %@ (%@s)%@\n", st.uppercaseString, r[@"suite"], r[@"name"], r[@"seconds"],
			r[@"detail"] ? [@" - " stringByAppendingString:r[@"detail"]] : @""];
	}
	NSString *head = OMCTestFormat(@"OmniCar auto test %@, iOS %@: %lu pass, %lu fail, %lu skip\n\n", d[@"run"],
		[UIDevice currentDevice].systemVersion, (unsigned long)pass, (unsigned long)fail, (unsigned long)skip);
	[[head stringByAppendingString:txt] writeToFile:[OMC_AUTOTEST_DIR stringByAppendingPathComponent:@"autotest.txt"] atomically:YES
		encoding:NSUTF8StringEncoding error:nil];
	OMCTestLog(@"===== XONG tu kiem tra: %lu dat, %lu loi, %lu bo qua =====\n%@", (unsigned long)pass, (unsigned long)fail, (unsigned long)skip, txt);
	OMCTestShowBanner(OMCTestFormat(@"OmniCar test: %lu pass · %lu fail · %lu skip", (unsigned long)pass, (unsigned long)fail, (unsigned long)skip));
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (!OMCTestRunning()) OMCTestHideBanner();
	});
}

static void OMCTestPoll(void);

static void OMCTestNext(void) {
	NSArray *steps = OMCTestSteps();
	NSInteger index = OMCTestIndex();
	if (index >= (NSInteger)steps.count) { OMCTestEndSuite(); return; }
	NSDictionary *step = steps[index];
	// dies in this step -> next launch knows which; stepName / stepCount: the Autotest page shows the step running
	if (!OMCTestSave(@{@"step": @(index), @"inStep": @YES, @"stepName": step[@"name"] ?: @"", @"stepCount": @(steps.count)})) return;
	OMCTestShowBanner(OMCTestProgress());
	OMCTestLog(@"[%@ %ld/%lu] %@ ...", OMCTestSuiteName(), (long)index + 1, (unsigned long)steps.count, step[@"name"]);
	NSInteger gen = OMCTestGen();
	dispatch_block_t go = ^{
		if (!OMCTestRunning() || OMCTestGen() != gen) return;
		OMCTestR()[@"stepStart"] = @(CFAbsoluteTimeGetCurrent());
		OMCTestBlock run = step[@"run"];
		NSString *skip = nil;
		@try { skip = run ? run() : nil; }
		@catch (NSException *e) { OMCTestFinishStep(@"fail", OMCTestFormat(@"exception: %@", e)); return; }
		if (skip) { OMCTestFinishStep(@"skip", skip); return; }
		if (!step[@"check"]) { OMCTestFinishStep(@"pass", nil); return; }
		OMCTestAfter([step[@"settle"] doubleValue], ^{ OMCTestPoll(); });
	};
	// The step names where it touches (OMCTestStepAt): the finger comes there and presses, then the step runs
	OMCTestPointBlock at = step[@"at"];
	NSValue *pv = nil;
	@try { pv = at ? at() : nil; } @catch (NSException *e) { pv = nil; }
	UIWindow *fw = pv ? OMCTestFingerWindow() : nil;
	if (fw) OMCTestFingerTap(fw, [fw convertPoint:pv.CGPointValue fromWindow:nil], go);
	else go();
}

static void OMCTestPoll(void) {
	NSDictionary *step = OMCTestSteps()[OMCTestIndex()];
	OMCTestBlock check = step[@"check"];
	NSString *why = check();
	if (!why) { OMCTestFinishStep(@"pass", nil); return; }
	if (CFAbsoluteTimeGetCurrent() - [OMCTestR()[@"stepStart"] doubleValue] >= [step[@"timeout"] doubleValue]) {
		OMCTestFinishStep(@"fail", why);
		return;
	}
	OMCTestAfter(OMC_TEST_POLL, ^{ OMCTestPoll(); });
}

static void OMCTestFinishStep(NSString *status, NSString *detail) {
	NSArray *steps = OMCTestSteps();
	NSInteger index = OMCTestIndex();
	if (index >= (NSInteger)steps.count) return;
	NSString *suite = OMCTestSuiteName(), *name = steps[index][@"name"];
	double secs = CFAbsoluteTimeGetCurrent() - [OMCTestR()[@"stepStart"] doubleValue];
	NSMutableDictionary *r = [@{@"suite": suite, @"name": name, @"status": status, @"seconds": @(round(secs * 10) / 10)} mutableCopy];
	if (detail) r[@"detail"] = detail;
	OMCTestLog(@"[%@ %ld/%lu] %@ %@ (%.1fs)%@", suite, (long)index + 1, (unsigned long)steps.count, status.uppercaseString, name, secs,
		detail ? [@": " stringByAppendingString:detail] : @"");
	NSArray *results = [OMCTestStored()[@"results"] ?: @[] arrayByAddingObject:r];
	OMCTestR()[@"index"] = @(index + 1);
	if (!OMCTestSave(@{@"step": @(index + 1), @"inStep": @NO, @"results": results})) return;
	OMCTestAfter([status isEqualToString:@"fail"] ? OMC_TEST_FAIL_GAP : OMC_TEST_GAP, ^{ OMCTestNext(); });
}

// Whose turn is it? Runs this process's suite when it is current and ready; keeps looking while a run is on.
static void OMCTestTick(void) {
	NSMutableDictionary *R = OMCTestR();
	NSDictionary *d = OMCTestStored();
	NSString *state = d[@"state"];
	if (![state isEqual:@"running"]) {
		if (OMCTestRunning()) {
			OMCTestLog(@"===== DUNG o %@ buoc %ld (%@) =====", OMCTestSuiteName(), (long)OMCTestIndex() + 1, state);
			R[@"running"] = @NO;
			R[@"gen"] = @(OMCTestGen() + 1);
			OMCTestHideBanner();
		}
		[(NSTimer *)R[@"timer"] invalidate];
		[R removeObjectForKey:@"timer"];
		return;
	}
	if (!R[@"timer"]) {
		R[@"timer"] = [NSTimer scheduledTimerWithTimeInterval:OMC_TEST_TICK repeats:YES block:^(NSTimer *t) { OMCTestTick(); }];
	}
	if (OMCTestRunning()) return;
	NSArray *suites = d[@"suites"];
	NSUInteger i = [d[@"suite"] unsignedIntegerValue];
	if (i >= suites.count) return;
	NSDictionary *entry = R[@"suites"][suites[i]];
	if (!entry) return;   // another process's suite
	BOOL (^ready)(void) = entry[@"ready"];
	BOOL ok = NO;
	@try { ok = !ready || ready(); } @catch (NSException *e) {}
	if (!ok) {
		if (![R[@"waiting"] isEqual:suites[i]]) OMCTestLog(@"%@: cho san sang (cam xe / mo tinh nang)", suites[i]);
		R[@"waiting"] = suites[i];
		return;
	}
	if ([d[@"suite"] unsignedIntegerValue] == 0 && [d[@"step"] integerValue] == 0 && ![d[@"results"] count]) {
		NSFileManager *fm = [NSFileManager defaultManager];   // fresh run: old files go (snapshots of older builds too)
		[fm removeItemAtPath:OMC_AUTOTEST_DIR error:nil];
		[fm createDirectoryAtPath:OMC_AUTOTEST_DIR withIntermediateDirectories:YES attributes:nil error:nil];
	}
	OMCTestStartSuite(d);
}

static void OMCTestBannerTapped(void) {
	NSDictionary *d = OMCTestStored();
	if (![d[@"state"] isEqual:@"running"]) { OMCTestHideBanner(); return; }
	NSMutableDictionary *m = [d mutableCopy];
	m[@"state"] = @"stopped";
	OMCTestStore(m);
	OMCTestLog(@"dung bang thanh tren xe");
	notify_post(OMC_DARWIN_AUTOTEST);
	OMCTestTick();
}

void OMCTestRegister(NSString *suite, BOOL (^ready)(void), NSArray<NSDictionary *> *(^build)(void), NSArray<UIWindow *> *(^windows)(void)) {
	if (!suite.length || !build) return;
	NSMutableDictionary *R = OMCTestR();
	NSMutableDictionary *entry = [@{@"build": [build copy]} mutableCopy];
	if (ready) entry[@"ready"] = [ready copy];
	if (windows) entry[@"windows"] = [windows copy];
	BOOL first = !R[@"listening"];
	R[@"suites"][suite] = entry;
	// Settings lists what is available (a suite of a process that never started is not offered)
	NSString *key = [OMC_KEY_AUTOTEST_AVAIL stringByAppendingString:suite];
	NSDictionary *avail = @{@"process": [NSProcessInfo processInfo].processName, @"date": [NSDate date]};
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)avail, OMC_PREFS_DOMAIN);
	CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
	OMCTestLog(@"bo test %@ san sang trong %@", suite, [NSProcessInfo processInfo].processName);
	if (first) {
		R[@"listening"] = @YES;
		static int token;
		notify_register_dispatch(OMC_DARWIN_AUTOTEST, &token, dispatch_get_main_queue(), ^(int t) { OMCTestTick(); });
	}
	// A run may be on already (this process just restarted after a crash, or the car just connected)
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OMCTestTick(); });
}

#endif
