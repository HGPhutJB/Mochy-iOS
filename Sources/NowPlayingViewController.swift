import UIKit
import MediaPlayer

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
    static let dimTag = 9901
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
            let fromView = transitionContext.viewController(forKey: .from)?.view
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
            flying.backgroundColor = Theme.placeholder
            flying.frame = start
            flying.layer.cornerRadius = 10
            container.addSubview(flying)
            realArt.alpha = 0
            miniArt?.alpha = 0

            // Màn hình phía sau mờ đi, bo góc và lùi lại.
            let dim = UIView(frame: fromView?.bounds ?? container.bounds)
            dim.tag = NowPlayingAnimator.dimTag
            dim.backgroundColor = UIColor.black
            dim.alpha = 0
            dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            fromView?.addSubview(dim)
            fromView?.clipsToBounds = true
            fromView?.window?.backgroundColor = UIColor.black

            toView.transform = CGAffineTransform(translationX: 0, y: container.bounds.height)
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0,
                           options: [.curveEaseOut], animations: {
                toView.transform = CGAffineTransform.identity
                flying.frame = target
                flying.layer.cornerRadius = 14
                dim.alpha = 0.35
                fromView?.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                fromView?.layer.cornerRadius = 14
            }, completion: { _ in
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
            let toView = transitionContext.viewController(forKey: .to)?.view
            let realArt = fromVC.artImageView
            let start = realArt.superview?.convert(realArt.frame, to: container) ?? container.bounds
            let end = miniArtFrame(in: container)

            // Ảnh bìa thu nhỏ bay về thanh phát nhỏ.
            let flying = UIImageView(image: realArt.image ?? miniArt?.image)
            flying.contentMode = .scaleAspectFill
            flying.clipsToBounds = true
            flying.backgroundColor = Theme.placeholder
            flying.frame = start
            flying.layer.cornerRadius = 14
            container.addSubview(flying)
            realArt.alpha = 0
            miniArt?.alpha = 0
            let dim = toView?.viewWithTag(NowPlayingAnimator.dimTag)

            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0,
                           options: [.curveEaseInOut], animations: {
                fromView.transform = CGAffineTransform(translationX: 0, y: container.bounds.height)
                flying.frame = end
                flying.layer.cornerRadius = 10
                dim?.alpha = 0
                toView?.transform = CGAffineTransform.identity
                toView?.layer.cornerRadius = 0
            }, completion: { _ in
                flying.removeFromSuperview()
                miniArt?.alpha = 1
                dim?.removeFromSuperview()
                toView?.clipsToBounds = false
                toView?.window?.backgroundColor = Theme.background
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            })
        }
    }
}

/// Màn hình đang phát: bìa lớn (thu nhỏ khi tạm dừng), nền lấy màu từ bìa, huy hiệu định dạng, thanh tiến trình,
/// điều khiển, âm lượng, ngẫu nhiên / lặp / hẹn giờ / tải xuống / hàng đợi. Kéo xuống để đóng.
final class NowPlayingViewController: UIViewController {
    let transition = NowPlayingTransition()

    private let tintView = UIView()
    private let fadeView = GradientView()
    private let grabber = UIView()
    private let grabZone = UIView()
    private let artArea = UIView()
    private var lastArtScale: CGFloat = 0
    private let artView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let badgeLabel = UILabel()
    private let heartButton = PressableButton(type: .custom)
    private let moreButton = PressableButton(type: .custom)
    private let slider = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let prevButton = PressableButton(type: .custom)
    private let playButton = PressableButton(type: .custom)
    private let nextButton = PressableButton(type: .custom)
    private let volumeView = MPVolumeView(frame: .zero)
    private let shuffleButton = PressableButton(type: .custom)
    private let repeatButton = PressableButton(type: .custom)
    private let sleepButton = PressableButton(type: .custom)
    private let downloadButton = PressableButton(type: .custom)
    private let queueButton = PressableButton(type: .custom)

    /// Ảnh bìa lớn (dùng cho hiệu ứng bay giữa thanh phát nhỏ và màn hình đang phát).
    var artImageView: UIImageView { return artView }

    private var isScrubbing = false
    private var shownVideoId: String?
    private var shownArtwork: UIImage?
    private var dragStartTransform = CGAffineTransform.identity

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.statusBarStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        view.layer.cornerRadius = 22
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        buildLayout()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(stateChanged), name: .playerStateChanged, object: nil)
        center.addObserver(self, selector: #selector(timeChanged), name: .playerTimeChanged, object: nil)
        center.addObserver(self, selector: #selector(libraryChanged), name: .libraryChanged, object: nil)
        center.addObserver(self, selector: #selector(libraryChanged), name: .downloadChanged, object: nil)
        stateChanged()
    }

    // MARK: - Dựng giao diện

    private func style(_ button: UIButton, _ image: UIImage, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.tintColor = Theme.primaryText
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func buildLayout() {
        tintView.frame = view.bounds
        tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintView.backgroundColor = Theme.background
        view.addSubview(tintView)

        fadeView.frame = view.bounds
        fadeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fadeView.isUserInteractionEnabled = false
        fadeView.gradientLayer.colors = [UIColor.clear.cgColor, Theme.background.cgColor]
        fadeView.gradientLayer.locations = [0.0, 0.8]
        view.addSubview(fadeView)

        grabZone.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grabZone)
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = Theme.secondaryText.withAlphaComponent(0.6)
        grabber.layer.cornerRadius = 2.5
        grabZone.addSubview(grabber)

        artArea.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(artArea)
        artView.translatesAutoresizingMaskIntoConstraints = false
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        artView.layer.cornerRadius = 14
        artView.backgroundColor = Theme.placeholder
        // Ảnh có kích thước gốc lớn: không để nó "đẩy" bố cục, nếu không tên bài/nghệ sĩ bị chồng lên nhau.
        artView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        artView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        artView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        artView.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        artArea.addSubview(artView)

        titleLabel.font = Theme.heavy(22)
        titleLabel.textColor = Theme.primaryText
        artistLabel.font = Theme.bold(17)
        artistLabel.textColor = Theme.secondaryText
        badgeLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        badgeLabel.textColor = Theme.secondaryText
        for label in [titleLabel, artistLabel, badgeLabel] {
            label.setContentCompressionResistancePriority(UILayoutPriority.required, for: .vertical)
        }
        badgeLabel.text = " "
        let textStack = UIStackView(arrangedSubviews: [titleLabel, artistLabel, badgeLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textStack)

        style(heartButton, Icons.heart(24, filled: false), action: #selector(heartTapped))
        style(moreButton, Icons.more(24), action: #selector(moreTapped))
        for b in [heartButton, moreButton] {
            b.backgroundColor = Theme.chip
            b.layer.cornerRadius = 19
            view.addSubview(b)
        }

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = Theme.primaryText
        slider.maximumTrackTintColor = Theme.chip
        slider.setThumbImage(NowPlayingViewController.thumbImage(), for: .normal)
        slider.addTarget(self, action: #selector(scrubBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(scrubEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(slider)

        for label in [elapsedLabel, remainingLabel] {
            label.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            label.textColor = Theme.secondaryText
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
        }
        remainingLabel.textAlignment = .right

        style(prevButton, Icons.previous(34), action: #selector(prevTapped))
        style(playButton, Icons.play(48), action: #selector(playTapped))
        style(nextButton, Icons.next(34), action: #selector(nextTapped))
        let controls = UIStackView(arrangedSubviews: [prevButton, playButton, nextButton])
        controls.axis = .horizontal
        controls.distribution = .equalSpacing
        controls.alignment = .center
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        volumeView.translatesAutoresizingMaskIntoConstraints = false
        volumeView.tintColor = Theme.primaryText
        view.addSubview(volumeView)

        style(shuffleButton, Icons.shuffle(24), action: #selector(shuffleTapped))
        style(repeatButton, Icons.repeatAll(24), action: #selector(repeatTapped))
        style(sleepButton, Icons.timer(24), action: #selector(sleepTapped))
        style(downloadButton, Icons.download(24), action: #selector(downloadTapped))
        style(queueButton, Icons.queue(24), action: #selector(queueTapped))
        let bottomRow = UIStackView(arrangedSubviews: [shuffleButton, repeatButton, sleepButton, downloadButton, queueButton])
        bottomRow.axis = .horizontal
        bottomRow.distribution = .fillEqually
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomRow)

        let guide = view.safeAreaLayoutGuide
        let side: CGFloat = 28
        let fill = artView.widthAnchor.constraint(equalTo: artArea.widthAnchor, constant: -side * 2)
        fill.priority = UILayoutPriority(750)
        NSLayoutConstraint.activate([
            fill,
            grabZone.topAnchor.constraint(equalTo: guide.topAnchor),
            grabZone.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grabZone.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grabZone.heightAnchor.constraint(equalToConstant: 28),
            grabber.centerXAnchor.constraint(equalTo: grabZone.centerXAnchor),
            grabber.centerYAnchor.constraint(equalTo: grabZone.centerYAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 40),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            artArea.topAnchor.constraint(equalTo: grabZone.bottomAnchor, constant: 4),
            artArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            artArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            artArea.bottomAnchor.constraint(equalTo: textStack.topAnchor, constant: -10),

            artView.centerXAnchor.constraint(equalTo: artArea.centerXAnchor),
            artView.centerYAnchor.constraint(equalTo: artArea.centerYAnchor),
            artView.widthAnchor.constraint(equalTo: artView.heightAnchor),
            artView.widthAnchor.constraint(lessThanOrEqualTo: artArea.widthAnchor, constant: -side * 2),
            artView.heightAnchor.constraint(lessThanOrEqualTo: artArea.heightAnchor),
            artView.widthAnchor.constraint(lessThanOrEqualToConstant: 420),

            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            textStack.trailingAnchor.constraint(equalTo: heartButton.leadingAnchor, constant: -10),
            textStack.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -14),

            moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            moreButton.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 38),
            moreButton.heightAnchor.constraint(equalToConstant: 38),
            heartButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            heartButton.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            heartButton.widthAnchor.constraint(equalToConstant: 38),
            heartButton.heightAnchor.constraint(equalToConstant: 38),

            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side - 2),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(side - 2)),
            slider.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -30),
            elapsedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            elapsedLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 0),
            remainingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            remainingLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 0),

            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -48),
            controls.bottomAnchor.constraint(equalTo: volumeView.topAnchor, constant: -18),
            controls.heightAnchor.constraint(equalToConstant: 64),

            volumeView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            volumeView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            volumeView.heightAnchor.constraint(equalToConstant: 30),
            volumeView.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -8),

            bottomRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomRow.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
            bottomRow.heightAnchor.constraint(equalToConstant: 44)
        ])

        let panA = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let panB = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        grabZone.addGestureRecognizer(panA)
        artArea.addGestureRecognizer(panB)
    }

    private static func thumbImage() -> UIImage {
        let size = CGSize(width: 14, height: 14)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            Theme.primaryText.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
    }

    // MARK: - Cập nhật

    @objc private func stateChanged() {
        let engine = PlayerEngine.shared
        guard let song = engine.currentSong else {
            dismiss(animated: true, completion: nil)
            return
        }
        titleLabel.text = song.title
        artistLabel.text = song.artist
        playButton.setImage(engine.isPlaying ? Icons.pause(48) : Icons.play(48), for: .normal)

        if shownVideoId != song.videoId {
            shownVideoId = song.videoId
            shownArtwork = nil
            artView.image = nil
            titleLabel.pop()
        }
        if let image = engine.artwork, shownArtwork !== image {
            shownArtwork = image
            UIView.transition(with: artView, duration: 0.45, options: .transitionCrossDissolve, animations: {
                self.artView.image = image
            }, completion: nil)
            applyBackground(from: image)
        }

        // Bìa nhỏ lại khi đang phát (0.84) và nhỏ hơn nữa khi tạm dừng (0.72).
        let scale: CGFloat = engine.isPlaying || engine.isLoading ? 0.84 : 0.72
        if scale != lastArtScale {
            lastArtScale = scale
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.artView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }, completion: nil)
        }

        shuffleButton.tintColor = engine.shuffleOn ? Theme.accent : Theme.primaryText
        switch engine.repeatMode {
        case .off:
            repeatButton.setImage(Icons.repeatAll(24), for: .normal)
            repeatButton.tintColor = Theme.primaryText
        case .all:
            repeatButton.setImage(Icons.repeatAll(24), for: .normal)
            repeatButton.tintColor = Theme.accent
        case .one:
            repeatButton.setImage(Icons.repeatOne(24), for: .normal)
            repeatButton.tintColor = Theme.accent
        }
        sleepButton.tintColor = engine.sleepEnd != nil ? Theme.accent : Theme.primaryText
        libraryChanged()
        timeChanged()
    }

    @objc private func libraryChanged() {
        guard let song = PlayerEngine.shared.currentSong else { return }
        let liked = Library.shared.isLiked(song)
        heartButton.setImage(Icons.heart(24, filled: liked), for: .normal)
        heartButton.tintColor = liked ? Theme.accent : Theme.primaryText

        let manager = DownloadManager.shared
        var info = ""
        if let stream = PlayerEngine.shared.streamInfo {
            info = stream.badge
        } else if PlayerEngine.shared.isLocal {
            info = "Đã tải về · nghe offline"
        } else if PlayerEngine.shared.isLoading {
            info = "Đang lấy luồng nhạc…"
        }
        if let fraction = manager.progress[song.videoId] {
            downloadButton.setImage(Icons.close(24), for: .normal)
            downloadButton.tintColor = Theme.accent
            info = "Đang tải xuống \(Int(fraction * 100))%"
        } else if Library.shared.isDownloaded(song) {
            downloadButton.setImage(Icons.check(24), for: .normal)
            downloadButton.tintColor = Theme.accent
        } else {
            downloadButton.setImage(Icons.download(24), for: .normal)
            downloadButton.tintColor = Theme.primaryText
        }
        badgeLabel.text = info.isEmpty ? " " : info.uppercased()
    }

    @objc private func timeChanged() {
        let engine = PlayerEngine.shared
        if isScrubbing { return }
        let total = engine.duration
        slider.maximumValue = total > 0 ? Float(total) : 1
        slider.value = total > 0 ? Float(min(engine.currentTime, total)) : 0
        elapsedLabel.text = formatTime(engine.currentTime)
        remainingLabel.text = total > 0 ? "-" + formatTime(max(0, total - engine.currentTime)) : "-:--"
    }

    private func applyBackground(from image: UIImage) {
        guard let average = image.averageColor() else { return }
        let base: UIColor
        if Theme.isDark {
            base = average.mixed(with: UIColor.black, amount: 0.55)
        } else {
            base = average.mixed(with: UIColor.white, amount: 0.5)
        }
        UIView.animate(withDuration: 0.8) {
            self.tintView.backgroundColor = base
        }
    }

    // MARK: - Hành động

    @objc private func heartTapped() {
        guard let song = PlayerEngine.shared.currentSong else { return }
        Haptics.tap()
        Library.shared.toggleLike(song)
        heartButton.pop()
    }

    @objc private func moreTapped() {
        guard let song = PlayerEngine.shared.currentSong else { return }
        SongActions.present(for: song, from: self, sourceView: moreButton)
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

    @objc private func sleepTapped() {
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
            popover.sourceView = sleepButton
            popover.sourceRect = sleepButton.bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    @objc private func downloadTapped() {
        guard let song = PlayerEngine.shared.currentSong else { return }
        let manager = DownloadManager.shared
        if manager.isActive(song.videoId) {
            manager.cancel(song.videoId)
        } else if Library.shared.isDownloaded(song) {
            SongActions.present(for: song, from: self, sourceView: downloadButton)
        } else {
            manager.start(song)
            Toast.show("Đang tải xuống…")
        }
    }

    @objc private func queueTapped() {
        let nav = UINavigationController(rootViewController: QueueViewController())
        Theme.style(navigationBar: nav.navigationBar)
        present(nav, animated: true, completion: nil)
    }

    // MARK: - Thanh tiến trình

    @objc private func scrubBegan() {
        isScrubbing = true
    }

    @objc private func scrubChanged() {
        let total = Double(slider.maximumValue)
        elapsedLabel.text = formatTime(Double(slider.value))
        remainingLabel.text = "-" + formatTime(max(0, total - Double(slider.value)))
    }

    @objc private func scrubEnded() {
        isScrubbing = false
        PlayerEngine.shared.seek(to: Double(slider.value))
    }

    // MARK: - Kéo xuống để đóng

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = max(0, gesture.translation(in: view.superview ?? view.window).y)
        let height = max(1, view.bounds.height)
        let behind = presentingViewController?.view
        switch gesture.state {
        case .changed:
            view.transform = CGAffineTransform(translationX: 0, y: translation)
            let progress = min(1, translation / height)
            let scale = 0.94 + 0.06 * progress
            behind?.transform = CGAffineTransform(scaleX: scale, y: scale)
            behind?.viewWithTag(NowPlayingAnimator.dimTag)?.alpha = 0.35 * (1 - progress)
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view.superview ?? view.window).y
            if translation > height * 0.22 || velocity > 900 {
                // Bìa sẽ bay từ vị trí hiện tại về thanh phát nhỏ.
                dismiss(animated: true, completion: nil)
            } else {
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4,
                               options: [], animations: {
                    self.view.transform = CGAffineTransform.identity
                    behind?.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                    behind?.viewWithTag(NowPlayingAnimator.dimTag)?.alpha = 0.35
                }, completion: nil)
            }
        default:
            break
        }
    }
}
