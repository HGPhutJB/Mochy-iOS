import UIKit
import CommonCrypto

/// Các dịch vụ nhạc có thể liên kết để tự đồng bộ playlist.
enum MusicService: String, CaseIterable {
    case spotify, appleMusic, deezer, soundCloud, youtubeMusic

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .deezer: return "Deezer"
        case .soundCloud: return "SoundCloud"
        case .youtubeMusic: return "YouTube Music"
        }
    }

    var brand: UIColor {
        switch self {
        case .spotify: return UIColor(red: 0.114, green: 0.725, blue: 0.329, alpha: 1)
        case .appleMusic: return UIColor(red: 0.98, green: 0.18, blue: 0.29, alpha: 1)
        case .deezer: return UIColor(red: 0.635, green: 0.22, blue: 1.0, alpha: 1)
        case .soundCloud: return UIColor(red: 1.0, green: 0.333, blue: 0.0, alpha: 1)
        case .youtubeMusic: return UIColor(red: 1.0, green: 0.0, blue: 0.2, alpha: 1)
        }
    }

    /// Dịch vụ không có API tài khoản công khai: chỉ liên kết từng link playlist.
    var isLinkBased: Bool { return self == .appleMusic || self == .youtubeMusic }

    var importSource: ImportSource {
        switch self {
        case .spotify: return .spotify
        case .appleMusic: return .appleMusic
        case .deezer: return .deezer
        case .soundCloud: return .soundCloud
        case .youtubeMusic: return .youtube
        }
    }
}

/// Ảnh bìa playlist đồng bộ: ô vuông bo góc màu dịch vụ, biểu tượng nốt nhạc trắng.
enum MusicCover {
    private static var cache: [String: UIImage] = [:]

    static func image(for key: String?) -> UIImage? {
        guard let key = key, let service = MusicService(rawValue: key) else { return nil }
        if let hit = cache[key] { return hit }
        let size: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let colors = [service.brand.cgColor, service.brand.withAlphaComponent(0.62).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])
            }
            let note = Icons.music(120)
            if let cg = note.cgImage {
                let target = CGRect(x: size * 0.25, y: size * 0.25, width: size * 0.5, height: size * 0.5)
                let c = ctx.cgContext
                c.saveGState()
                c.translateBy(x: 0, y: size)
                c.scaleBy(x: 1, y: -1)
                let flipped = CGRect(x: target.minX, y: size - target.maxY, width: target.width, height: target.height)
                c.clip(to: flipped, mask: cg)
                c.setFillColor(UIColor.white.cgColor)
                c.fill(rect)
                c.restoreGState()
            }
        }
        cache[key] = image
        return image
    }
}

/// Lưu chuỗi bí mật (token) trong Keychain; nếu bản cài không có quyền Keychain thì dùng UserDefaults.
enum Keychain {
    private static let service = "com.puc.mochyios.accounts"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "kc." + key)
        guard let value = value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(value, forKey: "kc." + key)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return UserDefaults.standard.string(forKey: "kc." + key)
    }
}

struct SyncTrack {
    let key: String
    let track: ImportedTrack
}

struct SyncList {
    let key: String
    let name: String
    var tracks: [SyncTrack]
    var directSongs: [Song] = []
}

private struct MatchCacheFile: Codable {
    var songs: [String: Song] = [:]
    var missed: [String] = []
}

/// Liên kết tài khoản nhạc và tự đồng bộ: mỗi dịch vụ tạo playlist "Bài hát đã thích" cùng các playlist của bạn,
/// ghép từng bài sang YouTube Music (có nhớ kết quả để lần sau chỉ ghép bài mới).
final class AccountSync {
    static let shared = AccountSync()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var cacheFile = MatchCacheFile()
    private var cacheLoaded = false
    private(set) var syncing = false
    private let maxMatchesPerRun = 250

    // MARK: Trạng thái

    func isLinked(_ s: MusicService) -> Bool { return defaults.string(forKey: "acct.\(s.rawValue).name") != nil }
    func accountName(_ s: MusicService) -> String? { return defaults.string(forKey: "acct.\(s.rawValue).name") }
    var linkedServices: [MusicService] { return MusicService.allCases.filter { isLinked($0) } }
    private func links(_ s: MusicService) -> [String] { return defaults.stringArray(forKey: "acct.\(s.rawValue).links") ?? [] }
    private func setLinks(_ s: MusicService, _ v: [String]) { defaults.set(v, forKey: "acct.\(s.rawValue).links") }
    private func setAccount(_ s: MusicService, name: String, id: String? = nil) {
        defaults.set(name, forKey: "acct.\(s.rawValue).name")
        if let id = id { defaults.set(id, forKey: "acct.\(s.rawValue).id") }
    }
    private func accountId(_ s: MusicService) -> String? { return defaults.string(forKey: "acct.\(s.rawValue).id") }

    // MARK: Playlist đã bị người dùng xoá (không tạo lại khi đồng bộ)

    private var dismissed: Set<String> {
        get { return Set(defaults.stringArray(forKey: "acct.dismissed") ?? []) }
        set { defaults.set(Array(newValue), forKey: "acct.dismissed") }
    }

    func dismiss(_ key: String) {
        var d = dismissed
        d.insert(key)
        dismissed = d
    }

    private func clearDismissed(_ s: MusicService) {
        dismissed = dismissed.filter { !$0.hasPrefix("acct:\(s.rawValue):") }
    }

    func disconnect(_ s: MusicService) {
        for k in ["name", "id", "links", "client.cid"] { defaults.removeObject(forKey: "acct.\(s.rawValue).\(k)") }
        switch s {
        case .spotify: break   // giữ cookie sp_dc cho video Canvas
        case .deezer: Keychain.set(nil, for: "deezer.arl")
        case .soundCloud: Keychain.set(nil, for: "soundcloud.token")
        case .appleMusic: Keychain.set(nil, for: "apple.mut")
        case .youtubeMusic: Keychain.set(nil, for: "youtube.cookie")
        }
    }

    // MARK: Hộp nhập

    static func prompt(from presenter: UIViewController, title: String, message: String, placeholder: String,
                       text: String? = nil, action: String = "Tiếp tục", completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { f in
            f.placeholder = placeholder
            f.text = text
            f.autocapitalizationType = .none
            f.autocorrectionType = .no
            f.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in completion(nil) })
        alert.addAction(UIAlertAction(title: action, style: .default) { _ in
            let v = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            completion(v.isEmpty ? nil : v)
        })
        var top = presenter
        while let next = top.presentedViewController { top = next }
        top.present(alert, animated: true, completion: nil)
    }

    private static func cancelled() -> UpdateError { return UpdateError("Đã huỷ", cancelled: true) }

    // MARK: Liên kết (đăng nhập thật bằng trang web của dịch vụ)

    private static let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"

    func connect(_ s: MusicService, from presenter: UIViewController,
                 completion: @escaping (Result<String, UpdateError>) -> Void) {
        let finish: (Result<String, UpdateError>) -> Void = { result in
            DispatchQueue.main.async {
                if case .success = result {
                    self.clearDismissed(s)
                    self.syncSoon(s)
                }
                completion(result)
            }
        }
        let spec: (url: String, required: [String], domains: [String])
        switch s {
        case .spotify: spec = ("https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F", ["sp_dc"], ["spotify.com"])
        case .appleMusic: spec = ("https://music.apple.com/vn/browse", ["media-user-token"], ["apple.com"])
        case .deezer: spec = ("https://www.deezer.com/login", ["arl"], ["deezer.com"])
        case .soundCloud: spec = ("https://soundcloud.com/signin", ["oauth_token"], ["soundcloud.com"])
        case .youtubeMusic: spec = ("https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F", ["SAPISID"], ["youtube.com", "google.com"])
        }
        WebLoginViewController.present(from: presenter, service: s, startURL: URL(string: spec.url)!, required: spec.required,
                                       domains: spec.domains) { header, jar in
            guard let header = header else { finish(.failure(AccountSync.cancelled())); return }
            DispatchQueue.global(qos: .userInitiated).async {
                switch s {
                case .spotify: self.finishSpotify(jar, finish)
                case .deezer: self.finishDeezer(jar, finish)
                case .soundCloud: self.finishSoundCloud(jar, finish)
                case .appleMusic: self.finishApple(jar, header, finish)
                case .youtubeMusic: self.finishYouTube(header, finish)
                }
            }
        }
    }

    private func finishSpotify(_ jar: [String: String], _ finish: (Result<String, UpdateError>) -> Void) {
        guard let dc = jar["sp_dc"] else { finish(.failure(UpdateError("Không thấy cookie đăng nhập Spotify."))); return }
        SpotifyCanvas.cookie = dc
        guard let me = spotifyGET("/me") else {
            finish(.failure(UpdateError("Đăng nhập được nhưng không lấy được token Spotify (Spotify có thể đã đổi cách bảo vệ).")))
            return
        }
        let name = (me["display_name"] as? String) ?? (me["id"] as? String) ?? "Spotify"
        setAccount(.spotify, name: name, id: me["id"] as? String)
        finish(.success(name))
    }

    private func finishDeezer(_ jar: [String: String], _ finish: (Result<String, UpdateError>) -> Void) {
        guard let arl = jar["arl"] else { finish(.failure(UpdateError("Không thấy cookie đăng nhập Deezer."))); return }
        Keychain.set(arl, for: "deezer.arl")
        guard let data = dzGW("deezer.getUserData", token: "", body: [:]), let user = data["USER"] as? [String: Any],
              let uid = user["USER_ID"] else {
            finish(.failure(UpdateError("Không đọc được tài khoản Deezer.")))
            return
        }
        let name = (user["BLOG_NAME"] as? String) ?? "Deezer"
        setAccount(.deezer, name: name, id: "\(uid)")
        finish(.success(name))
    }

    private func finishSoundCloud(_ jar: [String: String], _ finish: (Result<String, UpdateError>) -> Void) {
        guard let token = jar["oauth_token"] else { finish(.failure(UpdateError("Không thấy cookie đăng nhập SoundCloud."))); return }
        Keychain.set(token, for: "soundcloud.token")
        guard let page = Web.string(URL(string: "https://soundcloud.com")!),
              let cid = PlaylistImporter.shared.soundCloudClientId(html: page.text),
              let url = URL(string: "https://api-v2.soundcloud.com/me?client_id=\(cid)"),
              let me = Web.json(url, headers: ["Authorization": "OAuth \(token)"]) as? [String: Any],
              let id = me["id"] as? Int else {
            finish(.failure(UpdateError("Không đọc được tài khoản SoundCloud.")))
            return
        }
        defaults.set(cid, forKey: "acct.soundCloud.client.cid")
        let name = (me["username"] as? String) ?? "SoundCloud"
        setAccount(.soundCloud, name: name, id: String(id))
        finish(.success(name))
    }

    private func finishApple(_ jar: [String: String], _ header: String, _ finish: (Result<String, UpdateError>) -> Void) {
        guard let mut = jar["media-user-token"] else { finish(.failure(UpdateError("Không thấy cookie đăng nhập Apple Music."))); return }
        Keychain.set(mut, for: "apple.mut")
        guard appleGET("/me/library/songs?limit=1") != nil else {
            finish(.failure(UpdateError("Không đọc được thư viện Apple Music (cần gói đăng ký còn hiệu lực).")))
            return
        }
        setAccount(.appleMusic, name: "Đã đăng nhập")
        finish(.success("Apple Music"))
    }

    private func finishYouTube(_ header: String, _ finish: (Result<String, UpdateError>) -> Void) {
        Keychain.set(header, for: "youtube.cookie")
        guard ytBrowse("FEmusic_liked_playlists") != nil else {
            finish(.failure(UpdateError("Không đọc được thư viện YouTube Music.")))
            return
        }
        setAccount(.youtubeMusic, name: "Đã đăng nhập")
        finish(.success("YouTube Music"))
    }

    // MARK: Gọi API có đăng nhập

    private func postSync(_ urlString: String, headers: [String: String], body: Data?) -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 25
        request.setValue(AccountSync.safariUA, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data { out = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    // Spotify: token web lấy từ cookie sp_dc (cùng cách lấy video Canvas).
    private func spotifyToken() -> String? { return SpotifyCanvas.shared.webToken() }

    private func spotifyGET(_ path: String) -> [String: Any]? {
        guard let token = spotifyToken(), let url = URL(string: "https://api.spotify.com/v1" + path) else { return nil }
        return Web.json(url, headers: ["Authorization": "Bearer \(token)"]) as? [String: Any]
    }

    // Deezer: API nội bộ của trang web (cookie arl).
    private func dzGW(_ method: String, token: String, body: [String: Any]) -> [String: Any]? {
        guard let arl = Keychain.get("deezer.arl"),
              let data = try? JSONSerialization.data(withJSONObject: body, options: []) else { return nil }
        let urlString = "https://www.deezer.com/ajax/gw-light.php?method=\(method)&input=3&api_version=1.0&api_token=\(token)"
        let json = postSync(urlString, headers: ["Cookie": "arl=\(arl)", "Content-Type": "text/plain;charset=UTF-8"], body: data)
        return json?["results"] as? [String: Any]
    }

    private func dzToken() -> String? {
        guard let r = dzGW("deezer.getUserData", token: "", body: [:]) else { return nil }
        return r["checkForm"] as? String
    }

    // Apple Music: token nhà phát triển lấy từ trang web + cookie media-user-token.
    private func appleDevToken() -> String? {
        if let cached = defaults.string(forKey: "acct.apple.dev"), !cached.isEmpty { return cached }
        guard let home = Web.string(URL(string: "https://music.apple.com/vn/browse")!) else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "(/assets/[A-Za-z0-9_\\-\\.]+\\.js)", options: []) else { return nil }
        let ns = home.text as NSString
        let paths = regex.matches(in: home.text, options: [], range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        for path in paths {
            guard let url = URL(string: "https://music.apple.com" + path), let js = Web.string(url) else { continue }
            if let token = Web.firstMatch("(eyJh[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+)", in: js.text) {
                defaults.set(token, forKey: "acct.apple.dev")
                return token
            }
        }
        return nil
    }

    private func appleGET(_ path: String) -> [String: Any]? {
        guard let dev = appleDevToken(), let mut = Keychain.get("apple.mut"),
              let url = URL(string: "https://amp-api.music.apple.com/v1" + path) else { return nil }
        let json = Web.json(url, headers: ["Authorization": "Bearer \(dev)", "media-user-token": mut,
                                            "Origin": "https://music.apple.com", "Referer": "https://music.apple.com/"]) as? [String: Any]
        if json == nil { defaults.removeObject(forKey: "acct.apple.dev") }
        return json
    }

    // YouTube Music: InnerTube có đăng nhập (cookie + SAPISIDHASH).
    private func ytBrowse(_ browseId: String) -> [String: Any]? {
        guard let cookie = Keychain.get("youtube.cookie"), let sapisid = cookie.components(separatedBy: "; ")
            .first(where: { $0.hasPrefix("SAPISID=") })?.dropFirst(8) else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let origin = "https://music.youtube.com"
        let hash = AccountSync.sha1Hex("\(now) \(sapisid) \(origin)")
        let version = "1.20240501.01.00"
        let body: [String: Any] = ["context": ["client": ["clientName": "WEB_REMIX", "clientVersion": version, "hl": "vi", "gl": "VN"]],
                                   "browseId": browseId]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else { return nil }
        let headers = ["Cookie": cookie, "Authorization": "SAPISIDHASH \(now)_\(hash)", "X-Goog-AuthUser": "0",
                       "X-Origin": origin, "Origin": origin, "Referer": origin + "/", "Content-Type": "application/json",
                       "X-YouTube-Client-Name": "67", "X-YouTube-Client-Version": version]
        return postSync("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false", headers: headers, body: data)
    }

    private static func sha1Hex(_ text: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        let data = Data(text.utf8)
        data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            _ = CC_SHA1(p.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Đọc danh sách từ từng dịch vụ (chạy ở luồng nền)

    private func fetchBlocking(_ url: URL) -> Result<ImportedCollection, UpdateError> {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<ImportedCollection, UpdateError> = .failure(UpdateError("Không đọc được link."))
        DispatchQueue.main.async {
            PlaylistImporter.shared.fetch(url) { r in
                result = r
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + 90)
        return result
    }

    private func spotifyTrack(_ t: [String: Any]) -> SyncTrack? {
        guard let id = t["id"] as? String, let name = t["name"] as? String else { return nil }
        let artists = ((t["artists"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
        let ms = (t["duration_ms"] as? NSNumber)?.doubleValue ?? 0
        return SyncTrack(key: "sp:" + id, track: ImportedTrack(title: name, artist: artists, duration: ms > 0 ? ms / 1000 : nil))
    }

    private func spotifyLists() -> [SyncList] {
        var lists: [SyncList] = []
        var liked: [SyncTrack] = []
        var offset = 0
        while offset < 300 {
            guard let j = spotifyGET("/me/tracks?limit=50&offset=\(offset)"), let items = j["items"] as? [[String: Any]], !items.isEmpty else { break }
            for it in items { if let t = it["track"] as? [String: Any], let st = spotifyTrack(t) { liked.append(st) } }
            if items.count < 50 { break }
            offset += 50
        }
        lists.append(SyncList(key: "acct:spotify:liked", name: "Bài hát đã thích (Spotify)", tracks: liked))
        var owned: [(String, String)] = []
        offset = 0
        while offset < 200 {
            guard let j = spotifyGET("/me/playlists?limit=50&offset=\(offset)"), let items = j["items"] as? [[String: Any]], !items.isEmpty else { break }
            for p in items { if let id = p["id"] as? String, let name = p["name"] as? String { owned.append((id, name)) } }
            if items.count < 50 { break }
            offset += 50
        }
        for (id, name) in owned.prefix(40) {
            var tracks: [SyncTrack] = []
            var o = 0
            var path = "items"
            while o < 200 {
                var page = spotifyGET("/playlists/\(id)/\(path)?limit=100&offset=\(o)")
                if page == nil && o == 0 && path == "items" {
                    path = "tracks"
                    page = spotifyGET("/playlists/\(id)/tracks?limit=100&offset=0")
                }
                guard let j = page, let items = j["items"] as? [[String: Any]], !items.isEmpty else { break }
                for it in items {
                    if let t = (it["track"] ?? it["item"]) as? [String: Any], let st = spotifyTrack(t) { tracks.append(st) }
                }
                if items.count < 100 { break }
                o += 100
            }
            if !tracks.isEmpty { lists.append(SyncList(key: "acct:spotify:playlist:\(id)", name: "\(name) (Spotify)", tracks: tracks)) }
        }
        return lists
    }

    private func deezerTracks(_ path: String, cap: Int) -> [SyncTrack] {
        var out: [SyncTrack] = []
        var index = 0
        while index < cap {
            guard let url = URL(string: "https://api.deezer.com\(path)?limit=100&index=\(index)"),
                  let j = Web.json(url) as? [String: Any], let data = j["data"] as? [[String: Any]], !data.isEmpty else { break }
            for t in data {
                guard let id = t["id"] as? Int, let title = t["title"] as? String else { continue }
                let artist = ((t["artist"] as? [String: Any])?["name"] as? String) ?? ""
                let sec = (t["duration"] as? NSNumber)?.doubleValue ?? 0
                out.append(SyncTrack(key: "dz:\(id)", track: ImportedTrack(title: title, artist: artist, duration: sec > 0 ? sec : nil)))
            }
            if j["next"] == nil { break }
            index += 100
        }
        return out
    }

    private func dzSong(_ t: [String: Any]) -> SyncTrack? {
        guard let id = t["SNG_ID"], let title = t["SNG_TITLE"] as? String else { return nil }
        let artist = (t["ART_NAME"] as? String) ?? ""
        let sec = Double("\(t["DURATION"] ?? "")") ?? 0
        return SyncTrack(key: "dz:\(id)", track: ImportedTrack(title: title, artist: artist, duration: sec > 0 ? sec : nil))
    }

    private func deezerPrivateLists(uid: String) -> [SyncList] {
        guard let token = dzToken() else { return [] }
        var lists: [SyncList] = []
        if let r = dzGW("deezer.pageProfile", token: token, body: ["user_id": uid, "tab": "loved", "nb": 300]),
           let tab = r["TAB"] as? [String: Any], let loved = tab["loved"] as? [String: Any], let data = loved["data"] as? [[String: Any]] {
            lists.append(SyncList(key: "acct:deezer:liked", name: "Bài hát đã thích (Deezer)", tracks: data.compactMap { dzSong($0) }))
        }
        if let r = dzGW("deezer.pageProfile", token: token, body: ["user_id": uid, "tab": "playlists", "nb": 100]),
           let tab = r["TAB"] as? [String: Any], let pl = tab["playlists"] as? [String: Any], let data = pl["data"] as? [[String: Any]] {
            for p in data.prefix(40) {
                guard let pid = p["PLAYLIST_ID"], let title = p["TITLE"] as? String else { continue }
                if let r2 = dzGW("deezer.pagePlaylist", token: token, body: ["playlist_id": "\(pid)", "lang": "en", "nb": 200, "start": 0, "tags": true]),
                   let songs = r2["SONGS"] as? [String: Any], let sd = songs["data"] as? [[String: Any]] {
                    let tracks = sd.compactMap { dzSong($0) }
                    if !tracks.isEmpty { lists.append(SyncList(key: "acct:deezer:playlist:\(pid)", name: "\(title) (Deezer)", tracks: tracks)) }
                }
            }
        }
        return lists
    }

    private func deezerLists() -> [SyncList] {
        guard let uid = accountId(.deezer) else { return [] }
        let priv = deezerPrivateLists(uid: uid)
        if !priv.isEmpty { return priv }
        var lists: [SyncList] = []
        lists.append(SyncList(key: "acct:deezer:liked", name: "Bài hát đã thích (Deezer)", tracks: deezerTracks("/user/\(uid)/tracks", cap: 300)))
        if let url = URL(string: "https://api.deezer.com/user/\(uid)/playlists?limit=100"),
           let j = Web.json(url) as? [String: Any], let data = j["data"] as? [[String: Any]] {
            for p in data.prefix(40) {
                guard let id = p["id"] as? Int, let title = p["title"] as? String else { continue }
                let tracks = deezerTracks("/playlist/\(id)/tracks", cap: 200)
                if !tracks.isEmpty { lists.append(SyncList(key: "acct:deezer:playlist:\(id)", name: "\(title) (Deezer)", tracks: tracks)) }
            }
        }
        return lists
    }

    private func scResolve(_ link: String, clientId: String) -> [String: Any]? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let enc = link.addingPercentEncoding(withAllowedCharacters: allowed) ?? link
        guard let url = URL(string: "https://api-v2.soundcloud.com/resolve?url=\(enc)&client_id=\(clientId)") else { return nil }
        return Web.json(url) as? [String: Any]
    }

    private func scTrack(_ t: [String: Any]) -> SyncTrack? {
        guard let id = t["id"] as? Int, let title = t["title"] as? String else { return nil }
        let artist = ((t["user"] as? [String: Any])?["username"] as? String) ?? ""
        let ms = (t["duration"] as? NSNumber)?.doubleValue ?? 0
        return SyncTrack(key: "sc:\(id)", track: ImportedTrack(title: title, artist: artist, duration: ms > 0 ? ms / 1000 : nil))
    }

    private func soundCloudLists() -> [SyncList] {
        guard let uid = accountId(.soundCloud) else { return [] }
        let auth: [String: String] = Keychain.get("soundcloud.token").map { ["Authorization": "OAuth \($0)"] } ?? [:]
        var cid = defaults.string(forKey: "acct.soundCloud.client.cid") ?? ""
        func probe() -> Bool {
            guard !cid.isEmpty, let url = URL(string: "https://api-v2.soundcloud.com/users/\(uid)?client_id=\(cid)") else { return false }
            return Web.json(url, headers: auth) != nil
        }
        if !probe() {
            guard let page = Web.string(URL(string: "https://soundcloud.com")!),
                  let fresh = PlaylistImporter.shared.soundCloudClientId(html: page.text) else { return [] }
            cid = fresh
            defaults.set(cid, forKey: "acct.soundCloud.client.cid")
        }
        var lists: [SyncList] = []
        var liked: [SyncTrack] = []
        var next: String? = "https://api-v2.soundcloud.com/users/\(uid)/likes?limit=50&client_id=\(cid)"
        var pages = 0
        while let link = next, pages < 6, let url = URL(string: link), let j = Web.json(url, headers: auth) as? [String: Any] {
            for item in (j["collection"] as? [[String: Any]]) ?? [] {
                if let t = item["track"] as? [String: Any], let st = scTrack(t) { liked.append(st) }
            }
            if let n = j["next_href"] as? String { next = n + "&client_id=\(cid)" } else { next = nil }
            pages += 1
        }
        lists.append(SyncList(key: "acct:soundCloud:liked", name: "Bài hát đã thích (SoundCloud)", tracks: liked))
        if let url = URL(string: "https://api-v2.soundcloud.com/users/\(uid)/playlists_without_albums?limit=50&client_id=\(cid)"),
           let j = Web.json(url, headers: auth) as? [String: Any], let cols = j["collection"] as? [[String: Any]] {
            for p in cols.prefix(40) {
                guard let pid = p["id"] as? Int, let title = p["title"] as? String else { continue }
                var tracks: [SyncTrack] = []
                var missing: [Int] = []
                for t in (p["tracks"] as? [[String: Any]]) ?? [] {
                    if let st = scTrack(t) { tracks.append(st) } else if let id = t["id"] as? Int { missing.append(id) }
                }
                var index = 0
                while index < missing.count {
                    let chunk = missing[index..<min(index + 30, missing.count)].map(String.init).joined(separator: ",")
                    if let u = URL(string: "https://api-v2.soundcloud.com/tracks?ids=\(chunk)&client_id=\(cid)"),
                       let arr = Web.json(u, headers: auth) as? [[String: Any]] {
                        for t in arr { if let st = scTrack(t) { tracks.append(st) } }
                    }
                    index += 30
                }
                if !tracks.isEmpty { lists.append(SyncList(key: "acct:soundCloud:playlist:\(pid)", name: "\(title) (SoundCloud)", tracks: tracks)) }
            }
        }
        return lists
    }

    private func appleTrack(_ d: [String: Any]) -> SyncTrack? {
        guard let id = d["id"] as? String, let a = d["attributes"] as? [String: Any], let name = a["name"] as? String else { return nil }
        let ms = (a["durationInMillis"] as? NSNumber)?.doubleValue ?? 0
        return SyncTrack(key: "ap:" + id, track: ImportedTrack(title: name, artist: (a["artistName"] as? String) ?? "", duration: ms > 0 ? ms / 1000 : nil))
    }

    private func appleLists() -> [SyncList] {
        var lists: [SyncList] = []
        var songs: [SyncTrack] = []
        var offset = 0
        while offset < 300 {
            guard let j = appleGET("/me/library/songs?limit=100&offset=\(offset)"), let data = j["data"] as? [[String: Any]], !data.isEmpty else { break }
            songs.append(contentsOf: data.compactMap { appleTrack($0) })
            if data.count < 100 { break }
            offset += 100
        }
        lists.append(SyncList(key: "acct:appleMusic:library", name: "Thư viện (Apple Music)", tracks: songs))
        if let j = appleGET("/me/library/playlists?limit=100"), let data = j["data"] as? [[String: Any]] {
            for p in data.prefix(40) {
                guard let id = p["id"] as? String, let a = p["attributes"] as? [String: Any], let name = a["name"] as? String else { continue }
                var tracks: [SyncTrack] = []
                var o = 0
                while o < 200 {
                    guard let t = appleGET("/me/library/playlists/\(id)/tracks?limit=100&offset=\(o)"), let td = t["data"] as? [[String: Any]], !td.isEmpty else { break }
                    tracks.append(contentsOf: td.compactMap { appleTrack($0) })
                    if td.count < 100 { break }
                    o += 100
                }
                if !tracks.isEmpty { lists.append(SyncList(key: "acct:appleMusic:playlist:\(id)", name: "\(name) (Apple Music)", tracks: tracks)) }
            }
        }
        return lists
    }

    private func ytLists() -> [SyncList] {
        var lists: [SyncList] = []
        if let j = ytBrowse("VLLM") {
            let songs = InnerTube.parseSongs(j)
            if !songs.isEmpty { lists.append(SyncList(key: "acct:youtubeMusic:liked", name: "Bài hát đã thích (YouTube Music)", tracks: [], directSongs: songs)) }
        }
        var found: [(String, String)] = []
        func walk(_ node: Any) {
            if let d = node as? [String: Any] {
                if let r = d["musicTwoRowItemRenderer"] as? [String: Any],
                   let id = InnerTube.dig(r, ["navigationEndpoint", "browseEndpoint", "browseId"]) as? String, id.hasPrefix("VL"),
                   let title = InnerTube.dig(r, ["title", "runs", 0, "text"]) as? String {
                    found.append((id, title))
                }
                for v in d.values { walk(v) }
            } else if let a = node as? [Any] {
                for v in a { walk(v) }
            }
        }
        if let j = ytBrowse("FEmusic_liked_playlists") { walk(j) }
        for (id, title) in found.prefix(30) where id != "VLLM" {
            if let j = ytBrowse(id) {
                let songs = InnerTube.parseSongs(j)
                if !songs.isEmpty { lists.append(SyncList(key: "acct:youtubeMusic:playlist:\(id)", name: "\(title) (YouTube Music)", tracks: [], directSongs: songs)) }
            }
        }
        return lists
    }

    private func linkLists(_ s: MusicService) -> [SyncList] {
        var lists: [SyncList] = []
        for link in links(s) {
            guard let url = URL(string: link), case .success(let c) = fetchBlocking(url) else { continue }
            var tracks: [SyncTrack] = []
            for t in c.tracks {
                let key = "pl:" + SongMatcher.normalize(t.title) + "|" + SongMatcher.normalize(t.artist)
                tracks.append(SyncTrack(key: key, track: t))
            }
            lists.append(SyncList(key: "acct:\(s.rawValue):\(link)", name: "\(c.name) (\(s.title))", tracks: tracks, directSongs: c.directSongs))
        }
        return lists
    }

    // MARK: Đồng bộ

    func syncSoon(_ s: MusicService) {
        DispatchQueue.main.async {
            if self.syncing { return }
            self.syncing = true
            Toast.show("Đang đồng bộ \(s.title)…")
            DispatchQueue.global(qos: .utility).async {
                self.syncOne(s)
                DispatchQueue.main.async { self.syncing = false }
            }
        }
    }

    /// Đồng bộ lại tất cả tài khoản đã liên kết (gọi thủ công).
    func syncAll(manual: Bool) {
        DispatchQueue.main.async {
            let services = self.linkedServices
            if services.isEmpty || self.syncing { return }
            self.syncing = true
            if manual { Toast.show("Đang đồng bộ tài khoản nhạc…") }
            DispatchQueue.global(qos: .utility).async {
                for s in services { self.syncOne(s) }
                self.defaults.set(Date().timeIntervalSince1970, forKey: "acct.lastSync")
                DispatchQueue.main.async { self.syncing = false }
            }
        }
    }

    /// Tự đồng bộ mỗi khi mở app nếu đã quá 12 giờ.
    func autoSyncIfNeeded() {
        let last = defaults.double(forKey: "acct.lastSync")
        if Date().timeIntervalSince1970 - last > 12 * 3600 { syncAll(manual: false) }
    }

    private func loadCache() {
        lock.lock()
        defer { lock.unlock() }
        if cacheLoaded { return }
        cacheLoaded = true
        if let data = try? Data(contentsOf: cacheURL()), let file = try? JSONDecoder().decode(MatchCacheFile.self, from: data) {
            cacheFile = file
        }
    }

    private func cacheURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("account_match_cache.json")
    }

    private func saveCache() {
        lock.lock()
        let file = cacheFile
        lock.unlock()
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: cacheURL(), options: .atomic) }
    }

    private func publish(_ lists: [SyncList], _ s: MusicService) {
        lock.lock()
        let songsByKey = cacheFile.songs
        lock.unlock()
        DispatchQueue.main.sync {
            for l in lists {
                var songs = l.directSongs
                for t in l.tracks { if let song = songsByKey[t.key] { songs.append(song) } }
                if songs.isEmpty && l.tracks.isEmpty { continue }
                Library.shared.importPlaylist(name: l.name, songs: songs, sourceURL: l.key, cover: s.rawValue)
            }
        }
    }

    private func syncOne(_ s: MusicService) {
        loadCache()
        let all: [SyncList]
        switch s {
        case .spotify: all = spotifyLists()
        case .deezer: all = deezerLists()
        case .soundCloud: all = soundCloudLists()
        case .appleMusic: all = appleLists()
        case .youtubeMusic: all = ytLists()
        }
        let skip = dismissed
        let lists = all.filter { !skip.contains($0.key) }
        if lists.isEmpty {
            Toast.show("\(s.title): chưa đọc được playlist nào (kiểm tra quyền công khai/mạng).")
            return
        }
        publish(lists, s)

        var pending: [SyncTrack] = []
        var seen = Set<String>()
        lock.lock()
        for l in lists {
            for t in l.tracks where cacheFile.songs[t.key] == nil && !cacheFile.missed.contains(t.key) && !seen.contains(t.key) {
                seen.insert(t.key)
                pending.append(t)
            }
        }
        lock.unlock()
        let remaining = max(0, pending.count - maxMatchesPerRun)
        pending = Array(pending.prefix(maxMatchesPerRun))

        if !pending.isEmpty {
            let gate = DispatchSemaphore(value: 3)
            let group = DispatchGroup()
            var done = 0
            let total = pending.count
            for t in pending {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    gate.wait()
                    let song = PlaylistImporter.shared.bestMatch(for: t.track)
                    self.lock.lock()
                    if let song = song { self.cacheFile.songs[t.key] = song } else { self.cacheFile.missed.append(t.key) }
                    done += 1
                    let n = done
                    self.lock.unlock()
                    gate.signal()
                    if n % 60 == 0 {
                        self.saveCache()
                        Toast.show("\(s.title): đã ghép \(n)/\(total) bài…")
                    }
                    group.leave()
                }
            }
            group.wait()
            saveCache()
            publish(lists, s)
        }
        var songCount = 0
        lock.lock()
        for l in lists {
            songCount += l.directSongs.count
            for t in l.tracks where cacheFile.songs[t.key] != nil { songCount += 1 }
        }
        lock.unlock()
        var message = "Đồng bộ \(s.title) xong: \(lists.count) playlist, \(songCount) bài."
        if remaining > 0 { message += " Còn \(remaining) bài sẽ ghép ở lần đồng bộ sau." }
        Toast.show(message)
    }
}
