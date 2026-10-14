# OmniCar — giao diện

Giao diện đã chốt (13/10/2026): **HarmonyOS sáng + kính chất lỏng 3D** (logo phương án D). Mọi màn hình của
OmniCar (màn xe, Cài đặt, icon) làm theo đây. Mẫu đầy đủ: `tools/preview/theme.html` (mở bằng trình duyệt);
logo: `tools/preview/logo.html`; bàn phím: `tools/preview/keyboard.html`. Thử ở trang mẫu trước rồi mới sửa code.

## Màu
- Nền chất lỏng pastel: oải hương #B7A6FF, xanh trời #8FD3FF, bạc hà #9DF2D8, đào #FFC2D6 (chỉ làm nền: đầu
  trang Cài đặt, bảng chọn app, màn hình khởi động, logo).
- **Bảng trên màn xe** (khay bố cục, thanh tỉ lệ, thanh •••, thông báo, bảng chọn app, bàn phím, ô nút Split Screen
  trên dock) = **nền phối 4 màu như nền logo** (`OMCLogoMeshImage`): tím oải #C9BAFC trên trái, xanh trời #A6DDFD trên
  phải, hồng #FEC4D8 dưới trái, bạc hà #A0F1D9 dưới phải; viền trắng 1pt, bóng tím nhạt. Không nền xám / trắng đặc.
- **Ô trong bảng** (nút X, nút thanh •••, phím chức năng) = kính trắng trong 50% + viền trắng 1pt như đĩa trong logo.
  **Khung từng ô bố cục** = viền trắng 1,5pt; ô bố cục chưa chọn nền trong suốt (cùng màu bảng). **Không dùng viền đen.**
- **Đang chọn** (bố cục đang dùng, tỉ lệ đang dùng) = nền vẫn trong + **viền cầu vồng 2pt** 4 màu logo (#A78BFA,
  #60C5FA, #5EDDB6, #F59AC0) + quầng tím nhạt.
- **Nút chính = gradient tím #9B87F8 → xanh trời #5DB4F6**: tay cầm ••• đang mở, Enter / Shift của bàn phím, nút
  "Mở lại", ô đang chọn app trong sơ đồ bảng chọn app.
- Chữ / icon trên màn xe: chàm dịu #4A4F80 (phụ 55%).
- **Công tắc bật: xanh lá** (`OMCSwitchColor`, systemGreen).
- **Dấu X đóng / tắt: đỏ** #FF5A5F (nút tắt có nền đỏ nhạt), luôn ở cuối.
- Logo tác giả "AL" (`Prefs/Resources/avatar*.png`) giữ nguyên, không vẽ lại.

## Hình
- Bo góc: bảng lớn 24 (khay bố cục, bảng chọn app, bàn phím), thẻ Cài đặt 20, thanh = viên thuốc, ô bố cục 14,
  phím 7, nút tròn.
- Icon kiểu HarmonyOS Symbol: lưới 24, nét 1,5–2, đầu và góc bo tròn, khung cửa sổ bo lớn.

## Màn xe
- **Nút ••• của mỗi ô**: tay cầm nhỏ giữa mép trên ô; chạm → tay cầm gradient, thanh nền logo thả xuống. Mỗi nút = ô
  kính tròn 40pt chỉ icon 22pt, không nhãn: Đổi app (4 ô vuông) · Toàn màn (4 góc khung) / Chia màn khi đang chạy 1 màn hình
  (2 khung) · Cửa sổ nổi (khung + ô nhỏ đặc) · Chạy nền (gạch ngang) | Tắt app (X đỏ, tách bằng vạch trắng).
  Icon HarmonyOS Symbol giữ nguyên. Thanh ••• của app iPhone (App Bridge, `ABHost.mm`) vẽ giống hệt.
- **Bảng chọn app**: icon app không có khung (trần như màn Home), cột sơ đồ bên phải nền trong.
- **Nút Split Screen trên dock**: ô nền logo 4 màu, viền trắng, glyph 2 ô màu chàm (giống nút Chia màn của thanh •••).
- **Thanh tỉ lệ**: hình mô tả tỉ lệ (1/3 · 1/2 · 2/3), không dùng số.
- **Bàn phím** theo bàn phím HarmonyOS: thẻ nổi bo tròn 4 góc (20) cách mép 6 pt, kín bề rộng ô app, hàng số riêng, gợi ý góc phím (Telex: dấu /
  chữ phím đó tạo), bong bóng phóng to khi chạm; nền logo 4 màu, phím trắng không viền, phím chức năng kính trong
  viền trắng, Shift / Enter gradient.
- **Màn hình khởi động**: kiểu "Chất lỏng" (`SS_STYLE_LIQUID`) là bộ mặt mới — 4 vệt pastel trôi chậm, logo kính nổi
  lên, chữ OmniCar gradient, thanh tải mảnh; tự thay cho Video khi chưa có video. Các kiểu khác giữ bản sắc riêng.
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
