import UIKit

/// Thông tin bản dựng đang chạy (đọc từ Info.plist do build.sh ghi vào).
enum AppInfo {
    private static func string(_ key: String) -> String? {
        return Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    static var version: String { return string("CFBundleShortVersionString") ?? "?" }
    static var build: Int { return Int(string("CFBundleVersion") ?? "") ?? 0 }
    static var commit: String { return string("MochyBuildCommit") ?? "" }
    /// Kênh mà bản dựng này được phát hành ("stable" hoặc "dev").
    static var builtChannel: String { return string("MochyChannel") ?? "stable" }
    /// Cài bằng .deb (jailbreak) thì app nằm trong /Applications.
    static var isJailbreakInstall: Bool { return Bundle.main.bundlePath.hasPrefix("/Applications/") }
    static var osVersion: String { return UIDevice.current.systemVersion }
}

enum UpdateChannel: String {
    case stable
    case dev

    var title: String {
        return self == .stable ? L("Ổn định") : L("Nhà phát triển")
    }
}

enum AudioQuality: Int {
    case best = 0
    case saver = 1
}

/// Cài đặt người dùng, lưu trong UserDefaults.
enum PlayerBlur: Int {
    case auto = 0, light, dark
    var title: String {
        switch self {
        case .auto: return L("Tự động theo ảnh bìa")
        case .light: return L("Sáng")
        case .dark: return L("Tối")
        }
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    static var autoCheck: Bool {
        get {
            if defaults.object(forKey: "update.auto") == nil { return true }
            return defaults.bool(forKey: "update.auto")
        }
        set { defaults.set(newValue, forKey: "update.auto") }
    }

    static var channel: UpdateChannel {
        get {
            if let raw = defaults.string(forKey: "update.channel"), let value = UpdateChannel(rawValue: raw) {
                return value
            }
            return AppInfo.builtChannel == "dev" ? .dev : .stable
        }
        set { defaults.set(newValue.rawValue, forKey: "update.channel") }
    }

    static var audioQuality: AudioQuality {
        get { return AudioQuality(rawValue: defaults.integer(forKey: "audio.quality")) ?? .best }
        set { defaults.set(newValue.rawValue, forKey: "audio.quality") }
    }

    /// Dùng video MV làm nền màn hình đang phát (nếu bài có).
    /// Màu nhấn của app đổi theo ảnh bìa bài đang phát.
    static var dynamicAccent: Bool {
        get {
            if defaults.object(forKey: "ui.dynamicAccent") == nil { return true }
            return defaults.bool(forKey: "ui.dynamicAccent")
        }
        set { defaults.set(newValue, forKey: "ui.dynamicAccent") }
    }

    static var videoBackdrop: Bool {
        get {
            if defaults.object(forKey: "player.video") == nil { return true }
            return defaults.bool(forKey: "player.video")
        }
        set { defaults.set(newValue, forKey: "player.video") }
    }

    /// Kiểu làm mờ phía dưới màn hình đang phát khi chưa bật lời.
    static var playerBlur: PlayerBlur {
        get { return PlayerBlur(rawValue: defaults.integer(forKey: "player.blur")) ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "player.blur") }
    }

    /// Độ đậm của lời bài hát: 0 (Light) ... 6 (Black).
    static var lyricWeight: Int {
        get {
            if defaults.object(forKey: "lyrics.weight") == nil { return RoundedFont.defaultLyricIndex }
            return min(max(defaults.integer(forKey: "lyrics.weight"), 0), 6)
        }
        set { defaults.set(min(max(newValue, 0), 6), forKey: "lyrics.weight") }
    }

    /// Ẩn các dòng lời đã hát: 0 = tự động (chỉ khi xoay ngang), 1 = luôn ẩn, 2 = luôn hiện.
    static var hidePastLyrics: Int {
        get { return min(max(defaults.integer(forKey: "lyrics.hidePast"), 0), 2) }
        set { defaults.set(min(max(newValue, 0), 2), forKey: "lyrics.hidePast") }
    }

    static var recentSearches: [String] {
        get { return defaults.stringArray(forKey: "search.recent") ?? [] }
        set { defaults.set(Array(newValue.prefix(12)), forKey: "search.recent") }
    }

    /// Build đã được báo bằng hộp thoại, để không làm phiền lặp lại.
    static var lastNotifiedBuild: Int {
        get { return defaults.integer(forKey: "update.notified") }
        set { defaults.set(newValue, forKey: "update.notified") }
    }
}

/// So sánh phiên bản dạng "12.5.8": true nếu `current` >= `required`.
func versionAtLeast(_ current: String, _ required: String) -> Bool {
    let a = current.split(separator: ".").map { Int($0) ?? 0 }
    let b = required.split(separator: ".").map { Int($0) ?? 0 }
    let count = max(a.count, b.count)
    for i in 0..<count {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return true
}
