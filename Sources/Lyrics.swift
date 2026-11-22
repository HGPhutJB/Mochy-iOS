import UIKit

struct LyricLine {
    let time: Double
    let text: String
}

struct LyricsResult {
    var synced: [LyricLine]
    var plain: String?
    var source: String
}

/// Lấy lời bài hát: SimpMusic (theo videoId) → LRCLIB (theo tên bài + nghệ sĩ). Có lời đồng bộ thì dùng, không thì lời thường.
final class LyricsService {
    static let shared = LyricsService()
    private var cache: [String: LyricsResult] = [:]
    private var missed: Set<String> = []
    private let lock = NSLock()
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.httpAdditionalHeaders = ["User-Agent": "MochyiOS (+https://github.com/HGPhutJB/Mochy-iOS)", "Accept": "application/json"]
        return URLSession(configuration: c)
    }()

    func lyrics(for song: Song, durationHint: Double, completion: @escaping (LyricsResult?) -> Void) {
        lock.lock()
        let hit = cache[song.videoId]
        let known = missed.contains(song.videoId)
        lock.unlock()
        if let hit = hit { completion(hit); return }
        if known { completion(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let duration = durationHint > 0 ? durationHint : LyricsService.seconds(song.duration)
            var best: LyricsResult? = self.fromSimpMusic(song)
            if best == nil || best!.synced.isEmpty {
                if let lrc = self.fromLRCLIB(song, duration: duration) {
                    if best == nil || !lrc.synced.isEmpty { best = lrc }
                }
            }
            self.lock.lock()
            if let best = best { self.cache[song.videoId] = best } else { self.missed.insert(song.videoId) }
            self.lock.unlock()
            DispatchQueue.main.async { completion(best) }
        }
    }

    static func seconds(_ text: String?) -> Double {
        guard let text = text else { return 0 }
        let parts = text.split(separator: ":").compactMap { Double($0) }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    // MARK: - Mạng

    private func getJSON(_ url: URL) -> Any? {
        let sem = DispatchSemaphore(value: 0)
        var out: Any?
        session.dataTask(with: url) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data {
                out = try? JSONSerialization.jsonObject(with: data, options: [])
            }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    private func fromSimpMusic(_ song: Song) -> LyricsResult? {
        for base in ["https://api-lyrics.simpmusic.org/v1/", "https://musicfy-yt-music-server.onrender.com/v1/"] {
            guard let url = URL(string: base + song.videoId),
                  let json = getJSON(url) as? [String: Any],
                  (json["type"] as? String) == "success",
                  let list = json["data"] as? [[String: Any]] else { continue }
            let sorted = list.sorted { ((($0["vote"] as? Int) ?? 0) > (($1["vote"] as? Int) ?? 0)) }
            for item in sorted {
                if let lrc = item["syncedLyrics"] as? String {
                    let lines = LyricsService.parseLRC(lrc)
                    if !lines.isEmpty {
                        return LyricsResult(synced: lines, plain: item["plainLyric"] as? String, source: "SimpMusic")
                    }
                }
            }
            if let plain = sorted.compactMap({ $0["plainLyric"] as? String }).first(where: { !$0.isEmpty }) {
                return LyricsResult(synced: [], plain: plain, source: "SimpMusic")
            }
            return nil
        }
        return nil
    }

    private func fromLRCLIB(_ song: Song, duration: Double) -> LyricsResult? {
        let title = LyricsService.cleanTitle(song.title)
        let artist = LyricsService.cleanArtist(song.artist)
        func build(_ path: String, _ items: [URLQueryItem]) -> URL? {
            var c = URLComponents(string: "https://lrclib.net" + path)
            c?.queryItems = items
            return c?.url
        }
        var candidates: [[String: Any]] = []
        var q = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if duration > 0 { q.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        if let url = build("/api/get", q), let obj = getJSON(url) as? [String: Any] { candidates.append(obj) }
        if candidates.isEmpty {
            let search = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
            if let url = build("/api/search", search), let arr = getJSON(url) as? [[String: Any]] { candidates = arr }
        }
        if candidates.isEmpty {
            if let url = build("/api/search", [URLQueryItem(name: "q", value: title + " " + artist)]),
               let arr = getJSON(url) as? [[String: Any]] { candidates = arr }
        }
        // ưu tiên bản có lời đồng bộ và độ dài gần nhất
        let usable = candidates.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
        let pool = usable.isEmpty ? candidates : usable
        let pick = pool.min { a, b in
            let da = abs((a["duration"] as? Double ?? 0) - duration)
            let db = abs((b["duration"] as? Double ?? 0) - duration)
            return da < db
        }
        guard let item = pick else { return nil }
        if duration > 0, let d = item["duration"] as? Double, abs(d - duration) > 15 { return nil }
        if let lrc = item["syncedLyrics"] as? String {
            let lines = LyricsService.parseLRC(lrc)
            if !lines.isEmpty { return LyricsResult(synced: lines, plain: item["plainLyrics"] as? String, source: "LRCLIB") }
        }
        if let plain = item["plainLyrics"] as? String, !plain.isEmpty {
            return LyricsResult(synced: [], plain: plain, source: "LRCLIB")
        }
        return nil
    }

    // MARK: - Phân tích

    static func parseLRC(_ text: String) -> [LyricLine] {
        guard let stamp = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]", options: []) else { return [] }
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = stamp.matches(in: raw, options: [], range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { continue }
            let last = matches[matches.count - 1]
            var body = ns.substring(from: last.range.location + last.range.length)
            // bỏ thẻ thời gian từng từ dạng <00:12.34>
            body = body.replacingOccurrences(of: "<\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?>", with: "", options: .regularExpression)
            body = body.trimmingCharacters(in: .whitespaces)
            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                lines.append(LyricLine(time: mm * 60 + ss + frac, text: body))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func cleanTitle(_ title: String) -> String {
        var t = title
        let patterns = ["\\s*[\\(\\[][^\\)\\]]*(official|video|audio|lyric|visualizer|hd|hq|4k|remaster|live|mv)[^\\)\\]]*[\\)\\]]",
                        "\\s*【.*?】", "\\s*\\|.*$", "\\s*[\\(\\[]?(feat|ft)\\.?[^\\)\\]]*[\\)\\]]?$"]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive]) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func cleanArtist(_ artist: String) -> String {
        var a = artist
        for sep in [" & ", " and ", ", ", " x ", " feat. ", " ft. ", " with "] {
            if let r = a.range(of: sep, options: .caseInsensitive) { a = String(a[..<r.lowerBound]); break }
        }
        return a.trimmingCharacters(in: .whitespaces)
    }
}

/// Khu vực hiển thị lời: cuộn tự động theo dòng đang hát, chạm vào dòng để tua tới đó.
final class LyricsView: UIView, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private var lines: [LyricLine] = []
    private var plain: String?
    private var current = -1
    private var userScrolledAt = Date.distantPast
    var onSeek: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "line")
        table.estimatedRowHeight = 60
        table.rowHeight = UITableView.automaticDimension
        table.translatesAutoresizingMaskIntoConstraints = false
        addSubview(table)
        statusLabel.font = Theme.bold(17)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: topAnchor),
            table.bottomAnchor.constraint(equalTo: bottomAnchor),
            table.leadingAnchor.constraint(equalTo: leadingAnchor),
            table.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    func showLoading() { set(lines: [], plain: nil, message: "Đang tìm lời…") }

    func show(_ result: LyricsResult?) {
        guard let r = result else { set(lines: [], plain: nil, message: "Không tìm thấy lời bài hát này"); return }
        set(lines: r.synced, plain: r.synced.isEmpty ? r.plain : nil, message: nil)
    }

    private func set(lines: [LyricLine], plain: String?, message: String?) {
        self.lines = lines
        self.plain = plain
        current = -1
        statusLabel.text = message
        statusLabel.isHidden = message == nil
        table.reloadData()
        table.contentOffset = CGPoint(x: 0, y: -table.contentInset.top)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad = bounds.height * 0.35
        if table.contentInset.top != pad {
            table.contentInset = UIEdgeInsets(top: pad, left: 0, bottom: pad, right: 0)
        }
    }

    /// Gọi theo thời gian phát; cuộn tới dòng đang hát.
    func update(time: Double) {
        guard !lines.isEmpty else { return }
        var lo = 0, hi = lines.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time + 0.15 { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard idx != current else { return }
        let old = current
        current = idx
        for row in [old, idx] where row >= 0 {
            if let cell = table.cellForRow(at: IndexPath(row: row, section: 0)) { style(cell, row: row) }
        }
        if idx >= 0, Date().timeIntervalSince(userScrolledAt) > 3 {
            table.scrollToRow(at: IndexPath(row: idx, section: 0), at: .middle, animated: true)
        }
    }

    func resetFollow() { userScrolledAt = .distantPast }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { userScrolledAt = Date() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { userScrolledAt = Date() }

    // MARK: - Bảng

    func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !lines.isEmpty { return lines.count }
        return plain == nil ? 0 : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "line", for: indexPath)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0
        if lines.isEmpty {
            cell.textLabel?.text = plain
            cell.textLabel?.font = Theme.bold(20)
            cell.textLabel?.textColor = Theme.primaryText
            cell.textLabel?.textAlignment = .left
            cell.textLabel?.alpha = 1
        } else {
            cell.textLabel?.text = lines[indexPath.row].text.isEmpty ? "♪" : lines[indexPath.row].text
            style(cell, row: indexPath.row)
        }
        return cell
    }

    private func style(_ cell: UITableViewCell, row: Int) {
        let active = row == current
        cell.textLabel?.font = Theme.heavy(active ? 28 : 24)
        cell.textLabel?.textColor = Theme.primaryText
        cell.textLabel?.alpha = active ? 1 : 0.38
        cell.textLabel?.textAlignment = .left
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !lines.isEmpty else { return }
        userScrolledAt = .distantPast
        onSeek?(lines[indexPath.row].time)
    }
}
