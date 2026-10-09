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

// One file for every feature and process, readable with Filza. A process that cannot write it
// (sandboxed apps: Vietmap Live, GOFA) relays the line to SpringBoard, where the
// OmniCarCore dylib appends it (OMCLogRelayStart). The file is rotated at OMC_LOG_MAX_BYTES.
static NSString *const kLogPath = @"/var/mobile/Documents/OmniCar.log";
static const unsigned long long OMC_LOG_MAX_BYTES = 2 * 1024 * 1024;

static dispatch_queue_t OMCLogQueue(void) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.anlai.omnicar.log", DISPATCH_QUEUE_SERIAL); });
	return queue;
}

static BOOL OMCLogAppend(NSString *line) {
	FILE *f = fopen(kLogPath.fileSystemRepresentation, "a");
	if (!f) return NO;
	fputs(line.UTF8String, f);
	fclose(f);
	return YES;
}

static void OMCLogRotateIfNeeded(void) {
	NSFileManager *fm = [NSFileManager defaultManager];
	unsigned long long size = [[fm attributesOfItemAtPath:kLogPath error:nil] fileSize];
	if (size < OMC_LOG_MAX_BYTES) return;
	NSString *old = [kLogPath stringByAppendingString:@".old"];
	[fm removeItemAtPath:old error:nil];
	[fm moveItemAtPath:kLogPath toPath:old error:nil];
}

static BOOL OMCIsSpringBoard(void) {
	static BOOL is;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ is = [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]; });
	return is;
}

// NSDistributedNotificationCenter is private on iOS but is an NSNotificationCenter subclass,
// so the public NSNotificationCenter API drives it.
static NSNotificationCenter *OMCDistributedCenter(void) {
	Class cls = NSClassFromString(@"NSDistributedNotificationCenter");
	return cls ? (NSNotificationCenter *)[cls defaultCenter] : nil;
}

void OMCLogWrite(NSString *feature, NSString *message) {
	NSLog(@"[OmniCar/%@] %@", feature, message);

	static NSDateFormatter *df;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		df = [NSDateFormatter new];
		df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
	});
	NSString *line = [NSString stringWithFormat:@"%@ [%@:%d] %@: %@\n", [df stringFromDate:[NSDate date]],
		[NSProcessInfo processInfo].processName, getpid(), feature, message];
	dispatch_async(OMCLogQueue(), ^{
		if (OMCIsSpringBoard()) OMCLogRotateIfNeeded();
		if (OMCLogAppend(line) || OMCIsSpringBoard()) return;
		[OMCDistributedCenter() postNotificationName:OMC_LOG_RELAY object:nil userInfo:@{@"line": line}];
	});
}

void OMCLogRelayStart(void) {
	if (!OMCIsSpringBoard()) return;
	[OMCDistributedCenter() addObserverForName:OMC_LOG_RELAY object:nil queue:nil usingBlock:^(NSNotification *note) {
		NSString *line = note.userInfo[@"line"];
		if (![line isKindOfClass:[NSString class]]) return;
		dispatch_async(OMCLogQueue(), ^{
			OMCLogRotateIfNeeded();
			OMCLogAppend(line);
		});
	}];
}
