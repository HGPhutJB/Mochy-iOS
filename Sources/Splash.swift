import UIKit

extension Notification.Name {
    /// Trang chủ đã tải xong lần đầu (có hoặc không có dữ liệu).
    static let homeLoaded = Notification.Name("MochyHomeLoaded")
}

/// Khung tạm trong lúc dựng giao diện thật: nền trùng màn hình chờ, thanh trạng thái sáng.
final class SplashHostController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SplashView.background
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
}

/// Màn khởi động: logo Mochy (không nền) hiện ngay giữa màn hình, vòng xung nhịp lan ra trong lúc app tải.
/// Tải xong thì logo "núng nính" (ịch xuống, nảy to ra, xoáy nhẹ), hiện vòng tròn quanh logo rồi bay theo đường vòng cung
/// lên góc trái thanh tiêu đề Trang chủ.
final class SplashView: UIView {
    static let background = UIColor(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 29.0 / 255.0, alpha: 1)   // trùng màn hình chờ
    /// Còn đang chờ logo bay xuống (Trang chủ ẩn logo thật cho tới khi nó đáp).
    static var landing = false
    static weak var targetView: UIView?
    private static weak var current: SplashView?

    private static let side: CGFloat = 96   // bằng ảnh logo trong màn hình chờ
    private let logo = UIImageView()
    private let disc = CAShapeLayer()       // vòng tròn nền quanh logo
    private let ring = CAShapeLayer()       // vòng xung nhịp
    private var born = Date()
    private var homeReady = false
    private var finishing = false

    static func logoImage() -> UIImage? { return UIImage(named: "MochyLogo") }

    static func show(on window: UIWindow) {
        let v = SplashView(frame: window.bounds)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(v)
        current = v
        v.begin()
    }

    static func bringToFront(in window: UIWindow) {
        if let v = current { window.bringSubviewToFront(v) }
    }

    /// Nếu có lỗi bất ngờ, đảm bảo màn khởi động không kẹt lại.
    static func abort() {
        current?.removeFromSuperview()
        landing = false
        targetView?.alpha = 1
    }

    private func circle(_ layer: CAShapeLayer, diameter: CGFloat, at c: CGPoint) {
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.position = c
        layer.path = UIBezierPath(ovalIn: layer.bounds).cgPath
    }

    private func begin() {
        backgroundColor = SplashView.background
        born = Date()
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let side = SplashView.side

        circle(disc, diameter: side * 1.75, at: c)
        disc.fillColor = UIColor(white: 1, alpha: 0.07).cgColor
        disc.strokeColor = UIColor(white: 1, alpha: 0.3).cgColor
        disc.lineWidth = 1.5
        disc.opacity = 0
        layer.addSublayer(disc)

        circle(ring, diameter: side * 1.75, at: c)
        ring.fillColor = nil
        ring.strokeColor = UIColor(white: 1, alpha: 0.5).cgColor
        ring.lineWidth = 1.5
        ring.opacity = 0
        layer.addSublayer(ring)

        logo.image = SplashView.logoImage() ?? Icons.music(64)
        logo.contentMode = .scaleAspectFit
        logo.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        logo.center = c
        addSubview(logo)

        NotificationCenter.default.addObserver(self, selector: #selector(homeLoaded), name: .homeLoaded, object: nil)
        startPulse(from: side * 0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.tryFinish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in self?.finish() }   // chờ tối đa 5 giây
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func homeLoaded() {
        homeReady = true
        tryFinish()
    }

    /// Vòng mảnh lan ra từ logo, lặp lại nhẹ nhàng trong lúc chờ tải.
    private func startPulse(from diameter: CGFloat) {
        let c = ring.position
        circle(ring, diameter: diameter, at: c)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 1.9
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.55, 0]
        fade.keyTimes = [0, 0.2, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 1.5
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        ring.add(group, forKey: "pulse")
    }

    private func tryFinish() {
        guard !finishing, homeReady, Date().timeIntervalSince(born) >= 1.3 else { return }
        finish()
    }

    private func finish() {
        guard !finishing else { return }
        finishing = true
        guard window != nil else { SplashView.abort(); return }
        if UIAccessibility.isReduceMotionEnabled { flyAway(); return }
        wobble { self.flyAway() }
    }

    /// Núng nính: ịch xuống (thu nhỏ + nghiêng), bật to ra rồi lắc tắt dần như xoáy nước; sau đó hiện vòng tròn quanh logo.
    private func wobble(_ done: @escaping () -> Void) {
        ring.removeAnimation(forKey: "pulse")
        ring.opacity = 0
        let wob = CAKeyframeAnimation(keyPath: "transform")
        func t(_ s: CGFloat, _ r: CGFloat) -> NSValue {
            return NSValue(caTransform3D: CATransform3DRotate(CATransform3DMakeScale(s, s, 1), r, 0, 0, 1))
        }
        wob.values = [t(1, 0), t(0.74, -0.22), t(1.24, 0.16), t(0.93, -0.07), t(1.06, 0.03), t(1, 0)]
        wob.keyTimes = [0, 0.2, 0.46, 0.68, 0.86, 1]
        wob.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1),
            CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeOut)
        ]
        wob.duration = 0.85
        logo.layer.add(wob, forKey: "wobble")

        // Vòng tròn nền bung ra đúng lúc logo nảy to.
        let appear = CASpringAnimation(keyPath: "transform.scale")
        appear.fromValue = 0.55
        appear.toValue = 1
        appear.mass = 1
        appear.stiffness = 180
        appear.damping = 14
        appear.beginTime = CACurrentMediaTime() + 0.17
        appear.fillMode = .backwards
        appear.duration = appear.settlingDuration
        let show = CABasicAnimation(keyPath: "opacity")
        show.fromValue = 0
        show.toValue = 1
        show.duration = 0.25
        show.beginTime = CACurrentMediaTime() + 0.17
        show.fillMode = .backwards
        disc.opacity = 1
        disc.add(appear, forKey: "appear")
        disc.add(show, forKey: "show")

        // Vòng sóng lan ra từ vòng tròn.
        circle(ring, diameter: SplashView.side * 1.75, at: ring.position)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 1.55
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.7, 0]
        fade.keyTimes = [0, 1]
        let g = CAAnimationGroup()
        g.animations = [grow, fade]
        g.duration = 0.7
        g.beginTime = CACurrentMediaTime() + 0.3
        g.fillMode = .backwards
        g.timingFunction = CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1)
        ring.add(g, forKey: "burst")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: done)
    }

    /// Logo co nhỏ và bay theo đường cong tới vị trí logo Trang chủ; nền tối và vòng tròn mờ dần để lộ Trang chủ.
    private func flyAway() {
        guard let window = window else { SplashView.abort(); return }
        window.rootViewController?.view.layoutIfNeeded()
        var target = CGRect(x: 16, y: window.safeAreaInsets.top + 7, width: 30, height: 30)
        if let t = SplashView.targetView, t.window != nil {
            let r = t.convert(t.bounds, to: window)
            if r.width > 1 && r.minY > 0 && r.minX >= 0 && r.maxX <= window.bounds.width { target = r }
        }
        let from = logo.center
        let to = CGPoint(x: target.midX, y: target.midY)
        let duration: CFTimeInterval = UIAccessibility.isReduceMotionEnabled ? 0.01 : 0.95
        let timing = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.15, 1)

        // Đường vòng cung: đi lên rồi cong sang trái (cubic Bézier mượt).
        let path = UIBezierPath()
        path.move(to: from)
        path.addCurve(to: to,
                      controlPoint1: CGPoint(x: from.x + (to.x - from.x) * 0.05, y: from.y + (to.y - from.y) * 0.55),
                      controlPoint2: CGPoint(x: from.x + (to.x - from.x) * 0.55, y: to.y - 6))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path.cgPath
        move.calculationMode = .paced
        let shrink = CABasicAnimation(keyPath: "bounds")
        shrink.fromValue = NSValue(cgRect: logo.bounds)
        shrink.toValue = NSValue(cgRect: CGRect(origin: .zero, size: target.size))
        let group = CAAnimationGroup()
        group.animations = [move, shrink]
        group.duration = duration
        group.timingFunction = timing
        logo.layer.position = to
        logo.layer.bounds = CGRect(origin: .zero, size: target.size)
        logo.layer.add(group, forKey: "fly")

        // Vòng tròn nền co theo và mờ đi.
        let discShrink = CABasicAnimation(keyPath: "transform.scale")
        discShrink.fromValue = 1
        discShrink.toValue = 0.2
        let discFade = CABasicAnimation(keyPath: "opacity")
        discFade.fromValue = 1
        discFade.toValue = 0
        let dg = CAAnimationGroup()
        dg.animations = [discShrink, discFade]
        dg.duration = duration * 0.7
        dg.timingFunction = timing
        disc.opacity = 0
        disc.add(dg, forKey: "discOut")

        UIView.animate(withDuration: duration * 0.7, delay: duration * 0.15, options: [.curveEaseOut], animations: {
            self.backgroundColor = .clear
        }, completion: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in self?.land() }
    }

    private func land() {
        SplashView.landing = false
        if let t = SplashView.targetView {
            UIView.animate(withDuration: 0.2, animations: { t.alpha = 1 }, completion: nil)
        }
        UIView.animate(withDuration: 0.2, animations: { self.logo.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
    }
}
