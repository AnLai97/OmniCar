// Bong bong toc do ve theo kieu - dung chung tweak + Cai dat (xem SPPBubbleView.m).
#import <UIKit/UIKit.h>

@interface SPPBubbleView : UIView
@property (nonatomic) NSInteger style;            // 0..SB_STYLE_COUNT-1 (SPPStyle)
@property (nonatomic) int speed, limit;           // km/h, -1 = khong biet / khong co
@property (nonatomic) BOOL showIcon;   // icon app nguon
@property (nonatomic, strong) UIImage *iconImage; // icon app nguon (nguoi goi lay)
@property (nonatomic) NSInteger color;            // mau nen luc binh thuong (SB_KEY_COLOR), 0 = theo kieu
@property (nonatomic, copy) void (^log)(NSString *line);
@property (nonatomic, readonly) NSInteger builtStyle;      // kieu dang ve (-1 = chua ve)
@property (nonatomic, readonly) CGRect outlineRect;        // hinh chinh (vien "giu de thoat" chay quanh)
@property (nonatomic, readonly) CGFloat outlineCorner;
@property (nonatomic, strong, readonly) UILabel *speedLabel;
- (CGSize)render;     // ve lai theo thuoc tinh, tra ve kich thuoc noi dung (goc 0,0; dat bounds / frame theo do)
- (void)rebuild;      // lan render sau dung lai kieu tu dau
- (int)speedState;    // 0 binh thuong, 1 sap cham (>= 90%), 2 vuot (Dai HUD: cham gioi han)
@end
