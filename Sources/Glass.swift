import UIKit

/// Hiệu ứng "kéo giãn rồi nảy" của nút kính (như iOS mới): chạm xuống thì phình lên, kéo ngón tay thì nút
/// giãn dài theo hướng kéo và bị ngón tay kéo theo (có sức cản), thả ra thì co lại và nảy vài nhịp.
enum Elastic {
    static func begin(_ v: UIView, pressedScale: CGFloat = 1.12) {
        v.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 3,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            v.transform = CGAffineTransform(scaleX: pressedScale, y: pressedScale)
        }, completion: nil)
    }

    /// `delta` là quãng ngón tay đã kéo kể từ lúc chạm (theo toạ độ màn hình).
    static func move(_ v: UIView, delta: CGPoint, pressedScale: CGFloat = 1.12) {
        let d = hypot(delta.x, delta.y)
        guard d > 0.5 else { return }
        // Sức cản: kéo càng xa thì nút đi theo càng ít (tiệm cận ~34pt).
        let follow = 34 * tanh(d / 90) / d
        let angle = atan2(delta.y, delta.x)
        let r = min(d, 120) / 120
        var t = CGAffineTransform(translationX: delta.x * follow, y: delta.y * follow)
        t = t.rotated(by: angle).scaledBy(x: pressedScale * (1 + 0.38 * r), y: pressedScale * (1 - 0.14 * r)).rotated(by: -angle)
        v.layer.removeAllAnimations()
        v.transform = t
    }

    static func end(_ v: UIView) {
        UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.34, initialSpringVelocity: 9,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            v.transform = .identity
        }, completion: nil)
    }
}

/// Nút tròn kính: nền mờ, viền kính sáng ở mép trên/dưới, icon ở giữa; kéo giãn và nảy khi chạm.
final class GlassCircleButton: UIControl {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let tint = UIView()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    let iconView = UIImageView()
    private var startPoint = CGPoint.zero

    init(icon: UIImage) {
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        addSubview(blur)
        tint.isUserInteractionEnabled = false
        blur.contentView.addSubview(tint)
        rim.colors = [UIColor(white: 1, alpha: 0.14).cgColor, UIColor(white: 1, alpha: 0.0).cgColor,
                      UIColor(white: 1, alpha: 0.0).cgColor, UIColor(white: 1, alpha: 0.08).cgColor]
        rim.locations = [0, 0.28, 0.72, 1]
        rim.startPoint = CGPoint(x: 0.5, y: 0)
        rim.endPoint = CGPoint(x: 0.5, y: 1)
        rimMask.fillColor = UIColor.clear.cgColor
        rimMask.strokeColor = UIColor.black.cgColor
        rimMask.lineWidth = 0.6
        rim.mask = rimMask
        layer.addSublayer(rim)
        iconView.image = icon.withRenderingMode(.alwaysTemplate)
        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)
        setLook(light: !Theme.isDark)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        blur.layer.cornerRadius = bounds.height / 2
        tint.frame = blur.bounds
        rim.frame = bounds
        rimMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.35, dy: 0.35), cornerRadius: bounds.height / 2).cgPath
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        iconView.frame = bounds
    }

    func setLook(light: Bool) {
        blur.effect = UIBlurEffect(style: light ? .extraLight : .dark)
        tint.backgroundColor = light ? UIColor(white: 1, alpha: 0.26) : UIColor(white: 0.14, alpha: 0.86)
        iconView.tintColor = light ? UIColor(white: 0.08, alpha: 1) : .white
        layer.shadowOpacity = light ? 0.16 : 0.32
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        startPoint = touch.location(in: nil)
        Elastic.begin(self)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let p = touch.location(in: nil)
        Elastic.move(self, delta: CGPoint(x: p.x - startPoint.x, y: p.y - startPoint.y))
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        Elastic.end(self)
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        Elastic.end(self)
    }
}
