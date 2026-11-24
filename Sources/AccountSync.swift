import UIKit
import AuthenticationServices
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

@available(iOS 13.0, *)
private final class AuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return (UIApplication.shared.delegate as? AppDelegate)?.window ?? ASPresentationAnchor()
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
    static let spotifyRedirect = "mochyios://spotify-callback"

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var cacheFile = MatchCacheFile()
    private var cacheLoaded = false
    private var authSession: AnyObject?
    private var anchor: AnyObject?
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
        Keychain.set(nil, for: "spotify.access")
        if s == .spotify {
            Keychain.set(nil, for: "spotify.refresh")
            defaults.removeObject(forKey: "acct.spotify.expiry")
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

    // MARK: Liên kết

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
        switch s {
        case .spotify: connectSpotify(from: presenter, finish)
        case .deezer: connectDeezer(from: presenter, finish)
        case .soundCloud: connectSoundCloud(from: presenter, finish)
        case .appleMusic, .youtubeMusic: connectLink(s, from: presenter, finish)
        }
    }

    private func connectLink(_ s: MusicService, from presenter: UIViewController,
                             _ finish: @escaping (Result<String, UpdateError>) -> Void) {
        AccountSync.prompt(from: presenter, title: "Liên kết \(s.title)",
                           message: "\(s.title) không cho ứng dụng ngoài đăng nhập tài khoản. Hãy dán link một playlist (hoặc album) công khai; Mochy sẽ tạo playlist và tự cập nhật khi có bài mới. Có thể thêm nhiều link.",
                           placeholder: "https://…", action: "Liên kết") { text in
            guard let text = text else { finish(.failure(AccountSync.cancelled())); return }
            guard let url = PlaylistImporter.extractURL(text), PlaylistImporter.source(of: text) == s.importSource else {
                finish(.failure(UpdateError("Link không phải của \(s.title).")))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                switch self.fetchBlocking(url) {
                case .failure(let e):
                    finish(.failure(e))
                case .success:
                    var l = self.links(s)
                    if !l.contains(url.absoluteString) { l.append(url.absoluteString) }
                    self.setLinks(s, l)
                    self.setAccount(s, name: "\(l.count) playlist")
                    finish(.success("\(l.count) playlist"))
                }
            }
        }
    }

    private func connectDeezer(from presenter: UIViewController, _ finish: @escaping (Result<String, UpdateError>) -> Void) {
        AccountSync.prompt(from: presenter, title: "Liên kết Deezer",
                           message: "Dán link hồ sơ Deezer của bạn (deezer.com/…/profile/số) hoặc chỉ ID. Playlist và bài yêu thích cần để chế độ công khai.",
                           placeholder: "deezer.com/vi/profile/123456", text: accountId(.deezer), action: "Liên kết") { text in
            guard let text = text else { finish(.failure(AccountSync.cancelled())); return }
            var digits = ""
            if let r = text.range(of: "profile/") {
                digits = String(text[r.upperBound...]).prefix(while: { $0.isNumber }).description
            } else {
                digits = text.filter { $0.isNumber }
            }
            guard !digits.isEmpty else { finish(.failure(UpdateError("Không nhận ra ID Deezer."))); return }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let url = URL(string: "https://api.deezer.com/user/\(digits)"),
                      let info = Web.json(url) as? [String: Any], info["error"] == nil else {
                    finish(.failure(UpdateError("Không tìm thấy hồ sơ Deezer này.")))
                    return
                }
                let name = (info["name"] as? String) ?? "Deezer \(digits)"
                self.setAccount(.deezer, name: name, id: digits)
                finish(.success(name))
            }
        }
    }

    private func connectSoundCloud(from presenter: UIViewController, _ finish: @escaping (Result<String, UpdateError>) -> Void) {
        AccountSync.prompt(from: presenter, title: "Liên kết SoundCloud",
                           message: "Dán link hồ sơ SoundCloud của bạn (soundcloud.com/tên-của-bạn). Bài đã thích và playlist cần để chế độ công khai.",
                           placeholder: "soundcloud.com/ten-cua-ban", action: "Liên kết") { text in
            guard let text = text else { finish(.failure(AccountSync.cancelled())); return }
            var raw = text
            if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
            guard let url = URL(string: raw), (url.host ?? "").contains("soundcloud.com") else {
                finish(.failure(UpdateError("Link SoundCloud không hợp lệ.")))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let page = Web.string(url), let cid = PlaylistImporter.shared.soundCloudClientId(html: page.text),
                      let user = self.scResolve(url.absoluteString, clientId: cid),
                      let id = user["id"] as? Int else {
                    finish(.failure(UpdateError("Không đọc được hồ sơ SoundCloud. Kiểm tra link và mạng.")))
                    return
                }
                let name = (user["username"] as? String) ?? "SoundCloud"
                self.defaults.set(cid, forKey: "acct.soundCloud.client.cid")
                self.setAccount(.soundCloud, name: name, id: String(id))
                finish(.success(name))
            }
        }
    }

    // MARK: Spotify (OAuth PKCE)

    private func connectSpotify(from presenter: UIViewController, _ finish: @escaping (Result<String, UpdateError>) -> Void) {
        let saved = defaults.string(forKey: "acct.spotify.client") ?? ""
        let go: (String) -> Void = { clientId in
            self.defaults.set(clientId, forKey: "acct.spotify.client")
            self.authorizeSpotify(clientId: clientId, finish)
        }
        if !saved.isEmpty { go(saved); return }
        AccountSync.prompt(from: presenter, title: "Spotify Client ID",
                           message: "Spotify chỉ cho đăng nhập qua ứng dụng do bạn đăng ký. Vào developer.spotify.com/dashboard ▸ Create app, thêm Redirect URI: \(AccountSync.spotifyRedirect) (chọn Web API), nếu app ở chế độ Development thì thêm email của bạn trong User Management. Rồi dán Client ID vào đây.",
                           placeholder: "Client ID (32 ký tự)", action: "Đăng nhập") { text in
            guard let text = text else { finish(.failure(AccountSync.cancelled())); return }
            go(text)
        }
    }

    private func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var out = ""
        for _ in 0..<length { out.append(chars[Int(arc4random_uniform(UInt32(chars.count)))]) }
        return out
    }

    private func challenge(_ verifier: String) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let data = Data(verifier.utf8)
        data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            _ = CC_SHA256(p.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func authorizeSpotify(clientId: String, _ finish: @escaping (Result<String, UpdateError>) -> Void) {
        let verifier = randomString(64)
        let state = randomString(16)
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AccountSync.spotifyRedirect),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge(verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "user-library-read playlist-read-private playlist-read-collaborative")
        ]
        guard let url = comps.url else { finish(.failure(UpdateError("Không tạo được địa chỉ đăng nhập."))); return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "mochyios") { callback, error in
            self.authSession = nil
            if let error = error {
                let ns = error as NSError
                if ns.domain == ASWebAuthenticationSessionErrorDomain && ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    finish(.failure(AccountSync.cancelled()))
                } else {
                    finish(.failure(UpdateError("Đăng nhập Spotify lỗi: \(error.localizedDescription)")))
                }
                return
            }
            guard let callback = callback, let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
                finish(.failure(UpdateError("Spotify không trả kết quả.")))
                return
            }
            if let err = items.first(where: { $0.name == "error" })?.value {
                finish(.failure(UpdateError("Spotify từ chối: \(err)")))
                return
            }
            guard let code = items.first(where: { $0.name == "code" })?.value,
                  items.first(where: { $0.name == "state" })?.value == state else {
                finish(.failure(UpdateError("Phản hồi đăng nhập Spotify không hợp lệ.")))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let body = ["grant_type": "authorization_code", "code": code, "redirect_uri": AccountSync.spotifyRedirect,
                            "client_id": clientId, "code_verifier": verifier]
                guard let token = self.postForm("https://accounts.spotify.com/api/token", body) else {
                    finish(.failure(UpdateError("Không đổi được mã đăng nhập Spotify (kiểm tra Client ID và Redirect URI).")))
                    return
                }
                guard self.storeSpotify(token) else {
                    finish(.failure(UpdateError("Spotify không cấp token.")))
                    return
                }
                guard let me = self.spotifyGET("/me") else {
                    finish(.failure(UpdateError("Không đọc được hồ sơ Spotify. Nếu app ở chế độ Development, hãy thêm email của bạn vào User Management.")))
                    return
                }
                let name = (me["display_name"] as? String) ?? (me["id"] as? String) ?? "Spotify"
                self.setAccount(.spotify, name: name, id: me["id"] as? String)
                finish(.success(name))
            }
        }
        if #available(iOS 13.0, *) {
            let a = AuthAnchor()
            anchor = a
            session.presentationContextProvider = a
        }
        authSession = session
        if !session.start() {
            authSession = nil
            finish(.failure(UpdateError("Không mở được trang đăng nhập Spotify.")))
        }
    }

    private func storeSpotify(_ token: [String: Any]) -> Bool {
        guard let access = token["access_token"] as? String else { return false }
        Keychain.set(access, for: "spotify.access")
        if let refresh = token["refresh_token"] as? String { Keychain.set(refresh, for: "spotify.refresh") }
        let life = (token["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        defaults.set(Date().timeIntervalSince1970 + life, forKey: "acct.spotify.expiry")
        return true
    }

    private func spotifyToken() -> String? {
        let expiry = defaults.double(forKey: "acct.spotify.expiry")
        if let access = Keychain.get("spotify.access"), Date().timeIntervalSince1970 < expiry - 60 { return access }
        guard let refresh = Keychain.get("spotify.refresh"), let client = defaults.string(forKey: "acct.spotify.client") else { return nil }
        guard let token = postForm("https://accounts.spotify.com/api/token",
                                   ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": client]),
              storeSpotify(token) else { return nil }
        return Keychain.get("spotify.access")
    }

    private func spotifyGET(_ path: String) -> [String: Any]? {
        guard let token = spotifyToken(), let url = URL(string: "https://api.spotify.com/v1" + path) else { return nil }
        return Web.json(url, headers: ["Authorization": "Bearer \(token)"]) as? [String: Any]
    }

    private func postForm(_ urlString: String, _ params: [String: String]) -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = params.map { k, v in "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)" }.joined(separator: "&")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data { out = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] }
            sem.signal()
        }.resume()
        sem.wait()
        if out?["error"] != nil { return nil }
        return out
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

    private func deezerLists() -> [SyncList] {
        guard let uid = accountId(.deezer) else { return [] }
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
        var cid = defaults.string(forKey: "acct.soundCloud.client.cid") ?? ""
        func probe() -> Bool {
            guard !cid.isEmpty, let url = URL(string: "https://api-v2.soundcloud.com/users/\(uid)?client_id=\(cid)") else { return false }
            return Web.json(url) != nil
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
        while let link = next, pages < 6, let url = URL(string: link), let j = Web.json(url) as? [String: Any] {
            for item in (j["collection"] as? [[String: Any]]) ?? [] {
                if let t = item["track"] as? [String: Any], let st = scTrack(t) { liked.append(st) }
            }
            if let n = j["next_href"] as? String { next = n + "&client_id=\(cid)" } else { next = nil }
            pages += 1
        }
        lists.append(SyncList(key: "acct:soundCloud:liked", name: "Bài hát đã thích (SoundCloud)", tracks: liked))
        if let url = URL(string: "https://api-v2.soundcloud.com/users/\(uid)/playlists_without_albums?limit=50&client_id=\(cid)"),
           let j = Web.json(url) as? [String: Any], let cols = j["collection"] as? [[String: Any]] {
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
                       let arr = Web.json(u) as? [[String: Any]] {
                        for t in arr { if let st = scTrack(t) { tracks.append(st) } }
                    }
                    index += 30
                }
                if !tracks.isEmpty { lists.append(SyncList(key: "acct:soundCloud:playlist:\(pid)", name: "\(title) (SoundCloud)", tracks: tracks)) }
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
        case .appleMusic, .youtubeMusic: all = linkLists(s)
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
