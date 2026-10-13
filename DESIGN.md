# OmniCar — giao diện

Giao diện đã chốt (13/10/2026): **HarmonyOS sáng + kính chất lỏng 3D** (logo phương án D). Mọi màn hình của
OmniCar (màn xe, Cài đặt, icon) làm theo đây. Mẫu đầy đủ: `tools/preview/theme.html` (mở bằng trình duyệt);
logo: `tools/preview/logo.html`; bàn phím: `tools/preview/keyboard.html`. Thử ở trang mẫu trước rồi mới sửa code.

## Màu
- Nền chất lỏng pastel: oải hương #B7A6FF, xanh trời #8FD3FF, bạc hà #9DF2D8, đào #FFC2D6 (chỉ làm nền: đầu
  trang Cài đặt, bảng chọn app, màn hình khởi động, logo).
- **Đang chọn / nút chính = gradient tím #8B7CFF → xanh trời #5AB8FF có quầng màu**: bố cục đang dùng, tay cầm
  ••• đang mở, tỉ lệ đang dùng, Enter / Shift của bàn phím, nút "Mở lại".
- **Kính trắng** cho bảng / thanh / thẻ / phím: trắng 58–78%, mờ, viền sáng phía trên, bóng tím nhạt. Không nền xám đặc.
- Chữ / icon: mực #1F2233 (phụ #6B7090).
- **Công tắc bật: xanh lá** (`OMCSwitchColor`, systemGreen).
- **Dấu X đóng / tắt: đỏ** #FF5A5F (nút tắt có nền đỏ nhạt), luôn ở cuối.
- Logo tác giả "AL" (`Prefs/Resources/avatar*.png`) giữ nguyên, không vẽ lại.

## Hình
- Bo góc: bảng lớn 24 (khay bố cục, bảng chọn app, bàn phím), thẻ Cài đặt 20, thanh = viên thuốc, ô bố cục 14,
  phím 7, nút tròn.
- Icon kiểu HarmonyOS Symbol: lưới 24, nét 1,5–2, đầu và góc bo tròn, khung cửa sổ bo lớn.

## Màn xe
- **Nút ••• của mỗi ô**: tay cầm nhỏ giữa mép trên ô; chạm → tay cầm gradient, viên kính chỉ có icon thả xuống:
  Chọn app mới (4 ô vuông) · Chạy 1 màn hình (4 góc khung) / Chia màn hình khi đang chạy 1 màn hình (2 khung) ·
  Ảnh trong ảnh (khung + ô nhỏ đặc) · Chạy nền (gạch ngang) · Tắt hẳn app (X đỏ).
- **Thanh tỉ lệ**: hình mô tả tỉ lệ (1/3 · 1/2 · 2/3), không dùng số.
- **Bàn phím** theo bàn phím HarmonyOS: giữa vùng app, sát mép dưới, hàng số riêng, gợi ý góc phím (Telex: dấu /
  chữ phím đó tạo), bong bóng phóng to khi chạm; màu kính trắng, phím chức năng tím nhạt, Shift / Enter gradient.
- Không tô tối cả màn hình; không bao giờ che dock.

## Chuyển động
- Hiện: lò xo HarmonyOS (damping ~0,86, thu 0,94 → 1, thả xuống 8 pt); ẩn: trượt / mờ 250 ms
  (đường cong 0.2, 0, 0.2, 1). Các mục hiện lần lượt.
- Bảng bố cục, thanh •••, thanh tỉ lệ tự đóng sau 4 s không chạm.

## Dùng khi lái xe
- Ô bấm to, cách xa nhau; nhiều mục thì chia trang vuốt ngang có chấm trang HarmonyOS, không cuộn dọc.
- Chữ ngắn hoặc không có chữ.

## Logo
Phương án D (`tools/preview/logo.html`): nền chất lỏng pastel trong ô squircle, vòng + nút play CarPlay bằng kính
trắng mờ nổi 3D, viền sáng, vệt bóng. Vẽ ra PNG bằng `tools/icons/omnicar_logo_liquid.ps1`.
