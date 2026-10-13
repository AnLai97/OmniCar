#import "OMCStartupScreenController.h"
#import "OMCTheme.h"
#import "../StartupScreen.h"
#import "../SSStartupView.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

// AVFoundation can't load media inside CarPlay.app, so each video is extracted here into JPEG
// frames under Videos/.frames/<video>/ that the tweak plays as a flipbook.
static const int32_t kFrameRate     = 24;
static const double kMaxFrameSeconds = 60.0;
static const CGFloat kMaxFrameSide   = 1920.0;
// Bump when the extraction output changes so existing videos are re-extracted.
static const NSInteger kFramesVersion = 2;
// The logo is re-encoded to a PNG no larger than this (CarPlay decodes it while starting up).
static const CGFloat kMaxLogoSide    = 1024.0;
// Preview card: the car screen shape (wide CarPlay displays are about 16:6), at most this wide on iPad.
static const CGFloat kPreviewAspect  = 6.0 / 16.0;
static const CGFloat kPreviewMaxWidth = 560.0;

// What the shared photo / file pickers are choosing.
typedef NS_ENUM(NSInteger, SSPickKind) {
	SSPickVideo,
	SSPickLogo,
	SSPickSound,
};

@interface PSSpecifier (StartupScreen)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end

@interface OMCStartupScreenController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, assign) BOOL extracting;
@property (nonatomic, assign) SSPickKind pickKind;
@property (nonatomic, strong) UIView *previewHeader;
@property (nonatomic, strong) UIView *previewShadow;
@property (nonatomic, strong) SSStartupView *preview;
@property (nonatomic, assign) CGFloat previewWidth;
@property (nonatomic, strong) AVAudioPlayer *soundPlayer;
@end

@implementation OMCStartupScreenController

static id SSPrefValue(NSString *key) {
	return key ? (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain) : nil;
}

static void SSSetPrefValue(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.anlai.omnicar/prefschanged"), NULL, NULL, YES);
}

static NSString *SSPrefString(NSString *key) {
	id value = SSPrefValue(key);
	return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSInteger)currentStyle {
	id value = SSPrefValue(SS_KEY_STYLE);
	NSInteger style = value ? [value integerValue] : SS_STYLE_VIDEO;
	return (style >= SS_STYLE_VIDEO && style <= SS_STYLE_WEATHER) ? style : SS_STYLE_VIDEO;
}

// The startup sound file name, when the file is still there.
- (NSString *)currentSound {
	NSString *name = SSPrefString(SS_KEY_SOUND_FILE);
	if (!name.length) return nil;
	return [[NSFileManager defaultManager] fileExistsAtPath:[SS_SOUNDS_DIR stringByAppendingPathComponent:name]] ? name : nil;
}

#pragma mark - Specifiers

- (NSArray *)specifiers {
	if (!_specifiers) {
		[super specifiers];
		NSInteger style = [self currentStyle];
		for (PSSpecifier *spec in [_specifiers copy]) {
			// Rows that belong to other styles (plist "ssStyles") are left out.
			NSArray *styles = [spec propertyForKey:@"ssStyles"];
			if ([styles isKindOfClass:[NSArray class]] && ![styles containsObject:@(style)]) {
				[_specifiers removeObject:spec];
				continue;
			}
			// Edit-text placeholders are string keys too (OMCLocalizeSpecifiers only does labels and footers).
			NSString *placeholder = [spec propertyForKey:@"placeholder"];
			if (placeholder) [spec setProperty:L(placeholder) forKey:@"placeholder"];

			if ([spec.identifier isEqualToString:@"soundGroup"]) {
				NSString *sound = [self currentSound];
				NSString *status = sound ? [NSString stringWithFormat:L(@"STARTUPSCREEN_SOUND_CURRENT"), sound] : L(@"STARTUPSCREEN_SOUND_NONE");
				[spec setProperty:[NSString stringWithFormat:@"%@\n%@", status, L(@"STARTUPSCREEN_STARTUP_SOUND_FOOTER")] forKey:@"footerText"];
			} else if ([spec.identifier isEqualToString:@"greetingGroup"] && style == SS_STYLE_WEATHER) {
				// Weather: say plainly that it uses the network, and when the last numbers came in.
				NSDictionary *cached = SSWeatherLoadCache(0);
				NSString *last = L(@"STARTUPSCREEN_WEATHER_NONE");
				NSDate *date = cached[SS_WX_DATE];
				if ([date isKindOfClass:[NSDate class]]) {
					last = [NSString stringWithFormat:L(@"STARTUPSCREEN_WEATHER_LAST"),
						[NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
				}
				[spec setProperty:[NSString stringWithFormat:@"%@\n\n%@\n%@", L(@"STARTUPSCREEN_GREETING_FOOTER"), L(@"STARTUPSCREEN_WEATHER_FOOTER"), last]
				           forKey:@"footerText"];
			}
		}
		[self refreshVideoList];
	}
	return _specifiers;
}

// Picking a style shows its rows right away; the preview follows every setting it draws.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
	NSString *key = [specifier propertyForKey:@"key"];
	if (!key) return;
	NSArray *previewKeys = @[SS_KEY_STYLE, SS_KEY_GREET_NAME, SS_KEY_LOGO_EFFECT, SS_KEY_VIDEO_NAME, SS_KEY_SCALE_MODE];
	if (![previewKeys containsObject:key]) return;
	// Write synchronously so the row filter and the preview read the new value.
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	if ([key isEqualToString:SS_KEY_STYLE]) {
		_specifiers = nil;
		[self reloadSpecifiers];
	}
	[self updatePreview];
}

#pragma mark - Preview

- (void)viewDidLoad {
	[super viewDidLoad];
	self.previewHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 140)];

	// Soft shadow on a wrapper, rounded clipped card inside (DESIGN.md: large continuous corners).
	self.previewShadow = [UIView new];
	self.previewShadow.layer.shadowColor = [UIColor blackColor].CGColor;
	self.previewShadow.layer.shadowOpacity = 0.22;
	self.previewShadow.layer.shadowRadius = 12;
	self.previewShadow.layer.shadowOffset = CGSizeMake(0, 6);
	[self.previewHeader addSubview:self.previewShadow];

	self.preview = [[SSStartupView alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
	self.preview.layer.cornerRadius = 20;
	self.preview.layer.cornerCurve = kCACornerCurveContinuous;
	self.preview.layer.borderWidth = 0.5;
	self.preview.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
	self.preview.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.preview addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self.preview action:@selector(playIntro)]];
	[self.previewShadow addSubview:self.preview];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self updatePreview];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.soundPlayer stop];
	self.soundPlayer = nil;
}

// The header is sized from the table width (re-set so the table picks up the new height).
- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat width = self.table.bounds.size.width;
	if (width <= 0 || fabs(width - self.previewWidth) < 0.5) return;
	self.previewWidth = width;

	CGFloat cardWidth = MIN(kPreviewMaxWidth, width - 40);
	CGFloat cardHeight = round(cardWidth * kPreviewAspect);
	self.previewHeader.frame = CGRectMake(0, 0, width, cardHeight + 28);
	self.previewShadow.frame = CGRectMake(round((width - cardWidth) / 2), 18, cardWidth, cardHeight);
	self.preview.frame = self.previewShadow.bounds;
	self.previewShadow.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.previewShadow.bounds cornerRadius:20].CGPath;
	self.table.tableHeaderView = self.previewHeader;
}

// Draws the current settings with the car's renderer (the Weather style uses the last cached numbers,
// else a sample, since the settings page never goes online).
- (void)updatePreview {
	SSStartupView *preview = self.preview;
	if (!preview) return;
	NSInteger style = [self currentStyle];
	preview.style = style;
	preview.name = SSPrefString(SS_KEY_GREET_NAME);
	preview.logoEffect = [SSPrefValue(SS_KEY_LOGO_EFFECT) integerValue];
	preview.date = [NSDate date];
	preview.image = nil;
	preview.weather = nil;
	if (style == SS_STYLE_LOGO) {
		preview.image = [UIImage imageWithContentsOfFile:SS_LOGO_PATH];
	} else if (style == SS_STYLE_VIDEO) {
		NSString *video = [self selectedVideo];
		if (video) preview.image = [UIImage imageWithContentsOfFile:[SS_FRAMES_DIR(video) stringByAppendingPathComponent:@"00000.jpg"]];
		preview.imageFits = [SSPrefValue(SS_KEY_SCALE_MODE) integerValue] == 1;
	} else if (style == SS_STYLE_WEATHER) {
		preview.weather = SSWeatherLoadCache(0) ?: @{SS_WX_TEMP: @28, SS_WX_HIGH: @31, SS_WX_LOW: @24, SS_WX_RAIN: @40, SS_WX_CODE: @2, SS_WX_DAY: @YES};
	}
	[preview reload];
	[preview playIntro];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	// Videos added before frame extraction existed (or copied in by hand) still need converting.
	NSMutableArray *missing = [NSMutableArray array];
	for (NSString *file in [self videoFiles]) {
		if (![self hasFramesForVideo:file]) [missing addObject:file];
	}
	[self extractFramesForVideos:missing completion:nil];
}

- (NSArray<NSString *> *)videoFiles {
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:SS_VIDEOS_DIR withIntermediateDirectories:YES attributes:nil error:nil];
	NSMutableArray *files = [NSMutableArray array];
	for (NSString *file in [fm contentsOfDirectoryAtPath:SS_VIDEOS_DIR error:nil]) {
		if (![file hasPrefix:@"."]) [files addObject:file];
	}
	return [files sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

// The "current video" list shows the files in the videos folder (row id = videoName).
- (void)refreshVideoList {
	PSSpecifier *spec = nil;
	for (PSSpecifier *s in _specifiers) {
		if ([s.identifier isEqualToString:@"videoName"]) { spec = s; break; }
	}
	if (!spec) return;

	NSArray *files = [self videoFiles];
	if (files.count) {
		NSMutableArray *titles = [NSMutableArray array];
		for (NSString *file in files) [titles addObject:[file stringByDeletingPathExtension]];
		[spec setValues:files titles:titles];
	} else {
		[spec setValues:@[@""] titles:@[L(@"STARTUPSCREEN_NO_VIDEO")]];
	}
}

#pragma mark - Pref helpers

- (NSString *)selectedVideo {
	NSString *name = (__bridge_transfer NSString *)CFPreferencesCopyAppValue((__bridge CFStringRef)SS_KEY_VIDEO_NAME, kPrefsDomain);
	NSArray *files = [self videoFiles];
	if (name.length && [files containsObject:name]) return name;
	return files.firstObject;
}

- (void)setSelectedVideo:(NSString *)name {
	CFPreferencesSetAppValue((__bridge CFStringRef)SS_KEY_VIDEO_NAME, (__bridge CFStringRef)name, kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self reloadSpecifiers];
}

#pragma mark - Frames

- (BOOL)hasFramesForVideo:(NSString *)name {
	NSString *path = [SS_FRAMES_DIR(name) stringByAppendingPathComponent:@"info.plist"];
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:path];
	return [info[@"version"] integerValue] >= kFramesVersion;
}

// Exports the soundtrack to audio.m4a for SpringBoard to play. Returns NO only on a real failure;
// a video without audio is fine.
- (BOOL)extractAudioFromAsset:(AVAsset *)asset seconds:(double)seconds toDir:(NSString *)dir {
	if (![asset tracksWithMediaType:AVMediaTypeAudio].count) return YES;
	AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
	if (!export) return NO;
	export.outputURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"audio.m4a"]];
	export.outputFileType = AVFileTypeAppleM4A;
	export.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(seconds, 600));
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	[export exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
	return export.status == AVAssetExportSessionStatusCompleted;
}

- (void)extractFramesForVideos:(NSArray<NSString *> *)names completion:(void (^)(void))completion {
	if (!names.count || self.extracting) {
		if (completion) completion();
		return;
	}
	self.extracting = YES;

	UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"OmniCar"
	                                                                  message:[L(@"STARTUPSCREEN_PREPARING") stringByAppendingString:@"…"]
	                                                           preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:progress animated:YES completion:nil];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSMutableArray *failed = [NSMutableArray array];
		[names enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
			NSString *label = names.count > 1 ? [NSString stringWithFormat:@" (%lu/%lu)", (unsigned long)idx + 1, (unsigned long)names.count] : @"";
			NSError *error = nil;
			BOOL ok = [self extractFramesForVideo:name error:&error progress:^(double fraction) {
				dispatch_async(dispatch_get_main_queue(), ^{
					progress.message = [NSString stringWithFormat:@"%@%@… %d%%", L(@"STARTUPSCREEN_PREPARING"), label, (int)(fraction * 100)];
				});
			}];
			if (!ok) [failed addObject:[NSString stringWithFormat:@"%@: %@", name, error.localizedDescription ?: @"?"]];
		}];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.extracting = NO;
			[progress dismissViewControllerAnimated:YES completion:^{
				if (failed.count) [self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_PROCESS_FAILED"), [failed componentsJoinedByString:@"\n"]]];
				if (completion) completion();
			}];
		});
	});
}

static CGImagePropertyOrientation SSOrientationForTransform(CGAffineTransform t) {
	if (t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0) return kCGImagePropertyOrientationRight;
	if (t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0) return kCGImagePropertyOrientationLeft;
	if (t.a == -1 && t.d == -1) return kCGImagePropertyOrientationDown;
	return kCGImagePropertyOrientationUp;
}

// Decodes the video sequentially and writes one JPEG per 1/kFrameRate seconds, plus info.plist.
- (BOOL)extractFramesForVideo:(NSString *)name error:(NSError **)error progress:(void (^)(double fraction))progress {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dir = SS_FRAMES_DIR(name);
	[fm removeItemAtPath:dir error:nil];
	if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:error]) return NO;

	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name]] options:nil];
	AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
	AVAssetReader *reader = track ? [AVAssetReader assetReaderWithAsset:asset error:error] : nil;
	if (!reader) {
		[fm removeItemAtPath:dir error:nil];
		return NO;
	}

	NSDictionary *settings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
	AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
	output.alwaysCopiesSampleData = NO;
	[reader addOutput:output];
	double seconds = MIN(CMTimeGetSeconds(asset.duration), kMaxFrameSeconds);
	reader.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(seconds, 600));
	if (![reader startReading]) {
		if (error) *error = reader.error;
		[fm removeItemAtPath:dir error:nil];
		return NO;
	}

	CIContext *context = [CIContext contextWithOptions:nil];
	CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGImagePropertyOrientation orientation = SSOrientationForTransform(track.preferredTransform);
	NSDictionary *jpegOptions = @{(id)kCGImageDestinationLossyCompressionQuality: @0.9};
	NSUInteger count = 0;
	double nextTime = 0;

	CMSampleBufferRef sample;
	while ((sample = [output copyNextSampleBuffer])) {
		@autoreleasepool {
			double time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
			CVImageBufferRef pixels = CMSampleBufferGetImageBuffer(sample);
			// Keep only the frames that land on our output frame rate.
			if (pixels && time + 0.001 >= nextTime) {
				CIImage *image = [[CIImage imageWithCVPixelBuffer:pixels] imageByApplyingCGOrientation:orientation];
				CGFloat scale = MIN(1.0, kMaxFrameSide / MAX(image.extent.size.width, image.extent.size.height));
				image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
				NSData *jpeg = [context JPEGRepresentationOfImage:image colorSpace:sRGB options:jpegOptions];
				NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%05lu.jpg", (unsigned long)count]];
				if ([jpeg writeToFile:path atomically:NO]) count++;
				nextTime += 1.0 / kFrameRate;
				if (seconds > 0) progress(MIN(1.0, time / seconds));
			}
			CFRelease(sample);
		}
	}
	CGColorSpaceRelease(sRGB);

	if (reader.status == AVAssetReaderStatusFailed || !count) {
		if (error) *error = reader.error;
		[fm removeItemAtPath:dir error:nil];
		return NO;
	}
	// info.plist is written last: its presence marks the frames as complete.
	if (![self extractAudioFromAsset:asset seconds:seconds toDir:dir]) {
		// Keep the frames; the splash just plays silently.
		NSLog(@"[OmniCar/StartupScreen] audio export failed for %@", name);
	}
	NSDictionary *info = @{@"fps": @(kFrameRate), @"count": @(count), @"version": @(kFramesVersion)};
	return [info writeToURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"info.plist"]] error:error];
}

#pragma mark - Actions

- (void)importFromPhotos {
	self.pickKind = SSPickVideo;
	UIImagePickerController *picker = [UIImagePickerController new];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.mediaTypes = @[UTTypeMovie.identifier];
	picker.videoExportPreset = AVAssetExportPresetPassthrough;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
	if (self.pickKind == SSPickLogo) {
		// The file URL keeps a PNG's transparency; the decoded image is the fallback.
		NSURL *imageURL = info[UIImagePickerControllerImageURL];
		UIImage *image = imageURL ? [UIImage imageWithContentsOfFile:imageURL.path] : nil;
		if (!image) image = info[UIImagePickerControllerOriginalImage];
		[picker dismissViewControllerAnimated:YES completion:^{ [self saveLogoImage:image]; }];
		return;
	}
	NSURL *url = info[UIImagePickerControllerMediaURL];
	[picker dismissViewControllerAnimated:YES completion:^{
		if (!url) return;
		NSDateFormatter *df = [NSDateFormatter new];
		df.dateFormat = @"yyyyMMdd-HHmmss";
		NSString *ext = url.pathExtension.length ? url.pathExtension : @"mov";
		NSString *name = [NSString stringWithFormat:@"Video %@.%@", [df stringFromDate:[NSDate date]], ext];
		[self copyVideoAtURL:url name:name];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)importFromFiles {
	self.pickKind = SSPickVideo;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeMovie] asCopy:YES];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *url = urls.firstObject;
	if (!url) return;
	switch (self.pickKind) {
		case SSPickLogo:  [self saveLogoImage:[UIImage imageWithContentsOfFile:url.path]]; break;
		case SSPickSound: [self copySoundAtURL:url]; break;
		case SSPickVideo: [self copyVideoAtURL:url name:url.lastPathComponent]; break;
	}
}

- (void)copyVideoAtURL:(NSURL *)source name:(NSString *)name {
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:SS_VIDEOS_DIR withIntermediateDirectories:YES attributes:nil error:nil];

	// Avoid overwriting an existing video with the same name.
	NSString *base = [name stringByDeletingPathExtension];
	NSString *ext = name.pathExtension;
	NSString *dest = [SS_VIDEOS_DIR stringByAppendingPathComponent:name];
	for (int i = 2; [fm fileExistsAtPath:dest]; i++) {
		dest = [SS_VIDEOS_DIR stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d.%@", base, i, ext]];
	}

	NSError *error = nil;
	if (![fm copyItemAtPath:source.path toPath:dest error:&error]) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SAVE_FAILED"), error.localizedDescription]];
		return;
	}
	[fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:dest error:nil];
	[self setSelectedVideo:dest.lastPathComponent];
	__weak typeof(self) weakSelf = self;
	[self extractFramesForVideos:@[dest.lastPathComponent] completion:^{ [weakSelf updatePreview]; }];
}

// "Add video": one row, then Photos or Files.
- (void)addVideo {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_FROM_PHOTOS") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf importFromPhotos]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_FROM_FILES") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf importFromFiles]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.view;   // iPad
	sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)previewVideo {
	NSString *name = [self selectedVideo];
	if (!name) { [self showMessage:L(@"STARTUPSCREEN_NO_VIDEO_PREVIEW")]; return; }

	AVPlayerViewController *vc = [AVPlayerViewController new];
	vc.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name]]];
	[self presentViewController:vc animated:YES completion:^{ [vc.player play]; }];
}

- (void)deleteVideo {
	NSString *name = [self selectedVideo];
	if (!name) { [self showMessage:L(@"STARTUPSCREEN_NO_VIDEO_DELETE")]; return; }

	NSString *message = [NSString stringWithFormat:L(@"STARTUPSCREEN_DELETE_CONFIRM"), [name stringByDeletingPathExtension]];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"STARTUPSCREEN_DELETE_TITLE") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_DELETE_ACTION") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[[NSFileManager defaultManager] removeItemAtPath:[SS_VIDEOS_DIR stringByAppendingPathComponent:name] error:nil];
		[[NSFileManager defaultManager] removeItemAtPath:SS_FRAMES_DIR(name) error:nil];
		[self setSelectedVideo:[self videoFiles].firstObject];
		[self updatePreview];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Logo

// "Choose logo": Photos or Files (a PNG with transparency looks best on the dark background).
- (void)chooseLogo {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_FROM_PHOTOS") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf logoFromPhotos]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"STARTUPSCREEN_FROM_FILES") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf logoFromFiles]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:L(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.view;   // iPad
	sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)logoFromPhotos {
	self.pickKind = SSPickLogo;
	UIImagePickerController *picker = [UIImagePickerController new];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.mediaTypes = @[UTTypeImage.identifier];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)logoFromFiles {
	self.pickKind = SSPickLogo;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

// Redraws the image into a transparent sRGB PNG of at most kMaxLogoSide px (orientation applied) at SS_LOGO_PATH.
- (void)saveLogoImage:(UIImage *)image {
	if (!image || image.size.width <= 0 || image.size.height <= 0) {
		[self showMessage:L(@"STARTUPSCREEN_LOGO_FAILED")];
		return;
	}
	CGFloat pixelWidth = image.size.width * image.scale, pixelHeight = image.size.height * image.scale;
	CGFloat scale = MIN(1.0, kMaxLogoSide / MAX(pixelWidth, pixelHeight));
	CGSize size = CGSizeMake(MAX(1.0, round(pixelWidth * scale)), MAX(1.0, round(pixelHeight * scale)));
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.scale = 1;
	format.opaque = NO;
	format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
	UIImage *output = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[image drawInRect:CGRectMake(0, 0, size.width, size.height)];
	}];
	NSData *png = UIImagePNGRepresentation(output);

	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:[SS_LOGO_PATH stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
	NSError *error = nil;
	if (!png || ![png writeToFile:SS_LOGO_PATH options:NSDataWritingAtomic error:&error]) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SAVE_FAILED"), error.localizedDescription ?: @"PNG"]];
		return;
	}
	[fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:SS_LOGO_PATH error:nil];
	[self updatePreview];
}

- (void)deleteLogo {
	if (![[NSFileManager defaultManager] fileExistsAtPath:SS_LOGO_PATH]) { [self showMessage:L(@"STARTUPSCREEN_LOGO_NONE")]; return; }
	[[NSFileManager defaultManager] removeItemAtPath:SS_LOGO_PATH error:nil];
	[self updatePreview];
}

#pragma mark - Startup sound

- (void)chooseSound {
	self.pickKind = SSPickSound;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

// Keeps one sound: the old one is removed, the new one copied into SS_SOUNDS_DIR under its own name.
- (void)copySoundAtURL:(NSURL *)source {
	NSError *error = nil;
	AVAudioPlayer *check = [[AVAudioPlayer alloc] initWithContentsOfURL:source error:&error];
	if (!check) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SOUND_FAILED"), error.localizedDescription ?: source.lastPathComponent]];
		return;
	}
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:SS_SOUNDS_DIR error:nil];
	[fm createDirectoryAtPath:SS_SOUNDS_DIR withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *name = source.lastPathComponent;
	NSString *dest = [SS_SOUNDS_DIR stringByAppendingPathComponent:name];
	if (![fm copyItemAtPath:source.path toPath:dest error:&error]) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SAVE_FAILED"), error.localizedDescription]];
		return;
	}
	[fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:dest error:nil];
	SSSetPrefValue(SS_KEY_SOUND_FILE, name);
	_specifiers = nil;
	[self reloadSpecifiers];
}

// Plays the sound here at the chosen volume (the car plays it through SpringBoard the same way).
- (void)previewSound {
	NSString *name = [self currentSound];
	if (!name) { [self showMessage:L(@"STARTUPSCREEN_SOUND_NONE")]; return; }
	[self.soundPlayer stop];
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];
	NSError *error = nil;
	self.soundPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[SS_SOUNDS_DIR stringByAppendingPathComponent:name]] error:&error];
	if (!self.soundPlayer) {
		[self showMessage:[NSString stringWithFormat:L(@"STARTUPSCREEN_SOUND_FAILED"), error.localizedDescription ?: name]];
		return;
	}
	id volume = SSPrefValue(SS_KEY_SOUND_VOLUME);
	self.soundPlayer.volume = (float)(MAX(0.0, MIN(100.0, volume ? [volume doubleValue] : 100.0)) / 100.0);
	[self.soundPlayer play];
}

- (void)deleteSound {
	if (![self currentSound]) { [self showMessage:L(@"STARTUPSCREEN_SOUND_NONE")]; return; }
	[self.soundPlayer stop];
	self.soundPlayer = nil;
	[[NSFileManager defaultManager] removeItemAtPath:SS_SOUNDS_DIR error:nil];
	SSSetPrefValue(SS_KEY_SOUND_FILE, nil);
	_specifiers = nil;
	[self reloadSpecifiers];
}

@end
