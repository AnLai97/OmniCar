# OmniCar – Ghi chú phát triển

Dành cho người viết code: trạng thái code, file liên quan và cách thử của từng mục trong ROADMAP.md (cùng tên
mục, cùng thứ tự). ROADMAP.md chỉ giữ lộ trình: mục, mô tả, "Xong khi". Viết code cho một mục thì ghi vào đây.

## Trước khi phát hành

- Đặt `OMC_AUTOTEST` = 0 (Core/OmniCar.h) hoặc build bằng `make package OMC_AUTOTEST=0`: bỏ hẳn phần tự kiểm tra.
- Bản dịch 12 ngôn ngữ (ngoài vi / en) là dịch máy: cần người bản xứ đọc lại.
- Xem lại các TODO trong docs/sales/ (giá, hoàn tiền, liên hệ).

## Mức 1 – Cần ngay (trước khi mở repo miễn phí)

### Hỗ trợ và ổn định

- **Gửi log một chạm**
  Code: Hỗ trợ > Gửi log (OMCShareReport) → `OmniCar-log-<ngày>.txt`. Chờ thử gửi Zalo trên máy.

- **Màn chẩn đoán**
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

- **Thông tin đầu xe**
  Code: CarPlay ghi màn xe + phiên CarKit mỗi lần cắm (OMCCrashGuard), Chẩn đoán > Màn xe. Chờ thử trên xe.

- **Phát hiện tweak xung đột**
  Code: thẻ cảnh báo đầu trang chính khi dylib của tweak đó đang nạp; Chẩn đoán liệt kê cả gói đã cài.

- **Chế độ cứu (rescue)**
  Code: OMCCrashGuard (Core) nghi tính năng theo backtrace, thông báo trên iPhone, thẻ "Bật lại" ở trang chính.
  Thử: Chẩn đoán, nhấn giữ dòng OmniCar → chọn tính năng → cắm xe 3 lần.

- **Tự kiểm tra trên xe (chỉ bản dev)**
  Code: Core/OMCTest.h (khung), Features/SplitScreen/SCPAutoTest.mm, cuối StartupScreen.x, cuối SPPBubble.mm,
  Prefs/OMCAutoTestController.m. Chờ chạy thử trên xe.

- **Thử với nhiều app hơn**
  Bảng ghi kết quả: COMPATIBILITY.md.

### Bán quốc tế

- **Đơn vị và quy chuẩn theo nước**
  Code: Bong bóng tốc độ > Đơn vị (tự động theo vùng / km/h / mph) và Biển tốc độ (tự động / Viên / Mỹ), số vẫn so
  bằng km/h nên cảnh báo vượt tốc không đổi. Chia màn hình > Vị trí tay lái (tự động theo CarKit / trái / phải): tay
  lái phải thì app đang dùng vào ô bên phải. Chờ thử trên xe (tên trường rightHandDrive của CarKit).

- **Hướng dẫn lần đầu**
  Code: Prefs/OMCOnboardingController.m, 4 trang, tự hiện lần đầu mở Cài đặt (onboardingDone), Hỗ trợ > Xem lại
  hướng dẫn.

- **Nhiều ngôn ngữ**
  Code: 14 ngôn ngữ (OMCSupportedLanguages, Core/OMCCommon.m), theo ngôn ngữ máy hoặc chọn trong Cài đặt; thiếu câu
  nào thì dùng tiếng Anh. Chữ trên xe: OMCTr(vi, en), ngôn ngữ khác tra `<lang>.lproj/Car.strings` (khoá = câu tiếng
  Anh). Bản dịch máy: cần người bản xứ đọc lại; chưa kiểm tra chữ bị cắt (de) và RTL (ar) trên máy.

- **Trang tương thích công khai**
  Code: docs/compatibility.html (trang tĩnh, EN / VI), đồng bộ với COMPATIBILITY.md. Chưa có kết quả thử nào.

- **Bộ tài liệu bán hàng**
  Code: docs/sales/ (mô tả ngắn / dài, FAQ, riêng tư, kịch bản quay shotlist.md). Còn thiếu: quay video, chụp ảnh,
  giá / chính sách hoàn tiền (TODO trong file).

### Dùng hằng ngày

- **Phóng to tạm một ô**
  Code: SCPCarSplit zoomedSlot (ô khác ẩn nhưng giữ kích thước scene), cả thanh ••• của app iPhone (SpringBoard vẽ).

- **Bàn phím trên màn xe**
  Code: app iPhone qua App Bridge: App.xm chặn bàn phím iPhone khi app trên xe và báo SpringBoard; ABKeyboard.mm vẽ
  bàn phím trên màn xe (chữ / số, EN / VI Telex), gửi phím về app. App CarPlay gốc dùng bàn phím của CarPlay.
  Chờ thử YouTube / Safari trên xe.

## Nguyên tắc chung

- Mỗi tính năng là một dylib riêng (như hiện tại), tắt được độc lập, có log riêng trong OmniCar.log.
- Mọi giao diện mới có bản mô phỏng trong tools/preview trước, duyệt xong mới code.
- Không có tính năng nào được làm CarPlay sập: lỗi trong một tính năng chỉ được tắt tính năng đó.
- Đo pin và nhiệt cho mọi tính năng chạy liên tục, ghi số đo vào ghi chú phát hành.
