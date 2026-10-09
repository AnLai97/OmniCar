# OmniCar

Tweak CarPlay cho iOS 15+ (rootless): một gói, nhiều tính năng, mỗi tính năng có công tắc và
trang cài đặt riêng trong Settings > OmniCar.

## Cấu trúc

```
Makefile              build tweak + bundle settings (một Makefile, không subproject)
control               thông tin gói Sileo (tên, version, mô tả)
OmniCar.plist         filter: tweak nạp vào CarPlay.app và SpringBoard
Tweak.x               core ctor: đồng bộ prefs, log
Core/OmniCar.h/.m     API chung cho hook: OMCPref, OMCFeatureEnabled, OMCLog, OMC_DATA_ROOT
Prefs/                bundle settings dùng chung
  OMCRootListController    trang chính: header card, Bật OmniCar, Respring, danh sách tính năng
  OMCFeatureListController trang con chuẩn: nạp plist của tính năng, dịch key, vẽ icon
  OMCTheme                 ngôn ngữ (vi/en), màu HarmonyOS, icon dòng, style cell
  Resources/               Root.plist, Info.plist, icon/logo/avatar, <lang>.lproj/Localizable.strings
layout/               entry PreferenceLoader
Features/<Tên>/       mỗi tính năng là một component (xem bên dưới)
Template/             plist mẫu cho trang tính năng mới
assets/               icon 1024
```

### Một tính năng = một thư mục

```
Features/CarSplash/
  CarSplash.h                    hợp đồng: key prefs, thư mục dữ liệu, tên notification
                                 (chỉ macro, cả tweak lẫn bundle settings đều include)
  CarSplash.x                    hook: %group CarSplash, %ctor riêng, kiểm tra
                                 OMCFeatureEnabled(@"carsplash") lúc hành động
  Prefs/
    OMCCarSplashController.h/.m  trang settings (subclass OMCFeatureListController); chỉ cần khi
                                 trang có action, không có thì dùng thẳng OMCFeatureListController
    Resources/
      FeatureCarSplash.plist     các dòng của trang (luật như Root.plist)
      vi.lproj/CarSplash.strings bảng chuỗi riêng, key có tiền tố CARSPLASH_
      en.lproj/CarSplash.strings
```

Makefile gom tự động: `Features/*/*.x` vào tweak, `Features/*/Prefs/*.m` vào bundle settings,
`Features/*/Prefs/Resources` được rsync chung vào bundle (các `.lproj` tự gộp).
`OMCLoadStrings` nạp mọi bảng `.strings` trong `<lang>.lproj`, nên key của tính năng dùng `L()`
như key core.

Quy ước:

- Key prefs: `<tên>Xxx` trong domain `com.anlai.omnicar` (`carsplashVideoName`).
  `<tên>Enabled` là công tắc của tính năng; `OMCFeatureEnabled(@"<tên>")` = công tắc tổng và công tắc đó.
- Dữ liệu: `/var/mobile/Library/OmniCar/<Tên>/`.
- Darwin notification: `com.anlai.omnicar/<tên>.<việc>`.
- Log: `OMCLog(@"<Tên>", ...)` ra `[OmniCar/<Tên>]` trong Console và `/var/mobile/Documents/OmniCar.log`.
- Chuỗi: `<TÊN>_KEY` trong `<Tên>.strings`; `"<TÊN>"` là nhãn dòng ở trang chính.

## Thêm tính năng

1. Tạo `Features/<Tên>/<Tên>.h` khai báo key, đường dẫn, notification.
2. Viết hook trong `Features/<Tên>/<Tên>.x`: `%group <Tên>`, `%init(<Tên>)` trong `%ctor` của file,
   đọc prefs bằng `OMCPref()`, gate bằng `OMCFeatureEnabled()`.
3. Copy `Template/FeatureExample.plist` thành `Features/<Tên>/Prefs/Resources/Feature<Tên>.plist`,
   sửa dòng, viết `vi.lproj/<Tên>.strings` và `en.lproj/<Tên>.strings` (cùng bộ key).
4. Nếu trang có nút (action), tạo `Prefs/OMC<Tên>Controller.h/.m` kế thừa `OMCFeatureListController`,
   action là method trên controller đó.
5. Thêm một `PSLinkCell` vào `Prefs/Resources/Root.plist` dưới `FEATURES_GROUP`:
   `label` = `<TÊN>`, `plist` = `Feature<Tên>`, `detail` = controller, `symbol`/`symbolColor`.
6. Cần framework mới thì thêm vào `OmniCar_FRAMEWORKS` / `OmniCarPrefs_FRAMEWORKS` trong Makefile.

Build chỉ chạy trên CI (GitHub Actions, macOS): push lên `main` để lấy `OmniCar_<Version>_rootless.deb`,
tag `v<Version>` để ra Release.
