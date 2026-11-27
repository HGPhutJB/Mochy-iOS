import UIKit
import ObjectiveC

// Material 3 (Expressive) cho Mochy Remake: chuyển từ ClaudeMini — chỉ phần giao diện và chuyển động.
// Bật/tắt bằng Cài đặt ▸ Giao diện ▸ Kiểu giao diện; ở kiểu Gốc mọi thứ dưới đây không có tác dụng.

enum UIStyle {
    static let changed = Notification.Name("MochyUIStyleChanged")

    static var material: Bool {
        get { return UserDefaults.standard.bool(forKey: "ui.material") }
        set { UserDefaults.standard.set(newValue, forKey: "ui.material") }
    }
}

enum MatSpeed { case fast, normal, slow }

// MARK: - Chuyển động (lò xo Expressive + đường cong chuẩn của Material 3)

enum Mat {
    static var active: Bool { return UIStyle.material }
    static var reduceMotion: Bool { return UIAccessibility.isReduceMotionEnabled }

    struct Spec { let damping: CGFloat; let stiffness: CGFloat }

    /// Lò xo "không gian" (di chuyển, đổi cỡ, đổi hình): damping 0.6/0.8/0.8, độ cứng 800/380/200.
    static func spatial(_ speed: MatSpeed) -> Spec {
        switch speed {
        case .fast: return Spec(damping: 0.6, stiffness: 800)
        case .slow: return Spec(damping: 0.8, stiffness: 200)
        case .normal: return Spec(damping: 0.8, stiffness: 380)
        }
    }

    /// Lò xo "hiệu ứng" (màu, độ mờ): damping 1.
    static func effects(_ speed: MatSpeed) -> Spec {
        switch speed {
        case .fast: return Spec(damping: 1, stiffness: 3800)
        case .slow: return Spec(damping: 1, stiffness: 800)
        case .normal: return Spec(damping: 1, stiffness: 1600)
        }
    }

    /// Thời gian lò xo cần để dừng hẳn (còn 0,1% quãng đường).
    static func settle(_ spec: Spec) -> TimeInterval {
        return TimeInterval(6.9 / (spec.damping * sqrt(spec.stiffness)))
    }

    static func spring(_ keyPath: String, from: Any, to: Any, _ spec: Spec) -> CASpringAnimation {
        let s = CASpringAnimation(keyPath: keyPath)
        s.fromValue = from
        s.toValue = to
        s.mass = 1
        s.stiffness = spec.stiffness
        s.damping = 2 * spec.damping * sqrt(spec.stiffness)
        s.initialVelocity = 0
        s.duration = s.settlingDuration
        return s
    }

    private static func run(_ spec: Spec, delay: TimeInterval, _ animations: @escaping () -> Void, _ completion: ((Bool) -> Void)?) {
        if reduceMotion {
            animations()
            completion?(true)
            return
        }
        UIView.animate(withDuration: settle(spec), delay: delay, usingSpringWithDamping: spec.damping, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: animations, completion: completion)
    }

    static func animateSpatial(_ speed: MatSpeed = .normal, delay: TimeInterval = 0, _ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        run(spatial(speed), delay: delay, animations, completion)
    }

    static func animateEffects(_ speed: MatSpeed = .normal, _ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        run(effects(speed), delay: 0, animations, completion)
    }

    private static func curve(_ duration: TimeInterval, _ c1: CGPoint, _ c2: CGPoint, _ animations: @escaping () -> Void, _ completion: ((Bool) -> Void)?) {
        if reduceMotion {
            animations()
            completion?(true)
            return
        }
        let animator = UIViewPropertyAnimator(duration: duration, controlPoint1: c1, controlPoint2: c2, animations: animations)
        animator.isInterruptible = false
        if let completion = completion { animator.addCompletion { completion($0 == .end) } }
        animator.startAnimation()
    }

    /// Vào màn hình: giảm tốc (0.05, 0.7, 0.1, 1). Rời đi: tăng tốc (0.3, 0, 0.8, 0.15). Chuẩn: (0.2, 0, 0, 1).
    static func emphasizedDecelerate(_ d: TimeInterval, _ a: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        curve(d, CGPoint(x: 0.05, y: 0.7), CGPoint(x: 0.1, y: 1), a, completion)
    }
    static func emphasizedAccelerate(_ d: TimeInterval, _ a: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        curve(d, CGPoint(x: 0.3, y: 0), CGPoint(x: 0.8, y: 0.15), a, completion)
    }
    static func standard(_ d: TimeInterval, _ a: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        curve(d, CGPoint(x: 0.2, y: 0), CGPoint(x: 0, y: 1), a, completion)
    }

    /// Hộp thoại: thẻ phóng từ 0,9 bằng lò xo và hiện dần; khi đóng thu còn 0,94 và mờ trong 150 ms.
    static func presentDialogCard(_ card: UIView) {
        guard active, !reduceMotion else { return }
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        animateSpatial { card.transform = .identity }
        animateEffects { card.alpha = 1 }
    }

    static func dismissDialogCard(_ card: UIView) {
        guard active, !reduceMotion else { return }
        emphasizedAccelerate(0.15) {
            card.alpha = 0
            card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }
    }

    static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
    }

    /// Màu nền thẻ tonal.
    static var surface: UIColor { return Theme.cellBackground }

    static func roundedPath(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> UIBezierPath {
        let t = max(0, min(top, r.height / 2)), b = max(0, min(bottom, r.height / 2))
        let p = UIBezierPath()
        p.move(to: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY))
        p.addArc(withCenter: CGPoint(x: r.maxX - t, y: r.minY + t), radius: t, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - b))
        p.addArc(withCenter: CGPoint(x: r.maxX - b, y: r.maxY - b), radius: b, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        p.addLine(to: CGPoint(x: r.minX + b, y: r.maxY))
        p.addArc(withCenter: CGPoint(x: r.minX + b, y: r.maxY - b), radius: b, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + t))
        p.addArc(withCenter: CGPoint(x: r.minX + t, y: r.minY + t), radius: t, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
        p.close()
        return p
    }
}

// MARK: - Thẻ phía sau mỗi hàng

/// Thẻ tonal: khi chạm, hình dạng nhún thành bo tròn hoàn toàn (lò xo giải bằng công thức, góc không bao giờ vọt thành hình méo)
/// và có sóng ripple lan từ điểm chạm, bị cắt đúng theo viền thẻ.
final class MaterialCardView: UIView {
    var fillColor: UIColor? { didSet { setNeedsLayout() } }
    var topRadius: CGFloat = 6 { didSet { resetRadii() } }
    var bottomRadius: CGFloat = 6 { didSet { resetRadii() } }
    var cardInsets = UIEdgeInsets(top: 1.5, left: 0, bottom: 1.5, right: 0) { didSet { setNeedsLayout() } }

    private let shape = CAShapeLayer()
    private let overlay = CALayer()          // sóng ripple nằm ở đây, bị cắt bởi maskShape
    private let maskShape = CAShapeLayer()
    private var pressedState = false
    private var link: CADisplayLink?
    private var springStart: CFTimeInterval = 0
    private var curTop: CGFloat = 6, curBottom: CGFloat = 6
    private var fromTop: CGFloat = 6, fromBottom: CGFloat = 6, toTop: CGFloat = 6, toBottom: CGFloat = 6

    private final class Proxy {
        weak var card: MaterialCardView?
        @objc func tick(_ l: CADisplayLink) { card?.tickSpring(l) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        overlay.mask = maskShape
        layer.addSublayer(overlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    deinit { link?.invalidate() }

    private var cardRect: CGRect { return bounds.inset(by: cardInsets) }
    private var fullRadius: CGFloat { return min(28, cardRect.height / 2) }

    private func resetRadii() {
        if link == nil {
            curTop = pressedState ? fullRadius : topRadius
            curBottom = pressedState ? fullRadius : bottomRadius
        }
        applyRadii()
    }

    private func applyRadii() {
        let path = Mat.roundedPath(cardRect, top: curTop, bottom: curBottom).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        maskShape.path = path
        CATransaction.commit()
    }

    private func stopSpring() {
        link?.invalidate()
        link = nil
    }

    func setPressed(_ pressed: Bool, animated: Bool) {
        if pressed == pressedState { return }
        pressedState = pressed
        fromTop = curTop
        fromBottom = curBottom
        toTop = pressed ? fullRadius : topRadius
        toBottom = pressed ? fullRadius : bottomRadius
        if !pressed { fadeRipples() }
        let scale: CGFloat = pressed ? 0.975 : 1
        if animated && !Mat.reduceMotion && window != nil {
            let current = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
            let dip = Mat.spring("transform.scale", from: current > 0.5 ? current : 1, to: scale, Mat.spatial(.fast))
            layer.add(dip, forKey: "dip")
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
            springStart = CACurrentMediaTime()
            if link == nil {
                let proxy = Proxy()
                proxy.card = self
                let l = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
                l.add(to: .main, forMode: .common)
                link = l
            }
        } else {
            stopSpring()
            curTop = toTop
            curBottom = toBottom
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
            applyRadii()
        }
    }

    /// Lò xo "không gian nhanh" (damping 0,6, độ cứng 800) giải bằng công thức đóng.
    private func tickSpring(_ l: CADisplayLink) {
        let zeta: CGFloat = 0.6, omega = sqrt(CGFloat(800))
        let t = CGFloat(CACurrentMediaTime() - springStart)
        let settle = 6.9 / (zeta * omega)
        var s: CGFloat = 1
        if t < settle {
            let wd = omega * sqrt(1 - zeta * zeta)
            s = 1 - exp(-zeta * omega * t) * (cos(wd * t) + (zeta * omega / wd) * sin(wd * t))
        }
        let maxR = cardRect.height / 2
        curTop = max(0, min(maxR, fromTop + (toTop - fromTop) * s))
        curBottom = max(0, min(maxR, fromBottom + (toBottom - fromBottom) * s))
        applyRadii()
        if t >= settle || window == nil {
            curTop = toTop
            curBottom = toBottom
            applyRadii()
            stopSpring()
        }
    }

    /// Ripple (10% màu chữ) lớn dần từ điểm chạm tới góc xa nhất, giữ nguyên khi còn đặt tay, mờ đi khi nhấc tay.
    func ripple(from point: CGPoint) {
        let rect = cardRect
        if rect.width < 2 || Mat.reduceMotion { return }
        overlay.frame = bounds
        maskShape.frame = bounds
        applyRadii()
        let corners = [rect.origin, CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        let far = (corners.map { hypot($0.x - point.x, $0.y - point.y) }.max() ?? 0) + 2
        let circle = CAShapeLayer()
        circle.name = "ripple"
        circle.fillColor = (Theme.isDark ? UIColor.white : UIColor.black).withAlphaComponent(0.10).cgColor
        let start = UIBezierPath(ovalIn: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
        let end = UIBezierPath(ovalIn: CGRect(x: point.x - far, y: point.y - far, width: far * 2, height: far * 2))
        circle.path = end.cgPath
        overlay.addSublayer(circle)
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = start.cgPath
        grow.toValue = end.cgPath
        grow.duration = 0.45
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1)
        circle.add(grow, forKey: "grow")
    }

    private func fadeRipples() {
        for sub in overlay.sublayers ?? [] where sub.name == "ripple" && sub.animation(forKey: "fade") == nil {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = sub.presentation()?.opacity ?? 1
            fade.toValue = 0
            fade.duration = 0.30
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            sub.opacity = 0
            sub.add(fade, forKey: "fade")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak sub] in sub?.removeFromSuperlayer() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.fillColor = (fillColor ?? Mat.surface).cgColor
        overlay.frame = bounds
        maskShape.frame = bounds
        CATransaction.commit()
        if link == nil {
            curTop = pressedState ? fullRadius : topRadius
            curBottom = pressedState ? fullRadius : bottomRadius
        }
        applyRadii()
    }
}

// MARK: - Thanh trượt (rãnh gradient, nút tròn lớn)

final class MaterialSlider: UIControl {
    private let trackLayer = CAGradientLayer()
    private let thumbView = UIView()
    private static let thumb: CGFloat = 40
    private static let trackHeight: CGFloat = 28
    private(set) var value: CGFloat = 0

    var trackColors: [UIColor] = [.black, .white] { didSet { applyColors() } }
    var thumbColor: UIColor = .gray { didSet { thumbView.backgroundColor = thumbColor } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        trackLayer.startPoint = CGPoint(x: 0, y: 0.5)
        trackLayer.endPoint = CGPoint(x: 1, y: 0.5)
        trackLayer.cornerRadius = MaterialSlider.trackHeight / 2
        layer.addSublayer(trackLayer)
        thumbView.isUserInteractionEnabled = false
        thumbView.layer.cornerRadius = MaterialSlider.thumb / 2
        thumbView.layer.borderWidth = 4
        thumbView.layer.borderColor = UIColor.white.cgColor
        addSubview(thumbView)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override var intrinsicContentSize: CGSize { return CGSize(width: UIView.noIntrinsicMetric, height: MaterialSlider.thumb + 4) }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.colors = trackColors.map { $0.cgColor }
        CATransaction.commit()
        thumbView.backgroundColor = thumbColor
    }

    private var travelLength: CGFloat { return max(1, bounds.width - MaterialSlider.thumb) }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = CGRect(x: 0, y: (bounds.height - MaterialSlider.trackHeight) / 2, width: bounds.width, height: MaterialSlider.trackHeight)
        CATransaction.commit()
        placeThumb()
    }

    private func placeThumb() {
        let cx = MaterialSlider.thumb / 2 + value * travelLength
        thumbView.frame = CGRect(x: cx - MaterialSlider.thumb / 2, y: (bounds.height - MaterialSlider.thumb) / 2,
                                 width: MaterialSlider.thumb, height: MaterialSlider.thumb)
    }

    func setValue(_ v: CGFloat, animated: Bool) {
        value = max(0, min(1, v))
        if animated { Mat.animateSpatial(.fast) { self.placeThumb() } } else { placeThumb() }
    }

    private func update(from touch: UITouch) {
        let v = max(0, min(1, (touch.location(in: self).x - MaterialSlider.thumb / 2) / travelLength))
        if abs(v - value) < 0.0005 { return }
        value = v
        placeThumb()
        sendActions(for: .valueChanged)
    }

    private func grow(_ on: Bool) {
        let target = on ? CGAffineTransform(scaleX: 1.18, y: 1.18) : .identity
        Mat.animateSpatial(.fast) { self.thumbView.transform = target }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        update(from: touch)
        grow(true)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { update(from: touch); return true }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { if let t = touch { update(from: t) }; grow(false) }
    override func cancelTracking(with event: UIEvent?) { grow(false) }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { return bounds.insetBy(dx: -8, dy: -10).contains(point) }
}

// MARK: - Thanh điều hướng Material 3 (icon + nhãn, viên thuốc chỉ báo sau icon đang chọn)

protocol TabBarControl: AnyObject {
    var onSelect: ((Int) -> Void)? { get set }
    var onTapWhileCollapsed: (() -> Void)? { get set }
    var backdrop: UIView? { get set }
    func select(_ index: Int, animated: Bool)
    func setCollapsed(_ value: Bool, animated: Bool)
    func setBadge(visible: Bool)
    func adaptToBackdrop()
}

extension FloatingTabBar: TabBarControl {}

final class MaterialNavBar: UIView, TabBarControl {
    static let contentHeight: CGFloat = 80

    var onSelect: ((Int) -> Void)?
    var onTapWhileCollapsed: (() -> Void)?
    weak var backdrop: UIView?

    private let items: [(UIImage, String)]
    private var indicators: [UIView] = []
    private var icons: [UIImageView] = []
    private var labels: [UILabel] = []
    private var buttons: [UIControl] = []
    private let badge = UIView()
    private let shape = CAShapeLayer()
    private var selectedIndex = -1

    init(icons images: [UIImage], titles: [String]) {
        items = Array(zip(images, titles))
        super.init(frame: .zero)
        layer.addSublayer(shape)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Theme.isDark ? 0.35 : 0.12
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: -1)
        for (image, title) in items {
            let pill = UIView()
            pill.backgroundColor = Theme.accent.withAlphaComponent(Theme.isDark ? 0.30 : 0.20)
            pill.alpha = 0
            pill.isUserInteractionEnabled = false
            addSubview(pill)
            indicators.append(pill)
            let icon = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
            icon.contentMode = .center
            icon.tintColor = Theme.secondaryText
            icon.isUserInteractionEnabled = false
            addSubview(icon)
            icons.append(icon)
            let label = UILabel()
            label.text = title
            label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            label.textColor = Theme.secondaryText
            label.textAlignment = .center
            label.isUserInteractionEnabled = false
            addSubview(label)
            labels.append(label)
            let b = UIControl()
            b.tag = buttons.count
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addSubview(b)
            buttons.append(b)
        }
        badge.backgroundColor = Theme.accent
        badge.layer.cornerRadius = 4.5
        badge.isHidden = true
        badge.isUserInteractionEnabled = false
        addSubview(badge)
        accessibilityTraits = .tabBar
        NotificationCenter.default.addObserver(self, selector: #selector(accentChanged), name: .accentChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func accentChanged() {
        UIView.animate(withDuration: 0.5) {
            for pill in self.indicators { pill.backgroundColor = Theme.accent.withAlphaComponent(Theme.isDark ? 0.30 : 0.20) }
            self.badge.backgroundColor = Theme.accent
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    private func itemRect(_ i: Int) -> CGRect {
        let w = bounds.width / CGFloat(max(1, items.count))
        return CGRect(x: w * CGFloat(i), y: 0, width: w, height: MaterialNavBar.contentHeight)
    }

    private func pillRect(_ i: Int) -> CGRect {
        let r = itemRect(i)
        return CGRect(x: r.midX - 32, y: 12, width: 64, height: 32)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius: CGFloat = 20
        shape.frame = bounds
        shape.fillColor = (Theme.isDark ? UIColor(white: 0.11, alpha: 1) : UIColor(white: 0.965, alpha: 1)).cgColor
        let corners: UIRectCorner = [.topLeft, .topRight]
        shape.path = UIBezierPath(roundedRect: bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath
        layer.shadowPath = shape.path
        for i in 0..<items.count {
            let r = itemRect(i)
            let p = pillRect(i)
            let selected = i == selectedIndex
            if indicators[i].layer.animationKeys()?.isEmpty ?? true {
                indicators[i].transform = .identity
                indicators[i].frame = p
                indicators[i].layer.cornerRadius = 16
                indicators[i].alpha = selected ? 1 : 0
            }
            icons[i].frame = p
            labels[i].frame = CGRect(x: r.minX, y: 48, width: r.width, height: 16)
            buttons[i].frame = r
        }
        if let last = icons.last {
            badge.frame = CGRect(x: last.frame.midX + 8, y: last.frame.minY + 2, width: 9, height: 9)
        }
    }

    func select(_ index: Int, animated: Bool) {
        guard index >= 0 && index < items.count, index != selectedIndex else { return }
        let old = selectedIndex
        selectedIndex = index
        let ink = Theme.primaryText
        let apply = {
            for i in 0..<self.items.count {
                let on = i == index
                self.icons[i].tintColor = on ? ink : Theme.secondaryText
                self.labels[i].textColor = on ? ink : Theme.secondaryText
                self.labels[i].font = UIFont.systemFont(ofSize: 12, weight: on ? .bold : .medium)
            }
        }
        let pill = indicators[index]
        if animated && old >= 0 && !Mat.reduceMotion {
            // Viên thuốc mới nở ra từ giữa bằng lò xo, viên cũ mờ đi.
            pill.frame = pillRect(index)
            pill.layer.cornerRadius = 16
            pill.transform = CGAffineTransform(scaleX: 0.3, y: 1)
            pill.alpha = 0
            Mat.animateSpatial(.fast) { pill.transform = .identity }
            Mat.animateEffects(.normal) { pill.alpha = 1; apply() }
            let prev = indicators[old]
            Mat.animateEffects(.fast) { prev.alpha = 0 }
            let icon = icons[index]
            icon.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            Mat.animateSpatial(.fast) { icon.transform = .identity }
        } else {
            for (i, v) in indicators.enumerated() { v.alpha = i == index ? 1 : 0 }
            apply()
        }
    }

    @objc private func tapped(_ sender: UIControl) {
        Haptics.tap()
        onSelect?(sender.tag)
    }

    func setCollapsed(_ value: Bool, animated: Bool) {}
    func adaptToBackdrop() {}
    func setBadge(visible: Bool) {
        if badge.isHidden == !visible { return }
        badge.isHidden = !visible
        if visible { badge.pop() }
    }
}

// MARK: - Nền chọn bo tròn cho các hàng thường

/// Thay hình chữ nhật chọn mặc định: viên thuốc bo tròn nở ra bằng lò xo khi chạm (nhún từ góc nhỏ sang góc lớn).
final class MaterialSelectionView: UIView {
    private let pill = UIView()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        pill.backgroundColor = Theme.chip
        addSubview(pill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    private var restRadius: CGFloat { return min(28, max(0, pill.bounds.height / 2)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = bounds.insetBy(dx: 8, dy: 2)
        pill.layer.cornerRadius = restRadius
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !Mat.reduceMotion else { return }
        layoutIfNeeded()
        let end = restRadius
        pill.layer.add(Mat.spring("cornerRadius", from: 8, to: end, Mat.spatial(.fast)), forKey: "morph")
        pill.layer.add(Mat.spring("transform.scale", from: 0.97, to: 1, Mat.spatial(.fast)), forKey: "dip")
    }
}

extension Theme {
    /// Nền chọn của một hàng: viên thuốc bo tròn ở Material 3, hình chữ nhật mờ ở giao diện gốc.
    static func selectionView() -> UIView {
        if Mat.active { return MaterialSelectionView() }
        let v = UIView()
        v.backgroundColor = chip
        return v
    }
}

extension UITableViewCell {
    /// Hiện dần + trượt lên khi hàng xuất hiện lần đầu (so le theo vị trí), chỉ ở Material 3.
    func materialEntrance(force: Bool = false) {
        guard Mat.active, !Mat.reduceMotion, force || window == nil, frame.minY < 1100 else { return }
        let delay = Double(max(0, min(frame.minY, 900))) / 3200
        contentView.alpha = 0
        contentView.transform = CGAffineTransform(translationX: 0, y: 22)
        Mat.animateSpatial(.normal, delay: delay) { self.contentView.transform = .identity }
        UIView.animate(withDuration: 0.3, delay: delay, options: [.allowUserInteraction], animations: { self.contentView.alpha = 1 }, completion: nil)
    }
}
