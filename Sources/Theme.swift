import UIKit

/// Chế độ giao diện: theo hệ thống (iOS 13+; iOS 12 mặc định tối), sáng hoặc tối.
enum ThemeMode: Int {
    case system = 0
    case light = 1
    case dark = 2

    var title: String {
        switch self {
        case .system: return "Tự động"
        case .light: return "Sáng"
        case .dark: return "Tối"
        }
    }
}

extension Notification.Name {
    static let themeChanged = Notification.Name("MochyiOSThemeChanged")
}

/// Màu sắc và kiểu chữ. Màu đổi theo chế độ sáng/tối; khi đổi chế độ cả app được dựng lại (xem AppDelegate).
enum Theme {
    static let accent = UIColor(red: 250.0 / 255.0, green: 45.0 / 255.0, blue: 72.0 / 255.0, alpha: 1)

    static var mode: ThemeMode {
        get { return ThemeMode(rawValue: UserDefaults.standard.integer(forKey: "ui.theme")) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ui.theme") }
    }

    static var systemIsDark: Bool {
        if #available(iOS 13.0, *) {
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark
        }
        return true
    }

    static var isDark: Bool {
        switch mode {
        case .light: return false
        case .dark: return true
        case .system: return systemIsDark
        }
    }

    private static func pick(_ dark: UIColor, _ light: UIColor) -> UIColor {
        return isDark ? dark : light
    }

    static var background: UIColor { return pick(UIColor(white: 0.0, alpha: 1), UIColor.white) }
    static var groupedBackground: UIColor { return pick(UIColor(white: 0.0, alpha: 1), UIColor(white: 0.95, alpha: 1)) }
    static var cellBackground: UIColor { return pick(UIColor(white: 0.11, alpha: 1), UIColor.white) }
    static var card: UIColor { return pick(UIColor(white: 0.11, alpha: 1), UIColor(white: 0.95, alpha: 1)) }
    static var primaryText: UIColor { return pick(UIColor.white, UIColor.black) }
    static var secondaryText: UIColor { return pick(UIColor(white: 0.62, alpha: 1), UIColor(white: 0.45, alpha: 1)) }
    static var separator: UIColor { return pick(UIColor(white: 1.0, alpha: 0.14), UIColor(white: 0.0, alpha: 0.12)) }
    static var placeholder: UIColor { return pick(UIColor(white: 0.16, alpha: 1), UIColor(white: 0.92, alpha: 1)) }
    static var chip: UIColor { return pick(UIColor(white: 1.0, alpha: 0.14), UIColor(white: 0.0, alpha: 0.07)) }
    static var blurStyle: UIBlurEffect.Style { return isDark ? .dark : .extraLight }
    static var statusBarStyle: UIStatusBarStyle {
        if isDark { return .lightContent }
        if #available(iOS 13.0, *) { return .darkContent }
        return .default
    }

    static func heavy(_ size: CGFloat) -> UIFont { return UIFont.systemFont(ofSize: size, weight: .heavy) }
    static func bold(_ size: CGFloat) -> UIFont { return UIFont.systemFont(ofSize: size, weight: .bold) }
    static func regular(_ size: CGFloat) -> UIFont { return UIFont.systemFont(ofSize: size, weight: .regular) }

    // MARK: - Áp dụng cho các thành phần hệ thống

    static func applyWindowStyle(_ window: UIWindow?) {
        guard let window = window else { return }
        if #available(iOS 13.0, *) {
            switch mode {
            case .system: window.overrideUserInterfaceStyle = .unspecified
            case .light: window.overrideUserInterfaceStyle = .light
            case .dark: window.overrideUserInterfaceStyle = .dark
            }
        }
        window.backgroundColor = background
    }

    static func style(navigationBar bar: UINavigationBar) {
        bar.barStyle = isDark ? .black : .default
        bar.isTranslucent = true
        bar.setBackgroundImage(UIImage(), for: .default)
        bar.shadowImage = UIImage()
        bar.backgroundColor = UIColor.clear
        bar.barTintColor = nil
        bar.tintColor = accent
        bar.titleTextAttributes = [.foregroundColor: primaryText]
        bar.largeTitleTextAttributes = [.foregroundColor: primaryText, .font: heavy(34)]
        if #available(iOS 13.0, *) {
            let a = UINavigationBarAppearance()
            a.configureWithTransparentBackground()
            a.titleTextAttributes = [.foregroundColor: primaryText]
            a.largeTitleTextAttributes = [.foregroundColor: primaryText, .font: heavy(34)]
            bar.standardAppearance = a
            bar.scrollEdgeAppearance = a
            bar.compactAppearance = a
        }
    }

    static func style(searchBar bar: UISearchBar) {
        bar.barStyle = isDark ? .black : .default
        bar.keyboardAppearance = isDark ? .dark : .light
        bar.tintColor = accent
    }

    static func style(cell: UITableViewCell, grouped: Bool) {
        cell.backgroundColor = grouped ? cellBackground : background
        cell.textLabel?.textColor = primaryText
        cell.detailTextLabel?.textColor = secondaryText
        let selected = UIView()
        selected.backgroundColor = chip
        cell.selectedBackgroundView = selected
    }

    static func spinnerStyle() -> UIActivityIndicatorView.Style {
        return isDark ? .white : .gray
    }
}

/// Định dạng giây thành "m:ss".
func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
}
