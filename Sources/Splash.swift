import UIKit

extension Notification.Name {
    /// Trang chủ đã tải xong lần đầu (có hoặc không có dữ liệu).
    static let homeLoaded = Notification.Name("MochyHomeLoaded")
}

/// Màn khởi động: biểu tượng app hiện giữa nền tối, bo tròn dần kèm vòng xung nhịp trong lúc app tải,
/// khi Trang chủ sẵn sàng thì co nhỏ và bay lên góc trái thanh tiêu đề, trở thành logo của Trang chủ.
final class SplashView: UIView {
    /// Còn đang chờ logo bay xuống (Trang chủ ẩn logo thật cho tới khi nó đáp).
    static var landing = false
    static weak var targetView: UIView?
    private static weak var current: SplashView?

    private let icon = UIImageView()
    private let ring = CAShapeLayer()
    private let side: CGFloat = 88
    private var born = Date()
    private var homeReady = false
    private var morphed = false
    private var finishing = false

    static func logoImage() -> UIImage? {
        return UIImage(named: "AppIcon60x60")
    }

    static func show(on window: UIWindow) {
        let v = SplashView(frame: window.bounds)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(v)
        current = v
        v.begin()
    }

    /// Nếu có lỗi bất ngờ, đảm bảo màn khởi động không kẹt lại.
    static func abort() {
        current?.removeFromSuperview()
        landing = false
        targetView?.alpha = 1
    }

    private func begin() {
        backgroundColor = UIColor(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 29.0 / 255.0, alpha: 1)   // trùng màu màn hình chờ hệ thống
        born = Date()
        let c = CGPoint(x: bounds.midX, y: bounds.midY)

        ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ring.position = c
        ring.path = UIBezierPath(ovalIn: ring.bounds).cgPath
        ring.fillColor = nil
        ring.strokeColor = UIColor(white: 1, alpha: 0.5).cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        layer.addSublayer(ring)

        icon.image = SplashView.logoImage() ?? Icons.music(48)
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        icon.center = c
        icon.layer.cornerRadius = side * 0.2237
        icon.alpha = 0
        icon.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        addSubview(icon)

        NotificationCenter.default.addObserver(self, selector: #selector(homeLoaded), name: .homeLoaded, object: nil)
        UIView.animate(withDuration: 0.25) { self.icon.alpha = 1 }
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [], animations: {
            self.icon.transform = .identity
        }, completion: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.morph() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.tryFinish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in self?.finish() }   // chờ tối đa 4 giây
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func homeLoaded() {
        homeReady = true
        tryFinish()
    }

    /// Hình vuông bo góc → hình tròn, nảy nhẹ; vòng xung nhịp bắt đầu lan ra.
    private func morph() {
        guard !finishing else { return }
        let round = CASpringAnimation(keyPath: "cornerRadius")
        round.fromValue = icon.layer.cornerRadius
        round.toValue = side / 2
        round.mass = 1
        round.stiffness = 200
        round.damping = 16
        round.duration = round.settlingDuration
        icon.layer.cornerRadius = side / 2
        icon.layer.add(round, forKey: "round")
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0, options: [], animations: {
            self.icon.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        }, completion: { _ in
            UIView.animate(withDuration: 0.4) { self.icon.transform = .identity }
        })
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 1.7
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.55, 0]
        fade.keyTimes = [0, 0.15, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 1.2
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        ring.add(group, forKey: "pulse")
        morphed = true
        tryFinish()
    }

    private func tryFinish() {
        guard !finishing, morphed, homeReady, Date().timeIntervalSince(born) >= 1.4 else { return }
        finish()
    }

    /// Logo co nhỏ và bay tới vị trí logo của Trang chủ, nền tối mờ dần để lộ Trang chủ.
    private func finish() {
        guard !finishing else { return }
        finishing = true
        guard let window = window else { SplashView.abort(); return }
        window.rootViewController?.view.layoutIfNeeded()

        var target = CGRect(x: 16, y: window.safeAreaInsets.top + 7, width: 30, height: 30)
        if let t = SplashView.targetView, t.window != nil {
            let r = t.convert(t.bounds, to: window)
            if r.width > 1 && r.minY > 0 && r.minX >= 0 && r.maxX <= window.bounds.width { target = r }
        }

        ring.removeAllAnimations()
        ring.opacity = 0
        let center = icon.center
        icon.transform = .identity
        icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        icon.center = center

        let round = CABasicAnimation(keyPath: "cornerRadius")
        round.fromValue = icon.layer.cornerRadius
        round.toValue = target.width / 2
        round.duration = 0.6
        round.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        icon.layer.cornerRadius = target.width / 2
        icon.layer.add(round, forKey: "land")

        if UIAccessibility.isReduceMotionEnabled {
            icon.frame = target
            UIView.animate(withDuration: 0.3, animations: { self.backgroundColor = .clear }, completion: { _ in self.land() })
            return
        }
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, options: [], animations: {
            self.icon.frame = target
        }, completion: { _ in self.land() })
        UIView.animate(withDuration: 0.45, delay: 0.05, options: [.curveEaseOut], animations: {
            self.backgroundColor = .clear
        }, completion: nil)
    }

    private func land() {
        SplashView.landing = false
        SplashView.targetView?.alpha = 1
        removeFromSuperview()
    }
}
