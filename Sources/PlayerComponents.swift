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
        titleLabel.text = "Độ đậm lời"
        titleLabel.font = RoundedFont.font(16, index: 5)
        titleLabel.textColor = .white
        valueLabel.text = RoundedFont.titles[index]
        valueLabel.font = RoundedFont.font(13, index: 3)
        valueLabel.textColor = UIColor(white: 1, alpha: 0.6)
        done.setTitle("Xong", for: .normal)
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
    private var runningKey = ""
    private let mask2 = CAGradientLayer()

    var text: String? {
        didSet {
            label.text = text
            label.sizeToFit()
            runningKey = ""
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(label)
        mask2.startPoint = CGPoint(x: 0, y: 0.5)
        mask2.endPoint = CGPoint(x: 1, y: 0.5)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.sizeToFit()
        let key = "\(label.text ?? "")-\(Int(bounds.width))"
        if key == runningKey { return }
        runningKey = key
        label.layer.removeAllAnimations()
        label.frame = CGRect(x: 0, y: (bounds.height - label.bounds.height) / 2, width: label.bounds.width, height: label.bounds.height)
        let overflow = label.bounds.width - bounds.width
        if overflow > 1 {
            mask2.frame = bounds
            mask2.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
            let edge = min(0.12, 18 / max(1, bounds.width))
            mask2.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
            layer.mask = mask2
            let distance = overflow + 24
            UIView.animate(withDuration: Double(distance) / 28, delay: 1.5,
                           options: [.repeat, .autoreverse, .curveEaseInOut, .allowUserInteraction], animations: {
                self.label.frame.origin.x = -distance
            }, completion: nil)
        } else {
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
        checkButton.setImage(InfoRow.checkImage(liked: liked), for: .normal)
    }

    static func checkImage(liked: Bool) -> UIImage {
        let size = CGSize(width: 38, height: 38)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            if liked {
                Theme.accent.setFill()
                circle.fill()
                let tick = UIBezierPath()
                tick.move(to: CGPoint(x: 11, y: 19.5))
                tick.addLine(to: CGPoint(x: 16.5, y: 25))
                tick.addLine(to: CGPoint(x: 27, y: 13.5))
                UIColor.white.setStroke()
                tick.lineWidth = 3.4
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                tick.stroke()
            } else {
                UIColor(white: 1, alpha: 0.22).setFill()
                circle.fill()
                let plus = UIBezierPath()
                plus.move(to: CGPoint(x: 19, y: 11)); plus.addLine(to: CGPoint(x: 19, y: 27))
                plus.move(to: CGPoint(x: 11, y: 19)); plus.addLine(to: CGPoint(x: 27, y: 19))
                UIColor.white.setStroke()
                plus.lineWidth = 3.2
                plus.lineCapStyle = .round
                plus.stroke()
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
