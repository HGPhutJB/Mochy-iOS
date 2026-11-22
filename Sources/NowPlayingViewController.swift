import UIKit
import MediaPlayer
import AVKit

/// Chuyển cảnh mở/đóng màn hình đang phát: trượt lên bằng lò xo, nền phía sau thu nhỏ nhẹ.
final class NowPlayingTransition: NSObject, UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return NowPlayingAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return NowPlayingAnimator(presenting: false)
    }
}

final class NowPlayingAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool

    init(presenting: Bool) {
        self.presenting = presenting
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return presenting ? 0.65 : 0.55
    }

    /// Khung ảnh bìa của thanh phát nhỏ, tính theo toạ độ của container.
    private func miniArtFrame(in container: UIView) -> CGRect {
        if let art = RootViewController.shared?.miniArtView, let parent = art.superview {
            return parent.convert(art.frame, to: container)
        }
        return CGRect(x: 22, y: container.bounds.height - 110, width: 42, height: 42)
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView
        let miniArt = RootViewController.shared?.miniArtView
        let duration = transitionDuration(using: transitionContext)

        if presenting {
            guard let toVC = transitionContext.viewController(forKey: .to) as? NowPlayingViewController,
                  let toView = transitionContext.view(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            toView.frame = container.bounds
            container.addSubview(toView)
            toView.layoutIfNeeded()

            let realArt = toVC.artImageView
            let target = realArt.superview?.convert(realArt.frame, to: container) ?? container.bounds
            let start = miniArtFrame(in: container)

            // Ảnh bìa "bay" từ thanh phát nhỏ lên vị trí bìa lớn.
            let flying = UIImageView(image: realArt.image ?? miniArt?.image)
            flying.contentMode = .scaleAspectFill
            flying.clipsToBounds = true
            flying.backgroundColor = UIColor(white: 0.1, alpha: 1)
            flying.frame = start
            flying.layer.cornerRadius = 10
            container.addSubview(flying)
            realArt.alpha = 0
            miniArt?.alpha = 0

            // Không biến đổi màn hình phía sau (tránh vẽ lại cả ứng dụng mỗi khung hình → giật, mất thanh điều hướng).
            toView.layer.shouldRasterize = true
            toView.layer.rasterizationScale = UIScreen.main.scale
            toView.transform = CGAffineTransform(translationX: 0, y: container.bounds.height)
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0,
                           options: [.curveEaseOut], animations: {
                toView.transform = CGAffineTransform.identity
                flying.frame = target
                flying.layer.cornerRadius = 0
            }, completion: { _ in
                toView.layer.shouldRasterize = false
                realArt.alpha = 1
                flying.removeFromSuperview()
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            })
        } else {
            guard let fromVC = transitionContext.viewController(forKey: .from) as? NowPlayingViewController,
                  let fromView = transitionContext.view(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }
            let realArt = fromVC.artImageView
            let start = realArt.superview?.convert(realArt.frame, to: container) ?? container.bounds
            let end = miniArtFrame(in: container)

            // Ảnh bìa thu nhỏ bay về thanh phát nhỏ.
            let flying = UIImageView(image: realArt.image ?? miniArt?.image)
            flying.contentMode = .scaleAspectFill
            flying.clipsToBounds = true
            flying.backgroundColor = UIColor(white: 0.1, alpha: 1)
            flying.frame = start
            flying.layer.cornerRadius = 0
            container.addSubview(flying)
            realArt.alpha = 0
            miniArt?.alpha = 0
            fromView.layer.shouldRasterize = true
            fromView.layer.rasterizationScale = UIScreen.main.scale

            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0,
                           options: [.curveEaseInOut], animations: {
                fromView.transform = CGAffineTransform(translationX: 0, y: container.bounds.height)
                flying.frame = end
                flying.layer.cornerRadius = 10
            }, completion: { _ in
                fromView.layer.shouldRasterize = false
                flying.removeFromSuperview()
                miniArt?.alpha = 1
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            })
        }
    }
}

/// Màn hình đang phát kiểu Apple Music: bìa (hoặc video MV) tràn màn hình, dải mờ phía dưới các nút;
/// bật lời thì chuyển sang nền màu chuyển động, sau 5 giây không chạm thì lời phủ toàn màn hình.
final class NowPlayingViewController: UIViewController {
    let transition = NowPlayingTransition()

    private enum Mode { case cover, lyrics, immersive }
    private var mode: Mode = .cover
    private static let green = UIColor(red: 0.25, green: 0.92, blue: 0.2, alpha: 1)

    private let mediaView = UIView()
    private let artView = UIImageView()
    private let video = VideoBackdrop()
    private let fluidView = FluidBackgroundView()
    private let bandBlur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let bandMask = CAGradientLayer()
    private let bandShade = GradientView()
    private let topShade = GradientView()
    private let dragZone = UIView()
    private let lyricsView = LyricsView()

    private let chevron = GlassView(tint: nil)
    private let contextPill = GlassView(tint: nil)
    private let moreGlass = GlassView(tint: UIColor(red: 0.95, green: 0.22, blue: 0.32, alpha: 0.42))
    private let infoA = InfoRow(withThumb: false)
    private let infoB = InfoRow(withThumb: true)

    private let progress = ProgressBar()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let shuffleButton = UIButton(type: .custom)
    private let shuffleDot = UIView()
    private let prevButton = UIButton(type: .custom)
    private let playButton = UIButton(type: .custom)
    private let nextButton = UIButton(type: .custom)
    private let repeatButton = UIButton(type: .custom)
    private let lyricsButton = UIButton(type: .custom)
    private let deviceButton = UIButton(type: .custom)
    private let deviceUnderline = UIView()
    private let routePicker = AVRoutePickerView()
    private let queueButton = UIButton(type: .custom)

    private var chromeTop: [UIView] = []
    private var chromeBottom: [UIView] = []
    private var pillWidth: NSLayoutConstraint?
    private var lyricsTop: NSLayoutConstraint?
    private var lyricsBottom: NSLayoutConstraint?
    private var artPan: UIPanGestureRecognizer?

    private var shownVideoId: String?
    private var shownArtwork: UIImage?
    private var lyricsVideoId: String?
    private var idleTimer: Timer?
    private var suppressSeekUntil = Date.distantPast
    private var videoReady = false

    /// Ảnh bìa lớn (dùng cho hiệu ứng bay giữa thanh phát nhỏ và màn hình đang phát).
    var artImageView: UIImageView { return artView }

    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func loadView() {
        let root = PlayerRootView()
        root.onTouch = { [weak self] in self?.userTouched() }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        buildLayout()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(stateChanged), name: .playerStateChanged, object: nil)
        center.addObserver(self, selector: #selector(timeChanged), name: .playerTimeChanged, object: nil)
        center.addObserver(self, selector: #selector(libraryChanged), name: .libraryChanged, object: nil)
        center.addObserver(self, selector: #selector(libraryChanged), name: .downloadChanged, object: nil)
        stateChanged()
        apply(mode: .cover, animated: false)
    }

    deinit {
        idleTimer?.invalidate()
        video.stop()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lyricsView.setRunning(false)
        idleTimer?.invalidate()
        video.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width, h = view.bounds.height
        mediaView.frame = view.bounds
        artView.frame = mediaView.bounds
        video.layer.frame = mediaView.bounds
        let bandTop = h * 0.46
        bandBlur.frame = CGRect(x: 0, y: bandTop, width: w, height: h - bandTop)
        bandMask.frame = bandBlur.bounds
        bandShade.frame = bandBlur.frame
        topShade.frame = CGRect(x: 0, y: 0, width: w, height: 170)
        updateLyricsFrame()
    }

    // MARK: - Dựng giao diện

    private func icon(_ button: UIButton, _ image: UIImage, _ action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func buildLayout() {
        // Lớp nền: bìa/video, nền màu chuyển động, dải mờ, bóng đổ.
        mediaView.frame = view.bounds
        view.addSubview(mediaView)
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        artView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        mediaView.addSubview(artView)
        video.layer.opacity = 0
        mediaView.layer.addSublayer(video.layer)
        video.onReadyChanged = { [weak self] ready in
            guard let self = self else { return }
            self.videoReady = ready
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.6)
            self.video.layer.opacity = ready ? 1 : 0
            CATransaction.commit()
        }

        fluidView.frame = view.bounds
        fluidView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fluidView.alpha = 0
        view.addSubview(fluidView)

        bandBlur.isUserInteractionEnabled = false
        bandMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        bandMask.locations = [0, 0.42, 1]
        bandBlur.layer.mask = bandMask
        view.addSubview(bandBlur)
        bandShade.isUserInteractionEnabled = false
        bandShade.gradientLayer.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.5).cgColor]
        bandShade.gradientLayer.locations = [0, 0.7]
        view.addSubview(bandShade)
        topShade.isUserInteractionEnabled = false
        topShade.gradientLayer.colors = [UIColor(white: 0, alpha: 0.45).cgColor, UIColor.clear.cgColor]
        view.addSubview(topShade)

        lyricsView.translatesAutoresizingMaskIntoConstraints = false
        lyricsView.alpha = 0
        lyricsView.onSeek = { [weak self] time in
            guard let self = self, Date() > self.suppressSeekUntil else { return }
            PlayerEngine.shared.seek(to: time)
        }
        lyricsView.onInteraction = { [weak self] in self?.scheduleIdle() }
        view.addSubview(lyricsView)

        dragZone.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dragZone)

        // Thông tin bài.
        infoA.translatesAutoresizingMaskIntoConstraints = false
        infoB.translatesAutoresizingMaskIntoConstraints = false
        infoB.alpha = 0
        view.addSubview(infoA)
        view.addSubview(infoB)
        infoA.checkButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        infoB.checkButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)

        // Thanh trên cùng.
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.iconView.image = Icons.chevronDown(26)
        chevron.onTap = { [weak self] in self?.dismiss(animated: true, completion: nil) }
        contextPill.translatesAutoresizingMaskIntoConstraints = false
        contextPill.titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .heavy)
        contextPill.onTap = nil
        moreGlass.translatesAutoresizingMaskIntoConstraints = false
        moreGlass.iconView.image = Icons.more(26)
        moreGlass.onTap = { [weak self] in self?.moreTapped() }
        [chevron, contextPill, moreGlass].forEach { view.addSubview($0) }
        chromeTop = [chevron, contextPill, moreGlass]

        // Tiến trình.
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.onScrub = { [weak self] value, ended in self?.scrubbed(value, ended: ended) }
        for label in [elapsedLabel, remainingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFont.systemFont(ofSize: 13, weight: .heavy)
            label.textColor = UIColor(white: 1, alpha: 0.6)
        }
        elapsedLabel.text = "0:00"
        remainingLabel.text = "-:--"
        remainingLabel.textAlignment = .right

        // Điều khiển phát.
        icon(shuffleButton, Icons.shuffle(28), #selector(shuffleTapped))
        icon(prevButton, Icons.previous(50), #selector(prevTapped))
        icon(playButton, Icons.pause(64), #selector(playTapped))
        icon(nextButton, Icons.next(50), #selector(nextTapped))
        icon(repeatButton, Icons.repeatAll(28), #selector(repeatTapped))
        shuffleDot.translatesAutoresizingMaskIntoConstraints = false
        shuffleDot.backgroundColor = NowPlayingViewController.green
        shuffleDot.layer.cornerRadius = 2.5
        shuffleDot.alpha = 0

        icon(lyricsButton, Icons.lyrics(28), #selector(lyricsTapped))
        icon(deviceButton, Icons.device(28), #selector(noop))
        icon(queueButton, Icons.queue(28), #selector(queueTapped))
        deviceButton.tintColor = NowPlayingViewController.green
        deviceUnderline.translatesAutoresizingMaskIntoConstraints = false
        deviceUnderline.backgroundColor = NowPlayingViewController.green
        deviceUnderline.layer.cornerRadius = 1.5
        routePicker.translatesAutoresizingMaskIntoConstraints = false
        routePicker.tintColor = UIColor.clear
        routePicker.activeTintColor = UIColor.clear
        routePicker.backgroundColor = UIColor.clear

        chromeBottom = [progress, elapsedLabel, remainingLabel, shuffleButton, shuffleDot, prevButton, playButton,
                        nextButton, repeatButton, lyricsButton, deviceButton, routePicker, deviceUnderline, queueButton]
        chromeBottom.forEach { view.addSubview($0) }

        let guide = view.safeAreaLayoutGuide
        let side: CGFloat = 30
        func ratio(_ v: UIView, _ m: CGFloat) -> NSLayoutConstraint {
            return NSLayoutConstraint(item: v, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: m, constant: 0)
        }
        let pw = contextPill.widthAnchor.constraint(equalToConstant: 140)
        pillWidth = pw
        let lt = lyricsView.topAnchor.constraint(equalTo: view.topAnchor, constant: 200)
        let lb = lyricsView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -240)
        lyricsTop = lt
        lyricsBottom = lb

        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 17),
            chevron.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            chevron.widthAnchor.constraint(equalToConstant: 52),
            chevron.heightAnchor.constraint(equalToConstant: 52),
            moreGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -17),
            moreGlass.topAnchor.constraint(equalTo: chevron.topAnchor),
            moreGlass.widthAnchor.constraint(equalToConstant: 52),
            moreGlass.heightAnchor.constraint(equalToConstant: 52),
            contextPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contextPill.centerYAnchor.constraint(equalTo: chevron.centerYAnchor),
            contextPill.heightAnchor.constraint(equalToConstant: 40),
            pw,

            infoB.topAnchor.constraint(equalTo: chevron.bottomAnchor, constant: 13),
            infoB.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            infoB.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            infoB.heightAnchor.constraint(equalToConstant: 88),

            lyricsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lyricsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lt, lb,

            dragZone.topAnchor.constraint(equalTo: view.topAnchor),
            dragZone.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dragZone.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dragZone.heightAnchor.constraint(equalToConstant: 130),

            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            progress.heightAnchor.constraint(equalToConstant: 36),
            progress.centerYAnchor.constraint(equalTo: guide.bottomAnchor, constant: -210),
            elapsedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            elapsedLabel.centerYAnchor.constraint(equalTo: guide.bottomAnchor, constant: -190),
            remainingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            remainingLabel.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor),

            infoA.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            infoA.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            infoA.heightAnchor.constraint(equalToConstant: 60),
            infoA.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -10),

            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: guide.bottomAnchor, constant: -120),
            playButton.widthAnchor.constraint(equalToConstant: 80),
            playButton.heightAnchor.constraint(equalToConstant: 80),
            ratio(prevButton, 0.574), prevButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 70), prevButton.heightAnchor.constraint(equalToConstant: 70),
            ratio(nextButton, 1.426), nextButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 70), nextButton.heightAnchor.constraint(equalToConstant: 70),
            ratio(shuffleButton, 0.226), shuffleButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            shuffleButton.widthAnchor.constraint(equalToConstant: 56), shuffleButton.heightAnchor.constraint(equalToConstant: 56),
            ratio(repeatButton, 1.774), repeatButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            repeatButton.widthAnchor.constraint(equalToConstant: 56), repeatButton.heightAnchor.constraint(equalToConstant: 56),
            shuffleDot.centerXAnchor.constraint(equalTo: shuffleButton.centerXAnchor),
            shuffleDot.topAnchor.constraint(equalTo: shuffleButton.centerYAnchor, constant: 16),
            shuffleDot.widthAnchor.constraint(equalToConstant: 5),
            shuffleDot.heightAnchor.constraint(equalToConstant: 5),

            ratio(lyricsButton, 0.4), lyricsButton.centerYAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24),
            lyricsButton.widthAnchor.constraint(equalToConstant: 64), lyricsButton.heightAnchor.constraint(equalToConstant: 48),
            deviceButton.centerXAnchor.constraint(equalTo: view.centerXAnchor), deviceButton.centerYAnchor.constraint(equalTo: lyricsButton.centerYAnchor),
            deviceButton.widthAnchor.constraint(equalToConstant: 64), deviceButton.heightAnchor.constraint(equalToConstant: 48),
            ratio(queueButton, 1.6), queueButton.centerYAnchor.constraint(equalTo: lyricsButton.centerYAnchor),
            queueButton.widthAnchor.constraint(equalToConstant: 64), queueButton.heightAnchor.constraint(equalToConstant: 48),
            deviceUnderline.centerXAnchor.constraint(equalTo: deviceButton.centerXAnchor),
            deviceUnderline.topAnchor.constraint(equalTo: deviceButton.centerYAnchor, constant: 15),
            deviceUnderline.widthAnchor.constraint(equalToConstant: 26),
            deviceUnderline.heightAnchor.constraint(equalToConstant: 3),
            routePicker.centerXAnchor.constraint(equalTo: deviceButton.centerXAnchor),
            routePicker.centerYAnchor.constraint(equalTo: deviceButton.centerYAnchor),
            routePicker.widthAnchor.constraint(equalToConstant: 64),
            routePicker.heightAnchor.constraint(equalToConstant: 48)
        ])

        let panA = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let panB = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        dragZone.addGestureRecognizer(panA)
        mediaView.addGestureRecognizer(panB)
        artPan = panB
    }

    // MARK: - Chế độ hiển thị

    private func updateLyricsFrame() {
        let safe = view.safeAreaInsets
        if mode == .immersive {
            lyricsTop?.constant = 0
            lyricsBottom?.constant = 0
        } else {
            lyricsTop?.constant = safe.top + 16 + 52 + 13 + 88 + 8
            lyricsBottom?.constant = -(safe.bottom + 236)
        }
    }

    private func apply(mode new: Mode, animated: Bool) {
        mode = new
        let lyr = new != .cover
        lyricsView.immersive = new == .immersive
        lyricsView.anchorFraction = new == .immersive ? 0.36 : 0.2
        updateLyricsFrame()
        let chromeAlpha: CGFloat = new == .immersive ? 0 : 1
        let chromeViews = chromeTop + chromeBottom
        if new != .immersive { chromeViews.forEach { $0.isUserInteractionEnabled = true } }
        let changes = {
            self.mediaView.alpha = lyr ? 0 : 1
            self.fluidView.alpha = lyr ? 1 : 0
            self.bandBlur.alpha = lyr ? 0 : 1
            self.bandShade.alpha = lyr ? 0 : 1
            self.topShade.alpha = lyr ? 0 : 1
            self.infoA.alpha = new == .cover ? 1 : 0
            self.infoB.alpha = new == .lyrics ? 1 : 0
            self.lyricsView.alpha = lyr ? 1 : 0
            chromeViews.forEach { $0.alpha = chromeAlpha }
            self.view.layoutIfNeeded()
        }
        if new == .immersive { chromeViews.forEach { $0.isUserInteractionEnabled = false } }
        if animated {
            UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: changes, completion: nil)
        } else {
            changes()
        }
        lyricsButton.setImage(Icons.lyrics(28, filled: lyr), for: .normal)
        artPan?.isEnabled = !lyr
        infoA.isUserInteractionEnabled = new == .cover
        infoB.isUserInteractionEnabled = new == .lyrics
        lyricsView.setRunning(lyr)
        if lyr {
            video.pause()
        } else {
            timeChanged()
        }
        scheduleIdle()
    }

    private func scheduleIdle() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard mode == .lyrics else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self = self, self.mode == .lyrics, !self.progress.isDragging else { return }
            self.apply(mode: .immersive, animated: true)
        }
    }

    /// Mọi lần chạm: đang ở chế độ toàn màn hình thì hiện lại các nút; luôn tính lại 5 giây.
    private func userTouched() {
        if mode == .immersive {
            suppressSeekUntil = Date().addingTimeInterval(0.8)
            DispatchQueue.main.async { self.apply(mode: .lyrics, animated: true) }
        } else {
            scheduleIdle()
        }
    }

    // MARK: - Cập nhật theo trạng thái phát

    @objc private func stateChanged() {
        let engine = PlayerEngine.shared
        guard let song = engine.currentSong else {
            dismiss(animated: true, completion: nil)
            return
        }
        if shownVideoId != song.videoId {
            shownVideoId = song.videoId
            shownArtwork = nil
            artView.image = nil
            infoA.thumb.image = nil
            infoB.thumb.image = nil
            lyricsVideoId = nil
            video.stop()
            if mode != .cover { loadLyrics() }
        }
        let liked = Library.shared.isLiked(song)
        let explicit = song.explicit ?? false
        infoA.set(title: song.title, artist: song.artist, explicit: explicit, liked: liked)
        infoB.set(title: song.title, artist: song.artist, explicit: explicit, liked: liked)

        let context = engine.contextTitle ?? "Đang phát"
        if contextPill.titleLabel.text != context {
            contextPill.titleLabel.text = context
            let width = (context as NSString).size(withAttributes: [.font: contextPill.titleLabel.font as Any]).width
            pillWidth?.constant = min(190, ceil(width) + 40)
        }

        if let image = engine.artwork, shownArtwork !== image {
            shownArtwork = image
            UIView.transition(with: mediaView, duration: 0.45, options: .transitionCrossDissolve, animations: {
                self.artView.image = image
            }, completion: nil)
            infoA.thumb.image = image
            infoB.thumb.image = image
            fluidView.setImage(image)
            applyTone(from: image)
        }

        playButton.setImage(engine.isPlaying || engine.isLoading ? Icons.pause(64) : Icons.play(64), for: .normal)
        shuffleButton.tintColor = engine.shuffleOn ? NowPlayingViewController.green : .white
        shuffleDot.alpha = engine.shuffleOn && mode != .immersive ? 1 : 0
        switch engine.repeatMode {
        case .off:
            repeatButton.setImage(Icons.repeatAll(28), for: .normal)
            repeatButton.tintColor = .white
        case .all:
            repeatButton.setImage(Icons.repeatAll(28), for: .normal)
            repeatButton.tintColor = NowPlayingViewController.green
        case .one:
            repeatButton.setImage(Icons.repeatOne(28), for: .normal)
            repeatButton.tintColor = NowPlayingViewController.green
        }
        refreshVideo()
        timeChanged()
    }

    /// Thanh tiến trình và nhãn thời gian lấy màu từ bìa (bản sáng của màu nền bài hát).
    private func applyTone(from image: UIImage) {
        guard let average = image.averageColor() else { return }
        var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &sat, brightness: &br, alpha: &a)
        let tone = UIColor(hue: h, saturation: min(1, sat * 0.85), brightness: 0.92, alpha: 1)
        progress.setTone(tone)
        elapsedLabel.textColor = tone.withAlphaComponent(0.75)
        remainingLabel.textColor = tone.withAlphaComponent(0.75)
    }

    @objc private func libraryChanged() {
        guard let song = PlayerEngine.shared.currentSong else { return }
        let liked = Library.shared.isLiked(song)
        let explicit = song.explicit ?? false
        infoA.set(title: song.title, artist: song.artist, explicit: explicit, liked: liked)
        infoB.set(title: song.title, artist: song.artist, explicit: explicit, liked: liked)
    }

    @objc private func timeChanged() {
        let engine = PlayerEngine.shared
        if !progress.isDragging {
            let total = engine.duration
            let fraction = total > 0 ? min(1, engine.currentTime / total) : 0
            if progress.value != fraction {
                progress.value = fraction
            }
            elapsedLabel.text = formatTime(engine.currentTime)
            remainingLabel.text = total > 0 ? "-" + formatTime(max(0, total - engine.currentTime)) : "-:--"
        }
        if mode == .cover { video.sync(position: engine.livePosition, playing: engine.isPlaying) }
    }

    private func scrubbed(_ value: Double, ended: Bool) {
        let engine = PlayerEngine.shared
        let total = engine.duration
        elapsedLabel.text = formatTime(value * total)
        remainingLabel.text = "-" + formatTime(max(0, total - value * total))
        if ended { engine.seek(to: value * total) }
    }

    /// Có MV thì bắt buộc dùng video làm nền (nếu bật trong Cài đặt); không có thì giữ ảnh bìa.
    private func refreshVideo() {
        let engine = PlayerEngine.shared
        guard AppSettings.videoBackdrop, let song = engine.currentSong, let info = engine.streamInfo,
              let url = info.videoURL, !engine.isLocal else {
            if video.key != nil { video.stop() }
            return
        }
        let key = song.videoId + "|" + url.absoluteString
        if video.key == key { return }
        video.load(url: url, userAgent: info.userAgent, key: key, position: engine.livePosition)
    }

    private func loadLyrics() {
        let engine = PlayerEngine.shared
        guard let song = engine.currentSong, lyricsVideoId != song.videoId else {
            lyricsView.update(time: engine.livePosition)
            return
        }
        lyricsVideoId = song.videoId
        lyricsView.showLoading()
        LyricsService.shared.lyrics(for: song, durationHint: engine.duration) { [weak self] result in
            guard let self = self, self.lyricsVideoId == song.videoId else { return }
            self.lyricsView.show(result)
            self.lyricsView.update(time: PlayerEngine.shared.livePosition)
        }
    }

    // MARK: - Hành động

    @objc private func noop() {}

    @objc private func lyricsTapped() {
        Haptics.tap()
        if mode == .cover {
            lyricsView.resetFollow()
            loadLyrics()
            apply(mode: .lyrics, animated: true)
        } else {
            apply(mode: .cover, animated: true)
        }
    }

    @objc private func likeTapped() {
        guard let song = PlayerEngine.shared.currentSong else { return }
        Haptics.tap()
        Library.shared.toggleLike(song)
        infoA.checkButton.pop()
        infoB.checkButton.pop()
    }

    private func moreTapped() {
        guard let song = PlayerEngine.shared.currentSong else { return }
        let engine = PlayerEngine.shared
        var message: String? = nil
        if let stream = engine.streamInfo { message = stream.badge }
        let sheet = UIAlertController(title: song.title, message: message, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: engine.sleepEnd != nil ? "Hẹn giờ tắt (đang bật)…" : "Hẹn giờ tắt nhạc…", style: .default) { [weak self] _ in
            self?.sleepTapped()
        })
        let manager = DownloadManager.shared
        if manager.isActive(song.videoId) {
            sheet.addAction(UIAlertAction(title: "Huỷ tải xuống", style: .default) { _ in manager.cancel(song.videoId) })
        } else if !Library.shared.isDownloaded(song) {
            sheet.addAction(UIAlertAction(title: "Tải xuống", style: .default) { _ in
                manager.start(song)
                Toast.show("Đang tải xuống…")
            })
        }
        sheet.addAction(UIAlertAction(title: "Thêm vào playlist, chia sẻ…", style: .default) { [weak self] _ in
            guard let self = self else { return }
            SongActions.present(for: song, from: self, sourceView: self.moreGlass)
        })
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = moreGlass
            popover.sourceRect = moreGlass.bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    @objc private func playTapped() {
        Haptics.tap()
        PlayerEngine.shared.togglePlayPause()
    }

    @objc private func nextTapped() {
        Haptics.tap()
        PlayerEngine.shared.next()
    }

    @objc private func prevTapped() {
        Haptics.tap()
        PlayerEngine.shared.previous()
    }

    @objc private func shuffleTapped() {
        let engine = PlayerEngine.shared
        engine.setShuffle(!engine.shuffleOn)
        Toast.show(engine.shuffleOn ? "Ngẫu nhiên: bật" : "Ngẫu nhiên: tắt")
    }

    @objc private func repeatTapped() {
        PlayerEngine.shared.cycleRepeat()
        switch PlayerEngine.shared.repeatMode {
        case .off: Toast.show("Lặp lại: tắt")
        case .all: Toast.show("Lặp lại cả danh sách")
        case .one: Toast.show("Lặp lại một bài")
        }
    }

    private func sleepTapped() {
        let engine = PlayerEngine.shared
        var message: String? = nil
        if let end = engine.sleepEnd {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            message = "Đang hẹn tắt lúc \(f.string(from: end))"
        }
        let sheet = UIAlertController(title: "Hẹn giờ tắt nhạc", message: message, preferredStyle: .actionSheet)
        for minutes in [15, 30, 45, 60] {
            sheet.addAction(UIAlertAction(title: "\(minutes) phút", style: .default) { _ in
                engine.setSleepTimer(minutes: minutes)
                Toast.show("Sẽ tắt nhạc sau \(minutes) phút")
            })
        }
        if engine.sleepEnd != nil {
            sheet.addAction(UIAlertAction(title: "Tắt hẹn giờ", style: .destructive) { _ in
                engine.setSleepTimer(minutes: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = moreGlass
            popover.sourceRect = moreGlass.bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    @objc private func queueTapped() {
        let nav = UINavigationController(rootViewController: QueueViewController())
        Theme.style(navigationBar: nav.navigationBar)
        present(nav, animated: true, completion: nil)
    }

    // MARK: - Kéo xuống để đóng

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let space = view.superview ?? view.window
        let translation = max(0, gesture.translation(in: space).y)
        let height = max(1, view.bounds.height)
        switch gesture.state {
        case .began:
            // Chụp sẵn thành một ảnh để kéo mượt (video/làm mờ không phải vẽ lại mỗi khung hình).
            view.layer.shouldRasterize = true
            view.layer.rasterizationScale = UIScreen.main.scale
        case .changed:
            view.transform = CGAffineTransform(translationX: 0, y: translation)
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: space).y
            if translation > height * 0.22 || velocity > 900 {
                dismiss(animated: true, completion: nil)
            } else {
                UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3,
                               options: [], animations: {
                    self.view.transform = CGAffineTransform.identity
                }, completion: { _ in
                    self.view.layer.shouldRasterize = false
                })
            }
        default:
            break
        }
    }
}
