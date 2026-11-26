import UIKit

/// Cài đặt dịch lời.
enum TranslateSettings {
    static let languages: [(code: String, name: String)] = [
        ("vi", "Tiếng Việt"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어"), ("zh-CN", "中文 (简体)"),
        ("th", "ไทย"), ("fr", "Français"), ("es", "Español"), ("id", "Bahasa Indonesia"), ("ru", "Русский")
    ]

    static var target: String {
        get { return UserDefaults.standard.string(forKey: "lyrics.translateLang") ?? "vi" }
        set { UserDefaults.standard.set(newValue, forKey: "lyrics.translateLang") }
    }

    static var enabled: Bool {
        get { return UserDefaults.standard.bool(forKey: "lyrics.translateOn") }
        set { UserDefaults.standard.set(newValue, forKey: "lyrics.translateOn") }
    }

    static var targetName: String {
        return languages.first { $0.code == target }?.name ?? target
    }
}

/// Dịch lời bài hát. Thử lần lượt: Google Translate (không chính thức) → máy chủ Mochy (Cloudflare Workers AI) → MyMemory.
/// Nguồn nào lỗi thì tự chuyển sang nguồn kế tiếp; kết quả được nhớ trên máy theo bài + ngôn ngữ.
final class LyricTranslator {
    static let shared = LyricTranslator()

    private var memory: [String: [String]] = [:]
    private var running: [String: [([String]?, String?) -> Void]] = [:]

    private var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("lyric-translations", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        return base
    }

    /// Đoán ngôn ngữ của lời theo chữ viết ("auto" nếu là chữ Latin, để dịch vụ tự nhận).
    static func detect(_ lines: [String]) -> String {
        var hangul = 0, kana = 0, han = 0, cyr = 0, thai = 0, viet = 0, latin = 0
        let vietChars = Set("ăâđêôơưàáạảãằắặẳẵầấậẩẫèéẹẻẽềếệểễìíịỉĩòóọỏõồốộổỗờớợởỡùúụủũừứựửữỳýỵỷỹ")
        for ch in lines.joined(separator: " ").lowercased() {
            for u in ch.unicodeScalars {
                switch u.value {
                case 0xAC00...0xD7AF, 0x1100...0x11FF: hangul += 1
                case 0x3040...0x30FF: kana += 1
                case 0x4E00...0x9FFF: han += 1
                case 0x0400...0x04FF: cyr += 1
                case 0x0E00...0x0E7F: thai += 1
                case 0x41...0x7A: latin += 1
                default: break
                }
            }
            if vietChars.contains(ch) { viet += 1 }
        }
        if hangul > 5 { return "ko" }
        if kana > 3 { return "ja" }
        if han > 5 { return "zh-CN" }
        if cyr > 5 { return "ru" }
        if thai > 5 { return "th" }
        if viet > 3 { return "vi" }
        return latin > 0 ? "auto" : "auto"
    }

    // MARK: - Vào/ra

    func cached(videoId: String, target: String, count: Int) -> [String]? {
        let key = videoId + "|" + target
        if let m = memory[key], m.count == count { return m }
        let file = cacheDir.appendingPathComponent(safe(videoId) + "." + safe(target) + ".json")
        if let data = try? Data(contentsOf: file), let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String], arr.count == count {
            memory[key] = arr
            return arr
        }
        return nil
    }

    private func safe(_ s: String) -> String {
        return String(s.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    /// Dịch toàn bộ các dòng. completion(kết quả, thông báo lỗi). Kết quả cùng số phần tử với `lines` (dòng không dịch được là "").
    func translate(videoId: String, lines: [String], target: String, completion: @escaping ([String]?, String?) -> Void) {
        if let hit = cached(videoId: videoId, target: target, count: lines.count) { completion(hit, nil); return }
        let key = videoId + "|" + target
        if running[key] != nil { running[key]?.append(completion); return }
        running[key] = [completion]

        let source = LyricTranslator.detect(lines)
        if source == target {
            finish(key, videoId, target, Array(repeating: "", count: lines.count), nil)
            return
        }
        // Chỉ gửi các dòng có chữ.
        var indices: [Int] = []
        var texts: [String] = []
        for (i, l) in lines.enumerated() {
            let t = l.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && t != "♪" { indices.append(i); texts.append(t) }
        }
        var chunks: [[String]] = []
        var current: [String] = []
        var chars = 0
        for t in texts {
            if !current.isEmpty && (current.count >= 30 || chars + t.count > 1500) { chunks.append(current); current = []; chars = 0 }
            current.append(t)
            chars += t.count
        }
        if !current.isEmpty { chunks.append(current) }

        var out: [String] = []
        var provider = 0
        var lastError: String?

        func next(_ i: Int) {
            if i >= chunks.count {
                var full = Array(repeating: "", count: lines.count)
                for (k, idx) in indices.enumerated() where k < out.count {
                    let original = lines[idx].trimmingCharacters(in: .whitespaces)
                    let t = out[k].trimmingCharacters(in: .whitespacesAndNewlines)
                    full[idx] = t.lowercased() == original.lowercased() ? "" : t
                }
                if out.count < texts.count { self.finish(key, videoId, target, nil, lastError ?? L("Không dịch được.")); return }
                // Còn dòng chưa dịch được thì vẫn hiện nhưng không lưu, lần sau sẽ thử dịch bù.
                let incomplete = out.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                self.finish(key, videoId, target, full, nil, store: !incomplete)
                return
            }
            self.run(chunk: chunks[i], source: source, target: target, from: provider) { result, usedProvider, error in
                if let result = result {
                    provider = usedProvider
                    out += result
                    next(i + 1)
                } else {
                    lastError = error
                    self.finish(key, videoId, target, nil, error ?? L("Không dịch được."))
                }
            }
        }
        if chunks.isEmpty { finish(key, videoId, target, Array(repeating: "", count: lines.count), nil) } else { next(0) }
    }

    private func finish(_ key: String, _ videoId: String, _ target: String, _ result: [String]?, _ error: String?, store: Bool = true) {
        if let r = result, store {
            memory[key] = r
            if let data = try? JSONSerialization.data(withJSONObject: r, options: []) {
                try? data.write(to: cacheDir.appendingPathComponent(safe(videoId) + "." + safe(target) + ".json"), options: .atomic)
            }
        }
        let callbacks = running[key] ?? []
        running[key] = nil
        for cb in callbacks { cb(result, error) }
    }

    // MARK: - Các nguồn dịch

    /// Thử từ nguồn `from` trở đi; trả về bản dịch + chỉ số nguồn đã dùng được.
    private func run(chunk: [String], source: String, target: String, from: Int, depth: Int = 0,
                     completion: @escaping ([String]?, Int, String?) -> Void) {
        let providers: [(String, ([String], String, String, @escaping ([String]?) -> Void) -> Void)] = [
            ("Google", google), ("Mochy", mochy), ("MyMemory", myMemory)
        ]
        func attempt(_ i: Int) {
            guard i < providers.count else { completion(nil, i, L("Không dịch được (các nguồn dịch đều lỗi hoặc hết lượt). Thử lại sau.")) ; return }
            providers[i].1(chunk, source, target) { result in
                guard let r = result, r.count == chunk.count else { attempt(i + 1); return }
                // Dòng nào nguồn này bỏ trống thì dịch bù bằng các nguồn khác (từng dòng một).
                var missing: [Int] = []
                for (k, t) in r.enumerated() where t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append(k) }
                if missing.isEmpty || depth > 0 { completion(r, i, nil); return }
                let sub = missing.map { chunk[$0] }
                self.run(chunk: sub, source: source, target: target, from: 0, depth: 1) { fixed, _, _ in
                    var merged = r
                    if let fixed = fixed, fixed.count == missing.count { for (n, k) in missing.enumerated() { merged[k] = fixed[n] } }
                    completion(merged, i, nil)
                }
            }
        }
        attempt(from)
    }

    private func get(_ url: URL, completion: @escaping (Any?) -> Void) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var obj: Any?
            if status == 200, let data = data { obj = try? JSONSerialization.jsonObject(with: data, options: []) }
            DispatchQueue.main.async { completion(obj) }
        }.resume()
    }

    private func googleBatch(_ lines: [String], _ source: String, _ target: String, _ done: @escaping ([String]?) -> Void) {
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"), URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target), URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: lines.joined(separator: "\n"))
        ]
        guard let url = comps.url else { done(nil); return }
        get(url) { obj in
            guard let root = obj as? [Any], let segs = root.first as? [Any] else { done(nil); return }
            var text = ""
            for s in segs { if let a = s as? [Any], let t = a.first as? String { text += t } }
            if lines.count == 1 { done([text.replacingOccurrences(of: "\n", with: " ")]); return }
            var parts = text.components(separatedBy: "\n")
            while parts.count > lines.count, parts.last?.isEmpty == true { parts.removeLast() }
            done(parts.count == lines.count ? parts : nil)
        }
    }

    /// Dịch cả cụm một lần; Google đôi khi gộp/tách dòng làm lệch số dòng, khi đó dịch từng dòng một (4 yêu cầu song song).
    private func google(_ lines: [String], _ source: String, _ target: String, _ done: @escaping ([String]?) -> Void) {
        googleBatch(lines, source, target) { result in
            if let result = result { done(result); return }
            if lines.count == 1 { done(nil); return }
            var results = Array(repeating: "", count: lines.count)
            var failed = false
            var finished = false
            var index = 0
            var active = 0
            func launch() {
                while active < 4 && index < lines.count && !failed {
                    let i = index
                    index += 1
                    active += 1
                    self.googleBatch([lines[i]], source, target) { r in
                        active -= 1
                        if let r = r?.first { results[i] = r } else { failed = true }
                        if finished { return }
                        if failed { finished = true; done(nil); return }
                        if index >= lines.count && active == 0 { finished = true; done(results); return }
                        launch()
                    }
                }
            }
            launch()
        }
    }

    private func mochy(_ lines: [String], _ source: String, _ target: String, _ done: @escaping ([String]?) -> Void) {
        MochyCloud.shared.translate(lines: lines, from: source, to: target) { result in done(result) }
    }

    private func myMemory(_ lines: [String], _ source: String, _ target: String, _ done: @escaping ([String]?) -> Void) {
        var results = Array(repeating: "", count: lines.count)
        var failed = false
        let group = DispatchGroup()
        var index = 0
        func launchNext() {
            guard index < lines.count, !failed else { return }
            let i = index
            index += 1
            group.enter()
            var comps = URLComponents(string: "https://api.mymemory.translated.net/get")!
            comps.queryItems = [URLQueryItem(name: "q", value: String(lines[i].prefix(480))),
                                URLQueryItem(name: "langpair", value: (source == "auto" ? "Autodetect" : source) + "|" + target)]
            guard let url = comps.url else { failed = true; group.leave(); return }
            get(url) { obj in
                if let o = obj as? [String: Any], let d = o["responseData"] as? [String: Any], let t = d["translatedText"] as? String,
                   (o["responseStatus"] as? Int ?? Int(o["responseStatus"] as? String ?? "") ?? 0) == 200 {
                    results[i] = t
                } else {
                    failed = true
                }
                group.leave()
                launchNext()
            }
        }
        for _ in 0..<4 { launchNext() }
        group.notify(queue: .main) { done(failed ? nil : results) }
    }
}
