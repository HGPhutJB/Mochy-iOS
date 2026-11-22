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

/// Một từ đang hát: hai lớp chữ (mờ + sáng), lớp sáng có mặt nạ chạy từ trái sang phải với mép mềm;
/// từ nổi nhẹ lên, phóng to một chút và phát sáng khi đang được hát.
final class WordView: UIView {
    private let dim = UILabel()
    private let bright = UILabel()
    private let maskLayer = CAGradientLayer()
    private let edge: CGFloat
    private let total: CGFloat
    private var lastP: CGFloat = -1

    init(frame: CGRect, text: String, font: UIFont) {
        edge = max(10, frame.width * 0.4)
        total = frame.width + edge
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for label in [dim, bright] {
            label.text = text
            label.font = font
            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            label.frame = CGRect(x: 0, y: 0, width: frame.width + 3, height: frame.height)
            addSubview(label)
        }
        dim.textColor = UIColor.white.withAlphaComponent(0.4)
        bright.textColor = .white
        bright.layer.shadowColor = UIColor.white.cgColor
        bright.layer.shadowOffset = .zero
        bright.layer.shadowRadius = 9
        bright.layer.shadowOpacity = 0
        maskLayer.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        maskLayer.locations = [0, NSNumber(value: Double(frame.width / total)), 1]
        maskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        maskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        bright.layer.mask = maskLayer
        setProgress(0, force: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    func setProgress(_ p: CGFloat, force: Bool = false) {
        let value = min(1, max(0, p))
        if !force && abs(value - lastP) < 0.003 { return }
        lastP = value
        let lift = value > 0 && value < 1 ? CGFloat(sin(Double(value) * Double.pi)) : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = CGRect(x: (value - 1) * total, y: -16, width: total, height: bounds.height + 32)
        bright.layer.shadowOpacity = Float(0.6 * lift)
        CATransaction.commit()
        let scale = 1 + 0.06 * lift
        transform = CGAffineTransform(translationX: 0, y: -4 * lift).scaledBy(x: scale, y: scale)
    }
}

/// Một dòng lời: dòng đang hát to, rõ, tô dần từng từ (từ đang hát nổi lên); dòng khác thu nhỏ và làm mờ như Apple Music.
final class LyricCell: UITableViewCell {
    static let font = UIFont.systemFont(ofSize: 30, weight: .heavy)
    static let inactiveScale: CGFloat = 0.62
    static let sideInset: CGFloat = 26
    static let vPad: CGFloat = 11
    static let blurPad: CGFloat = 16

    static func attributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 5
        return [.font: font, .foregroundColor: color, .paragraphStyle: p]
    }

    static func measure(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let rect = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: attributes(font: font, color: .white), context: nil)
        return ceil(rect.height) + 2
    }

    let holder = UIView()
    let label = UILabel()
    let blurView = UIImageView()
    private let wordsHost = UIView()
    private(set) var row = -1
    private var text = ""
    private var textFont = LyricCell.font
    private var words: [LyricWord] = []
    private var wordRanges: [NSRange] = []
    private var wordViews: [WordView] = []
    private var builtKey = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        holder.layer.anchorPoint = .zero
        holder.isUserInteractionEnabled = false
        label.numberOfLines = 0
        blurView.contentMode = .scaleToFill
        contentView.addSubview(holder)
        holder.addSubview(blurView)
        holder.addSubview(label)
        holder.addSubview(wordsHost)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = max(10, bounds.width - LyricCell.sideInset * 2)
        let h = LyricCell.measure(text, width: w, font: textFont)
        holder.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        holder.layer.position = CGPoint(x: LyricCell.sideInset, y: LyricCell.vPad)
        label.frame = holder.bounds
        wordsHost.frame = holder.bounds
        let pad = LyricCell.blurPad
        blurView.frame = CGRect(x: -pad, y: -pad, width: w + pad * 2, height: h + pad * 2)
        buildWordsIfNeeded(width: w)
    }

    func configure(line: LyricLine?, text: String, row: Int, plainFont: UIFont? = nil) {
        self.row = row
        self.text = text
        textFont = plainFont ?? LyricCell.font
        words = line?.words ?? []
        wordRanges = []
        if !words.isEmpty {
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
        builtKey = ""
        wordViews.forEach { $0.removeFromSuperview() }
        wordViews = []
        label.attributedText = NSAttributedString(string: text, attributes: LyricCell.attributes(font: textFont, color: .white))
        setNeedsLayout()
    }

    private var canKaraoke: Bool { return !words.isEmpty && wordRanges.count == words.count }

    /// Tính vị trí từng từ bằng đúng cách UILabel xếp chữ rồi dựng các WordView.
    private func buildWordsIfNeeded(width: CGFloat) {
        guard canKaraoke, row >= 0 else { return }
        let key = "\(text)|\(Int(width))"
        if key == builtKey { return }
        builtKey = key
        wordViews.forEach { $0.removeFromSuperview() }
        wordViews = []
        let storage = NSTextStorage(attributedString: NSAttributedString(string: text, attributes: LyricCell.attributes(font: textFont, color: .white)))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let ns = text as NSString
        for r in wordRanges {
            let glyphs = manager.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            let frame = CGRect(x: rect.minX, y: rect.minY, width: ceil(rect.width), height: textFont.lineHeight)
            let v = WordView(frame: frame, text: ns.substring(with: r), font: textFont)
            wordsHost.addSubview(v)
            wordViews.append(v)
        }
    }

    /// Dòng đang hát thì giữ cỡ lớn, các dòng khác thu nhỏ (neo ở mép trái-trên).
    func setActive(_ active: Bool) {
        let s = active || row < 0 ? 1 : LyricCell.inactiveScale
        holder.transform = CGAffineTransform(scaleX: s, y: s)
    }

    func showDim(image: UIImage?, alpha: CGFloat) {
        label.alpha = 0
        wordsHost.alpha = 0
        blurView.image = image
        blurView.alpha = alpha
    }

    /// Dòng đang hát: trắng rõ; có thời gian từng từ thì mỗi từ tô dần và nổi lên khi tới lượt.
    func showActive(time: Double) {
        blurView.alpha = 0
        guard canKaraoke else {
            label.alpha = 1
            wordsHost.alpha = 0
            return
        }
        if wordViews.isEmpty, bounds.width > 0 { buildWordsIfNeeded(width: max(10, bounds.width - LyricCell.sideInset * 2)) }
        label.alpha = 0
        wordsHost.alpha = 1
        for (i, v) in wordViews.enumerated() where i < words.count {
            let w = words[i]
            let p = (time - w.start) / max(0.08, w.end - w.start)
            v.setProgress(CGFloat(p))
        }
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

/// Khu vực hiển thị lời: cuộn mượt theo dòng đang hát, dòng khác mờ, chạm vào dòng để tua.
final class LyricsView: UIView, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private var lines: [LyricLine] = []
    private var plain: String?
    private var current = -1
    private var userScrolledAt = Date.distantPast
    private var blurCache: [String: UIImage] = [:]
    private let ciContext = CIContext(options: nil)
    private var heightCache: [String: CGFloat] = [:]
    private var lastWidth: CGFloat = 0
    private static let plainFont = UIFont.systemFont(ofSize: 22, weight: .bold)
    private var link: CADisplayLink?
    private let fadeMask = CAGradientLayer()
    var onSeek: ((Double) -> Void)?
    var onInteraction: (() -> Void)?

    /// Vị trí dòng đang hát tính theo tỉ lệ chiều cao (0.2 khi có đầu trang, 0.36 khi toàn màn hình).
    var anchorFraction: CGFloat = 0.2 {
        didSet {
            guard anchorFraction != oldValue else { return }
            setNeedsLayout()
            layoutIfNeeded()
            if current >= 0 { scrollToCurrent(animated: false) }
        }
    }

    /// Chế độ toàn màn hình: các dòng khác mờ mạnh hơn.
    var immersive = false {
        didSet {
            guard immersive != oldValue else { return }
            UIView.animate(withDuration: 0.45) {
                for case let cell as LyricCell in self.table.visibleCells { self.style(cell, time: PlayerEngine.shared.livePosition) }
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.dataSource = self
        table.delegate = self
        table.register(LyricCell.self, forCellReuseIdentifier: "line")
        table.estimatedRowHeight = 0
        table.estimatedSectionHeaderHeight = 0
        table.estimatedSectionFooterHeight = 0
        table.translatesAutoresizingMaskIntoConstraints = false
        addSubview(table)
        statusLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.6)
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
        fadeMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        layer.mask = fadeMask
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
        heightCache.removeAll()
        statusLabel.text = message
        statusLabel.isHidden = message == nil
        table.reloadData()
        table.contentOffset = CGPoint(x: 0, y: -table.contentInset.top)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(table.bounds.width - lastWidth) > 0.5 && table.bounds.width > 0 {
            lastWidth = table.bounds.width
            heightCache.removeAll()
            blurCache.removeAll()
            table.reloadData()
        }
        let top = bounds.height * anchorFraction
        let bottom = bounds.height * 0.55
        if table.contentInset.top != top || table.contentInset.bottom != bottom {
            table.contentInset = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        }
        let h = max(1, bounds.height)
        let fade = min(0.2, (immersive ? 90 : 56) / h)
        fadeMask.frame = bounds
        fadeMask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
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
            let follow = idx >= 0 && Date().timeIntervalSince(userScrolledAt) > 3
            UIView.animate(withDuration: 0.6, delay: 0, options: [.allowUserInteraction, .curveEaseInOut, .beginFromCurrentState], animations: {
                // đổi chiều cao các dòng (dòng mới to lên, dòng cũ nhỏ lại) rồi cuộn tới dòng mới
                self.table.beginUpdates()
                self.table.endUpdates()
                for case let cell as LyricCell in self.table.visibleCells { self.style(cell, time: time) }
                if follow { self.table.contentOffset = CGPoint(x: 0, y: self.targetOffset()) }
            }, completion: nil)
        }
        if current >= 0, let cell = table.cellForRow(at: IndexPath(row: current, section: 0)) as? LyricCell {
            cell.showActive(time: time)
        }
    }

    private func targetOffset() -> CGFloat {
        let rect = table.rectForRow(at: IndexPath(row: current, section: 0))
        let target = rect.minY - table.bounds.height * anchorFraction
        let minY = -table.contentInset.top
        let maxY = max(minY, table.contentSize.height - table.bounds.height + table.contentInset.bottom)
        return min(max(target, minY), maxY)
    }

    private func scrollToCurrent(animated: Bool) {
        guard current >= 0 else { return }
        let y = targetOffset()
        if animated {
            UIView.animate(withDuration: 0.7, delay: 0, options: [.allowUserInteraction, .curveEaseInOut, .beginFromCurrentState], animations: {
                self.table.contentOffset = CGPoint(x: 0, y: y)
            }, completion: nil)
        } else {
            table.contentOffset = CGPoint(x: 0, y: y)
        }
    }

    func resetFollow() { userScrolledAt = .distantPast }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { userScrolledAt = Date(); onInteraction?() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { if scrollView.isDragging { userScrolledAt = Date(); onInteraction?() } }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { userScrolledAt = Date() }

    // MARK: - Bảng

    func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !lines.isEmpty { return lines.count }
        return plain == nil ? 0 : 1
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let w = max(10, tableView.bounds.width - LyricCell.sideInset * 2)
        if lines.isEmpty {
            return LyricCell.measure(plain ?? "", width: w, font: LyricsView.plainFont) + LyricCell.vPad * 2 + 20
        }
        let key = "\(indexPath.row)-\(Int(w))"
        let base: CGFloat
        if let hit = heightCache[key] {
            base = hit
        } else {
            let t = lines[indexPath.row].text
            base = LyricCell.measure(t.isEmpty ? "♪" : t, width: w, font: LyricCell.font)
            heightCache[key] = base
        }
        let scale = indexPath.row == current ? 1 : LyricCell.inactiveScale
        return LyricCell.vPad * 2 + base * scale
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "line", for: indexPath) as? LyricCell else {
            return UITableViewCell()
        }
        if lines.isEmpty {
            cell.configure(line: nil, text: plain ?? "", row: -1, plainFont: LyricsView.plainFont)
            cell.setActive(true)
            cell.label.alpha = 1
            cell.blurView.alpha = 0
        } else {
            let text = lines[indexPath.row].text
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
            cell.setActive(true)
            cell.showActive(time: time)
            return
        }
        cell.setActive(false)
        let distance = current < 0 ? cell.row + 1 : abs(cell.row - current)
        let bucket = min(max(distance, 1), 4)
        let base: [CGFloat] = [0, 0.72, 0.6, 0.5, 0.42]
        let alpha = immersive ? base[bucket] * 0.85 : base[bucket]
        cell.showDim(image: blurred(row: cell.row, bucket: bucket, text: cell.label.text ?? ""), alpha: alpha)
    }

    private func blurred(row: Int, bucket: Int, text: String) -> UIImage? {
        let width = max(40, table.bounds.width - LyricCell.sideInset * 2)
        let key = "\(row)-\(bucket)-\(Int(width))-\(immersive)"
        if let hit = blurCache[key] { return hit }
        let ns = text as NSString
        let attrs = LyricCell.attributes(font: LyricCell.font, color: .white)
        let height = LyricCell.measure(text, width: width, font: LyricCell.font)
        let pad = LyricCell.blurPad
        let size = CGSize(width: width + pad * 2, height: height + pad * 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        let flat = renderer.image { _ in
            ns.draw(with: CGRect(x: pad, y: pad, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        }
        // Làm mờ nhẹ hơn trước (ảnh còn bị thu nhỏ ~0,62 lần khi hiển thị).
        let points: [CGFloat] = [0, 2.6, 4, 5.4, 6.8]
        let radius = Double(points[bucket] * (immersive ? 1.5 : 1.0) * flat.scale)
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

/// Nền chuyển động kiểu Apple Music: bìa làm mờ rất mạnh, nhiều lớp xoay chậm chồng lên nhau.
final class FluidBackgroundView: UIView {
    private var layers: [UIImageView] = []
    private var token = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = UIColor(white: 0.08, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    func setImage(_ image: UIImage) {
        token += 1
        let mine = token
        DispatchQueue.global(qos: .userInitiated).async {
            let blurred = FluidBackgroundView.makeBlurred(image)
            DispatchQueue.main.async {
                guard mine == self.token, let blurred = blurred else { return }
                self.apply(blurred)
            }
        }
    }

    private static func makeBlurred(_ image: UIImage) -> UIImage? {
        let side: CGFloat = 80
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let small = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
        guard let input = CIImage(image: small),
              let blur = CIFilter(name: "CIGaussianBlur"),
              let color = CIFilter(name: "CIColorControls") else { return nil }
        blur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(9.0, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return nil }
        color.setValue(blurred.cropped(to: input.extent), forKey: kCIInputImageKey)
        color.setValue(1.7, forKey: kCIInputSaturationKey)
        color.setValue(-0.04, forKey: kCIInputBrightnessKey)
        guard let out = color.outputImage,
              let cg = CIContext(options: nil).createCGImage(out, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func apply(_ image: UIImage) {
        layers.forEach { $0.removeFromSuperview() }
        layers = []
        let big = max(bounds.width, bounds.height) * 1.8
        let specs: [(alpha: CGFloat, dx: CGFloat, dy: CGFloat, start: CGFloat, seconds: Double, dir: Double)] = [
            (1.0, 0, 0, 0, 70, 1), (0.8, -0.25, 0.2, 2.1, 95, -1), (0.65, 0.25, -0.2, 4.2, 120, 1)
        ]
        for spec in specs {
            let v = UIImageView(image: image)
            v.bounds = CGRect(x: 0, y: 0, width: big, height: big)
            v.center = CGPoint(x: bounds.midX + bounds.width * spec.dx, y: bounds.midY + bounds.height * spec.dy)
            v.alpha = spec.alpha
            v.transform = CGAffineTransform(rotationAngle: spec.start)
            addSubview(v)
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = Double(spec.start)
            spin.toValue = Double(spec.start) + 2 * Double.pi * spec.dir
            spin.duration = spec.seconds
            spin.repeatCount = .infinity
            v.layer.add(spin, forKey: "spin")
            layers.append(v)
        }
    }
}
