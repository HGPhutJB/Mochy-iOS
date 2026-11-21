# Mochy iOS

> Bản chuyển Mochy Music sang iOS 12+ (Swift + UIKit). Dựa trên **Mochy Music** của realidkroo
> (https://github.com/realidkroo/mochy-music, GPL-3.0).

Trình nghe nhạc cho iPhone đời cũ: tìm bài từ YouTube Music, phát nền, điều khiển ở màn hình khoá.

- Gói cài: `.deb` cho máy jailbreak (rootful, Chimera/Sileo) và `.ipa` chưa ký cho ESign / Sideloadly / AltStore
- Bundle id: `com.puc.mochyios`, iOS 12.2 trở lên (arm64)
- Giấy phép: GPL-3.0 (xem `LICENSE`)

## Tải về

Vào [Releases](../../releases): bản **ổn định** (`v…`) và bản **thử nghiệm** (`dev`, ghi đè sau mỗi lần cập nhật mã).
Máy jailbreak cũng có thể thêm nguồn Sileo `https://hgphutjb.github.io/repo/` và cài `Mochy iOS` từ đó (chỉ có bản ổn định).

## Cập nhật trong app

Tab **Cài đặt** có:

- Tự động kiểm tra cập nhật (tối đa 6 giờ một lần, tắt được)
- Kênh **Ổn định** hoặc **Nhà phát triển**
- Nút "Kiểm tra cập nhật ngay"; khi có bản mới, tải về, app xác minh rồi mở tệp bằng Sileo / ESign

Bảo mật của cơ chế cập nhật:

- Chỉ HTTPS tới `github.com` và `*.githubusercontent.com`, chặn chuyển hướng ra host khác
- Link tải phải nằm đúng trong repo này; tên tệp và đuôi `.deb` / `.ipa` được kiểm tra
- `update.json` được ký ECDSA P-256 (secret `UPDATE_SIGNING_KEY`); chữ ký sai thì bỏ qua bản cập nhật
- Tệp tải về phải khớp kích thước và SHA-256 trong `update.json`
- Chỉ chấp nhận build cao hơn bản đang chạy (chống hạ cấp), không bao giờ tự cài

## Build

Chỉ build được trên macOS có Xcode. Repo này build bằng GitHub Actions (`.github/workflows/build.yml`):

- Đẩy mã lên `main` → build, phát hành lại release `dev` (kênh Nhà phát triển)
- Actions → "Build and release" → Run workflow, chọn `stable` → phát hành `v<VERSION>` (đọc `VERSION` và `RELEASE_NOTES.md`)

Chạy tay trên Mac: `./build.sh` (cần `brew install ldid dpkg`).

## Tiến độ

| Mốc | Nội dung | Trạng thái |
|-----|----------|------------|
| 0 | Khung app, tìm kiếm, phát một bài, phát nền, màn hình khoá | xong, đang thử |
| 0.5 | Cập nhật trong app (hai kênh), icon mới | bản này |
| 1 | Hàng đợi, thư viện, playlist, tải về, giao diện kiểu Apple Music | chưa |
| 2 | Lời bài hát đồng bộ, equalizer | chưa |
| 3 | Import playlist, Last.fm, các tính năng còn lại | chưa |

## Ghi công

Danh sách đầy đủ nằm trong [`NOTICE`](NOTICE):

- Mochy Music (realidkroo): nguồn cảm hứng, luồng gọi YouTube Music và thông số client
- ViviMusic (vivizzz007Z) và Metrolist (Mostafa Alagamy): nền mà Mochy Music xây lên
- LRCLIB, SimpMusic, LyricsPlus, Better Lyrics API, Monochrome Music, AutoEq: dịch vụ sẽ dùng ở mốc sau

Mochy iOS là dự án không chính thức, không liên kết với YouTube, Google hay Apple, và không lưu trữ hay phân phối nhạc.
