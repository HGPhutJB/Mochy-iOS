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
    var miniArtView: UIImageView { return mini.artImageView }
    private var miniVisible = false
    private var lastIsDark = Theme.isDark
    private var tabTrailing: NSLayoutConstraint!
    private var tabWidth: NSLayoutConstraint!
    private var tabLeading: NSLayoutConstraint!
    private var miniExpanded: [NSLayoutConstraint] = []
    private var miniCompact: [NSLayoutConstraint] = []
    private var scrollObservation: NSKeyValueObservation?
    private var lastOffsetY: CGFloat = 0
    private var adaptTimer: Timer?
    private var transitionToken = 0

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
            let nav = GlassNavigationController(rootViewController: vc)
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

        tabLeading = tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28)
        tabTrailing = tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        tabWidth = tabBar.widthAnchor.constraint(equalToConstant: FloatingTabBar.height)
        let miniHeight = mini.heightAnchor.constraint(equalToConstant: MiniPlayerView.height)
        miniExpanded = [
            mini.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            mini.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            mini.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -8)
        ]
        miniCompact = [
            mini.leadingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: 8),
            mini.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            mini.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor)
        ]
        NSLayoutConstraint.activate([
            tabLeading, tabTrailing,
            tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            tabBar.heightAnchor.constraint(equalToConstant: FloatingTabBar.height),
            miniHeight
        ] + miniExpanded)
        tabBar.backdrop = contentView
        tabBar.onTapWhileCollapsed = { [weak self] in self?.setCompact(false) }
        tabBar.select(selectedIndex, animated: false)
        applyInsets(animated: false)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(playerChanged), name: .playerStateChanged, object: nil)
        center.addObserver(self, selector: #selector(playbackFailed(_:)), name: .playerFailed, object: nil)
        center.addObserver(self, selector: #selector(downloadFailed(_:)), name: .downloadFailed, object: nil)
        center.addObserver(self, selector: #selector(handleUpdateState), name: .updateStateChanged, object: nil)
        playerChanged()
        handleUpdateState()
        controllers.forEach { $0.delegate = self }
        attachScrollObserver()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tabBar.adaptToBackdrop()
        adaptTimer?.invalidate()
        adaptTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self = self, self.presentedViewController == nil else { return }
            self.tabBar.adaptToBackdrop()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        adaptTimer?.invalidate()
        adaptTimer = nil
    }

    // MARK: - Thu gọn thanh tab khi cuộn

    private var compact = false
    private var travel: CGFloat = 0
    private var lastToggle = Date.distantPast

    /// Đổi trạng thái do cuộn: có thời gian nghỉ để hiệu ứng lò xo chạy xong, tránh nhấp nháy.
    private func requestCompact(_ value: Bool) {
        guard value != compact, Date().timeIntervalSince(lastToggle) > 0.7 else { return }
        lastToggle = Date()
        setCompact(value)
    }

    private func setCompact(_ value: Bool) {
        guard value != compact else { return }
        compact = value
        tabBar.setCollapsed(value, animated: true)
        if value {
            NSLayoutConstraint.deactivate(miniExpanded)
            tabTrailing.isActive = false
            tabWidth.isActive = true
            tabLeading.constant = 16
            NSLayoutConstraint.activate(miniCompact)
        } else {
            NSLayoutConstraint.deactivate(miniCompact)
            tabWidth.isActive = false
            tabTrailing.isActive = true
            tabLeading.constant = 28
            NSLayoutConstraint.activate(miniExpanded)
        }
        UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0.2,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    private func primaryScroll(in v: UIView) -> UIScrollView? {
        if let s = v as? UIScrollView { return s }
        for sub in v.subviews { if let s = primaryScroll(in: sub) { return s } }
        return nil
    }

    fileprivate func attachScrollObserver() {
        scrollObservation = nil
        guard let top = controllers[selectedIndex].topViewController, top.isViewLoaded,
              let scroll = primaryScroll(in: top.view) else { return }
        lastOffsetY = scroll.contentOffset.y
        travel = 0
        scrollObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] s, _ in
            guard let self = self, s.isTracking || s.isDecelerating else { return }
            let y = s.contentOffset.y
            let top = -s.adjustedContentInset.top
            let maxY = max(top, s.contentSize.height - s.bounds.height + s.adjustedContentInset.bottom)
            // Đàn hồi ở hai đầu danh sách không được tính (làm thanh thụt ra thụt vào).
            if y < top - 1 || y > maxY + 1 { self.lastOffsetY = y; return }
            let dy = y - self.lastOffsetY
            self.lastOffsetY = y
            if dy == 0 { return }
            if (dy > 0) != (self.travel > 0) { self.travel = 0 }
            self.travel += dy
            if y <= top + 12 { self.requestCompact(false) }
            else if self.travel > 56 && y > top + 80 { self.requestCompact(true); self.travel = 0 }
            else if self.travel < -56 { self.requestCompact(false); self.travel = 0 }
        }
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
        setCompact(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.attachScrollObserver()
            self?.tabBar.adaptToBackdrop()
        }

        transitionToken += 1
        let token = transitionToken
        if new.parent == nil { addChild(new) }
        new.view.layer.removeAllAnimations()
        new.view.frame = contentView.bounds
        new.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if animated {
            new.view.alpha = 0
            new.view.transform = .identity
            if new.view.superview == nil { contentView.insertSubview(new.view, belowSubview: old.view) } else { contentView.bringSubviewToFront(new.view) }
            UIView.animate(withDuration: 0.22, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
                new.view.alpha = 1
                old.view.alpha = 0
            }, completion: { [weak self] _ in
                // Chỉ lần chuyển tab MỚI NHẤT được dọn dẹp; các lần cũ bị ghi đè (bấm nhanh) thì bỏ qua.
                guard let self = self, token == self.transitionToken else { return }
                self.settleTabs()
            })
        } else {
            new.view.alpha = 1
            new.view.transform = .identity
            if new.view.superview == nil { contentView.addSubview(new.view) }
            settleTabs()
        }
    }

    /// Đưa các tab về trạng thái chuẩn: chỉ tab đang chọn hiện (rõ nét, đúng chỗ), các tab khác gỡ khỏi màn hình.
    private func settleTabs() {
        for (i, nav) in controllers.enumerated() {
            if i == selectedIndex {
                nav.view.layer.removeAllAnimations()
                nav.view.alpha = 1
                nav.view.transform = .identity
                nav.view.frame = contentView.bounds
                if nav.parent == nil { addChild(nav) }
                if nav.view.superview == nil { contentView.addSubview(nav.view) }
                nav.didMove(toParent: self)
            } else {
                nav.view.alpha = 1
                nav.view.transform = .identity
                if nav.parent != nil {
                    nav.willMove(toParent: nil)
                    nav.view.removeFromSuperview()
                    nav.removeFromParent()
                }
            }
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
        let message = (notification.userInfo?["message"] as? String) ?? L("Lỗi không rõ")
        showAlert(title: L("Không phát được"), message: message)
    }

    @objc private func downloadFailed(_ notification: Notification) {
        let message = (notification.userInfo?["message"] as? String) ?? L("Lỗi không rõ")
        showAlert(title: L("Tải xuống thất bại"), message: message)
    }

    @objc private func handleUpdateState() {
        let updater = Updater.shared
        tabBar.setBadge(visible: updater.available != nil)
        guard let info = updater.available, !updater.isChecking, !updater.lastCheckWasManual,
              AppSettings.lastNotifiedBuild != info.build, presentedViewController == nil else { return }
        AppSettings.lastNotifiedBuild = info.build
        let alert = UIAlertController(title: L("Có bản cập nhật mới"),
                                      message: Lf("Mochy iOS %@ (build %@) đã sẵn sàng.", info.version, info.build),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Xem", style: .default) { [weak self] _ in
            self?.select(3, animated: true)
        })
        alert.addAction(UIAlertAction(title: L("Để sau"), style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(alert, animated: true, completion: nil)
    }
}

extension RootViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        setCompact(false)
        attachScrollObserver()
        tabBar.adaptToBackdrop()
    }
}
