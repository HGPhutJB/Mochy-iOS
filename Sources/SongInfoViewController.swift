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
        title = "Thông tin bài hát"
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
        var general: [(String, String)] = [("Tên", song.title), ("Nghệ sĩ", song.artist), ("Mã video", song.videoId)]
        if let d = song.duration { general.append(("Độ dài (YouTube)", d)) }
        sections.append(("Bài hát", general))

        var stream: [(String, String)] = []
        let downloaded = Library.shared.isDownloaded(song)
        if isCurrent, let info = engine.streamInfo {
            stream.append(("Nguồn phát", engine.isLocal ? "Tệp đã tải" : "Trực tuyến"))
            stream.append(("Codec", info.codecLabel))
            if info.bitrate > 0 { stream.append(("Bitrate", "\(info.bitrate / 1000) kbps")) }
            if info.sampleRate > 0 { stream.append(("Tần số mẫu", "\(info.sampleRate) Hz")) }
            stream.append(("Client", info.clientName))
            if info.contentLength > 0 { stream.append(("Dung lượng luồng", ByteCountFormatter.string(fromByteCount: info.contentLength, countStyle: .file))) }
            if info.durationSeconds > 0 { stream.append(("Độ dài thật", time(info.durationSeconds))) }
            stream.append(("Kiểm tra byte cuối", info.unverified ? "Không qua (có thể bị cắt)" : "Đạt"))
        } else if isCurrent && engine.isLocal {
            stream.append(("Nguồn phát", "Tệp đã tải"))
        } else {
            stream.append(("Nguồn phát", isCurrent ? "Đang tải thông tin…" : "Không phải bài đang phát"))
        }
        if isCurrent && engine.duration > 0 { stream.append(("Độ dài player", time(engine.duration))) }
        sections.append(("Luồng âm thanh", stream))

        var offline: [(String, String)] = [("Đã tải xuống", downloaded ? "Có" : "Chưa")]
        if downloaded {
            offline.append(("Dung lượng tệp", ByteCountFormatter.string(fromByteCount: Library.shared.fileSize(of: song), countStyle: .file)))
            let real = DownloadStore.realDuration(for: song)
            if real > 0 { offline.append(("Độ dài đã lưu", time(real))) }
            offline.append(("Lời kèm theo", DownloadStore.lyrics(song.videoId) != nil ? "Có" : "Không"))
        }
        sections.append(("Ngoại tuyến", offline))

        var lyr: [(String, String)] = []
        if let result = LyricsService.shared.cached(song.videoId) ?? DownloadStore.lyrics(song.videoId) {
            lyr.append(("Nguồn lời", result.source))
            lyr.append(("Kiểu", result.synced.isEmpty ? "Lời thường" : "Đồng bộ theo \(result.synced.count) dòng"))
        } else {
            lyr.append(("Nguồn lời", "Chưa tải / không có"))
        }
        sections.append(("Lời bài hát", lyr))
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
