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
        return self == .stable ? "Ổn định" : "Nhà phát triển"
    }
}

enum AudioQuality: Int {
    case best = 0
    case saver = 1
}

/// Cài đặt người dùng, lưu trong UserDefaults.
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
    static var videoBackdrop: Bool {
        get {
            if defaults.object(forKey: "player.video") == nil { return true }
            return defaults.bool(forKey: "player.video")
        }
        set { defaults.set(newValue, forKey: "player.video") }
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
