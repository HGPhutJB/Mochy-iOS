import UIKit

/// "Thông tin bài hát" (kiểu Stats for nerds): codec, bitrate, độ dài thật, nguồn phát, lời…
final class SongInfoViewController: UITableViewController {
    private var sections: [(String, [(String, String)])] = []
    private let song: Song

    init(song: Song) {
        self.song = song
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("Thông tin bài hát")
        tableView.backgroundColor = Theme.groupedBackground
        tableView.allowsSelection = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        build()
    }

    @objc private func close() { dismiss(animated: true, completion: nil) }

    private func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func build() {
        let engine = PlayerEngine.shared
        let isCurrent = engine.currentSong == song
        var general: [(String, String)] = [(L("Tên"), song.title), (L("Nghệ sĩ"), song.artist), (L("Mã video"), song.videoId)]
        if let d = song.duration { general.append((L("Độ dài (YouTube)"), d)) }
        sections.append((L("Bài hát"), general))

        var stream: [(String, String)] = []
        let downloaded = Library.shared.isDownloaded(song)
        if isCurrent, let info = engine.streamInfo {
            stream.append((L("Nguồn phát"), engine.isLocal ? L("Tệp đã tải") : L("Trực tuyến")))
            stream.append(("Codec", info.codecLabel))
            if info.bitrate > 0 { stream.append(("Bitrate", "\(info.bitrate / 1000) kbps")) }
            if info.sampleRate > 0 { stream.append((L("Tần số mẫu"), "\(info.sampleRate) Hz")) }
            stream.append(("Client", info.clientName))
            if info.contentLength > 0 { stream.append((L("Dung lượng luồng"), ByteCountFormatter.string(fromByteCount: info.contentLength, countStyle: .file))) }
            if info.durationSeconds > 0 { stream.append((L("Độ dài thật"), time(info.durationSeconds))) }
            stream.append((L("Kiểm tra byte cuối"), info.unverified ? L("Không qua (có thể bị cắt)") : L("Đạt")))
        } else if isCurrent && engine.isLocal {
            stream.append((L("Nguồn phát"), L("Tệp đã tải")))
        } else {
            stream.append((L("Nguồn phát"), isCurrent ? L("Đang tải thông tin…") : L("Không phải bài đang phát")))
        }
        if isCurrent && engine.duration > 0 { stream.append((L("Độ dài player"), time(engine.duration))) }
        sections.append((L("Luồng âm thanh"), stream))

        var offline: [(String, String)] = [(L("Đã tải xuống"), downloaded ? L("Có") : L("Chưa"))]
        if downloaded {
            offline.append((L("Dung lượng tệp"), ByteCountFormatter.string(fromByteCount: Library.shared.fileSize(of: song), countStyle: .file)))
            let real = DownloadStore.realDuration(for: song)
            if real > 0 { offline.append((L("Độ dài đã lưu"), time(real))) }
            offline.append((L("Lời kèm theo"), DownloadStore.lyrics(song.videoId) != nil ? L("Có") : L("Không")))
        }
        sections.append((L("Ngoại tuyến"), offline))

        var lyr: [(String, String)] = []
        if let result = LyricsService.shared.cached(song.videoId) ?? DownloadStore.lyrics(song.videoId) {
            lyr.append((L("Nguồn lời"), result.source))
            lyr.append((L("Kiểu"), result.synced.isEmpty ? L("Lời thường") : Lf("Đồng bộ theo %@ dòng", result.synced.count)))
        } else {
            lyr.append((L("Nguồn lời"), L("Chưa tải / không có")))
        }
        sections.append((L("Lời bài hát"), lyr))
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return sections[section].1.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { return sections[section].0 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let row = sections[indexPath.section].1[indexPath.row]
        cell.backgroundColor = Theme.cellBackground
        cell.textLabel?.text = row.0
        cell.textLabel?.textColor = Theme.primaryText
        cell.textLabel?.font = Theme.regular(15)
        cell.detailTextLabel?.text = row.1
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.detailTextLabel?.font = Theme.regular(14)
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }
}
