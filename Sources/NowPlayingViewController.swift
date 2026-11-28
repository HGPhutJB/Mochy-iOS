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
            // Bìa bay nằm DƯỚI dải mờ và nền màu (không đè lên hiệu ứng). Nó là con của màn hình đang trượt lên,
            // nên toạ độ xuất phát lùi đúng bằng quãng trượt để trên màn hình vẫn đi từ thanh phát nhỏ tới bìa lớn.
            let slide = container.bounds.height
            flying.frame = start.offsetBy(dx: 0, dy: -slide)
            flying.layer.cornerRadius = 10
            toVC.insertBelowBlur(flying)
            realArt.alpha = 0
            miniArt?.alpha = 0

            // Không rasterize: các lớp làm mờ (blur) không chụp được, rasterize làm dải mờ biến mất rồi bật lên đột ngột.
            // Dải mờ trượt lên cùng cả màn hình, luôn hiển thị đủ (không đổi alpha của lớp làm mờ vì iOS 12 vẽ sai).
            toView.transform = CGAffineTransform(translationX: 0, y: slide)
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0,
                           options: [.curveEaseOut], animations: {
                toView.transform = CGAffineTransform.identity
                flying.frame = target
                flying.layer.cornerRadius = 0
            }, completion: { _ in
                realArt.alpha = 1
                UIView.animate(withDuration: 0.18, animations: { flying.alpha = 0 }, completion: { _ in flying.removeFromSuperview() })
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
            let slide = container.bounds.height
            if fromVC.isCoverMode {
                fromVC.insertBelowBlur(flying)
            } else {
                // Đang bật lời: nền màu phủ kín nên bìa bay phải nằm trên mới nhìn thấy.
                container.addSubview(flying)
            }
            realArt.alpha = 0
            miniArt?.alpha = 0
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0,
                           options: [.curveEaseInOut], animations: {
                fromView.transform = CGAffineTransform(translationX: 0, y: slide)
                flying.frame = flying.superview === container ? end : end.offsetBy(dx: 0, dy: -slide)
                flying.layer.cornerRadius = 10
            }, completion: { _ in
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
    private static let green = Theme.accent   // màu nhấn của Mochy
    private var tone = UIColor.white           // màu nhấn lấy từ ảnh bìa
    private var toneLight: UIColor { return tone.mixed(with: .white, amount: 0.3) }   // bản sáng hơn cho nút
    private var weightPanel: WeightPanel?
    private var coverLuminance: CGFloat = 0.2   // độ sáng phần dưới ảnh bìa
    /// Nền phía dưới (khi chưa bật lời) có sáng không: theo cài đặt hoặc tự động theo ảnh bìa.
    private var backdropLight: Bool {
        switch AppSettings.playerBlur {
        case .light: return true
        case .dark: return false
        case .auto: return false   // tự động: màu dải dưới đồng bộ với nền lời (tối, theo bảng màu bìa)
        }
    }
    /// Nền sáng thì nút/chữ dùng màu tối (lấy tông của bìa), nền tối thì dùng bản sáng.
    private var iconColor: UIColor {
        return mode == .cover && backdropLight ? tone.mixed(with: .black, amount: 0.65) : toneLight
    }

    private let mediaView = UIView()
    private let artView = UIImageView()
    private let backFill = UIImageView()   // bản mờ của bìa phủ kín màn hình, nằm sau bìa vuông
    private let artFade = CAGradientLayer()
    private let video = VideoBackdrop()
    private let fluidView = FluidBackgroundView()
    private let bandBlur = ProgressiveBlurView(layers: 4)
    private let bandShade = GradientView()
    private let topShade = GradientView()
    private let dragZone = UIView()
    private let lyricsView = LyricsView()
    private let stage = LandscapeStage()
    private var lyricsLeading: NSLayoutConstraint?
    private var isLandscape = false
    private var modeBeforeLandscape: Mode = .cover

    private let chevron = GlassView(tint: nil)
    private let contextPill = GlassView(tint: nil)
    private let moreGlass = GlassView(tint: nil)
    private let infoA = InfoRow(withThumb: false)
    private let infoB = InfoRow(withThumb: true, compact: true, translate: true)

    private let progress = ProgressBar()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let shuffleButton = ControlButton(type: .custom)
    private let shuffleDot = UIView()
    private let prevButton = ControlButton(type: .custom)
    private let playButton = ControlButton(type: .custom)
    private let nextButton = ControlButton(type: .custom)
    private let repeatButton = ControlButton(type: .custom)
    private let lyricsButton = ControlButton(type: .custom)
    private let deviceButton = ControlButton(type: .custom)
    private let routePicker = AVRoutePickerView()
    private let queueButton = ControlButton(type: .custom)

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

    /// Chèn một view ngay dưới dải mờ (trên bìa nền, dưới nền màu và mờ) cho các hiệu ứng bìa bay.
    func insertBelowBlur(_ v: UIView) {
        loadViewIfNeeded()
        view.insertSubview(v, belowSubview: bandBlur)
    }

    var isCoverMode: Bool { return mode == .cover }

    /// Bìa lớn co về ảnh nhỏ cạnh tên bài (bật lời) hoặc ngược lại; bay ở dưới lớp nền màu.
    private func flyCover(toLyrics: Bool) {
        guard let image = artView.image, !isLandscape, infoB.thumb.superview != nil else { return }
        view.layoutIfNeeded()
        let big = mediaView.convert(artView.frame, to: view)
        let small = infoB.thumb.superview!.convert(infoB.thumb.frame, to: view)
        let f = UIImageView(image: image)
        f.contentMode = .scaleAspectFill
        f.clipsToBounds = true
        f.frame = toLyrics ? big : small
        f.layer.cornerRadius = toLyrics ? 0 : 14
        view.insertSubview(f, belowSubview: bandBlur)
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                       options: [.curveEaseInOut], animations: {
            f.frame = toLyrics ? small : big
            f.layer.cornerRadius = toLyrics ? 14 : 0
        }, completion: { _ in
            UIView.animate(withDuration: 0.2, animations: { f.alpha = 0 }, completion: { _ in f.removeFromSuperview() })
        })
    }

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
        center.addObserver(self, selector: #selector(updateReverbIndicator), name: .reverbChanged, object: nil)
        updateReverbIndicator()
        center.addObserver(self, selector: #selector(stateChanged), name: .playerStateChanged, object: nil)
        center.addObserver(self, selector: #selector(timeChanged), name: .playerTimeChanged, object: nil)
        center.addObserver(self, selector: #selector(libraryChanged), name: .libraryChanged, object: nil)
        center.addObserver(self, selector: #selector(libraryChanged), name: .downloadChanged, object: nil)
        stateChanged()
        apply(mode: .cover, animated: false)
        fluidView.setReveal(.hidden, animated: false)   // dải màu sẽ trồi lên khi màn hình hiện xong
    }

    private var didAppearOnce = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        OrientationPolicy.allowLandscape = true
        refreshHidesPast()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if presentedViewController == nil {
            OrientationPolicy.allowLandscape = false
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didAppearOnce {
            didAppearOnce = true
            if mode == .cover { fluidView.setReveal(.band, animated: true) }
            refreshVideo()
        }
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
        backFill.frame = mediaView.bounds
        // Bìa vuông rộng hết chiều ngang, phần đáy mờ dần vào nền; xoay ngang không dùng.
        artView.frame = CGRect(x: 0, y: 0, width: w, height: min(w, h))
        artFade.frame = artView.bounds
        video.layer.frame = mediaView.bounds
        let bandTop = h * 0.42
        bandBlur.frame = CGRect(x: 0, y: bandTop, width: w, height: h - bandTop)
        bandShade.frame = bandBlur.frame
        topShade.frame = CGRect(x: 0, y: 0, width: w, height: 170)
        stage.frame = view.bounds
        let landscape = w > h
        if landscape != isLandscape { setLandscape(landscape) }
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
        backFill.contentMode = .scaleAspectFill
        backFill.clipsToBounds = true
        backFill.backgroundColor = UIColor(white: 0.06, alpha: 1)
        mediaView.addSubview(backFill)
        mediaView.addSubview(artView)
        artFade.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
        artFade.locations = [0, 0.8, 1]
        artView.layer.mask = artFade
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
        fluidView.setReveal(.hidden, animated: false)

        bandBlur.isUserInteractionEnabled = false
        view.addSubview(bandBlur)
        view.addSubview(fluidView)   // nằm trên lớp mờ: dải màu phủ lên phần ảnh đã mờ
        bandShade.isUserInteractionEnabled = false
        bandShade.gradientLayer.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.32).cgColor]
        bandShade.gradientLayer.locations = [0.3, 1]
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

        stage.alpha = 0
        stage.isHidden = true
        stage.onScrub = { [weak self] value, ended in self?.scrubbed(value, ended: ended) }
        stage.prevBtn.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        stage.playBtn.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        stage.nextBtn.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        stage.close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        stage.translate.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
        stage.reverb.addTarget(self, action: #selector(reverbTapped), for: .touchUpInside)
        stage.queue.addTarget(self, action: #selector(queueTapped), for: .touchUpInside)
        stage.more.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        view.addSubview(stage)

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
        infoB.translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)

        // Thanh trên cùng.
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.iconView.image = Icons.chevronDown(20)
        chevron.onTap = { [weak self] in self?.dismiss(animated: true, completion: nil) }
        contextPill.translatesAutoresizingMaskIntoConstraints = false
        contextPill.titleLabel.font = RoundedFont.font(13, index: 5)
        contextPill.onTap = nil
        moreGlass.translatesAutoresizingMaskIntoConstraints = false
        moreGlass.iconView.image = Icons.more(20)
        moreGlass.onTap = { [weak self] in self?.moreTapped() }
        [chevron, contextPill, moreGlass].forEach { view.addSubview($0) }
        chromeTop = [chevron, contextPill, moreGlass]

        // Tiến trình.
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.onScrub = { [weak self] value, ended in self?.scrubbed(value, ended: ended) }
        for label in [elapsedLabel, remainingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = RoundedFont.font(13, index: 5)
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
        icon(deviceButton, Icons.reverb(28), #selector(reverbTapped))
        icon(queueButton, Icons.queue(28), #selector(queueTapped))
        routePicker.isUserInteractionEnabled = false
        routePicker.translatesAutoresizingMaskIntoConstraints = false
        routePicker.tintColor = UIColor.clear
        routePicker.activeTintColor = UIColor.clear
        routePicker.backgroundColor = UIColor.clear

        chromeBottom = [progress, elapsedLabel, remainingLabel, shuffleButton, shuffleDot, prevButton, playButton,
                        nextButton, repeatButton, lyricsButton, deviceButton, routePicker, queueButton]
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
        let ll = lyricsView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        lyricsLeading = ll
        lyricsBottom = lb

        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 17),
            chevron.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            chevron.widthAnchor.constraint(equalToConstant: 40),
            chevron.heightAnchor.constraint(equalToConstant: 40),
            moreGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -17),
            moreGlass.topAnchor.constraint(equalTo: chevron.topAnchor),
            moreGlass.widthAnchor.constraint(equalToConstant: 40),
            moreGlass.heightAnchor.constraint(equalToConstant: 40),
            contextPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contextPill.centerYAnchor.constraint(equalTo: chevron.centerYAnchor),
            contextPill.heightAnchor.constraint(equalToConstant: 32),
            pw,

            infoB.topAnchor.constraint(equalTo: chevron.bottomAnchor, constant: 10),
            infoB.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            infoB.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            infoB.heightAnchor.constraint(equalToConstant: 62),

            ll,
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
            routePicker.centerXAnchor.constraint(equalTo: deviceButton.centerXAnchor),
            routePicker.centerYAnchor.constraint(equalTo: deviceButton.centerYAnchor),
            routePicker.widthAnchor.constraint(equalToConstant: 8),
            routePicker.heightAnchor.constraint(equalToConstant: 8)
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
        if isLandscape {
            lyricsLeading?.constant = view.bounds.width * 0.47
            lyricsTop?.constant = 0
            lyricsBottom?.constant = 0
            return
        }
        lyricsLeading?.constant = 0
        if mode == .immersive {
            lyricsTop?.constant = 0
            lyricsBottom?.constant = 0
        } else {
            lyricsTop?.constant = safe.top + 8 + 40 + 10 + 62 + 8
            lyricsBottom?.constant = -(safe.bottom + 236)
        }
    }

    private func apply(mode new: Mode, animated: Bool) {
        let previous = mode
        if animated && !isLandscape && ((previous == .cover) != (new == .cover)) { flyCover(toLyrics: new != .cover) }
        // Như video: tên bài + nghệ sĩ trượt lên/xuống cùng lúc bìa co/phóng (không chỉ mờ chéo).
        let slide = animated && !isLandscape && ((previous == .cover && new == .lyrics) || (previous == .lyrics && new == .cover))
        var slideDest: InfoRow?
        if slide {
            view.layoutIfNeeded()
            let src = new == .lyrics ? infoA : infoB
            let dst = new == .lyrics ? infoB : infoA
            let wasHidden = src.thumb.isHidden
            src.thumb.isHidden = true
            if let snap = src.snapshotView(afterScreenUpdates: false) {
                snap.frame = src.frame
                snap.isUserInteractionEnabled = false
                view.insertSubview(snap, aboveSubview: dst)
                let a = src.titleLabel.convert(src.titleLabel.bounds, to: view).origin
                let b = dst.titleLabel.convert(dst.titleLabel.bounds, to: view).origin
                UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                               options: [], animations: {
                    snap.transform = CGAffineTransform(translationX: b.x - a.x, y: b.y - a.y)
                }, completion: nil)
                UIView.animate(withDuration: 0.2, delay: 0.3, options: [.curveEaseIn], animations: { snap.alpha = 0 },
                               completion: { _ in snap.removeFromSuperview() })
            }
            src.thumb.isHidden = wasHidden
            src.layer.removeAllAnimations()
            src.alpha = 0
            dst.alpha = 0
            slideDest = dst
        }
        mode = new
        let lyr = new != .cover
        lyricsView.immersive = new == .immersive
        lyricsView.anchorFraction = new == .immersive ? 0.36 : 0.2
        updateLyricsFrame()
        let chromeAlpha: CGFloat = new == .immersive ? 0 : 1
        let chromeViews = chromeTop + chromeBottom
        if new != .immersive { chromeViews.forEach { $0.isUserInteractionEnabled = true } }
        fluidView.setReveal(lyr ? .full : .band, animated: animated)
        if lyr { video.pause() }   // lời phủ kín thì không cần giải mã video phía sau
        let changes = {
            self.mediaView.alpha = lyr ? 0 : 1
            self.fluidView.alpha = lyr ? 1 : (self.backdropLight ? 0 : 1)
            self.bandBlur.alpha = lyr ? 0 : 1
            self.bandShade.alpha = lyr ? 0 : 1
            self.topShade.alpha = lyr ? 0 : 1
            if !slide {
                self.infoA.alpha = new == .cover ? 1 : 0
                self.infoB.alpha = new == .lyrics ? 1 : 0
            }
            self.lyricsView.alpha = lyr ? 1 : 0
            chromeViews.forEach { $0.alpha = chromeAlpha }
            self.view.layoutIfNeeded()
        }
        if new == .immersive { chromeViews.forEach { $0.isUserInteractionEnabled = false } }
        if let d = slideDest {
            UIView.animate(withDuration: 0.25, delay: 0.3, options: [.curveEaseOut, .allowUserInteraction], animations: { d.alpha = 1 }, completion: nil)
        }
        if animated {
            UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: changes, completion: nil)
        } else {
            changes()
        }
        lyricsButton.setImage(Icons.lyrics(28, filled: lyr), for: .normal)
        lyricsButton.tintColor = lyr ? NowPlayingViewController.green : iconColor
        refreshBackdrop(animated: animated)
        artPan?.isEnabled = !lyr
        infoA.isUserInteractionEnabled = new == .cover
        infoB.isUserInteractionEnabled = new == .lyrics
        lyricsView.setRunning(lyr)
        if lyr {
            video.pause()
        } else {
            timeChanged()
        }
        if isLandscape { landscapeOverride() }
        refreshHidesPast()
        scheduleIdle()
    }

    // MARK: - Xoay ngang

    private func refreshHidesPast() {
        switch AppSettings.hidePastLyrics {
        case 1: lyricsView.hidesPast = true
        case 2: lyricsView.hidesPast = false
        default: lyricsView.hidesPast = isLandscape
        }
    }

    private func setLandscape(_ on: Bool) {
        guard on != isLandscape else { return }
        isLandscape = on
        LyricCell.landscape = on
        dragZone.isUserInteractionEnabled = !on   // vùng kéo xuống chắn mất các nút phía trên khi xoay ngang
        view.bringSubviewToFront(stage)
        if on {
            modeBeforeLandscape = mode == .immersive ? .lyrics : mode
            lyricsView.resetFollow()
            loadLyrics()
            apply(mode: .lyrics, animated: false)
            stage.isHidden = false
            stage.setControls(visible: true, animated: false)
            lyricsView.anchorFraction = 0.33
            lyricsView.immersive = false
            updateLyricsFrame()
            view.layoutIfNeeded()
            lyricsView.reloadStyle()
            DispatchQueue.main.async { [weak self] in self?.lyricsView.reloadStyle() }
            landscapeOverride()
            syncStage()
            UIView.animate(withDuration: 0.3) { self.stage.alpha = 1 }
        } else {
            stage.alpha = 0
            stage.isHidden = true
            updateLyricsFrame()
            view.layoutIfNeeded()
            apply(mode: modeBeforeLandscape, animated: false)
            lyricsView.reloadStyle()
            DispatchQueue.main.async { [weak self] in self?.lyricsView.reloadStyle() }
            for v in chromeTop + chromeBottom { v.isUserInteractionEnabled = true }
        }
        refreshHidesPast()
        scheduleIdle()
    }

    /// Xoay ngang: ẩn mọi thứ của bố cục dọc, chỉ để nền màu, lời và bảng điều khiển bên trái.
    private func landscapeOverride() {
        mediaView.alpha = 0
        bandBlur.alpha = 0
        bandShade.alpha = 0
        topShade.alpha = 0
        infoA.alpha = 0
        infoB.alpha = 0
        (chromeTop + chromeBottom).forEach { $0.alpha = 0; $0.isUserInteractionEnabled = false }
        fluidView.setReveal(.full, animated: false)
        fluidView.alpha = 1
        lyricsView.alpha = 1
        lyricsView.anchorFraction = 0.33
        lyricsView.immersive = false
    }

    private func syncStage() {
        let engine = PlayerEngine.shared
        guard let song = engine.currentSong else { return }
        stage.set(title: song.title, artist: song.artist, image: engine.artwork)
        stage.setPlaying(engine.isPlaying || engine.isLoading)
        stage.reverb.tintColor = ReverbSettings.enabled ? NowPlayingViewController.green : .white
        stage.translate.setImage(InfoRow.translateImage(on: TranslateSettings.enabled), for: .normal)
        let total = engine.duration
        stage.setTime(fraction: total > 0 ? min(1, engine.currentTime / total) : 0,
                      elapsedText: formatTime(engine.currentTime),
                      remainingText: total > 0 ? "-" + formatTime(max(0, total - engine.currentTime)) : "-:--")
    }

    @objc private func closeTapped() {
        dismiss(animated: true, completion: nil)
    }

    private func scheduleIdle() {
        idleTimer?.invalidate()
        idleTimer = nil
        if isLandscape {
            // Xoay ngang: các nút tua/phát và nút phía trên luôn hiện, không tự ẩn.
            if !stage.controlsVisible { stage.setControls(visible: true, animated: true) }
            return
        }
        guard mode == .lyrics, weightPanel == nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self = self, self.mode == .lyrics, !self.progress.isDragging else { return }
            self.apply(mode: .immersive, animated: true)
        }
    }

    /// Mọi lần chạm: đang ở chế độ toàn màn hình thì hiện lại các nút; luôn tính lại 5 giây.
    private func userTouched() {
        if isLandscape {
            if !stage.controlsVisible { stage.setControls(visible: true, animated: true) }
            scheduleIdle()
            return
        }
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
            backFill.image = nil
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

        let context = engine.contextTitle ?? L("Đang phát")
        if contextPill.titleLabel.text != context {
            contextPill.titleLabel.text = context
            let width = (context as NSString).size(withAttributes: [.font: contextPill.titleLabel.font as Any]).width
            pillWidth?.constant = min(190, ceil(width) + 32)
        }

        if let image = engine.artwork, shownArtwork !== image {
            shownArtwork = image
            UIView.transition(with: mediaView, duration: 0.45, options: .transitionCrossDissolve, animations: {
                self.artView.image = image
            }, completion: nil)
            infoA.thumb.image = image
            infoB.thumb.image = image
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let soft = FluidBackgroundView.makeAmbient(image) else { return }
                DispatchQueue.main.async {
                    guard let self = self, self.shownArtwork === image else { return }
                    UIView.transition(with: self.backFill, duration: 0.45, options: .transitionCrossDissolve, animations: {
                        self.backFill.image = UIImage(cgImage: soft)
                    }, completion: nil)
                }
            }
            fluidView.setImage(image)
            applyTone(from: image)
        }

        playButton.setImageAnimated(engine.isPlaying || engine.isLoading ? Icons.pause(64) : Icons.play(64))
        shuffleButton.tintColor = engine.shuffleOn ? NowPlayingViewController.green : iconColor.withAlphaComponent(0.7)
        shuffleDot.alpha = engine.shuffleOn && mode != .immersive ? 1 : 0
        switch engine.repeatMode {
        case .off:
            repeatButton.setImage(Icons.repeatAll(28), for: .normal)
            repeatButton.tintColor = iconColor.withAlphaComponent(0.7)
        case .all:
            repeatButton.setImage(Icons.repeatAll(28), for: .normal)
            repeatButton.tintColor = NowPlayingViewController.green
        case .one:
            repeatButton.setImage(Icons.repeatOne(28), for: .normal)
            repeatButton.tintColor = NowPlayingViewController.green
        }
        refreshVideo()
        timeChanged()
        if isLandscape { syncStage() }
    }

    /// Thanh tiến trình, nhãn thời gian và các icon lấy màu từ bìa.
    private func applyTone(from image: UIImage) {
        guard let color = image.songTone() else { return }
        tone = color
        coverLuminance = image.bottomLuminance() ?? 0.2
        refreshBackdrop(animated: true)
    }

    /// Chỉnh dải mờ, bóng, chữ và nút theo độ sáng của nền (bìa sáng → mờ sáng + chữ tối).
    private func refreshBackdrop(animated: Bool) {
        let light = backdropLight
        bandBlur.setLight(light, animated: animated)
        if mode == .cover {
            let target: CGFloat = light ? 0 : 1
            if animated { UIView.animate(withDuration: 0.5) { self.fluidView.alpha = target } } else { fluidView.alpha = target }
        }
        bandShade.gradientLayer.colors = [UIColor.clear.cgColor,
                                          (light ? UIColor(white: 1, alpha: 0.28) : UIColor(white: 0, alpha: 0.32)).cgColor]
        infoA.setInk(dark: light)
        applyIconTints()
    }

    private func applyIconTints() {
        let engine = PlayerEngine.shared
        let color = iconColor
        UIView.animate(withDuration: 0.4) {
            self.progress.setTone(color)
            self.elapsedLabel.textColor = color.withAlphaComponent(0.8)
            self.remainingLabel.textColor = color.withAlphaComponent(0.8)
            for b in [self.prevButton, self.playButton, self.nextButton, self.queueButton] {
                b.tintColor = color
            }
            self.lyricsButton.tintColor = self.mode == .cover ? color : NowPlayingViewController.green
            self.deviceButton.tintColor = ReverbSettings.enabled ? NowPlayingViewController.green : color
            self.shuffleButton.tintColor = engine.shuffleOn ? NowPlayingViewController.green : color.withAlphaComponent(0.7)
            self.repeatButton.tintColor = engine.repeatMode == .off ? color.withAlphaComponent(0.7) : NowPlayingViewController.green
        }
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
        if mode == .cover && !isLandscape { video.sync(position: engine.livePosition, playing: engine.isPlaying) }
        if isLandscape {
            let total = engine.duration
            stage.setTime(fraction: total > 0 ? min(1, engine.currentTime / total) : 0,
                          elapsedText: formatTime(engine.currentTime),
                          remainingText: total > 0 ? "-" + formatTime(max(0, total - engine.currentTime)) : "-:--")
        }
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
        // Chờ màn hình hiện xong mới tải/giải mã video để hiệu ứng mở không bị giật.
        guard didAppearOnce else { return }
        let engine = PlayerEngine.shared
        guard AppSettings.videoBackdrop, let song = engine.currentSong else {
            if video.key != nil { video.stop() }
            return
        }
        // 1) Canvas của Spotify (nếu đã nhập sp_dc và bài có Canvas).
        if SpotifyCanvas.isConfigured {
            let state = SpotifyCanvas.shared.cached(song.videoId)
            if let known = state {
                if let url = known {
                    let key = song.videoId + "|canvas|" + url.absoluteString
                    if video.key != key { video.load(url: url, userAgent: LyricsHTTP.browserUA, key: key, position: 0, loop: true) }
                    return
                }
            } else {
                SpotifyCanvas.shared.request(song, duration: engine.duration) { [weak self] _ in
                    guard PlayerEngine.shared.currentSong == song else { return }
                    self?.refreshVideo()
                }
            }
        }
        // 2) MV YouTube; 3) không có thì giữ ảnh bìa.
        guard let info = engine.streamInfo, let url = info.videoURL, !engine.isLocal else {
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
            applyTranslation(manual: false)
            return
        }
        lyricsVideoId = song.videoId
        lyricsView.showLoading()
        LyricsService.shared.lyrics(for: song, durationHint: engine.duration) { [weak self] result in
            guard let self = self, self.lyricsVideoId == song.videoId else { return }
            self.lyricsView.show(result)
            self.lyricsView.update(time: PlayerEngine.shared.livePosition)
            self.applyTranslation(manual: false)
        }
    }

    @objc private func translateTapped() {
        Haptics.tap()
        TranslateSettings.enabled.toggle()
        infoB.translateButton.setImage(InfoRow.translateImage(on: TranslateSettings.enabled), for: .normal)
        stage.translate.setImage(InfoRow.translateImage(on: TranslateSettings.enabled), for: .normal)
        infoB.translateButton.pop()
        if TranslateSettings.enabled {
            applyTranslation(manual: true)
        } else {
            lyricsView.setTranslations(nil)
        }
    }

    /// Dịch lời bài đang phát (nếu đang bật dịch) và hiện dưới từng dòng.
    private func applyTranslation(manual: Bool) {
        guard TranslateSettings.enabled, let song = PlayerEngine.shared.currentSong, lyricsVideoId == song.videoId else { return }
        let texts = lyricsView.lineTexts
        guard !texts.isEmpty else {
            if manual { Toast.show(L("Bài này chưa có lời đồng bộ theo dòng để dịch")) }
            return
        }
        let target = TranslateSettings.target
        if let hit = LyricTranslator.shared.cached(videoId: song.videoId, target: target, count: texts.count) {
            lyricsView.setTranslations(hit)
            return
        }
        if manual { Toast.show(Lf("Đang dịch sang %@…", TranslateSettings.targetName)) }
        LyricTranslator.shared.translate(videoId: song.videoId, lines: texts, target: target) { [weak self] result, error in
            guard let self = self, TranslateSettings.enabled, self.lyricsVideoId == song.videoId, TranslateSettings.target == target else { return }
            if let result = result {
                if result.allSatisfy({ $0.isEmpty }) {
                    if manual { Toast.show(Lf("Lời bài này đã là %@", TranslateSettings.targetName)) }
                } else {
                    self.lyricsView.setTranslations(result)
                }
            } else {
                Toast.show(error ?? L("Không dịch được"))
            }
        }
    }

    // MARK: - Hành động

    @objc private func noop() {}

    @objc private func reverbTapped() {
        ReverbPanelViewController.present(from: self)
    }

    /// Nút reverb được tô màu xanh khi đang bật (không còn gạch dưới).
    @objc private func updateReverbIndicator() {
        stage.reverb.tintColor = ReverbSettings.enabled ? NowPlayingViewController.green : .white
        applyIconTints()
    }

    /// Mở bảng chọn thiết bị phát (AirPlay) bằng nút bên trong AVRoutePickerView.
    private func showRoutePicker() {
        for sub in routePicker.subviews {
            if let button = sub as? UIButton { button.sendActions(for: .touchUpInside); return }
        }
    }

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
        let nowLiked = Library.shared.toggleLike(song)
        LastFM.shared.love(song, loved: nowLiked)
        if nowLiked && !isLandscape {
            HeartBurstView.play(in: view, at: CGPoint(x: view.bounds.midX, y: view.bounds.height * 0.36))
        }
    }

    @objc private func moreTapped() {
        guard let song = PlayerEngine.shared.currentSong else { return }
        let engine = PlayerEngine.shared
        var message: String? = nil
        if let stream = engine.streamInfo { message = stream.badge }
        let sheet = UIAlertController(title: song.title, message: message, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: engine.sleepEnd != nil ? L("Hẹn giờ tắt (đang bật)…") : L("Hẹn giờ tắt nhạc…"), style: .default) { [weak self] _ in
            self?.sleepTapped()
        })
        sheet.addAction(UIAlertAction(title: ReverbSettings.enabled ? L("Reverb (đang bật)…") : "Reverb…", style: .default) { [weak self] _ in
            guard let self = self else { return }
            ReverbPanelViewController.present(from: self)
        })
        sheet.addAction(UIAlertAction(title: L("Thiết bị phát (AirPlay)…"), style: .default) { [weak self] _ in
            self?.showRoutePicker()
        })
        let manager = DownloadManager.shared
        if manager.isActive(song.videoId) {
            sheet.addAction(UIAlertAction(title: L("Huỷ tải xuống"), style: .default) { _ in manager.cancel(song.videoId) })
        } else if !Library.shared.isDownloaded(song) {
            sheet.addAction(UIAlertAction(title: L("Tải xuống"), style: .default) { _ in
                manager.start(song)
                Toast.show(L("Đang tải xuống…"))
            })
        }
        sheet.addAction(UIAlertAction(title: L("Thêm vào playlist, chia sẻ…"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            SongActions.present(for: song, from: self, sourceView: self.moreGlass)
        })
        sheet.addAction(UIAlertAction(title: L("Thông tin bài hát"), style: .default) { [weak self] _ in
            let nav = GlassNavigationController(rootViewController: SongInfoViewController(song: song))
            self?.present(nav, animated: true, completion: nil)
        })
        if let artistId = song.artistId, !artistId.isEmpty {
            sheet.addAction(UIAlertAction(title: L("Xem nghệ sĩ"), style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.dismiss(animated: true) {
                    MusicPageViewController.present(artist: song.artist, id: artistId, from: UIApplication.shared.keyWindow?.rootViewController ?? self)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: Lf("Độ đậm lời: %@…", RoundedFont.titles[AppSettings.lyricWeight]), style: .default) { [weak self] _ in
            self?.showWeightPanel()
        })
        sheet.addAction(UIAlertAction(title: Lf("Làm mờ nền: %@…", AppSettings.playerBlur.title), style: .default) { [weak self] _ in
            self?.blurTapped()
        })
        sheet.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = moreGlass
            popover.sourceRect = moreGlass.bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    /// Hiện bảng chỉnh độ đậm của lời (tự mở lời nếu đang ở màn hình bìa).
    private func showWeightPanel() {
        guard weightPanel == nil else { return }
        if mode == .cover {
            lyricsView.resetFollow()
            loadLyrics()
            apply(mode: .lyrics, animated: true)
        } else if mode == .immersive {
            apply(mode: .lyrics, animated: true)
        }
        let panel = WeightPanel(index: AppSettings.lyricWeight)
        panel.onChange = { [weak self] index in
            AppSettings.lyricWeight = index
            self?.lyricsView.reloadStyle()
        }
        panel.onClose = { [weak self] in self?.hideWeightPanel() }
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 17),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -17),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -(view.safeAreaInsets.bottom + 24)),
            panel.heightAnchor.constraint(equalToConstant: 108)
        ])
        panel.alpha = 0
        panel.transform = CGAffineTransform(translationX: 0, y: 30)
        weightPanel = panel
        idleTimer?.invalidate()
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [], animations: {
            panel.alpha = 1
            panel.transform = .identity
        }, completion: nil)
    }

    private func hideWeightPanel() {
        guard let panel = weightPanel else { return }
        weightPanel = nil
        UIView.animate(withDuration: 0.25, animations: {
            panel.alpha = 0
            panel.transform = CGAffineTransform(translationX: 0, y: 30)
        }, completion: { _ in panel.removeFromSuperview() })
        scheduleIdle()
    }

    /// Chọn kiểu làm mờ phía dưới màn hình bìa: tự động theo ảnh bìa, luôn sáng hoặc luôn tối.
    private func blurTapped() {
        let sheet = UIAlertController(title: L("Làm mờ nền"), message: L("Áp dụng cho phần dưới màn hình đang phát khi chưa bật lời."), preferredStyle: .actionSheet)
        for option in [PlayerBlur.auto, .light, .dark] {
            let mark = AppSettings.playerBlur == option ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: mark + option.title, style: .default) { [weak self] _ in
                AppSettings.playerBlur = option
                self?.refreshBackdrop(animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
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
        nextButton.nudge(10)
        stage.nextBtn.nudge(10)
        PlayerEngine.shared.next()
    }

    @objc private func prevTapped() {
        Haptics.tap()
        prevButton.nudge(-10)
        stage.prevBtn.nudge(-10)
        PlayerEngine.shared.previous()
    }

    @objc private func shuffleTapped() {
        let engine = PlayerEngine.shared
        engine.setShuffle(!engine.shuffleOn)
        Toast.show(engine.shuffleOn ? L("Ngẫu nhiên: bật") : L("Ngẫu nhiên: tắt"))
    }

    @objc private func repeatTapped() {
        PlayerEngine.shared.cycleRepeat()
        switch PlayerEngine.shared.repeatMode {
        case .off: Toast.show(L("Lặp lại: tắt"))
        case .all: Toast.show(L("Lặp lại cả danh sách"))
        case .one: Toast.show(L("Lặp lại một bài"))
        }
    }

    private func sleepTapped() {
        let engine = PlayerEngine.shared
        var message: String? = nil
        if let end = engine.sleepEnd {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            message = Lf("Đang hẹn tắt lúc %@", f.string(from: end))
        }
        let sheet = UIAlertController(title: L("Hẹn giờ tắt nhạc"), message: message, preferredStyle: .actionSheet)
        for minutes in [15, 30, 45, 60] {
            sheet.addAction(UIAlertAction(title: Lf("%@ phút", minutes), style: .default) { _ in
                engine.setSleepTimer(minutes: minutes)
                Toast.show(Lf("Sẽ tắt nhạc sau %@ phút", minutes))
            })
        }
        if engine.sleepEnd != nil {
            sheet.addAction(UIAlertAction(title: L("Tắt hẹn giờ"), style: .destructive) { _ in
                engine.setSleepTimer(minutes: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = moreGlass
            popover.sourceRect = moreGlass.bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    @objc private func queueTapped() {
        let nav = GlassNavigationController(rootViewController: QueueViewController())
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
