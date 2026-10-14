# OmniCar – Lộ trình tính năng (dev)

Các mức tính năng và trạng thái code của từng mục. Kế hoạch phát hành, giá, Lite / Pro: **ROADMAP-RELEASE.md**.

Cách dùng file này
- Mức tính năng xếp theo **ưu tiên**: Mức 1 là thứ phải có ngay, mức sau làm khi mức trước đã xong.
- Mỗi mức chia thành **nhóm** theo tính năng. Trong mỗi nhóm, mục xếp **từ dễ đến khó** (Thấp → Vừa → Cao);
  mục nào phụ thuộc mục khác thì đứng sau nó.
- Mỗi mục có **hai ô**: `- [x] [ ]`. Ô thứ nhất = **code xong** (Claude đánh khi làm xong và ghi Code / Thử bên dưới);
  ô thứ hai = **đã kiểm tra** (tác giả tự đánh sau khi thử thấy tốt, ghi phiên bản bên cạnh). Chưa ai đánh ô thứ hai thay tác giả.
- **Độ khó**: Thấp (vài ngày) · Vừa (1–2 tuần) · Cao (vài tuần, cần thử nghiệm nhiều trên xe).
- **Xong khi**: tiêu chí kiểm tra được trên xe thật, không phải "code đã viết".
- **Code** / **Thử**: đã viết gì, ở file nào, thử thế nào (ghi khi bắt đầu code một mục).

Đã có (1.0.0): Chia màn hình 2–3 ô (4 bố cục, chia dọc, kéo tỉ lệ, yêu thích, gần đây, Siri URL), App Bridge
(app iPhone lên xe, icon trên màn chính CarPlay), Bong bóng tốc độ (18 kiểu, Vietmap Live / GOFA), Màn hình
khởi động (một video MP4), Cài đặt vi / en.

## Trước khi phát hành

- Đặt `OMC_AUTOTEST` = 0 (Core/OmniCar.h) hoặc build bằng `make package OMC_AUTOTEST=0`: bỏ hẳn phần tự kiểm tra.
- Bản dịch 12 ngôn ngữ (ngoài vi / en) là dịch máy: cần người bản xứ đọc lại.
- Xem lại các TODO trong docs/sales/ (giá, hoàn tiền, liên hệ).

---

## Mức 1 – Cần ngay (trước khi mở repo miễn phí)

Thiếu một trong các mục này thì khách quốc tế không mua, hoặc mua rồi đòi hoàn tiền.

### Hỗ trợ và ổn định

- [x] [ ] **Gửi log một chạm** · Thấp
  Nút trong Cài đặt: gói OmniCar.log + phiên bản iOS, máy, đầu xe, danh sách tweak → share sheet.
  Xong khi: khách gửi được file qua Zalo / email trong 3 chạm.
  Code: Hỗ trợ > Gửi log (OMCShareReport) → `OmniCar-log-<ngày>.txt`. Chờ thử gửi Zalo trên máy.
- [x] [ ] **Màn chẩn đoán** · Thấp
  Độ phân giải màn xe, dây / không dây, nhiệt độ máy, FPS app iPhone, phiên bản từng tính năng.
  Code: Hỗ trợ > Chẩn đoán là trang kiểm tra sức khoẻ cho người dùng: kết luận chung ở đầu, ~20 mục ✓ / ⚠ / ✗ kèm
  cách sửa (điện thoại: iOS, jailbreak, trình nạp tweak, gói, OmniCar đang chạy đúng bản, bộ nhớ, pin, nhiệt, tweak
  xung đột; CarPlay: kết nối, OmniCar trong CarPlay, tương thích iOS, lần sập gần nhất, chế độ cứu, màn xe; từng tính
  năng), chạm để respring / bật lại; số liệu thô ở Chi tiết kỹ thuật. Chưa có FPS app iPhone (cần đo trong App
  Bridge). Dây / không dây đọc từ CarKit: chờ thử trên xe.
  Hiệu năng CarPlay: CarPlay tự đo trong lúc lái (khung hình trễ 10 s mỗi phút, khựng ≥ 0,5 s, CPU, RAM còn dư,
  nhiệt, nguồn điện thấp, tweak khác nạp vào CarPlay), Chẩn đoán đọc lại, chấm ✓ / ⚠ / ✗ và gợi ý nguyên nhân
  chính; chạm để đo lại / xoá log. Chờ thử trên xe để chỉnh ngưỡng.
  Tối ưu: nút Tối ưu (tự làm được gì thì làm, còn lại liệt kê cho người dùng), Chế độ nhẹ tắt / tự động / luôn bật
  (chia màn hình bỏ kính mờ + chỉ 2 app, bong bóng 1 s/lần không đổ bóng, bỏ video khởi động; tự động bật khi máy
  nóng, khựng 3 lần / 2 phút hoặc ≥ 15% khung trễ, tắt sau 3 phút ổn), dọn RAM khi cắm xe / dọn ngay. App Bridge chỉ cài
  hook khi app được đưa lên xe. Trang Chẩn đoán: Cần xử lý (nút sửa ngay) → Tối ưu → các nhóm thu gọn.
- [x] [ ] **Thông tin đầu xe** · Thấp
  Độ phân giải, tỉ lệ màn, chất lượng video gợi ý (gộp vào Màn chẩn đoán).
  Code: CarPlay ghi màn xe + phiên CarKit mỗi lần cắm (OMCCrashGuard), Chẩn đoán > Màn xe. Chờ thử trên xe.
- [x] [ ] **Phát hiện tweak xung đột** · Thấp
  Thấy CarBridge, DuoDash, TrueDash, CarPlayEnable… đang bật → cảnh báo trong Cài đặt (không tự gỡ tweak của người khác).
  Code: thẻ cảnh báo đầu trang chính khi dylib của tweak đó đang nạp; Chẩn đoán liệt kê cả gói đã cài.
- [x] [ ] **Chế độ cứu (rescue)** · Vừa
  CarPlay sập 2 lần liền trong 60 giây sau khi cắm → tự tắt tính năng nghi gây lỗi, lần cắm sau báo cho người dùng.
  Xong khi: cố tình gây crash trong một tính năng, CarPlay tự phục hồi ở lần cắm thứ 3.
  Code: OMCCrashGuard (Core) nghi tính năng theo backtrace, thông báo trên iPhone, thẻ "Bật lại" ở trang chính.
  Thử: Chẩn đoán, nhấn giữ dòng OmniCar → chọn tính năng → cắm xe 3 lần.
- [x] [ ] **Tự kiểm tra trên xe (chỉ bản dev)** · Vừa
  Công cụ cho tác giả, không phát hành: macro `OMC_AUTOTEST` (Core/OmniCar.h, hoặc `make OMC_AUTOTEST=0`) bỏ hẳn
  khỏi bản phát hành. Cài đặt > Hỗ trợ > Tự kiểm tra: chọn tính năng → mỗi tính năng tự chạy bộ test của nó trên xe,
  mỗi bước ghi đạt / lỗi + lý do + trạng thái + ảnh màn xe → Gửi log. Process sập giữa chừng thì lần sau chạy tiếp.
  Bộ test: Chia màn hình (bố cục, tỉ lệ, đổi chỗ, cửa sổ nổi, bảng chọn / bảng bố cục, toàn màn, lệnh URL, yêu thích,
  gần đây, bấm nhanh), App Bridge (trong ô, tỉ lệ, đổi chỗ, 3 ô, chặn cửa sổ nổi, toàn màn, đóng, icon, 2 app cùng
  lúc), Màn hình khởi động (phát, khung chạy, tự tắt, chạm bỏ qua, tắt tính năng), Bong bóng tốc độ (hiện trên xe,
  số, gần / vượt giới hạn, ẩn khi Split Screen chiếm màn, 18 kiểu, cỡ, mất nguồn).
  Xong khi: một lần chạy trên xe ra đủ kết quả từng bước, gửi log có ảnh, sửa lỗi không cần thử tay lại từng ca.
  Code: Core/OMCTest.h (khung), Features/SplitScreen/SCPAutoTest.mm, cuối StartupScreen.x, cuối SPPBubble.mm,
  Prefs/OMCAutoTestController.m. Chờ chạy thử trên xe.
- [ ] [ ] **Thử với nhiều app hơn** · Vừa
  Danh sách tối thiểu: YouTube, TikTok, Facebook, Instagram, Chrome, Safari, Zalo, Grab, Shopee, X, Twitch, Plex.
  Xong khi: có bảng app chạy tốt / chạy được / không chạy kèm lý do, đưa lên trang tương thích.
  Bảng ghi kết quả: COMPATIBILITY.md.
- [ ] [ ] **Chạy thật trên iOS 15 16 17 và 18** · Cao
  App Bridge và Chia màn hình đang dựa selector iOS 16. Kiểm tra từng selector, có đường dự phòng khi thiếu.
  Kiểm tra lại luôn app có giao diện CarPlay riêng chạy trong ô.
  Xong khi: thử đủ 4 bố cục + YouTube / TikTok qua App Bridge trên iOS 15, 16, 17, 18 (rootless), ghi kết quả.
  Chẩn đoán hiện hook thiếu trên từng iOS; ghi kết quả vào COMPATIBILITY.md.

### Bán quốc tế

- [x] [ ] **Đơn vị và quy chuẩn theo nước** · Thấp
  km/h ↔ mph; biển tốc độ kiểu Viên (tròn viền đỏ) / kiểu Mỹ (chữ nhật trắng); lái tay phải → đảo bố cục mặc định.
  Code: Bong bóng tốc độ > Đơn vị (tự động theo vùng / km/h / mph) và Biển tốc độ (tự động / Viên / Mỹ), số vẫn so
  bằng km/h nên cảnh báo vượt tốc không đổi. Chia màn hình > Vị trí tay lái (tự động theo CarKit / trái / phải): tay
  lái phải thì app đang dùng vào ô bên phải. Chờ thử trên xe (tên trường rightHandDrive của CarKit).
- [x] [ ] **Hướng dẫn lần đầu** · Thấp
  3–4 trang: chọn app lên xe, chọn bố cục đầu tiên, bật bong bóng tốc độ, cách gọi bảng bố cục trên xe.
  Code: Prefs/OMCOnboardingController.m, 4 trang, tự hiện lần đầu mở Cài đặt (onboardingDone), Hỗ trợ > Xem lại
  hướng dẫn.
- [x] [ ] **Nhiều ngôn ngữ** · Thấp (dịch) / Vừa (kiểm tra)
  Tối thiểu: en, vi, es, pt-BR, de, fr, it, ru, zh-Hans, ja, ko, ar (RTL), th, id.
  Xong khi: mọi trang Cài đặt và chữ trên xe không bị cắt ở ngôn ngữ dài nhất (de) và RTL (ar).
  Code: 14 ngôn ngữ (OMCSupportedLanguages, Core/OMCCommon.m), theo ngôn ngữ máy hoặc chọn trong Cài đặt; thiếu câu
  nào thì dùng tiếng Anh. Chữ trên xe: OMCTr(vi, en), ngôn ngữ khác tra `<lang>.lproj/Car.strings` (khoá = câu tiếng
  Anh). Bản dịch máy: cần người bản xứ đọc lại; chưa kiểm tra chữ bị cắt (de) và RTL (ar) trên máy.
- [x] [ ] **Trang tương thích công khai** · Thấp
  iOS, kiểu jailbreak (rootless / roothide), chip, đầu xe đã thử, app đã thử, giới hạn đã biết (DRM).
  Code: docs/compatibility.html (trang tĩnh, EN / VI), đồng bộ với COMPATIBILITY.md. Chưa có kết quả thử nào.

### Dùng hằng ngày

- [x] [ ] **Phóng to tạm một ô** · Thấp
  Chạm đúp thanh "•••" → ô to toàn vùng app, chạm lại → về bố cục cũ (khác "toàn màn" là không đóng các ô khác).
  Code: SCPCarSplit zoomedSlot (ô khác ẩn nhưng giữ kích thước scene), cả thanh ••• của app iPhone (SpringBoard vẽ).
- [x] [ ] **Bàn phím trên màn xe** · Cao
  Một bàn phím chung cho mọi ô (kể cả app iPhone qua App Bridge), kiểu HarmonyOS, có tiếng Việt và các ngôn ngữ chính.
  Xong khi: gõ được tìm kiếm trong YouTube và ô địa chỉ của Safari trên xe.
  Code: app iPhone qua App Bridge: App.xm chặn bàn phím iPhone khi app trên xe và báo SpringBoard; ABKeyboard.mm vẽ
  bàn phím trên màn xe (chữ / số, EN / VI Telex), gửi phím về app. App CarPlay gốc dùng bàn phím của CarPlay.
  Chờ thử YouTube / Safari trên xe.

## Mức 2 – Quan trọng (bằng DuoDash, làm ngay sau bản bán đầu tiên)

Khách so sánh trực tiếp với DuoDash / CarBridge ở các mục này, và đây là những thứ khách nhìn thấy mỗi lần cắm xe.

### Màn chính CarPlay (nâng cấp từ App Bridge)

Trang Cài đặt "App trên màn xe" mở rộng thành "Màn chính CarPlay": app, bố cục, hình nền, dock.
Mỗi thay đổi có xem trước trong Cài đặt (mô phỏng màn xe) trước khi áp lên xe.
Bản xem trước giao diện: tools/preview/home.html (trang Cài đặt + màn xe mô phỏng đổi theo ngay).
Code chung cho cả 5 mục (chưa thử trên xe, MẶC ĐỊNH TẮT): App trên màn xe > Màn chính CarPlay
(Features/AppBridge/Prefs/OMCHomeScreenController.m, có màn xe xem trước ở đầu trang; key HS_KEY_* trong AppBridge.h).
Trên xe (Features/SplitScreen/SCPHomeScreen.mm): bật thì OmniCar vẽ lưới icon + dock + hình nền của riêng mình lên trên
của CarPlay; lưới / icon dock gốc chỉ bị ẩn, tắt là trả lại nguyên vẹn. Thứ tự app đọc từ model *IconListView (cách bảng
chọn app của Split Screen đã chạy trên xe), mở app qua DashBoard _launchAppWithInfo:forURL: (app iPhone → App Bridge),
dock là appDockViewController của root (như nút Split Screen). Lần đầu bật ghi log "HomeScreen: DIAG cay man chinh" để
chỉnh nếu khác. Thử chung: bật Màn chính CarPlay, cắm xe, Gửi log (dòng "HomeScreen:").

- [x] [ ] **Ẩn và sắp xếp app** · Vừa
  Ẩn cả app CarPlay gốc không dùng (CarBridge có), kéo đổi thứ tự app iPhone và app CarPlay trong một danh sách.
  Xong khi: thứ tự và app ẩn giữ nguyên sau khi rút / cắm lại và sau respring.
  Code: một danh sách duy nhất ở App trên màn xe > mục Trên màn xe (app CarPlay xe đã đọc + app iPhone đã chọn): kéo để
  sắp xếp, con mắt để ẩn, ghim lên dock, "−" để bỏ app iPhone khỏi xe → HS_KEY_ORDER / HS_KEY_HIDDEN / HS_KEY_DOCK /
  AB_KEY_APPS; app mới nối theo thứ tự CarPlay. Trang Màn chính CarPlay chỉ còn giao diện (lưới, hình nền, dock).
  Thử: ẩn 1 app CarPlay gốc, kéo YouTube lên đầu → cắm xe, rút / cắm lại, respring: vẫn đúng.
- [x] [ ] **Cỡ icon** · Vừa
  Thanh trượt cỡ icon trên màn chính (ví dụ 80–130 %), lưới tự tính lại để không tràn màn.
  Code: Cỡ icon 80–130 % (HS_KEY_ICON_SIZE, icon gốc 64 pt); lưới bớt cột / hàng khi không vừa màn xe.
  Thử: kéo 130 % trên màn xe nhỏ → không icon nào bị cắt, app dư sang trang sau.
- [x] [ ] **Số cột / hàng và tên app** · Vừa
  Chọn số cột × hàng mỗi trang, ẩn / hiện tên dưới icon, khoảng cách icon.
  Code: Số cột 3–7, Số hàng 1–3, Khoảng cách 60–140 %, Tên dưới icon (HS_KEY_COLS / ROWS / GAP / NAMES); vuốt ngang
  đổi trang, chấm trang.
  Thử: 4 × 2 không tên → mỗi trang 8 icon; bật tên → tên không chồng icon hàng dưới.
- [x] [ ] **Hình nền màn chính** · Vừa
  Chọn hình dựng sẵn hoặc ảnh từ Ảnh (bỏ chọn từ Tệp), cắt theo tỉ lệ màn xe, chỉnh độ mờ và độ tối để icon vẫn dễ nhìn.
  Code: ô Mặc định + 6 hình dựng sẵn (gradient như bản xem trước, vẽ 1920 × 720) + ô ảnh của bạn, nút Từ Ảnh
  → OmniCar/HomeScreen/wallpaper.jpg (≤ 1920 px, có trong bản sao lưu), lấp kín vùng app (cắt
  theo tỉ lệ), Độ mờ 0–30 (CIGaussianBlur trên luồng phụ), Độ tối 0–70 %; Bỏ hình nền = dùng lại hình nền CarPlay.
  Thử: ảnh dọc và ảnh ngang đều phủ kín, không méo; đổi độ mờ / tối thấy ngay khi thả tay.
- [x] [ ] **Dock tuỳ chỉnh** · Vừa
  Chọn app nào nằm cố định trên dock (kể cả app iPhone), ẩn mục gợi ý của CarPlay.
  Code: chip app ghim (✕ để bỏ) + chip "+ Thêm" (chọn app), hoặc ghim từ danh sách app; tối đa 4, kể cả app iPhone, thay cho gợi ý của CarPlay; không ghim + tắt "Gợi ý của CarPlay" = dock trống.
  Nút Split Screen trên dock giữ nguyên. Dock ngắn hơn số app ghim thì chỉ hiện số vừa (ghi log).
  Thử: ghim Bản đồ + YouTube → dock chỉ còn 2 app đó, chạm mở đúng app; bỏ ghim hết → gợi ý của CarPlay trở lại.

### Màn hình khởi động mới

Đổi từ "một video" sang nhiều **kiểu khởi động**. Mỗi kiểu là một mẫu có tham số; người dùng chọn kiểu,
xem trước ngay trong Cài đặt. Âm thanh phát qua loa xe khi CarPlay kết nối.

- [x] [ ] **Khung chọn kiểu khởi động** · Vừa
  Trang Cài đặt mới: danh sách kiểu (Video, Logo + âm thanh, Lời chào, Thời tiết…), xem trước, thời lượng, chạm để bỏ qua.
  Video MP4 hiện tại thành một kiểu trong danh sách, cài đặt cũ được giữ.
  Code: startupScreenStyle (0 Video, 1 Logo, 2 Lời chào, 3 Thời tiết), SSStartupView.m vẽ chung cho xe và xem trước
  trong Cài đặt (Prefs/SSStartupViewPrefs.m #import lại file đó). Chờ thử trên xe.
- [x] [ ] **Logo + âm thanh của bạn** · Thấp (sau khi có khung)
  Chọn ảnh logo (PNG trong suốt) + âm thanh; vài hiệu ứng xuất hiện: hiện dần, phóng to, phát sáng.
  Code: logo PNG (Ảnh / Tệp, ≤ 1024 px) ở StartupScreen/Logo, hiệu ứng hiện dần / phóng to / phát sáng.
- [x] [ ] **Âm thanh khởi động riêng** · Thấp
  Gắn âm thanh vào bất kỳ kiểu nào (tiếng máy nổ, chuông, lời chào ghi âm), chỉnh âm lượng, tắt khi đang có cuộc gọi.
  Code: một file âm thanh (Tệp) ở StartupScreen/Sounds, âm lượng, SpringBoard phát; bỏ qua khi đang gọi (CXCallObserver
  trong SpringBoard: chờ thử).
- [x] [ ] **Lời chào theo giờ** · Thấp
  "Chào buổi sáng, An" + giờ, ngày; chữ và nền đổi theo sáng / chiều / tối.
  Code: giờ, "Chào buổi sáng, <tên>", ngày; nền đổi theo sáng / chiều / tối / khuya.
- [x] [ ] **Thời tiết và nhiệt độ** · Vừa
  Nhiệt độ hiện tại, cao / thấp trong ngày, khả năng mưa, biểu tượng thời tiết; lấy từ WeatherKit / dữ liệu Thời tiết của iOS, không có mạng thì dùng số đo gần nhất.
  Code: Open-Meteo (cần mạng, toạ độ làm tròn 2 số, đã ghi trong Cài đặt), vị trí gần nhất của CarPlay, cache 12 h,
  không có dữ liệu thì về Lời chào. Chờ thử: CarPlay có quyền vị trí / mạng không. Cập nhật docs/sales/privacy.md.

### Chia màn hình

- [x] [ ] **Ghim ô bản đồ** · Thấp
  Ô được ghim không bị thay khi chọn bố cục / app khác.
  Code: splitScreenPinnedApp (Chia màn hình > Ô được ghim, hoặc omnicar://splitscreen/pin?app=): ô của app đó không bị
  thay khi chọn app, đổi bố cục hay bớt ô.
- [x] [ ] **Nhớ tỉ lệ theo cặp app** · Thấp
  Maps + Nhạc = 70/30, Maps + YouTube = 50/50… tự áp lại.
  Code: có từ trước (SCPPrefs ratioForPairLeft:right:, SPL_KEY_PAIR_RATIOS).
- [x] [ ] **Hồ sơ theo từng xe** · Thấp
  Nhận xe qua tên / ID đầu xe → bố cục chia màn, màn chính CarPlay, kiểu khởi động, cỡ bong bóng riêng cho từng xe.
  Code: Core OMCProfileSwitch khi cắm xe (khoá xe từ phiên CarKit), OMCProfileKeys() là các cài đặt theo xe;
  Cài đặt > Hồ sơ theo xe (Prefs/OMCCarProfilesController.m). Chờ thử: tên trường định danh xe của CarKit.
- [ ] [ ] **Chọn ô phát tiếng** · Vừa
  Hai ô cùng có âm thanh → chọn ô nào phát, ô kia tắt tiếng; tự giảm nhạc khi bản đồ đọc hướng dẫn.
  Chưa làm: cần biết CarPlay chọn nguồn âm thanh thế nào (bộ dò liệt kê lớp NowPlaying / Audio).
- [ ] [ ] **Gán nút giọng nói trên vô lăng** · Vừa
  Bấm giữ = Siri như cũ; bấm ngắn = mở bảng bố cục / một app / một lệnh OmniCar, người dùng chọn.
  Chưa làm: cần đường sự kiện nút Siri của DashBoard (bộ dò liệt kê DBEvent).

### Lái xe

- [x] [ ] **Cảnh báo quá tốc độ** · Thấp
  Vượt biển + ngưỡng tuỳ chọn → viền màn đổi màu, tiếng ngắn; có chế độ im lặng.
  Code: SPPWarn.mm: viền đỏ nhấp nháy trên màn xe + tiếng bíp 1 lần mỗi lần vượt; ngưỡng 0–20, chế độ tắt / chỉ viền /
  viền + tiếng (Bong bóng tốc độ > Cảnh báo quá tốc độ).
- [ ] [ ] **Chế độ lái** · Vừa
  Trên tốc độ đặt trước: ô video chỉ còn tiếng / mờ đi, chữ và nút to hơn, khoá thao tác nhỏ; dừng xe → trở lại.
  Đây cũng là câu trả lời khi repo / người mua hỏi về an toàn.
  Code: ABHost che ô app iPhone ("chỉ còn tiếng", khoá chạm) khi tốc độ ≥ 10 km/h 3 giây, dừng xe 5 giây là mở lại
  (App trên màn xe > Chế độ lái; tốc độ từ com.anlai.omnicar/speed). Còn thiếu: chữ / nút to hơn khi chạy.
  Bản xem trước chữ / nút to: tools/preview/theme.html mục 5b (thanh ••• còn 3 nút to, khay bố cục ô to vẫn đủ Bố cục /
  Gần đây / Yêu thích, thanh tỉ lệ to, bảng chọn app 4 cột, chip "Đang lái"). Chờ tác giả duyệt rồi mới code.
- [ ] [ ] **Nguồn tốc độ toàn cầu** · Vừa
  Thêm Google Maps, Waze, Apple Maps; dự phòng bằng giới hạn tốc độ OpenStreetMap tải sẵn theo vùng.
  Code: nguồn "GPS iPhone" (SPPGPS.mm, CoreLocation trong SpringBoard) dùng được mọi nơi nhưng không có biển giới hạn.
  Google Maps / Waze / Apple Maps là nguồn 3–5 (NavApp.xm chạy trong app): tốc độ từ GPS riêng trong app, giới hạn quét
  trên màn hình như Vietmap / GOFA (vòng đỏ, tên ảnh, chữ); chỉ quét khi là nguồn đang chọn (SPP_DARWIN_SOURCE). Chờ thử
  trên xe: log "chan doan" của NavApp khi chưa thấy biển cho biết giao diện từng app để chỉnh cách đọc giới hạn.
  Còn thiếu: giới hạn tốc độ OSM tải sẵn theo vùng.

### Cài đặt và hiệu năng

- [x] [ ] **Sao lưu / khôi phục cài đặt** · Thấp
  Xuất một file `.omnicar`, mở file là nạp lại (bố cục, màn chính, kiểu khởi động, kiểu bong bóng, ảnh / video / âm thanh đã chọn).
  Code: Prefs/OMCBackup.m: file .omnicar (plist: cài đặt + file dữ liệu ≤ 200 MB), Hỗ trợ > Sao lưu / Khôi phục.
  Mở file .omnicar thẳng từ Tệp / AirDrop / Zalo: app OmniCar khai báo kiểu com.anlai.omnicar.backup (App/Resources/Info.plist),
  chép file vào OmniCar/Inbox rồi mở Cài đặt > OmniCar, trang chính hỏi khôi phục (OMCBackupOfferImported). Chờ thử trên máy.
- [x] [ ] **Có gì mới** · Thấp
  Sau mỗi bản cập nhật hiện một trang ngắn trong Cài đặt.
  Code: Prefs/OMCWhatsNewController.m + Resources/WhatsNew.plist (theo phiên bản trong control), tự hiện 1 lần sau mỗi bản
  mới, Hỗ trợ > Có gì mới. Thêm mục cho mỗi phiên bản mới vào WhatsNew.plist.
- [x] [ ] **Tinh chỉnh hiệu năng** · Vừa
  Giới hạn FPS app iPhone, tự giảm khi máy nóng, giữ app trong bộ nhớ hay không, giữ kết nối CarPlay khi khoá máy.
  Code (một phần, Mức 1): Chế độ nhẹ tự giảm khi máy nóng, dọn RAM; App Bridge giữ app trên xe khi khoá máy.
  Giới hạn FPS: App trên màn xe > Khung hình app (Tối đa / 30 / 24, AB_KEY_FPS); SpringBoard gửi kèm thông báo hướng,
  App.xm giới hạn CADisplayLink của app (hoạt ảnh, cuộn, game; video không đổi). Chờ thử trên xe.
- [ ] [ ] **Tối ưu CarPlay không dây** · Vừa
  Tự giảm chất lượng / FPS app iPhone khi kết nối không dây chập chờn.
  Code (một phần): Khung hình app để Tối đa thì tự giới hạn 30 khi CarPlay không dây (OMCCarWireless, đọc phiên CarKit)
  hoặc Chế độ nhẹ bật. Còn thiếu: đo kết nối chập chờn (cần số liệu từ xe không dây).
- [x] [ ] **Phím tắt Siri đầy đủ** · Vừa
  Hành động cho app Phím tắt: mở bố cục, đặt app vào ô, đổi tỉ lệ, đổi hình nền / kiểu khởi động, bật / tắt từng tính năng.
  Code: omnicar://splitscreen/layout | ratio | swap | zoom | pin, omnicar://feature/<tính năng>?on=, lite?mode=,
  startup?style=, cleanram (Core.x, Features/SplitScreen/SpringBoard.xm). Chưa có: đổi hình nền (chưa có hình nền).

## Mức 3 – Vượt DuoDash (tạo khác biệt khi lái xe)

Những thứ DuoDash không có. Đây là nội dung chính cho video quảng cáo các bản cập nhật lớn.

### Màn chính CarPlay

- [ ] [ ] **Hình nền theo giờ** · Thấp
  Hai ảnh ngày / đêm, tự đổi theo giờ mặt trời mọc / lặn hoặc theo chế độ sáng / tối của xe.
- [ ] [ ] **Hình nền động** · Vừa
  Video ngắn lặp hoặc ảnh động làm nền, tự dừng khi máy nóng hoặc khi đang chia màn.
- [ ] [ ] **Hình dạng và gói icon** · Vừa
  Bo tròn / vuông / tròn hẳn, viền kính, bóng; dùng gói icon có sẵn trên máy (theo chuẩn IconBundles) cho màn xe.
- [ ] [ ] **Thư mục và trang riêng** · Vừa
  Gom app vào thư mục trên màn chính CarPlay; một trang riêng cho app iPhone (App Bridge).
- [ ] [ ] **Widget trên màn chính** · Vừa
  Đặt đồng hồ, thời tiết, nhạc đang phát… thành ô lớn ngay trên màn chính CarPlay (dùng chung phần Ô tiện ích).

### Màn hình khởi động

- [ ] [ ] **Theo dịp đặc biệt** · Thấp
  Sinh nhật, Tết, Giáng sinh, ngày kỷ niệm → kiểu khởi động riêng hôm đó (người dùng đặt ngày).
- [ ] [ ] **Ngẫu nhiên / xoay vòng** · Thấp
  Mỗi lần cắm xe chọn ngẫu nhiên hoặc lần lượt trong các kiểu đã đánh dấu.
- [ ] [ ] **Logo hãng xe kiểu mẫu** · Thấp
  Mẫu dựng sẵn cho logo + âm thanh kiểu xe sang (nền tối, quét sáng, âm "chime"); **người dùng tự nhập logo hãng**,
  OmniCar không đóng gói sẵn logo / âm thanh của hãng xe (bản quyền thương hiệu).
- [ ] [ ] **Hiệu ứng logo nâng cao** · Vừa
  Quét sáng qua logo, ghép từng mảnh, chữ hiện từng ký tự, hạt sáng; chỉnh màu và tốc độ.
- [ ] [ ] **Thông tin chuyến đi** · Vừa
  Lịch hôm nay, giờ đến nơi làm việc dự kiến, quãng đường hôm qua, pin điện thoại (và pin xe khi có OBD2 / VinFast).
- [ ] [ ] **Chia sẻ mẫu khởi động** · Vừa
  Xuất kiểu khởi động thành một file (ảnh + âm thanh + tham số) để gửi cho người khác, mở là cài.

### Chia màn hình

- [ ] [ ] **Thanh nhạc chung** · Thấp
  Luôn hiện, điều khiển app nào đang phát (kể cả qua App Bridge).
- [ ] [ ] **Tự phóng to ô bản đồ khi sắp rẽ** · Vừa
  Còn ~300 m tới chỗ rẽ → ô bản đồ to ra (có hiệu ứng), qua chỗ rẽ → trả bố cục cũ. Ngưỡng chỉnh được.
- [ ] [ ] **Bố cục tự do** · Vừa
  Kéo vạch để tự tạo bố cục tới 4 ô, lưu thành mẫu, chia sẻ bằng mã ngắn (mã chứa bố cục, không chứa dữ liệu cá nhân).
- [ ] [ ] **Tự động theo ngữ cảnh** · Vừa
  Quy tắc: giờ, ngày trong tuần, xe, vị trí, có lịch hẹn → mở bố cục tương ứng khi cắm.
- [ ] [ ] **Ô tiện ích** · Vừa
  Đồng hồ, thời tiết, lịch hôm nay, nhạc đang phát, pin điện thoại, nhiệt độ máy, la bàn, độ cao.
- [ ] [ ] **Cụm đồng hồ kiểu xe thể thao** · Vừa
  Bố cục dạng đồng hồ: tốc độ, bản đồ thu nhỏ, nhạc; thêm dữ liệu OBD2 khi có (Mức 5).
- [ ] [ ] **Kéo icon thả vào ô** · Vừa
  Từ dock / màn chính CarPlay kéo icon vào ô muốn mở.
- [ ] [ ] **Cửa sổ nổi hoàn chỉnh** · Vừa
  Thu một app thành ô nhỏ nổi ở góc (kiểu hình trong hình), kéo đi, chạm để mở lại.
- [ ] [ ] **Cử chỉ lớn khi đang chạy** · Vừa
  Vuốt 3 ngón trái / phải đổi chỗ ô, chụm về màn chính; khi xe chạy chỉ nhận cử chỉ lớn.

### Lái xe

- [ ] [ ] **Nhắc nghỉ** · Thấp
  Lái liên tục 2 giờ (chỉnh được) → nhắc nghỉ, gợi ý trạm dừng gần nhất.
- [ ] [ ] **Nhớ chỗ đỗ xe** · Thấp
  Rút CarPlay → lưu vị trí (+ ảnh nếu có camera), chỉ đường đi bộ quay lại.
- [ ] [ ] **Nhắc kiểm tra ghế sau** · Thấp
  Rút CarPlay khi trời nóng (thời tiết) → thông báo trên iPhone.
- [ ] [ ] **HUD bằng chính iPhone** · Thấp
  Màn iPhone hiện tốc độ + hướng rẽ tiếp theo, lật gương, đặt dưới kính lái.
- [ ] [ ] **Hướng dẫn làn đường cỡ lớn** · Vừa
  Mũi tên làn to ở mép màn, kể cả khi bản đồ ở ô nhỏ.
- [ ] [ ] **Giữ tốc độ trong hầm** · Vừa
  Mất GPS → ước lượng tiếp bằng gia tốc kế + tốc độ trước đó, bong bóng không đứng số.
- [ ] [ ] **Nút vô lăng làm phím tắt** · Vừa
  Bấm đúp "bài tiếp" = đổi ô đang chọn, giữ = mở bảng bố cục.
- [ ] [ ] **Điểm lái an toàn và nhật ký chuyến đi** · Vừa
  Quãng đường, thời gian, phanh gấp, tăng tốc gắt, vào cua nhanh, số lần quá tốc độ; xem lại trong Cài đặt.
- [ ] [ ] **Lệnh giọng nói ngay trên máy** · Vừa
  Vài lệnh cố định không cần mạng: "lưu clip", "phóng to bản đồ", "tắt video", "bố cục đi làm".
- [ ] [ ] **Thông báo gọn** · Vừa
  Gom tin nhắn thành dải ngắn ở mép, Siri đọc khi chạm, trả lời bằng câu soạn sẵn; ẩn nội dung khi xe chạy.

### Giao diện

- [ ] [ ] **Màn chờ khi đỗ** · Thấp
  Đỗ lâu → đồng hồ lớn / ảnh, giống StandBy (dùng chung mẫu với Màn hình khởi động).
- [ ] [ ] **Hiệu ứng chuyển cảnh HarmonyOS** · Thấp
  Mở ô, đổi app, đổi bố cục mượt theo DESIGN.md.
- [ ] [ ] **Chủ đề giao diện** · Thấp
  Màu nhấn, độ trong kính, kiểu thanh nút; chủ đề theo hãng xe.
- [ ] [ ] **Hỗ trợ núm xoay (đầu xe không cảm ứng)** · Cao
  Điều khiển bảng bố cục và chọn ô bằng núm / nút; DuoDash không có.

## Mức 4 – Camera hành trình và hỗ trợ lái (ADAS)

Điện thoại trên giá, camera sau nhìn ra đường. Xử lý bằng Vision / Core ML ngay trên máy, không gửi hình đi đâu.
Trước khi bắt đầu: đo pin và nhiệt khi chạy camera + CarPlay 1 giờ giữa trưa. Không đạt thì dừng mức này.
Thứ tự trong mức này theo phụ thuộc: phải có ghi vòng trước rồi mới có tự lưu.
Điều kiện chung: chấm xanh camera của iOS sẽ hiện, ghi rõ trong mô tả; mọi cảnh báo ghi "hỗ trợ, không thay người lái".

### Camera hành trình

- [ ] [ ] **Camera hành trình (ghi vòng)** · Vừa
  Ghi liên tục, chỉ giữ N phút gần nhất, giới hạn dung lượng.
- [ ] [ ] **Tự lưu khi có sự cố** · Thấp (sau khi có ghi vòng)
  Phanh gấp / va chạm → giữ đoạn trước + sau, kèm tốc độ, toạ độ, giờ trên hình.
- [ ] [ ] **Lưu bằng chạm / giọng nói, xem lại trên xe khi đỗ** · Thấp

### Hỗ trợ lái (ADAS)

- [ ] [ ] **Báo đèn xanh** · Vừa
  Đang dừng đèn đỏ, đèn chuyển xanh mà xe chưa đi → tiếng ngắn.
- [ ] [ ] **Báo xe trước đã chạy** · Vừa
- [ ] [ ] **Đọc biển tốc độ bằng camera** · Cao
  Nhận biển thật (kể cả biển tạm), đưa vào Bong bóng tốc độ, ưu tiên hơn dữ liệu bản đồ khi chắc chắn.
- [ ] [ ] **Khoảng cách tới xe trước** · Cao
  Hiện số giây bám đuôi, nhắc khi dưới 2 giây.
- [ ] [ ] **Cảnh báo va chạm phía trước** · Cao
- [ ] [ ] **Cảnh báo lệch làn** · Cao
- [ ] [ ] **Phát hiện buồn ngủ / nhìn điện thoại** · Cao
  Chế độ camera trước (máy hướng về người lái). Không chạy cùng lúc với các mục camera sau.

## Mức 5 – Mở rộng hệ sinh thái

Cần thử nghiệm dài và phần cứng / dữ liệu ngoài. Làm khi sản phẩm đã ổn định và có người dùng.

- [ ] [ ] **Báo tai nạn cho người thân** · Vừa
  Va chạm mạnh + không phản hồi trong 30 giây → gửi vị trí (và clip camera nếu có) cho liên hệ đã chọn.
  Ghi rõ: chỉ hỗ trợ, không thay tính năng phát hiện tai nạn của Apple.
- [ ] [ ] **API cho nhà phát triển** · Vừa
  Tweak khác / Phím tắt đặt nội dung vào ô tiện ích, widget màn chính, hoặc thêm kiểu khởi động mới. Có tài liệu và ví dụ mã nguồn mở.
- [ ] [ ] **Tốc độ khuyên dùng khi vào cua** · Cao
  Từ độ cong đường (dữ liệu bản đồ / OSM) nhắc giảm tốc trước cua gắt, nhất là đường đèo.
- [ ] [ ] **OBD2 Bluetooth LE** · Cao
  Tốc độ thật, vòng tua, nhiệt độ nước, nhiên liệu, điện áp ắc quy, mã lỗi (đọc / xoá). Thử với ELM327 phổ biến.

## Mức 6 – Gói theo vùng (bắt đầu với Việt Nam)

Làm song song khi có thời gian; mỗi gói chỉ phục vụ một thị trường.

- [ ] [ ] **Trạm thu phí ETC** · Thấp
  Báo sắp tới trạm, giá vé theo loại xe.
- [ ] [ ] **Giọng đọc tiếng Việt tự nhiên** cho mọi cảnh báo · Thấp
- [ ] [ ] **Cơ sở dữ liệu camera phạt nguội / trạm cân** · Vừa
  Cập nhật định kỳ, cảnh báo bằng giọng.
- [ ] [ ] **Pin xe điện VinFast** · Vừa (phụ thuộc dữ liệu có lấy được không)
- [ ] [ ] **Mẫu cho vùng khác** · Vừa
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
