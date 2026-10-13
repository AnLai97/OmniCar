#import "SPPGPS.h"
#import "SPPBubble.h"
#import "SPPPrefs.h"
#import <CoreLocation/CoreLocation.h>

#define SPP_PGPS_FRESH     3.0    // giay: vi tri cu hon -> bo; khong co toc do hop le lau hon -> gui "khong co"
#define SPP_PGPS_ACCURACY  100.0  // m: sai so vi tri lon hon -> bo (vi tri tu wifi / tram, toc do khong dang tin)
#define SPP_PGPS_CAR_GRACE 5.0    // giay mat man xe lien tuc moi tat GPS (man xe chop mat thoang qua)
#define SPP_PGPS_POLL      5.0    // giay: nhip xet lai khi nguon la GPS (bat GPS ngay khi xe vua ket noi)
#define SPP_PGPS_SMOOTH    0.5    // he so lam muot (trung binh truot): 1 = khong lam muot
#define SPP_PGPS_STILL     3.0    // km/h: duoi muc nay coi nhu dung yen (GPS troi khi xe dung)
#define SPP_PGPS_SLOW      10.0   // km/h: dang cham ma CoreLocation cho toc do -1 -> coi la dung yen (0)

@interface SPPPhoneGPS () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *mgr;
@property (nonatomic, strong) NSTimer *poll;
@property (nonatomic) double smooth;                 // km/h da lam muot (< 0 = chua co)
@property (nonatomic) CFAbsoluteTime validAt;        // lan cuoi co toc do hop le
@property (nonatomic) CFAbsoluteTime carLostAt;      // luc bat dau mat man xe (0 = dang co)
@property (nonatomic) BOOL denied;                   // SpringBoard bi tu choi quyen vi tri: khong bat lai toi lan update sau
@property (nonatomic) BOOL loggedFirst;
@end

@implementation SPPPhoneGPS

+ (instancetype)shared
{
    static SPPPhoneGPS *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SPPPhoneGPS new]; s.smooth = -1; });
    return s;
}

- (BOOL)running { return self.mgr != nil; }

// Cai dat doi / xe ket noi / ngat: thu lai ca khi lan truoc bi tu choi quyen (nguoi dung co the da cho phep)
- (void)update
{
    self.denied = NO;
    [self check];
}

- (void)check
{
    BOOL wanted = [SPPPrefs enabled] && [SPPPrefs source] == SPP_SOURCE_GPS;
    if (wanted && !self.poll) {
        __weak SPPPhoneGPS *weakSelf = self;
        self.poll = [NSTimer scheduledTimerWithTimeInterval:SPP_PGPS_POLL repeats:YES block:^(NSTimer *t) { [weakSelf check]; }];
    } else if (!wanted && self.poll) {
        [self.poll invalidate]; self.poll = nil;
    }
    BOOL car = SPPGetCarPlayCADisplay() != nil;
    if (car) self.carLostAt = 0;
    else if (self.mgr && wanted) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (self.carLostAt <= 0) self.carLostAt = now;
        if (now - self.carLostAt < SPP_PGPS_CAR_GRACE) car = YES;   // nhip poll sau xet lai
    }
    BOOL run = wanted && car && !self.denied;
    if (run && !self.mgr) [self start];
    else if (!run && self.mgr) [self stop];
}

- (void)start
{
    CLLocationManager *m = [CLLocationManager new];
    m.delegate = self;
    m.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    m.distanceFilter = kCLDistanceFilterNone;
    m.activityType = CLActivityTypeAutomotiveNavigation;
    m.pausesLocationUpdatesAutomatically = NO;
    self.mgr = m;
    self.smooth = -1; self.validAt = 0; self.loggedFirst = NO; self.carLostAt = 0;
    CLAuthorizationStatus st = m.authorizationStatus;
    SPPLog("gps iphone: bat (xe ket noi, quyen vi tri cua SpringBoard = %d)", (int)st);
    // SpringBoard la process he thong: thuong khong can hoi. Chua xac dinh -> xin quyen (khong co mo ta trong Info.plist
    // thi he thong bo qua im lang); bi tu choi -> locationManagerDidChangeAuthorization / didFailWithError bao.
    if (st == kCLAuthorizationStatusNotDetermined) [m requestAlwaysAuthorization];
    else [SPPPrefs setGPSStatus:(int)st];
    [m startUpdatingLocation];
}

- (void)stop
{
    [self.mgr stopUpdatingLocation];
    self.mgr.delegate = nil;
    self.mgr = nil;
    self.smooth = -1; self.validAt = 0;
    SPPLog("gps iphone: tat%@", self.denied ? @" (khong co quyen vi tri)" : @"");
    [[SPPBubble shared] sourceStopped:SPP_SOURCE_GPS];
}

- (void)post:(int)kmh
{
    // Cung duong voi ban tin cua app dan duong (SpringBoard.xm): khong co gioi han, khong co app dang hien
    [[SPPBubble shared] updateSpeed:kmh limit:-1 appForeground:NO app:SPP_SOURCE_GPS];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *fix = locations.lastObject;
    if (!fix || manager != self.mgr) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double age = -[fix.timestamp timeIntervalSinceNow];
    BOOL good = age <= SPP_PGPS_FRESH && fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= SPP_PGPS_ACCURACY;
    double mps = fix.speed;   // m/s, < 0 = khong hop le
    // Xe dung / bo cham: CoreLocation hay cho -1 -> coi la 0 thay vi "--"
    if (good && mps < 0 && self.smooth >= 0 && self.smooth < SPP_PGPS_SLOW) mps = 0;
    if (!good || mps < 0) {
        // Tam mat (ham, vi tri tu wifi): bong bong giu so cu SPP_VALUE_HOLD giay; lau hon -> "--"
        if (now - self.validAt > SPP_PGPS_FRESH && self.smooth >= 0) { self.smooth = -1; [self post:-1]; }
        else if (self.validAt <= 0) [self post:-1];
        return;
    }
    double kmh = mps * 3.6;
    if (kmh > 300) return;
    self.smooth = self.smooth < 0 ? kmh : self.smooth + SPP_PGPS_SMOOTH * (kmh - self.smooth);
    self.validAt = now;
    int shown = self.smooth < SPP_PGPS_STILL ? 0 : (int)lround(self.smooth);
    if (!self.loggedFirst) {
        self.loggedFirst = YES;
        SPPLog("gps iphone: vi tri dau tien, %d km/h (sai so %.0fm)", shown, fix.horizontalAccuracy);
        [SPPPrefs setGPSStatus:(int)manager.authorizationStatus];
    }
    [self post:shown];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
{
    if (manager != self.mgr) return;
    CLAuthorizationStatus st = manager.authorizationStatus;
    SPPLog("gps iphone: quyen vi tri cua SpringBoard = %d", (int)st);
    [SPPPrefs setGPSStatus:(int)st];
    if (st == kCLAuthorizationStatusDenied || st == kCLAuthorizationStatusRestricted) { self.denied = YES; [self stop]; }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    if (manager != self.mgr) return;
    SPPLog("gps iphone: loi %@ (%ld)", error.localizedDescription, (long)error.code);
    // kCLErrorLocationUnknown: tam thoi, CoreLocation tu thu tiep
    if ([error.domain isEqualToString:kCLErrorDomain] && error.code == kCLErrorDenied) {
        [SPPPrefs setGPSStatus:(int)kCLAuthorizationStatusDenied];
        self.denied = YES;
        [self stop];
    }
}

@end
