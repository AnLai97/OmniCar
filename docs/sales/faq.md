# OmniCar – FAQ

Keep answers in sync with `docs/compatibility.html`. Items marked TODO need a decision or a link before publishing.

---

## English

**1. How do I install OmniCar?**
Add the repo `<TODO: repo URL>` in Sileo or Zebra, install OmniCar, then respring once. Connect your car: features apply each time CarPlay connects. Every feature has its own switch under Settings > OmniCar.

**2. Which iOS versions are supported?**
iOS 15 and 16. iOS 17 and 18 are not tested yet; OmniCar installs there, and Send log tells the developer which part is missing on your iOS. iOS 14 and older are not supported.

**3. Which jailbreaks work? What about roothide?**
Rootless jailbreaks only: Dopamine and palera1n in rootless mode. roothide and rootful jailbreaks are not supported at the moment.

**4. Does it work with wireless CarPlay?**
Yes, OmniCar works the same way on wired and wireless CarPlay. App Bridge sends a live iPhone app to the car as video, so on wireless CarPlay it can lag or look softer than on a cable, depending on the head unit.

**5. Which cars / head units work?**
OmniCar draws on whatever screen size the car reports, so it is made for any CarPlay head unit. Tested head units are listed on the compatibility page `<TODO: URL>`; the list is still being filled.

**6. Why is an app black on the car screen (Netflix, Disney+…)?**
Video apps with DRM block their picture on any external screen, including CarPlay. You may hear sound but see a black picture. This is the app's protection, not something OmniCar can turn off.

**7. Do I still need CarBridge?**
No. App Bridge puts iPhone apps on the car screen by itself. Please turn off CarBridge and any other tweak that changes CarPlay: running them together can break it. OmniCar shows a warning when it finds them, but never removes other tweaks.

**8. CarPlay crashed and a feature turned itself off. What happened?**
That is rescue mode. If CarPlay crashes twice in a row within a minute of connecting, OmniCar turns off the feature that caused it so CarPlay keeps working, and tells you on the iPhone. Turn it back on from the OmniCar main page (after an update), and please send the log so the bug can be fixed.

**9. How do I send a log?**
Settings > OmniCar > Send log, then pick Mail or a chat app. Please add your head unit model and what you were doing. The file is made on your phone and only leaves it when you share it (see Privacy).

**10. I changed a setting but nothing changed in the car.**
Most changes apply the next time CarPlay connects: unplug and reconnect (or turn wireless CarPlay off and on). After the first install, respring once.

**11. The Speed Bubble shows nothing.**
The bubble reads speed and the posted limit from Vietmap Live or GOFA. Pick your app as the speed source in Speed Bubble settings and keep that app running (it can be in the background).

**12. Can I type in YouTube or Safari on the car screen?**
Yes: when you tap a text field in an iPhone app shown through App Bridge, OmniCar shows its own keyboard on the car screen (English, or Vietnamese with Telex). Not tested on a car yet.

**13. My phone gets hot or the car screen stutters.**
Three live panes or two video apps at once are heavy. Lite mode turns on by itself while the phone is hot or CarPlay stutters: it drops blur effects and limits Split Screen to two apps.

**14. Can I get a refund?**
TODO: refund policy (time window, how to ask, what is needed – for example a log showing the problem).

**15. Does OmniCar collect my data?**
No. OmniCar sends nothing to the developer. The only network request is the optional Weather startup screen (Open-Meteo, location rounded to about 1 km). See the privacy policy.

---

## Tiếng Việt

**1. Cài OmniCar thế nào?**
Thêm repo `<TODO: link repo>` vào Sileo hoặc Zebra, cài OmniCar, respring một lần. Cắm xe: tính năng áp dụng mỗi lần CarPlay kết nối. Mỗi tính năng có công tắc riêng trong Cài đặt > OmniCar.

**2. Hỗ trợ iOS nào?**
iOS 15 và 16. iOS 17, 18 chưa thử; vẫn cài được, và Gửi log cho tác giả biết phần nào bị thiếu trên bản iOS của bạn. Không hỗ trợ iOS 14 trở xuống.

**3. Jailbreak nào dùng được? Còn roothide?**
Chỉ jailbreak rootless: Dopamine và palera1n chế độ rootless. Hiện chưa hỗ trợ roothide và rootful.

**4. Có chạy với CarPlay không dây không?**
Có, OmniCar chạy như nhau với CarPlay có dây và không dây. App Bridge gửi app iPhone lên xe dưới dạng video, nên với không dây có thể trễ hoặc kém nét hơn cắm dây, tuỳ đầu xe.

**5. Xe / đầu xe nào dùng được?**
OmniCar vẽ theo kích thước màn mà xe báo nên dùng cho mọi đầu xe CarPlay. Đầu xe đã thử ghi trên trang tương thích `<TODO: link>`; danh sách đang được bổ sung.

**6. Sao app hiện màn đen trên xe (Netflix, Disney+…)?**
App video có DRM chặn hình trên mọi màn ngoài, kể cả CarPlay. Có thể nghe tiếng nhưng hình đen. Đây là bảo vệ của app, OmniCar không tắt được.

**7. Còn cần CarBridge không?**
Không. App Bridge tự đưa app iPhone lên màn xe. Hãy tắt CarBridge và các tweak khác cũng sửa CarPlay: chạy chung có thể làm hỏng CarPlay. OmniCar cảnh báo khi thấy chúng nhưng không bao giờ tự gỡ tweak khác.

**8. CarPlay sập rồi một tính năng tự tắt, chuyện gì vậy?**
Đó là chế độ cứu. CarPlay sập 2 lần liền trong một phút sau khi cắm thì OmniCar tắt tính năng gây lỗi để CarPlay vẫn dùng được, và báo trên iPhone. Bật lại ở trang chính OmniCar (sau khi cập nhật), và gửi log giúp tác giả sửa lỗi.

**9. Gửi log thế nào?**
Cài đặt > OmniCar > Gửi log, chọn Zalo hoặc Mail. Ghi kèm tên đầu xe và việc bạn đang làm. File tạo trên máy và chỉ rời máy khi bạn chia sẻ (xem Chính sách riêng tư).

**10. Đổi cài đặt mà trên xe không thấy gì.**
Đa số thay đổi có hiệu lực ở lần cắm sau: rút ra cắm lại (hoặc tắt / bật CarPlay không dây). Lần đầu cài thì respring một lần.

**11. Bong bóng tốc độ không hiện gì.**
Bong bóng đọc tốc độ và biển giới hạn từ Vietmap Live hoặc GOFA. Chọn app đó làm nguồn trong cài đặt Bong bóng tốc độ và để app chạy (chạy nền cũng được).

**12. Gõ phím trong YouTube, Safari trên màn xe được không?**
Được: chạm vào ô nhập trong app iPhone (qua App Bridge), OmniCar hiện bàn phím riêng trên màn xe (tiếng Anh, hoặc tiếng Việt kiểu Telex). Chưa thử trên xe.

**13. Máy nóng hoặc màn xe bị khựng.**
Ba ô cùng chạy hoặc hai app video cùng lúc khá nặng. Chế độ nhẹ tự bật khi máy nóng hoặc CarPlay khựng: bỏ hiệu ứng kính mờ và giới hạn Chia màn hình còn 2 app.

**14. Có hoàn tiền không?**
TODO: chính sách hoàn tiền (thời hạn, cách yêu cầu, cần gì – ví dụ log cho thấy lỗi).

**15. OmniCar có thu thập dữ liệu không?**
Không. OmniCar không gửi gì cho tác giả. Kết nối mạng duy nhất là kiểu khởi động Thời tiết (tuỳ chọn, Open-Meteo, vị trí làm tròn khoảng 1 km). Xem chính sách riêng tư.
