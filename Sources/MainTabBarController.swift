import UIKit

/// Khung chính: thanh tab (Tìm kiếm / Đang phát / Cài đặt) + thanh phát nhỏ + hộp thoại báo lỗi phát nhạc và báo bản cập nhật.
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {
    private let mini = MiniPlayerView()
    private let searchNav = UINavigationController(rootViewController: SearchViewController())
    private let nowPlaying = NowPlayingViewController()
    private let settingsNav = UINavigationController(rootViewController: SettingsViewController())

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        view.backgroundColor = Theme.background

        searchNav.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 0)
        nowPlaying.tabBarItem = UITabBarItem(title: "Đang phát", image: Icons.music(25), tag: 1)
        settingsNav.tabBarItem = UITabBarItem(title: "Cài đặt", image: Icons.sliders(25), tag: 2)
        viewControllers = [searchNav, nowPlaying, settingsNav]
        tabBar.tintColor = Theme.accent

        mini.translatesAutoresizingMaskIntoConstraints = false
        mini.isHidden = true
        mini.onTap = { [weak self] in
            self?.selectedIndex = 1
            self?.updateMini()
        }
        view.addSubview(mini)
        NSLayoutConstraint.activate([
            mini.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mini.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mini.bottomAnchor.constraint(equalTo: tabBar.topAnchor),
            mini.heightAnchor.constraint(equalToConstant: MiniPlayerView.height)
        ])

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(stateChanged), name: .playerStateChanged, object: nil)
        center.addObserver(self, selector: #selector(playbackFailed(_:)), name: .playerFailed, object: nil)
        center.addObserver(self, selector: #selector(handleUpdateState), name: .updateStateChanged, object: nil)
    }

    @objc private func stateChanged() {
        updateMini()
    }

    private func updateMini() {
        let hasSong = PlayerEngine.shared.currentSong != nil
        let show = hasSong && (selectedIndex == 0 || selectedIndex == 2)
        mini.isHidden = !show
        let insets = UIEdgeInsets(top: 0, left: 0, bottom: show ? MiniPlayerView.height : 0, right: 0)
        searchNav.additionalSafeAreaInsets = insets
        settingsNav.additionalSafeAreaInsets = insets
        if show { mini.update() }
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        updateMini()
    }

    @objc private func playbackFailed(_ notification: Notification) {
        let message = (notification.userInfo?["message"] as? String) ?? "Lỗi không rõ"
        showAlert(title: "Không phát được", message: message)
    }

    @objc private func handleUpdateState() {
        let updater = Updater.shared
        settingsNav.tabBarItem.badgeValue = updater.available != nil ? "1" : nil
        guard let info = updater.available, !updater.isChecking, !updater.lastCheckWasManual,
              AppSettings.lastNotifiedBuild != info.build, presentedViewController == nil else { return }
        AppSettings.lastNotifiedBuild = info.build
        let alert = UIAlertController(title: "Có bản cập nhật mới",
                                      message: "Mochy iOS \(info.version) (build \(info.build)) đã sẵn sàng.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Xem", style: .default) { [weak self] _ in
            self?.selectedIndex = 2
            self?.updateMini()
        })
        alert.addAction(UIAlertAction(title: "Để sau", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(alert, animated: true, completion: nil)
    }
}
