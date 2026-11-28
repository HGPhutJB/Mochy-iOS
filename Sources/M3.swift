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
        super.selectedBackgroundView = UIView()   // trong suốt: không để hệ thống vẽ nền chữ nhật
        press.alpha = 0
        press.isUserInteractionEnabled = false
        insertSubview(press, at: 0)
        divider.backgroundColor = Theme.separator
        addSubview(divider)
        applyShape()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var card: MaterialCardView?
    private var lastTouch = CGPoint.zero

    /// Kiểu Material 3: mỗi hàng là một thẻ riêng (góc lớn ở đầu/cuối nhóm, góc nhỏ ở giữa), chạm thì nhún bo tròn + ripple.
    private func applyMaterial() {
        let c: MaterialCardView
        if let existing = card { c = existing } else {
            c = MaterialCardView()
            insertSubview(c, at: 0)
            card = c
        }
        c.isHidden = false
        layer.masksToBounds = false
        layer.cornerRadius = 0
        backgroundColor = .clear
        press.isHidden = true
        divider.isHidden = true
        let big: CGFloat = 24, small: CGFloat = 6
        switch position {
        case .single: c.topRadius = big; c.bottomRadius = big
        case .top: c.topRadius = big; c.bottomRadius = small
        case .middle: c.topRadius = small; c.bottomRadius = small
        case .bottom: c.topRadius = small; c.bottomRadius = big
        }
        c.fillColor = Theme.cellBackground
        c.frame = bounds
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { lastTouch = t.location(in: self) }
        super.touchesBegan(touches, with: event)
    }

    private func applyShape() {
        if Mat.active { applyMaterial(); return }
        card?.isHidden = true
        press.isHidden = false
        layer.masksToBounds = true
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

    /// Tự vẽ trạng thái chạm ngay trong lớp đã bo góc (nền chọn mặc định của hệ thống hiện thành hình chữ nhật).
    private let press = UIView()
    override var selectedBackgroundView: UIView? {
        get { return super.selectedBackgroundView }
        set { }   // Theme.style(cell:) đặt nền chọn hình chữ nhật; ô này tự vẽ nên bỏ qua
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        applyPress(highlighted, animated: animated)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        applyPress(selected, animated: animated)
    }

    private func applyPress(_ on: Bool, animated: Bool) {
        if Mat.active, let c = card {
            guard selectionStyle != .none else { c.setPressed(false, animated: true); return }
            if on { c.ripple(from: lastTouch) }
            c.setPressed(on, animated: animated)
            return
        }
        guard selectionStyle != .none else { press.alpha = 0; return }
        press.backgroundColor = Theme.chip
        let change = { self.press.alpha = on ? 1 : 0 }
        if animated { UIView.animate(withDuration: 0.2, animations: change) } else { change() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = 1.0 / UIScreen.main.scale
        press.frame = bounds
        if Mat.active { applyMaterial() }
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

/// Làm mờ gần như trong suốt: hiệu ứng mờ của hệ thống đã bỏ lớp phủ màu sáng/tối.
final class ClearBlurView: UIView {
    private var fallback: UIVisualEffectView?

    init(radius: CGFloat) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        addSubview(v)
        fallback = v
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let v = fallback {
            v.frame = bounds
            for sub in v.subviews where String(describing: type(of: sub)).contains("VisualEffectSubview") { sub.alpha = 0 }
        }
    }
}

/// Dải mờ trong suốt nhạt dần xuống dưới, đặt sau thanh điều hướng (nhiều lớp với độ mờ tăng dần ở trên).
final class GlassBackdropView: UIView {
    private var layers: [ClearBlurView] = []
    private var masks: [CAGradientLayer] = []

    /// iOS 12 không gỡ được lớp phủ màu của hiệu ứng mờ nên bị vệt xám/trắng ở đầu màn hình (thấy rõ ở Cài đặt);
    /// bản đó dùng dải chuyển màu nền thay cho lớp mờ.
    private let fade = CAGradientLayer()
    private var useFade = false

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        if #available(iOS 13.0, *) {} else {
            useFade = true
            fade.colors = [Theme.background.withAlphaComponent(0.92).cgColor, Theme.background.withAlphaComponent(0.55).cgColor,
                           Theme.background.withAlphaComponent(0).cgColor]
            fade.locations = [0, 0.6, 1]
            layer.addSublayer(fade)
            return
        }
        let radii: [CGFloat] = [3, 7, 13]
        for (i, r) in radii.enumerated() {
            let v = ClearBlurView(radius: r)
            let m = CAGradientLayer()
            m.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
            let start = Double(i) * 0.12
            m.locations = [0, NSNumber(value: 0.55 + start * 0.4), NSNumber(value: 1.0 - 0.12 * Double(2 - i))]
            v.layer.mask = m
            addSubview(v)
            layers.append(v)
            masks.append(m)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if useFade { fade.frame = bounds }
        for (i, v) in layers.enumerated() {
            v.frame = bounds
            masks[i].frame = v.bounds
        }
        CATransaction.commit()
    }
}

/// Thanh điều hướng trong suốt + dải mờ kính; dùng cho mọi màn hình trong app.
final class GlassNavigationController: UINavigationController {
    private let backdrop = GlassBackdropView()

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.style(navigationBar: navigationBar)
        view.insertSubview(backdrop, belowSubview: navigationBar)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.isHidden = navigationBar.isHidden
        backdrop.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.safeAreaInsets.top + 44 + 26)
    }
}

/// Nút chọn một trong vài mục kiểu Material 3: viên thuốc có viền, mục đang chọn tô màu nhấn nhạt kèm dấu ✓.
final class M3Segmented: UIControl {
    private var buttons: [UILabel] = []
    private let fill = UIView()
    private(set) var selectedSegmentIndex: Int
    private let titles: [String]
    private let font = UIFont.systemFont(ofSize: 13, weight: .semibold)

    init(items: [String], selected: Int) {
        titles = items
        selectedSegmentIndex = selected
        super.init(frame: .zero)
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = M3.outline.cgColor
        clipsToBounds = true
        fill.backgroundColor = M3.primaryContainer
        fill.layer.cornerRadius = 16
        fill.isUserInteractionEnabled = false
        addSubview(fill)
        for t in items {
            let l = UILabel()
            l.text = t
            l.font = font
            l.textAlignment = .center
            l.isUserInteractionEnabled = false
            addSubview(l)
            buttons.append(l)
        }
        let w = items.reduce(CGFloat(0)) { $0 + ceil(($1 as NSString).size(withAttributes: [.font: font]).width) + 28 }
        frame = CGRect(x: 0, y: 0, width: w, height: 32)
        refreshColors()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshColors() {
        for (i, l) in buttons.enumerated() {
            l.textColor = i == selectedSegmentIndex ? M3.primary : Theme.secondaryText
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let widths = titles.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 28 }
        var x: CGFloat = 0
        for (i, l) in buttons.enumerated() {
            l.frame = CGRect(x: x, y: 0, width: widths[i], height: bounds.height)
            if i == selectedSegmentIndex { fill.frame = CGRect(x: x, y: 0, width: widths[i], height: bounds.height) }
            x += widths[i]
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        for (i, l) in buttons.enumerated() where l.frame.contains(p) && i != selectedSegmentIndex {
            selectedSegmentIndex = i
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.5, options: [], animations: {
                self.layoutSubviews()
                self.refreshColors()
            }, completion: nil)
            sendActions(for: .valueChanged)
            break
        }
    }
}
