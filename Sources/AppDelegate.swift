// Mochy iOS — trình nghe nhạc cho iOS 12 trở lên (jailbreak rootful hoặc sideload).
//
// Nguồn gốc: đây là bản viết lại bằng Swift/UIKit, dựa trên ý tưởng, luồng gọi YouTube Music và
// bộ thông số client của Mochy Music (https://github.com/realidkroo/mochy-music, GPL-3.0) do realidkroo làm.
// Mochy Music lại phát triển từ ViviMusic và Metrolist. Dự án này giữ nguyên giấy phép GPL-3.0
// và tri ân các tác giả đó; xem thêm NOTICE ở thư mục gốc.

import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        _ = PlayerEngine.shared
        ScrobbleTracker.shared.start()
        let window = UIWindow(frame: UIScreen.main.bounds)
        Theme.applyWindowStyle(window)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .themeChanged, object: nil)
        return true
    }

    /// Đổi sáng/tối: dựng lại toàn bộ giao diện với hiệu ứng mờ dần, giữ nguyên tab đang mở.
    @objc private func themeChanged() {
        guard let window = window else { return }
        let index = (window.rootViewController as? RootViewController)?.selectedIndex ?? 0
        Theme.applyWindowStyle(window)
        UIView.transition(with: window, duration: 0.45, options: [.transitionCrossDissolve, .allowAnimatedContent], animations: {
            window.rootViewController = RootViewController(selectedIndex: index)
        }, completion: nil)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        PlayLog.shared.flush()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AccountSync.shared.autoSyncIfNeeded()
        // Tự kiểm tra cập nhật (tối đa mỗi 6 giờ, và chỉ khi người dùng không tắt trong Cài đặt).
        Updater.shared.autoCheckIfNeeded()
        BackupManager.autoBackupIfNeeded()
    }
}
