# tools/icons

Script Pillow vẽ logo gói và icon dòng 29pt của từng tính năng. Chạy từ thư mục này
(`PYTHONIOENCODING=utf-8` trên Windows). Cần `pip install pillow`.

| Script | Ra | Ghi chú |
| --- | --- | --- |
| `omnicar_logo.py` | `assets/icon-1024.png`, `Prefs/Resources/icon*.png`, `logo*.png`, `PackageIcon.png` | file glyph cho `harmony_icon.py` của skill `ios-tweak-format` (`~/.claude/skills/ios-tweak-format/scripts/`): `python harmony_icon.py omnicar_logo.py --pick final --project ../.. --prefs-dir Prefs` |
| `bubble_icon.py` | `Features/SpeedBubble/Prefs/Resources/SpeedBubbleIcon*.png` | `python bubble_icon.py <out dir> "S1 sign big"`; không có tên biến thể thì ra sheet so sánh. Cũng chứa `tile()` (ô màu HarmonyOS) mà các script khác dùng |
| `startup_icon.py` | `Features/StartupScreen/Prefs/Resources/StartupScreenIcon*.png` | `python startup_icon.py <out dir> "T2 big card"` |

Icon dòng: ô 29pt bo góc 8.5, màu theo bảng của skill (xanh dương `#0A59F7`, xanh lá `#36B37E`...),
vệt sáng trắng 22% ở trên như `OMCIcon` vẽ cho SF Symbol, để icon vẽ tay và icon SF Symbol nhìn đồng bộ.
