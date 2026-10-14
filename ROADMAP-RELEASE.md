# OmniCar – Lộ trình phát hành

Mục tiêu: khai phá hết sức mạnh của CarPlay khi lái xe, vượt DuoDash, bán Pro qua Chariz cho người dùng
toàn cầu (không chỉ Việt Nam); bản miễn phí phát trên repo riêng.

Cách dùng file này
- Tuyến **Phát hành**: giới thiệu → miễn phí trên repo riêng → quyết định → miễn phí kèm dùng thử Pro + bán Pro → cập nhật.
- Tính năng làm theo **ROADMAP-DEV.md** (Mức 1–6); mỗi phát hành ghi mức nào phải xong trước.
- Mỗi mục là một ô `[ ]`. Làm xong thì đánh `[x]` và ghi ngày / phiên bản bên cạnh.
- **Độ khó**: Thấp (vài ngày) · Vừa (1–2 tuần) · Cao (vài tuần).

---

## Phát hành 0 – Chuẩn bị (làm song song Mức 1)

Kế hoạch: ra **repo riêng** cho dùng miễn phí một thời gian để đo phản ứng thị trường, rồi bán **Pro qua Chariz**.
Repo riêng chỉ phát gói miễn phí và dẫn link sang Chariz để mua; không tự thu tiền trên repo riêng.
Mức 1 xong thì mở repo miễn phí; Mức 2 xong phần lớn thì bán Pro.

- [ ] **Tên gói và định danh** · Thấp
  OmniCar (miễn phí, có dùng thử Pro) và OmniCar Pro (gói mở khoá trả phí). Chốt bundle id trước khi mở repo để
  người dùng thời kỳ miễn phí lên bản chính thức không mất cài đặt.
- [ ] **Repo riêng** · Thấp
  `repo.<tên miền>` (APT repo cho Sileo / Zebra): Release ký, ảnh bìa, trang mô tả (depiction) kiểu Sileo cho từng gói,
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
- [ ] **Bộ tài liệu bán hàng** · Thấp
  Video 60 giây, 6 ảnh chụp màn xe, mô tả ngắn / dài cho repo riêng và Chariz, FAQ, chính sách riêng tư.
  Code: docs/sales/ (mô tả ngắn / dài, FAQ, riêng tư, kịch bản quay shotlist.md). Còn thiếu: quay video, chụp ảnh,
  giá / chính sách hoàn tiền (TODO trong file).
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

- [ ] **Bản quyền, Lite / Pro và dùng thử** · Vừa
  Nền tảng kỹ thuật cho Phát hành 3 và 4: cờ Pro dùng chung cho mọi tính năng, đếm ngày dùng thử, đọc khoá của gói Pro.
  Làm trước các mục bên dưới (dùng thử, đếm ngược, hết hạn mềm, giới hạn Lite / Pro dựa vào nó).
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
  Phần còn lại của Mức 2: chế độ lái, nút vô lăng, hồ sơ theo xe.
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
