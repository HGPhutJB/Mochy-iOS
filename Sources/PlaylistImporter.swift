import Foundation

/// Một bài đọc được từ Spotify / Apple Music / Deezer / SoundCloud (chưa có videoId YouTube).
struct ImportedTrack {
    let title: String
    let artist: String
    let duration: Double?   // giây, nếu nguồn có
}

struct ImportedCollection {
    var name: String
    var tracks: [ImportedTrack]
    var source: String
    var truncated: Bool = false   // nguồn chỉ cho lấy một phần (ví dụ embed Spotify tối đa 100 bài)
    var directSongs: [Song] = []  // nguồn YouTube: đã có sẵn bài, khỏi ghép
}

enum ImportSource: String {
    case spotify = "Spotify", appleMusic = "Apple Music", deezer = "Deezer", soundCloud = "SoundCloud", youtube = "YouTube Music"
}

/// Tải trang web/API bằng cách chờ (chỉ gọi từ luồng nền).
enum Web {
    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    /// Trả về dữ liệu và địa chỉ cuối cùng (sau khi chuyển hướng).
    static func get(_ url: URL, headers: [String: String] = [:]) -> (data: Data, finalURL: URL)? {
        var request = URLRequest(url: url)
        request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        request.setValue("vi,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let sem = DispatchSemaphore(value: 0)
        var out: (Data, URL)?
        session.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data {
                out = (data, http.url ?? url)
            }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    static func string(_ url: URL, headers: [String: String] = [:]) -> (text: String, finalURL: URL)? {
        guard let r = get(url, headers: headers), let text = String(data: r.data, encoding: .utf8) else { return nil }
        return (text, r.finalURL)
    }

    static func json(_ url: URL, headers: [String: String] = [:]) -> Any? {
        guard let r = get(url, headers: headers) else { return nil }
        return try? JSONSerialization.jsonObject(with: r.data, options: [])
    }

    /// Các khối <script> của trang: (thuộc tính, nội dung).
    static func scripts(_ html: String) -> [(attrs: String, body: String)] {
        guard let regex = try? NSRegularExpression(pattern: "<script([^>]*)>(.*?)</script>", options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)).map {
            (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range(at: 2)))
        }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)),
              m.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: m.range(at: 1))
    }
}

/// Đọc danh sách bài từ link của các dịch vụ nhạc, rồi ghép từng bài sang YouTube Music.
final class PlaylistImporter {
    static let shared = PlaylistImporter()

    static func source(of text: String) -> ImportSource? {
        let t = text.lowercased()
        if t.contains("spotify.com") || t.hasPrefix("spotify:") || t.contains("spotify.link") { return .spotify }
        if t.contains("music.apple.com") || t.contains("itunes.apple.com") { return .appleMusic }
        if t.contains("deezer.com") || t.contains("deezer.page.link") || t.contains("dzr.page.link") { return .deezer }
        if t.contains("soundcloud.com") || t.contains("on.soundcloud.com") { return .soundCloud }
        if t.contains("music.youtube.com") || t.contains("youtube.com") || t.contains("youtu.be") { return .youtube }
        return nil
    }

    /// Lấy URL từ đoạn văn bản dán vào (có thể kèm chữ khác).
    static func extractURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("spotify:") {
            let parts = trimmed.split(separator: ":").map(String.init)
            if parts.count >= 3 { return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])") }
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = trimmed as NSString
            if let match = detector.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length)), let url = match.url {
                return url
            }
        }
        return URL(string: trimmed)
    }

    // MARK: - Đọc link

    func fetch(_ url: URL, completion: @escaping (Result<ImportedCollection, UpdateError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.fetchSync(url)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func fetchSync(_ original: URL) -> Result<ImportedCollection, UpdateError> {
        guard let source = PlaylistImporter.source(of: original.absoluteString) else {
            return .failure(UpdateError(L("Link này chưa được hỗ trợ. Hỗ trợ: Spotify, Apple Music, Deezer, SoundCloud, YouTube Music.")))
        }
        switch source {
        case .spotify: return spotify(original)
        case .appleMusic: return appleMusic(original)
        case .deezer: return deezer(original)
        case .soundCloud: return soundCloud(original)
        case .youtube: return youtube(original)
        }
    }

    // MARK: Spotify (trang nhúng, không cần tài khoản; tối đa 100 bài/playlist)

    private func spotify(_ input: URL) -> Result<ImportedCollection, UpdateError> {
        var url = input
        if (url.host ?? "").contains("spotify.link") || !(url.host ?? "").contains("open.spotify.com") {
            if let r = Web.get(url) { url = r.finalURL }   // link rút gọn → link thật
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        // bỏ tiền tố ngôn ngữ như "intl-vi"
        guard let index = parts.firstIndex(where: { ["playlist", "album", "track", "artist"].contains($0) }), index + 1 < parts.count else {
            return .failure(UpdateError(L("Không nhận ra link Spotify (cần link playlist, album hoặc bài hát).")))
        }
        let kind = parts[index], id = parts[index + 1]
        if kind == "artist" { return .failure(UpdateError(L("Chưa hỗ trợ link nghệ sĩ Spotify. Hãy dùng link playlist, album hoặc bài hát."))) }
        guard let embed = URL(string: "https://open.spotify.com/embed/\(kind)/\(id)"),
              let page = Web.string(embed) else {
            return .failure(UpdateError(L("Không mở được trang Spotify. Kiểm tra mạng, hoặc playlist đang ở chế độ riêng tư.")))
        }
        var json: [String: Any]?
        for block in Web.scripts(page.text) where block.attrs.contains("__NEXT_DATA__") {
            json = (try? JSONSerialization.jsonObject(with: Data(block.body.utf8), options: [])) as? [String: Any]
        }
        guard let entity = InnerTube.dig(json, ["props", "pageProps", "state", "data", "entity"]) as? [String: Any] else {
            return .failure(UpdateError(L("Spotify đã đổi cấu trúc trang nhúng nên chưa đọc được. Hãy báo để cập nhật.")))
        }
        let name = (entity["name"] as? String) ?? (entity["title"] as? String) ?? "Spotify"
        var tracks: [ImportedTrack] = []
        if let list = entity["trackList"] as? [[String: Any]] {
            for t in list {
                guard let title = t["title"] as? String else { continue }
                let artist = ((t["subtitle"] as? String) ?? "").replacingOccurrences(of: "\u{00a0}", with: " ")
                let ms = (t["duration"] as? Double) ?? Double((t["duration"] as? Int) ?? 0)
                tracks.append(ImportedTrack(title: title, artist: artist, duration: ms > 0 ? ms / 1000 : nil))
            }
        } else if kind == "track" {
            let artists = ((entity["artists"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            let ms = (entity["duration"] as? Double) ?? Double((entity["duration"] as? Int) ?? 0)
            tracks.append(ImportedTrack(title: name, artist: artists, duration: ms > 0 ? ms / 1000 : nil))
        }
        if tracks.isEmpty { return .failure(UpdateError(L("Không thấy bài nào trong link Spotify (playlist riêng tư hoặc trống)."))) }
        var collection = ImportedCollection(name: name, tracks: tracks, source: ImportSource.spotify.rawValue)
        collection.truncated = kind == "playlist" && tracks.count >= 100
        return .success(collection)
    }

    // MARK: Apple Music (JSON-LD trong trang)

    private static func isoDuration(_ text: String?) -> Double? {
        guard let text = text, text.hasPrefix("PT") else { return nil }
        func part(_ unit: String) -> Double {
            Double(Web.firstMatch("(\\d+(?:\\.\\d+)?)\(unit)", in: text) ?? "") ?? 0
        }
        let total = part("H") * 3600 + part("M") * 60 + part("S")
        return total > 0 ? total : nil
    }

    private func appleMusic(_ url: URL) -> Result<ImportedCollection, UpdateError> {
        guard let page = Web.string(url) else {
            return .failure(UpdateError(L("Không mở được trang Apple Music. Kiểm tra mạng hoặc link.")))
        }
        func names(_ value: Any?) -> String {
            if let list = value as? [[String: Any]] { return list.compactMap { $0["name"] as? String }.joined(separator: ", ") }
            if let one = value as? [String: Any] { return (one["name"] as? String) ?? "" }
            return (value as? String) ?? ""
        }
        for block in Web.scripts(page.text) where block.attrs.contains("ld+json") {
            guard let root = (try? JSONSerialization.jsonObject(with: Data(block.body.utf8), options: [])) as? [String: Any] else { continue }
            let kind = (root["@type"] as? String) ?? ""
            let name = (root["name"] as? String) ?? "Apple Music"
            let albumArtist = names(root["byArtist"])
            var items: [[String: Any]] = []
            if let list = root["track"] as? [[String: Any]] { items = list }
            else if let list = root["tracks"] as? [[String: Any]] { items = list }
            else if kind == "MusicRecording" { items = [root] }
            if items.isEmpty { continue }
            var tracks: [ImportedTrack] = []
            for t in items {
                guard let title = t["name"] as? String else { continue }
                let artist = names(t["byArtist"]).isEmpty ? albumArtist : names(t["byArtist"])
                tracks.append(ImportedTrack(title: title, artist: artist, duration: PlaylistImporter.isoDuration(t["duration"] as? String)))
            }
            if !tracks.isEmpty { return .success(ImportedCollection(name: name, tracks: tracks, source: ImportSource.appleMusic.rawValue)) }
        }
        return .failure(UpdateError(L("Không đọc được danh sách bài từ Apple Music (cần link playlist/album/bài công khai).")))
    }

    // MARK: Deezer (API công khai)

    private func deezer(_ input: URL) -> Result<ImportedCollection, UpdateError> {
        var url = input
        if let r = Web.get(url) { url = r.finalURL }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: { ["playlist", "album", "track"].contains($0) }), index + 1 < parts.count else {
            return .failure(UpdateError(L("Không nhận ra link Deezer (cần link playlist, album hoặc bài hát).")))
        }
        let kind = parts[index], id = parts[index + 1].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        func track(_ t: [String: Any], fallbackArtist: String = "") -> ImportedTrack? {
            guard let title = t["title"] as? String else { return nil }
            let artist = ((t["artist"] as? [String: Any])?["name"] as? String) ?? fallbackArtist
            let seconds = (t["duration"] as? Double) ?? Double((t["duration"] as? Int) ?? 0)
            return ImportedTrack(title: title, artist: artist, duration: seconds > 0 ? seconds : nil)
        }
        guard let infoURL = URL(string: "https://api.deezer.com/\(kind)/\(id)"),
              let info = Web.json(infoURL) as? [String: Any], info["error"] == nil else {
            return .failure(UpdateError(L("Không lấy được dữ liệu Deezer (playlist riêng tư hoặc link sai).")))
        }
        let name = (info["title"] as? String) ?? "Deezer"
        var tracks: [ImportedTrack] = []
        if kind == "track" {
            if let t = track(info) { tracks.append(t) }
        } else {
            let albumArtist = ((info["artist"] as? [String: Any])?["name"] as? String) ?? ""
            var index = 0
            while index < 1000 {
                guard let pageURL = URL(string: "https://api.deezer.com/\(kind)/\(id)/tracks?limit=100&index=\(index)"),
                      let json = Web.json(pageURL) as? [String: Any],
                      let data = json["data"] as? [[String: Any]], !data.isEmpty else { break }
                for t in data { if let item = track(t, fallbackArtist: albumArtist) { tracks.append(item) } }
                if json["next"] == nil { break }
                index += 100
            }
        }
        if tracks.isEmpty { return .failure(UpdateError(L("Link Deezer không có bài nào."))) }
        return .success(ImportedCollection(name: name, tracks: tracks, source: ImportSource.deezer.rawValue))
    }

    // MARK: SoundCloud (dữ liệu nhúng trong trang + API công khai)

    private func soundCloud(_ input: URL) -> Result<ImportedCollection, UpdateError> {
        guard let page = Web.string(input) else {
            return .failure(UpdateError(L("Không mở được trang SoundCloud. Kiểm tra mạng hoặc link.")))
        }
        var hydration: [[String: Any]] = []
        for block in Web.scripts(page.text) where block.body.contains("__sc_hydration") {
            if let start = block.body.range(of: "= ")?.upperBound {
                var text = String(block.body[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasSuffix(";") { text.removeLast() }
                hydration = ((try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [])) as? [[String: Any]]) ?? []
            }
        }
        func track(_ t: [String: Any]) -> ImportedTrack? {
            guard let title = t["title"] as? String else { return nil }
            let artist = ((t["user"] as? [String: Any])?["username"] as? String) ?? ""
            let ms = (t["duration"] as? Double) ?? Double((t["duration"] as? Int) ?? 0)
            return ImportedTrack(title: title, artist: artist, duration: ms > 0 ? ms / 1000 : nil)
        }
        var name = "SoundCloud"
        var tracks: [ImportedTrack] = []
        var missingIds: [Int] = []
        for item in hydration {
            guard let kind = item["hydratable"] as? String, let data = item["data"] as? [String: Any] else { continue }
            if kind == "sound", let t = track(data) { name = t.title; tracks = [t] }
            if kind == "playlist" {
                name = (data["title"] as? String) ?? name
                for t in (data["tracks"] as? [[String: Any]]) ?? [] {
                    if let item = track(t) { tracks.append(item) } else if let id = t["id"] as? Int { missingIds.append(id) }
                }
            }
        }
        // Những bài chỉ có id (SoundCloud chỉ nhúng đầy đủ vài bài đầu): hỏi API công khai bằng client_id lấy từ trang.
        if !missingIds.isEmpty, let clientId = soundCloudClientId(html: page.text) {
            var index = 0
            while index < missingIds.count {
                let chunk = missingIds[index..<min(index + 30, missingIds.count)].map(String.init).joined(separator: ",")
                if let url = URL(string: "https://api-v2.soundcloud.com/tracks?ids=\(chunk)&client_id=\(clientId)"),
                   let list = Web.json(url) as? [[String: Any]] {
                    for t in list { if let item = track(t) { tracks.append(item) } }
                }
                index += 30
            }
        }
        if tracks.isEmpty { return .failure(UpdateError(L("Không đọc được bài nào từ SoundCloud (cần link công khai)."))) }
        var collection = ImportedCollection(name: name, tracks: tracks, source: ImportSource.soundCloud.rawValue)
        collection.truncated = !missingIds.isEmpty && tracks.count < missingIds.count
        return .success(collection)
    }

    func soundCloudClientId(html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "src=\"(https://a-v2\\.sndcdn\\.com/assets/[^\"]+\\.js)\"", options: []) else { return nil }
        let ns = html as NSString
        let urls = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        for raw in urls.reversed() {
            guard let url = URL(string: raw), let js = Web.string(url) else { continue }
            if let id = Web.firstMatch("client_id:\"([a-zA-Z0-9]{32})\"", in: js.text) { return id }
        }
        return nil
    }

    // MARK: YouTube / YouTube Music (đã là bài YouTube nên không cần ghép)

    private func youtube(_ url: URL) -> Result<ImportedCollection, UpdateError> {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        let sem = DispatchSemaphore(value: 0)
        if let list = items.first(where: { $0.name == "list" })?.value, !list.isEmpty {
            var result: Result<ImportedCollection, UpdateError> = .failure(UpdateError(L("Không đọc được playlist YouTube.")))
            DispatchQueue.main.async {
                InnerTube.shared.playlistSongs(listId: list) { r in
                    switch r {
                    case .success(let value):
                        var c = ImportedCollection(name: value.name, tracks: [], source: ImportSource.youtube.rawValue)
                        c.directSongs = value.songs
                        result = .success(c)
                    case .failure(let error):
                        result = .failure(UpdateError(error.localizedDescription))
                    }
                    sem.signal()
                }
            }
            sem.wait()
            return result
        }
        var videoId = items.first(where: { $0.name == "v" })?.value
        if videoId == nil, (url.host ?? "").contains("youtu.be") { videoId = url.pathComponents.last }
        guard let id = videoId, id.count >= 6 else { return .failure(UpdateError(L("Link YouTube không có playlist hoặc bài hát."))) }
        // oEmbed cho tên bài và kênh.
        guard let oembed = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(id)"),
              let json = Web.json(oembed) as? [String: Any], let title = json["title"] as? String else {
            return .failure(UpdateError(L("Không đọc được thông tin video YouTube.")))
        }
        let author = ((json["author_name"] as? String) ?? "").replacingOccurrences(of: " - Topic", with: "")
        let thumb = (json["thumbnail_url"] as? String).flatMap { URL(string: $0) }
        var c = ImportedCollection(name: title, tracks: [], source: ImportSource.youtube.rawValue)
        c.directSongs = [Song(videoId: id, title: title, artist: author, subtitle: author, duration: nil, thumbnailURL: thumb)]
        return .success(c)
    }

    // MARK: - Ghép sang YouTube Music

    struct MatchResult {
        var songs: [Song]
        var missed: [ImportedTrack]
    }

    /// Ghép từng bài (tên + nghệ sĩ + độ dài) với kết quả tìm kiếm YouTube Music, 3 bài song song.
    func match(_ collection: ImportedCollection,
               progress: @escaping (Int, Int) -> Void,
               completion: @escaping (MatchResult) -> Void) {
        let tracks = collection.tracks
        let total = tracks.count
        var found = [Song?](repeating: nil, count: total)
        let lock = NSLock()
        var done = 0
        let queue = DispatchQueue.global(qos: .userInitiated)
        let gate = DispatchSemaphore(value: 3)
        let group = DispatchGroup()
        for (index, track) in tracks.enumerated() {
            group.enter()
            queue.async {
                gate.wait()
                let song = self.bestMatch(for: track)
                lock.lock()
                found[index] = song
                done += 1
                let current = done
                lock.unlock()
                gate.signal()
                DispatchQueue.main.async { progress(current, total) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            var songs: [Song] = []
            var missed: [ImportedTrack] = []
            for (i, track) in tracks.enumerated() {
                if let s = found[i] { songs.append(s) } else { missed.append(track) }
            }
            completion(MatchResult(songs: songs, missed: missed))
        }
    }

    func bestMatch(for track: ImportedTrack) -> Song? {
        let query = "\(SongMatcher.cleanTitle(track.title)) \(track.artist.components(separatedBy: ",").first ?? "")"
        let sem = DispatchSemaphore(value: 0)
        var results: [Song] = []
        DispatchQueue.main.async {
            InnerTube.shared.search(query) { r in
                if case .success(let songs) = r { results = songs }
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + 25)
        var best: (Song, Double)?
        for song in results.prefix(6) {
            let score = SongMatcher.score(track: track, candidate: song)
            if best == nil || score > best!.1 { best = (song, score) }
        }
        if let (song, score) = best, score >= 0.5 { return song }
        return nil
    }
}

/// So khớp tên bài / nghệ sĩ / độ dài giữa nguồn gốc và kết quả YouTube Music.
enum SongMatcher {
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US")).lowercased()
            .replacingOccurrences(of: "đ", with: "d")
        let allowed = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(allowed).split(separator: " ").joined(separator: " ")
    }

    /// Bỏ phần "(feat. …)", "- Remastered", "[Official]" ở tên bài.
    static func cleanTitle(_ title: String) -> String {
        var t = title
        for pattern in ["\\([^)]*\\)", "\\[[^\\]]*\\]", "\\s-\\s.*(remaster|version|edit|mix|live|from).*$"] {
            t = t.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    private static func tokens(_ text: String) -> Set<String> {
        return Set(normalize(text).split(separator: " ").map(String.init))
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        let x = tokens(a), y = tokens(b)
        if x.isEmpty || y.isEmpty { return 0 }
        let common = Double(x.intersection(y).count)
        return common / Double(max(x.count, y.count))
    }

    static func score(track: ImportedTrack, candidate: Song) -> Double {
        let titleScore = max(similarity(cleanTitle(track.title), cleanTitle(candidate.title)),
                             normalize(candidate.title).contains(normalize(cleanTitle(track.title))) ? 0.9 : 0)
        var artistScore = 0.0
        let wanted = tokens(track.artist)
        if wanted.isEmpty {
            artistScore = 0.6
        } else {
            let have = tokens(candidate.artist + " " + candidate.subtitle)
            artistScore = Double(wanted.intersection(have).count) / Double(wanted.count)
        }
        var durationScore = 0.5
        if let wantedSeconds = track.duration, let have = candidate.duration {
            let diff = abs(LyricsService.seconds(have) - wantedSeconds)
            durationScore = diff <= 3 ? 1 : (diff <= 8 ? 0.6 : (diff <= 20 ? 0.2 : 0))
        }
        return titleScore * 0.55 + artistScore * 0.3 + durationScore * 0.15
    }
}
