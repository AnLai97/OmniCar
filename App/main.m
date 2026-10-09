// OmniCar companion app: the URL scheme Shortcuts / Siri can call. It only forwards the URL to
// SpringBoard (distributed notification OMC_URL_NOTIFY, userInfo @{url}); each feature's SpringBoard
// hook handles the host it owns:
//   omnicar://splitscreen/open?left=<bundle>&right=<bundle>   split the car screen between two apps
//   omnicar://splitscreen/fav?n=1                              open favorite layout 1..3
//   omnicar://splitscreen/close                                leave the split
//   omnicar://splitscreen/picker                               app picker for the focused pane
#import <UIKit/UIKit.h>
#import "SplitScreen.h"

static BOOL OMCForwardURL(NSURL *url)
{
    if (![url.scheme isEqualToString:@"omnicar"]) return NO;
    Class center = NSClassFromString(@"NSDistributedNotificationCenter");
    if (!center) return NO;
    [(NSNotificationCenter *)[center defaultCenter] postNotificationName:OMC_URL_NOTIFY object:nil userInfo:@{@"url": url.absoluteString}];
    return YES;
}

@interface OMCAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation OMCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.07 blue:0.15 alpha:1];

    BOOL vi = [[NSLocale preferredLanguages].firstObject hasPrefix:@"vi"];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectInset(vc.view.bounds, 24, 0)];
    l.numberOfLines = 0;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:15];
    l.textAlignment = NSTextAlignmentCenter;
    l.text = [NSString stringWithFormat:@"OmniCar\n\n%@\n\n%@\n\n"
              @"omnicar://splitscreen/open?left=com.apple.Maps&right=com.spotify.client\n\n"
              @"omnicar://splitscreen/fav?n=1\n\nomnicar://splitscreen/close\n\n%@",
              vi ? @"App này nhận lệnh từ Shortcuts / Siri." : @"This app receives commands from Shortcuts / Siri.",
              vi ? @"Tạo Shortcut với hành động \"Mở URL\":" : @"Create a Shortcut with the \"Open URL\" action:",
              vi ? @"Cài đặt chi tiết: Cài đặt > OmniCar" : @"Settings: Settings > OmniCar"];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:l];

    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:(vi ? @"Mở Cài đặt OmniCar" : @"Open OmniCar Settings") forState:UIControlStateNormal];
    b.frame = CGRectMake(0, vc.view.bounds.size.height - 90, vc.view.bounds.size.width, 44);
    b.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [b addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:b];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)openSettings
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"prefs:root=OmniCar"] options:@{} completionHandler:nil];
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    BOOL ok = OMCForwardURL(url);
    // Quay ve man truoc (Shortcuts) sau khi gui lenh
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
    });
    return ok;
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([OMCAppDelegate class]));
    }
}
