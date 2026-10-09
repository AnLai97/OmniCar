# OmniCar

Tweak CarPlay cho iOS 15+ (rootless): một gói, nhiều tính năng, mỗi tính năng có công tắc và
trang cài đặt riêng trong Settings > OmniCar.

## Cấu trúc

```
Makefile              một Makefile: mỗi tính năng -> một dylib OmniCar<Tên>.dylib, cộng bundle settings
control               thông tin gói Sileo (tên, version, mô tả)
Core/OmniCar.h/.m     API chung cho hook: OMCPref, OMCFeatureEnabled, OMCLog, OMC_DATA_ROOT (biên dịch kèm vào từng dylib)
Core/Core.x           OmniCarCore.dylib, chỉ nạp SpringBoard: trạm nhận log từ app bị sandbox
Prefs/                bundle settings dùng chung
  OMCRootListController    trang chính: header card, Bật OmniCar, Respring, danh sách tính năng (tự quét Feature*.plist)
  OMCFeatureListController trang con chuẩn: nạp plist của tính năng, dịch key, vẽ icon
  OMCTheme                 ngôn ngữ (vi/en), màu HarmonyOS, icon dòng, style cell
  Resources/               Root.plist, Info.plist, icon/logo/avatar, <lang>.lproj/Localizable.strings
layout/               entry PreferenceLoader
Features/<Tên>/       mỗi tính năng là một component (xem bên dưới)
  StartupScreen/      video khởi động trên màn CarPlay (từ CarSplash)
  SpeedBubble/        bong bóng tốc độ + biển giới hạn từ Vietmap Live / GOFA (từ CarSpeed, ObjC++)
  SplitScreen/        chia màn xe cho 2-3 app CarPlay chạy song song (từ CarDuo, ObjC++); split nằm trong
                      process CarPlay, SpringBoard chỉ nhận URL và đặt cửa sổ CarBridge
App/                  app OmniCar nhận URL omnicar://<tính năng>/<việc> cho Shortcuts / Siri rồi chuyển sang
                      SpringBoard (distributed notification com.anlai.omnicar/url); hook của tính năng tự xử lý
Template/             plist mẫu cho trang tính năng mới
tools/icons/          script vẽ logo gói và icon dòng của từng tính năng (Pillow)
assets/               icon 1024
```

### Một tính năng = một thư mục

```
Features/StartupScreen/
  StartupScreen.h                    hợp đồng: key prefs, thư mục dữ liệu, tên notification
                                     (chỉ macro, cả tweak lẫn bundle settings đều include)
  StartupScreen.x                    hook: %group StartupScreen, %ctor riêng, kiểm tra
                                     OMCFeatureEnabled(@"startupScreen") lúc hành động
  Filter.plist                       process mà dylib của tính năng nạp vào (Makefile copy ra gốc thành
                                     OmniCarStartupScreen.plist lúc build, file đó được gitignore)
  feature.mk                         framework riêng: OmniCarStartupScreen_FRAMEWORKS += AVFoundation ...
  Prefs/
    OMCStartupScreenController.h/.m  trang settings (subclass OMCFeatureListController); chỉ cần khi
                                     trang có action, không có thì dùng thẳng OMCFeatureListController
    Resources/
      FeatureStartupScreen.plist     các dòng của trang (luật như Root.plist) + các key feature* ở đầu
                                     (featureLabel, featureIcon hoặc featureSymbol/featureSymbolColor,
                                     featureController, featureOrder) để trang chính tự liệt kê
      StartupScreenIcon.png (@2x/@3x) icon dòng 29pt
      vi.lproj/StartupScreen.strings bảng chuỗi riêng, key có tiền tố STARTUPSCREEN_
      en.lproj/StartupScreen.strings
```

Makefile gom tự động: `Features/<Tên>/*.x|.xm|.m|.mm` + `Core/OmniCar.m` thành `OmniCar<Tên>.dylib`,
`Features/*/Prefs/*.m` vào bundle settings, `Features/*/Prefs/Resources` được rsync chung vào bundle
(các `.lproj` tự gộp). `OMCLoadStrings` nạp mọi bảng `.strings` trong `<lang>.lproj`, nên key của tính
năng dùng `L()` như key core. Mỗi tính năng là dylib riêng với filter riêng: code của tính năng này không
nạp vào process của tính năng khác, một tính năng lỗi không kéo cả gói.

Quy ước:

- Key prefs: `<tên>Xxx` trong domain `com.anlai.omnicar` (`startupScreenVideoName`).
  `<tên>Enabled` là công tắc của tính năng; `OMCFeatureEnabled(@"<tên>")` = công tắc tổng và công tắc đó.
- Dữ liệu: `/var/mobile/Library/OmniCar/<Tên>/`.
- Darwin notification: `com.anlai.omnicar/<tên>.<việc>`. Mọi cell lưu prefs đều `PostNotification`
  `com.anlai.omnicar/prefschanged`.
- Log: `OMCLog(@"<Tên>", ...)` ra `[OmniCar/<Tên>]` trong Console và `/var/mobile/Documents/OmniCar.log`
  (xoay sang `.old` khi quá 2 MB). Process không ghi được file (Vietmap, GOFA) tự gửi dòng log sang
  SpringBoard qua distributed notification, `OmniCarCore` ghi hộ. Mọi tính năng chỉ dùng cơ chế này.
- Chuỗi: `<TÊN>_KEY` trong `<Tên>.strings`; `"<TÊN>"` là nhãn dòng ở trang chính.
- URL cho Shortcuts / Siri: `omnicar://<tên thường>/<việc>?...` (`omnicar://splitscreen/open?left=..&right=..`).
  App `App/main.m` chỉ chuyển URL sang SpringBoard; tính năng nào cần thì nghe `OMC_URL_NOTIFY` trong hook
  SpringBoard của mình và lọc theo host.

## Thêm tính năng

1. Tạo `Features/<Tên>/<Tên>.h` khai báo key, đường dẫn, notification.
2. Viết hook trong `Features/<Tên>/<Tên>.x`: `%group <Tên>`, `%init(<Tên>)` trong `%ctor` của file,
   đọc prefs bằng `OMCPref()`, gate bằng `OMCFeatureEnabled()`.
3. `Features/<Tên>/Filter.plist`: process cần nạp. Cần framework thì thêm `Features/<Tên>/feature.mk`
   với `OmniCar<Tên>_FRAMEWORKS += ...` (bundle settings cần framework thì sửa `OmniCarPrefs_FRAMEWORKS`).
4. Copy `Template/FeatureExample.plist` thành `Features/<Tên>/Prefs/Resources/Feature<Tên>.plist`,
   điền các key `feature*` ở đầu, sửa dòng, viết `vi.lproj/<Tên>.strings` và `en.lproj/<Tên>.strings`.
5. Nếu trang có nút (action), tạo `Prefs/OMC<Tên>Controller.h/.m` kế thừa `OMCFeatureListController`,
   action là method trên controller đó, ghi tên class vào `featureController`.
6. Icon dòng: vẽ bằng script trong `tools/icons/` (29pt, @2x, @3x) hoặc dùng `featureSymbol`.

Không phải sửa Root.plist hay Makefile: trang chính tự liệt kê, Makefile tự gom.

Build chỉ chạy trên CI (GitHub Actions, macOS): push lên `main` để lấy `OmniCar_<Version>_rootless.deb`,
tag `v<Version>` để ra Release.
