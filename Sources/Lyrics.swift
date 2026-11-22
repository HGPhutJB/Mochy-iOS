import UIKit

struct LyricWord {
    let text: String
    let start: Double
    let end: Double
}

struct LyricLine {
    let time: Double
    let text: String
    var words: [LyricWord] = []
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
            // Thử lần lượt; nguồn nào có lời đồng bộ trước thì dùng, không có thì giữ lời thường đầu tiên.
            let sources: [() -> LyricsResult?] = [
                { self.fromYouLyPlus(song, duration: duration) },
                { self.fromSimpMusic(song) },
                { self.fromLRCLIB(song, duration: duration) },
                { self.fromKuGou(song, duration: duration) }
            ]
            var best: LyricsResult?
            for source in sources {
                if let r = source() {
                    if !r.synced.isEmpty { best = r; break }
                    if best == nil { best = r }
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

    /// YouLy+: gom lời từ Apple Music / Musixmatch / Spotify, không cần khoá; có cả nhạc Việt.
    private func fromYouLyPlus(_ song: Song, duration: Double) -> LyricsResult? {
        let title = LyricsService.cleanTitle(song.title)
        let artist = LyricsService.cleanArtist(song.artist)
        for base in ["https://lyricsplus.prjktla.my.id", "https://lyricsplus.binimum.org"] {
            var c = URLComponents(string: base + "/v2/lyrics/get")
            var items = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "artist", value: artist)]
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
            c?.queryItems = items
            guard let url = c?.url, let json = getJSON(url) as? [String: Any] else { continue }
            var lines: [LyricLine] = []
            if let list = json["lyrics"] as? [[String: Any]] {
                for item in list {
                    guard let ms = item["time"] as? Double ?? (item["time"] as? Int).map(Double.init) else { continue }
                    var text = (item["text"] as? String) ?? ""
                    var words: [LyricWord] = []
                    if let syl = item["syllabus"] as? [[String: Any]] {
                        let lineStart = ms / 1000
                        for sy in syl {
                            if (sy["isBackground"] as? Bool) == true { continue }
                            guard let t = sy["text"] as? String else { continue }
                            let st = (sy["time"] as? Double) ?? Double((sy["time"] as? Int) ?? 0)
                            let du = (sy["duration"] as? Double) ?? Double((sy["duration"] as? Int) ?? 0)
                            // thời gian âm tiết có thể tuyệt đối hoặc tính từ đầu dòng
                            var start = st / 1000
                            if start < lineStart - 0.5 { start += lineStart }
                            words.append(LyricWord(text: t, start: start, end: start + max(0.05, du / 1000)))
                        }
                        if text.isEmpty { text = words.map { $0.text }.joined() }
                    }
                    var line = LyricLine(time: ms / 1000, text: text.trimmingCharacters(in: .whitespaces))
                    if words.map({ $0.text }).joined().trimmingCharacters(in: .whitespaces) == line.text { line.words = words }
                    lines.append(line)
                }
            }
            if lines.isEmpty, let lrc = json["syncedLyrics"] as? String { lines = LyricsService.parseLRC(lrc) }
            if !lines.isEmpty { return LyricsResult(synced: lines.sorted { $0.time < $1.time }, plain: json["plainLyrics"] as? String, source: "YouLy+") }
            if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
                return LyricsResult(synced: [], plain: plain, source: "YouLy+")
            }
        }
        return nil
    }

    /// KuGou: nguồn lời LRC lớn, hay có nhạc Việt/Hoa.
    private func fromKuGou(_ song: Song, duration: Double) -> LyricsResult? {
        let title = LyricsService.cleanTitle(song.title)
        let artist = LyricsService.cleanArtist(song.artist)
        func object(_ url: URL) -> [String: Any]? {
            let sem = DispatchSemaphore(value: 0)
            var out: [String: Any]?
            session.dataTask(with: url) { data, _, _ in
                if var text = data.flatMap({ String(data: $0, encoding: .utf8) }),
                   let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}") {
                    text = String(text[s...e])
                    out = (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [])) as? [String: Any]
                }
                sem.signal()
            }.resume()
            sem.wait()
            return out
        }
        func url(_ base: String, _ items: [(String, String)]) -> URL? {
            var c = URLComponents(string: base)
            c?.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
            return c?.url
        }
        var candidate: (Int, String)?
        if let u = url("https://mobileservice.kugou.com/api/v3/search/song",
                       [("version", "9108"), ("plat", "0"), ("pagesize", "8"), ("showtype", "0"), ("keyword", title + " - " + artist)]),
           let info = (object(u)?["data"] as? [String: Any])?["info"] as? [[String: Any]] {
            for item in info {
                let d = (item["duration"] as? Double) ?? Double((item["duration"] as? Int) ?? 0)
                if duration > 0 && d > 0 && abs(d - duration) > 8 { continue }
                guard let hash = item["hash"] as? String,
                      let u2 = url("https://lyrics.kugou.com/search", [("ver", "1"), ("man", "yes"), ("client", "pc"), ("hash", hash)]),
                      let cands = object(u2)?["candidates"] as? [[String: Any]], let first = cands.first,
                      let id = (first["id"] as? Int) ?? Int((first["id"] as? String) ?? ""),
                      let key = first["accesskey"] as? String else { continue }
                candidate = (id, key)
                break
            }
        }
        guard let (id, key) = candidate,
              let u3 = url("https://lyrics.kugou.com/download",
                           [("fmt", "lrc"), ("charset", "utf8"), ("client", "pc"), ("ver", "1"), ("id", String(id)), ("accesskey", key)]),
              let content = object(u3)?["content"] as? String,
              let data = Data(base64Encoded: content), let text = String(data: data, encoding: .utf8) else { return nil }
        // bỏ các dòng đầu dạng "Nhạc sĩ: ..." / "Lời: ..."
        var lines = LyricsService.parseLRC(text)
        var head = 0
        while head < min(lines.count, 8), lines[head].text.range(of: "[:：]", options: .regularExpression) != nil { head += 1 }
        lines.removeFirst(head)
        return lines.isEmpty ? nil : LyricsResult(synced: lines, plain: nil, source: "KuGou")
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
            let words = LyricsService.parseWordTags(body)
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
                var line = LyricLine(time: mm * 60 + ss + frac, text: body)
                if words.map({ $0.text }).joined().trimmingCharacters(in: .whitespaces) == body { line.words = words }
                lines.append(line)
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// Lời LRC "enhanced": `<00:12.34>từ <00:12.80>kế`. Trả về rỗng nếu không có thẻ từng từ.
    static func parseWordTags(_ body: String) -> [LyricWord] {
        guard let tag = try? NSRegularExpression(pattern: "<(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?>", options: []) else { return [] }
        let ns = body as NSString
        let matches = tag.matches(in: body, options: [], range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return [] }
        func time(_ m: NSTextCheckingResult) -> Double {
            let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
            var frac = 0.0
            if m.range(at: 3).location != NSNotFound {
                let f = ns.substring(with: m.range(at: 3))
                frac = (Double(f) ?? 0) / pow(10, Double(f.count))
            }
            return mm * 60 + ss + frac
        }
        var words: [LyricWord] = []
        for (i, m) in matches.enumerated() {
            let textStart = m.range.location + m.range.length
            let textEnd = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let text = ns.substring(with: NSRange(location: textStart, length: textEnd - textStart))
            if text.isEmpty { continue }
            let start = time(m)
            let end = i + 1 < matches.count ? time(matches[i + 1]) : start + 0.5
            words.append(LyricWord(text: text, start: start, end: max(end, start + 0.05)))
        }
        return words
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

/// Một dòng lời: dòng đang hát tô trắng dần theo từng từ (karaoke), các dòng khác mờ nhẹ như Apple Music.
final class LyricCell: UITableViewCell {
    static let font = UIFont.systemFont(ofSize: 24, weight: .bold)
    let label = UILabel()
    let blurView = UIImageView()
    private(set) var row = -1
    private var text = ""
    private var words: [LyricWord] = []
    private var wordRanges: [NSRange] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        label.numberOfLines = 0
        label.font = LyricCell.font
        label.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentMode = .topLeft
        blurView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        contentView.addSubview(blurView)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            blurView.topAnchor.constraint(equalTo: label.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: label.leadingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    func configure(line: LyricLine?, text: String, row: Int) {
        self.row = row
        self.text = text
        words = line?.words ?? []
        wordRanges = []
        if !words.isEmpty {
            // khớp từng từ với vị trí ký tự trong dòng
            let ns = text as NSString
            var cursor = 0
            for w in words {
                let r = ns.range(of: w.text.trimmingCharacters(in: .whitespaces), options: [], range: NSRange(location: cursor, length: max(0, ns.length - cursor)))
                if r.location == NSNotFound { wordRanges = []; words = []; break }
                wordRanges.append(r)
                cursor = r.location + r.length
            }
        }
        blurView.image = nil
        label.attributedText = nil
        label.text = text
    }

    func showDim(image: UIImage?, alpha: CGFloat) {
        label.alpha = 0
        blurView.image = image
        blurView.alpha = alpha
    }

    /// Dòng đang hát: tô trắng đến vị trí `time`; chưa có thời gian từng từ thì trắng cả dòng.
    func showActive(time: Double) {
        label.alpha = 1
        blurView.alpha = 0
        let full = Theme.primaryText
        let dim = full.withAlphaComponent(0.34)
        let attr = NSMutableAttributedString(string: text, attributes: [.font: LyricCell.font, .foregroundColor: words.isEmpty ? full : dim])
        if !words.isEmpty {
            let ns = text as NSString
            for (i, w) in words.enumerated() {
                let r = wordRanges[i]
                let p = min(1, max(0, (time - w.start) / max(0.05, w.end - w.start)))
                if p >= 1 {
                    attr.addAttribute(.foregroundColor, value: full, range: r)
                } else if p > 0 {
                    // tô dần từng ký tự trong từ
                    let n = r.length
                    let exact = p * Double(n)
                    let whole = Int(exact)
                    if whole > 0 { attr.addAttribute(.foregroundColor, value: full, range: NSRange(location: r.location, length: whole)) }
                    if whole < n {
                        let frac = CGFloat(exact - Double(whole))
                        attr.addAttribute(.foregroundColor, value: dim.mixedWith(full, frac), range: NSRange(location: r.location + whole, length: 1))
                    }
                }
            }
            _ = ns
        }
        label.attributedText = attr
    }
}

private extension UIColor {
    func mixedWith(_ other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

/// Khu vực hiển thị lời: cuộn mượt theo dòng đang hát, dòng khác mờ nhẹ, chạm vào dòng để tua.
final class LyricsView: UIView, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private var lines: [LyricLine] = []
    private var plain: String?
    private var current = -1
    private var userScrolledAt = Date.distantPast
    private var blurCache: [String: UIImage] = [:]
    private let ciContext = CIContext(options: nil)
    private var link: CADisplayLink?
    var onSeek: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.dataSource = self
        table.delegate = self
        table.register(LyricCell.self, forCellReuseIdentifier: "line")
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

    deinit { link?.invalidate() }

    /// Bật/tắt vòng cập nhật theo từng khung hình (chỉ khi đang hiển thị).
    func setRunning(_ on: Bool) {
        if on {
            guard link == nil else { return }
            let l = CADisplayLink(target: self, selector: #selector(displayTick))
            l.add(to: .main, forMode: .common)
            link = l
        } else {
            link?.invalidate()
            link = nil
        }
    }

    @objc private func displayTick() {
        update(time: PlayerEngine.shared.livePosition)
    }

    func showLoading() { set(lines: [], plain: nil, message: "Đang tìm lời…") }

    func show(_ result: LyricsResult?) {
        guard let r = result else { set(lines: [], plain: nil, message: "Không tìm thấy lời bài hát này"); return }
        set(lines: r.synced, plain: r.synced.isEmpty ? r.plain : nil, message: nil)
    }

    private func set(lines: [LyricLine], plain: String?, message: String?) {
        self.lines = lines
        self.plain = plain
        current = -1
        blurCache.removeAll()
        statusLabel.text = message
        statusLabel.isHidden = message == nil
        table.reloadData()
        table.contentOffset = CGPoint(x: 0, y: -table.contentInset.top)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let top = bounds.height * 0.28
        let bottom = bounds.height * 0.6
        if table.contentInset.top != top {
            table.contentInset = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        }
    }

    /// Gọi mỗi khung hình; cập nhật dòng đang hát, tô từng từ, cuộn tới dòng đó.
    func update(time: Double) {
        guard !lines.isEmpty else { return }
        var lo = 0, hi = lines.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time + 0.1 { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        if idx != current {
            current = idx
            UIView.animate(withDuration: 0.35, delay: 0, options: [.allowUserInteraction, .curveEaseInOut], animations: {
                for case let cell as LyricCell in self.table.visibleCells { self.style(cell, time: time) }
            }, completion: nil)
            if idx >= 0, Date().timeIntervalSince(userScrolledAt) > 3 { scrollToCurrent(animated: true) }
        }
        if current >= 0, let cell = table.cellForRow(at: IndexPath(row: current, section: 0)) as? LyricCell {
            cell.showActive(time: time)
        }
    }

    private func scrollToCurrent(animated: Bool) {
        guard current >= 0 else { return }
        let rect = table.rectForRow(at: IndexPath(row: current, section: 0))
        let target = rect.minY - table.bounds.height * 0.28 + 8 - 40
        let minY = -table.contentInset.top
        let maxY = max(minY, table.contentSize.height - table.bounds.height + table.contentInset.bottom)
        let y = min(max(target + 40, minY), maxY)
        if animated {
            UIView.animate(withDuration: 0.65, delay: 0, options: [.allowUserInteraction, .curveEaseInOut, .beginFromCurrentState], animations: {
                self.table.contentOffset = CGPoint(x: 0, y: y)
            }, completion: nil)
        } else {
            table.contentOffset = CGPoint(x: 0, y: y)
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
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "line", for: indexPath) as? LyricCell else {
            return UITableViewCell()
        }
        if lines.isEmpty {
            cell.configure(line: nil, text: plain ?? "", row: -1)
            cell.label.font = Theme.bold(20)
            cell.label.textColor = Theme.primaryText
            cell.label.alpha = 1
            cell.blurView.alpha = 0
        } else {
            let text = lines[indexPath.row].text
            cell.label.font = LyricCell.font
            cell.configure(line: lines[indexPath.row], text: text.isEmpty ? "♪" : text, row: indexPath.row)
            style(cell, time: PlayerEngine.shared.livePosition)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let c = cell as? LyricCell, !lines.isEmpty { style(c, time: PlayerEngine.shared.livePosition) }
    }

    private func style(_ cell: LyricCell, time: Double) {
        guard cell.row >= 0 else { return }
        if cell.row == current {
            cell.showActive(time: time)
            return
        }
        let distance = current < 0 ? cell.row + 1 : abs(cell.row - current)
        let bucket = min(max(distance, 1), 4)
        // gần: mờ nhẹ, xa: mờ hơn và nhạt hơn (như video mẫu)
        let alpha: CGFloat = [0, 0.42, 0.34, 0.27, 0.2][bucket]
        cell.showDim(image: blurred(row: cell.row, bucket: bucket, text: cell.label.text ?? ""), alpha: alpha)
    }

    private func blurred(row: Int, bucket: Int, text: String) -> UIImage? {
        let width = max(40, table.bounds.width - 44)
        let key = "\(row)-\(bucket)-\(Int(width))-\(Theme.isDark)"
        if let hit = blurCache[key] { return hit }
        let ns = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: LyricCell.font, .foregroundColor: Theme.primaryText]
        let rect = ns.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        let size = CGSize(width: width, height: ceil(rect.height))
        guard size.height > 1 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        let flat = renderer.image { _ in ns.draw(with: CGRect(origin: .zero, size: size), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil) }
        let radius: Double = [0, 0.7, 1.1, 1.5, 1.9][bucket]
        guard let input = CIImage(image: flat), let filter = CIFilter(name: "CIGaussianBlur") else { return flat }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage,
              let cg = ciContext.createCGImage(output, from: input.extent) else { return flat }
        let image = UIImage(cgImage: cg, scale: flat.scale, orientation: .up)
        blurCache[key] = image
        return image
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !lines.isEmpty else { return }
        userScrolledAt = .distantPast
        onSeek?(lines[indexPath.row].time)
    }
}

/// Nền chuyển động mềm kiểu Apple Music: vài mảng màu lấy từ bìa trôi chậm.
final class FluidBackgroundView: UIView {
    private var blobs: [CAGradientLayer] = []
    private var colors: [UIColor] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    func setPalette(_ palette: [UIColor]) {
        colors = palette
        rebuild()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if blobs.isEmpty && !colors.isEmpty { rebuild() }
    }

    private func rebuild() {
        blobs.forEach { $0.removeFromSuperlayer() }
        blobs = []
        guard bounds.width > 0, !colors.isEmpty else { return }
        let size = max(bounds.width, bounds.height) * 0.95
        let anchors: [CGPoint] = [CGPoint(x: 0.1, y: 0.15), CGPoint(x: 0.9, y: 0.3), CGPoint(x: 0.2, y: 0.85), CGPoint(x: 0.85, y: 0.9)]
        for (i, color) in colors.prefix(4).enumerated() {
            let layer = CAGradientLayer()
            layer.type = .radial
            layer.colors = [color.withAlphaComponent(0.9).cgColor, color.withAlphaComponent(0).cgColor]
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            let a = anchors[i % anchors.count]
            let from = CGPoint(x: bounds.width * a.x, y: bounds.height * a.y)
            layer.position = from
            self.layer.addSublayer(layer)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: from)
            move.toValue = NSValue(cgPoint: CGPoint(x: bounds.width * (1 - a.x), y: bounds.height * (1 - a.y)))
            move.duration = 9 + Double(i) * 2.5
            move.autoreverses = true
            move.repeatCount = .infinity
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(move, forKey: "drift")
            blobs.append(layer)
        }
    }
}

enum LyricsPalette {
    /// Bốn màu lấy từ bốn góc của bìa, làm đậm/sáng cho hợp nền.
    static func colors(from image: UIImage, dark: Bool) -> [UIColor] {
        guard let cg = image.cgImage else { return [] }
        let w = cg.width / 2, h = cg.height / 2
        var out: [UIColor] = []
        for (x, y) in [(0, 0), (w, 0), (0, h), (w, h)] {
            if let part = cg.cropping(to: CGRect(x: x, y: y, width: w, height: h)),
               let avg = UIImage(cgImage: part).averageColor() {
                out.append(dark ? avg.mixed(with: UIColor.black, amount: 0.2) : avg.mixed(with: UIColor.white, amount: 0.2))
            }
        }
        return out
    }
}
