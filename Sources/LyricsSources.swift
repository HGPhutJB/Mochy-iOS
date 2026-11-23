import Foundation

/// HTTP đồng bộ nhỏ cho các nguồn lời (chỉ gọi từ luồng nền).
enum LyricsHTTP {
    static let browserUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 9
        c.timeoutIntervalForResource = 14
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    static func fetch(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) -> (data: Data?, status: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        var status = 0
        session.dataTask(with: request) { data, response, _ in
            out = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            sem.signal()
        }.resume()
        sem.wait()
        return (out, status)
    }

    static func json(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) -> Any? {
        let r = fetch(url, method: method, headers: headers, body: body)
        guard r.status == 200, let data = r.data else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    static func text(_ url: URL, headers: [String: String] = [:]) -> String? {
        let r = fetch(url, headers: headers)
        guard r.status == 200, let data = r.data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func url(_ base: String, _ items: [(String, String)]) -> URL? {
        guard var c = URLComponents(string: base) else { return nil }
        c.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        // URLComponents không mã hoá dấu "+" trong giá trị; tự mã hoá để không bị đổi thành khoảng trắng.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }

    static func form(_ items: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let text = items.map { k, v in
            (k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k) + "=" + (v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)
        }.joined(separator: "&")
        return Data(text.utf8)
    }

    static func number(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String, let d = Double(s) { return d }
        return 0
    }

    static func unescape(_ text: String) -> String {
        var t = text
        for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#x27;", "'"), ("&#39;", "'"),
                       ("&nbsp;", " "), ("&#10;", "\n"), ("&#13;", "")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }
}

/// Đọc TTML kiểu Apple Music (BiniLyrics, Unison): từng dòng `<p begin end>` và từng chữ `<span begin end>`.
final class TTMLParser: NSObject, XMLParserDelegate {
    private(set) var lines: [LyricLine] = []
    private var inP = false
    private var pBegin: Double?
    private var words: [LyricWord] = []
    private var loose = ""
    private var stack: [(skip: Bool, word: Bool)] = []
    private var spanStart = 0.0
    private var spanEnd = 0.0
    private var spanText = ""

    static func parse(_ text: String) -> [LyricLine] {
        let parser = XMLParser(data: Data(text.utf8))
        let delegate = TTMLParser()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.lines.sorted { $0.time < $1.time }
    }

    static func time(_ raw: String?) -> Double? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasSuffix("ms"), let v = Double(s.dropLast(2)) { return v / 1000 }
        if s.hasSuffix("s") { s = String(s.dropLast()) }
        let parts = s.split(separator: ":").map(String.init)
        var total = 0.0
        for p in parts {
            guard let v = Double(p) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    private func local(_ name: String) -> String {
        if let i = name.lastIndex(of: ":") { return String(name[name.index(after: i)...]) }
        return name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = local(elementName)
        func attr(_ key: String) -> String? {
            return attributeDict[key] ?? attributeDict.first { local($0.key) == key }?.value
        }
        if name == "p" {
            inP = true
            pBegin = TTMLParser.time(attr("begin"))
            words = []
            loose = ""
            stack = []
        } else if name == "span" && inP {
            let role = attr("role") ?? ""
            let parentSkip = stack.contains { $0.skip }
            let skip = parentSkip || role == "x-bg" || role.hasPrefix("x-translation") || role.hasPrefix("x-roman")
            let hasWordAncestor = stack.contains { $0.word }
            let begin = TTMLParser.time(attr("begin"))
            let isWord = !skip && !hasWordAncestor && begin != nil
            stack.append((skip, isWord))
            if isWord {
                spanStart = begin ?? 0
                spanEnd = TTMLParser.time(attr("end")) ?? (spanStart + 0.3)
                spanText = ""
                if !loose.isEmpty, var last = words.last, loose.rangeOfCharacter(from: .whitespacesAndNewlines) != nil, !last.text.hasSuffix(" ") {
                    last = LyricWord(text: last.text + " ", start: last.start, end: last.end)
                    words[words.count - 1] = last
                }
                loose = ""
            }
        } else if name == "br" && inP && stack.isEmpty {
            loose += " "
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inP else { return }
        if stack.contains(where: { $0.skip }) { return }
        if stack.contains(where: { $0.word }) { spanText += string } else { loose += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = local(elementName)
        if name == "span" && inP, let top = stack.popLast(), top.word {
            if !spanText.isEmpty { words.append(LyricWord(text: spanText, start: spanStart, end: max(spanEnd, spanStart + 0.05))) }
        } else if name == "p" && inP {
            inP = false
            var text: String
            var lineWords: [LyricWord] = []
            if words.isEmpty {
                text = loose.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                text = words.map { $0.text }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                lineWords = words
                if let last = lineWords.last {
                    lineWords[lineWords.count - 1] = LyricWord(text: last.text.trimmingCharacters(in: .whitespaces), start: last.start, end: last.end)
                }
            }
            guard let t = pBegin ?? words.first?.start, !text.isEmpty else { return }
            var line = LyricLine(time: t, text: text)
            line.words = lineWords
            lines.append(line)
        }
    }
}

extension LyricsService {
    // MARK: - Tiện ích chung

    fileprivate static func titleLike(_ a: String, _ b: String) -> Bool {
        let x = SongMatcher.normalize(SongMatcher.cleanTitle(a)), y = SongMatcher.normalize(SongMatcher.cleanTitle(b))
        if x.isEmpty || y.isEmpty { return false }
        if x == y || x.contains(y) || y.contains(x) { return true }
        let tx = Set(x.split(separator: " ")), ty = Set(y.split(separator: " "))
        return Double(tx.intersection(ty).count) / Double(max(tx.count, ty.count)) >= 0.6
    }

    fileprivate static func fits(_ lines: [LyricLine], duration: Double) -> Bool {
        guard duration > 0, let last = lines.last else { return true }
        return last.time <= duration + 12
    }

    fileprivate static func dropCredits(_ lines: [LyricLine]) -> [LyricLine] {
        var out = lines
        let credit = "(作词|作詞|作曲|编曲|編曲|制作|製作|词|曲|lyricist|composer|arranger|producer|lyrics by|music by|written by|词：|曲：)"
        var n = 0
        while n < min(out.count, 8), out[n].text.range(of: "^\\s*" + credit + "\\s*[:：]", options: [.regularExpression, .caseInsensitive]) != nil { n += 1 }
        out.removeFirst(n)
        return out
    }

    private static func build(_ lines: [LyricLine], plain: String? = nil, source: String, duration: Double) -> LyricsResult? {
        let sorted = lines.sorted { $0.time < $1.time }
        if !sorted.isEmpty && fits(sorted, duration: duration) {
            return LyricsResult(synced: sorted, plain: plain, source: source)
        }
        if let plain = plain, !plain.isEmpty { return LyricsResult(synced: [], plain: plain, source: source) }
        return nil
    }

    // MARK: - 1. Spicy Lyrics (cần API key riêng, nhập trong Cài đặt)

    func fromSpicyLyrics(_ song: Song, duration: Double) -> LyricsResult? {
        let key = (UserDefaults.standard.string(forKey: "spicy.key") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let headers = ["Authorization": "Bearer " + key, "Accept": "application/json"]
        let title = LyricsService.cleanTitle(song.title)
        let artist = LyricsService.cleanArtist(song.artist)
        var items = [("title", title), ("artist", artist)]
        if duration > 0 { items.append(("duration", String(format: "%.3f", duration))) }
        guard let searchURL = LyricsHTTP.url("https://api.spicylyrics.org/v1/tracks/search", items),
              let found = LyricsHTTP.json(searchURL, headers: headers) as? [String: Any] else { return nil }
        let body = (found["Body"] as? [String: Any]) ?? found
        guard let results = body["results"] as? [[String: Any]] else { return nil }
        let pick = results.first { ($0["tier"] as? String) == "exact" } ?? results.first { ($0["tier"] as? String) == "likely" }
        guard let id = pick?["id"] as? String, let url = URL(string: "https://api.spicylyrics.org/v1/lyrics/" + id),
              let json = LyricsHTTP.json(url, headers: headers) as? [String: Any] else { return nil }
        let data = (json["Body"] as? [String: Any]) ?? json
        let type = (data["Type"] as? String) ?? ""
        var credit = "Spicy Lyrics"
        if let a = data["UploadAttribution"] as? [String: Any], let who = (a["Maker"] ?? a["Uploader"]) as? String, !who.isEmpty {
            credit += " · " + who
        }
        let content = (data["Content"] as? [[String: Any]]) ?? (data["Lines"] as? [[String: Any]]) ?? []
        var lines: [LyricLine] = []
        var plainLines: [String] = []
        for item in content {
            if let lead = item["Lead"] as? [String: Any], let syl = lead["Syllables"] as? [[String: Any]] {
                var words: [LyricWord] = []
                for s in syl {
                    guard let t = s["Text"] as? String else { continue }
                    let st = LyricsHTTP.number(s["StartTime"]), en = LyricsHTTP.number(s["EndTime"])
                    let part = (s["IsPartOfWord"] as? Bool) ?? false
                    words.append(LyricWord(text: part ? t : t + " ", start: st, end: max(en, st + 0.05)))
                }
                guard let first = words.first else { continue }
                let text = words.map { $0.text }.joined().trimmingCharacters(in: .whitespaces)
                var line = LyricLine(time: first.start, text: text)
                var w = words
                if let last = w.last { w[w.count - 1] = LyricWord(text: last.text.trimmingCharacters(in: .whitespaces), start: last.start, end: last.end) }
                line.words = w
                lines.append(line)
            } else if let text = item["Text"] as? String {
                if type == "Static" || item["StartTime"] == nil {
                    plainLines.append(text)
                } else {
                    lines.append(LyricLine(time: LyricsHTTP.number(item["StartTime"]), text: text))
                }
            }
        }
        let plain = plainLines.isEmpty ? nil : plainLines.joined(separator: "\n")
        return LyricsService.build(lines, plain: plain, source: credit, duration: duration)
    }

    // MARK: - 2. BiniLyrics (TTML theo ISRC, lấy ISRC từ Deezer)

    func fromBiniLyrics(_ song: Song, duration: Double) -> LyricsResult? {
        guard let isrc = LyricsService.isrc(for: song, duration: duration) else { return nil }
        for base in ["https://lyrics-storage.binimum.org/", "https://lrc.red/s/"] {
            guard let url = URL(string: base + isrc + ".ttml"), let xml = LyricsHTTP.text(url) else { continue }
            let lines = TTMLParser.parse(xml)
            if let r = LyricsService.build(lines, source: "BiniLyrics", duration: duration) { return r }
        }
        return nil
    }

    private static let isrcLock = NSLock()
    private static var isrcCache: [String: String] = [:]

    /// Tìm mã ISRC của bài qua Deezer (khớp độ dài trong 6 giây).
    static func isrc(for song: Song, duration: Double) -> String? {
        isrcLock.lock(); let hit = isrcCache[song.videoId]; isrcLock.unlock()
        if let hit = hit { return hit.isEmpty ? nil : hit }
        let title = cleanTitle(song.title), artist = cleanArtist(song.artist)
        var found: String?
        if let url = LyricsHTTP.url("https://api.deezer.com/search", [("q", "track:\"\(title)\" artist:\"\(artist)\""), ("limit", "6")]),
           let json = LyricsHTTP.json(url) as? [String: Any], let list = json["data"] as? [[String: Any]] {
            for item in list {
                let d = LyricsHTTP.number(item["duration"])
                if duration > 0 && d > 0 && abs(d - duration) > 6 { continue }
                guard let name = item["title"] as? String, titleLike(name, title), let id = item["id"] as? Int,
                      let u2 = URL(string: "https://api.deezer.com/track/\(id)"),
                      let detail = LyricsHTTP.json(u2) as? [String: Any], let code = detail["isrc"] as? String, !code.isEmpty else { continue }
                found = code
                break
            }
        }
        isrcLock.lock(); isrcCache[song.videoId] = found ?? ""; isrcLock.unlock()
        return found
    }

    // MARK: - 3. Musixmatch (token ẩn danh của app Android)

    private static let mxmLock = NSLock()

    private func musixmatchToken(forceNew: Bool = false) -> String? {
        LyricsService.mxmLock.lock(); defer { LyricsService.mxmLock.unlock() }
        let d = UserDefaults.standard
        if !forceNew, let t = d.string(forKey: "mxm.token"), Date().timeIntervalSince1970 - d.double(forKey: "mxm.time") < 3600 { return t }
        let guid = d.string(forKey: "mxm.guid") ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        d.set(guid, forKey: "mxm.guid")
        for (host, app) in [("apic.musixmatch.com", "android-player-v1.0"), ("apic-appmobile.musixmatch.com", "mac-ios-v2.0")] {
            guard let url = LyricsHTTP.url("https://\(host)/ws/1.1/token.get",
                                           [("app_id", app), ("guid", guid), ("format", "json"), ("t", String(Int(Date().timeIntervalSince1970 * 1000)))]),
                  let json = LyricsHTTP.json(url, headers: ["Accept-Language": "en"]) as? [String: Any],
                  let body = (json["message"] as? [String: Any])?["body"] as? [String: Any],
                  let token = body["user_token"] as? String, token.count > 8,
                  Set(token).count > 3 else { continue }
            d.set(token, forKey: "mxm.token")
            d.set(host, forKey: "mxm.host")
            d.set(app, forKey: "mxm.app")
            d.set(Date().timeIntervalSince1970, forKey: "mxm.time")
            return token
        }
        return nil
    }

    func fromMusixmatch(_ song: Song, duration: Double) -> LyricsResult? {
        let title = LyricsService.cleanTitle(song.title), artist = LyricsService.cleanArtist(song.artist)
        for attempt in 0..<2 {
            guard let token = musixmatchToken(forceNew: attempt == 1) else { return nil }
            let d = UserDefaults.standard
            let host = d.string(forKey: "mxm.host") ?? "apic.musixmatch.com"
            let app = d.string(forKey: "mxm.app") ?? "android-player-v1.0"
            var items: [(String, String)] = [("format", "json"), ("namespace", "lyrics_richsynched"), ("subtitle_format", "lrc"),
                                             ("optional_calls", "track.richsync"), ("app_id", app), ("usertoken", token),
                                             ("q_track", title), ("q_artist", artist)]
            if duration > 0 { items.append(("q_duration", String(Int(duration.rounded())))); items.append(("f_subtitle_length", String(Int(duration.rounded())))) }
            guard let url = LyricsHTTP.url("https://\(host)/ws/1.1/macro.subtitles.get", items),
                  let json = LyricsHTTP.json(url, headers: ["Accept-Language": "en"]) as? [String: Any],
                  let message = json["message"] as? [String: Any] else { continue }
            if let header = message["header"] as? [String: Any], (header["status_code"] as? Int) == 401 { continue }
            guard let body = message["body"] as? [String: Any], let calls = body["macro_calls"] as? [String: Any] else { continue }
            func inner(_ key: String) -> [String: Any]? {
                return (((calls[key] as? [String: Any])?["message"] as? [String: Any])?["body"]) as? [String: Any]
            }
            // Chống kết quả giả (token hỏng thường trả cùng một bài bất kể truy vấn).
            if let track = inner("matcher.track.get")?["track"] as? [String: Any], let name = track["track_name"] as? String,
               !LyricsService.titleLike(name, title) { return nil }
            if let rich = inner("track.richsync.get")?["richsync"] as? [String: Any], let text = rich["richsync_body"] as? String,
               let data = text.data(using: .utf8), let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: Any]] {
                var lines: [LyricLine] = []
                for entry in arr {
                    let ts = LyricsHTTP.number(entry["ts"]), te = LyricsHTTP.number(entry["te"])
                    guard let chunks = entry["l"] as? [[String: Any]], !chunks.isEmpty else { continue }
                    var words: [LyricWord] = []
                    for (i, c) in chunks.enumerated() {
                        guard let t = c["c"] as? String else { continue }
                        let start = ts + LyricsHTTP.number(c["o"])
                        var end = te
                        if i + 1 < chunks.count { end = ts + LyricsHTTP.number(chunks[i + 1]["o"]) }
                        words.append(LyricWord(text: t, start: start, end: max(end, start + 0.05)))
                    }
                    // Các mảnh là khoảng trắng riêng: ghép thành từ có dấu cách cuối.
                    var merged: [LyricWord] = []
                    for w in words {
                        if w.text.trimmingCharacters(in: .whitespaces).isEmpty, let last = merged.last {
                            merged[merged.count - 1] = LyricWord(text: last.text + " ", start: last.start, end: last.end)
                        } else {
                            merged.append(w)
                        }
                    }
                    let text = merged.map { $0.text }.joined().trimmingCharacters(in: .whitespaces)
                    if text.isEmpty { continue }
                    var line = LyricLine(time: ts, text: text)
                    line.words = merged
                    lines.append(line)
                }
                if let r = LyricsService.build(lines, source: "Musixmatch", duration: duration) { return r }
            }
            if let list = inner("track.subtitles.get")?["subtitle_list"] as? [[String: Any]],
               let sub = list.first?["subtitle"] as? [String: Any], let lrc = sub["subtitle_body"] as? String {
                var lines = LyricsService.parseLRC(lrc)
                if lines.isEmpty, let data = lrc.data(using: .utf8), let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: Any]] {
                    for e in arr {
                        if let t = e["text"] as? String, let tm = (e["time"] as? [String: Any]).map({ LyricsHTTP.number($0["total"]) }) {
                            lines.append(LyricLine(time: tm, text: t))
                        }
                    }
                }
                if let r = LyricsService.build(lines, source: "Musixmatch", duration: duration) { return r }
            }
            if let plain = (inner("track.lyrics.get")?["lyrics"] as? [String: Any])?["lyrics_body"] as? String, !plain.isEmpty {
                let cleaned = plain.components(separatedBy: "\n").filter { !$0.contains("NOT FOR COMMERCIAL USE") && !$0.hasPrefix("******") }.joined(separator: "\n")
                return LyricsResult(synced: [], plain: cleaned.trimmingCharacters(in: .whitespacesAndNewlines), source: "Musixmatch")
            }
            return nil
        }
        return nil
    }

    // MARK: - 4. Unison (Better Lyrics)

    func fromUnison(_ song: Song, duration: Double) -> LyricsResult? {
        let title = LyricsService.cleanTitle(song.title), artist = LyricsService.cleanArtist(song.artist)
        var attempts: [[(String, String)]] = [[("v", song.videoId)]]
        var byName: [(String, String)] = [("song", title), ("artist", artist)]
        if duration > 0 { byName.append(("duration", String(Int(duration.rounded())))) }
        attempts.append(byName)
        for base in ["https://unison.boidu.dev", "https://unison.betterlyrics.org"] {
            for items in attempts {
                guard let url = LyricsHTTP.url(base + "/lyrics", items),
                      let json = LyricsHTTP.json(url) as? [String: Any], (json["success"] as? Bool) != false,
                      let data = json["data"] as? [String: Any], let text = data["lyrics"] as? String, !text.isEmpty else { continue }
                let format = (data["format"] as? String) ?? ""
                if format == "ttml" || text.contains("<tt") {
                    if let r = LyricsService.build(TTMLParser.parse(text), source: "Unison", duration: duration) { return r }
                } else if format == "lrc" || text.contains("[0") {
                    if let r = LyricsService.build(LyricsService.parseLRC(text), plain: nil, source: "Unison", duration: duration) { return r }
                } else {
                    return LyricsResult(synced: [], plain: text, source: "Unison")
                }
            }
        }
        return nil
    }

    // MARK: - 5. NetEase

    func fromNetEase(_ song: Song, duration: Double) -> LyricsResult? {
        let title = LyricsService.cleanTitle(song.title), artist = LyricsService.cleanArtist(song.artist)
        let headers = ["Referer": "https://music.163.com/", "Cookie": "appver=2.0.2; os=pc", "Content-Type": "application/x-www-form-urlencoded"]
        guard let search = URL(string: "https://music.163.com/api/search/get/"),
              let json = LyricsHTTP.json(search, method: "POST", headers: headers,
                                          body: LyricsHTTP.form([("s", title + " " + artist), ("type", "1"), ("limit", "8"), ("offset", "0")])) as? [String: Any],
              let songs = (json["result"] as? [String: Any])?["songs"] as? [[String: Any]] else { return nil }
        for item in songs {
            guard let id = item["id"] as? Int, let name = item["name"] as? String, LyricsService.titleLike(name, title) else { continue }
            let ms = LyricsHTTP.number(item["duration"])
            if duration > 0 && ms > 0 && abs(ms / 1000 - duration) > 10 { continue }
            guard let url = LyricsHTTP.url("https://music.163.com/api/song/lyric", [("id", String(id)), ("lv", "-1"), ("kv", "-1"), ("tv", "-1")]),
                  let lyric = LyricsHTTP.json(url, headers: headers) as? [String: Any],
                  let lrc = (lyric["lrc"] as? [String: Any])?["lyric"] as? String, !lrc.isEmpty else { continue }
            let lines = LyricsService.dropCredits(LyricsService.parseLRC(lrc))
            if let r = LyricsService.build(lines, source: "NetEase", duration: duration) { return r }
        }
        return nil
    }

    // MARK: - 7. QQ Music

    func fromQQMusic(_ song: Song, duration: Double) -> LyricsResult? {
        let title = LyricsService.cleanTitle(song.title), artist = LyricsService.cleanArtist(song.artist)
        let headers = ["Referer": "https://y.qq.com/portal/player.html", "Origin": "https://y.qq.com"]
        var candidates: [(mid: String, name: String, seconds: Double)] = []
        let payload: [String: Any] = ["search": ["method": "DoSearchForQQMusicDesktop", "module": "music.search.SearchCgiService",
                                                 "param": ["num_per_page": 8, "page_num": 1, "query": title + " " + artist, "search_type": 0]]]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []), let text = String(data: data, encoding: .utf8),
           let url = LyricsHTTP.url("https://u.y.qq.com/cgi-bin/musicu.fcg", [("data", text)]),
           let json = LyricsHTTP.json(url, headers: headers) as? [String: Any],
           let list = ((((json["search"] as? [String: Any])?["data"] as? [String: Any])?["body"] as? [String: Any])?["song"] as? [String: Any])?["list"] as? [[String: Any]] {
            for s in list {
                if let mid = s["mid"] as? String, let name = s["name"] as? String { candidates.append((mid, name, LyricsHTTP.number(s["interval"]))) }
            }
        }
        if candidates.isEmpty,
           let url = LyricsHTTP.url("https://c.y.qq.com/soso/fcgi-bin/client_search_cp",
                                    [("format", "json"), ("platform", "h5"), ("w", title + " " + artist), ("t", "0"), ("n", "8"), ("p", "1"), ("remoteplace", "txt.mqq.all")]),
           let json = LyricsHTTP.json(url, headers: headers) as? [String: Any],
           let list = ((json["data"] as? [String: Any])?["song"] as? [String: Any])?["list"] as? [[String: Any]] {
            for s in list {
                if let mid = s["songmid"] as? String, let name = s["songname"] as? String { candidates.append((mid, name, LyricsHTTP.number(s["interval"]))) }
            }
        }
        for c in candidates where LyricsService.titleLike(c.name, title) {
            if duration > 0 && c.seconds > 0 && abs(c.seconds - duration) > 10 { continue }
            guard let url = LyricsHTTP.url("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",
                                           [("songmid", c.mid), ("format", "json"), ("nobase64", "1"), ("g_tk", "5381")]),
                  let r = Optional(LyricsHTTP.fetch(url, headers: headers)), r.status == 200, var text = r.data.flatMap({ String(data: $0, encoding: .utf8) }),
                  let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}") else { continue }
            text = String(text[s...e])
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [])) as? [String: Any],
                  var lrc = obj["lyric"] as? String, !lrc.isEmpty else { continue }
            if !lrc.contains("["), let raw = Data(base64Encoded: lrc), let decoded = String(data: raw, encoding: .utf8) { lrc = decoded }
            lrc = LyricsHTTP.unescape(lrc)
            let lines = LyricsService.dropCredits(LyricsService.parseLRC(lrc))
            if let result = LyricsService.build(lines, source: "QQ Music", duration: duration) { return result }
        }
        return nil
    }

    // MARK: - 9. Genius (lời thường, không đồng bộ)

    func fromGenius(_ song: Song, duration: Double) -> LyricsResult? {
        let title = LyricsService.cleanTitle(song.title), artist = LyricsService.cleanArtist(song.artist)
        guard let search = LyricsHTTP.url("https://genius.com/api/search", [("q", title + " " + artist)]),
              let json = LyricsHTTP.json(search, headers: ["Accept": "application/json"]) as? [String: Any] else { return nil }
        var hits = ((json["response"] as? [String: Any])?["hits"] as? [[String: Any]]) ?? []
        if hits.isEmpty, let sections = (json["response"] as? [String: Any])?["sections"] as? [[String: Any]] {
            hits = sections.flatMap { ($0["hits"] as? [[String: Any]]) ?? [] }
        }
        let wantedArtist = SongMatcher.normalize(artist)
        for hit in hits {
            guard (hit["type"] as? String) == "song", let result = hit["result"] as? [String: Any],
                  let name = result["title"] as? String, let link = result["url"] as? String,
                  LyricsService.titleLike(name, title), !link.lowercased().contains("translation"), !link.lowercased().contains("romanized"),
                  let url = URL(string: link) else { continue }
            let by = SongMatcher.normalize(((result["primary_artist"] as? [String: Any])?["name"] as? String) ?? "")
            if !wantedArtist.isEmpty, !by.isEmpty, !by.contains(wantedArtist), !wantedArtist.contains(by),
               Set(wantedArtist.split(separator: " ")).intersection(Set(by.split(separator: " "))).isEmpty { continue }
            guard let html = LyricsHTTP.text(url, headers: ["Accept": "text/html"]),
                  let plain = LyricsService.geniusLyrics(fromHTML: html) else { continue }
            return LyricsResult(synced: [], plain: plain, source: "Genius")
        }
        return nil
    }

    private static func geniusLyrics(fromHTML html: String) -> String? {
        let ns = html as NSString
        guard let marker = try? NSRegularExpression(pattern: "<div[^>]*data-lyrics-container=\"true\"[^>]*>", options: []) else { return nil }
        var parts: [String] = []
        for m in marker.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) {
            var depth = 1
            var cursor = m.range.location + m.range.length
            let start = cursor
            guard let tag = try? NSRegularExpression(pattern: "<(/?)div\\b[^>]*>", options: []) else { return nil }
            let rest = NSRange(location: cursor, length: ns.length - cursor)
            var end = ns.length
            for t in tag.matches(in: html, options: [], range: rest) {
                depth += ns.substring(with: t.range(at: 1)).isEmpty ? 1 : -1
                if depth == 0 { end = t.range.location; break }
                cursor = t.range.location + t.range.length
            }
            var chunk = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
            chunk = chunk.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            chunk = chunk.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            parts.append(LyricsHTTP.unescape(chunk))
        }
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
