// OmniCar auto test - developer only. Everything here exists only when OMC_AUTOTEST is 1 (Core/OmniCar.h);
// release builds set it to 0 and neither the runner, the test cases nor the Settings page are compiled.
//
// Each feature registers one suite (named by its key prefix: "splitScreen", "speedBubble" ...) in the
// process that can drive it, usually from its %ctor. Settings > OmniCar > Developer > Autotest lists the
// registered suites, the developer picks some and starts; the suites run one after another (a suite of
// another process waits for its turn), each step logs PASS / FAIL + reason to OmniCar.log and is stored in
// OMC_KEY_AUTOTEST (no car-screen snapshots). A crash in the middle: the process that restarts marks that step
// "crash" and goes on with the next one. Send log carries the results.
//
// The run is paced for a person watching the car screen (OMC_TEST_GAP seconds between steps) and a finger is drawn
// where each step touches: a step made with OMCTestStepAt names its point on the car screen, the runner brings the
// finger there, presses, then runs the step. A touch inside an app (tap a YouTube video, drag the Google Maps map) is
// made by the app itself with OMCTestTouch* below (the App Bridge dylib is in every app), finger included.
//
//   OMCTestRegister(@"speedBubble", ^BOOL { return carConnected; }, ^NSArray *{
//       return @[ OMCTestStep(@"Hien tren xe", 1, 5, ^NSString *{ ...; return nil; }, ^NSString *{ return ok ? nil : @"why"; }) ];
//   }, nil);
#import "OmniCar.h"

#if OMC_AUTOTEST
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef NSString *(^OMCTestBlock)(void);
// Where a step touches the car screen (screen points of the car display); nil = no finger for this step.
typedef NSValue *(^OMCTestPointBlock)(void);

// One step. run: does the action, returns nil, or why the step is skipped. check: polled every 0.5 s from
// `settle` s after run until it returns nil (pass) or `timeout` s have gone by (fail with its last reason).
// check nil = pass as soon as run returns.
NSDictionary *OMCTestStep(NSString *name, double settle, double timeout, OMCTestBlock run, OMCTestBlock check);
// The same with a finger: `at` gives the car-screen point the step touches; the finger comes there and presses, then
// run is called (the timing of the step starts at run).
NSDictionary *OMCTestStepAt(NSString *name, double settle, double timeout, OMCTestPointBlock at, OMCTestBlock run, OMCTestBlock check);

// ready: the suite can start now (car connected, the feature is up). build: the steps, built when the suite
// starts. windows: no longer used (snapshots were dropped), pass nil.
void OMCTestRegister(NSString *suite, BOOL (^ready)(void), NSArray<NSDictionary *> *(^build)(void), NSArray<UIWindow *> *(^windows)(void));

// Finger drawn in `host` (a window or a view that covers it; p in host coordinates): it comes in from below-right, presses
// at p (`press` runs at that moment: the real action), holds a little and lifts. No touch is made by this.
void OMCTestFingerTap(UIView *host, CGPoint p, dispatch_block_t press);
// Finger drag: presses at `from` (`began`), slides to `to` in `duration` s calling `move` with each point, lifts (`ended`).
void OMCTestFingerDrag(UIView *host, CGPoint from, CGPoint to, double duration, dispatch_block_t began, void (^move)(CGPoint), dispatch_block_t ended);

// Synthetic touch in THIS process, through UIKit like a real one (private UITouch / UITouchesEvent API, the way KIF does
// it): the hit view, its gesture recognizers and controls all see it. Finger drawn in the window. done: the view the touch
// reached (nil = none) and whether a gesture recognizer of it or a parent took it.
void OMCTestTouchTap(UIWindow *window, CGPoint p, void (^done)(UIView *hit, BOOL gesture));
void OMCTestTouchDrag(UIWindow *window, CGPoint from, CGPoint to, double duration, void (^done)(UIView *hit, BOOL gesture));

NSString *OMCTestFormat(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
// Short log line in the suite's log ("[OmniCar/AutoTest]").
#define OMCTestLog(fmt, ...) OMCLogWrite(@"AutoTest", [NSString stringWithFormat:fmt, ##__VA_ARGS__])

#ifdef __cplusplus
}
#endif
#endif
