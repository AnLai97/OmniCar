// OmniCarCore.dylib - loaded into SpringBoard only. Hosts the process-wide services the feature
// dylibs cannot own without duplicating them: the log relay for sandboxed apps.

#import "OmniCar.h"

%ctor {
	@autoreleasepool {
		OMCLogRelayStart();
		OMCLog(@"Core", @"loaded into %@ enabled=%d", [NSBundle mainBundle].bundleIdentifier, OMCEnabled());
	}
}
