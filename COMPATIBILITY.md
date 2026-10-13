# OmniCar – Kết quả thử

Bảng ghi kết quả thử trên xe thật cho hai mục của ROADMAP (Mức 1 – Hỗ trợ và ổn định):
**Chạy thật trên iOS 15 16 17 và 18** và **Thử với nhiều app hơn**. Sau này là nguồn cho trang tương thích công khai.

Trang công khai: `docs/compatibility.html` (en + vi). Sửa file này trước, rồi chép sang trang đó: hai nơi phải khớp.

Ký hiệu: ✅ chạy tốt · 🟡 chạy được (ghi rõ lỗi nhỏ) · ❌ không chạy (ghi lý do) · ⬜ chưa thử.
Trên trang công khai: ✅ = Works · 🟡 = Partly · ❌ = Doesn't · ⬜ = Untested. Chỉ đổi khỏi ⬜ khi đã thử trên xe thật.

## Tóm tắt hỗ trợ

| Mục | Trạng thái | Ghi chú |
|---|---|---|
| iOS 15 | Hỗ trợ | Tác giả đã chạy (hook chỉ có trên iOS 16 tự bỏ qua, ghi log); bảng dưới chưa điền |
| iOS 16 | Hỗ trợ | Bản phát triển chính (Chia màn hình, App Bridge dựa selector iOS 16); bảng dưới chưa điền |
| iOS 17, 18 | ⬜ chưa thử | Gói cài được (`firmware (>= 15.0)`); Chẩn đoán hiện hook thiếu |
| iOS 14 trở xuống | ❌ | Gói yêu cầu iOS 15.0+ |
| Rootless: Dopamine (A12+, arm64e), palera1n rootless (A9–A11, arm64) | Hỗ trợ | Gói `iphoneos-arm64`, build arm64 + arm64e |
| roothide | ❌ chưa hỗ trợ | Có trong kế hoạch (ROADMAP Phát hành 0) |
| Rootful | ❌ | Chỉ rootless |
| Tweak xung đột | CarBridge, DuoDash, TrueDash, CarPlayEnable | Cảnh báo trong Cài đặt (`OMCConflictingTweaks`), không tự gỡ |

## Cách thử một bản iOS

1. Cài bản mới nhất, respring, cắm xe một lần.
2. Mở Cài đặt > OmniCar > **Chẩn đoán**. Mục Tính năng phải hiện "đủ N hook". Có dòng "thiếu" thì chép
   chân mục (tên hook thiếu) vào cột Ghi chú: đó là selector cần đường dự phòng trên iOS này.
3. Bản dev (`OMC_AUTOTEST` = 1): đỗ xe, vào Hỗ trợ > **Tự kiểm tra (dev)**, chọn tính năng, Bắt đầu. Các bộ test
   chạy lần lượt (thanh cam trên màn xe hiện tiến độ, chạm để dừng); kết quả từng bước hiện ngay trên trang đó.
4. Bấm **Gửi log** (kèm kết quả từng bước + ảnh màn xe), lưu cạnh bảng này (ví dụ `tests/ios17-iphone11/`).
   Điền bảng dưới từ kết quả đó; chỉ phải thử tay phần tự kiểm tra không làm được (app có giao diện CarPlay
   riêng, xoay / phát video bên trong app, âm thanh màn hình khởi động).

## Theo bản iOS

| Mục thử | iOS 15 | iOS 16 | iOS 17 | iOS 18 |
|---|---|---|---|---|
| Máy / jailbreak | | | | |
| Chẩn đoán: hook Chia màn hình | ⬜ | ⬜ | ⬜ | ⬜ |
| Chẩn đoán: hook App Bridge | ⬜ | ⬜ | ⬜ | ⬜ |
| Bố cục 2 ô | ⬜ | ⬜ | ⬜ | ⬜ |
| Bố cục 3 ô | ⬜ | ⬜ | ⬜ | ⬜ |
| Bố cục 1 lớn + 2 | ⬜ | ⬜ | ⬜ | ⬜ |
| Bố cục 2 + 1 lớn | ⬜ | ⬜ | ⬜ | ⬜ |
| Chia dọc, kéo tỉ lệ, đóng / mở ô, về Home | ⬜ | ⬜ | ⬜ | ⬜ |
| App có giao diện CarPlay riêng trong ô (Maps, Spotify…) | ⬜ | ⬜ | ⬜ | ⬜ |
| YouTube qua App Bridge (phát, xoay, toàn màn) | ⬜ | ⬜ | ⬜ | ⬜ |
| TikTok qua App Bridge | ⬜ | ⬜ | ⬜ | ⬜ |
| Icon app iPhone trên màn chính CarPlay | ⬜ | ⬜ | ⬜ | ⬜ |
| Bong bóng tốc độ (Vietmap Live / GOFA) | ⬜ | ⬜ | ⬜ | ⬜ |
| Màn hình khởi động | ⬜ | ⬜ | ⬜ | ⬜ |
| Chế độ cứu (Tự kiểm tra > Thử chế độ cứu, cắm lần 3 tự phục hồi) | ⬜ | ⬜ | ⬜ | ⬜ |
| Ghi chú (hook thiếu, lỗi) | | | | |

## Theo app (qua App Bridge)

| App | Kết quả | iOS đã thử | Ghi chú / lý do |
|---|---|---|---|
| YouTube | ⬜ | | |
| TikTok | ⬜ | | |
| Facebook | ⬜ | | |
| Instagram | ⬜ | | |
| Chrome | ⬜ | | |
| Safari | ⬜ | | |
| Zalo | ⬜ | | |
| Grab | ⬜ | | |
| Shopee | ⬜ | | |
| X | ⬜ | | |
| Twitch | ⬜ | | |
| Plex | ⬜ | | |
| Netflix | ⬜ | | Dự kiến ❌ (DRM), chưa xác nhận |
| Disney+ | ⬜ | | Dự kiến ❌ (DRM), chưa xác nhận |

Giới hạn đã biết: app có DRM (Netflix, Disney+…) chặn hình khi đưa ra màn ngoài, ghi ❌ kèm "DRM".

## Nguồn Bong bóng tốc độ

| App | Kết quả | iOS đã thử | Ghi chú |
|---|---|---|---|
| Vietmap Live | ⬜ | | |
| GOFA | ⬜ | | |

## Giới hạn dự kiến (đưa lên trang công khai)

Suy ra từ cách hoạt động, chưa xác nhận hết trên xe:

- App có DRM: dự kiến màn đen (có thể vẫn có tiếng).
- CarPlay không dây: App Bridge có thể trễ / kém nét hơn cắm dây, tuỳ đầu xe.
- Bong bóng tốc độ chỉ đọc Vietmap Live / GOFA, khi app đó đang chạy.
- Chưa có bàn phím trên màn xe cho app qua App Bridge.
- Đổi cài đặt có hiệu lực ở lần cắm sau; respring một lần sau khi cài.
- Ba ô / hai app video cùng lúc có thể làm máy nóng (Chế độ nhẹ giới hạn còn 2 app).
- iOS 17, 18: phần dựa vào hook thiếu sẽ không chạy.

## Đầu xe đã thử

Lấy từ Chẩn đoán > Màn xe.

| Đầu xe | Độ phân giải | Tỉ lệ | Kết nối | iOS | Ghi chú |
|---|---|---|---|---|---|
| | | | | | |
