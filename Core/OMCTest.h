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

// One step. run: does the action, returns nil, or why the step is skipped. check: polled every 0.5 s from
// `settle` s after run until it returns nil (pass) or `timeout` s have gone by (fail with its last reason).
// check nil = pass as soon as run returns.
NSDictionary *OMCTestStep(NSString *name, double settle, double timeout, OMCTestBlock run, OMCTestBlock check);

// ready: the suite can start now (car connected, the feature is up). build: the steps, built when the suite
// starts. windows: no longer used (snapshots were dropped), pass nil.
void OMCTestRegister(NSString *suite, BOOL (^ready)(void), NSArray<NSDictionary *> *(^build)(void), NSArray<UIWindow *> *(^windows)(void));

NSString *OMCTestFormat(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
// Short log line in the suite's log ("[OmniCar/AutoTest]").
#define OMCTestLog(fmt, ...) OMCLogWrite(@"AutoTest", [NSString stringWithFormat:fmt, ##__VA_ARGS__])

#ifdef __cplusplus
}
#endif
#endif
