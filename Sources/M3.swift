import UIKit

/// Material 3: màu, ô danh sách dạng thẻ bo góc, công tắc M3 và thanh trên kính mờ.
enum M3 {
    static var primary: UIColor { return Theme.accent }
    static var primaryContainer: UIColor { return Theme.accent.withAlphaComponent(Theme.isDark ? 0.24 : 0.14) }
    static var onSurface: UIColor { return Theme.primaryText }
    static var onSurfaceVariant: UIColor { return Theme.secondaryText }
    static var outline: UIColor { return Theme.isDark ? UIColor(white: 1, alpha: 0.46) : UIColor(white: 0, alpha: 0.46) }
    static var trackOff: UIColor { return Theme.isDark ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0, alpha: 0.07) }
    static var surfaceHigh: UIColor { return Theme.isDark ? UIColor(white: 0.16, alpha: 1) : UIColor.white }
    static var danger: UIColor {
        return Theme.isDark ? UIColor(red: 1.0, green: 0.49, blue: 0.55, alpha: 1) : UIColor(red: 0.85, green: 0.23, blue: 0.33, alpha: 1)
    }
    static var dangerButton: UIColor {
        return Theme.isDark ? UIColor(red: 0.90, green: 0.28, blue: 0.30, alpha: 1) : UIColor(red: 0.85, green: 0.19, blue: 0.29, alpha: 1)
    }
    static let cardRadius: CGFloat = 24
    static let sideInset: CGFloat = 16

    /// Tiêu đề nhóm kiểu M3 (chữ màu nhấn, nhỏ, đậm vừa).
    static func headerView(_ text: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.font = Theme.bold(14)
        label.textColor = M3.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: sideInset + 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(sideInset + 16)),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    static func footerView(_ text: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.font = Theme.regular(12.5)
        label.textColor = Theme.secondaryText
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: sideInset + 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(sideInset + 16)),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8)
        ])
        return container
    }

    static func footerHeight(_ text: String, width: CGFloat) -> CGFloat {
        let w = width - 2 * (sideInset + 16)
        let rect = (text as NSString).boundingRect(with: CGSize(width: w, height: 2000), options: .usesLineFragmentOrigin,
                                                    attributes: [.font: Theme.regular(12.5)], context: nil)
        return ceil(rect.height) + 20
    }

    static func chevronImage(_ s: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        let image = renderer.image { _ in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: s * 0.62, y: s * 0.2))
            p.addLine(to: CGPoint(x: s * 0.36, y: s * 0.5))
            p.addLine(to: CGPoint(x: s * 0.62, y: s * 0.8))
            p.lineWidth = s * 0.095
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            UIColor.black.setStroke()
            p.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

/// Ô danh sách kiểu M3: thẻ bo góc lớn ở đầu/cuối nhóm, vạch ngăn mảnh ở giữa.
final class M3Cell: UITableViewCell {
    enum Position { case single, top, middle, bottom }

    var position: Position = .single {
        didSet { applyShape() }
    }
    private let divider = UIView()

    override var frame: CGRect {
        get { return super.frame }
        set {
            var f = newValue
            f.origin.x += M3.sideInset
            f.size.width = max(0, f.size.width - 2 * M3.sideInset)
            super.frame = f
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        layer.masksToBounds = true
        divider.backgroundColor = Theme.separator
        addSubview(divider)
        applyShape()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyShape() {
        layer.cornerRadius = M3.cardRadius
        if #available(iOS 11.0, *) {
            switch position {
            case .single: layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            case .top: layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            case .bottom: layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            case .middle: layer.cornerRadius = 0
            }
        }
        divider.isHidden = (position == .single || position == .bottom)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = 1.0 / UIScreen.main.scale
        divider.frame = CGRect(x: 16, y: bounds.height - h, width: bounds.width - 32, height: h)
    }
}

/// Công tắc Material 3: rãnh bo tròn, nút tròn lớn lên khi bật (có dấu ✓) và nhún khi chạm.
final class M3Switch: UIControl {
    private let track = UIView()
    private let thumb = UIView()
    private let tick = UIImageView()
    private var pressed = false
    private(set) var isOnState = false

    var isOn: Bool {
        get { return isOnState }
        set { setOn(newValue, animated: false) }
    }

    override var intrinsicContentSize: CGSize { return CGSize(width: 52, height: 32) }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 52, height: 32))
        track.frame = bounds
        track.layer.cornerRadius = 16
        track.isUserInteractionEnabled = false
        addSubview(track)
        thumb.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        thumb.layer.cornerRadius = 14
        thumb.isUserInteractionEnabled = false
        addSubview(thumb)
        tick.image = Icons.check(14)
        tick.frame = CGRect(x: 7, y: 7, width: 14, height: 14)
        tick.contentMode = .scaleAspectFit
        thumb.addSubview(tick)
        apply()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setOn(_ on: Bool, animated: Bool) {
        isOnState = on
        if animated {
            UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.6,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: { self.apply() }, completion: nil)
        } else {
            apply()
        }
    }

    private func apply() {
        if isOnState {
            track.backgroundColor = M3.primary
            track.layer.borderWidth = 0
            thumb.backgroundColor = UIColor.white
            tick.tintColor = M3.primary
            tick.alpha = 1
        } else {
            track.backgroundColor = M3.trackOff
            track.layer.borderWidth = 2
            track.layer.borderColor = M3.outline.cgColor
            thumb.backgroundColor = M3.outline
            tick.alpha = 0
        }
        let scale: CGFloat = pressed ? 1.0 : (isOnState ? 24.0 / 28.0 : 16.0 / 28.0)
        thumb.center = CGPoint(x: isOnState ? 36 : 16, y: 16)
        thumb.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        pressed = true
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: { self.apply() }, completion: nil)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        pressed = false
        if let t = touch, bounds.insetBy(dx: -16, dy: -16).contains(t.location(in: self)) {
            isOnState = !isOnState
            sendActions(for: .valueChanged)
        }
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.6,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: { self.apply() }, completion: nil)
    }

    override func cancelTracking(with event: UIEvent?) {
        pressed = false
        UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: { self.apply() }, completion: nil)
    }
}

/// Thanh trên kính mờ: nền mờ nhạt dần xuống dưới, nút quay lại tròn bằng kính, tiêu đề ở giữa.
final class GlassTopBar: UIView {
    let titleLabel = UILabel()
    let backButton = UIControl()
    var onBack: (() -> Void)?
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: Theme.blurStyle))
    private let blurMask = CAGradientLayer()
    private let tint = CAGradientLayer()
    private let backBlur = UIVisualEffectView(effect: UIBlurEffect(style: Theme.blurStyle))
    private let chevron = UIImageView(image: M3.chevronImage(22))
    private let contentHeight: CGFloat = 56

    init(title: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        addSubview(blur)
        blurMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        blurMask.locations = [0, 0.62, 1]
        blur.layer.mask = blurMask
        layer.addSublayer(tint)
        refreshColors()

        titleLabel.text = title
        titleLabel.font = Theme.heavy(18)
        titleLabel.textColor = Theme.primaryText
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        backBlur.clipsToBounds = true
        backBlur.layer.cornerRadius = 22
        backBlur.layer.borderWidth = 0.5
        backBlur.layer.borderColor = UIColor(white: 1, alpha: 0.22).cgColor
        backBlur.isUserInteractionEnabled = false
        backButton.addSubview(backBlur)
        chevron.tintColor = Theme.primaryText
        chevron.contentMode = .center
        chevron.isUserInteractionEnabled = false
        backButton.addSubview(chevron)
        backButton.addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
        backButton.addTarget(self, action: #selector(up), for: [.touchUpOutside, .touchCancel, .touchDragExit])
        backButton.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addSubview(backButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var totalHeight: CGFloat { return safeAreaInsets.top + contentHeight + 18 }

    private func refreshColors() {
        let base = Theme.groupedBackground
        tint.colors = [base.withAlphaComponent(0.78).cgColor, base.withAlphaComponent(0.46).cgColor, base.withAlphaComponent(0).cgColor]
        tint.locations = [0, 0.6, 1]
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blurMask.frame = bounds
        tint.frame = bounds
        CATransaction.commit()
        let top = safeAreaInsets.top
        backButton.frame = CGRect(x: 16, y: top + 6, width: 44, height: 44)
        backBlur.frame = backButton.bounds
        chevron.frame = backButton.bounds
        titleLabel.frame = CGRect(x: 72, y: top + 6, width: bounds.width - 144, height: 44)
    }

    @objc private func down() {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.backButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }, completion: nil)
    }

    @objc private func up() {
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.backButton.transform = CGAffineTransform.identity
        }, completion: nil)
    }

    @objc private func tapped() {
        up()
        onBack?()
    }

    /// Chỉ nhận chạm ở nút quay lại; phần còn lại của thanh để cuộn xuyên qua.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === backButton || hit?.isDescendant(of: backButton) == true { return backButton }
        return nil
    }
}
