import Foundation
import CommonCrypto

/// Last.fm: đăng nhập bằng khoá API của chính bạn, báo "đang nghe" và ghi nhận (scrobble) bài đã nghe, thích/bỏ thích.
/// Mật khẩu chỉ dùng một lần để lấy khoá phiên, không được lưu.
final class LastFM {
    static let shared = LastFM()
    private let defaults = UserDefaults.standard
    private let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    struct Pending: Codable {
        let artist: String
        let track: String
        let album: String?
        let timestamp: Int
        let duration: Int?
    }

    var apiKey: String { return defaults.string(forKey: "lastfm.key") ?? "" }
    var secret: String { return defaults.string(forKey: "lastfm.secret") ?? "" }
    var sessionKey: String { return defaults.string(forKey: "lastfm.session") ?? "" }
    var username: String { return defaults.string(forKey: "lastfm.user") ?? "" }
    var isLoggedIn: Bool { return !sessionKey.isEmpty && !apiKey.isEmpty && !secret.isEmpty }

    /// Bật/tắt ghi nhận tự động (mặc định bật sau khi đăng nhập).
    var scrobbleEnabled: Bool {
        get { return defaults.object(forKey: "lastfm.enabled") == nil ? true : defaults.bool(forKey: "lastfm.enabled") }
        set { defaults.set(newValue, forKey: "lastfm.enabled") }
    }

    private var pending: [Pending] {
        get {
            guard let data = defaults.data(forKey: "lastfm.pending") else { return [] }
            return (try? JSONDecoder().decode([Pending].self, from: data)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(Array(newValue.suffix(300))), forKey: "lastfm.pending")
        }
    }

    // MARK: - Ký và gọi API

    private static func md5(_ text: String) -> String {
        let data = Array(text.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5(data, CC_LONG(data.count), &digest)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func signature(_ params: [String: String], secret: String) -> String {
        let joined = params.keys.sorted().map { $0 + (params[$0] ?? "") }.joined()
        return LastFM.md5(joined + secret)
    }

    private func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private func post(_ method: String, _ extra: [String: String], key: String? = nil, secret: String? = nil, session sk: String? = nil,
                      completion: @escaping (Result<[String: Any], UpdateError>) -> Void) {
        var params = extra
        params["method"] = method
        params["api_key"] = key ?? apiKey
        if let sk = sk { params["sk"] = sk }
        let sig = signature(params, secret: secret ?? self.secret)
        params["api_sig"] = sig
        params["format"] = "json"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = params.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&").data(using: .utf8)
        session.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(UpdateError(error.localizedDescription))); return }
                guard let data = data, let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                    completion(.failure(UpdateError("Last.fm trả về dữ liệu không đọc được.")))
                    return
                }
                if let message = json["message"] as? String, json["error"] != nil {
                    completion(.failure(UpdateError(message)))
                    return
                }
                completion(.success(json))
            }
        }.resume()
    }

    // MARK: - Đăng nhập

    func login(key: String, secret: String, username: String, password: String, completion: @escaping (Result<String, UpdateError>) -> Void) {
        post("auth.getMobileSession", ["username": username, "password": password], key: key, secret: secret) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let json):
                guard let s = json["session"] as? [String: Any], let sk = s["key"] as? String else {
                    completion(.failure(UpdateError("Last.fm không trả về khoá phiên.")))
                    return
                }
                let name = (s["name"] as? String) ?? username
                self?.defaults.set(key, forKey: "lastfm.key")
                self?.defaults.set(secret, forKey: "lastfm.secret")
                self?.defaults.set(sk, forKey: "lastfm.session")
                self?.defaults.set(name, forKey: "lastfm.user")
                completion(.success(name))
            }
        }
    }

    func logout() {
        for key in ["lastfm.session", "lastfm.user", "lastfm.pending"] { defaults.removeObject(forKey: key) }
    }

    // MARK: - Báo và ghi nhận

    private func clean(_ song: Song) -> (artist: String, track: String) {
        let artist = LyricsService.cleanArtist(song.artist)
        return (artist.isEmpty ? song.artist : artist, LyricsService.cleanTitle(song.title))
    }

    func nowPlaying(_ song: Song, duration: Double) {
        guard isLoggedIn, scrobbleEnabled else { return }
        let c = clean(song)
        var params = ["artist": c.artist, "track": c.track]
        if duration > 0 { params["duration"] = String(Int(duration)) }
        post("track.updateNowPlaying", params, session: sessionKey) { _ in }
    }

    func scrobble(_ song: Song, startedAt: Date, duration: Double) {
        guard isLoggedIn, scrobbleEnabled else { return }
        let c = clean(song)
        var list = pending
        list.append(Pending(artist: c.artist, track: c.track, album: nil, timestamp: Int(startedAt.timeIntervalSince1970),
                            duration: duration > 0 ? Int(duration) : nil))
        pending = list
        flush()
    }

    private var flushing = false

    /// Gửi các lượt nghe đang chờ (tối đa 50 một lần); lỗi mạng thì giữ lại gửi sau.
    func flush() {
        guard isLoggedIn, !flushing else { return }
        let batch = Array(pending.prefix(50))
        if batch.isEmpty { return }
        flushing = true
        var params: [String: String] = [:]
        for (i, item) in batch.enumerated() {
            params["artist[\(i)]"] = item.artist
            params["track[\(i)]"] = item.track
            params["timestamp[\(i)]"] = String(item.timestamp)
            if let d = item.duration { params["duration[\(i)]"] = String(d) }
        }
        post("track.scrobble", params, session: sessionKey) { [weak self] result in
            guard let self = self else { return }
            self.flushing = false
            switch result {
            case .success:
                self.pending = Array(self.pending.dropFirst(batch.count))
                if !self.pending.isEmpty { self.flush() }
            case .failure(let error):
                // Lỗi do dữ liệu (khác lỗi mạng) thì bỏ lô này để không kẹt mãi.
                if error.message.contains("Invalid") || error.message.contains("ignored") {
                    self.pending = Array(self.pending.dropFirst(batch.count))
                }
            }
        }
    }

    func love(_ song: Song, loved: Bool) {
        guard isLoggedIn, scrobbleEnabled else { return }
        let c = clean(song)
        post(loved ? "track.love" : "track.unlove", ["artist": c.artist, "track": c.track], session: sessionKey) { _ in }
    }
}

/// Theo dõi bài đang phát để báo "đang nghe" và ghi nhận khi đã nghe đủ lâu (một nửa bài hoặc 4 phút, bài dài hơn 30 giây).
final class ScrobbleTracker {
    static let shared = ScrobbleTracker()
    private var trackedId: String?
    private var startedAt = Date()
    private var listened: Double = 0
    private var lastPosition: Double = 0
    private var scrobbled = false
    private var announced = false

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(tick), name: .playerTimeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tick), name: .playerStateChanged, object: nil)
        LastFM.shared.flush()
    }

    @objc private func tick() {
        let engine = PlayerEngine.shared
        guard let song = engine.currentSong else { return }
        if song.videoId != trackedId {
            trackedId = song.videoId
            startedAt = Date()
            listened = 0
            lastPosition = engine.currentTime
            scrobbled = false
            announced = false
            return
        }
        if !announced && engine.duration > 0 && engine.isPlaying {
            announced = true
            LastFM.shared.nowPlaying(song, duration: engine.duration)
        }
        guard engine.isPlaying else { lastPosition = engine.currentTime; return }
        let delta = engine.currentTime - lastPosition
        lastPosition = engine.currentTime
        // Chỉ cộng thời gian nghe thật (tua thì bỏ qua), tránh tính gian lận.
        if delta > 0 && delta < 3 {
            listened += delta
            PlayLog.shared.addListening(song.videoId, seconds: delta)
        }
        let length = engine.duration
        guard !scrobbled, length > 30 else { return }
        if listened >= min(length / 2, 240) {
            scrobbled = true
            LastFM.shared.scrobble(song, startedAt: startedAt, duration: length)
        }
    }
}
