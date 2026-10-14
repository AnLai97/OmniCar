# tools/icons

Script Pillow vẽ logo gói và icon dòng 29pt của từng tính năng. Chạy từ thư mục này
(`PYTHONIOENCODING=utf-8` trên Windows). Cần `pip install pillow`.

| Script | Ra | Ghi chú |
| --- | --- | --- |
| `omnicar_logo_liquid.ps1` | `assets/icon-1024.png`, `Prefs/Resources/icon*.png`, `logo*.png`, `PackageIcon.png`, `App/Resources/AppIcon60x60@2x/@3x.png` | **logo hiện dùng** (13/10/2026, phương án D trong `tools/preview/logo.html`): nền chất lỏng pastel (oải hương, xanh trời, bạc hà, đào), vòng + nút play bằng kính trắng mờ nổi 3D (bóng đổ mềm, vệt bóng, viền sáng). Phần trộn màu tính từng điểm ảnh bằng C# nhúng (GDI+ không làm mờ được). `powershell -ExecutionPolicy Bypass -File tools/icons/omnicar_logo_liquid.ps1 -Project .` (`-Out <thư mục>` để chỉ xuất bản xem trước) |
| `omnicar_logo_glass.ps1` | (bản trước) | kiểu kính HarmonyOS tối — ô kính tối (#33373F → #0C0D10, vệt sáng nửa trên, viền trắng mảnh), vòng + nút play trắng với quầng sáng trắng toả ra ngoài vòng, không còn màu xanh; cùng hình với nút dock `SCPCLogoImage`. Thêm nhiễu ±1,5 mức để nền không bị sọc. `powershell -ExecutionPolicy Bypass -File tools/icons/omnicar_logo_glass.ps1 -Project .` (thêm `-Out <thư mục>` để chỉ xuất bản xem trước, không đụng vào project) |
| `omnicar_logo_white.ps1` | (bản trước) | ô trắng, vòng + nút play tô gradient xanh (#2563EB → #0B1026), cùng hình với nút dock `SCPCLogoImage`. Vẽ bằng .NET System.Drawing, không cần Python: `powershell -ExecutionPolicy Bypass -File tools/icons/omnicar_logo_white.ps1 -Project .` (chạy từ gốc repo). Icon app là bản vuông đặc (iOS tự bo góc) |
| `omnicar_logo.py` | (bản cũ: nền xanh, glyph trắng) | file glyph cho `harmony_icon.py` của skill `ios-tweak-format` (`~/.claude/skills/ios-tweak-format/scripts/`): `python harmony_icon.py omnicar_logo.py --pick final --project ../.. --prefs-dir Prefs` |
| `bubble_icon.py` | `Features/SpeedBubble/Prefs/Resources/SpeedBubbleIcon*.png` | `python bubble_icon.py <out dir> "S1 sign big"`; không có tên biến thể thì ra sheet so sánh. Cũng chứa `tile()` (ô màu HarmonyOS) mà các script khác dùng |
| `startup_icon.py` | `Features/StartupScreen/Prefs/Resources/StartupScreenIcon*.png` | `python startup_icon.py <out dir> "T2 big card"` |

Icon dòng: ô 29pt bo góc 8.5, màu theo bảng của skill (xanh dương `#0A59F7`, xanh lá `#36B37E`...),
vệt sáng trắng 22% ở trên như `OMCIcon` vẽ cho SF Symbol, để icon vẽ tay và icon SF Symbol nhìn đồng bộ.
