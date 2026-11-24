import Foundation
import CommonCrypto

/// Video Canvas (clip lặp ngắn) của Spotify. Cần cookie sp_dc của chính bạn; API không chính thức nên có thể đổi bất cứ lúc nào.
/// Lỗi ở bước nào thì bỏ qua, app tự dùng MV YouTube rồi ảnh bìa.
final class SpotifyCanvas {
    static let shared = SpotifyCanvas()

    static var cookie: String {
        get { return (UserDefaults.standard.string(forKey: "spotify.spdc") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spotify.spdc") }
    }
    static var isConfigured: Bool { return !cookie.isEmpty }

    private let lock = NSLock()
    private var results: [String: URL?] = [:]    // đã hỏi: có URL hoặc nil (không có Canvas)
    private var inflight: Set<String> = []
    private var token: (value: String, expires: Date)?
    private var secrets: (version: String, key: [UInt8])?
    private let queue = DispatchQueue(label: "mochyios.canvas", qos: .utility)

    /// nil = chưa hỏi; .some(nil) = bài này không có Canvas.
    func cached(_ videoId: String) -> URL?? {
        lock.lock(); defer { lock.unlock() }
        return results[videoId]
    }

    func request(_ song: Song, duration: Double, completion: @escaping (URL?) -> Void) {
        guard SpotifyCanvas.isConfigured else { completion(nil); return }
        lock.lock()
        if let hit = results[song.videoId] { lock.unlock(); completion(hit); return }
        if inflight.contains(song.videoId) { lock.unlock(); return }
        inflight.insert(song.videoId)
        lock.unlock()
        queue.async {
            let url = self.lookup(song, duration: duration)
            self.lock.lock()
            self.inflight.remove(song.videoId)
            // Lỗi mạng/token thì không nhớ "không có", để lần sau thử lại.
            if url != nil || self.lastLookupConclusive { self.results[song.videoId] = .some(url) }
            self.lock.unlock()
            DispatchQueue.main.async { completion(url) }
        }
    }

    private var lastLookupConclusive = false

    private func lookup(_ song: Song, duration: Double) -> URL? {
        lastLookupConclusive = false
        guard let access = accessToken() else { return nil }
        guard let uri = trackURI(for: song, duration: duration, token: access) else {
            lastLookupConclusive = true
            return nil
        }
        let found = canvasViaProtobuf(uri: uri, token: access) ?? canvasViaPathfinder(uri: uri, token: access)
        lastLookupConclusive = true
        return found
    }

    // MARK: - Token (sp_dc + TOTP)

    private func loadSecrets() -> (version: String, key: [UInt8])? {
        if let s = secrets { return s }
        for link in ["https://code.thetadev.de/ThetaDev/spotify-secrets/raw/branch/main/secrets/secretDict.json",
                     "https://raw.githubusercontent.com/xyloflake/spot-secrets-go/main/secrets/secretDict.json"] {
            guard let url = URL(string: link), let json = LyricsHTTP.json(url) as? [String: Any] else { continue }
            let versions = json.keys.compactMap { Int($0) }.sorted()
            guard let top = versions.last, let raw = json[String(top)] as? [Any] else { continue }
            let bytes = raw.compactMap { ($0 as? Int).map { UInt8(truncatingIfNeeded: $0) } }
            if bytes.isEmpty { continue }
            let transformed = bytes.enumerated().map { i, b in Int(b ^ UInt8((i % 33) + 9)) }
            let digits = transformed.map(String.init).joined()
            secrets = (String(top), Array(digits.utf8))
            return secrets
        }
        return nil
    }

    private static func totp(key: [UInt8], at seconds: Int) -> String {
        var counter = UInt64(seconds / 30).bigEndian
        var mac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        withUnsafeBytes(of: &counter) { c in
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), key, key.count, c.baseAddress, 8, &mac)
        }
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let code = (UInt32(mac[offset] & 0x7f) << 24) | (UInt32(mac[offset + 1]) << 16) | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])
        return String(format: "%06d", code % 1_000_000)
    }

    /// Token web của Spotify (từ cookie sp_dc); dùng cả để đọc thư viện của tài khoản đã đăng nhập.
    func webToken() -> String? { return accessToken() }

    private func accessToken() -> String? {
        lock.lock()
        if let t = token, t.expires > Date().addingTimeInterval(60) { lock.unlock(); return t.value }
        lock.unlock()
        let cookie = SpotifyCanvas.cookie
        guard !cookie.isEmpty else { return nil }
        var server = Int(Date().timeIntervalSince1970)
        if let url = URL(string: "https://open.spotify.com/api/server-time"), let json = LyricsHTTP.json(url) as? [String: Any] {
            let t = Int(LyricsHTTP.number(json["serverTime"]))
            if t > 1_000_000_000 { server = t }
        }
        let headers = ["Cookie": "sp_dc=" + cookie, "Accept": "application/json", "App-Platform": "WebPlayer"]
        var attempts: [(String, String, Int)] = []   // (reason, mã, phiên bản)
        if let s = loadSecrets() {
            attempts.append(("transport", SpotifyCanvas.totp(key: s.key, at: server), Int(s.version) ?? 0))
            attempts.append(("init", SpotifyCanvas.totp(key: s.key, at: server), Int(s.version) ?? 0))
        }
        for (reason, code, version) in attempts {
            guard let url = LyricsHTTP.url("https://open.spotify.com/api/token",
                                           [("reason", reason), ("productType", "web-player"), ("totp", code),
                                            ("totpServer", code), ("totpVer", String(version))]),
                  let json = LyricsHTTP.json(url, headers: headers) as? [String: Any],
                  let value = json["accessToken"] as? String, !value.isEmpty,
                  (json["isAnonymous"] as? Bool) != true else { continue }
            let expMs = LyricsHTTP.number(json["accessTokenExpirationTimestampMs"])
            let expires = expMs > 0 ? Date(timeIntervalSince1970: expMs / 1000) : Date().addingTimeInterval(50 * 60)
            lock.lock(); token = (value, expires); lock.unlock()
            return value
        }
        lock.lock(); secrets = nil; lock.unlock()   // có thể bí mật đã đổi: lần sau tải lại
        return nil
    }

    // MARK: - Tìm bài trên Spotify

    private func trackURI(for song: Song, duration: Double, token: String) -> String? {
        let title = LyricsService.cleanTitle(song.title), artist = LyricsService.cleanArtist(song.artist)
        guard let url = LyricsHTTP.url("https://api.spotify.com/v1/search", [("q", "track:\(title) artist:\(artist)"), ("type", "track"), ("limit", "6")]),
              let json = LyricsHTTP.json(url, headers: ["Authorization": "Bearer " + token]) as? [String: Any],
              let items = (json["tracks"] as? [String: Any])?["items"] as? [[String: Any]] else { return nil }
        func like(_ a: String, _ b: String) -> Bool {
            let x = SongMatcher.normalize(SongMatcher.cleanTitle(a)), y = SongMatcher.normalize(SongMatcher.cleanTitle(b))
            return !x.isEmpty && (x == y || x.contains(y) || y.contains(x))
        }
        for item in items {
            guard let uri = item["uri"] as? String, let name = item["name"] as? String, like(name, title) else { continue }
            let d = LyricsHTTP.number(item["duration_ms"]) / 1000
            if duration > 0 && d > 0 && abs(d - duration) > 6 { continue }
            return uri
        }
        return nil
    }

    // MARK: - Canvas

    private static func varint(_ n: Int) -> [UInt8] {
        var value = n, out: [UInt8] = []
        while value >= 0x80 { out.append(UInt8(value & 0x7f) | 0x80); value >>= 7 }
        out.append(UInt8(value))
        return out
    }

    private func extractMP4(_ data: Data?) -> URL? {
        guard let data = data, let text = String(data: data, encoding: .isoLatin1),
              let r = text.range(of: "https://canvaz\\.scdn\\.co/[A-Za-z0-9/_.\\-%]+\\.mp4", options: .regularExpression) else { return nil }
        return URL(string: String(text[r]))
    }

    private func canvasViaProtobuf(uri: String, token: String) -> URL? {
        let u = Array(uri.utf8)
        let entity = [UInt8(0x0A)] + SpotifyCanvas.varint(u.count) + u
        let body = Data([UInt8(0x0A)] + SpotifyCanvas.varint(entity.count) + entity)
        guard let url = URL(string: "https://spclient.wg.spotify.com/canvaz-cache/v0/canvases") else { return nil }
        let r = LyricsHTTP.fetch(url, method: "POST", headers: ["Authorization": "Bearer " + token, "Content-Type": "application/x-protobuf",
                                                                 "Accept": "application/protobuf"], body: body)
        guard r.status == 200 else { return nil }
        return extractMP4(r.data)
    }

    private func canvasViaPathfinder(uri: String, token: String) -> URL? {
        guard let url = URL(string: "https://api-partner.spotify.com/pathfinder/v2/query") else { return nil }
        let body: [String: Any] = ["operationName": "canvas", "variables": ["trackUri": uri],
                                   "extensions": ["persistedQuery": ["version": 1, "sha256Hash": "575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f"]]]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else { return nil }
        let r = LyricsHTTP.fetch(url, method: "POST", headers: ["Authorization": "Bearer " + token, "Content-Type": "application/json",
                                                                 "App-Platform": "WebPlayer", "Accept": "application/json"], body: data)
        guard r.status == 200 else { return nil }
        return extractMP4(r.data)
    }
}
