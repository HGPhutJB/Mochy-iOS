import UIKit

/// Thanh phát nhỏ nổi phía trên thanh tab: ảnh bìa, tên bài, nút phát/tạm dừng và bài kế tiếp. Chạm hoặc vuốt lên để mở màn hình đang phát.
final class MiniPlayerView: UIView {
    static let height: CGFloat = 62

    var onTap: (() -> Void)?

    /// Ảnh bìa nhỏ (điểm xuất phát/kết thúc của hiệu ứng bay).
    var artImageView: UIImageView { return art }

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: Theme.blurStyle))
    private let art = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let playButton = ControlButton(type: .custom)
    private let nextButton = ControlButton(type: .custom)
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var shownVideoId: String?
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Theme.isDark ? 0.45 : 0.16
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 5)

        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.clipsToBounds = true
        blur.layer.cornerRadius = Mat.active ? 24 : 20
        addSubview(blur)
        if Mat.active {
            blur.effect = nil
            blur.backgroundColor = tonalColor()
            layer.shadowOpacity = Theme.isDark ? 0.3 : 0.12
            layer.shadowRadius = 10
            layer.shadowOffset = CGSize(width: 0, height: 3)
        }

        if !Mat.active {
            // Viên thuốc kính như thanh tab: viền sáng ở mép trên và mép dưới.
            rim.colors = [UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 1, alpha: 0.10).cgColor,
                          UIColor(white: 1, alpha: 0.10).cgColor, UIColor(white: 1, alpha: 0.34).cgColor]
            rim.locations = [0, 0.3, 0.7, 1]
            rim.startPoint = CGPoint(x: 0.5, y: 0)
            rim.endPoint = CGPoint(x: 0.5, y: 1)
            rimMask.fillColor = UIColor.clear.cgColor
            rimMask.strokeColor = UIColor.black.cgColor
            rimMask.lineWidth = 1.2
            rim.mask = rimMask
            layer.addSublayer(rim)
        }

        art.translatesAutoresizingMaskIntoConstraints = false
        art.contentMode = .scaleAspectFill
        art.clipsToBounds = true
        art.layer.cornerRadius = 10
        art.backgroundColor = Theme.placeholder
        blur.contentView.addSubview(art)

        titleLabel.font = Theme.bold(15)
        titleLabel.textColor = Theme.primaryText
        artistLabel.font = Theme.regular(13)
        artistLabel.textColor = Theme.secondaryText
        let stack = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
        stack.axis = .vertical
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        for button in [playButton, nextButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = Theme.primaryText
            blur.contentView.addSubview(button)
        }
        nextButton.setImage(Icons.next(26), for: .normal)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.backgroundColor = Theme.chip
        progressFill.backgroundColor = Theme.accent
        blur.contentView.addSubview(progressTrack)
        progressTrack.addSubview(progressFill)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            art.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 10),
            art.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor),
            art.widthAnchor.constraint(equalToConstant: 42),
            art.heightAnchor.constraint(equalToConstant: 42),
            stack.leadingAnchor.constraint(equalTo: art.trailingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor),
            nextButton.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -10),
            nextButton.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 44),
            nextButton.heightAnchor.constraint(equalToConstant: 44),
            playButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -2),
            playButton.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            progressTrack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16),
            progressTrack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16),
            progressTrack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 2)
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(tapped))
        swipe.direction = .up
        addGestureRecognizer(swipe)

        NotificationCenter.default.addObserver(self, selector: #selector(timeChanged),
                                               name: .playerTimeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accentChanged), name: .accentChanged, object: nil)
    }

    /// Nền tonal Material 3: màu bề mặt pha một chút màu nhấn.
    private func tonalColor() -> UIColor {
        return Mat.mix(Theme.isDark ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.97, alpha: 1), Theme.accent, Theme.isDark ? 0.16 : 0.12)
    }

    @objc private func accentChanged() {
        UIView.animate(withDuration: 0.5) {
            self.progressFill.backgroundColor = Theme.accent
            if Mat.active { self.blur.backgroundColor = self.tonalColor() }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius: CGFloat = Mat.active ? 24 : bounds.height / 2
        blur.layer.cornerRadius = radius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
        rim.frame = bounds
        rimMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.6, dy: 0.6), cornerRadius: radius).cgPath
        updateProgress()
    }

    @objc private func tapped() { onTap?() }

    @objc private func playTapped() {
        Haptics.tap()
        PlayerEngine.shared.togglePlayPause()
    }

    @objc private func nextTapped() {
        Haptics.tap()
        nextButton.nudge(8)
        PlayerEngine.shared.next()
    }

    @objc private func timeChanged() {
        updateProgress()
    }

    private func updateProgress() {
        let engine = PlayerEngine.shared
        let fraction = engine.duration > 0 ? CGFloat(min(1, max(0, engine.currentTime / engine.duration))) : 0
        progressFill.frame = CGRect(x: 0, y: 0, width: progressTrack.bounds.width * fraction, height: 2)
    }

    func update() {
        let engine = PlayerEngine.shared
        guard let song = engine.currentSong else { return }
        titleLabel.text = song.title
        artistLabel.text = engine.isLoading ? L("Đang tải…") : song.artist
        let icon = engine.isPlaying ? Icons.pause(26) : Icons.play(26)
        playButton.setImageAnimated(icon)
        if shownVideoId != song.videoId {
            shownVideoId = song.videoId
            art.image = nil
        }
        if let image = engine.artwork {
            if art.image !== image {
                UIView.transition(with: art, duration: 0.3, options: .transitionCrossDissolve, animations: {
                    self.art.image = image
                }, completion: nil)
            }
            if let tone = image.songTone() {
                UIView.animate(withDuration: 0.4) { self.progressFill.backgroundColor = tone }
            }
        }
        updateProgress()
    }
}
