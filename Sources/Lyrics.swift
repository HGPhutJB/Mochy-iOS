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

    /// Lời đang có trong bộ nhớ (không gọi mạng), dùng cho màn hình thông tin bài.
    func cached(_ videoId: String) -> LyricsResult? {
        lock.lock(); defer { lock.unlock() }
        return cache[videoId]
    }

    func lyrics(for song: Song, durationHint: Double, completion: @escaping (LyricsResult?) -> Void) {
        lock.lock()
        let hit = cache[song.videoId]
        let known = missed.contains(song.videoId)
        lock.unlock()
        if let hit = hit { completion(hit); return }
        // Bài đã tải kèm lời thì dùng lời đã lưu (nghe offline vẫn có lời).
        if let stored = DownloadStore.lyrics(song.videoId) {
            lock.lock(); cache[song.videoId] = stored; lock.unlock()
            completion(stored)
            return
        }
        if known { completion(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let duration = durationHint > 0 ? durationHint : LyricsService.seconds(song.duration)
            // Hỏi song song cả 10 nguồn, chọn bản tốt nhất: đồng bộ từng chữ > từng dòng > lời thường.
            let sources: [(String, Int, () -> LyricsResult?)] = [
                ("Spicy Lyrics", 0, { self.fromSpicyLyrics(song, duration: duration) }),
                ("BiniLyrics", 1, { self.fromBiniLyrics(song, duration: duration) }),
                ("Musixmatch", 2, { self.fromMusixmatch(song, duration: duration) }),
                ("Unison", 3, { self.fromUnison(song, duration: duration) }),
                ("YouLy+", 4, { self.fromYouLyPlus(song, duration: duration) }),
                ("SimpMusic", 5, { self.fromSimpMusic(song) }),
                ("NetEase", 6, { self.fromNetEase(song, duration: duration) }),
                ("LRCLIB", 7, { self.fromLRCLIB(song, duration: duration) }),
                ("QQ Music", 8, { self.fromQQMusic(song, duration: duration) }),
                ("KuGou", 9, { self.fromKuGou(song, duration: duration) }),
                ("Genius", 10, { self.fromGenius(song, duration: duration) })
            ]
            let resultLock = NSLock()
            var found: [(Int, LyricsResult)] = []
            let group = DispatchGroup()
            let early = DispatchSemaphore(value: 0)
            let queue = DispatchQueue(label: "mochyios.lyrics.fetch", attributes: .concurrent)
            for (_, order, run) in sources {
                group.enter()
                queue.async {
                    if let r = run() {
                        resultLock.lock(); found.append((order, r)); resultLock.unlock()
                        if r.synced.contains(where: { !$0.words.isEmpty }) { early.signal() }
                    }
                    group.leave()
                }
            }
            group.notify(queue: queue) { early.signal() }
            // Có bản đồng bộ từng chữ thì dừng đợi ngay; không thì đợi đủ các nguồn (tối đa 16 giây).
            _ = early.wait(timeout: .now() + 16)
            resultLock.lock()
            let snapshot = found
            resultLock.unlock()
            func rank(_ r: LyricsResult) -> Int {
                if r.synced.contains(where: { !$0.words.isEmpty }) { return 3 }
                return r.synced.isEmpty ? 1 : 2
            }
            let best = snapshot.sorted { a, b in
                let ra = rank(a.1), rb = rank(b.1)
                return ra != rb ? ra > rb : a.0 < b.0
            }.first?.1
            self.lock.lock()
            if let best = best { self.cache[song.videoId] = best } else { self.missed.insert(song.videoId) }
            self.lock.unlock()
            // Bài đã tải mà chưa có lời lưu sẵn (tải từ bản cũ) thì lưu luôn lần đầu lấy được.
            if let best = best, Library.shared.localURL(for: song.videoId) != nil {
                DownloadStore.update(song.videoId) { if $0.lyrics == nil { $0.lyrics = best.stored } }
            }
            DispatchQueue.main.async { completion(best) }
        }
    }

    /// Lấy lời ngay khi tải xong bài và lưu cạnh tệp nhạc.
    func storeForDownload(_ song: Song, durationHint: Double) {
        lyrics(for: song, durationHint: durationHint) { result in
            guard let result = result else { return }
            DownloadStore.update(song.videoId) { $0.lyrics = result.stored }
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

    static func cleanTitle(_ title: String) -> String {
        var t = title
        let patterns = ["\\s*[\\(\\[][^\\)\\]]*(official|video|audio|lyric|visualizer|hd|hq|4k|remaster|live|mv)[^\\)\\]]*[\\)\\]]",
                        "\\s*【.*?】", "\\s*\\|.*$", "\\s*[\\(\\[]?(feat|ft)\\.?[^\\)\\]]*[\\)\\]]?$"]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive]) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func cleanArtist(_ artist: String) -> String {
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
    private let glow = UIImageView()
    private static let glowCache = NSCache<NSString, UIImage>()
    private static let glowPad: CGFloat = 32
    private let maskLayer = CAGradientLayer()
    private let edge: CGFloat
    private let total: CGFloat
    private var lastP: CGFloat = -1

    init(frame: CGRect, text: String, font: UIFont) {
        edge = max(10, frame.width * 0.4)
        total = frame.width + edge
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // Vầng sáng là ảnh chữ đã làm mờ, nằm sau chữ và không bị mặt nạ/khung nào cắt nên loang đều quanh chữ.
        let pad = WordView.glowPad
        glow.frame = CGRect(x: -pad, y: -pad, width: frame.width + 3 + pad * 2, height: frame.height + pad * 2)
        glow.image = WordView.glowImage(text: text, font: font, width: frame.width + 3, height: frame.height)
        WordView.upgradeGlow(text: text, font: font, width: frame.width + 3, height: frame.height) { [weak self] image in self?.glow.image = image }
        glow.alpha = 0
        addSubview(glow)
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
        maskLayer.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        maskLayer.locations = [0, NSNumber(value: Double(frame.width / total)), 1]
        maskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        maskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        bright.layer.mask = maskLayer
        apply(p: 0, lift: 0, force: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    private var lastLift: CGFloat = -1

    private static let glowQueue = DispatchQueue(label: "mochyios.lyrics.glow", qos: .userInitiated)
    private static let ciContext = CIContext(options: nil)

    /// Bản vầng sáng Gaussian đầy đủ, dựng ở luồng nền và thay vào khi xong (bản nhanh hiện ngay).
    private static func upgradeGlow(text: String, font: UIFont, width: CGFloat, height: CGFloat, apply: @escaping (UIImage) -> Void) {
        let key = "hq|\(text)|\(font.pointSize)|\(Int(width))" as NSString
        if let hit = glowCache.object(forKey: key) { apply(hit); return }
        glowQueue.async {
            let pad = glowPad
            let size = CGSize(width: width + pad * 2, height: height + pad * 2)
            let flat = UIGraphicsImageRenderer(size: size).image { _ in
                (text as NSString).draw(in: CGRect(x: pad, y: pad, width: width, height: height),
                                        withAttributes: [.font: font, .foregroundColor: UIColor.white])
            }
            guard let input = CIImage(image: flat), let filter = CIFilter(name: "CIGaussianBlur") else { return }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(Double(9 * flat.scale), forKey: kCIInputRadiusKey)
            guard let output = filter.outputImage, let cg = ciContext.createCGImage(output, from: input.extent) else { return }
            let image = UIImage(cgImage: cg, scale: flat.scale, orientation: .up)
            glowCache.setObject(image, forKey: key)
            DispatchQueue.main.async { apply(image) }
        }
    }

    private static func glowImage(text: String, font: UIFont, width: CGFloat, height: CGFloat) -> UIImage? {
        let key = "\(text)|\(font.pointSize)|\(Int(width))" as NSString
        if let hit = glowCache.object(forKey: key) { return hit }
        let pad = glowPad
        let size = CGSize(width: width + pad * 2, height: height + pad * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale / 4   // ảnh nhỏ, GPU phóng to = vầng sáng mềm, tạo gần như tức thì
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            (text as NSString).draw(in: CGRect(x: pad, y: pad, width: width, height: height),
                                    withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
        glowCache.setObject(image, forKey: key)
        return image
    }

    /// Cập nhật theo thời gian bài hát: tô dần từ trái sang phải; từ nổi lên nhanh khi tới lượt (ease-out)
    /// rồi hạ xuống chậm, mượt sau khi hát xong — giống Apple Music.
    func update(time: Double, start: Double, end: Double) {
        let dur = max(0.08, end - start)
        let p = CGFloat(min(1, max(0, (time - start) / dur)))
        let rise = CGFloat(min(1, max(0, (time - (start - 0.05)) / 0.32)))
        var lift = 1 - pow(1 - rise, 3)
        if time > end {
            let f = CGFloat(min(1, (time - end) / 0.7))
            lift *= 1 - f * f * (3 - 2 * f)
        }
        apply(p: p, lift: lift, force: false)
    }

    private func apply(p: CGFloat, lift: CGFloat, force: Bool) {
        if !force && abs(p - lastP) < 0.002 && abs(lift - lastLift) < 0.004 { return }
        lastP = p
        lastLift = lift
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = CGRect(x: (p - 1) * total, y: -16, width: total, height: bounds.height + 32)
        CATransaction.commit()
        glow.alpha = 0.9 * lift
        let scale = 1 + 0.075 * lift
        transform = CGAffineTransform(translationX: 0, y: -4.5 * lift).scaledBy(x: scale, y: scale)
    }
}

/// Một dòng lời: dòng đang hát to, rõ, tô dần từng từ (từ đang hát nổi lên); dòng khác thu nhỏ và làm mờ như Apple Music.
final class LyricCell: UITableViewCell {
    static var font: UIFont { return RoundedFont.font(30, index: AppSettings.lyricWeight) }
    static let inactiveScale: CGFloat = 0.78
    static let sideInset: CGFloat = 26
    static let vPad: CGFloat = 11
    static let blurPad: CGFloat = 44   // đủ rộng để vầng mờ lan hết, không bị cắt

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
    let subLabel = UILabel()
    let subBlur = UIImageView()
    private(set) var translation = ""
    private var scaleNow: CGFloat = 1
    static var translationFont: UIFont { return RoundedFont.font(17, index: 4) }
    private let wordsHost = UIView()
    private(set) var row = -1
    private var text = ""
    private var textFont = LyricCell.font
    private var words: [LyricWord] = []
    private var wordRanges: [NSRange] = []
    private var wordViews: [WordView] = []
    private var builtKey = ""
    private var shownActive = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        clipsToBounds = false
        contentView.clipsToBounds = false
        holder.layer.anchorPoint = .zero
        holder.isUserInteractionEnabled = false
        label.numberOfLines = 0
        blurView.contentMode = .scaleToFill
        contentView.addSubview(holder)
        holder.addSubview(blurView)
        holder.addSubview(label)
        holder.addSubview(wordsHost)
        subLabel.numberOfLines = 0
        subLabel.alpha = 0
        subLabel.isHidden = true
        contentView.addSubview(subLabel)
        subBlur.contentMode = .scaleToFill
        subBlur.alpha = 0
        subBlur.isHidden = true
        contentView.addSubview(subBlur)
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
        if translation.isEmpty {
            subLabel.isHidden = true
            subBlur.isHidden = true
        } else {
            subLabel.isHidden = false
            subBlur.isHidden = false
            let th = LyricCell.measure(translation, width: w, font: LyricCell.translationFont)
            subLabel.frame = CGRect(x: LyricCell.sideInset, y: LyricCell.vPad + h * scaleNow + 2, width: w, height: th)
            subBlur.frame = subLabel.frame.insetBy(dx: -LyricCell.blurPad, dy: -LyricCell.blurPad)
        }
    }

    func configure(line: LyricLine?, text: String, row: Int, plainFont: UIFont? = nil, translation: String = "") {
        self.row = row
        self.text = text
        self.translation = translation
        subLabel.attributedText = translation.isEmpty ? nil : NSAttributedString(string: translation, attributes: LyricCell.attributes(font: LyricCell.translationFont, color: .white))
        subLabel.alpha = 0
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
        contentView.layer.removeAllAnimations()
        contentView.transform = .identity
        blurView.image = nil
        subBlur.image = nil
        subBlur.alpha = 0
        shownActive = false
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
        let key = "\(text)|\(Int(width))|\(textFont.fontName)"
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
        if scaleNow != s { scaleNow = s; setNeedsLayout() }
    }

    func showDim(image: UIImage?, alpha: CGFloat, subImage: UIImage? = nil) {
        shownActive = false
        subLabel.alpha = 0
        subBlur.image = subImage
        subBlur.alpha = alpha
        label.alpha = 0
        wordsHost.alpha = 0
        blurView.image = image
        blurView.alpha = alpha
    }

    /// Dòng đang hát: trắng rõ; có thời gian từng từ thì mỗi từ tô dần và nổi lên khi tới lượt.
    func showActive(time: Double) {
        let karaoke = canKaraoke
        if !shownActive {
            shownActive = true
            subLabel.alpha = 0.85
            subBlur.alpha = 0
            blurView.alpha = 0
            label.alpha = karaoke ? 0 : 1
            wordsHost.alpha = karaoke ? 1 : 0
        }
        guard karaoke else { return }
        if wordViews.isEmpty, bounds.width > 0 { buildWordsIfNeeded(width: max(10, bounds.width - LyricCell.sideInset * 2)) }
        for (i, v) in wordViews.enumerated() where i < words.count {
            v.update(time: time, start: words[i].start, end: words[i].end)
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
/// Ba chấm báo "chưa tới lời": sáng dần theo thời gian tới dòng đầu, nhấp nhô nhẹ.
final class LyricDotsView: UIView {
    private let dots: [UIView] = (0..<3).map { _ in UIView() }
    private var dismissed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for d in dots {
            d.backgroundColor = UIColor.white
            d.layer.cornerRadius = 8
            addSubview(d)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, d) in dots.enumerated() {
            let t = d.transform
            d.transform = .identity
            d.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
            d.center = CGPoint(x: 28 + 8 + CGFloat(i) * 28, y: bounds.maxY - 14)
            d.transform = t
        }
    }

    /// progress 0...1: ba chấm sáng lần lượt; cả cụm phồng nhẹ theo nhịp thở.
    func update(progress: Double, time: Double) {
        if dismissed { dismissed = false; alpha = 1 }
        let breath = 1 + 0.08 * CGFloat(sin(time * 2.6))
        for (i, d) in dots.enumerated() {
            let fill = CGFloat(min(1, max(0, progress * 3 - Double(i))))
            d.alpha = 0.3 + 0.7 * fill
            let k = breath * (0.85 + 0.15 * fill)
            d.transform = CGAffineTransform(scaleX: k, y: k)
        }
    }

    /// Hết đoạn chờ: ba chấm co lại rồi tan đi.
    func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn, .beginFromCurrentState], animations: {
            self.alpha = 0
            for d in self.dots { d.transform = CGAffineTransform(scaleX: 0.2, y: 0.2) }
        }, completion: nil)
    }
}

final class LyricsView: UIView, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private var lines: [LyricLine] = []
    private var plain: String?
    private var current = -1
    private var userScrolledAt = Date.distantPast
    private var blurCache: [String: UIImage] = [:]
    private var heightCache: [String: CGFloat] = [:]
    private var transCache: [String: CGFloat] = [:]
    private var translations: [String] = []
    private var lastWidth: CGFloat = 0
    private static var plainFont: UIFont { return RoundedFont.font(22, index: AppSettings.lyricWeight - 1) }
    private var link: CADisplayLink?
    private let dotsView = LyricDotsView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
    private var dotsShown = false
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

    var lineTexts: [String] { return lines.map { $0.text } }

    /// Đặt (hoặc xoá, nếu nil) bản dịch cho từng dòng.
    func setTranslations(_ t: [String]?) {
        let new = (t != nil && t!.count == lines.count) ? t! : []
        if new == translations { return }
        translations = new
        heightCache.removeAll(); transCache.removeAll()
        blurCache.removeAll()
        UIView.performWithoutAnimation {
            self.table.reloadData()
            self.table.layoutIfNeeded()
        }
        if current >= 0 { scrollToCurrent(animated: false) }
    }

    func showLoading() { set(lines: [], plain: nil, message: "Đang tìm lời…") }

    func show(_ result: LyricsResult?) {
        guard let r = result else { set(lines: [], plain: nil, message: "Không tìm thấy lời bài hát này"); return }
        set(lines: r.synced, plain: r.synced.isEmpty ? r.plain : nil, message: nil)
    }

    private func set(lines: [LyricLine], plain: String?, message: String?) {
        self.lines = lines
        self.plain = plain
        translations = []
        current = -1
        blurCache.removeAll()
        heightCache.removeAll(); transCache.removeAll()
        statusLabel.text = message
        statusLabel.isHidden = message == nil
        dotsShown = false
        if let first = lines.first, first.time > 1.5 {
            dotsShown = true
            dotsView.alpha = 1
            dotsView.frame = CGRect(x: 0, y: 0, width: max(1, table.bounds.width), height: 44)
            table.tableHeaderView = dotsView
        } else {
            table.tableHeaderView = nil
        }
        table.reloadData()
        table.contentOffset = CGPoint(x: 0, y: -table.contentInset.top)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(table.bounds.width - lastWidth) > 0.5 && table.bounds.width > 0 {
            lastWidth = table.bounds.width
            heightCache.removeAll(); transCache.removeAll()
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
            if lines[mid].time <= time + 0.35 { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        if idx != current {
            changeCurrent(to: idx, time: time)
        }
        if dotsShown {
            if idx < 0 {
                dotsView.alpha = 1
                dotsView.update(progress: time / max(0.5, lines[0].time), time: time)
            } else {
                dotsView.dismiss()
            }
        }
        if current >= 0, let cell = table.cellForRow(at: IndexPath(row: current, section: 0)) as? LyricCell {
            cell.showActive(time: time)
        }
    }

    /// Đổi dòng đang hát: các dòng trượt về chỗ mới theo kiểu "sóng" — dòng càng xa phía dưới càng trễ,
    /// mỗi dòng chuyển bằng lò xo nên chuyển động mượt, không cứng.
    private func changeCurrent(to idx: Int, time: Double) {
        let follow = idx >= 0 && Date().timeIntervalSince(userScrolledAt) > 3
        var oldY: [Int: CGFloat] = [:]
        for case let cell as LyricCell in table.visibleCells where cell.row >= 0 {
            oldY[cell.row] = cell.frame.minY - table.contentOffset.y
        }
        current = idx
        UIView.performWithoutAnimation {
            self.table.beginUpdates()
            self.table.endUpdates()
            if follow { self.table.contentOffset = CGPoint(x: 0, y: self.targetOffset()) }
            self.table.layoutIfNeeded()
        }
        let cells = table.visibleCells.compactMap { $0 as? LyricCell }.filter { $0.row >= 0 }.sorted { $0.row < $1.row }
        var lastDelta: CGFloat = 0
        for cell in cells {
            let newY = cell.frame.minY - table.contentOffset.y
            let delta = oldY[cell.row].map { $0 - newY } ?? lastDelta
            lastDelta = delta
            cell.contentView.layer.removeAllAnimations()
            cell.contentView.transform = CGAffineTransform(translationX: 0, y: delta)
            let rank = idx >= 0 && cell.row > idx ? min(cell.row - idx, 7) : 0
            UIView.animate(withDuration: 0.55, delay: Double(rank) * 0.028, usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                cell.contentView.transform = .identity
                self.style(cell, time: time)
            }, completion: nil)
        }
        prewarmBlur()
    }

    /// Đổi độ đậm/font: tính lại chiều cao, ảnh mờ và dựng lại các dòng.
    func reloadStyle() {
        heightCache.removeAll(); transCache.removeAll()
        blurCache.removeAll()
        table.reloadData()
        table.layoutIfNeeded()
        scrollToCurrent(animated: false)
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
        var extra: CGFloat = 0
        if indexPath.row < translations.count, !translations[indexPath.row].isEmpty {
            let tk = "\(indexPath.row)-\(Int(w))"
            if let hit = transCache[tk] {
                extra = hit
            } else {
                extra = LyricCell.measure(translations[indexPath.row], width: w, font: LyricCell.translationFont) + 6
                transCache[tk] = extra
            }
        }
        return LyricCell.vPad * 2 + base * scale + extra
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
            let tr = indexPath.row < translations.count ? translations[indexPath.row] : ""
            cell.configure(line: lines[indexPath.row], text: text.isEmpty ? "♪" : text, row: indexPath.row, translation: tr)
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
        let sub = cell.translation.isEmpty ? nil : blurred(row: cell.row, bucket: bucket, text: cell.translation, keep: cell.subBlur.image, translation: true)
        cell.showDim(image: blurred(row: cell.row, bucket: bucket, text: cell.label.text ?? "", keep: cell.blurView.image), alpha: alpha, subImage: sub)
    }

    /// Dựng sẵn ảnh mờ cho các dòng sắp đổi mức mờ (khi dòng hát chuyển 1–2 dòng tới) để lúc chuyển không bị rõ một chớp.
    private func prewarmBlur() {
        guard !lines.isEmpty, current >= 0 else { return }
        let low = max(0, current - 3), high = min(lines.count - 1, current + 9)
        guard low <= high else { return }
        for step in 1...2 {
            let target = current + step
            for r in low...high where r != target {
                let text = lines[r].text.isEmpty ? "♪" : lines[r].text
                let bucket = min(max(abs(r - target), 1), 4)
                _ = blurred(row: r, bucket: bucket, text: text, keep: nil, prewarm: true)
                if r < translations.count, !translations[r].isEmpty {
                    _ = blurred(row: r, bucket: bucket, text: translations[r], keep: nil, prewarm: true, translation: true)
                }
            }
        }
    }

    private let ciContext = CIContext(options: nil)
    private let blurQueue = DispatchQueue(label: "mochyios.lyrics.blur", qos: .userInitiated)
    private var blurPending = Set<String>()

    /// Ảnh chữ mờ: trả ngay bản làm mờ nhanh (vẽ nhỏ rồi phóng to), đồng thời dựng bản Gaussian chất lượng đầy đủ
    /// ở luồng nền rồi thay vào — hình ảnh giống hệt trước, nhưng không còn chặn luồng chính khi đổi dòng.
    private func blurred(row: Int, bucket: Int, text: String, keep: UIImage?, prewarm: Bool = false, translation: Bool = false) -> UIImage? {
        let width = max(40, table.bounds.width - LyricCell.sideInset * 2)
        let key = "\(translation ? "t" : "")\(row)-\(bucket)-\(Int(width))-\(immersive)"
        if let hit = blurCache[key] { return hit }
        let font = translation ? LyricCell.translationFont : LyricCell.font
        let attrs = LyricCell.attributes(font: font, color: .white)
        let height = LyricCell.measure(text, width: width, font: font)
        let pad = LyricCell.blurPad
        let size = CGSize(width: width + pad * 2, height: height + pad * 2)
        let points: [CGFloat] = [0, 2.6, 4, 5.4, 6.8]
        let radius = points[bucket] * (immersive ? 1.5 : 1.0) * (translation ? 0.75 : 1.0)
        func drawFlat(scale: CGFloat) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                (text as NSString).draw(with: CGRect(x: pad, y: pad, width: width, height: height),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            }
        }
        let hasOld = keep != nil && !prewarm
        let fast: UIImage? = hasOld ? keep : (prewarm ? nil : drawFlat(scale: UIScreen.main.scale / max(3, radius * 1.7)))
        if !blurPending.contains(key) {
            blurPending.insert(key)
            let screenScale = UIScreen.main.scale
            blurQueue.async { [weak self] in
                guard let self = self else { return }
                let flat = drawFlat(scale: screenScale)
                guard let input = CIImage(image: flat), let filter = CIFilter(name: "CIGaussianBlur") else { return }
                filter.setValue(input, forKey: kCIInputImageKey)
                filter.setValue(Double(radius * screenScale), forKey: kCIInputRadiusKey)
                guard let output = filter.outputImage, let cg = self.ciContext.createCGImage(output, from: input.extent) else { return }
                let image = UIImage(cgImage: cg, scale: screenScale, orientation: .up)
                DispatchQueue.main.async {
                    self.blurPending.remove(key)
                    self.blurCache[key] = image
                    if let cell = self.table.visibleCells.compactMap({ $0 as? LyricCell }).first(where: { $0.row == row }), row != self.current {
                        self.style(cell, time: PlayerEngine.shared.livePosition)
                    }
                }
            }
        }
        return fast
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !lines.isEmpty else { return }
        userScrolledAt = .distantPast
        onSeek?(lines[indexPath.row].time)
    }
}

/// Nền gradient từ màu của bìa: vài đốm màu mềm (gradient tròn) trôi chậm trên nền tối, không còn các lớp ảnh mờ xoay.
final class FluidBackgroundView: UIView {
    private var blobs: [CALayer] = []
    private let shade = CAGradientLayer()
    private var palette: [UIColor] = []
    private var token = 0
    private let reveal = CAGradientLayer()
    enum Reveal { case hidden, band, full }
    private(set) var revealState: Reveal = .full
    private var revealToken = 0
    // vị trí tương đối và biên độ trôi của từng đốm màu
    // (tâm quỹ đạo, bán kính quỹ đạo theo tỉ lệ màn hình, thời gian một vòng, quay ngược?)
    private let spots: [(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat, seconds: Double, reverse: Bool)] = [
        (0.22, 0.20, 0.36, 0.20, 7.5, false), (0.80, 0.30, 0.34, 0.22, 9, true), (0.24, 0.76, 0.38, 0.20, 8.5, true),
        (0.78, 0.82, 0.36, 0.20, 10, false), (0.52, 0.48, 0.40, 0.28, 12, false), (0.50, 0.12, 0.44, 0.14, 11, true)
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = UIColor(white: 0.07, alpha: 1)
        for _ in spots {
            // Đốm màu là ảnh có sẵn (nhẹ hơn nhiều so với gradient tròn vẽ lại mỗi khung hình).
            let g = CALayer()
            g.contentsGravity = .resize
            g.magnificationFilter = .linear
            layer.addSublayer(g)
            blobs.append(g)
        }
        shade.colors = [UIColor(white: 0, alpha: 0.1).cgColor, UIColor(white: 0, alpha: 0.0).cgColor, UIColor(white: 0, alpha: 0.42).cgColor]
        shade.locations = [0, 0.4, 1]
        layer.addSublayer(shade)
        reveal.startPoint = CGPoint(x: 0.5, y: 0)
        reveal.endPoint = CGPoint(x: 0.5, y: 1)
        applyRevealModel(.full)
    }

    /// Mặt nạ cao hơn khung 48pt mỗi đầu để khi "thở" (dịch lên xuống) không để hở mép trên/dưới (vệt xám chỗ thanh home).
    private static let maskExtra: CGFloat = 48

    private func mapped(_ fraction: CGFloat) -> NSNumber {
        let h = max(bounds.height, 1)
        return NSNumber(value: Double((fraction * h + FluidBackgroundView.maskExtra) / (h + 2 * FluidBackgroundView.maskExtra)))
    }

    private func revealValues(_ state: Reveal) -> (colors: [CGColor], locations: [NSNumber]) {
        switch state {
        case .hidden:
            return ([UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0).cgColor], [mapped(0.98), mapped(1)])
        case .band:
            return ([UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.95).cgColor], [mapped(0.36), mapped(0.68)])
        case .full:
            return ([UIColor(white: 0, alpha: 1).cgColor, UIColor(white: 0, alpha: 1).cgColor], [0, 0.001])
        }
    }

    private func applyRevealModel(_ state: Reveal) {
        let v = revealValues(state)
        reveal.colors = v.colors
        reveal.locations = v.locations
    }

    /// Phần màu phía dưới ảnh bìa/MV: cùng bảng màu với nền lời nên khi bật lời, màu nối liền, không nhảy.
    /// .band = chỉ dải dưới (khi xem bìa), .full = phủ cả màn hình (khi bật lời).
    func setReveal(_ state: Reveal, animated: Bool) {
        // Mặt nạ chỉ gắn khi cần (vẽ qua mặt nạ tốn thêm một lượt dựng hình): bỏ khi phủ kín, ẩn hẳn khi không hiện.
        revealToken += 1
        let mine = revealToken
        isHidden = false
        if state != .full { layer.mask = reveal }
        let settle = animated ? (state == .hidden ? 0.5 : 1.0) : 0
        let finish = {
            guard mine == self.revealToken else { return }
            if state == .full { self.layer.mask = nil }
            if state == .hidden { self.isHidden = true }
        }
        if settle == 0 { finish() } else { DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: finish) }
        let from = reveal.presentation() ?? reveal
        let fromColors = from.colors, fromLocations = from.locations
        reveal.removeAllAnimations()
        applyRevealModel(state)
        revealState = state
        if animated {
            let v = revealValues(state)
            let place = CABasicAnimation(keyPath: "locations")
            place.fromValue = fromLocations
            place.toValue = v.locations
            let tint = CABasicAnimation(keyPath: "colors")
            tint.fromValue = fromColors
            tint.toValue = v.colors
            let group = CAAnimationGroup()
            group.animations = [place, tint]
            group.duration = state == .hidden ? 0.45 : 0.9
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            reveal.add(group, forKey: "reveal")
        }
        // Dải màu "thở" nhẹ lên xuống khi đang ở chế độ bìa.
        reveal.removeAnimation(forKey: "breath")
        if state == .band {
            let breath = CABasicAnimation(keyPath: "transform.translation.y")
            breath.fromValue = -16
            breath.toValue = 16
            breath.duration = 6.5
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            reveal.add(breath, forKey: "breath")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = max(bounds.width, bounds.height) * 1.35
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, g) in blobs.enumerated() {
            g.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            g.position = CGPoint(x: bounds.width * spots[i].x, y: bounds.height * spots[i].y)
        }
        shade.frame = bounds
        reveal.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + 2 * FluidBackgroundView.maskExtra)
        reveal.position = CGPoint(x: bounds.midX, y: bounds.midY)
        if reveal.animation(forKey: "reveal") == nil { applyRevealModel(revealState) }
        CATransaction.commit()
        startDrifting()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { startDrifting() }
    }

    /// Cho từng đốm màu quay quanh một quỹ đạo elip rộng, vừa quay vừa phồng/xẹp (lặp vô hạn).
    private func startDrifting() {
        guard bounds.width > 0 else { return }
        for (i, g) in blobs.enumerated() where g.animation(forKey: "drift") == nil {
            let s = spots[i]
            let cx = bounds.width * s.x, cy = bounds.height * s.y
            let rx = bounds.width * s.rx, ry = bounds.height * s.ry
            let orbit = CAKeyframeAnimation(keyPath: "position")
            let oval = UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            var mirror = reflectX(cx)
            let mirrored = oval.cgPath.copy(using: &mirror) ?? oval.cgPath
            orbit.path = s.reverse ? mirrored : oval.cgPath
            orbit.duration = s.seconds
            orbit.repeatCount = .infinity
            orbit.calculationMode = .paced
            orbit.timeOffset = s.seconds * Double(i) / Double(spots.count)
            g.add(orbit, forKey: "drift")
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.7
            pulse.toValue = 1.45
            pulse.duration = s.seconds * 0.5
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            g.add(pulse, forKey: "pulse")
        }
    }

    private func reflectX(_ cx: CGFloat) -> CGAffineTransform {
        return CGAffineTransform(translationX: cx, y: 0).scaledBy(x: -1, y: 1).translatedBy(x: -cx, y: 0)
    }

    func setImage(_ image: UIImage) {
        token += 1
        let mine = token
        DispatchQueue.global(qos: .userInitiated).async {
            let colors = FluidBackgroundView.makePalette(image)
            DispatchQueue.main.async {
                guard mine == self.token else { return }
                self.apply(colors)
            }
        }
    }

    /// Lấy bốn màu nổi bật, khác nhau của bìa rồi chỉnh sao cho đậm màu nhưng đủ tối để chữ trắng đọc rõ.
    private static func makePalette(_ image: UIImage) -> [UIColor] {
        let n = 12
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var samples: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        if let cg = image.cgImage,
           let ctx = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space, bitmapInfo: info) {
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            for i in 0..<(n * n) {
                let c = UIColor(red: CGFloat(pixels[i * 4]) / 255, green: CGFloat(pixels[i * 4 + 1]) / 255,
                                blue: CGFloat(pixels[i * 4 + 2]) / 255, alpha: 1)
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                samples.append((h, s, b))
            }
        }
        if samples.isEmpty { return [UIColor(white: 0.3, alpha: 1)] }
        // điểm nổi bật: ưu tiên màu sặc sỡ, không quá tối
        let ranked = samples.sorted { ($0.s * min(1, $0.b * 1.6)) > ($1.s * min(1, $1.b * 1.6)) }
        var picked: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        for c in ranked {
            let far = picked.allSatisfy { p in
                let d = abs(p.h - c.h)
                return min(d, 1 - d) > 0.06 || abs(p.b - c.b) > 0.3
            }
            if far { picked.append(c) }
            if picked.count == 5 { break }
        }
        var i = 0
        while picked.count < 5 { picked.append(ranked[i % ranked.count]); i += 1 }
        // Giữ gần màu thật của bìa: chỉ hạ độ sáng vừa đủ cho chữ trắng đọc rõ.
        return picked.map { c in
            UIColor(hue: c.h, saturation: min(1, max(0.32, c.s * 1.15)), brightness: min(0.9, max(0.4, c.b * 1.0)), alpha: 1)
        }
    }

    private static let blobCache = NSCache<NSString, UIImage>()

    private static func blobImage(_ color: UIColor) -> CGImage? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = String(format: "%.2f-%.2f-%.2f", r, g, b) as NSString
        if let hit = blobCache.object(forKey: key) { return hit.cgImage }
        let side: CGFloat = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let colors = [color.withAlphaComponent(1).cgColor, color.withAlphaComponent(0.62).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) else { return }
            let c = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: side / 2, options: [])
        }
        blobCache.setObject(image, forKey: key)
        return image.cgImage
    }

    private func apply(_ colors: [UIColor]) {
        guard !colors.isEmpty else { return }
        palette = colors
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colors[0].getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.4)
        UIView.animate(withDuration: 1.4) {
            self.backgroundColor = UIColor(hue: h, saturation: min(1, s * 0.95), brightness: max(0.2, min(0.42, b * 0.55)), alpha: 1)
        }
        for (i, g) in blobs.enumerated() {
            g.contents = FluidBackgroundView.blobImage(colors[i % colors.count])
        }
        CATransaction.commit()
    }
}
