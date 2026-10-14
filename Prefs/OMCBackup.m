#import "OMCBackup.h"
#import "OMCTheme.h"
#import "OMCDiagnostics.h"
#import "OmniCar.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <notify.h>
#import <objc/runtime.h>

#ifndef TWEAK_VERSION
#define TWEAK_VERSION "dev"
#endif

#define OMC_BACKUP_ERROR_DOMAIN @"com.anlai.omnicar.backup"

#pragma mark - Keys

// Runtime state the tweak or Settings writes by itself: diagnostics, auto test, rescue mode, guides already seen,
// the last split, crash markers and caches. A backup leaves them out and a restore never touches them.
BOOL OMCBackupOwnsKey(NSString *key) {
	static NSArray<NSString *> *prefixes;
	static NSSet<NSString *> *exact;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		prefixes = @[@"diag", @"autoTest", @"rescue", @"debug", @"onboarding", @"whatsNew"];
		exact = [NSSet setWithArray:@[
			@"splitScreenIconsPending", @"splitScreenIconsCrashed", @"splitScreenCarPlayApps", @"splitScreenTipCount",
			@"splitScreenLastLeft", @"splitScreenLastRight", @"splitScreenMigrated",
			@"speedBubbleGPSStatus", @"carProfileCurrent",
		]];
	});
	if (![key isKindOfClass:[NSString class]] || !key.length || [exact containsObject:key]) return NO;
	for (NSString *prefix in prefixes) if ([key hasPrefix:prefix]) return NO;
	return YES;
}

static NSArray<NSString *> *OMCBackupCurrentKeys(void) {
	CFPreferencesAppSynchronize(kPrefsDomain);
	NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
	return keys ?: @[];
}

static NSError *OMCBackupError(NSString *key) {
	return [NSError errorWithDomain:OMC_BACKUP_ERROR_DOMAIN code:1 userInfo:@{NSLocalizedDescriptionKey: L(key)}];
}

// Path under OMC_DATA_ROOT for a relative path from a backup; nil when it would leave the folder.
static NSString *OMCBackupFilePath(NSString *rel) {
	if (![rel isKindOfClass:[NSString class]] || !rel.length || rel.isAbsolutePath) return nil;
	for (NSString *part in rel.pathComponents)
		if ([part isEqualToString:@".."] || [part isEqualToString:@"."] || [part isEqualToString:@"/"]) return nil;
	return [OMC_DATA_ROOT stringByAppendingPathComponent:rel];
}

#pragma mark - Write / read

NSURL *OMCBackupWrite(NSArray<NSString *> **skipped, NSError **error) {
	NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
	for (NSString *key in OMCBackupCurrentKeys()) {
		if (!OMCBackupOwnsKey(key)) continue;
		id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain));
		if (value) prefs[key] = value;
	}

	// User files (startup videos, frames, images, sounds ...): everything under OMC_DATA_ROOT up to the size limit.
	// Mapped reads keep big videos out of memory until the plist is streamed to disk.
	NSMutableDictionary *files = [NSMutableDictionary dictionary];
	NSMutableArray *left = [NSMutableArray array];
	unsigned long long total = 0;
	NSString *root = OMC_DATA_ROOT;
	NSSet *caches = [NSSet setWithArray:@[@"StartupScreen/weather.plist"]];   // rebuilt by the tweak, not user data
	NSDirectoryEnumerator *walker = [[NSFileManager defaultManager] enumeratorAtPath:root];
	for (NSString *rel in walker) {
		NSDictionary *attrs = walker.fileAttributes;
		if (![attrs.fileType isEqualToString:NSFileTypeRegular] || [rel.lastPathComponent hasPrefix:@"."]) continue;
		if ([caches containsObject:rel]) continue;
		unsigned long long size = attrs.fileSize;
		if (total + size > OMC_BACKUP_MAX_BYTES) { [left addObject:rel]; continue; }
		NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:rel] options:NSDataReadingMappedIfSafe error:nil];
		if (!data) { [left addObject:rel]; continue; }
		files[rel] = data;
		total += size;
	}
	if (skipped) *skipped = left;

	NSDictionary *backup = @{
		@"format": @(OMC_BACKUP_FORMAT),
		@"version": @TWEAK_VERSION,
		@"date": [NSDate date],
		@"prefs": prefs,
		@"files": files,
	};

	NSDateFormatter *df = [NSDateFormatter new];
	df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	df.dateFormat = @"yyyy-MM-dd";
	NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OmniCarBackup"];
	[[NSFileManager defaultManager] removeItemAtPath:dir error:nil];   // last backup shared
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"OmniCar-%@.%@", [df stringFromDate:[NSDate date]], OMC_BACKUP_EXTENSION]];

	NSOutputStream *out = [NSOutputStream outputStreamToFileAtPath:path append:NO];
	[out open];
	NSInteger written = [NSPropertyListSerialization writePropertyList:backup toStream:out format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
	[out close];
	if (written <= 0) {
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
		if (error && !*error) *error = OMCBackupError(@"BAK_ERR_WRITE");
		return nil;
	}
	return [NSURL fileURLWithPath:path];
}

NSDictionary *OMCBackupRead(NSURL *url, NSError **error) {
	BOOL scoped = [url startAccessingSecurityScopedResource];
	NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
	id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil] : nil;
	data = nil;
	if (scoped) [url stopAccessingSecurityScopedResource];

	NSDictionary *backup = [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
	if (!backup || ![backup[@"format"] isKindOfClass:[NSNumber class]] || ![backup[@"prefs"] isKindOfClass:[NSDictionary class]]) {
		if (error) *error = OMCBackupError(@"BAK_ERR_NOT_BACKUP");
		return nil;
	}
	if ([backup[@"format"] integerValue] > OMC_BACKUP_FORMAT) {
		if (error) *error = OMCBackupError(@"BAK_ERR_NEWER");
		return nil;
	}
	if (backup[@"files"] && ![backup[@"files"] isKindOfClass:[NSDictionary class]]) {
		if (error) *error = OMCBackupError(@"BAK_ERR_NOT_BACKUP");
		return nil;
	}
	return backup;
}

NSString *OMCBackupSummary(NSDictionary *backup) {
	NSUInteger prefCount = 0;
	for (NSString *key in backup[@"prefs"]) if (OMCBackupOwnsKey(key)) prefCount++;

	NSDictionary *files = [backup[@"files"] isKindOfClass:[NSDictionary class]] ? backup[@"files"] : @{};
	unsigned long long bytes = 0;
	NSMutableOrderedSet *folders = [NSMutableOrderedSet orderedSet];   // top folder = the feature ("StartupScreen")
	for (NSString *rel in files) {
		id data = files[rel];
		if (!OMCBackupFilePath(rel) || ![data isKindOfClass:[NSData class]]) continue;
		bytes += [(NSData *)data length];
		[folders addObject:rel.pathComponents.count > 1 ? rel.pathComponents.firstObject : rel];
	}

	NSDateFormatter *df = [NSDateFormatter new];
	df.locale = [NSLocale localeWithLocaleIdentifier:OMCLanguage()];
	df.dateStyle = NSDateFormatterMediumStyle;
	df.timeStyle = NSDateFormatterShortStyle;
	NSDate *date = [backup[@"date"] isKindOfClass:[NSDate class]] ? backup[@"date"] : nil;
	NSString *version = [backup[@"version"] isKindOfClass:[NSString class]] ? backup[@"version"] : @"?";

	NSMutableArray *lines = [NSMutableArray array];
	[lines addObject:[NSString stringWithFormat:L(@"BAK_SUMMARY_HEAD"), date ? [df stringFromDate:date] : @"?", version]];
	[lines addObject:[NSString stringWithFormat:L(@"BAK_SUMMARY_PREFS"), (unsigned long)prefCount]];
	if (folders.count) {
		NSString *size = [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
		[lines addObject:[NSString stringWithFormat:L(@"BAK_SUMMARY_FILES"), (unsigned long)files.count, size, [folders.array componentsJoinedByString:@", "]]];
	}
	[lines addObject:L(@"BAK_SUMMARY_FOOT")];
	return [lines componentsJoinedByString:@"\n"];
}

BOOL OMCBackupRestore(NSDictionary *backup, NSError **error) {
	// Files first, so a full disk leaves the settings as they were.
	NSDictionary *files = [backup[@"files"] isKindOfClass:[NSDictionary class]] ? backup[@"files"] : @{};
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *rel in files) {
		NSString *path = OMCBackupFilePath(rel);
		id data = files[rel];
		if (!path || ![data isKindOfClass:[NSData class]]) continue;
		[fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
		if (![(NSData *)data writeToFile:path options:NSDataWritingAtomic error:nil]) {
			if (error) *error = OMCBackupError(@"BAK_ERR_FILES");
			return NO;
		}
	}

	// Owned keys the backup lacks go back to their defaults; runtime keys stay as they are.
	NSDictionary *prefs = backup[@"prefs"];
	for (NSString *key in OMCBackupCurrentKeys())
		if (OMCBackupOwnsKey(key) && !prefs[key]) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, kPrefsDomain);
	for (NSString *key in prefs)
		if (OMCBackupOwnsKey(key)) CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)prefs[key], kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	notify_post("com.anlai.omnicar/prefschanged");
	return YES;
}

#pragma mark - UI

static void OMCBackupAlert(UIViewController *vc, NSString *title, NSString *message) {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[vc presentViewController:alert animated:YES completion:nil];
}

// "Preparing ..." alert while the file is written or read off the main thread.
static UIAlertController *OMCBackupBusyAlert(NSString *message) {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:message message:@"\n\n" preferredStyle:UIAlertControllerStyleAlert];
	UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[spinner startAnimating];
	[alert.view addSubview:spinner];
	[NSLayoutConstraint activateConstraints:@[
		[spinner.centerXAnchor constraintEqualToAnchor:alert.view.centerXAnchor],
		[spinner.bottomAnchor constraintEqualToAnchor:alert.view.bottomAnchor constant:-20],
	]];
	return alert;
}

static void OMCBackupPresentShare(UIViewController *vc, NSURL *url) {
	UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	UIPopoverPresentationController *pop = share.popoverPresentationController;   // iPad
	pop.sourceView = vc.view;
	pop.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
	[vc presentViewController:share animated:YES completion:nil];
}

void OMCBackupShare(UIViewController *vc) {
	if (vc.presentedViewController) return;
	UIAlertController *busy = OMCBackupBusyAlert(L(@"BAK_PREPARING"));
	__weak UIViewController *weakVC = vc;
	[vc presentViewController:busy animated:YES completion:^{
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSArray<NSString *> *skipped = nil;
			NSError *error = nil;
			NSURL *url = OMCBackupWrite(&skipped, &error);
			dispatch_async(dispatch_get_main_queue(), ^{
				[busy dismissViewControllerAnimated:YES completion:^{
					UIViewController *host = weakVC;
					if (!host) return;
					if (!url) {
						OMCBackupAlert(host, L(@"BAK_FAILED"), error.localizedDescription);
						return;
					}
					if (!skipped.count) {
						OMCBackupPresentShare(host, url);
						return;
					}
					// Over the size limit: say which files stayed out, then share the rest.
					NSString *message = [NSString stringWithFormat:L(@"BAK_SKIPPED"), (unsigned long)(OMC_BACKUP_MAX_BYTES / (1024 * 1024)),
						[skipped componentsJoinedByString:@"\n"]];
					UIAlertController *warn = [UIAlertController alertControllerWithTitle:L(@"BAK_SKIPPED_TITLE") message:message preferredStyle:UIAlertControllerStyleAlert];
					[warn addAction:[UIAlertAction actionWithTitle:L(@"BAK_CONTINUE") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
						UIViewController *strongHost = weakVC;
						if (strongHost) OMCBackupPresentShare(strongHost, url);
					}]];
					[host presentViewController:warn animated:YES completion:nil];
				}];
			});
		});
	}];
}

#pragma mark - Restore

// Files picker delegate, kept alive by the picker itself (UIDocumentPickerViewController.delegate is weak).
@interface OMCBackupPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, copy) void (^done)(void);
@end

static char kOMCBackupPickerKey;

@implementation OMCBackupPicker

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *url = urls.firstObject;
	if (!url) return;
	// Let the picker finish closing before the next alert goes up.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self readURL:url];
	});
}

- (void)readURL:(NSURL *)url {
	UIViewController *host = self.host;
	if (!host || host.presentedViewController) return;
	UIAlertController *busy = OMCBackupBusyAlert(L(@"BAK_READING"));
	[host presentViewController:busy animated:YES completion:^{
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSError *error = nil;
			NSDictionary *backup = OMCBackupRead(url, &error);
			dispatch_async(dispatch_get_main_queue(), ^{
				[busy dismissViewControllerAnimated:YES completion:^{
					UIViewController *strongHost = self.host;
					if (!strongHost) return;
					if (!backup) OMCBackupAlert(strongHost, L(@"BAK_RESTORE_FAILED"), error.localizedDescription);
					else [self confirmBackup:backup];
				}];
			});
		});
	}];
}

- (void)confirmBackup:(NSDictionary *)backup {
	UIViewController *host = self.host;
	if (!host) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"BAK_RESTORE_CONFIRM") message:OMCBackupSummary(backup) preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"BAK_RESTORE_BUTTON") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		[self restoreBackup:backup];
	}]];
	[host presentViewController:alert animated:YES completion:nil];
}

- (void)restoreBackup:(NSDictionary *)backup {
	UIViewController *host = self.host;
	if (!host) return;
	UIAlertController *busy = OMCBackupBusyAlert(L(@"BAK_RESTORING"));
	[host presentViewController:busy animated:YES completion:^{
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSError *error = nil;
			BOOL ok = OMCBackupRestore(backup, &error);
			dispatch_async(dispatch_get_main_queue(), ^{
				[busy dismissViewControllerAnimated:YES completion:^{
					if (ok && self.done) self.done();
					UIViewController *strongHost = self.host;
					if (!strongHost) return;
					if (!ok) {
						OMCBackupAlert(strongHost, L(@"BAK_RESTORE_FAILED"), error.localizedDescription);
						return;
					}
					// Every feature reads the new values on the next respring.
					UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:L(@"BAK_RESTORED") message:L(@"BAK_RESTORED_TEXT") preferredStyle:UIAlertControllerStyleAlert];
					[doneAlert addAction:[UIAlertAction actionWithTitle:L(@"BAK_LATER") style:UIAlertActionStyleCancel handler:nil]];
					[doneAlert addAction:[UIAlertAction actionWithTitle:L(@"RESPRING") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
						OMCRespring();
					}]];
					[strongHost presentViewController:doneAlert animated:YES completion:nil];
				}];
			});
		});
	}];
}

@end

BOOL OMCBackupOfferImported(UIViewController *vc, void (^done)(void)) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *inbox = OMC_BACKUP_INBOX;
	if (vc.presentedViewController || ![fm fileExistsAtPath:inbox]) return NO;
	NSString *taken = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Import.omnicar"];
	[fm removeItemAtPath:taken error:nil];
	if (![fm moveItemAtPath:inbox toPath:taken error:nil]) return NO;
	OMCBackupPicker *flow = [OMCBackupPicker new];
	flow.host = vc;
	flow.done = done;
	objc_setAssociatedObject(vc, &kOMCBackupPickerKey, flow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // alive while the alerts run
	[flow readURL:[NSURL fileURLWithPath:taken]];
	return YES;
}

void OMCBackupPickAndRestore(UIViewController *vc, void (^done)(void)) {
	if (vc.presentedViewController) return;
	// Accept any data file (backups made before the .omnicar type was registered too) and let OMCBackupRead check it.
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
	OMCBackupPicker *delegate = [OMCBackupPicker new];
	delegate.host = vc;
	delegate.done = done;
	objc_setAssociatedObject(picker, &kOMCBackupPickerKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	picker.delegate = delegate;
	picker.allowsMultipleSelection = NO;
	[vc presentViewController:picker animated:YES completion:nil];
}
