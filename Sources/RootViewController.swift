import UIKit

/// Khung chính: 4 tab (Trang chủ / Tìm kiếm / Thư viện / Cài đặt), thanh tab nổi, thanh phát nhỏ,
/// hộp thoại báo lỗi phát nhạc, lỗi tải xuống và bản cập nhật.
final class RootViewController: UIViewController {
    static weak var shared: RootViewController?

    private let contentView = UIView()
    private let tabBar = FloatingTabBar(icons: [Icons.home(25), Icons.search(25), Icons.library(25), Icons.sliders(25)])
    private let mini = MiniPlayerView()
    private var controllers: [UINavigationController] = []
    private(set) var selectedIndex = 0
    private var miniVisible = false
    private var lastIsDark = Theme.isDark

    init(selectedIndex: Int = 0) {
        super.init(nibName: nil, bundle: nil)
        self.selectedIndex = selectedIndex
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.statusBarStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        RootViewController.shared = self
        view.backgroundColor = Theme.background

        let roots: [UIViewController] = [HomeViewController(), SearchViewController(),
                                         LibraryViewController(), SettingsViewController()]
        controllers = roots.map { vc in
            let nav = UINavigationController(rootViewController: vc)
            Theme.style(navigationBar: nav.navigationBar)
            nav.navigationBar.prefersLargeTitles = true
            return nav
        }

        contentView.frame = view.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(contentView)
        embed(controllers[selectedIndex])

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.onSelect = { [weak self] index in self?.select(index, animated: true) }
        view.addSubview(tabBar)

        mini.translatesAutoresizingMaskIntoConstraints = false
        mini.alpha = 0
        mini.isHidden = true
        mini.onTap = { [weak self] in self?.presentNowPlaying() }
        view.addSubview(mini)

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            tabBar.heightAnchor.constraint(equalToConstant: FloatingTabBar.height),
            mini.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            mini.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            mini.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -8),
            mini.heightAnchor.constraint(equalToConstant: MiniPlayerView.height)
        ])
        tabBar.select(selectedIndex, animated: false)
        applyInsets(animated: false)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(playerChanged), name: .playerStateChanged, object: nil)
        center.addObserver(self, selector: #selector(playbackFailed(_:)), name: .playerFailed, object: nil)
        center.addObserver(self, selector: #selector(downloadFailed(_:)), name: .downloadFailed, object: nil)
        center.addObserver(self, selector: #selector(handleUpdateState), name: .updateStateChanged, object: nil)
        playerChanged()
        handleUpdateState()
    }

    // MARK: - Chuyển tab

    private func embed(_ controller: UIViewController) {
        addChild(controller)
        controller.view.frame = contentView.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    func select(_ index: Int, animated: Bool) {
        guard index >= 0 && index < controllers.count else { return }
        if index == selectedIndex {
            // Chạm lại tab hiện tại: quay về màn hình đầu của tab.
            controllers[index].popToRootViewController(animated: true)
            return
        }
        let old = controllers[selectedIndex]
        let new = controllers[index]
        selectedIndex = index
        tabBar.select(index, animated: animated)
        applyInsets(animated: false)

        addChild(new)
        new.view.frame = contentView.bounds
        new.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if animated {
            new.view.alpha = 0
            new.view.transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.985, y: 0.985)
            contentView.insertSubview(new.view, belowSubview: old.view)
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                           options: [.allowUserInteraction], animations: {
                new.view.alpha = 1
                new.view.transform = CGAffineTransform.identity
                old.view.alpha = 0
                old.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            }, completion: { _ in
                old.view.alpha = 1
                old.view.transform = CGAffineTransform.identity
                old.willMove(toParent: nil)
                old.view.removeFromSuperview()
                old.removeFromParent()
                new.didMove(toParent: self)
            })
        } else {
            contentView.addSubview(new.view)
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
            new.didMove(toParent: self)
        }
    }

    // MARK: - Thanh phát nhỏ

    /// Chừa chỗ ở đáy cho thanh tab nổi (và thanh phát nhỏ) để danh sách không bị che.
    private func applyInsets(animated: Bool) {
        var bottom = FloatingTabBar.height + 16
        if miniVisible { bottom += MiniPlayerView.height + 8 }
        let apply = {
            for nav in self.controllers {
                nav.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
            }
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                           options: [.allowUserInteraction], animations: apply, completion: nil)
        } else {
            apply()
        }
    }

    @objc private func playerChanged() {
        let hasSong = PlayerEngine.shared.currentSong != nil
        if hasSong { mini.update() }
        if hasSong == miniVisible { return }
        miniVisible = hasSong
        if hasSong {
            mini.isHidden = false
            mini.transform = CGAffineTransform(translationX: 0, y: 30).scaledBy(x: 0.96, y: 0.96)
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.5,
                           options: [], animations: {
                self.mini.alpha = 1
                self.mini.transform = CGAffineTransform.identity
            }, completion: nil)
        } else {
            UIView.animate(withDuration: 0.25, animations: {
                self.mini.alpha = 0
            }, completion: { _ in self.mini.isHidden = true })
        }
        applyInsets(animated: true)
    }

    func presentNowPlaying() {
        guard PlayerEngine.shared.currentSong != nil, presentedViewController == nil else { return }
        let vc = NowPlayingViewController()
        vc.modalPresentationStyle = .overFullScreen
        vc.transitioningDelegate = vc.transition
        present(vc, animated: true, completion: nil)
    }

    // MARK: - Theo dõi giao diện hệ thống

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if Theme.mode == .system && Theme.isDark != lastIsDark {
            lastIsDark = Theme.isDark
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    // MARK: - Hộp thoại

    @objc private func playbackFailed(_ notification: Notification) {
        let message = (notification.userInfo?["message"] as? String) ?? "Lỗi không rõ"
        showAlert(title: "Không phát được", message: message)
    }

    @objc private func downloadFailed(_ notification: Notification) {
        let message = (notification.userInfo?["message"] as? String) ?? "Lỗi không rõ"
        showAlert(title: "Tải xuống thất bại", message: message)
    }

    @objc private func handleUpdateState() {
        let updater = Updater.shared
        tabBar.setBadge(visible: updater.available != nil)
        guard let info = updater.available, !updater.isChecking, !updater.lastCheckWasManual,
              AppSettings.lastNotifiedBuild != info.build, presentedViewController == nil else { return }
        AppSettings.lastNotifiedBuild = info.build
        let alert = UIAlertController(title: "Có bản cập nhật mới",
                                      message: "Mochy iOS \(info.version) (build \(info.build)) đã sẵn sàng.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Xem", style: .default) { [weak self] _ in
            self?.select(3, animated: true)
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
