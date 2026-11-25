import Foundation
import UIKit

extension Notification.Name {
    static let cloudStateChanged = Notification.Name("MochyiOSCloudStateChanged")
}

/// Địa chỉ máy chủ tài khoản Mochy (Cloudflare Worker trong thư mục server/). Để trống thì tính năng tài khoản báo "chưa cấu hình".
enum CloudConfig {
    static let baseURL = "https://mochy-cloud.pucpucput.workers.dev"
}

/// Dữ liệu đồng bộ của một tài khoản Mochy.
struct CloudBlob: Codable {
    var library: Library.Store
    var settings: BackupManager.Settings
    var plays: [PlayRecord]?
    var downloaded: [Song]?
}

/// Tài khoản Mochy: đăng ký/đăng nhập với máy chủ, giữ phiên trong Keychain, đồng bộ thư viện hai chiều.
/// Quy tắc: nếu máy này chưa có thay đổi nào chưa đồng bộ thì lấy nguyên dữ liệu từ máy chủ (xoá cũng được đồng bộ);
/// nếu cả hai bên cùng đổi thì GỘP (không mất gì) rồi đẩy lên.
final class MochyCloud {
    static let shared = MochyCloud()

    private let queue = DispatchQueue(label: "mochyios.cloud")
    private var pushWork: DispatchWorkItem?
    private var syncing = false
    private var pending = false
    private(set) var lastError: String?
    private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "cloud.lastSync") as? Date

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryChanged, object: nil)
    }

    var isConfigured: Bool { return URL(string: CloudConfig.baseURL)?.host != nil }
    var token: String? { return Keychain.get("mochy.token") }
    var username: String? { return Keychain.get("mochy.user") }
    var isLoggedIn: Bool { return token != nil && username != nil }
    private var version: Int {
        get { return UserDefaults.standard.integer(forKey: "cloud.version") }
        set { UserDefaults.standard.set(newValue, forKey: "cloud.version") }
    }
    private var lastHash: String? {
        get { return UserDefaults.standard.string(forKey: "cloud.hash") }
        set { UserDefaults.standard.set(newValue, forKey: "cloud.hash") }
    }

    // MARK: - Mạng

    private func request(_ path: String, method: String, body: [String: Any]?, auth: Bool,
                         completion: @escaping (Int, [String: Any]?) -> Void) {
        guard isConfigured, let url = URL(string: CloudConfig.baseURL + path) else {
            completion(0, ["error": "Máy chủ tài khoản chưa được cấu hình."])
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        if let body = body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth, let token = token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        URLSession.shared.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var json: [String: Any]?
            if let data = data { json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] }
            if status == 0 && json == nil { json = ["error": error?.localizedDescription ?? "Không kết nối được máy chủ."] }
            DispatchQueue.main.async { completion(status, json) }
        }.resume()
    }

    // MARK: - Tài khoản

    func authenticate(register: Bool, username: String, password: String, completion: @escaping (String?) -> Void) {
        let path = register ? "/register" : "/login"
        request(path, method: "POST", body: ["username": username, "password": password], auth: false) { status, json in
            guard status == 200, let token = json?["token"] as? String, let name = json?["username"] as? String else {
                completion((json?["error"] as? String) ?? "Không thực hiện được (mã \(status)).")
                return
            }
            Keychain.set(token, for: "mochy.token")
            Keychain.set(name, for: "mochy.user")
            self.version = 0
            self.lastHash = nil
            self.lastError = nil
            NotificationCenter.default.post(name: .cloudStateChanged, object: nil)
            completion(nil)
            self.syncNow(firstAfterLogin: true)
        }
    }

    func logout() {
        request("/logout", method: "POST", body: nil, auth: true) { _, _ in }
        clearSession()
    }

    private func clearSession() {
        Keychain.set(nil, for: "mochy.token")
        Keychain.set(nil, for: "mochy.user")
        version = 0
        lastHash = nil
        lastSync = nil
        try? FileManager.default.removeItem(at: avatarFile)
        cachedAvatar = nil
        UserDefaults.standard.removeObject(forKey: "cloud.badges")
        UserDefaults.standard.removeObject(forKey: "cloud.lastSync")
        NotificationCenter.default.post(name: .cloudStateChanged, object: nil)
    }

    func changePassword(old: String, new: String, completion: @escaping (String?) -> Void) {
        request("/password", method: "POST", body: ["oldPassword": old, "newPassword": new], auth: true) { status, json in
            completion(status == 200 ? nil : ((json?["error"] as? String) ?? "Không đổi được mật khẩu."))
        }
    }

    func deleteAccount(completion: @escaping (String?) -> Void) {
        request("/account", method: "DELETE", body: nil, auth: true) { status, json in
            if status == 200 {
                self.clearSession()
                completion(nil)
            } else {
                completion((json?["error"] as? String) ?? "Không xoá được tài khoản.")
            }
        }
    }

    // MARK: - Huy hiệu (tick xanh/đen, owner) do chủ app cấp trên máy chủ

    var badges: [String] { return UserDefaults.standard.stringArray(forKey: "cloud.badges") ?? [] }
    var isVerified: Bool { return badges.contains("verified") }
    var isOwner: Bool { return badges.contains("owner") }

    func refreshProfile() {
        guard isLoggedIn else { return }
        request("/profile", method: "GET", body: nil, auth: true) { status, json in
            guard status == 200, let list = json?["badges"] as? [String] else { return }
            if list != self.badges {
                UserDefaults.standard.set(list, forKey: "cloud.badges")
                NotificationCenter.default.post(name: .cloudStateChanged, object: nil)
            }
        }
    }

    // MARK: - Ảnh đại diện

    private var avatarFile: URL { return Library.supportDirectory.appendingPathComponent("avatar.jpg") }
    private var cachedAvatar: UIImage?

    /// Ảnh đại diện của tài khoản đang đăng nhập (lưu sẵn trên máy, tự cập nhật từ máy chủ).
    var avatarImage: UIImage? {
        guard isLoggedIn else { return nil }
        if let image = cachedAvatar { return image }
        if let data = try? Data(contentsOf: avatarFile), let image = UIImage(data: data) {
            cachedAvatar = image
            return image
        }
        return nil
    }

    private func setLocalAvatar(_ data: Data?) {
        if let data = data, let image = UIImage(data: data) {
            try? data.write(to: avatarFile, options: .atomic)
            cachedAvatar = image
        } else {
            try? FileManager.default.removeItem(at: avatarFile)
            cachedAvatar = nil
        }
        NotificationCenter.default.post(name: .cloudStateChanged, object: nil)
    }

    /// Thu ảnh về hình vuông 256px (JPEG) rồi tải lên.
    func uploadAvatar(_ image: UIImage, completion: @escaping (String?) -> Void) {
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let square = renderer.image { _ in
            let w = image.size.width, h = image.size.height
            let scale = max(side / max(w, 1), side / max(h, 1))
            let draw = CGSize(width: w * scale, height: h * scale)
            image.draw(in: CGRect(x: (side - draw.width) / 2, y: (side - draw.height) / 2, width: draw.width, height: draw.height))
        }
        guard let data = square.jpegData(compressionQuality: 0.82) else { completion("Không xử lý được ảnh."); return }
        request("/avatar", method: "PUT", body: ["image": data.base64EncodedString()], auth: true) { status, json in
            if status == 200 {
                self.setLocalAvatar(data)
                completion(nil)
            } else {
                completion((json?["error"] as? String) ?? "Không tải được ảnh lên.")
            }
        }
    }

    func removeAvatar(completion: @escaping (String?) -> Void) {
        request("/avatar", method: "DELETE", body: nil, auth: true) { status, json in
            if status == 200 {
                self.setLocalAvatar(nil)
                completion(nil)
            } else {
                completion((json?["error"] as? String) ?? "Không xoá được ảnh.")
            }
        }
    }

    func refreshAvatar() {
        guard isLoggedIn else { return }
        request("/avatar", method: "GET", body: nil, auth: true) { status, json in
            guard status == 200 else { return }
            if let text = json?["image"] as? String, let data = Data(base64Encoded: text) {
                self.setLocalAvatar(data)
            } else if self.cachedAvatar != nil || FileManager.default.fileExists(atPath: self.avatarFile.path) {
                self.setLocalAvatar(nil)
            }
        }
    }

    // MARK: - Dữ liệu

    private func makeBlob() -> CloudBlob {
        var store = Library.shared.snapshot()
        store.playlists = store.playlists.filter { $0.id != Library.cloudDownloadsId }
        let settings = BackupManager.Settings(quality: AppSettings.audioQuality.rawValue, video: AppSettings.videoBackdrop,
                                              blur: AppSettings.playerBlur.rawValue, lyricWeight: AppSettings.lyricWeight, theme: Theme.mode.rawValue)
        return CloudBlob(library: store, settings: settings, plays: PlayLog.shared.records, downloaded: Library.shared.downloads)
    }

    private func encode(_ blob: CloudBlob, sorted: Bool) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if sorted { encoder.outputFormatting = .sortedKeys }
        guard let data = try? encoder.encode(blob) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Dấu vân tay của phần cần đồng bộ (không tính lịch sử phát để khỏi đẩy lên liên tục).
    private func fingerprint(_ blob: CloudBlob) -> String {
        var copy = blob
        copy.plays = nil
        let text = encode(copy, sorted: true) ?? ""
        var h: UInt64 = 14695981039346656037
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }

    private func apply(_ blob: CloudBlob, replace: Bool) {
        if replace {
            Library.shared.replaceFromCloud(blob.library)
            let s = blob.settings
            if let q = AudioQuality(rawValue: s.quality) { AppSettings.audioQuality = q }
            AppSettings.videoBackdrop = s.video
            if let b = PlayerBlur(rawValue: s.blur) { AppSettings.playerBlur = b }
            AppSettings.lyricWeight = s.lyricWeight
            if let mode = ThemeMode(rawValue: s.theme), mode != Theme.mode {
                Theme.mode = mode
                NotificationCenter.default.post(name: .themeChanged, object: nil)
            }
        } else {
            Library.shared.merge(blob.library)
        }
        if let plays = blob.plays { PlayLog.shared.merge(plays) }
        if let downloaded = blob.downloaded { Library.shared.setCloudDownloads(downloaded) }
    }

    private func decode(_ text: String) -> CloudBlob? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(CloudBlob.self, from: Data(text.utf8))
    }

    // MARK: - Đồng bộ

    @objc private func libraryChanged() {
        guard isLoggedIn else { return }
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncNow() }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    /// Kéo dữ liệu mới từ máy chủ (nếu có) rồi đẩy thay đổi của máy này lên.
    func syncNow(firstAfterLogin: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard isLoggedIn, isConfigured else { completion?(false); return }
        if syncing { pending = true; completion?(false); return }
        syncing = true
        request("/data", method: "GET", body: nil, auth: true) { status, json in
            if status == 401 { self.finish(error: "Phiên đăng nhập hết hạn, hãy đăng nhập lại.", expired: true, completion: completion); return }
            guard status == 200, let json = json else {
                self.finish(error: (json?["error"] as? String) ?? "Không đồng bộ được.", completion: completion)
                return
            }
            let remoteVersion = (json["version"] as? Int) ?? 0
            let remoteBlob = (json["blob"] as? String).flatMap { self.decode($0) }
            let localFingerprint = self.fingerprint(self.makeBlob())
            let localChanged = localFingerprint != self.lastHash
            if let remote = remoteBlob, remoteVersion != self.version {
                // Máy chủ có bản mới hơn bản đã biết.
                let neverSynced = self.lastHash == nil
                let localEmpty = Library.shared.liked.isEmpty && Library.shared.playlists.isEmpty && Library.shared.history.isEmpty
                self.apply(remote, replace: (!localChanged && !neverSynced) || localEmpty)
                self.version = remoteVersion
                if !localChanged || localEmpty {
                    self.lastHash = self.fingerprint(self.makeBlob())
                    self.finish(error: nil, completion: completion)
                    return
                }
            } else if remoteBlob == nil {
                self.version = remoteVersion
            }
            self.pushIfNeeded(completion: completion)
        }
    }

    private func pushIfNeeded(retry: Bool = true, completion: ((Bool) -> Void)?) {
        let blob = makeBlob()
        let fp = fingerprint(blob)
        if fp == lastHash { finish(error: nil, completion: completion); return }
        guard let text = encode(blob, sorted: false) else { finish(error: "Không đóng gói được dữ liệu.", completion: completion); return }
        request("/data", method: "PUT", body: ["baseVersion": version, "blob": text], auth: true) { status, json in
            if status == 200, let v = json?["version"] as? Int {
                self.version = v
                self.lastHash = fp
                self.finish(error: nil, completion: completion)
            } else if status == 409, retry {
                // Máy khác vừa đẩy lên: gộp rồi thử lại một lần.
                if let t = json?["blob"] as? String, let remote = self.decode(t) { self.apply(remote, replace: false) }
                self.version = (json?["version"] as? Int) ?? self.version
                self.pushIfNeeded(retry: false, completion: completion)
            } else if status == 401 {
                self.finish(error: "Phiên đăng nhập hết hạn, hãy đăng nhập lại.", expired: true, completion: completion)
            } else {
                self.finish(error: (json?["error"] as? String) ?? "Không đồng bộ được.", completion: completion)
            }
        }
    }

    private func finish(error: String?, expired: Bool = false, completion: ((Bool) -> Void)?) {
        syncing = false
        lastError = error
        if error == nil {
            refreshAvatar()
            refreshProfile()
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: "cloud.lastSync")
        }
        if expired { clearSession() }
        NotificationCenter.default.post(name: .cloudStateChanged, object: nil)
        completion?(error == nil)
        if pending {
            pending = false
            syncNow()
        }
    }
}

// MARK: - Theo dõi (follow / follower)

struct CloudUser {
    let username: String
    let badges: [String]
    var following: Bool
    var isVerified: Bool { return badges.contains("verified") }
    var isOwner: Bool { return badges.contains("owner") }

    init?(_ json: [String: Any]) {
        guard let name = json["username"] as? String else { return nil }
        username = name
        badges = (json["badges"] as? [String]) ?? []
        following = (json["following"] as? Bool) ?? false
    }
}

extension MochyCloud {
    private static var avatarCache: [String: UIImage] = [:]

    /// Tìm người dùng theo tiền tố tên (máy chủ ghim tài khoản chủ app lên đầu, ví dụ gõ "puc" thì gợi ý pucpucpuc).
    func searchUsers(_ query: String, completion: @escaping ([CloudUser]?, String?) -> Void) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { completion([], nil); return }
        request("/users/search?q=" + encoded, method: "GET", body: nil, auth: true) { status, json in
            guard status == 200 else { completion(nil, (json?["error"] as? String) ?? "Không tìm được."); return }
            let list = ((json?["users"] as? [[String: Any]]) ?? []).compactMap { CloudUser($0) }
            completion(list, nil)
        }
    }

    func setFollowing(_ username: String, follow: Bool, completion: @escaping (String?) -> Void) {
        let done: (Int, [String: Any]?) -> Void = { status, json in
            completion(status == 200 ? nil : ((json?["error"] as? String) ?? "Không thực hiện được."))
        }
        if follow {
            request("/follow", method: "POST", body: ["username": username], auth: true, completion: done)
        } else {
            let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
            request("/follow?username=" + encoded, method: "DELETE", body: nil, auth: true, completion: done)
        }
    }

    func loadFollows(completion: @escaping ([CloudUser], [CloudUser], String?) -> Void) {
        request("/follows", method: "GET", body: nil, auth: true) { status, json in
            guard status == 200 else { completion([], [], (json?["error"] as? String) ?? "Không tải được danh sách."); return }
            let following = ((json?["following"] as? [[String: Any]]) ?? []).compactMap { CloudUser($0) }
            let followers = ((json?["followers"] as? [[String: Any]]) ?? []).compactMap { CloudUser($0) }
            UserDefaults.standard.set(following.count, forKey: "cloud.followingCount")
            UserDefaults.standard.set(followers.count, forKey: "cloud.followersCount")
            completion(following, followers, nil)
        }
    }

    /// Ảnh đại diện của người khác (nhớ trong bộ nhớ).
    func avatar(of username: String, completion: @escaping (UIImage?) -> Void) {
        if let hit = MochyCloud.avatarCache[username] { completion(hit); return }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        request("/avatar?user=" + encoded, method: "GET", body: nil, auth: true) { status, json in
            guard status == 200, let text = json?["image"] as? String, let data = Data(base64Encoded: text), let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            MochyCloud.avatarCache[username] = image
            completion(image)
        }
    }
}
