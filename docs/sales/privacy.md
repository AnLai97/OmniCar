# OmniCar – Privacy policy

Last updated: 2026-10-13 · applies to OmniCar 1.0.0 and later unless this page says otherwise.

TODO before publishing: contact address for privacy questions, and a note on what the store (Chariz / own repo) collects for purchases, which is covered by that store's own policy.

---

## English

**Short version: OmniCar collects nothing and sends nothing to the developer. The only network request is the optional Weather startup screen.**

### What OmniCar does not do
- No analytics, no tracking, no ads, no account.
- No data to the developer or anyone else. One exception, only if you choose the **Weather** startup style: the CarPlay
  process asks Open-Meteo (api.open-meteo.com, no account) for the forecast at your last known location, rounded to
  2 decimals (about 1 km). Nothing else is sent; other styles make no network request.
- It does not read your messages, photos, contacts or browsing.

### What stays on your iPhone
- **Settings** you choose in Settings > OmniCar (stored in the standard preferences of the phone).
- **Startup videos** you add, copied to `/var/jb/var/mobile/Library/OmniCar/`.
- **A log file**, `/var/mobile/Documents/OmniCar.log` (an older part is kept as `OmniCar.log.old`; the file rolls over at 2 MB). It records what OmniCar did and any errors or crashes, so problems can be fixed.
- **Car screen info and CarPlay performance** from the last connection, shown on the Diagnostics page.

### Location and speed
Speed Bubble gets your speed and the posted speed limit from the navigation app you chose (Vietmap Live or GOFA), inside that app and with that app's own location permission. OmniCar does not store or log your position. Speed values may appear in the log.

### When you tap "Send log"
OmniCar builds a text file on your phone and opens the iOS share sheet. **Nothing leaves your phone unless you choose where to send it** (Mail, Zalo, etc.). The file contains:
- Date, OmniCar version, master switch and language.
- iOS version and build, device model (for example `iPhone12,1`), jailbreak type, temperature, battery level, memory and the results of the Diagnostics health check.
- Car screen info: head unit name / maker as the car reports it, wired or wireless, resolution, UI size, aspect ratio, max frame rate, last connection time, and the raw CarPlay screen data.
- Which OmniCar features are on, missing hooks, rescue mode state and other CarPlay tweaks found.
- CarPlay performance from the last drive (frame delays, freezes, CPU, memory, temperature).
- The list of installed packages (package id, version and name).
- `OmniCar.log` and `OmniCar.log.old`, which can include the bundle ids of apps you put on the car screen and speed values.

You can open the file before you send it. The developer uses a log you send only to fix the problem you reported, and deletes it when it is no longer needed. TODO: confirm retention period.

### Removing your data
Uninstall OmniCar, then delete `/var/mobile/Documents/OmniCar.log*` and `/var/jb/var/mobile/Library/OmniCar/` with a file manager if you want them gone.

---

## Tiếng Việt

**Ngắn gọn: OmniCar không thu thập và không gửi gì cho tác giả. Kết nối mạng duy nhất là kiểu khởi động Thời tiết (tuỳ chọn).**

### OmniCar không làm gì
- Không thống kê, không theo dõi, không quảng cáo, không tài khoản.
- Không gửi dữ liệu cho tác giả hay bất kỳ ai. Ngoại lệ duy nhất, chỉ khi bạn chọn kiểu khởi động **Thời tiết**: CarPlay hỏi
  Open-Meteo (api.open-meteo.com, không cần tài khoản) dự báo tại vị trí gần nhất của máy, làm tròn 2 chữ số thập phân
  (khoảng 1 km). Không gửi gì khác; các kiểu khác không dùng mạng.
- Không đọc tin nhắn, ảnh, danh bạ hay lịch sử duyệt web.

### Những gì nằm lại trên iPhone
- **Cài đặt** bạn chọn trong Cài đặt > OmniCar (lưu trong cài đặt chuẩn của máy).
- **Video khởi động** bạn thêm, chép vào `/var/jb/var/mobile/Library/OmniCar/`.
- **File log** `/var/mobile/Documents/OmniCar.log` (phần cũ giữ ở `OmniCar.log.old`; quá 2 MB thì xoay vòng). Ghi việc OmniCar đã làm, lỗi và lần sập để sửa lỗi.
- **Thông tin màn xe và hiệu năng CarPlay** của lần cắm gần nhất, hiện ở trang Chẩn đoán.

### Vị trí và tốc độ
Bong bóng tốc độ lấy tốc độ và biển giới hạn từ app dẫn đường bạn chọn (Vietmap Live hoặc GOFA), ngay trong app đó và bằng quyền vị trí của chính app đó. OmniCar không lưu và không ghi log vị trí của bạn. Giá trị tốc độ có thể xuất hiện trong log.

### Khi bấm "Gửi log"
OmniCar tạo một file chữ trên máy rồi mở bảng chia sẻ của iOS. **Không có gì rời máy trừ khi bạn chọn nơi gửi** (Zalo, Mail…). File gồm:
- Ngày giờ, phiên bản OmniCar, công tắc tổng, ngôn ngữ.
- Phiên bản iOS và bản build, đời máy (ví dụ `iPhone12,1`), kiểu jailbreak, nhiệt độ, mức pin, bộ nhớ và kết quả kiểm tra của trang Chẩn đoán.
- Thông tin màn xe: tên / hãng đầu xe do xe báo, có dây hay không dây, độ phân giải, cỡ giao diện, tỉ lệ, FPS tối đa, lần cắm gần nhất, và dữ liệu màn xe thô của CarPlay.
- Tính năng OmniCar nào đang bật, hook thiếu, trạng thái chế độ cứu, tweak CarPlay khác tìm thấy.
- Hiệu năng CarPlay của chuyến đi gần nhất (khung hình trễ, khựng, CPU, bộ nhớ, nhiệt độ).
- Danh sách gói đã cài (mã gói, phiên bản, tên).
- `OmniCar.log` và `OmniCar.log.old`, có thể gồm mã (bundle id) của app bạn đưa lên màn xe và giá trị tốc độ.

Bạn có thể mở xem file trước khi gửi. Tác giả chỉ dùng log bạn gửi để sửa lỗi bạn báo và xoá khi không cần nữa. TODO: chốt thời hạn lưu.

### Xoá dữ liệu
Gỡ OmniCar, rồi dùng trình quản lý file xoá `/var/mobile/Documents/OmniCar.log*` và `/var/jb/var/mobile/Library/OmniCar/` nếu muốn.
