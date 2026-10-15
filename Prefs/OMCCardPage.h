#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

// Trang Cai dat kieu the (tools/preview/index.html#bubble, #settings): bang inset grouped tu ve, moi o la
// cong tac / nut chon / thanh keo noi thang voi 1 key trong prefs OmniCar. Trang tinh nang ke thua lop nay va tu dung
// cac section; doi gia tri -> ghi prefs + "com.anlai.omnicar/prefschanged" + -prefChanged:.
@interface PSViewController (OMCCardPage)
- (PSSpecifier *)specifier;
- (void)setSpecifier:(PSSpecifier *)specifier;
@end

@interface OMCCardPage : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong, readonly) UITableView *table;

- (id)prefForKey:(NSString *)key def:(id)def;
- (NSInteger)intForKey:(NSString *)key def:(NSInteger)def;
- (void)storeValue:(id)value forKey:(NSString *)key;   // nil = xoa
- (void)prefChanged:(NSString *)key;                   // goi sau moi lan ghi tu dieu khien (lop con ghi de)
- (void)prefChanging:(NSString *)key;                  // thanh keo dang keo (chua tha tay)

- (UITableViewCell *)cellWithId:(NSString *)rid;      // o da to theo giao dien, khong phu kien
- (UIView *)boxInCell:(UITableViewCell *)cell;        // view phu kin contentView de dat dieu khien tu do
- (UISwitch *)switchForKey:(NSString *)key def:(BOOL)def;
- (UISegmentedControl *)segmentForKey:(NSString *)key titles:(NSArray<NSString *> *)titles def:(NSInteger)def;   // gia tri = chi so
- (UIView *)sliderForKey:(NSString *)key min:(NSInteger)mn max:(NSInteger)mx def:(NSInteger)def format:(NSString *)format width:(CGFloat)w;
- (void)setAccessory:(UIView *)view onCell:(UITableViewCell *)cell;
- (void)toast:(NSString *)text;
- (void)reloadSection:(NSInteger)section;
@end
