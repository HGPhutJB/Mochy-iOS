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

/// Tim lớn khi thích bài, dựng theo video mẫu (20 khung/giây):
/// 0–0,25 s tim trắng nhỏ xíu hiện ở trên rồi phóng to và trượt xuống giữa; 0,25–0,55 s giữ trắng;
/// 0,55 s bật đỏ phồng to kèm vòng mảnh lan ra và hạt li ti; 0,6–0,85 s co về ~65% và nhạt dần sang hồng;
/// 0,85–1,2 s ngả trắng, bay nhẹ lên và tan.
final class HeartBurstView: UIView {
    private static let red = UIColor(red: 1, green: 0.1, blue: 0.27, alpha: 1)
    private static let pink = UIColor(red: 1, green: 0.55, blue: 0.62, alpha: 1)
    private static let pale = UIColor(red: 1, green: 0.9, blue: 0.92, alpha: 1)
    private let heart = CAShapeLayer()
    private let size: CGFloat
    private let drop: CGFloat

    /// `center` là vị trí nghỉ của tim; tim xuất phát cao hơn một đoạn rồi trượt xuống.
    static func play(in host: UIView, at center: CGPoint, size: CGFloat? = nil) {
        let s = size ?? max(80, min(130, host.bounds.width * 0.3))
        let v = HeartBurstView(center: center, size: s)
        host.addSubview(v)
        v.run()
    }

    private init(center: CGPoint, size: CGFloat) {
        self.size = size
        self.drop = size * 0.55
        let side = size * 3
        super.init(frame: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
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
        heart.shadowOpacity = 0.3
        heart.shadowRadius = 10
        heart.shadowOffset = .zero
        layer.addSublayer(heart)

        if UIAccessibility.isReduceMotionEnabled {
            heart.fillColor = HeartBurstView.red.cgColor
            UIView.animate(withDuration: 0.4, delay: 0.7, options: [], animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
            return
        }

        // Pha 1 (0–0,25 s): nhỏ xíu → phóng to, trượt từ trên xuống vị trí nghỉ.
        let appear = CAAnimationGroup()
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.12
        scale.toValue = 1
        let move = CABasicAnimation(keyPath: "position.y")
        move.fromValue = mid.y - drop
        move.toValue = mid.y
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.08
        appear.animations = [scale, move]
        appear.duration = 0.27
        appear.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
        heart.add(appear, forKey: "appear")
        heart.add(fade, forKey: "fade")

        // Pha 2 (0,27–0,55 s): giữ trắng, hơi co lại như đang nén.
        let hold = CABasicAnimation(keyPath: "transform.scale")
        hold.fromValue = 1
        hold.toValue = 0.93
        hold.beginTime = CACurrentMediaTime() + 0.27
        hold.duration = 0.28
        hold.fillMode = .both
        hold.isRemovedOnCompletion = false
        heart.add(hold, forKey: "hold")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in self?.flash() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.removeFromSuperview() }
    }

    /// Pha 3 (0,55 s): bật đỏ phồng to, vòng mảnh + hạt, rồi co lại và nhạt dần.
    private func flash() {
        heart.removeAnimation(forKey: "hold")
        heart.fillColor = HeartBurstView.pale.cgColor
        heart.transform = CATransform3DMakeScale(0.62, 0.62, 1)
        heart.position = CGPoint(x: mid.x, y: mid.y - size * 0.1)
        heart.opacity = 0

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.93, 1.28, 1.1, 0.62]
        pop.keyTimes = [0, 0.12, 0.35, 1]
        pop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        let colors = CAKeyframeAnimation(keyPath: "fillColor")
        colors.values = [UIColor.white.cgColor, HeartBurstView.red.cgColor, HeartBurstView.red.cgColor, HeartBurstView.pink.cgColor, HeartBurstView.pale.cgColor]
        colors.keyTimes = [0, 0.06, 0.4, 0.7, 1]
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = mid.y
        rise.toValue = mid.y - size * 0.1
        rise.beginTime = 0.3
        rise.duration = 0.4
        rise.fillMode = .both
        let g = CAAnimationGroup()
        g.animations = [pop, colors, rise]
        g.duration = 0.7
        g.beginTime = CACurrentMediaTime()
        heart.add(g, forKey: "flash")

        let out = CABasicAnimation(keyPath: "opacity")
        out.fromValue = 1
        out.toValue = 0
        out.beginTime = CACurrentMediaTime() + 0.45
        out.duration = 0.25
        out.fillMode = .both
        heart.add(out, forKey: "out")

        // Vòng mảnh lan ra quanh tim.
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        ring.position = mid
        ring.path = UIBezierPath(ovalIn: ring.bounds).cgPath
        ring.fillColor = nil
        ring.strokeColor = HeartBurstView.red.cgColor
        ring.lineWidth = 1.6
        ring.opacity = 0
        layer.insertSublayer(ring, below: heart)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.85
        grow.toValue = 1.45
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.9, 0.55, 0]
        fade.keyTimes = [0, 0.5, 1]
        let rg = CAAnimationGroup()
        rg.animations = [grow, fade]
        rg.duration = 0.38
        rg.timingFunction = CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1)
        ring.add(rg, forKey: "ring")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ring.removeFromSuperlayer() }

        // Hạt li ti nằm trong và quanh vòng.
        let palette: [UIColor] = [HeartBurstView.red, HeartBurstView.pink, .white]
        for i in 0..<10 {
            let angle = CGFloat(i) / 10 * 2 * .pi + 0.2
            let r = CGFloat(1.5 + CGFloat(i % 3) * 0.7)
            let dot = CAShapeLayer()
            dot.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
            dot.path = UIBezierPath(ovalIn: dot.bounds).cgPath
            dot.fillColor = palette[i % 3].cgColor
            let from = CGPoint(x: mid.x + cos(angle) * size * 0.5, y: mid.y + sin(angle) * size * 0.5)
            let to = CGPoint(x: mid.x + cos(angle) * size * (0.7 + CGFloat(i % 3) * 0.08), y: mid.y + sin(angle) * size * (0.7 + CGFloat(i % 3) * 0.08))
            dot.position = to
            dot.opacity = 0
            layer.addSublayer(dot)
            let mv = CABasicAnimation(keyPath: "position")
            mv.fromValue = from
            mv.toValue = to
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values = [0.9, 0.9, 0]
            op.keyTimes = [0, 0.5, 1]
            let dg = CAAnimationGroup()
            dg.animations = [mv, op]
            dg.duration = 0.4
            dg.timingFunction = CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1)
            dot.add(dg, forKey: "dot")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { dot.removeFromSuperlayer() }
        }
    }
}
