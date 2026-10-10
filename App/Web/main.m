// OmniCar Web: a bare WKWebView app (no browser chrome) that loads one page with a desktop (macOS Safari) user
// agent and a page zoom, so a site shows its PC layout on the car screen through App Bridge - the point is YouTube's
// desktop site, which the YouTube app cannot show. Installed to /Applications as com.anlai.omnicar.web ("Web");
// pick it in Settings > OmniCar > Apps like any other app. Page and zoom: AB_KEY_WEB_URL / AB_KEY_WEB_ZOOM in the
// OmniCar prefs domain (Apps page, "Web" group); changes apply live (prefschanged).
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <notify.h>
#import "AppBridge.h"

#define kDomain CFSTR("com.anlai.omnicar")
#define kDesktopUA @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Safari/605.1.15"

static id OMWPref(NSString *key)
{
    CFPreferencesAppSynchronize(kDomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kDomain));
}

static NSURL *OMWPageURL(void)
{
    NSString *s = OMWPref(AB_KEY_WEB_URL);
    if (![s isKindOfClass:[NSString class]] || !s.length) s = AB_WEB_DEFAULT_URL;
    if (![s containsString:@"://"]) s = [@"https://" stringByAppendingString:s];
    return [NSURL URLWithString:s] ?: [NSURL URLWithString:AB_WEB_DEFAULT_URL];
}

static CGFloat OMWZoom(void)
{
    id v = OMWPref(AB_KEY_WEB_ZOOM);
    double z = v ? [v doubleValue] / 100.0 : AB_WEB_DEFAULT_ZOOM / 100.0;
    return MIN(1.5, MAX(0.3, z));
}

@interface OMWViewController : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, strong) NSURL *loadedURL;
@end

@implementation OMWViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    cfg.allowsPictureInPictureMediaPlayback = NO;
    cfg.defaultWebpagePreferences.preferredContentMode = WKContentModeDesktop;
    _web = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    _web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _web.customUserAgent = kDesktopUA;
    _web.navigationDelegate = self;
    _web.UIDelegate = self;
    _web.backgroundColor = [UIColor blackColor];
    _web.opaque = NO;
    _web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:_web];
    [self applyPrefs];

    // Settings doi trang / thu phong -> ap ngay
    static int token;
    __weak OMWViewController *weakSelf = self;
    notify_register_dispatch("com.anlai.omnicar/prefschanged", &token, dispatch_get_main_queue(), ^(int t) { [weakSelf applyPrefs]; });
}

- (void)applyPrefs
{
    _web.pageZoom = OMWZoom();
    NSURL *url = OMWPageURL();
    if (![url isEqual:_loadedURL]) {
        _loadedURL = url;
        [_web loadRequest:[NSURLRequest requestWithURL:url]];
    }
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

// Trang mo cua so moi (target=_blank) -> mo trong chinh web view nay
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
       forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    if (navigationAction.request.URL) [webView loadRequest:navigationAction.request];
    return nil;
}

@end

@interface OMWAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation OMWAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [OMWViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([OMWAppDelegate class]));
    }
}
