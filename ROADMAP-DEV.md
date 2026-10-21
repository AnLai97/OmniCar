# OmniCar – Lộ trình tính năng (dev)

Các mức tính năng và trạng thái code của từng mục. Kế hoạch phát hành, giá, Lite / Pro: **ROADMAP-RELEASE.md**.

Cách dùng file này
- Mức tính năng xếp theo **ưu tiên**: Mức 1 là thứ phải có ngay, mức sau làm khi mức trước đã xong.
- Mỗi mức chia thành **nhóm** theo tính năng. Trong mỗi nhóm, mục xếp **từ dễ đến khó** (Thấp → Vừa → Cao);
  mục nào phụ thuộc mục khác thì đứng sau nó.
- Mỗi mục có **hai ô**: `- [x] [ ]`. Ô thứ nhất = **code xong** (Claude đánh khi làm xong và ghi Code / Thử bên dưới);
  ô thứ hai = **đã kiểm tra** (tác giả tự đánh sau khi thử thấy tốt, ghi phiên bản bên cạnh). Chưa ai đánh ô thứ hai thay tác giả.
- **Đánh số**: nhóm theo mức (Mức 2 có 2.1, 2.2…), mục theo nhóm (nhóm 2.1 có 2.1.1, 2.1.2…); mức không chia nhóm
  thì mục đánh thẳng 5.1, 5.2… Dùng số này khi nhắc tới một mục.
- **Độ khó**: Thấp (vài ngày) · Vừa (1–2 tuần) · Cao (vài tuần, cần thử nghiệm nhiều trên xe).
- **Xong khi**: tiêu chí kiểm tra được trên xe thật, không phải "code đã viết".
- **Code** / **Thử**: đã viết gì, ở file nào, thử thế nào (ghi khi bắt đầu code một mục).

Đã có (1.0.0): Chia màn hình 2–3 ô (4 bố cục, chia dọc, kéo tỉ lệ, yêu thích, gần đây, Siri URL), App Bridge
(app iPhone lên xe, icon trên màn chính CarPlay), Bong bóng tốc độ (18 kiểu, nay thay bằng 9 kiểu mới, Vietmap Live / GOFA / Waze), Màn hình
khởi động (một video MP4), Cài đặt vi / en.

## Trước khi phát hành

- Đặt `OMC_AUTOTEST` = 0 (Core/OmniCar.h) hoặc build bằng `make package OMC_AUTOTEST=0`: bỏ hẳn phần tự kiểm tra.
- Bản dịch 12 ngôn ngữ (ngoài vi / en) là dịch máy: cần người bản xứ đọc lại.
- Xem lại các TODO trong docs/sales/ (giá, hoàn tiền, liên hệ).

---

## Mức 1 – Cần ngay (trước khi mở repo miễn phí)

Thiếu một trong các mục này thì khách quốc tế không mua, hoặc mua rồi đòi hoàn tiền.

### 1.1 Hỗ trợ và ổn định

- [x] [ ] **1.1.1 Gửi log một chạm** · Thấp
  Nút trong Cài đặt: gói OmniCar.log + phiên bản iOS, máy, đầu xe, danh sách tweak → share sheet.
  Xong khi: khách gửi được file qua Zalo / email trong 3 chạm.
  Code: Hỗ trợ > Gửi log (OMCShareReport) → `OmniCar-log-<ngày>.txt`. Chờ thử gửi Zalo trên máy.
- ~~**1.1.2 Màn chẩn đoán**~~ · ĐÃ BỎ (10/2026): trang Chẩn đoán, nút Tối ưu, công tắc Chế độ nhẹ / dọn RAM trong Cài đặt bỏ hết
  cho gọn. Phần còn giữ: báo cáo Gửi log vẫn chứa ~20 mục kiểm tra sức khoẻ ✓ / ⚠ / ✗ + số đo hiệu năng CarPlay của
  chuyến gần nhất (Prefs/OMCDiagnostics.m), Chế độ nhẹ tự động (Core) vẫn chạy ngầm khi máy nóng / CarPlay khựng.
- [x] [ ] **1.1.3 Thông tin đầu xe** · Thấp
  Độ phân giải, tỉ lệ màn, chất lượng video gợi ý (gộp vào báo cáo Gửi log).
  Code: CarPlay ghi màn xe + phiên CarKit mỗi lần cắm (OMCCrashGuard), mục "Màn xe" trong báo cáo. Chờ thử trên xe.
- [x] [ ] **1.1.4 Phát hiện tweak xung đột** · Thấp
  Thấy CarBridge, DuoDash, TrueDash, CarPlayEnable… đang bật → cảnh báo trong Cài đặt (không tự gỡ tweak của người khác).
  Code: thẻ cảnh báo đầu trang chính khi dylib của tweak đó đang nạp; Chẩn đoán liệt kê cả gói đã cài.
- [x] [ ] **1.1.5 Chế độ cứu (rescue)** · Vừa
  CarPlay sập 2 lần liền trong 60 giây sau khi cắm → tự tắt tính năng nghi gây lỗi, lần cắm sau báo cho người dùng.
  Xong khi: cố tình gây crash trong một tính năng, CarPlay tự phục hồi ở lần cắm thứ 3.
  Code: OMCCrashGuard (Core) nghi tính năng theo backtrace, thông báo trên iPhone, thẻ "Bật lại" ở trang chính.
  Thử: Chẩn đoán, nhấn giữ dòng OmniCar → chọn tính năng → cắm xe 3 lần.
- [x] [ ] **1.1.6 Tự kiểm tra trên xe (chỉ bản dev)** · Vừa
  Công cụ cho tác giả, không phát hành: macro `OMC_AUTOTEST` (Core/OmniCar.h, hoặc `make OMC_AUTOTEST=0`) bỏ hẳn
  khỏi bản phát hành. Cài đặt > Hỗ trợ > Tự kiểm tra: chọn tính năng → mỗi tính năng tự chạy bộ test của nó trên xe,
  mỗi bước ghi đạt / lỗi + lý do + trạng thái + ảnh màn xe → Gửi log. Process sập giữa chừng thì lần sau chạy tiếp.
  Bộ test: Chia màn hình (nút Split Screen trên dock: 2 ô theo nút Home, bấm mở / đóng bảng bố cục, còn hiện khi đang chia và sau khi tắt; bố cục, tỉ lệ, đổi chỗ, cửa sổ nổi, bảng chọn / bảng bố cục, toàn màn, lệnh URL, yêu thích,
  gần đây, bấm nhanh), App Bridge (trong ô, tỉ lệ, đổi chỗ, 3 ô, cửa sổ nổi (app iPhone nổi, app CarPlay nổi trên ô app iPhone), toàn màn, đóng, icon, 2 app cùng
  lúc), Màn hình khởi động (phát, khung chạy, tự tắt, chạm bỏ qua, tắt tính năng), Bong bóng tốc độ (hiện trên xe,
  số, gần / vượt giới hạn, ẩn khi Split Screen chiếm màn, mọi kiểu, cỡ, mất nguồn).
  Xong khi: một lần chạy trên xe ra đủ kết quả từng bước, gửi log có ảnh, sửa lỗi không cần thử tay lại từng ca.
  Code: Core/OMCTest.h (khung), Features/SplitScreen/SCPAutoTest.mm, cuối StartupScreen.x, cuối SPPBubble.mm,
  Prefs/OMCAutoTestController.m. Chờ chạy thử trên xe.
  19/10/2026: bật lại (OMC_AUTOTEST 1). Chạy chậm (3 s giữa hai bước), ngón tay vẽ ở chỗ mỗi bước chạm (OMCTestStepAt;
  trên ô app iPhone thì app tự vẽ vì cửa sổ host của SpringBoard che). Chạm trong app do app tự gửi qua UIKit
  (OMC_NOTIF_AUTOTEST_TOUCH → App.xm → OMCTestTouchTap / Drag, trả lời Darwin notify): YouTube chạm vào một video (mở app
  toàn màn, trong ô, giữa 3 ô), Google Maps kéo bản đồ qua lại (toàn màn, trong ô). Ưu tiên app: mở YouTube / Google Maps;
  chia màn YouTube | Google Maps | GOFA.
  21/10/2026: thêm test cho các bản sửa 20–21/10 (danh sách: docs/test-plan-20261021.html). App Bridge: bước "cửa sổ theo cỡ ô"
  (kind window, App.xm tự so mọi cửa sổ toàn màn với cỡ scene, bit OMC_AT_WINDOW_FITS) sau khi vào ô, sau mỗi tỉ lệ, khi
  YouTube đang xem video, toàn màn và từ toàn màn vào ô; AIMap được ưu tiên trong danh sách app iPhone. Chia màn hình: mở
  GOFA / Google Maps toàn màn thì nút Split Screen phải nhận ra app đó (fullscreenAppBundle). Màn chính: lưới đều 4 × 2,
  6 × 3, 3 × 1, 5 × Tự động (SCPHomeGridCheck: tâm ảnh icon đúng tâm ô ±2 pt, cạnh = SCPHomeIconSide, không tràn / chồng),
  Cỡ icon 60 / 130 % giữ tâm, tắt tên thì icon to hơn, cầu dao chèn icon theo build. Màn hình khởi động: hỏi riêng ipapi.co,
  ipwho.is và cả chuỗi dự phòng (SSIPAsk).
- [ ] [ ] **1.1.7 Thử với nhiều app hơn** · Vừa
  Danh sách tối thiểu: YouTube, TikTok, Facebook, Instagram, Chrome, Safari, Zalo, Grab, Shopee, X, Twitch, Plex.
  Xong khi: có bảng app chạy tốt / chạy được / không chạy kèm lý do, đưa lên trang tương thích.
  Bảng ghi kết quả: COMPATIBILITY.md.
- [ ] [ ] **1.1.8 Chạy thật trên iOS 15 16 17 và 18** · Cao
  App Bridge và Chia màn hình đang dựa selector iOS 16. Kiểm tra từng selector, có đường dự phòng khi thiếu.
  Kiểm tra lại luôn app có giao diện CarPlay riêng chạy trong ô.
  Xong khi: thử đủ 4 bố cục + YouTube / TikTok qua App Bridge trên iOS 15, 16, 17, 18 (rootless), ghi kết quả.
  Chẩn đoán hiện hook thiếu trên từng iOS; ghi kết quả vào COMPATIBILITY.md.
  iOS 15, nhánh Dev-IOS15 (20/10/2026, từ log 19/10 17:45 iPhone 7 Plus 15.8.4 + video, log 19/10 21:59 iPhone 8 15.6 + video):
  App Bridge (App.xm, chỉ khi nhóm APPS15 được cài, cờ abLegacyRotation): (1) hook UIDevice setOrientation bỏ qua giá trị
  cảm biến (nằm ngửa / úp / không rõ) và chỉ báo SpringBoard khi hướng app muốn thật sự đổi, hết cảnh scene lắc 0,3 s một
  lần khi máy ngả trên giá; (2) khi ép về hướng ô bị bỏ qua vì app chỉ cho ngang (YouTube ở trình phát toàn màn, mask 24)
  thì báo SpringBoard mã 0xFF kèm mask để scene xoay ngang và đổi khung, và báo lại khi app cho dọc trở lại (cờ
  abToldLandscape), hết cảnh YouTube vẽ xoay 90° (màn 640 × 240) hoặc video thu vào một góc (màn 512 × 300). Chia màn hình
  (CarPlay.xm, nhóm LAYOUT chỉ iOS 15): bộ lọc khai báo trùng FBSDisplayLayoutPublisher tự theo dõi phần tử đang giữ
  (sLiveLayout, token giữ yếu, swizzle invalidate của lớp token) thay vì chỉ quét ivar, vì 19:29:46 CarPlay sập assert
  "already have an element ... com.google.Maps" sau khi scene Maps bị huỷ mà quét ivar không thấy. Core: nghi phạm crash
  bỏ qua frame của chính OMCCrashGuard (báo cáo từng đổ cho Bong bóng tốc độ trong khi frame 4 là SplitScreen). Chờ thử:
  YouTube phát video toàn màn rồi vào ô trên máy iOS 15, thoát chia màn sau khi một app CarPlay thoát. Còn mở: app iPhone
  bị giết liên tục trên iPhone 8 (cần crash log máy), AIMap không theo cỡ ô (cần log có dấu vết cửa sổ). Thêm cùng ngày:
  app của jailbreak (OMCIsJailbreakApp trong OmniCar.h: tiền tố bundle id và app nằm trong gốc rootless) bị loại khỏi bảng
  chọn app, danh sách app iPhone của Chia màn hình và danh sách chèn icon; app đã chọn cho App Bridge luôn được coi là app
  iPhone trước khi xét khai báo CarPlay (YouTube từng bị mở theo đường app CarPlay lúc 19:25:35 vì khai báo giả còn trong
  thư viện); ABHost ghi pid app lúc host và khi "scene bi huy" ghi app còn chạy hay đã chết kèm bộ nhớ trống, để lần sau
  biết app bị jetsam hay tự sập.
  Treo táo 7 Plus 15.7.7 (log 19/10 20:36 chỉ có "AppBridge: loaded into SpringBoard"): điểm chết ngay sau dòng đó, nghi nhất là
  MSHookFunction BKSDisplayServicesSetScreenBlanked (chỗ duy nhất vá mã máy trong SpringBoard). Sửa: không vá lúc khởi động, chỉ
  vá khi lần đầu host app (ABInstallScreenBlankHook), bỏ qua nếu SpringBoard đã nạp CarBridge / carplay-cast; cầu dao cho cả
  hook ObjC lẫn lệnh vá (AB_KEY_SB_* / AB_KEY_HOOK_*: còn "đang cài" ở lần khởi động sau thì bỏ bước đó ở bản này, đổi cài
  đặt thì thử lại); OMCLogFlush ghi log đồng bộ cuối mỗi hàm khởi tạo và trước bước nguy hiểm; control Conflicts thêm
  com.leemin.carbridge và com.ethanarbuckle.carplay-cast. Chờ: crash / panic log của máy đó, danh sách tweak, thử lại bản mới.
- [x] 20/10 21:20, 7 Plus 15.8.4: bản e258fb5 treo táo, log không có dòng SpringBoard nào (bản 566af6c lúc 21:18 lên bình thường).
  Nghi OMCLogFlush: dispatch_sync trong %ctor khi dyld giữ khoá, mà khối ghi log trong SpringBoard gọi NSFileManager. Sửa: lúc
  các hàm khởi tạo chạy (tới khi main queue chạy lần đầu) OMCLogWrite ghi thẳng file bằng open/write trên luồng gọi, OMCLogFlush
  trả về ngay; sau đó mới chờ hàng đợi. Chờ: thử lại trên máy đó, stackshot / WatchdogTimeoutReport lúc 21:20 nếu còn.
- [x] 20/10 21:45, cùng máy, bản 0518440: SpringBoard lên được nhưng app App Bridge không mở trong chia màn hình. Cầu dao đã ghi
  "1.0.3" từ lần treo của e258fb5, bản sửa cũng là 1.0.3 nên vẫn bỏ hook SpringBoard. Sửa: cầu dao ghi "version build", dấu
  "đang cài" của build khác chỉ bị xoá, không tính là treo.
  21/10: cầu dao chèn icon của Chia màn hình (SCPAppIconsBeginInjection) cũng theo "version build" như vậy; trước đó nó
  ghi "1.0.3" nên một máy từng sập (iPhone 8, 19/10 19:27) sẽ không được chèn icon ở mọi build 1.0.3 cho tới khi đổi danh sách app.
- [x] 20/10 22:05, cùng máy, bản 4d04cdd (chỉ iOS 15, iOS 16 không đổi):
  - Chia màn hình: CarPlay mở lại GOFA toàn màn lúc cắm xe, bấm nút Split Screen vẫn "man chinh" (currentBaseViewController
    rỗng) nên phải chọn lại cả 2 ô. Sửa: nhớ VC DashBoard vừa trình bày (presentBaseViewController), dùng khi
    currentBaseViewController rỗng mà VC đó còn trên màn xe (currentBaseVC:); log "khong thay app dang mo" ghi lý do nếu vẫn hụt.
  - App Bridge: kéo vạch thì scene đổi khung nhưng cửa sổ trong app giữ cỡ cũ (TikTok 371x300); YouTube giữ cửa sổ 414x736
    trong scene ngang (xoay 90°), mở lại thì 1190x480 trong ô 297. Sửa: SpringBoard gửi cỡ ô (AB_NOTIF_SIZE) sau mỗi lần đổi
    scene, app (nhóm APPS15) đặt lại mọi cửa sổ toàn màn theo cỡ đó, cả sau khi UIKit xoay cửa sổ; rời xe thì trả về cỡ màn.
  Chờ: log bản mới, xem dòng "iOS 15: N cua so -> ..." và "app dang mo lay tu VC vua trinh bay".
  Thử 21/10 (tác giả, máy iOS 15.8.8, bản 80ac25d): YouTube trong ô không còn xoay 90°, cửa sổ theo cỡ ô (lỗi trong
  video log 19/10 17:45) — OK. Chưa thử lại trên 7 Plus 15.8.4.

### 1.2 Bán quốc tế

- [x] [ ] **1.2.1 Đơn vị và quy chuẩn theo nước** · Thấp
  Đã bỏ (10/2026): bong bóng tốc độ luôn km/h và biển tròn viền đỏ (Viên), không còn lựa chọn Đơn vị / Biển trong Cài đặt.
  (Vị trí tay lái của Chia màn hình cũng đã bỏ: không cần thiết.)
- [x] [ ] **1.2.2 Hướng dẫn lần đầu** · Thấp
  3–4 trang: chọn app lên xe, chọn bố cục đầu tiên, bật bong bóng tốc độ, cách gọi bảng bố cục trên xe.
  Code: Prefs/OMCOnboardingController.m, 4 trang, tự hiện lần đầu mở Cài đặt (onboardingDone), Hỗ trợ > Xem lại
  hướng dẫn.
- [x] [ ] **1.2.3 Nhiều ngôn ngữ** · Thấp (dịch) / Vừa (kiểm tra)
  Tối thiểu: en, vi, es, pt-BR, de, fr, it, ru, zh-Hans, ja, ko, ar (RTL), th, id.
  Xong khi: mọi trang Cài đặt và chữ trên xe không bị cắt ở ngôn ngữ dài nhất (de) và RTL (ar).
  Code: 14 ngôn ngữ (OMCSupportedLanguages, Core/OMCCommon.m), theo ngôn ngữ máy hoặc chọn trong Cài đặt; thiếu câu
  nào thì dùng tiếng Anh. Chữ trên xe: OMCTr(vi, en), ngôn ngữ khác tra `<lang>.lproj/Car.strings` (khoá = câu tiếng
  Anh). Bản dịch máy: cần người bản xứ đọc lại; chưa kiểm tra chữ bị cắt (de) và RTL (ar) trên máy.
  Chờ dịch (đang thử chỉ sửa en + vi, dịch 12 ngôn ngữ còn lại một lần khi xong): STARTUPSCREEN_WEATHER_FOOTER (21/10, thêm ipapi.co / ipwho.is).
- [x] [ ] **1.2.4 Trang tương thích công khai** · Thấp
  iOS, kiểu jailbreak (rootless / roothide), chip, đầu xe đã thử, app đã thử, giới hạn đã biết (DRM).
  Code: docs/compatibility.html (trang tĩnh, EN / VI), đồng bộ với COMPATIBILITY.md. Chưa có kết quả thử nào.

### 1.3 Dùng hằng ngày

- [x] [ ] **1.3.1 Phóng to tạm một ô** · Thấp
  Chạm đúp thanh "•••" → ô to toàn vùng app, chạm lại → về bố cục cũ (khác "toàn màn" là không đóng các ô khác).
  Code: SCPCarSplit zoomedSlot (ô khác ẩn nhưng giữ kích thước scene), cả thanh ••• của app iPhone (SpringBoard vẽ).
- [x] [ ] **1.3.2 Bàn phím trên màn xe** · Cao
  Một bàn phím chung cho mọi ô (kể cả app iPhone qua App Bridge), kiểu HarmonyOS, có tiếng Việt và các ngôn ngữ chính.
  Xong khi: gõ được tìm kiếm trong YouTube và ô địa chỉ của Safari trên xe.
  Code: app iPhone qua App Bridge: App.xm chặn bàn phím iPhone khi app trên xe và báo SpringBoard; ABKeyboard.mm vẽ
  bàn phím trên màn xe (chữ / số, EN / VI Telex), gửi phím về app. App CarPlay gốc dùng bàn phím của CarPlay.
  Chờ thử YouTube / Safari trên xe.

## Mức 2 – Quan trọng (bằng DuoDash, làm ngay sau bản bán đầu tiên)

Khách so sánh trực tiếp với DuoDash / CarBridge ở các mục này, và đây là những thứ khách nhìn thấy mỗi lần cắm xe.

### 2.1 Màn chính CarPlay (nâng cấp từ App Bridge)

THU GỌN (10/2026, theo ý tác giả): KHÔNG đụng vào giao diện của CarPlay. Nhóm "Màn xe" ở trang chính có hai mục
(Features/AppBridge/Prefs/OMCAppBridgeAppsController.m, xem trước tools/preview/index.html#home): "App trên màn xe": trên là lưới app đang
hiện trên xe (app CarPlay + app iPhone có dấu iPhone), dưới 2 tab App CarPlay (chỉ xem; chưa cắm xe thì đoán theo
entitlement) / App Bridge (công tắc đưa app iPhone lên xe = App Bridge, AB_KEY_APPS); "Màn chính CarPlay" (OMCHomeScreenController) gồm xem trước
màn xe, Lưới icon (Số cột / Số hàng, Cỡ icon HS_KEY_ICON_SIZE 60–130 %, Tên app) và thẻ Hình nền (6 hình dựng sẵn, ảnh hoặc video từ Ảnh, độ mờ, độ tối). Trên xe (Features/SplitScreen/SCPHomeScreen.mm) màn chính gốc
của CarPlay giữ nguyên: hình nền là một view chèn xuống dưới lưới icon của DBDashboardHomeViewController, cỡ icon qua hook
SBIconListGridLayoutConfiguration -iconImageInfo (AppIcons.xm, nhân hệ số; cột / hàng: xem 2.1.3). 100 %, lưới Tự động,
có tên và không hình nền = không đụng gì. Lưới icon riêng, sắp xếp app CarPlay, dock, thư mục, widget, gói icon, ngày /
đêm đã bỏ hẳn (code trong git trước commit này). Lần đầu áp ghi log "HomeScreen: DIAG cay man chinh".
Thử: chọn hình nền + kéo cỡ icon 130 %, cắm xe, Gửi log (dòng "HomeScreen:"; "khong co SBIconListGridLayoutConfiguration"
= iOS này cần cách khác cho cỡ icon).

- [x] [ ] **2.1.1 Ẩn app CarPlay** · Vừa (sắp xếp app vẫn bỏ)
  Ẩn icon app CarPlay gốc không dùng (CarBridge có) trên màn chính gốc của CarPlay; app vẫn tự mở khi có cuộc gọi, chỉ
  đường, Siri. Sắp xếp / ghim dock vẫn bỏ (không tự vẽ lưới).
  Xong khi: app ẩn không hiện trên màn chính, giữ nguyên sau khi rút / cắm lại và sau respring; bật lại thì icon về.
  Flow: cắm xe thì CarPlay hiện app như đã chọn trong Cài đặt iPhone › Chung › CarPlay; chỉnh trong OmniCar thì OmniCar thay
  danh sách đó (không còn công tắc Tùy chỉnh: 2 danh sách bên dưới đều rỗng = CarPlay nguyên vẹn; Đặt lại xoá cả 2).
  Code: App trên màn xe kiểu Cài đặt iPhone › CarPlay › Tùy chỉnh: Bao gồm (nút − bỏ) và Ứng dụng khác (nút + thêm, ô tìm),
  chung app CarPlay và app iPhone qua App Bridge (AB_KEY_APPS). Bỏ app CarPlay → HS_KEY_HIDDEN_APPS (isIconVisible: NO);
  thêm lại app đã bỏ trong Tùy chỉnh của iOS → HS_KEY_SHOWN_APPS (isIconVisible: buộc YES, xe ghi các app này vào
  HS_KEY_CAR_APPS với off = YES). Khoá: Điện thoại / Nhạc / Bản đồ / Tin nhắn + mọi icon riêng của CarPlay (có trên màn chính
  mà không phải app cài trên iPhone, không cần biết mã bundle), ở cả Cài đặt lẫn trên xe. Không kéo đổi thứ tự; app thêm lại
  do CarPlay tự xếp chỗ (xem log "HomeScreen: N app tren man chinh").
  Thử thêm: bỏ Lịch trong Cài đặt iPhone › CarPlay, thêm lại ở OmniCar → log "hien lai (iOS da bo ...)" và icon về; không có
  dòng đó = CarPlay không hỏi isIconVisible: cho app iOS đã bỏ (cần cách khác).
  Đồng bộ với Tùy chỉnh của iOS (đang dò): CarProbe (bản dev, OMC_AUTOTEST) có mục "CARPLAY CUSTOMIZE STORAGE": tìm file
  dưới /var/mobile chứa mã app trên màn chính (kèm đường key trong plist) và so với lần probe trước. Cách dò: cắm xe (probe tự
  chạy sau 8 s) → vào Cài đặt iPhone › Chung › CarPlay › xe › Tùy chỉnh bỏ 1 app → probe lại (rút / cắm lại xe, hoặc
  notifyutil -p com.anlai.omnicar/probe) → Gửi log (dòng "Tuy chinh CarPlay: ... doi tu lan truoc: ...") + file
  /var/mobile/Documents/OmniCar-Probe.txt. Tìm ra chỗ lưu thì đọc / ghi thẳng: danh sách giống hệt iOS, kéo đổi thứ tự.
  Như CarPlay: Điện thoại, Nhạc, Bản đồ, Tin nhắn, Đang phát, Xe, Cài đặt không ẩn được (HSIsLockedCarPlayApp trong
  AppBridge.h: hàng có khóa thay công tắc, trên xe bỏ qua dù có trong danh sách ẩn).
  Trên xe: hook -[DBIconModel isIconVisible:] (AppIcons.xm, SCPIconHiddenOnCar trong SCPAppIcons.mm) trả NO cho app bị ẩn
  (iOS 16: DBIconModel < SBHIconModel, không còn SBIconModel; DBIconModel tự override isIconVisible: nên hook thẳng lớp đó,
  không có thì SBHIconModel / SBIconModel; autotest 15/10 trên iOS 16.6 báo thiếu hook SBIconModel và iBooks vẫn hiện);
  đổi danh sách → -[iconModel layout] của DBDashboardHomeViewController, không có thì _handleAppLibraryRefresh. Xe chỉ ghi
  app đang hiện nên app đã ẩn giữ chỗ cũ trong danh sách để bật lại được. Danh sách tab App CarPlay = HS_KEY_CAR_APPS do xe
  ghi từ mô hình icon của lưới màn chính (mọi trang, đúng thứ tự, có cả Đang phát / Cài đặt / app Xe, tên lấy từ xe; ghi lại
  1 s sau mỗi lần màn chính xếp lại, log "HomeScreen: N app tren man chinh cho Cai dat"); không còn dùng splitScreenCarPlayApps
  (chỉ app chia màn được, ghi 1 lần lúc cắm xe). Chưa cắm xe thì đoán theo entitlement CarPlay. Chưa thử trên xe.
  Thử: ẩn Podcasts → cắm xe: icon không còn, log "HomeScreen: an com.apple.podcasts"; bật lại khi đang cắm → log
  "danh sach an doi ... layout" và icon về. Không thấy dòng "an ..." = DashBoard không gọi isIconVisible: (cần cách khác,
  chạy CarProbe xem DBIconModel). Ẩn Điện thoại rồi gọi đến: màn cuộc gọi vẫn hiện.
- [x] [ ] **2.1.2 Cỡ icon** · Vừa
  Thanh trượt cỡ icon trên màn chính gốc của CarPlay (60–130 %).
  Code: HS_KEY_ICON_SIZE; hook SBIconListGridLayoutConfiguration -iconImageInfo trong process CarPlay nhân cỡ ảnh icon + bo
  góc, đổi cỡ thì gọi layoutIconsNow cho các *IconListView (SCPHomeScreen.mm). Chờ thử trên xe (iOS 15 có thể khác lớp).
  Thử: kéo 130 % → icon to trong ô của CarPlay, tên không chồng; 60 % → icon nhỏ, ô giữ nguyên.
- [x] [ ] **2.1.3 Số cột / hàng và tên app** · Vừa (làm lại trên lưới gốc của CarPlay)
  Chọn số cột × hàng của lưới màn chính CarPlay (Tự động = như CarPlay), ẩn / hiện tên dưới icon.
  Code: Cài đặt > Màn xe > Màn chính CarPlay > Lưới icon: Số cột (Tự động, 3–8, HS_KEY_COLS), Số hàng (Tự động, 1–4,
  HS_KEY_ROWS), Tên app (HS_KEY_NAMES). Trên xe: hook SBIconListGridLayoutConfiguration numberOf{Portrait,Landscape}
  {Columns,Rows} (chỉ lưới có ≥ 2 cột và ≥ 2 hàng, không đụng dock), đổi thì -[iconModel layout] + layoutIconsNow
  (SCPHomeScreen.mm); tên: hook -[SBIconView setLabelHidden:] + đặt lại cho icon đang có, dự phòng
  +[CARIconView / DBIconView maxLabelSizeForIconImageSize:] = 0 (cách của tweak CarPlayHideLabels, chỉ init khi lớp có hàm này). Key cũ homeScreenCols / Rows / Names
  không đọc. Chưa thử trên xe.
  Thử: 4 × 2 → mỗi trang 8 icon, log "HomeScreen: luoi ... cot 5 -> 4"; tắt Tên app → tên mất, log "ten app an";
  về Tự động → như CarPlay. Không thấy dòng "luoi" = CarPlay không đọc các getter này (cần cách khác).
  21/10: chia lưới đều (tác giả: tỉ lệ chia chưa đúng khi chọn cột / hàng). CarPlay đổi số icon mỗi trang nhưng vẫn đặt theo
  lề / khoảng cách của lưới gốc. SCPHomeLayoutGrid (SCPHomeScreen.mm, hook -[SBIconListView layoutIconsNow / layoutSubviews]
  trong AppIcons.xm): sau mỗi lần CarPlay xếp, chia vùng lưới icon (bounds thật) thành cột × hàng ô bằng nhau, đặt tâm ảnh
  icon (iconImageFrame) vào tâm ô, tên treo bên dưới; đổi cỡ icon thì phóng to / thu nhỏ quanh điểm đó. Chỉ khi đã chọn cột
  hoặc hàng (Tự động × Tự động = như CarPlay), chỉ lưới trong màn chính, bỏ dải hẹp < 120 pt. Xem trước trong Cài đặt vẽ
  cùng cách. Chạy trên mọi iOS (nhánh Dev-IOS15). Thử: 4 × 2, 6 × 3, 3 × 1, cỡ icon 60 % và 130 % → icon cách đều, phóng
  quanh tâm; log "HomeScreen: luoi deu CxR trong {W, H}".
  21/10: cỡ icon theo ô (tác giả: "scale cân đối với tỉ lệ màn hình"). Đã chọn cột / hàng thì iconImageInfo không còn là icon
  gốc × %, mà cạnh = 80 % cạnh ngắn của ô (có tên: cao ô − 2 × 18 pt cho nhãn) × Cỡ icon (SCPHomeIconSide); ô đổi thì xếp lại
  một lần. 100 % vừa ô trên mọi tỉ lệ màn; Tự động × Tự động vẫn là icon gốc × %. Log "o luoi WxH -> canh icon N pt".
- [x] [ ] **2.1.4 Hình nền màn chính** · Vừa
  Chọn hình dựng sẵn hoặc ảnh từ Ảnh (bỏ chọn từ Tệp), cắt theo tỉ lệ màn xe, chỉnh độ mờ và độ tối để icon vẫn dễ nhìn.
  Code: ô Mặc định + 6 hình dựng sẵn (gradient như bản xem trước, vẽ 1920 × 720) + ô ảnh / video của bạn, nút Từ Ảnh
  → OmniCar/HomeScreen/wallpaper.jpg (≤ 1920 px) hoặc video.mp4; view chèn dưới lưới icon gốc của CarPlay, lấp kín vùng app (cắt
  theo tỉ lệ), Độ mờ 0–30 (CIGaussianBlur trên luồng phụ), Độ tối 0–70 %; Bỏ hình nền = dùng lại hình nền CarPlay.
  Thử: ảnh dọc và ảnh ngang đều phủ kín, không méo; đổi độ mờ / tối thấy ngay khi thả tay.
- ~~**2.1.5 Dock tuỳ chỉnh**~~ · ĐÃ BỎ (10/2026, không đụng dock CarPlay)
  Chọn app nào nằm cố định trên dock (kể cả app iPhone), ẩn mục gợi ý của CarPlay.
  Code: chip app ghim (✕ để bỏ) + chip "+ Thêm" (chọn app), hoặc ghim từ danh sách app; tối đa 4, kể cả app iPhone, thay cho gợi ý của CarPlay; không ghim + tắt "Gợi ý của CarPlay" = dock trống.
  Nút Split Screen trên dock giữ nguyên. Dock ngắn hơn số app ghim thì chỉ hiện số vừa (ghi log).
  Thử: ghim Bản đồ + YouTube → dock chỉ còn 2 app đó, chạm mở đúng app; bỏ ghim hết → gợi ý của CarPlay trở lại.

### 2.2 Màn hình khởi động mới

Đổi từ "một video" sang nhiều **kiểu khởi động**. Mỗi kiểu là một mẫu có tham số; người dùng chọn kiểu,
xem trước ngay trong Cài đặt. Âm thanh phát qua loa xe khi CarPlay kết nối.

- [x] [ ] **2.2.1 Khung chọn kiểu khởi động** · Vừa
  Trang Cài đặt mới: danh sách kiểu (Video, Logo + âm thanh, Lời chào, Thời tiết…), xem trước, thời lượng, chạm để bỏ qua.
  Video MP4 hiện tại thành một kiểu trong danh sách, cài đặt cũ được giữ.
  Code: startupScreenStyle (0 Video, 1 Logo, 2 Lời chào, 3 Thời tiết), SSStartupView.m vẽ chung cho xe và xem trước
  trong Cài đặt (Prefs/SSStartupViewPrefs.m #import lại file đó). Chờ thử trên xe.
- [x] [ ] **2.2.2 Logo + âm thanh của bạn** · Thấp (sau khi có khung)
  Chọn ảnh logo (PNG trong suốt) + âm thanh; vài hiệu ứng xuất hiện: hiện dần, phóng to, phát sáng.
  Code: logo PNG (Ảnh / Tệp, ≤ 1024 px) ở StartupScreen/Logo, hiệu ứng hiện dần / phóng to / phát sáng.
- [x] [ ] **2.2.3 Âm thanh khởi động riêng** · Thấp
  Gắn âm thanh vào bất kỳ kiểu nào (tiếng máy nổ, chuông, lời chào ghi âm), chỉnh âm lượng, tắt khi đang có cuộc gọi.
  Code: một file âm thanh (Tệp) ở StartupScreen/Sounds, âm lượng, SpringBoard phát; bỏ qua khi đang gọi (CXCallObserver
  trong SpringBoard: chờ thử).
- [x] [ ] **2.2.4 Lời chào theo giờ** · Thấp
  "Chào buổi sáng, An" + giờ, ngày; chữ và nền đổi theo sáng / chiều / tối.
  Code: giờ, "Chào buổi sáng, <tên>", ngày; nền đổi theo sáng / chiều / tối / khuya.
- [x] [ ] **2.2.5 Thời tiết và nhiệt độ** · Vừa
  Nhiệt độ hiện tại, cao / thấp trong ngày, khả năng mưa, biểu tượng thời tiết; lấy từ WeatherKit / dữ liệu Thời tiết của iOS, không có mạng thì dùng số đo gần nhất.
  Code: Open-Meteo (cần mạng, toạ độ làm tròn 2 số, đã ghi trong Cài đặt), vị trí gần nhất của CarPlay, cache 12 h,
  không có dữ liệu thì về Lời chào. Chờ thử: CarPlay có quyền vị trí / mạng không. Cập nhật docs/sales/privacy.md.
  21/10: tra vị trí theo IP (khi không có toạ độ nào) hỏi ipapi.co rồi ipwho.is nếu lỗi; lỗi ghi URL, mã HTTP và đầu câu trả lời
  (log 19/10 21:59 iPhone 8: ipapi.co 5/6 lần không có toạ độ). privacy.md ghi thêm hai dịch vụ này. Chờ: log có dòng
  "IP location failed at" để biết ipapi.co giới hạn hay chặn.

### 2.3 Chia màn hình

- [x] [ ] **2.3.1 Ghim ô bản đồ** · Thấp
  Ô được ghim không bị thay khi chọn bố cục / app khác.
  Code: splitScreenPinnedApp (Chia màn hình > Ô được ghim, hoặc omnicar://splitscreen/pin?app=): ô của app đó không bị
  thay khi chọn app, đổi bố cục hay bớt ô.
- [x] [ ] **2.3.2 Nhớ tỉ lệ theo cặp app** · Thấp
  Maps + Nhạc = 70/30, Maps + YouTube = 50/50… tự áp lại.
  Code: có từ trước (SCPPrefs ratioForPairLeft:right:, SPL_KEY_PAIR_RATIOS).
- [x] [ ] **2.3.3 Hồ sơ theo từng xe** · Thấp
  Nhận xe qua tên / ID đầu xe → bố cục chia màn, màn chính CarPlay, kiểu khởi động, cỡ bong bóng riêng cho từng xe.
  Code: Core OMCProfileSwitch khi cắm xe (khoá xe từ phiên CarKit), OMCProfileKeys() là các cài đặt theo xe;
  Cài đặt > Hồ sơ theo xe (Prefs/OMCCarProfilesController.m). Chờ thử: tên trường định danh xe của CarKit.
- [ ] [ ] **2.3.4 Gán nút giọng nói trên vô lăng** · Vừa
  Bấm giữ = Siri như cũ; bấm ngắn = mở bảng bố cục / một app / một lệnh OmniCar, người dùng chọn.
  Chưa làm: cần đường sự kiện nút Siri của DashBoard (bộ dò liệt kê DBEvent).

### 2.4 Lái xe

- [x] [ ] **2.4.1 Cảnh báo quá tốc độ** · Thấp
  Vượt biển + ngưỡng tuỳ chọn → viền màn đổi màu, tiếng ngắn; có chế độ im lặng.
  Code: SPPWarn.mm: viền đỏ nhấp nháy trên màn xe + tiếng bíp 1 lần mỗi lần vượt; ngưỡng −10…+10 so với giới hạn (âm = báo
  từ trước khi chạm giới hạn), hai công tắc Cảnh báo (viền) và Âm thanh (tiếng), bật cái nào có cái đó
  (mặc định cả hai; lưu 2 bit trong SB_KEY_WARN_MODE, giá trị cũ 2 = viền + tiếng tự đổi thành 3, SB_KEY_WARN_MODE_V2) (Bong bóng tốc độ > Cảnh báo quá tốc độ).
  Trang cài đặt: nhóm Cỡ và vị trí nằm ngay dưới Kiểu; icon nguồn trong bong bóng là ô vuông bo góc (trước là tròn).
  Theo đúng bản duyệt tools/preview/index.html#bubble: Cảnh báo có 4 kiểu (Viền nháy / Phát sáng / Nháy màn / Bong bóng phóng
  to + rung, SB_KEY_WARN_FX); Âm thanh chọn Âm báo (6 tiếng tổng hợp như bản duyệt: Bíp, Bíp đôi, Bíp gấp, Chuông, Ping, Radar)
  hoặc Giọng nói (3 câu nghiêm túc, 5 câu vui, câu tự nhập; đọc bằng AVSpeechSynthesizer theo ngôn ngữ OmniCar), chạm một mục để
  nghe thử (SPPSound.m, dùng chung SpringBoard + Cài đặt). Nhóm Giao diện thêm Màu nền bong bóng (Mặc định + 6 màu, SB_KEY_COLOR,
  sắp chạm / vượt vẫn hổ phách / đỏ); thứ tự nhóm: Giao diện, Cỡ và vị trí, Nguồn tốc độ, Cảnh báo, Hiển thị.
- [ ] [ ] **2.4.2 Nguồn tốc độ toàn cầu** · Vừa
  Chỉ còn 3 nguồn (10/2026): Vietmap Live, GOFA, Waze. Đã bỏ GPS iPhone (SPPGPS.mm xoá), Google Maps, Apple Maps; nguồn cũ
  4 (Waze) tự đổi thành 2, các nguồn bỏ về Vietmap (SB_KEY_SOURCE_V2).
  Code: Waze là nguồn 2 (NavApp.xm chạy trong app): tốc độ từ GPS riêng trong app, giới hạn quét trên màn hình như
  Vietmap / GOFA (vòng đỏ, tên ảnh, chữ); chỉ quét khi là nguồn đang chọn (SPP_DARWIN_SOURCE). Chờ thử trên xe: log
  "chan doan" của NavApp khi chưa thấy biển cho biết giao diện Waze để chỉnh cách đọc giới hạn.
  Sửa 20/10/2026 (log 20/10 07:40, GOFA): bong bóng lấy nhầm tốc độ GPS của GOFA làm giới hạn. Ô cảnh báo của GOFA có
  tên lớp gợi ý giới hạn nhưng số bên trong là tốc độ hiện tại (ứng viên "17(f28 UIView gioi-han)" đổi theo GPS mỗi lần
  quét), còn biển thật là ảnh. Lỗi có từ đầu (luật "view cha tên Limit = giới hạn" dùng chung cho mọi nguồn), 18/10
  không lộ vì chỉ thử GOFA lúc xe đứng yên (nhãn 0 → bỏ, rơi xuống ảnh → 50 đúng); 19-20/10 chạy xe là sai.
  Nay NavApp.xm đọc màn hình theo TỪNG NGUỒN, mỗi nguồn một hàm với luật riêng, chọn theo SPP_APP_INDEX_* (common.h):
  SPPScanVietmap (view plugin SpeedLimitView2 / CurrentSpeedView, không có nhãn thì cây AX, rồi ảnh), SPPScanGOFA (giới
  hạn = nhãn trong vòng viền đỏ hoặc tên ảnh biển; nhãn trong view tên Limit / Speed là tốc độ, không bao giờ là giới
  hạn), SPPScanWaze (giới hạn = nhãn trong WZSpeedSignView / vòng đỏ), SPPScanGeneric cho Wyn và nguồn mới (vòng đỏ =
  giới hạn, vòng xanh = tốc độ, rồi tên lớp, AX, ảnh). Thêm nguồn mới = thêm 1 case + 1 hàm, không sửa hàm nguồn cũ.
  Log "speed scan" ghi tên lớp view cha sau "gioi-han:" / "toc-do:" và "[anh ... gioi-han]" khi lấy từ ảnh. Chờ thử trên
  xe với GOFA (giới hạn phải là số trên biển đỏ), Waze và Vietmap (không đổi gì về hành vi).
  Còn thiếu: giới hạn tốc độ OSM tải sẵn theo vùng.

### 2.5 Cài đặt và hiệu năng

- ~~**2.5.1 Sao lưu / khôi phục cài đặt**~~ · ĐÃ BỎ (10/2026): bỏ Sao lưu / Khôi phục từ file và kiểu file .omnicar của app
  OmniCar (code Prefs/OMCBackup.m đã xoá, lấy lại từ git nếu cần).
- [x] [ ] **2.5.2 Có gì mới** · Thấp
  Sau mỗi bản cập nhật hiện một trang ngắn trong Cài đặt.
  Code: Prefs/OMCWhatsNewController.m + Resources/WhatsNew.plist (theo phiên bản trong control), tự hiện 1 lần sau mỗi bản
  mới, Hỗ trợ > Có gì mới. Thêm mục cho mỗi phiên bản mới vào WhatsNew.plist.
- [x] [ ] **2.5.3 Tinh chỉnh hiệu năng** · Vừa
  Giới hạn FPS app iPhone, tự giảm khi máy nóng, giữ app trong bộ nhớ hay không, giữ kết nối CarPlay khi khoá máy.
  Code (một phần, Mức 1): Chế độ nhẹ tự giảm khi máy nóng, dọn RAM; App Bridge giữ app trên xe khi khoá máy.
  Giới hạn FPS: App trên màn xe > Khung hình app (Tối đa / 30 / 24, AB_KEY_FPS); SpringBoard gửi kèm thông báo hướng,
  App.xm giới hạn CADisplayLink của app (hoạt ảnh, cuộn, game; video không đổi). Chờ thử trên xe.
- [ ] [ ] **2.5.4 Tối ưu CarPlay không dây** · Vừa
  Tự giảm chất lượng / FPS app iPhone khi kết nối không dây chập chờn.
  Code (một phần): Khung hình app để Tối đa thì tự giới hạn 30 khi CarPlay không dây (OMCCarWireless, đọc phiên CarKit)
  hoặc Chế độ nhẹ bật. Còn thiếu: đo kết nối chập chờn (cần số liệu từ xe không dây).
- [x] [ ] **2.5.5 Phím tắt Siri đầy đủ** · Vừa
  Hành động cho app Phím tắt: mở bố cục, đặt app vào ô, đổi tỉ lệ, đổi hình nền / kiểu khởi động, bật / tắt từng tính năng.
  Code: omnicar://splitscreen/layout | ratio | swap | zoom | pin, omnicar://feature/<tính năng>?on=, lite?mode=,
  startup?style=, cleanram (Core.x, Features/SplitScreen/SpringBoard.xm). Chưa có: đổi hình nền (chưa có hình nền).

## Mức 3 – Vượt DuoDash (tạo khác biệt khi lái xe)

Những thứ DuoDash không có. Đây là nội dung chính cho video quảng cáo các bản cập nhật lớn.

### 3.1 Màn chính CarPlay

ĐÃ BỎ cả nhóm (10/2026): người dùng chỉ muốn chọn app lên xe + hình nền + bố cục icon; hình nền ngày / đêm, hình nền động
vẫn còn dưới dạng "Video của bạn" trong thẻ Hình nền, còn hình dạng / gói icon, thư mục, trang riêng, widget bỏ hẳn
(code cũ trong git trước commit này nếu cần lấy lại). Các mục dưới giữ lại để tham khảo.

- ~~**3.1.1 Hình nền theo giờ**~~ (đã bỏ) · Thấp
  Hai ảnh ngày / đêm, tự đổi theo giờ mặt trời mọc / lặn hoặc theo chế độ sáng / tối của xe.
  Code: thẻ Hình nền có Ban ngày / Ban đêm (HS_KEY_NIGHT_STYLE, ảnh đêm HomeScreen/wallpaper-night.jpg, "Như ban ngày" = tắt),
  Đổi sang đêm: Theo xe (traitCollection sáng / tối của màn xe) hoặc Mặt trời (giờ mọc / lặn tính từ vị trí iOS biết gần
  nhất, không có thì 6:00 / 18:00) (HS_KEY_NIGHT_BY). Trên xe kiểm tra lại mỗi 30 giây, ảnh đổi mờ dần.
  Thử: đêm chọn hình Đêm, Theo xe → bật / tắt đèn pha (hoặc giao diện tối của xe): hình đổi trong 30 giây; log "hinh nen dem".
- [x] [ ] **3.1.2 Hình nền động** (còn: ô "Video của bạn" trong Hình nền) · Vừa
  Video ngắn lặp hoặc ảnh động làm nền, tự dừng khi máy nóng hoặc khi đang chia màn.
  Code: Từ Ảnh nhận cả video → cắt 20 giây đầu, 1280 px, bỏ tiếng (HomeScreen/video.mp4 + khung đầu video.jpg), ô Video
  của bạn dùng được cho ngày hoặc đêm (kiểu 8). Trên xe AVPlayerLooper không tiếng; dừng khi máy nóng (thermal ≥ serious),
  chế độ nhẹ, đang chia màn, hoặc màn chính bị che (viewDidDisappear). Video không làm mờ, chỉ phủ độ tối.
  Thử: chọn một video 1 phút → còn 20 giây lặp; mở app toàn màn / chia màn → log "hinh nen dong dung", về màn chính → "chay".
- ~~**3.1.3 Hình dạng và gói icon**~~ (đã bỏ) · Vừa
  Bo tròn / vuông / tròn hẳn, viền kính, bóng; dùng gói icon có sẵn trên máy (theo chuẩn IconBundles) cho màn xe.
  Code: thẻ Bố cục icon thêm Hình dạng (HS_KEY_ICON_SHAPE), Viền kính, Bóng, Gói icon (HS_KEY_ICON_THEME = thư mục trong
  /Library/Themes có IconBundles, đọc <bundle id>-large.png / <bundle id>.png @2x / @3x; app thiếu trong gói giữ icon gốc).
  Áp cho lưới, dock tuỳ chỉnh, thư mục; xem trước và chip trong Cài đặt cũng đổi theo.
  Thử: cài một gói IconBundles (vd. từ Sileo), chọn → icon trên xe đổi; nếu không đổi, xem CarPlay có đọc được /var/jb/Library/Themes không.
- ~~**3.1.4 Thư mục và trang riêng**~~ (đã bỏ) · Vừa
  Gom app vào thư mục trên màn chính CarPlay; một trang riêng cho app iPhone (App Bridge).
  Code: thẻ Thư mục: Thư mục mới (tên + chọn app), chạm thư mục → Chọn app / Đổi tên / Xoá (HS_KEY_FOLDERS, mỗi app một
  thư mục). Trên xe thư mục nằm ở chỗ app đầu tiên của nó, ô kính 4 icon nhỏ; chạm mở thẻ kính giữa màn, chạm ngoài để đóng.
  Trang riêng cho app iPhone (HS_KEY_PHONE_PAGE): app iPhone bắt đầu ở trang mới sau app CarPlay.
  Thử: tạo thư mục 3 app → chạm mở, mở app trong thư mục; bật trang riêng → app iPhone sang trang sau; rút / cắm lại vẫn giữ.
- ~~**3.1.5 Widget trên màn chính**~~ (đã bỏ) · Vừa
  Đặt đồng hồ, thời tiết, nhạc đang phát… thành ô lớn ngay trên màn chính CarPlay.
  Code: thẻ Widget: Đồng hồ / Thời tiết / Đang phát, tối đa 2 (HS_KEY_WIDGETS), thành cột thẻ kính bên trái lưới (200–280 pt).
  Thời tiết: Open-Meteo theo vị trí iOS biết gần nhất, 30 phút một lần, chung bộ nhớ với Màn hình khởi động. Đang phát:
  MediaRemote (tên bài, ca sĩ, ảnh bìa, nút phát / dừng).
  Thử: bật Đồng hồ + Đang phát, mở nhạc → tên bài đổi theo, nút phát / dừng chạy; log "widget". Thời tiết "—" = CarPlay chưa có quyền vị trí.

### 3.2 Màn hình khởi động

- [ ] [ ] **3.2.1 Theo dịp đặc biệt** · Thấp
  Sinh nhật, Tết, Giáng sinh, ngày kỷ niệm → kiểu khởi động riêng hôm đó (người dùng đặt ngày).
- [ ] [ ] **3.2.2 Ngẫu nhiên / xoay vòng** · Thấp
  Mỗi lần cắm xe chọn ngẫu nhiên hoặc lần lượt trong các kiểu đã đánh dấu.
- [ ] [ ] **3.2.3 Logo hãng xe kiểu mẫu** · Thấp
  Mẫu dựng sẵn cho logo + âm thanh kiểu xe sang (nền tối, quét sáng, âm "chime"); **người dùng tự nhập logo hãng**,
  OmniCar không đóng gói sẵn logo / âm thanh của hãng xe (bản quyền thương hiệu).
- [ ] [ ] **3.2.4 Hiệu ứng logo nâng cao** · Vừa
  Quét sáng qua logo, ghép từng mảnh, chữ hiện từng ký tự, hạt sáng; chỉnh màu và tốc độ.
- [ ] [ ] **3.2.5 Thông tin chuyến đi** · Vừa
  Lịch hôm nay, giờ đến nơi làm việc dự kiến, quãng đường hôm qua, pin điện thoại (và pin xe khi có OBD2 / VinFast).
- [ ] [ ] **3.2.6 Chia sẻ mẫu khởi động** · Vừa
  Xuất kiểu khởi động thành một file (ảnh + âm thanh + tham số) để gửi cho người khác, mở là cài.

## Mức 4 – Camera hành trình và hỗ trợ lái (ADAS)

Điện thoại trên giá, camera sau nhìn ra đường. Xử lý bằng Vision / Core ML ngay trên máy, không gửi hình đi đâu.
Trước khi bắt đầu: đo pin và nhiệt khi chạy camera + CarPlay 1 giờ giữa trưa. Không đạt thì dừng mức này.
Thứ tự trong mức này theo phụ thuộc: phải có ghi vòng trước rồi mới có tự lưu.
Điều kiện chung: chấm xanh camera của iOS sẽ hiện, ghi rõ trong mô tả; mọi cảnh báo ghi "hỗ trợ, không thay người lái".

### 4.1 Camera hành trình

- [ ] [ ] **4.1.1 Camera hành trình (ghi vòng)** · Vừa
  Ghi liên tục, chỉ giữ N phút gần nhất, giới hạn dung lượng.
- [ ] [ ] **4.1.2 Tự lưu khi có sự cố** · Thấp (sau khi có ghi vòng)
  Phanh gấp / va chạm → giữ đoạn trước + sau, kèm tốc độ, toạ độ, giờ trên hình.
- [ ] [ ] **4.1.3 Lưu bằng chạm / giọng nói, xem lại trên xe khi đỗ** · Thấp

### 4.2 Hỗ trợ lái (ADAS)

- [ ] [ ] **4.2.1 Báo đèn xanh** · Vừa
  Đang dừng đèn đỏ, đèn chuyển xanh mà xe chưa đi → tiếng ngắn.
- [ ] [ ] **4.2.2 Báo xe trước đã chạy** · Vừa
- [ ] [ ] **4.2.3 Đọc biển tốc độ bằng camera** · Cao
  Nhận biển thật (kể cả biển tạm), đưa vào Bong bóng tốc độ, ưu tiên hơn dữ liệu bản đồ khi chắc chắn.
- [ ] [ ] **4.2.4 Khoảng cách tới xe trước** · Cao
  Hiện số giây bám đuôi, nhắc khi dưới 2 giây.
- [ ] [ ] **4.2.5 Cảnh báo va chạm phía trước** · Cao
- [ ] [ ] **4.2.6 Cảnh báo lệch làn** · Cao
- [ ] [ ] **4.2.7 Phát hiện buồn ngủ / nhìn điện thoại** · Cao
  Chế độ camera trước (máy hướng về người lái). Không chạy cùng lúc với các mục camera sau.

## Mức 5 – Mở rộng hệ sinh thái

Cần thử nghiệm dài và phần cứng / dữ liệu ngoài. Làm khi sản phẩm đã ổn định và có người dùng.

- [ ] [ ] **5.1 Báo tai nạn cho người thân** · Vừa
  Va chạm mạnh + không phản hồi trong 30 giây → gửi vị trí (và clip camera nếu có) cho liên hệ đã chọn.
  Ghi rõ: chỉ hỗ trợ, không thay tính năng phát hiện tai nạn của Apple.
- [ ] [ ] **5.2 API cho nhà phát triển** · Vừa
  Tweak khác / Phím tắt đặt nội dung vào widget màn chính, hoặc thêm kiểu khởi động mới. Có tài liệu và ví dụ mã nguồn mở.
- [ ] [ ] **5.3 Tốc độ khuyên dùng khi vào cua** · Cao
  Từ độ cong đường (dữ liệu bản đồ / OSM) nhắc giảm tốc trước cua gắt, nhất là đường đèo.
- [ ] [ ] **5.4 OBD2 Bluetooth LE** · Cao
  Tốc độ thật, vòng tua, nhiệt độ nước, nhiên liệu, điện áp ắc quy, mã lỗi (đọc / xoá). Thử với ELM327 phổ biến.

## Mức 6 – Gói theo vùng (bắt đầu với Việt Nam)

Làm song song khi có thời gian; mỗi gói chỉ phục vụ một thị trường.

- [ ] [ ] **6.1 Trạm thu phí ETC** · Thấp
  Báo sắp tới trạm, giá vé theo loại xe.
- [ ] [ ] **6.2 Giọng đọc tiếng Việt tự nhiên** cho mọi cảnh báo · Thấp
- [ ] [ ] **6.3 Cơ sở dữ liệu camera phạt nguội / trạm cân** · Vừa
  Cập nhật định kỳ, cảnh báo bằng giọng.
- [ ] [ ] **6.4 Pin xe điện VinFast** · Vừa (phụ thuộc dữ liệu có lấy được không)
- [ ] [ ] **6.5 Mẫu cho vùng khác** · Vừa
  Châu Âu: camera cố định / vùng phát thải thấp; Mỹ: school zone… khi có người dùng ở đó.

## Ý tưởng để dành (chưa xếp mức)

- **Chia sẻ giờ đến nơi** cho một liên hệ khi bắt đầu chuyến đi theo lịch / bố cục.
- **Thời tiết dọc tuyến đường**: mưa lớn ở phía trước 20 phút → nhắc.
- **Trạm xăng / trạm sạc rẻ nhất trên đường đi** (theo dữ liệu từng vùng).
- **Tiếp tục podcast / audiobook** đúng chỗ khi cắm lại xe.
- **Chế độ tài xế mới**: giới hạn app, báo quá tốc độ chặt hơn, khoá Cài đặt bằng mật mã.
- **Chế độ chở khách / gia đình**: ô video chỉ phát khi đỗ hoặc khi có người ngồi ghế phụ (người dùng xác nhận).
- **Chế độ ban đêm tự động**: giảm sáng theo giờ mặt trời lặn, chủ đề tối cho mọi lớp phủ.
- **Nhiều người lái một xe**: nhận người lái theo iPhone đang cắm, mỗi người một hồ sơ.
- **Đo tốc độ tăng tốc 0–100 km/h** và vòng chạy (track mode) cho dân mê xe.
- **Ghi chú giọng nói khi lái**: nói một câu → lưu vào Ghi chú / Lời nhắc khi đến nơi.
- **Âm thanh khi tắt xe / rút cáp**: lời tạm biệt, tóm tắt chuyến đi trên iPhone.
- **Mô phỏng HTML cho mọi tính năng** (như tools/preview) để duyệt giao diện trước khi code.

## Không làm / không hứa

- Phát video DRM (Netflix, Disney+, Prime Video, Apple TV+): bị FairPlay chặn ở phần cứng, không quảng cáo.
- Đóng gói sẵn logo, âm thanh khởi động hay hình ảnh của hãng xe: dính bản quyền thương hiệu, repo có thể gỡ. Chỉ cung cấp mẫu, người dùng tự nhập.
- Tự gỡ tweak của người khác.
- Gửi hình camera, vị trí hay dữ liệu lái lên server. Thống kê ẩn danh chỉ gửi khi người dùng đồng ý, tắt được bất cứ lúc nào; tính năng nào cần mạng phải ghi rõ trong chính sách riêng tư.
- Bất kỳ tính năng nào khuyến khích xem video khi xe đang chạy.

## Nguyên tắc chung

- Mỗi tính năng là một dylib riêng (như hiện tại), tắt được độc lập, có log riêng trong OmniCar.log.
- Mọi giao diện mới có bản mô phỏng trong tools/preview trước, duyệt xong mới code.
- Không có tính năng nào được làm CarPlay sập: lỗi trong một tính năng chỉ được tắt tính năng đó.
- Đo pin và nhiệt cho mọi tính năng chạy liên tục, ghi số đo vào ghi chú phát hành.
