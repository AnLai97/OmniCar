# OmniCar – Lộ trình

Mục tiêu: khai phá hết sức mạnh của CarPlay khi lái xe, vượt DuoDash, bán Pro qua Chariz cho người dùng
toàn cầu (không chỉ Việt Nam); bản miễn phí phát trên repo riêng.

Cách dùng file này
- Hai tuyến: **Phát hành** (giới thiệu → miễn phí trên repo riêng → quyết định → miễn phí kèm dùng thử Pro + bán Pro → cập nhật) và **Mức tính năng**.
- Mức tính năng xếp theo **ưu tiên**: Mức 1 là thứ phải có ngay, mức sau làm khi mức trước đã xong.
- Mỗi mức chia thành **nhóm** theo tính năng. Trong mỗi nhóm, mục xếp **từ dễ đến khó** (Thấp → Vừa → Cao);
  mục nào phụ thuộc mục khác thì đứng sau nó.
- Mỗi mục là một ô `[ ]`. Làm xong thì đánh `[x]` và ghi phiên bản phát hành bên cạnh.
- **Độ khó**: Thấp (vài ngày) · Vừa (1–2 tuần) · Cao (vài tuần, cần thử nghiệm nhiều trên xe).
- **Xong khi**: tiêu chí kiểm tra được trên xe thật, không phải "code đã viết".
- Sửa xong file này thì chạy `python tools/roadmap_html.py` để cập nhật ROADMAP.html.

Đã có (1.0.0): Chia màn hình 2–3 ô (4 bố cục, chia dọc, kéo tỉ lệ, yêu thích, gần đây, Siri URL), App Bridge
(app iPhone lên xe, icon trên màn chính CarPlay), Bong bóng tốc độ (18 kiểu, Vietmap Live / GOFA), Màn hình
khởi động (một video MP4), Cài đặt vi / en.

---

## Phát hành 0 – Chuẩn bị (làm song song Mức 1)

Kế hoạch: ra **repo riêng** cho dùng miễn phí một thời gian để đo phản ứng thị trường, rồi bán **Pro qua Chariz**.
Repo riêng chỉ phát gói miễn phí và dẫn link sang Chariz để mua; không tự thu tiền trên repo riêng.
Mức 1 xong thì mở repo miễn phí; Mức 2 xong phần lớn thì bán Pro.

- [ ] **Tên gói và định danh** · Thấp
  OmniCar (miễn phí, có dùng thử Pro) và OmniCar Pro (gói mở khoá trả phí). Chốt bundle id trước khi mở repo để
  người dùng thời kỳ miễn phí lên bản chính thức không mất cài đặt.
- [ ] **Repo riêng** · Thấp
  repo.<tên miền> (APT repo cho Sileo / Zebra): Release ký, ảnh bìa, trang mô tả (depiction) kiểu Sileo cho từng gói,
  nhánh beta tách khỏi nhánh chính. Đặt sau Cloudflare / máy chủ có log để đếm lượt tải.
  Xong khi: thêm repo trên Sileo và Zebra, cài / cập nhật / gỡ OmniCar chạy đúng trên rootless và roothide.
- [ ] **Trang giới thiệu một trang** · Thấp
  Video, ảnh màn xe, so sánh Lite / Pro, trang tương thích, FAQ, nút "Thêm repo", liên hệ hỗ trợ.
- [ ] **Bộ nhận diện** · Thấp
  Logo (đã có), ảnh bìa repo, mẫu ảnh chụp màn xe, mẫu thumbnail video; giữ đúng DESIGN.md.
- [ ] **Kênh cộng đồng** · Thấp
  Discord (quốc tế) + nhóm Facebook / Zalo (Việt Nam) + tài khoản X; một kênh hỗ trợ chính ghi trong Cài đặt.
- [ ] **Chính sách riêng tư và điều khoản** · Thấp
  Nói rõ: dữ liệu nào được gửi (chỉ khi người dùng đồng ý), quyền camera / vị trí dùng làm gì, chính sách hoàn tiền.
- [ ] **Hỏi trước quy định của Chariz** · Thấp
  Gói đã phát miễn phí trên repo riêng có được bán Pro trên Chariz sau đó không; gói OmniCar miễn phí để trên repo
  riêng còn gói mở khoá Pro trên Chariz có được duyệt không; dẫn link mua từ repo riêng sang Chariz có được không.
  Hỏi thêm Havoc nếu muốn bán cả ở đó. Có câu trả lời bằng văn bản trước khi mở repo.

## Phát hành 1 – Giới thiệu (teaser)

Mục tiêu: có người chờ trước khi mở repo. Chưa phát hành gì, chỉ cho xem.

- [ ] **Video demo 60 giây** · Thấp
  Quay trên xe thật: chia 3 ô, app iPhone trên xe, bong bóng tốc độ, màn hình khởi động. Không quay cảnh xem video khi xe chạy.
- [ ] **Bài [Upcoming] trên r/jailbreak** · Thấp
  Video + danh sách tính năng + ngày mở repo + link đăng ký nhận tin.
- [ ] **Đăng ký nhận tin** · Thấp
  Form: iOS, máy, jailbreak, hãng / đời xe, dây hay không dây. Dùng để biết thị trường gồm những ai, xe gì.
- [ ] **Bộ tài liệu báo chí** · Thấp
  Ảnh, video, mô tả ngắn, thông tin liên hệ; gửi iDownloadBlog, iDeviceCentral, các kênh YouTube về jailbreak.
  Xong khi: có ít nhất 300 người đăng ký.

## Phát hành 2 – Miễn phí trên repo riêng (đo phản ứng thị trường)

Mục tiêu: nhiều người dùng thật trên nhiều đầu xe, biết họ thích gì, gặp lỗi gì, sẵn sàng trả bao nhiêu.
Đủ tính năng Pro, miễn phí trong thời gian có hạn (đề xuất 6–8 tuần), ghi rõ ngày kết thúc ngay trên trang repo.

- [ ] **Bản miễn phí có ngày kết thúc** · Thấp
  Đủ tính năng, hết ngày X thì tự chuyển sang Lite + 7 ngày dùng thử Pro như bản chính thức (không tắt hẳn).
  Thẻ đầu trang Cài đặt ghi "Miễn phí đến ngày X", có nút "Gửi log" và "Góp ý" nổi bật.
- [ ] **Đo lượt dùng (chỉ khi đồng ý)** · Vừa
  Lần đầu mở Cài đặt hỏi: "Gửi thống kê ẩn danh để giúp OmniCar?". Đồng ý thì mỗi ngày gửi một gói nhỏ: phiên bản,
  iOS, độ phân giải màn xe, tính năng nào đang bật. Không vị trí, không tên app, không định danh máy.
  Không đồng ý thì không gửi gì; vẫn có lượt tải từ log repo.
- [ ] **Thu thập tương thích** · Vừa
  Form trong Cài đặt: xe, đầu xe, iOS, cái gì chạy / không chạy. Gộp thành trang tương thích công khai.
- [ ] **Khảo sát giá và tính năng** · Thấp
  Sau 2 tuần dùng hiện một lần: tính năng dùng nhiều nhất, thiếu gì, sẵn sàng trả bao nhiêu (4 mức giá).
- [ ] **Sửa lỗi theo mức độ** · Vừa
  Ưu tiên: làm sập CarPlay > mất cài đặt > sai giao diện > ý kiến tính năng. Cập nhật qua repo ít nhất mỗi tuần.
- [ ] **Quà cho người dùng sớm** · Thấp
  Ai dùng trong thời kỳ miễn phí và gửi góp ý / log được mã giảm giá Pro (hoặc Pro miễn phí cho người đóng góp nhiều).

## Điểm quyết định – Bán Pro hay chưa

Cuối thời kỳ miễn phí, xem số liệu rồi mới quyết định. Chưa đạt thì kéo dài miễn phí, sửa tiếp, hoặc đổi hướng tính năng.

- [ ] **Tổng hợp số liệu** · Thấp
  Lượt tải, số máy đang dùng (từ thống kê đồng ý), số đầu xe đã thử, lỗi còn mở, kết quả khảo sát giá, tính năng dùng nhiều nhất.
- [ ] **Tiêu chí đi tiếp** · Thấp
  Đề xuất: ≥ 2.000 lượt tải, ≥ 30 đầu xe khác nhau, 2 tuần không có lỗi làm sập CarPlay, ≥ 20 % người trả lời khảo sát
  sẵn sàng trả từ mức giá dự kiến. Chỉnh lại con số trước khi mở repo, không chỉnh sau khi đã có số liệu.
- [ ] **Chốt giá và bảng Lite / Pro** · Thấp
  Dựa trên khảo sát và tính năng dùng nhiều nhất: tính năng được dùng nhiều nhất nên nằm trong Pro, nhưng Lite vẫn
  phải dùng được.

## Phát hành 3 – Chính thức: OmniCar miễn phí, dùng thử đủ Pro

Mục tiêu: người dùng thấy **hết** OmniCar làm được gì trên chính xe của họ, rồi mới quyết định mua.
Một gói OmniCar miễn phí chứa toàn bộ mã; mới cài là chạy đủ Pro trong thời gian thử, hết hạn thì về Lite.

- [ ] **Dùng thử đủ Pro 7 ngày lái xe** · Vừa
  Đếm theo **ngày có cắm CarPlay**, không phải ngày lịch: cài xong để đó không mất lượt thử. Đủ mọi tính năng Pro.
  Xong khi: cài mới, cắm xe 7 ngày khác nhau → ngày thứ 8 về Lite; không cắm xe thì không bị trừ ngày.
- [ ] **Đếm ngược rõ ràng, nhắc nhẹ** · Thấp
  Thẻ đầu trang Cài đặt hiện "Dùng thử Pro · còn 5 ngày". Nhắc một lần trên iPhone khi còn 2 ngày và khi hết hạn.
  Không bao giờ hiện nhắc nhở trên màn xe khi đang lái.
- [ ] **Hết hạn mềm** · Thấp
  Về Lite nhưng giữ nguyên mọi cài đặt Pro (bố cục, hình nền, kiểu khởi động); mua Pro là có lại ngay, không phải cài lại.
  Tính năng Pro đang dùng tự đổi về bản Lite tương ứng (3 ô → 2 ô 50/50…), không để màn xe trống hay lỗi.
- [ ] **Chống thử lại vô hạn** · Vừa
  Lưu trạng thái thử theo máy (băm định danh máy, lưu ở chỗ còn lại sau khi gỡ / cài lại tweak). Không gửi đi đâu.
- [ ] **Xem thử không cần xe** · Vừa
  Trang trong Cài đặt mô phỏng màn xe (như tools/preview): bấm thử chia màn, bong bóng tốc độ, kiểu khởi động
  ngay trên iPhone, cho người chưa ra xe hoặc đang xem trước khi cài.
- [ ] **Giới hạn tính năng theo bảng Lite / Pro** · Vừa
  Khoá tính năng Pro sau khi hết thử. Cài đặt của Lite gọn: chỉ các mục Lite, cuối trang khối "Có trong Pro"
  liệt kê ngắn (xem thử được, không bấm dùng được).
- [ ] **Nút "Nâng cấp lên Pro"** · Thấp
  Một dòng trong Cài đặt và trên mục Pro bị khoá, mở trang mua Pro trên Chariz. Không hiện quảng cáo trên màn xe.
- [ ] **Phát hành OmniCar miễn phí trên repo riêng (và Chariz)** · Thấp
  Mô tả ghi rõ: "Miễn phí, dùng thử đủ Pro 7 ngày lái xe", bảng so sánh Lite / Pro, link trang tương thích.
  Xong khi: 1.000 lượt cài, đánh giá trung bình ≥ 4 sao, ít nhất 5 % người thử mua Pro.

## Phát hành 4 – OmniCar Pro (trả phí)

- [ ] **Gói mở khoá Pro trên Chariz** · Vừa
  "OmniCar Pro" là gói trả phí nhỏ trên Chariz, chỉ chứa khoá bản quyền kiểm tra bằng DRM của Chariz; OmniCar miễn
  phí (cài từ repo riêng hoặc Chariz) thấy khoá hợp lệ thì mở đủ Pro. Mua xong không phải gỡ / cài lại gì.
  Xong khi: mua trên Chariz, Pro mở trong 1 phút; đăng nhập Chariz trên máy mới là khôi phục được Pro.
- [ ] **Repo riêng dẫn sang Chariz** · Thấp
  Trang mô tả OmniCar trên repo riêng và trang giới thiệu có nút "Mua Pro trên Chariz"; ghi rõ repo riêng không bán gì.
- [ ] **Bán thêm trên Havoc (tuỳ chọn)** · Vừa
  Chỉ khi Havoc chấp nhận và không đòi bán độc quyền; khoá phải nhận cả DRM của Havoc, cùng giá với Chariz.
- [ ] **Giá và khuyến mãi ra mắt** · Thấp
  Đề xuất 7,99–9,99 USD (DuoDash 12,99 USD), chốt lại theo khảo sát; giảm 30 % tuần đầu; người dùng thời kỳ miễn phí có mã giảm thêm;
  giảm thêm trong 48 giờ sau khi hết dùng thử.
- [ ] **Phát hành Pro trên Chariz** · Thấp
  Mô tả nói rõ những gì có trong Pro và những gì không làm được (DRM), link trang tương thích.
- [ ] **Hỗ trợ sau bán** · Thấp
  Mẫu trả lời cho lỗi thường gặp, cam kết phản hồi trong 48 giờ, quy trình hoàn tiền.
  Xong khi: tỉ lệ hoàn tiền dưới 3 % trong tháng đầu.

## Phát hành 5 – Cập nhật và tăng trưởng

Mỗi bản lớn đi kèm một video ngắn và một bài đăng; bản nhỏ sửa lỗi phát hành khi cần.

- [ ] **1.1 – Màn chính và Khởi động** · Vừa
  Phần Màn chính CarPlay và Màn hình khởi động mới của Mức 2.
- [ ] **1.2 – Chia màn hình và Lái xe** · Vừa
  Phần còn lại của Mức 2: 8 bố cục, chế độ lái, nút vô lăng, hồ sơ theo xe.
- [ ] **2.0 – Vượt DuoDash** · Cao
  Mức 3: bố cục tự do, tự phóng to bản đồ khi rẽ, ô tiện ích, cụm đồng hồ, widget màn chính.
- [ ] **Gói thêm "OmniCar Drive" (camera / ADAS)** · Cao
  Mức 4 bán riêng hoặc là gói nâng cấp, vì tốn nhiều công và chỉ dành cho người muốn dùng camera. Pro không bị mất tính năng đã có.
- [ ] **Chương trình giới thiệu** · Thấp
  Mã giới thiệu cho người dùng / YouTuber; giảm giá theo mùa (Black Friday, Tết).

## Bảng Lite và Pro

Áp dụng sau khi hết 7 ngày dùng thử. Nguyên tắc: Lite chỉ có tính năng đơn giản, đủ để người dùng thấy OmniCar làm được gì và muốn lên Pro; không
có tuỳ chỉnh, không có tính năng nâng cao. Pro là toàn bộ sức mạnh. Bản sửa lỗi có cho cả hai.

- **Chia màn hình**: Lite 2 ô 50/50 cố định, chọn app cho 2 ô · Pro kéo đổi tỉ lệ, 3 ô, đủ bố cục, yêu thích, gần đây, bố cục tự do, tự phóng to bản đồ, hồ sơ theo xe.
- **App iPhone trên xe (App Bridge)**: Lite 1 app iPhone, chỉ mở toàn màn · Pro không giới hạn, app iPhone vào ô chia màn.
- **Màn chính CarPlay**: Lite không có · Pro ẩn / sắp xếp app, cỡ icon, cột / hàng, dock, hình nền, gói icon, thư mục, widget.
- **Màn hình khởi động**: Lite 1 video của bạn, không tuỳ chỉnh · Pro mọi kiểu (logo + âm thanh, lời chào, thời tiết, theo dịp, ngẫu nhiên, hiệu ứng, chia sẻ mẫu).
- **Bong bóng tốc độ**: Lite 1 kiểu, 1 nguồn, cỡ mặc định · Pro đủ kiểu, mọi nguồn, chỉnh cỡ / vị trí, cảnh báo quá tốc độ tuỳ chỉnh.
- **Lái xe an toàn**: Lite chế độ lái + cảnh báo quá tốc độ cơ bản (an toàn không khoá sau tiền; Lite chạy được video qua App Bridge nên bắt buộc có chế độ lái) · Pro nhắc nghỉ, nhật ký và điểm lái, HUD, giữ tốc độ trong hầm, nút vô lăng, lệnh giọng nói.
- **Cài đặt**: Lite đủ ngôn ngữ, không sao lưu, không Phím tắt Siri · Pro sao lưu / khôi phục, Phím tắt Siri, hồ sơ theo xe.
- **Hỗ trợ**: Lite qua cộng đồng · Pro hỗ trợ trực tiếp, ưu tiên sửa lỗi theo đầu xe.
- **Camera / ADAS**: không có trong Lite · gói thêm "OmniCar Drive".

---

## Mức 1 – Cần ngay (trước khi mở repo miễn phí)

Thiếu một trong các mục này thì khách quốc tế không mua, hoặc mua rồi đòi hoàn tiền.

### Hỗ trợ và ổn định

- [ ] **Gửi log một chạm** · Thấp
  Nút trong Cài đặt: gói OmniCar.log + phiên bản iOS, máy, đầu xe, danh sách tweak → share sheet.
  Xong khi: khách gửi được file qua Zalo / email trong 3 chạm.
  Code: Hỗ trợ > Gửi log (OMCShareReport) → OmniCar-log-<ngày>.txt. Chờ thử gửi Zalo trên máy.
- [ ] **Màn chẩn đoán** · Thấp
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
- [ ] **Thông tin đầu xe** · Thấp
  Độ phân giải, tỉ lệ màn, chất lượng video gợi ý (gộp vào Màn chẩn đoán).
  Code: CarPlay ghi màn xe + phiên CarKit mỗi lần cắm (OMCCrashGuard), Chẩn đoán > Màn xe. Chờ thử trên xe.
- [ ] **Phát hiện tweak xung đột** · Thấp
  Thấy CarBridge, DuoDash, TrueDash, CarPlayEnable… đang bật → cảnh báo trong Cài đặt (không tự gỡ tweak của người khác).
  Code: thẻ cảnh báo đầu trang chính khi dylib của tweak đó đang nạp; Chẩn đoán liệt kê cả gói đã cài.
- [ ] **Chế độ cứu (rescue)** · Vừa
  CarPlay sập 2 lần liền trong 60 giây sau khi cắm → tự tắt tính năng nghi gây lỗi, lần cắm sau báo cho người dùng.
  Xong khi: cố tình gây crash trong một tính năng, CarPlay tự phục hồi ở lần cắm thứ 3.
  Code: OMCCrashGuard (Core) nghi tính năng theo backtrace, thông báo trên iPhone, thẻ "Bật lại" ở trang chính.
  Thử: Chẩn đoán, nhấn giữ dòng OmniCar → chọn tính năng → cắm xe 3 lần.
- [ ] **Tự kiểm tra trên xe (chỉ bản dev)** · Vừa
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
- [ ] **Thử với nhiều app hơn** · Vừa
  Danh sách tối thiểu: YouTube, TikTok, Facebook, Instagram, Chrome, Safari, Zalo, Grab, Shopee, X, Twitch, Plex.
  Xong khi: có bảng app chạy tốt / chạy được / không chạy kèm lý do, đưa lên trang tương thích.
  Bảng ghi kết quả: COMPATIBILITY.md.
- [ ] **Chạy thật trên iOS 15 16 17 và 18** · Cao
  App Bridge và Chia màn hình đang dựa selector iOS 16. Kiểm tra từng selector, có đường dự phòng khi thiếu.
  Kiểm tra lại luôn app có giao diện CarPlay riêng chạy trong ô.
  Xong khi: thử đủ 4 bố cục + YouTube / TikTok qua App Bridge trên iOS 15, 16, 17, 18 (rootless), ghi kết quả.
  Chẩn đoán hiện hook thiếu trên từng iOS; ghi kết quả vào COMPATIBILITY.md.

### Bán quốc tế

- [ ] **Đơn vị và quy chuẩn theo nước** · Thấp
  km/h ↔ mph; biển tốc độ kiểu Viên (tròn viền đỏ) / kiểu Mỹ (chữ nhật trắng); lái tay phải → đảo bố cục mặc định.
- [ ] **Hướng dẫn lần đầu** · Thấp
  3–4 trang: chọn app lên xe, chọn bố cục đầu tiên, bật bong bóng tốc độ, cách gọi bảng bố cục trên xe.
- [ ] **Nhiều ngôn ngữ** · Thấp (dịch) / Vừa (kiểm tra)
  Tối thiểu: en, vi, es, pt-BR, de, fr, it, ru, zh-Hans, ja, ko, ar (RTL), th, id.
  Xong khi: mọi trang Cài đặt và chữ trên xe không bị cắt ở ngôn ngữ dài nhất (de) và RTL (ar).
- [ ] **Trang tương thích công khai** · Thấp
  iOS, kiểu jailbreak (rootless / roothide), chip, đầu xe đã thử, app đã thử, giới hạn đã biết (DRM).
- [ ] **Bộ tài liệu bán hàng** · Thấp
  Video 60 giây, 6 ảnh chụp màn xe, mô tả ngắn / dài cho repo riêng và Chariz, FAQ, chính sách riêng tư.
- [ ] **Bản quyền, Lite / Pro và dùng thử** · Vừa
  Nền tảng kỹ thuật cho Phát hành 3 và 4: cờ Pro dùng chung cho mọi tính năng, đếm ngày dùng thử, đọc khoá của gói Pro.

### Dùng hằng ngày

- [ ] **Phóng to tạm một ô** · Thấp
  Chạm đúp thanh "•••" → ô to toàn vùng app, chạm lại → về bố cục cũ (khác "toàn màn" là không đóng các ô khác).
- [ ] **Bàn phím trên màn xe** · Cao
  Một bàn phím chung cho mọi ô (kể cả app iPhone qua App Bridge), kiểu HarmonyOS, có tiếng Việt và các ngôn ngữ chính.
  Xong khi: gõ được tìm kiếm trong YouTube và ô địa chỉ của Safari trên xe.

## Mức 2 – Quan trọng (bằng DuoDash, làm ngay sau bản bán đầu tiên)

Khách so sánh trực tiếp với DuoDash / CarBridge ở các mục này, và đây là những thứ khách nhìn thấy mỗi lần cắm xe.

### Màn chính CarPlay (nâng cấp từ App Bridge)

Trang Cài đặt "App trên màn xe" mở rộng thành "Màn chính CarPlay": app, bố cục, hình nền, dock.
Mỗi thay đổi có xem trước trong Cài đặt (mô phỏng màn xe) trước khi áp lên xe.

- [ ] **Ẩn và sắp xếp app** · Vừa
  Ẩn cả app CarPlay gốc không dùng (CarBridge có), kéo đổi thứ tự app iPhone và app CarPlay trong một danh sách.
  Xong khi: thứ tự và app ẩn giữ nguyên sau khi rút / cắm lại và sau respring.
- [ ] **Cỡ icon** · Vừa
  Thanh trượt cỡ icon trên màn chính (ví dụ 80–130 %), lưới tự tính lại để không tràn màn.
- [ ] **Số cột / hàng và tên app** · Vừa
  Chọn số cột × hàng mỗi trang, ẩn / hiện tên dưới icon, khoảng cách icon.
- [ ] **Hình nền màn chính** · Vừa
  Chọn ảnh từ Ảnh / Tệp, cắt theo tỉ lệ màn xe, chỉnh độ mờ và độ tối để icon vẫn dễ nhìn.
- [ ] **Dock tuỳ chỉnh** · Vừa
  Chọn app nào nằm cố định trên dock (kể cả app iPhone), ẩn mục gợi ý của CarPlay.

### Màn hình khởi động mới

Đổi từ "một video" sang nhiều **kiểu khởi động**. Mỗi kiểu là một mẫu có tham số; người dùng chọn kiểu,
xem trước ngay trong Cài đặt. Âm thanh phát qua loa xe khi CarPlay kết nối.

- [ ] **Khung chọn kiểu khởi động** · Vừa
  Trang Cài đặt mới: danh sách kiểu (Video, Logo + âm thanh, Lời chào, Thời tiết…), xem trước, thời lượng, chạm để bỏ qua.
  Video MP4 hiện tại thành một kiểu trong danh sách, cài đặt cũ được giữ.
- [ ] **Logo + âm thanh của bạn** · Thấp (sau khi có khung)
  Chọn ảnh logo (PNG trong suốt) + âm thanh; vài hiệu ứng xuất hiện: hiện dần, phóng to, phát sáng.
- [ ] **Âm thanh khởi động riêng** · Thấp
  Gắn âm thanh vào bất kỳ kiểu nào (tiếng máy nổ, chuông, lời chào ghi âm), chỉnh âm lượng, tắt khi đang có cuộc gọi.
- [ ] **Lời chào theo giờ** · Thấp
  "Chào buổi sáng, An" + giờ, ngày; chữ và nền đổi theo sáng / chiều / tối.
- [ ] **Thời tiết và nhiệt độ** · Vừa
  Nhiệt độ hiện tại, cao / thấp trong ngày, khả năng mưa, biểu tượng thời tiết; lấy từ WeatherKit / dữ liệu Thời tiết của iOS, không có mạng thì dùng số đo gần nhất.

### Chia màn hình

- [ ] **Ghim ô bản đồ** · Thấp
  Ô được ghim không bị thay khi chọn bố cục / app khác.
- [ ] **Nhớ tỉ lệ theo cặp app** · Thấp
  Maps + Nhạc = 70/30, Maps + YouTube = 50/50… tự áp lại.
- [ ] **Hồ sơ theo từng xe** · Thấp
  Nhận xe qua tên / ID đầu xe → bố cục chia màn, màn chính CarPlay, kiểu khởi động, cỡ bong bóng riêng cho từng xe.
- [ ] **Đủ 8 bố cục trở lên** · Vừa
  Thêm 70/30, 30/70, 3 cột đều, 1 lớn trên + 2 dưới (màn dọc), lưới 2×2 (màn siêu rộng).
- [ ] **Chọn ô phát tiếng** · Vừa
  Hai ô cùng có âm thanh → chọn ô nào phát, ô kia tắt tiếng; tự giảm nhạc khi bản đồ đọc hướng dẫn.
- [ ] **Gán nút giọng nói trên vô lăng** · Vừa
  Bấm giữ = Siri như cũ; bấm ngắn = mở bảng bố cục / một app / một lệnh OmniCar, người dùng chọn.

### Lái xe

- [ ] **Cảnh báo quá tốc độ** · Thấp
  Vượt biển + ngưỡng tuỳ chọn → viền màn đổi màu, tiếng ngắn; có chế độ im lặng.
- [ ] **Chế độ lái** · Vừa
  Trên tốc độ đặt trước: ô video chỉ còn tiếng / mờ đi, chữ và nút to hơn, khoá thao tác nhỏ; dừng xe → trở lại.
  Đây cũng là câu trả lời khi repo / người mua hỏi về an toàn.
- [ ] **Nguồn tốc độ toàn cầu** · Vừa
  Thêm Google Maps, Waze, Apple Maps; dự phòng bằng giới hạn tốc độ OpenStreetMap tải sẵn theo vùng.

### Cài đặt và hiệu năng

- [ ] **Sao lưu / khôi phục cài đặt** · Thấp
  Xuất một file `.omnicar`, mở file là nạp lại (bố cục, màn chính, kiểu khởi động, kiểu bong bóng, ảnh / video / âm thanh đã chọn).
- [ ] **Có gì mới** · Thấp
  Sau mỗi bản cập nhật hiện một trang ngắn trong Cài đặt.
- [ ] **Tinh chỉnh hiệu năng** · Vừa
  Giới hạn FPS app iPhone, tự giảm khi máy nóng, giữ app trong bộ nhớ hay không, giữ kết nối CarPlay khi khoá máy.
- [ ] **Tối ưu CarPlay không dây** · Vừa
  Tự giảm chất lượng / FPS app iPhone khi kết nối không dây chập chờn.
- [ ] **Phím tắt Siri đầy đủ** · Vừa
  Hành động cho app Phím tắt: mở bố cục, đặt app vào ô, đổi tỉ lệ, đổi hình nền / kiểu khởi động, bật / tắt từng tính năng.

## Mức 3 – Vượt DuoDash (tạo khác biệt khi lái xe)

Những thứ DuoDash không có. Đây là nội dung chính cho video quảng cáo các bản cập nhật lớn.

### Màn chính CarPlay

- [ ] **Hình nền theo giờ** · Thấp
  Hai ảnh ngày / đêm, tự đổi theo giờ mặt trời mọc / lặn hoặc theo chế độ sáng / tối của xe.
- [ ] **Hình nền động** · Vừa
  Video ngắn lặp hoặc ảnh động làm nền, tự dừng khi máy nóng hoặc khi đang chia màn.
- [ ] **Hình dạng và gói icon** · Vừa
  Bo tròn / vuông / tròn hẳn, viền kính, bóng; dùng gói icon có sẵn trên máy (theo chuẩn IconBundles) cho màn xe.
- [ ] **Thư mục và trang riêng** · Vừa
  Gom app vào thư mục trên màn chính CarPlay; một trang riêng cho app iPhone (App Bridge).
- [ ] **Widget trên màn chính** · Vừa
  Đặt đồng hồ, thời tiết, nhạc đang phát… thành ô lớn ngay trên màn chính CarPlay (dùng chung phần Ô tiện ích).

### Màn hình khởi động

- [ ] **Theo dịp đặc biệt** · Thấp
  Sinh nhật, Tết, Giáng sinh, ngày kỷ niệm → kiểu khởi động riêng hôm đó (người dùng đặt ngày).
- [ ] **Ngẫu nhiên / xoay vòng** · Thấp
  Mỗi lần cắm xe chọn ngẫu nhiên hoặc lần lượt trong các kiểu đã đánh dấu.
- [ ] **Logo hãng xe kiểu mẫu** · Thấp
  Mẫu dựng sẵn cho logo + âm thanh kiểu xe sang (nền tối, quét sáng, âm "chime"); **người dùng tự nhập logo hãng**,
  OmniCar không đóng gói sẵn logo / âm thanh của hãng xe (bản quyền thương hiệu).
- [ ] **Hiệu ứng logo nâng cao** · Vừa
  Quét sáng qua logo, ghép từng mảnh, chữ hiện từng ký tự, hạt sáng; chỉnh màu và tốc độ.
- [ ] **Thông tin chuyến đi** · Vừa
  Lịch hôm nay, giờ đến nơi làm việc dự kiến, quãng đường hôm qua, pin điện thoại (và pin xe khi có OBD2 / VinFast).
- [ ] **Chia sẻ mẫu khởi động** · Vừa
  Xuất kiểu khởi động thành một file (ảnh + âm thanh + tham số) để gửi cho người khác, mở là cài.

### Chia màn hình

- [ ] **Thanh nhạc chung** · Thấp
  Luôn hiện, điều khiển app nào đang phát (kể cả qua App Bridge).
- [ ] **Tự phóng to ô bản đồ khi sắp rẽ** · Vừa
  Còn ~300 m tới chỗ rẽ → ô bản đồ to ra (có hiệu ứng), qua chỗ rẽ → trả bố cục cũ. Ngưỡng chỉnh được.
- [ ] **Bố cục tự do** · Vừa
  Kéo vạch để tự tạo bố cục tới 4 ô, lưu thành mẫu, chia sẻ bằng mã ngắn (mã chứa bố cục, không chứa dữ liệu cá nhân).
- [ ] **Tự động theo ngữ cảnh** · Vừa
  Quy tắc: giờ, ngày trong tuần, xe, vị trí, có lịch hẹn → mở bố cục tương ứng khi cắm.
- [ ] **Ô tiện ích** · Vừa
  Đồng hồ, thời tiết, lịch hôm nay, nhạc đang phát, pin điện thoại, nhiệt độ máy, la bàn, độ cao.
- [ ] **Cụm đồng hồ kiểu xe thể thao** · Vừa
  Bố cục dạng đồng hồ: tốc độ, bản đồ thu nhỏ, nhạc; thêm dữ liệu OBD2 khi có (Mức 5).
- [ ] **Kéo icon thả vào ô** · Vừa
  Từ dock / màn chính CarPlay kéo icon vào ô muốn mở.
- [ ] **Cửa sổ nổi hoàn chỉnh** · Vừa
  Thu một app thành ô nhỏ nổi ở góc (kiểu hình trong hình), kéo đi, chạm để mở lại.
- [ ] **Cử chỉ lớn khi đang chạy** · Vừa
  Vuốt 3 ngón trái / phải đổi chỗ ô, chụm về màn chính; khi xe chạy chỉ nhận cử chỉ lớn.

### Lái xe

- [ ] **Nhắc nghỉ** · Thấp
  Lái liên tục 2 giờ (chỉnh được) → nhắc nghỉ, gợi ý trạm dừng gần nhất.
- [ ] **Nhớ chỗ đỗ xe** · Thấp
  Rút CarPlay → lưu vị trí (+ ảnh nếu có camera), chỉ đường đi bộ quay lại.
- [ ] **Nhắc kiểm tra ghế sau** · Thấp
  Rút CarPlay khi trời nóng (thời tiết) → thông báo trên iPhone.
- [ ] **HUD bằng chính iPhone** · Thấp
  Màn iPhone hiện tốc độ + hướng rẽ tiếp theo, lật gương, đặt dưới kính lái.
- [ ] **Hướng dẫn làn đường cỡ lớn** · Vừa
  Mũi tên làn to ở mép màn, kể cả khi bản đồ ở ô nhỏ.
- [ ] **Giữ tốc độ trong hầm** · Vừa
  Mất GPS → ước lượng tiếp bằng gia tốc kế + tốc độ trước đó, bong bóng không đứng số.
- [ ] **Nút vô lăng làm phím tắt** · Vừa
  Bấm đúp "bài tiếp" = đổi ô đang chọn, giữ = mở bảng bố cục.
- [ ] **Điểm lái an toàn và nhật ký chuyến đi** · Vừa
  Quãng đường, thời gian, phanh gấp, tăng tốc gắt, vào cua nhanh, số lần quá tốc độ; xem lại trong Cài đặt.
- [ ] **Lệnh giọng nói ngay trên máy** · Vừa
  Vài lệnh cố định không cần mạng: "lưu clip", "phóng to bản đồ", "tắt video", "bố cục đi làm".
- [ ] **Thông báo gọn** · Vừa
  Gom tin nhắn thành dải ngắn ở mép, Siri đọc khi chạm, trả lời bằng câu soạn sẵn; ẩn nội dung khi xe chạy.

### Giao diện

- [ ] **Màn chờ khi đỗ** · Thấp
  Đỗ lâu → đồng hồ lớn / ảnh, giống StandBy (dùng chung mẫu với Màn hình khởi động).
- [ ] **Hiệu ứng chuyển cảnh HarmonyOS** · Thấp
  Mở ô, đổi app, đổi bố cục mượt theo DESIGN.md.
- [ ] **Chủ đề giao diện** · Thấp
  Màu nhấn, độ trong kính, kiểu thanh nút; chủ đề theo hãng xe.
- [ ] **Hỗ trợ núm xoay (đầu xe không cảm ứng)** · Cao
  Điều khiển bảng bố cục và chọn ô bằng núm / nút; DuoDash không có.

## Mức 4 – Camera hành trình và hỗ trợ lái (ADAS)

Điện thoại trên giá, camera sau nhìn ra đường. Xử lý bằng Vision / Core ML ngay trên máy, không gửi hình đi đâu.
Trước khi bắt đầu: đo pin và nhiệt khi chạy camera + CarPlay 1 giờ giữa trưa. Không đạt thì dừng mức này.
Thứ tự trong mức này theo phụ thuộc: phải có ghi vòng trước rồi mới có tự lưu.
Điều kiện chung: chấm xanh camera của iOS sẽ hiện, ghi rõ trong mô tả; mọi cảnh báo ghi "hỗ trợ, không thay người lái".

### Camera hành trình

- [ ] **Camera hành trình (ghi vòng)** · Vừa
  Ghi liên tục, chỉ giữ N phút gần nhất, giới hạn dung lượng.
- [ ] **Tự lưu khi có sự cố** · Thấp (sau khi có ghi vòng)
  Phanh gấp / va chạm → giữ đoạn trước + sau, kèm tốc độ, toạ độ, giờ trên hình.
- [ ] **Lưu bằng chạm / giọng nói, xem lại trên xe khi đỗ** · Thấp

### Hỗ trợ lái (ADAS)

- [ ] **Báo đèn xanh** · Vừa
  Đang dừng đèn đỏ, đèn chuyển xanh mà xe chưa đi → tiếng ngắn.
- [ ] **Báo xe trước đã chạy** · Vừa
- [ ] **Đọc biển tốc độ bằng camera** · Cao
  Nhận biển thật (kể cả biển tạm), đưa vào Bong bóng tốc độ, ưu tiên hơn dữ liệu bản đồ khi chắc chắn.
- [ ] **Khoảng cách tới xe trước** · Cao
  Hiện số giây bám đuôi, nhắc khi dưới 2 giây.
- [ ] **Cảnh báo va chạm phía trước** · Cao
- [ ] **Cảnh báo lệch làn** · Cao
- [ ] **Phát hiện buồn ngủ / nhìn điện thoại** · Cao
  Chế độ camera trước (máy hướng về người lái). Không chạy cùng lúc với các mục camera sau.

## Mức 5 – Mở rộng hệ sinh thái

Cần thử nghiệm dài và phần cứng / dữ liệu ngoài. Làm khi sản phẩm đã ổn định và có người dùng.

- [ ] **Báo tai nạn cho người thân** · Vừa
  Va chạm mạnh + không phản hồi trong 30 giây → gửi vị trí (và clip camera nếu có) cho liên hệ đã chọn.
  Ghi rõ: chỉ hỗ trợ, không thay tính năng phát hiện tai nạn của Apple.
- [ ] **API cho nhà phát triển** · Vừa
  Tweak khác / Phím tắt đặt nội dung vào ô tiện ích, widget màn chính, hoặc thêm kiểu khởi động mới. Có tài liệu và ví dụ mã nguồn mở.
- [ ] **Tốc độ khuyên dùng khi vào cua** · Cao
  Từ độ cong đường (dữ liệu bản đồ / OSM) nhắc giảm tốc trước cua gắt, nhất là đường đèo.
- [ ] **OBD2 Bluetooth LE** · Cao
  Tốc độ thật, vòng tua, nhiệt độ nước, nhiên liệu, điện áp ắc quy, mã lỗi (đọc / xoá). Thử với ELM327 phổ biến.

## Mức 6 – Gói theo vùng (bắt đầu với Việt Nam)

Làm song song khi có thời gian; mỗi gói chỉ phục vụ một thị trường.

- [ ] **Trạm thu phí ETC** · Thấp
  Báo sắp tới trạm, giá vé theo loại xe.
- [ ] **Giọng đọc tiếng Việt tự nhiên** cho mọi cảnh báo · Thấp
- [ ] **Cơ sở dữ liệu camera phạt nguội / trạm cân** · Vừa
  Cập nhật định kỳ, cảnh báo bằng giọng.
- [ ] **Pin xe điện VinFast** · Vừa (phụ thuộc dữ liệu có lấy được không)
- [ ] **Mẫu cho vùng khác** · Vừa
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
