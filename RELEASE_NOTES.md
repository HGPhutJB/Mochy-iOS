Mochy iOS 0.8.0 — tài khoản Mochy + đồng bộ

- Mục "Tài khoản Mochy" trong Cài đặt: đăng ký / đăng nhập bằng tên + mật khẩu (mật khẩu được băm trên máy chủ).
- Đồng bộ yêu thích, playlist, lịch sử nghe, cài đặt và danh sách bài đã tải giữa các máy; tự đồng bộ khi có thay đổi. Bài đã tải ở máy khác hiện trong playlist "Đã tải trên tài khoản" để tải lại.
- Máy chủ là Cloudflare Worker (thư mục server/), tự triển khai bằng GitHub Actions.

Mochy iOS 0.7.7 — ba chấm chờ lời mượt hơn, nền gradient chuyển động mạnh hơn

- Ba chấm: to hơn, sáng lần lượt theo thời gian tới dòng đầu, phồng nhẹ theo nhịp, co lại rồi tan khi lời bắt đầu (không còn bị nhấp nháy/giật).
- Nền gradient: các đốm màu quay nhanh và rộng hơn, thêm một màu thứ năm, màu bám sát bìa hơn (sáng và đậm hơn).

Mochy iOS 0.7.6 — sửa lịch sử nghe

- Lịch sử nghe không còn lặp một bài nhiều lần (bài nghe lại được đưa lên đầu).
- Bỏ tiêu đề bị lặp hai lần ở đầu trang danh sách bài.

Mochy iOS 0.7.5 — khôi phục dải mờ, tiêu đề mục không còn dính khi lướt

- Khôi phục dải mờ trong suốt ở đầu mọi màn hình (0.7.4 lỡ bỏ).
- Tiêu đề các mục ("Nhạc Việt mới"...) cuộn theo nội dung, không dính lại phía trên ở Trang chủ, Nghệ sĩ, Thư viện, Tìm kiếm.

Mochy iOS 0.7.4 — bỏ dải mờ dính ở đầu trang, nút qua bài bo tròn, ba chấm chờ lời

- Bỏ dải mờ dính ở đầu mọi màn hình khi lướt xuống.
- Hai nút qua bài/lùi bài bo tròn góc.
- Khi lời chưa tới: hiện ba chấm sáng dần như Apple Music.
- Thanh tab nổi theo đúng chế độ sáng/tối (0.7.3).

Mochy iOS 0.7.3 — sửa thanh tab bị tối ở chế độ sáng

- Thanh tab nổi giờ theo chế độ giao diện: chế độ sáng thì thanh sáng (trước đây đo nền thất bại nên luôn tối).

Mochy iOS 0.7.2 — trang nghệ sĩ mới, sửa album, gợi ý tìm kiếm

- Làm lại trang nghệ sĩ: ảnh lớn tràn đầu trang, tên + người nghe, nút Phát/Ngẫu nhiên, bài nổi bật (xem tất cả bài), các hàng ngang Album / Đĩa đơn & EP / Video / Nghệ sĩ tương tự, mỗi hàng có "Xem tất cả" mở lưới toàn bộ đĩa.
- Sửa trang album bị trống tên/ảnh bìa (YouTube Music đổi cấu trúc trang).
- Sửa trang playlist rỗng bị giật/đè chữ sau khi tạo playlist.
- Tìm kiếm có gợi ý khi gõ.
- Nền màu ở màn hình đang phát/lời: chuyển động nhiều hơn (6 đốm quay quanh quỹ đạo rộng) và bám sát màu bìa hơn.
- Trang chủ bỏ các hàng "Nghe gần đây", "Vì bạn nghe …".
- Tạm gỡ mục Tài khoản nhạc và Last.fm khỏi Cài đặt.
- Dải mờ trên cùng dùng lại hiệu ứng mờ hệ thống bỏ lớp phủ màu (hết đốm màu lạ).

Mochy iOS 0.7.1 — đăng nhập tài khoản thật, thanh mờ trong suốt, nút tải tròn

- Liên kết tài khoản nay mở trang đăng nhập thật của Spotify, Deezer, SoundCloud, Apple Music, YouTube Music ngay trong app; sau khi đăng nhập Mochy đọc được thư viện riêng tư của tài khoản (bài đã thích, playlist) và tự đồng bộ. Cookie đăng nhập lưu trong Keychain.
- Thanh trên của mọi màn hình trong app là kính mờ trong suốt (chỉ làm mờ nền, không phủ màu sáng/tối) nhạt dần xuống dưới; bỏ nút quay lại riêng ở tab Cài đặt.
- Sửa ô chọn Sáng/Tối/Tự động (và Chất lượng, Kênh cập nhật) bị lỗi bo góc: đổi sang nút chọn Material 3 dạng viên thuốc.
- Danh sách bài (Yêu thích, playlist, lịch sử): thu hẹp nút Ngẫu nhiên và thêm nút tròn tải xuống; khi tải hiện vòng tiến độ như App Store (bấm để dừng), tải xong hiện dấu ✓.

Mochy iOS 0.7.0 — Material 3, hộp thoại động, liên kết tài khoản nhạc

- Cài đặt dạng Material 3: thẻ bo góc theo nhóm, công tắc M3, tiêu đề nhóm màu nhấn; thanh trên kính mờ nhạt dần như ảnh mẫu (nút quay lại tròn bằng kính, tiêu đề ở giữa).
- Hộp thoại xoá playlist có hoạt ảnh thùng rác: nắp lật mở, tài liệu rơi vào, nắp đóng lại, thân thùng bóp nhẹ rồi hộp thoại tự đóng (Huỷ/Esc đóng ngay).
- Liên kết tài khoản nhạc (Cài đặt ▸ Tài khoản nhạc): Spotify (đăng nhập thật, cần Client ID riêng), Deezer, SoundCloud (qua link hồ sơ công khai), Apple Music và YouTube Music (qua link playlist). Tự tạo playlist "Bài hát đã thích" và các playlist của bạn, ảnh bìa là biểu tượng dịch vụ, tự đồng bộ mỗi khi mở app (cách nhau 12 giờ).
- Thêm nút tải tất cả bài trong playlist (tải 2 bài cùng lúc).
- Sửa lỗi lời bài hát: các dòng mờ không còn "rõ một chớp" rồi mới mờ lại khi đổi dòng.

Mochy iOS 0.6.7 — khôi phục blur như bản 0.6.4

- Dải mờ dưới ảnh bìa trở lại 4 lớp và đúng vị trí cũ; chữ lời mờ và vầng sáng từng chữ trở lại chất lượng làm mờ Gaussian như trước (dựng ở luồng nền, không chặn giao diện nên vẫn mượt).

Mochy iOS 0.6.6 — sửa thanh tab thụt ra thụt vào khi cuộn

- Thanh tab và thanh phát nhỏ không còn nhấp nháy giữa hai trạng thái khi vuốt lên xuống: tính theo quãng cuộn liên tục theo một hướng, bỏ qua đàn hồi ở hai đầu danh sách và có thời gian nghỉ để hiệu ứng chạy xong.

Mochy iOS 0.6.5 — tối ưu hiệu năng, bỏ viền và dải sáng của thấu kính

- Giảm giật: làm mờ chữ lời và vầng sáng từng chữ chuyển sang cách vẽ nhẹ (không còn bộ lọc nặng chạy trên luồng chính mỗi lần đổi dòng); đốm màu nền dùng ảnh có sẵn thay cho gradient vẽ lại mỗi khung hình; mặt nạ dải màu chỉ gắn khi cần và ẩn hẳn khi không hiện; ít lớp mờ hơn.
- Mở màn hình đang phát: video chờ màn hình hiện xong mới tải; khi lời phủ kín thì video tạm dừng; ảnh bìa được giải mã sẵn ở luồng nền.
- Thanh tab: đo độ sáng nền chỉ chụp đúng dải phía sau thanh và thưa hơn; bỏ viền kính và dải trắng của thấu kính chọn tab.

Mochy iOS 0.6.4 — sửa vệt xám ở thanh home

- Màn hình đang phát: sửa vệt xám hiện ở chỗ thanh home khi mở/tắt lời và khi mở bài từ thanh phát nhỏ (dải màu "thở" làm hở mép dưới).

Mochy iOS 0.6.3 — bỏ viền kính và dải sáng của thanh tab

- Thanh tab: bỏ viền kính và dải trắng nhẹ từ trên xuống; giữ nguyên mọi hiệu ứng khác (thấu kính trượt, nảy, tự đổi sáng/tối, thu gọn khi cuộn).

Mochy iOS 0.6.2 — dải màu đồng bộ nền lời, thanh tab liquid glass

- Màn hình đang phát: dải mờ phía dưới ảnh bìa/video giờ cùng bảng màu và cùng lớp màu chuyển động với nền khi bật lời, nên bật/tắt lời màu nối liền không bị nhảy. Dải màu trồi lên khi mở màn hình, "thở" nhẹ lên xuống, đổi màu mượt khi sang bài mới và loang ra phủ kín khi bật lời. Chế độ Tự động nay luôn đồng bộ với nền lời; chọn "Sáng" trong menu ba chấm nếu muốn dải mờ sáng.
- Thanh tab liquid glass: nền kính mờ có viền sáng, icon và nền tự đổi sáng/tối theo nội dung phía sau; tab đang chọn tô màu nhấn Mochy; thấu kính chọn tab trượt bằng lò xo, co giãn như giọt nước, chạm thì phồng và icon nảy; kéo ngón tay để lướt qua các tab.
- Cuộn xuống thì thanh tab thu gọn thành viên tròn (icon tab đang chọn) và thanh phát nhỏ trượt xuống cạnh nó; cuộn lên hoặc chạm viên tròn để mở lại.

Mochy iOS 0.6.1 — 10 nguồn lời chạy song song, video Canvas Spotify, lời trôi nhanh hơn

- Lời bài hát: hỏi song song Spicy Lyrics, BiniLyrics, Musixmatch, Unison, YouLy+, SimpMusic, NetEase, LRCLIB, QQ Music, KuGou, Genius; tự chọn bản tốt nhất (đồng bộ từng chữ > từng dòng > lời thường), loại bản lệch độ dài so với bài. Có bản từng chữ là dùng ngay.
- Spicy Lyrics cần API key (Cài đặt ▸ Nguồn nâng cao). Genius chỉ có lời thường.
- Video Canvas của Spotify làm nền màn hình đang phát (nhập cookie sp_dc trong Nguồn nâng cao); không có Canvas thì dùng MV YouTube, không có nữa thì hiện ảnh bìa.
- Lời trôi giảm độ trễ: dòng mới sáng sớm hơn khoảng 0,25 giây, sóng chuyển dòng nhanh hơn nhưng không đổi tốc độ chạy chữ.

Mochy iOS 0.6.0 — tải kèm lời, sửa lỗi độ dài, nhập playlist, Last.fm, Recap

- Tải xuống: tự tải kèm lời bài hát (nghe offline vẫn có lời, đồng bộ từng chữ nếu có). Lưu độ dài thật, kiểm tra tải đủ dung lượng và cắt tệp về đúng độ dài, nên bài 3 phút không còn bị hiện 6 phút.
- Cập nhật: hiện cả hai bản .ipa và .deb (bản phù hợp với cách cài của bạn được chọn sẵn); tải xong chọn ứng dụng để ký/cài. Tự sao lưu dữ liệu trước khi cập nhật.
- Sao lưu / khôi phục (Cài đặt ▸ Dữ liệu): yêu thích, playlist, lịch sử, cài đặt; khôi phục chỉ gộp, không xoá dữ liệu đang có. Tự sao lưu mỗi khi mở app, tệp nằm trong Tệp ▸ Mochy.
- Nhập playlist từ link Spotify, Apple Music, Deezer, SoundCloud, YouTube Music (playlist công khai), ghép từng bài sang YouTube Music; nhập lại cùng link sẽ chỉ thêm bài mới. Spotify chỉ lấy được khoảng 100 bài đầu.
- Last.fm: đăng nhập bằng API key riêng, báo đang nghe, scrobble, thích/bỏ thích.
- Trang nghệ sĩ và album (Xem nghệ sĩ trong menu bài hát, phát/xáo trộn).
- Thông tin bài hát (codec, bitrate, độ dài thật, nguồn lời…) trong menu ba chấm.
- Recap: tổng kết thời gian nghe, bài và nghệ sĩ nghe nhiều nhất, thói quen, chia sẻ ảnh.

Mochy iOS 0.5.7 — font SF Pro Rounded, chỉnh độ đậm lời

- Đóng kèm font SF Pro Rounded (7 mức đậm, đã cắt còn chữ Latin và tiếng Việt), dùng cho lời và chữ ở màn hình đang phát.
- Menu ba chấm: "Độ đậm lời…" mở thanh trượt chọn 7 mức từ rất nhạt đến đậm nhất, lời đổi ngay khi kéo và được lưu lại; mặc định tự chọn mức đậm nhất.

Mochy iOS 0.5.6 — vầng sáng chữ, nền sáng/tối theo bìa

- Từ đang hát: vầng sáng là ảnh chữ làm mờ nằm sau chữ nên loang đều quanh chữ, không còn bị cắt thành khung chữ nhật.
- Màn hình bìa: làm mờ và nút tự chuyển sáng/tối theo độ sáng của ảnh bìa (bìa sáng → mờ sáng, chữ và nút màu tối; bìa tối → mờ tối, nút sáng).
- Menu ba chấm: thêm "Làm mờ nền" để chọn Tự động / Sáng / Tối.
- Nền gradient khi mở lời tối hơn một chút để nút và chữ luôn dễ đọc.

Mochy iOS 0.5.5 — nền lời, làm mờ tăng dần, icon lời

- Lời: vầng mờ quanh chữ lan đủ rộng, không còn bị cắt thành khung.
- Nền khi mở lời: gradient từ màu bìa (các đốm màu mềm trôi chậm), thay cho các lớp ảnh mờ xoay.
- Màn hình bìa: làm mờ tăng dần từ không mờ ở trên đến mờ đậm ở dưới (nhiều lớp mờ chồng nhau), bỏ dải màu phủ.
- Icon lời: đang chọn dùng logo gốc, chưa chọn là bản viền rỗng vẽ lại cùng hình dạng.
- Nút ba chấm cùng kiểu kính xám như nút còn lại; màu các nút sáng và rõ hơn, nút tắt dịu hơn nút bật.

Mochy iOS 0.5.4 — lời trôi kiểu sóng

- Đổi dòng: các dòng trượt về chỗ mới theo hiệu ứng sóng (dòng càng xa phía dưới càng trễ), chuyển bằng lò xo nên mượt, không còn cứng.
- Dòng chưa/đã hát to hơn ~25% (0,62 → 0,78 lần dòng đang hát).
- Từ đang hát nổi lên nhanh rồi hạ xuống từ từ, phóng nhẹ và phát sáng, theo đúng thời gian từng từ.

Mochy iOS 0.5.3 — thanh thời lượng theo màu bài hát

- Thanh tiến trình ở thanh phát nhỏ (trước đây màu đỏ cố định) giờ lấy màu nhấn của bài hát.
- Màu nhấn của bài hát sáng và đậm hơn để nổi trên nền tối; dùng chung cho thanh, số giây và icon ở màn hình đang phát.

Mochy iOS 0.5.2 — làm lại lời bài hát

- Dùng 3 icon mới (lời, thiết bị, danh sách phát), đổi màu theo ảnh bìa.
- Màu xanh lá đổi thành màu nhấn của Mochy (nút ngẫu nhiên/lặp, gạch dưới thiết bị, dấu đã thích).
- Lời: dòng đang hát phóng to, các dòng khác thu nhỏ (~0,6 lần), giảm độ mờ; dòng đổi mượt kèm cuộn.
- Chữ chạy theo từng từ: mép tô mềm, từ đang hát nổi lên, phóng nhẹ và phát sáng.
- Chế độ lời: ảnh bìa và tên bài ở đầu trang thu nhỏ lại.

Mochy iOS 0.5.1 — sửa hiệu ứng mở/đóng màn hình đang phát

- Vuốt xuống / mở lên: ảnh bìa và màn hình đi cùng nhau, không còn lệch rồi nhảy về chỗ cũ.
- Không còn làm mờ/thu nhỏ màn hình phía sau, nên thanh trên cùng (nút quay lại, tên playlist) không bị mất.
- Chụp sẵn màn hình khi kéo nên mượt hơn, hết giật.
- Thanh thời lượng và số giây đổi màu theo màu bìa bài hát.

Mochy iOS 0.5.0 — làm lại màn hình đang phát

- Giao diện mới theo mẫu: bìa tràn màn hình, nút kính mờ (đóng, tên danh sách, tuỳ chọn), tên bài chạy ngang, huy hiệu E, nút đã thích tròn, thanh tiến trình dày, dải mờ phía sau các nút.
- Bài có MV thì dùng video làm nền (không tiếng, bám theo nhạc); bài không có thì dùng ảnh bìa. Tắt/bật trong Cài đặt.
- Bấm nút lời: nền màu chuyển động từ bìa, đầu trang thu nhỏ (bìa nhỏ + tên bài), lời chữ lớn, dòng đang hát rõ, các dòng khác mờ mạnh.
- Sau 5 giây không chạm, lời phủ toàn màn hình (ẩn các nút); chạm lại để hiện.
- Hẹn giờ tắt, tải xuống, thêm playlist chuyển vào nút "..." ở góc phải.
