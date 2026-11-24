import UIKit

/// Nút tròn tải xuống kiểu App Store: mũi tên tải → vòng tiến độ có nút dừng ở giữa → dấu ✓ khi đã tải đủ.
final class DownloadRingButton: UIControl {
    enum Phase: Equatable {
        case idle
        case active(Double)
        case done
    }

    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private let stop = CAShapeLayer()
    private let icon = UIImageView()
    private(set) var phase: Phase = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 22
        backgroundColor = Theme.chip
        for l in [track, arc] {
            l.fillColor = UIColor.clear.cgColor
            l.lineWidth = 2.6
            l.lineCap = .round
            l.opacity = 0
            layer.addSublayer(l)
        }
        track.strokeColor = Theme.accent.withAlphaComponent(0.25).cgColor
        arc.strokeColor = Theme.accent.cgColor
        arc.strokeEnd = 0
        stop.fillColor = Theme.accent.cgColor
        stop.opacity = 0
        layer.addSublayer(stop)
        icon.contentMode = .center
        icon.tintColor = Theme.accent
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        icon.image = Icons.download(22)
        addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let ringPath = UIBezierPath(arcCenter: c, radius: bounds.width / 2 - 5, startAngle: -CGFloat.pi / 2,
                                    endAngle: CGFloat.pi * 1.5, clockwise: true).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [track, arc] { l.frame = bounds; l.path = ringPath }
        stop.frame = bounds
        stop.path = UIBezierPath(roundedRect: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10), cornerRadius: 2.5).cgPath
        CATransaction.commit()
        icon.frame = bounds
    }

    func set(_ new: Phase) {
        guard new != phase else { return }
        let old = phase
        phase = new
        switch new {
        case .idle:
            arc.removeAnimation(forKey: "spin")
            fade(track, 0); fade(arc, 0); fade(stop, 0)
            swap(Icons.download(22))
        case .active(let p):
            if case .active = old {} else {
                fade(track, 1); fade(arc, 1); fade(stop, 1)
                icon.alpha = 0
            }
            arc.strokeEnd = CGFloat(max(0.05, min(1, p)))
            if p < 0.02 {
                if arc.animation(forKey: "spin") == nil {
                    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                    spin.fromValue = 0
                    spin.toValue = Double.pi * 2
                    spin.duration = 1.0
                    spin.repeatCount = .infinity
                    arc.add(spin, forKey: "spin")
                }
            } else {
                arc.removeAnimation(forKey: "spin")
            }
        case .done:
            arc.removeAnimation(forKey: "spin")
            fade(track, 0); fade(arc, 0); fade(stop, 0)
            swap(Icons.check(20))
        }
    }

    /// Cập nhật tiến độ liên tục mà không phá hoạt ảnh khi vẫn đang tải.
    func setProgress(_ p: Double) {
        if case .active = phase {
            arc.strokeEnd = CGFloat(max(0.05, min(1, p)))
            if p >= 0.02 { arc.removeAnimation(forKey: "spin") }
        } else {
            set(.active(p))
        }
    }

    private func fade(_ l: CALayer, _ to: Float) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = l.presentation()?.opacity ?? l.opacity
        a.toValue = to
        a.duration = 0.2
        l.opacity = to
        l.add(a, forKey: "fade")
    }

    private func swap(_ image: UIImage) {
        icon.image = image
        icon.alpha = 0
        icon.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.6, options: [], animations: {
            self.icon.alpha = 1
            self.icon.transform = CGAffineTransform.identity
        }, completion: nil)
    }

    @objc private func down() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }, completion: nil)
    }

    @objc private func up() {
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.transform = CGAffineTransform.identity
        }, completion: nil)
    }
}
