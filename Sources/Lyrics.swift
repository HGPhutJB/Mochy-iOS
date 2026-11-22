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
                    if text.isEmpty, let syl = item["syllabus"] as? [[String: Any]] {
                        text = syl.compactMap { $0["text"] as? String }.joined()
                    }
                    lines.append(LyricLine(time: ms / 1000, text: text.trimmingCharacters(in: .whitespaces)))
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

/// Một dòng lời: nhãn rõ nét cho dòng đang hát, ảnh làm mờ cho các dòng khác (mờ dần theo khoảng cách như Apple Music).
final class LyricCell: UITableViewCell {
    let box = UIView()
    let label = UILabel()
    let blurView = UIImageView()
    private(set) var row = -1

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        box.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(box)
        label.numberOfLines = 0
        label.font = Theme.heavy(30)
        label.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentMode = .topLeft
        blurView.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        box.addSubview(blurView)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            box.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9),
            box.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            box.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: box.topAnchor),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: label.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: label.leadingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    func configure(text: String, row: Int) {
        self.row = row
        label.text = text
        label.textColor = Theme.primaryText
        blurView.image = nil
    }

    /// distance: số dòng cách dòng đang hát (0 = đang hát). Dòng chưa tới hát và đã hát đều mờ dần.
    func apply(distance: Int, blurImage: UIImage?) {
        let active = distance == 0
        let scale: CGFloat = active ? 1 : 0.9
        var t = CGAffineTransform(scaleX: scale, y: scale)
        t.tx = -(box.bounds.width / 2) * (1 - scale)
        box.transform = t
        label.alpha = active ? 1 : 0
        blurView.alpha = active ? 0 : max(0.28, 0.62 - 0.1 * CGFloat(distance - 1))
        if !active { blurView.image = blurImage }
    }
}

/// Khu vực hiển thị lời: cuộn mượt theo dòng đang hát, dòng khác làm mờ, chạm vào dòng để tua.
final class LyricsView: UIView, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private var lines: [LyricLine] = []
    private var plain: String?
    private var current = -1
    private var userScrolledAt = Date.distantPast
    private var blurCache: [String: UIImage] = [:]
    private let ciContext = CIContext(options: nil)
    var onSeek: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.dataSource = self
        table.delegate = self
        table.register(LyricCell.self, forCellReuseIdentifier: "line")
        table.estimatedRowHeight = 70
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
        blurCache.removeAll()
        statusLabel.text = message
        statusLabel.isHidden = message == nil
        table.reloadData()
        table.contentOffset = CGPoint(x: 0, y: -table.contentInset.top)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let top = bounds.height * 0.3
        let bottom = bounds.height * 0.55
        if table.contentInset.top != top {
            table.contentInset = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        }
    }

    /// Gọi theo thời gian phát; cuộn tới dòng đang hát.
    func update(time: Double) {
        guard !lines.isEmpty else { return }
        var lo = 0, hi = lines.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time + 0.2 { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard idx != current else { return }
        current = idx
        UIView.animate(withDuration: 0.4, delay: 0, options: [.allowUserInteraction, .curveEaseInOut], animations: {
            for case let cell as LyricCell in self.table.visibleCells { self.style(cell) }
        }, completion: nil)
        if idx >= 0, Date().timeIntervalSince(userScrolledAt) > 3 {
            scrollToCurrent(animated: true)
        }
    }

    private func scrollToCurrent(animated: Bool) {
        guard current >= 0 else { return }
        let path = IndexPath(row: current, section: 0)
        let rect = table.rectForRow(at: path)
        let target = rect.midY - table.bounds.height * 0.3 - 10
        let minY = -table.contentInset.top
        let maxY = max(minY, table.contentSize.height - table.bounds.height + table.contentInset.bottom)
        let y = min(max(target, minY), maxY)
        if animated {
            UIView.animate(withDuration: 0.6, delay: 0, options: [.allowUserInteraction, .curveEaseInOut, .beginFromCurrentState], animations: {
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
            cell.configure(text: plain ?? "", row: -1)
            cell.label.font = Theme.bold(20)
            cell.apply(distance: 0, blurImage: nil)
        } else {
            let text = lines[indexPath.row].text
            cell.configure(text: text.isEmpty ? "♪" : text, row: indexPath.row)
            cell.label.font = Theme.heavy(30)
            style(cell)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let c = cell as? LyricCell, !lines.isEmpty { style(c) }
    }

    private func style(_ cell: LyricCell) {
        guard cell.row >= 0 else { return }
        // Chưa có dòng nào đang hát (đầu bài): mọi dòng ở mức mờ nhẹ.
        let distance = current < 0 ? max(1, cell.row + 1) : abs(cell.row - current)
        let bucket = min(distance, 4)
        cell.apply(distance: distance, blurImage: distance == 0 ? nil : blurred(row: cell.row, bucket: bucket, cell: cell))
    }

    private func blurred(row: Int, bucket: Int, cell: LyricCell) -> UIImage? {
        let width = max(40, table.bounds.width - 40)
        let key = "\(row)-\(bucket)-\(Int(width))-\(Theme.isDark)"
        if let hit = blurCache[key] { return hit }
        let text = (cell.label.text ?? "") as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.heavy(30), .foregroundColor: Theme.primaryText]
        let rect = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        let size = CGSize(width: width, height: ceil(rect.height))
        guard size.height > 1 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        let flat = renderer.image { _ in text.draw(with: CGRect(origin: .zero, size: size), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil) }
        let radius = [0, 1.2, 2.4, 3.6, 4.8][bucket]
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
