#import "OmniCar.h"
#import <unistd.h>

#pragma mark - Preferences

void OMCPrefsSync(void) {
	CFPreferencesAppSynchronize(OMC_PREFS_DOMAIN);
}

id OMCPref(NSString *key, id fallback) {
	id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, OMC_PREFS_DOMAIN);
	return value ?: fallback;
}

BOOL OMCEnabled(void) {
	return [OMCPref(@"enabled", @YES) boolValue];
}

BOOL OMCFeatureEnabled(NSString *feature) {
	return OMCEnabled() && [OMCPref([feature stringByAppendingString:@"Enabled"], @YES) boolValue];
}

#pragma mark - Logging

// Logs go to syslog and to a file readable with Filza. If the process sandbox blocks the
// Documents folder, fall back to /var/tmp.
static NSString *const kLogPaths[] = { @"/var/mobile/Documents/OmniCar.log", @"/var/tmp/OmniCar.log" };

void OMCLogWrite(NSString *feature, NSString *message) {
	NSLog(@"[OmniCar/%@] %@", feature, message);

	static dispatch_queue_t queue;
	static NSDateFormatter *df;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("com.anlai.omnicar.log", DISPATCH_QUEUE_SERIAL);
		df = [NSDateFormatter new];
		df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
	});
	NSString *line = [NSString stringWithFormat:@"%@ [%d] %@: %@\n", [df stringFromDate:[NSDate date]], getpid(), feature, message];
	dispatch_async(queue, ^{
		for (size_t i = 0; i < sizeof(kLogPaths) / sizeof(kLogPaths[0]); i++) {
			FILE *f = fopen(kLogPaths[i].fileSystemRepresentation, "a");
			if (!f) continue;
			fputs(line.UTF8String, f);
			fclose(f);
			break;
		}
	});
}
