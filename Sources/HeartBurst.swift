import UIKit

/// Hình trái tim dùng chung (cùng đường cong với Icons.heart).
enum HeartShape {
    static func path(in r: CGRect) -> UIBezierPath {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { return CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        let p = UIBezierPath()
        p.move(to: pt(0.5, 0.86))
        p.addCurve(to: pt(0.12, 0.38), controlPoint1: pt(0.2, 0.66), controlPoint2: pt(0.1, 0.52))
        p.addCurve(to: pt(0.5, 0.28), controlPoint1: pt(0.14, 0.2), controlPoint2: pt(0.4, 0.18))
        p.addCurve(to: pt(0.88, 0.38), controlPoint1: pt(0.6, 0.18), controlPoint2: pt(0.86, 0.2))
        p.addCurve(to: pt(0.5, 0.86), controlPoint1: pt(0.9, 0.52), controlPoint2: pt(0.8, 0.66))
        p.close()
        return p
    }
}

/// Tim lớn bung ra khi thích bài: tim trắng nảy lên, đổi đỏ, vòng sóng lan ra cùng các hạt nhỏ, rồi mờ dần.
final class HeartBurstView: UIView {
    private static let red = UIColor(red: 1, green: 0.1, blue: 0.27, alpha: 1)
    private let heart = CAShapeLayer()
    private let size: CGFloat

    static func play(in host: UIView, at center: CGPoint, size: CGFloat = 96) {
        let v = HeartBurstView(center: center, size: size)
        host.addSubview(v)
        v.run()
    }

    private init(center: CGPoint, size: CGFloat) {
        self.size = size
        super.init(frame: CGRect(x: center.x - size * 1.4, y: center.y - size * 1.4, width: size * 2.8, height: size * 2.8))
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    private var mid: CGPoint { return CGPoint(x: bounds.midX, y: bounds.midY) }

    private func run() {
        heart.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        heart.position = mid
        heart.path = HeartShape.path(in: heart.bounds).cgPath
        heart.fillColor = UIColor.white.cgColor
        heart.shadowColor = UIColor.black.cgColor
        heart.shadowOpacity = 0.25
        heart.shadowRadius = 8
        heart.shadowOffset = .zero
        heart.opacity = 0
        layer.addSublayer(heart)

        if UIAccessibility.isReduceMotionEnabled {
            heart.fillColor = HeartBurstView.red.cgColor
            heart.opacity = 1
            UIView.animate(withDuration: 0.4, delay: 0.6, options: [], animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
            return
        }

        // 1) Tim trắng nảy lên bằng lò xo.
        heart.opacity = 1
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.25
        pop.toValue = 1
        pop.mass = 1
        pop.stiffness = 260
        pop.damping = 12
        pop.duration = pop.settlingDuration
        heart.add(pop, forKey: "pop")
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = 1
        appear.duration = 0.1
        heart.add(appear, forKey: "appear")

        // 2) Đổi sang đỏ kèm một nhịp phồng, rồi vòng sóng và hạt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.turnRed() }
        // 3) Mờ dần, hơi nhỏ lại.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in self?.fadeOut() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.removeFromSuperview() }
    }

    private func turnRed() {
        let color = CABasicAnimation(keyPath: "fillColor")
        color.fromValue = UIColor.white.cgColor
        color.toValue = HeartBurstView.red.cgColor
        color.duration = 0.2
        heart.fillColor = HeartBurstView.red.cgColor
        heart.add(color, forKey: "color")

        let beat = CAKeyframeAnimation(keyPath: "transform.scale")
        beat.values = [1, 1.18, 1]
        beat.keyTimes = [0, 0.4, 1]
        beat.duration = 0.35
        beat.timingFunction = CAMediaTimingFunction(name: .easeOut)
        heart.add(beat, forKey: "beat")

        // Vòng sóng đỏ lan ra.
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        ring.position = mid
        ring.path = UIBezierPath(ovalIn: ring.bounds).cgPath
        ring.fillColor = nil
        ring.strokeColor = HeartBurstView.red.cgColor
        ring.lineWidth = 3
        ring.opacity = 0
        layer.insertSublayer(ring, below: heart)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.75
        grow.toValue = 1.7
        grow.duration = 0.6
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.9, 0.7, 0]
        fade.keyTimes = [0, 0.5, 1]
        fade.duration = 0.6
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.6
        ring.add(group, forKey: "ring")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { ring.removeFromSuperlayer() }

        // Hạt nhỏ bắn ra theo vòng tròn.
        let count = 12
        let palette: [UIColor] = [HeartBurstView.red, UIColor(red: 1, green: 0.55, blue: 0.65, alpha: 1), .white]
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat(i % 3) * 0.08
            let radius = CGFloat(3 + i % 3)
            let dot = CAShapeLayer()
            dot.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            dot.path = UIBezierPath(ovalIn: dot.bounds).cgPath
            dot.fillColor = palette[i % palette.count].cgColor
            let from = CGPoint(x: mid.x + cos(angle) * size * 0.55, y: mid.y + sin(angle) * size * 0.55)
            let reach = size * (0.95 + CGFloat(i % 4) * 0.12)
            let to = CGPoint(x: mid.x + cos(angle) * reach, y: mid.y + sin(angle) * reach)
            dot.position = to
            dot.opacity = 0
            layer.addSublayer(dot)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = from
            move.toValue = to
            move.timingFunction = CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1)
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1
            shrink.toValue = 0.2
            let out = CAKeyframeAnimation(keyPath: "opacity")
            out.values = [1, 1, 0]
            out.keyTimes = [0, 0.55, 1]
            let g = CAAnimationGroup()
            g.animations = [move, shrink, out]
            g.duration = 0.62
            dot.add(g, forKey: "dot")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) { dot.removeFromSuperlayer() }
        }
    }

    private func fadeOut() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 0.82
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [scale, fade]
        g.duration = 0.4
        g.timingFunction = CAMediaTimingFunction(name: .easeIn)
        heart.opacity = 0
        heart.transform = CATransform3DMakeScale(0.82, 0.82, 1)
        heart.add(g, forKey: "out")
    }
}
