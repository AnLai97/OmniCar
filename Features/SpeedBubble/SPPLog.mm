#import "common.h"

// Log: NSLog + the shared OmniCar.log (Filza); sandboxed nav apps relay their lines to SpringBoard.
static NSString *const kLogPath = @"/var/mobile/Documents/OmniCar.log";

// Ghi 1 dong vao file; tra ve NO neu khong duoc (sandbox)
static BOOL SPPAppendLine(NSString *path, NSString *line)
{
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path] && ![fm createFileAtPath:path contents:nil attributes:nil]) return NO;
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return NO;
        [fh seekToEndOfFile];
        [fh writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
        return YES;
    } @catch (NSException *e) { return NO; }
}

void SPPLogAppendRelayed(NSString *line)
{
    SPPAppendLine(kLogPath, line);
}

void SPPLogWrite(NSString *msg)
{
    NSString *proc = [[NSProcessInfo processInfo] processName];
    NSLog(@LOGTAG " %@", msg);

    static NSDateFormatter *df; static dispatch_once_t once;
    dispatch_once(&once, ^{ df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss"; });
    NSString *line = [NSString stringWithFormat:@"%@ [%@] %@", [df stringFromDate:[NSDate date]], proc, msg];

    // Vietmap bi sandbox -> khong ghi duoc file chung: gui dong log sang SpringBoard ghi ho (xem SpringBoard.xm)
    if (SPPAppendLine(kLogPath, line)) return;
    static BOOL isSpringBoard; static dispatch_once_t sbOnce;
    dispatch_once(&sbOnce, ^{ isSpringBoard = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]; });
    if (!isSpringBoard) {
        [[objc_getClass("NSDistributedNotificationCenter") defaultCenter]
            postNotificationName:SPP_NOTIF_LOG object:nil userInfo:@{@"line": line}];
    }
}
