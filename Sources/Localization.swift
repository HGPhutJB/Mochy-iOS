import Foundation

/// Ngôn ngữ giao diện: tự động theo hệ thống (tiếng Việt nếu hệ thống là tiếng Việt, còn lại là English), hoặc chọn tay.
enum AppLanguage: Int {
    case auto = 0
    case vietnamese = 1
    case english = 2

    var title: String {
        switch self {
        case .auto: return L("Tự động (theo hệ thống)")
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        }
    }
}

enum Lang {
    static var setting: AppLanguage {
        get { return AppLanguage(rawValue: UserDefaults.standard.integer(forKey: "ui.language")) ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ui.language") }
    }

    /// Quyết định một lần khi mở app (đổi cài đặt thì áp dụng đầy đủ sau khi mở lại).
    static let isVietnamese: Bool = {
        switch AppLanguage(rawValue: UserDefaults.standard.integer(forKey: "ui.language")) ?? .auto {
        case .vietnamese: return true
        case .english: return false
        case .auto: return (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("vi")
        }
    }()
}

/// Chuỗi giao diện: gốc là tiếng Việt, ngôn ngữ khác tra trong bảng dịch (không có thì giữ nguyên).
func L(_ vi: String) -> String {
    return Lang.isVietnamese ? vi : (EnglishStrings.table[vi] ?? vi)
}

/// Như `L` nhưng có chỗ chèn giá trị: mỗi "%@" được thay lần lượt bằng một đối số.
func Lf(_ vi: String, _ args: Any...) -> String {
    let parts = L(vi).components(separatedBy: "%@")
    var out = parts[0]
    for (i, part) in parts.dropFirst().enumerated() {
        out += (i < args.count ? String(describing: args[i]) : "%@") + part
    }
    return out
}
