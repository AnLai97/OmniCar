# OmniCar — giao diện

Giao diện đã chốt (11/10/2026). Mọi màn hình mới của OmniCar (màn xe, Cài đặt, icon) làm theo đây.
Xem và thử trước mọi thay đổi bằng `tools/preview/splitscreen.html` (mở bằng trình duyệt) rồi mới push.

## Bề mặt: kính HarmonyOS
- Bảng, thanh, popup: kính mờ mỏng tối (ultra-thin dark material, phủ tối ~0,18–0,2), viền trắng 22% dày
  0,5 pt, bóng đen mềm, bo góc lớn liên tục (bảng 22–24 pt, thanh dạng viên).
- Không tô tối cả màn hình; không bao giờ che dock.

## Màu
- **Đang chọn / đang chạm / đang dùng: trắng sáng có quầng sáng trắng** — ô đang chọn trong popup chọn app,
  chấm tròn khi chạm, tỉ lệ đang dùng, bố cục đang dùng, viền ô loé lên, ô sắp thả khi kéo •••.
  Nội dung nằm trên nền trắng thì chuyển sang màu tối.
- **Mọi dấu X đóng / thoát / huỷ: đỏ** (`SCPCDanger` #FF5C54; trên nền trắng dùng #E0332E).
- **Không dùng màu xanh** làm điểm nhấn. Biểu tượng: nét trắng (hoặc tối trên nền trắng).
- **Ngoại lệ: công tắc trong Settings khi bật là xanh lá** (`OMCSwitchColor`, systemGreen như iOS). Thanh trượt, nút vẫn than chì / xám bạc.
- Bản thân bảng / thanh vẫn là kính — đã thử làm cả thanh trắng và bỏ.
- **Bàn phím trên màn xe theo bàn phím HarmonyOS** (không phải kính): nền than xanh đặc #252935, phím xám xanh
  phẳng bo 7 pt, hàng số riêng, ký tự gợi ý góc phím (Telex: dấu / chữ phím đó tạo), phím `,` `.` xám xanh nhạt.
  Shift đang bật và Enter: trắng chữ tối (không xanh). Mẫu: `tools/preview/keyboard.html`.

## Chuyển động
- Lò xo êm (damping ~0,86), phóng nhẹ từ 0,9–0,92 lên 1; các mục hiện lần lượt (mờ → rõ, trôi lên nhẹ).
- Đóng: thu về 0,94 và mờ đi. Bảng bố cục, thanh nút, thanh tỉ lệ tự đóng sau 4 s không chạm.

## Dùng khi lái xe
- Ô bấm to, cách xa nhau; nhiều mục thì chia trang vuốt ngang có chấm trang HarmonyOS, không cuộn dọc.
- Chữ ngắn hoặc không có chữ — sơ đồ ô đã nói đang chọn cho ô nào.

## Logo
`tools/icons/omnicar_logo_glass.ps1`: ô kính tối, vòng + nút play CarPlay trắng có quầng sáng trắng toả ra
ngoài vòng. Logo chỉ dùng cho icon tweak / trang cài đặt.

Nút Split Screen trên dock CarPlay (`SCPCSplitImage`) là hình 2 ô cạnh nhau (chia đôi màn hình), không ô nền,
cùng màu với lưới app của nút Home ngay dưới nó, để đồng bộ với dock chứ không lặp lại logo.
