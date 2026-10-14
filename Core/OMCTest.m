// Auto test runner (developer only, see Core/OMCTest.h). Compiled into every feature dylib like OmniCar.m,
// so the runner of a process is shared through one dictionary on the main thread: the first dylib that
// registers a suite creates it and installs the listeners, the others only add their suites. No class is
// declared here (each dylib would carry its own copy of it); state is plain dictionaries and blocks.
#import "OMCTest.h"

#if OMC_AUTOTEST
#import <notify.h>

#define OMC_TEST_POLL      0.5    // s between two checks of a step
#define OMC_TEST_TICK      2.0    // s between two looks at whose turn it is while a run is on
#define OMC_TEST_GAP       1.0    // s after a step before the next one
#define OMC_TEST_FAIL_GAP  2.5

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

#pragma mark - Car screen: snapshot + progress bar

static UIWindowScene *OMCTestCarScene(void) {
	for (UIScene *sc in [UIApplication sharedApplication].connectedScenes)
		if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen != [UIScreen mainScreen]) return (UIWindowScene *)sc;
	return nil;
}

static NSArray<UIWindow *> *OMCTestCarWindows(void) {
	NSMutableArray *out = [NSMutableArray array];
	UIWindowScene *scene = OMCTestCarScene();
	if (scene) [out addObjectsFromArray:scene.windows];
	else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.screen != [UIScreen mainScreen]) [out addObject:w];
#pragma clang diagnostic pop
	}
	return out;
}

// What CarPlay / SpringBoard draws itself (panes, dividers, bars, bubble). Content of other processes (CarPlay
// app scenes, hosted iPhone apps) may come out black.
static NSString *OMCTestSnapshot(NSString *name) {
	@try {
		NSArray<UIWindow *> *(^custom)(void) = OMCTestR()[@"windows"];
		NSMutableArray<UIWindow *> *windows = [(custom ? custom() : OMCTestCarWindows()) mutableCopy];
		[windows removeObject:OMCTestR()[@"banner"]];
		[windows sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
			return a.windowLevel < b.windowLevel ? NSOrderedAscending : (a.windowLevel > b.windowLevel ? NSOrderedDescending : NSOrderedSame);
		}];
		CGRect bounds = CGRectNull;
		for (UIWindow *w in windows) if (!w.hidden) bounds = CGRectUnion(bounds, w.frame);
		if (CGRectIsNull(bounds) || bounds.size.width < 10 || bounds.size.height < 10) return nil;
		UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
		fmt.scale = 1;
		UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:bounds.size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
			[[UIColor blackColor] setFill];
			UIRectFill(CGRectMake(0, 0, bounds.size.width, bounds.size.height));
			for (UIWindow *w in windows)
				if (!w.hidden) [w drawViewHierarchyInRect:CGRectOffset(w.frame, -bounds.origin.x, -bounds.origin.y) afterScreenUpdates:NO];
		}];
		NSString *file = [name stringByAppendingPathExtension:@"jpg"];
		NSString *path = [OMC_AUTOTEST_DIR stringByAppendingPathComponent:file];
		return [UIImageJPEGRepresentation(img, 0.6) writeToFile:path atomically:YES] ? file : nil;
	} @catch (NSException *e) {
		OMCTestLog(@"chup man xe loi: %@", e);
		return nil;
	}
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

static void OMCTestHideBanner(void) {
	NSMutableDictionary *R = OMCTestR();
	((UIWindow *)R[@"banner"]).hidden = YES;
	[R removeObjectsForKeys:@[@"banner", @"label", @"tapTarget"]];
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
	if (!OMCTestSave(@{@"step": @(index), @"inStep": @YES})) return;   // dies in this step -> next launch knows which
	OMCTestShowBanner(OMCTestProgress());
	OMCTestLog(@"[%@ %ld/%lu] %@ ...", OMCTestSuiteName(), (long)index + 1, (unsigned long)steps.count, step[@"name"]);
	OMCTestR()[@"stepStart"] = @(CFAbsoluteTimeGetCurrent());
	OMCTestBlock run = step[@"run"];
	NSString *skip = nil;
	@try { skip = run ? run() : nil; }
	@catch (NSException *e) { OMCTestFinishStep(@"fail", OMCTestFormat(@"exception: %@", e)); return; }
	if (skip) { OMCTestFinishStep(@"skip", skip); return; }
	if (!step[@"check"]) { OMCTestFinishStep(@"pass", nil); return; }
	OMCTestAfter([step[@"settle"] doubleValue], ^{ OMCTestPoll(); });
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
	NSString *shot = OMCTestSnapshot(OMCTestFormat(@"%@-%02ld-%@", suite, (long)index + 1, status));
	if (shot) r[@"shot"] = shot;
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
		NSFileManager *fm = [NSFileManager defaultManager];   // fresh run: old snapshots go
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
