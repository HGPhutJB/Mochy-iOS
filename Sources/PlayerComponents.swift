import UIKit
import AVFoundation

/// Gốc của màn hình đang phát: báo cho bộ điều khiển mỗi khi có chạm (để tính 5 giây không thao tác).
final class PlayerRootView: UIView {
    var onTouch: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit != nil, event?.type == .touches { onTouch?() }
        return hit
    }
}

/// Làm mờ tăng dần: trên cùng không mờ, càng xuống càng mờ đậm. Xếp chồng nhiều lớp mờ, mỗi lớp hiện dần
/// bằng một mặt nạ chuyển sắc nên độ mờ tăng liên tục, không có chỗ "dừng" hay dải màu phủ lên.
final class ProgressiveBlurView: UIView {
    private var effects: [UIVisualEffectView] = []
    private var masks: [CAGradientLayer] = []

    init(layers count: Int = 4) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        for i in 0..<count {
            let v = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            v.isUserInteractionEnabled = false
            let m = CAGradientLayer()
            m.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
            m.startPoint = CGPoint(x: 0.5, y: 0)
            m.endPoint = CGPoint(x: 0.5, y: 1)
            let start = Double(i) * 0.15
            m.locations = [NSNumber(value: start), NSNumber(value: start + 0.45)]
            v.layer.mask = m
            addSubview(v)
            effects.append(v)
            masks.append(m)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    private var full = false

    /// Phủ kín: chỉ dùng một lớp mờ đậm đều từ trên xuống (nhẹ hơn nhiều so với bốn lớp), đổi mượt từ dải đáy.
    func setFull(_ value: Bool, animated: Bool) {
        guard value != full else { return }
        full = value
        for (i, m) in masks.enumerated() {
            let start = Double(i) * 0.15
            let to: [NSNumber] = value ? [0, 0.001] : [NSNumber(value: start), NSNumber(value: start + 0.45)]
            if animated {
                let anim = CABasicAnimation(keyPath: "locations")
                anim.fromValue = (m.presentation() ?? m).locations
                anim.toValue = to
                anim.duration = 0.5
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                m.add(anim, forKey: "full")
            }
            m.locations = to
            if i > 0 { effects[i].isHidden = value }
        }
    }

    /// Sáng cho bìa sáng, tối cho bìa tối.
    func setLight(_ light: Bool, animated: Bool) {
        let effect = UIBlurEffect(style: light ? .light : .dark)
        let change = { self.effects.forEach { $0.effect = effect } }
        if animated { UIView.animate(withDuration: 0.5, animations: change) } else { change() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, v) in effects.enumerated() {
            v.frame = bounds
            masks[i].frame = v.bounds
        }
    }
}

/// Bảng chỉnh độ đậm nhạt của lời: kéo thanh trượt, lời đổi ngay theo bảy mức.
final class WeightPanel: UIView {
    var onChange: ((Int) -> Void)?
    var onClose: (() -> Void)?
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let small = UILabel()
    private let big = UILabel()
    private let done = UIButton(type: .system)
    private var index: Int

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        layer.cornerRadius = 22
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.2).cgColor
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)
        titleLabel.text = L("Độ đậm lời")
        titleLabel.font = RoundedFont.font(16, index: 5)
        titleLabel.textColor = .white
        valueLabel.text = RoundedFont.titles[index]
        valueLabel.font = RoundedFont.font(13, index: 3)
        valueLabel.textColor = UIColor(white: 1, alpha: 0.6)
        done.setTitle(L("Xong"), for: .normal)
        done.titleLabel?.font = RoundedFont.font(16, index: 5)
        done.setTitleColor(Theme.accent, for: .normal)
        done.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        small.text = "Aa"
        small.font = RoundedFont.font(15, index: 0)
        big.text = "Aa"
        big.font = RoundedFont.font(24, index: 6)
        small.textColor = .white
        big.textColor = .white
        slider.minimumValue = 0
        slider.maximumValue = 6
        slider.value = Float(index)
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.3)
        slider.addTarget(self, action: #selector(changed), for: .valueChanged)
        slider.addTarget(self, action: #selector(snap), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        [titleLabel, valueLabel, done, small, slider, big].forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        titleLabel.frame = CGRect(x: 20, y: 14, width: w - 120, height: 22)
        done.frame = CGRect(x: w - 20 - 60, y: 10, width: 60, height: 30)
        valueLabel.frame = CGRect(x: 20, y: 38, width: w - 40, height: 18)
        small.frame = CGRect(x: 20, y: 66, width: 30, height: 28)
        big.frame = CGRect(x: w - 20 - 34, y: 62, width: 34, height: 34)
        slider.frame = CGRect(x: 56, y: 66, width: w - 56 - 60, height: 28)
    }

    @objc private func changed() {
        let i = min(6, max(0, Int(slider.value.rounded())))
        guard i != index else { return }
        index = i
        valueLabel.text = RoundedFont.titles[i]
        Haptics.tap()
        onChange?(i)
    }

    @objc private func snap() {
        slider.setValue(Float(index), animated: true)
    }

    @objc private func closeTapped() { onClose?() }
}

/// Nút/nhãn kính mờ (nền làm mờ + viền sáng mảnh), bo tròn theo chiều cao.
final class GlassView: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let tintLayer = UIView()
    let iconView = UIImageView()
    let titleLabel = UILabel()
    var onTap: (() -> Void)?

    init(tint: UIColor?) {
        super.init(frame: .zero)
        clipsToBounds = true
        blur.isUserInteractionEnabled = false
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)
        tintLayer.isUserInteractionEnabled = false
        tintLayer.frame = bounds
        tintLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintLayer.backgroundColor = tint ?? UIColor(white: 1, alpha: 0.12)
        addSubview(tintLayer)
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.28).cgColor
        iconView.contentMode = .center
        iconView.tintColor = .white
        iconView.isUserInteractionEnabled = false
        iconView.frame = bounds
        iconView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(iconView)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.isUserInteractionEnabled = false
        titleLabel.frame = bounds
        titleLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(titleLabel)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    private func dip(_ on: Bool) {
        UIView.animate(withDuration: on ? 0.2 : 0.5, delay: 0, usingSpringWithDamping: on ? 0.8 : 0.5, initialSpringVelocity: on ? 0 : 5,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.transform = on ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
        }, completion: nil)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesBegan(touches, with: event); dip(true) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesEnded(touches, with: event); dip(false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesCancelled(touches, with: event); dip(false) }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func setTint(_ color: UIColor) {
        UIView.animate(withDuration: 0.4) { self.tintLayer.backgroundColor = color }
    }

    @objc private func tapped() {
        Haptics.tap()
        UIView.animate(withDuration: 0.1, animations: { self.alpha = 0.6 }, completion: { _ in
            UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        })
        onTap?()
    }
}

/// Nhãn chạy ngang khi tên dài, mờ hai đầu.
final class MarqueeLabel: UIView {
    let label = UILabel()
    /// Bản sao nối đuôi để chữ chạy một chiều, vòng lại liền mạch (không chạy qua chạy lại).
    private let twin = UILabel()
    private let scroller = UIView()
    private var runningKey = ""
    private let mask2 = CAGradientLayer()
    private let gap: CGFloat = 40

    var text: String? {
        didSet {
            label.text = text
            twin.text = text
            label.sizeToFit()
            runningKey = ""
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(scroller)
        scroller.addSubview(label)
        scroller.addSubview(twin)
        twin.isHidden = true
        mask2.startPoint = CGPoint(x: 0, y: 0.5)
        mask2.endPoint = CGPoint(x: 1, y: 0.5)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        twin.font = label.font
        twin.textColor = label.textColor
        label.sizeToFit()
        let key = "\(label.text ?? "")-\(Int(bounds.width))-\(label.font.pointSize)"
        if key == runningKey { return }
        runningKey = key
        scroller.layer.removeAllAnimations()
        let h = label.bounds.height
        let w = label.bounds.width
        scroller.frame = CGRect(x: 0, y: (bounds.height - h) / 2, width: w * 2 + gap, height: h)
        label.frame = CGRect(x: 0, y: 0, width: w, height: h)
        twin.frame = CGRect(x: w + gap, y: 0, width: w, height: h)
        if w - bounds.width > 1 {
            twin.isHidden = false
            mask2.frame = bounds
            mask2.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
            let edge = min(0.14, 22 / max(1, bounds.width))
            mask2.locations = [0, NSNumber(value: Double(1 - edge)), 1]
            layer.mask = mask2
            // Đứng yên ~2s rồi chạy một chiều sang trái; hết một vòng thì bản sao đã vào đúng vị trí nên lặp liền mạch.
            let distance = w + gap
            let run = Double(distance) / 32
            let pause = 2.0
            let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
            anim.values = [0, 0, -distance]
            anim.keyTimes = [0, NSNumber(value: pause / (pause + run)), 1]
            anim.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear)]
            anim.duration = pause + run
            anim.repeatCount = .infinity
            scroller.layer.add(anim, forKey: "marquee")
        } else {
            twin.isHidden = true
            layer.mask = nil
        }
    }
}

/// Thanh tiến trình dày, bo tròn, kéo để tua.
final class ProgressBar: UIView {
    private let track = UIView()
    private let fill = UIView()
    private var dragging = false
    var value: Double = 0 { didSet { if !dragging { setNeedsLayout() } } }
    var onScrub: ((Double, Bool) -> Void)?
    private let barHeight: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = UIColor(white: 1, alpha: 0.28)
        fill.backgroundColor = .white
        addSubview(track)
        addSubview(fill)
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = dragging ? barHeight * 1.5 : barHeight
        let y = (bounds.height - h) / 2
        track.frame = CGRect(x: 0, y: y, width: bounds.width, height: h)
        track.layer.cornerRadius = h / 2
        fill.frame = CGRect(x: 0, y: y, width: bounds.width * CGFloat(min(1, max(0, value))), height: h)
        fill.layer.cornerRadius = h / 2
    }

    private func position(_ touches: Set<UITouch>) -> Double {
        guard let t = touches.first, bounds.width > 0 else { return value }
        return Double(min(1, max(0, t.location(in: self).x / bounds.width)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragging = true
        value = position(touches)
        UIView.animate(withDuration: 0.15) { self.layoutIfNeeded() }
        setNeedsLayout()
        onScrub?(value, false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        value = position(touches)
        setNeedsLayout()
        layoutIfNeeded()
        onScrub?(value, false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        value = position(touches)
        dragging = false
        UIView.animate(withDuration: 0.2) { self.setNeedsLayout(); self.layoutIfNeeded() }
        onScrub?(value, true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragging = false
        setNeedsLayout()
        onScrub?(value, true)
    }

    var isDragging: Bool { return dragging }

    /// Màu thanh: phần đã chạy đặc, phần còn lại cùng màu nhưng mờ.
    func setTone(_ color: UIColor) {
        UIView.animate(withDuration: 0.5) {
            self.fill.backgroundColor = color
            self.track.backgroundColor = color.withAlphaComponent(0.28)
        }
    }
}

/// Hàng thông tin bài: (ảnh nhỏ) + tên chạy ngang + huy hiệu E + nghệ sĩ + nút đã thích tròn.
final class InfoRow: UIView {
    let thumb = UIImageView()
    let titleLabel = MarqueeLabel()
    let artistLabel = UILabel()
    let explicitBadge = UILabel()

    /// Màu chữ theo nền: nền sáng dùng chữ tối.
    func setInk(dark: Bool) {
        titleLabel.label.textColor = dark ? UIColor(white: 0.06, alpha: 1) : .white
        artistLabel.textColor = dark ? UIColor(white: 0.06, alpha: 0.6) : UIColor(white: 1, alpha: 0.6)
    }
    let checkButton = UIButton(type: .custom)
    let translateButton = UIButton(type: .custom)
    private let textColumn = UIView()
    private var artistLeading: NSLayoutConstraint?

    init(withThumb: Bool, compact: Bool = false, translate: Bool = false) {
        super.init(frame: .zero)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = compact ? 9 : 14
        thumb.backgroundColor = UIColor(white: 1, alpha: 0.1)
        thumb.isHidden = !withThumb
        addSubview(thumb)

        textColumn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textColumn)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.label.font = RoundedFont.font(compact ? 18 : 25, index: 5)
        titleLabel.label.textColor = .white
        textColumn.addSubview(titleLabel)

        explicitBadge.translatesAutoresizingMaskIntoConstraints = false
        explicitBadge.text = "E"
        explicitBadge.font = UIFont.systemFont(ofSize: 11, weight: .heavy)
        explicitBadge.textColor = UIColor(white: 0, alpha: 0.7)
        explicitBadge.textAlignment = .center
        explicitBadge.backgroundColor = UIColor(white: 1, alpha: 0.6)
        explicitBadge.layer.cornerRadius = 3.5
        explicitBadge.clipsToBounds = true
        textColumn.addSubview(explicitBadge)

        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.font = RoundedFont.font(compact ? 15 : 20, index: 4)
        artistLabel.textColor = UIColor(white: 1, alpha: 0.6)
        textColumn.addSubview(artistLabel)

        checkButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkButton)
        translateButton.translatesAutoresizingMaskIntoConstraints = false
        translateButton.isHidden = !translate
        addSubview(translateButton)

        let thumbSize: CGFloat = compact ? 58 : 88
        var constraints: [NSLayoutConstraint] = [
            checkButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            checkButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkButton.widthAnchor.constraint(equalToConstant: 38),
            checkButton.heightAnchor.constraint(equalToConstant: 38),
            textColumn.trailingAnchor.constraint(equalTo: translate ? translateButton.leadingAnchor : checkButton.leadingAnchor, constant: -14),
            textColumn.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: textColumn.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: textColumn.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: textColumn.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: compact ? 23 : 31),
            explicitBadge.leadingAnchor.constraint(equalTo: textColumn.leadingAnchor),
            explicitBadge.centerYAnchor.constraint(equalTo: artistLabel.centerYAnchor),
            explicitBadge.widthAnchor.constraint(equalToConstant: 17),
            explicitBadge.heightAnchor.constraint(equalToConstant: 17),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            artistLabel.trailingAnchor.constraint(equalTo: textColumn.trailingAnchor),
            artistLabel.bottomAnchor.constraint(equalTo: textColumn.bottomAnchor)
        ]
        let leading = artistLabel.leadingAnchor.constraint(equalTo: textColumn.leadingAnchor)
        artistLeading = leading
        constraints.append(leading)
        if withThumb {
            constraints += [
                thumb.leadingAnchor.constraint(equalTo: leadingAnchor),
                thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
                thumb.widthAnchor.constraint(equalToConstant: thumbSize),
                thumb.heightAnchor.constraint(equalToConstant: thumbSize),
                textColumn.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 16)
            ]
        } else {
            constraints.append(textColumn.leadingAnchor.constraint(equalTo: leadingAnchor))
        }
        if translate {
            constraints += [
                translateButton.trailingAnchor.constraint(equalTo: checkButton.leadingAnchor, constant: -10),
                translateButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                translateButton.widthAnchor.constraint(equalToConstant: 38),
                translateButton.heightAnchor.constraint(equalToConstant: 38)
            ]
            translateButton.setImage(InfoRow.translateImage(on: TranslateSettings.enabled), for: .normal)
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    /// Nút dịch: vòng tròn mờ chứa "文A"; đang bật thì đặc, chữ tối.
    static func translateImage(on: Bool) -> UIImage {
        let size = CGSize(width: 38, height: 38)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            (on ? UIColor.white : UIColor(white: 1, alpha: 0.22)).setFill()
            circle.fill()
            let ink = on ? UIColor(white: 0.08, alpha: 1) : UIColor.white
            let big = NSAttributedString(string: "文", attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: ink])
            let small = NSAttributedString(string: "A", attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .heavy), .foregroundColor: ink])
            big.draw(at: CGPoint(x: 7, y: 7))
            small.draw(at: CGPoint(x: 22, y: 17))
        }
    }

    func set(title: String, artist: String, explicit: Bool, liked: Bool) {
        if titleLabel.text != title { titleLabel.text = title }
        artistLabel.text = artist
        explicitBadge.isHidden = !explicit
        artistLeading?.constant = explicit ? 23 : 0
        let changed = lastLiked != nil && lastLiked != liked
        lastLiked = liked
        if changed && window != nil {
            // Dấu cộng ↔ trái tim: đổi hình mờ chéo kèm cú nảy.
            UIView.transition(with: checkButton, duration: 0.22, options: [.transitionCrossDissolve, .allowUserInteraction], animations: {
                self.checkButton.setImage(InfoRow.checkImage(liked: liked), for: .normal)
            }, completion: nil)
            checkButton.imageView?.transform = CGAffineTransform(scaleX: liked ? 0.4 : 1.3, y: liked ? 0.4 : 1.3)
            UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.42, initialSpringVelocity: 6,
                           options: [.allowUserInteraction], animations: { self.checkButton.imageView?.transform = .identity }, completion: nil)
        } else {
            checkButton.setImage(InfoRow.checkImage(liked: liked), for: .normal)
        }
    }

    private var lastLiked: Bool?

    static func checkImage(liked: Bool) -> UIImage {
        let size = CGSize(width: 38, height: 38)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            let heart = HeartShape.path(in: CGRect(x: 8, y: 8.5, width: 22, height: 22))
            if liked {
                Theme.accent.setFill()
                circle.fill()
                UIColor.white.setFill()
                heart.fill()
            } else {
                UIColor(white: 1, alpha: 0.22).setFill()
                circle.fill()
                UIColor.white.setStroke()
                heart.lineWidth = 2.2
                heart.lineJoinStyle = .round
                heart.stroke()
            }
        }
    }
}

/// Video MV phát không tiếng, bám theo vị trí của nhạc; chưa sẵn sàng hoặc lỗi thì để lộ ảnh bìa phía sau.
final class VideoBackdrop {
    let layer = AVPlayerLayer()
    private var player: AVPlayer?
    private var readyObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private(set) var key: String?
    var onReadyChanged: ((Bool) -> Void)?
    private(set) var looping = false
    private var endObserver: NSObjectProtocol?

    init() {
        layer.videoGravity = .resizeAspectFill
    }

    /// loop = true: clip ngắn lặp mãi (Canvas), không bám theo vị trí nhạc.
    func load(url: URL, userAgent: String, key: String, position: Double, loop: Bool = false) {
        stop()
        self.key = key
        looping = loop
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent]])
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.allowsExternalPlayback = false
        p.actionAtItemEnd = .pause
        player = p
        layer.player = p
        readyObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] l, _ in
            DispatchQueue.main.async { self?.onReadyChanged?(l.isReadyForDisplay) }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            if it.status == .failed { DispatchQueue.main.async { self?.onReadyChanged?(false) } }
        }
        if loop {
            p.actionAtItemEnd = .none
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak p] _ in
                p?.seek(to: .zero)
                p?.play()
            }
            p.play()
        } else {
            p.seek(to: CMTime(seconds: max(0, position), preferredTimescale: 600))
        }
    }

    func stop() {
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        looping = false
        readyObservation = nil
        statusObservation = nil
        player?.pause()
        layer.player = nil
        player = nil
        key = nil
        onReadyChanged?(false)
    }

    func pause() { player?.pause() }

    /// Gọi theo thời gian của nhạc; kéo video về đúng nhịp nếu lệch quá 0,8 giây.
    func sync(position: Double, playing: Bool) {
        guard let p = player else { return }
        guard playing else { p.pause(); return }
        if looping { if p.rate == 0 { p.play() }; return }
        let drift = p.currentTime().seconds - position
        if !drift.isFinite || abs(drift) > 0.8 {
            p.seek(to: CMTime(seconds: max(0, position), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if p.rate == 0 { p.play() }
    }
}

/// Nút điều khiển kiểu bộ phát của iOS: chạm thì hiện vòng sáng tròn mờ sau icon (nở ra bằng lò xo) và icon thu nhẹ,
/// nhả tay thì vòng sáng tan dần; đổi icon phát/tạm dừng có chuyển cảnh mượt, tua có cú đẩy theo hướng.
final class ControlButton: UIButton {
    private let bubble = UIView()

    private func prepareBubble() {
        if bubble.superview != nil { return }
        bubble.isUserInteractionEnabled = false
        bubble.backgroundColor = UIColor(white: 1, alpha: 0.22)
        bubble.alpha = 0
        insertSubview(bubble, at: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        prepareBubble()
        let d = min(bounds.width, bounds.height)
        let t = bubble.transform
        bubble.transform = .identity
        bubble.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        bubble.center = CGPoint(x: bounds.midX, y: bounds.midY)
        bubble.layer.cornerRadius = d / 2
        bubble.transform = t
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            prepareBubble()
            let on = isHighlighted
            if on {
                bubble.layer.removeAllAnimations()
                bubble.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: { self.bubble.alpha = 1 }, completion: nil)
                UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5,
                               options: [.allowUserInteraction, .beginFromCurrentState], animations: { self.bubble.transform = .identity }, completion: nil)
            } else {
                UIView.animate(withDuration: 0.38, delay: 0.05, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: { self.bubble.alpha = 0 }, completion: nil)
            }
            UIView.animate(withDuration: on ? 0.22 : 0.5, delay: 0, usingSpringWithDamping: on ? 0.8 : 0.5, initialSpringVelocity: on ? 0 : 6,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.imageView?.transform = on ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity
            }, completion: nil)
        }
    }

    /// Đổi icon bằng chuyển cảnh mờ + nảy (phát ↔ tạm dừng).
    func setImageAnimated(_ image: UIImage) {
        if currentImage === image { return }
        guard window != nil else { setImage(image, for: .normal); return }
        UIView.transition(with: self, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction], animations: {
            self.setImage(image, for: .normal)
        }, completion: nil)
        imageView?.transform = CGAffineTransform(scaleX: 0.78, y: 0.78)
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 4,
                       options: [.allowUserInteraction], animations: { self.imageView?.transform = .identity }, completion: nil)
    }

    /// Cú đẩy icon theo hướng (tua tới +, tua lui −) rồi bật lại.
    func nudge(_ dx: CGFloat) {
        imageView?.transform = CGAffineTransform(translationX: dx, y: 0)
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 5,
                       options: [.allowUserInteraction], animations: { self.imageView?.transform = .identity }, completion: nil)
    }
}
