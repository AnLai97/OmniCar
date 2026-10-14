// Back up / restore every OmniCar setting (ROADMAP-DEV.md: Sao lưu / khôi phục cài đặt). Support > "Back up settings"
// writes one "OmniCar-<date>.omnicar" file and opens the share sheet; Support > "Restore from file" opens the Files
// picker, lists what will be replaced, writes it back and offers a respring. Strings: <lang>.lproj/Backup.strings.
//
// The file is a binary plist: {format: 1, version: TWEAK_VERSION, date, prefs: {key: value}, files: {path relative
// to OMC_DATA_ROOT: NSData}}. prefs holds every key of com.anlai.omnicar the user chose (OMCBackupOwnsKey); runtime
// state (diag*, autoTest*, rescue*, onboardingDone, last split, crash markers ...) stays out of it and is never
// touched by a restore.
#import <UIKit/UIKit.h>

#define OMC_BACKUP_FORMAT     1
#define OMC_BACKUP_EXTENSION  @"omnicar"
// Files under OMC_DATA_ROOT go in until their total reaches this; the rest are skipped and named in a warning.
#define OMC_BACKUP_MAX_BYTES  (200ULL * 1024 * 1024)

#ifdef __cplusplus
extern "C" {
#endif

// NO for the runtime keys a backup leaves out (and a restore leaves alone).
BOOL OMCBackupOwnsKey(NSString *key);
// Writes the backup into tmp. skipped: relative paths left out (size limit or unreadable). Nil + error on failure.
NSURL *OMCBackupWrite(NSArray<NSString *> **skipped, NSError **error);
// Reads and checks a backup file (format, structure). Nil + error when it is not one.
NSDictionary *OMCBackupRead(NSURL *url, NSError **error);
// What a restore of `backup` replaces, in words, for the confirm alert.
NSString *OMCBackupSummary(NSDictionary *backup);
// Writes the prefs (and removes owned keys the backup lacks) and the files, then posts the prefs-changed notification.
BOOL OMCBackupRestore(NSDictionary *backup, NSError **error);

// UI flows started from the root page rows. done runs on the main queue after a successful restore.
void OMCBackupShare(UIViewController *vc);
void OMCBackupPickAndRestore(UIViewController *vc, void (^done)(void));

#ifdef __cplusplus
}
#endif
