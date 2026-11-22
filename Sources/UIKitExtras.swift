import UIKit

/// Nút nhún nhẹ khi chạm (spring), dùng cho mọi nút điều khiển.
class PressableButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            let pressed = isHighlighted
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 6,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.transform = pressed ? CGAffineTransform(scaleX: 0.86, y: 0.86) : CGAffineTransform.identity
            }, completion: nil)
        }
    }
}

/// View có nền chuyển màu.
final class GradientView: UIView {
    override class var layerClass: AnyClass { return CAGradientLayer.self }
    var gradientLayer: CAGradientLayer { return layer as! CAGradientLayer }
}

enum Haptics {
    static func tap() {
        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

extension UIImage {
    /// Màu trung bình của ảnh (thu nhỏ còn 1x1 điểm ảnh).
    func averageColor() -> UIColor? {
        guard let cg = self.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: space, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(red: CGFloat(pixel[0]) / 255.0, green: CGFloat(pixel[1]) / 255.0,
                       blue: CGFloat(pixel[2]) / 255.0, alpha: 1)
    }
}

extension UIImage {
    /// Màu nhấn của bài hát: tông màu của ảnh bìa, đẩy sáng và đậm lên để nổi trên nền tối.
    func songTone() -> UIColor? {
        guard let average = averageColor() else { return nil }
        var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &sat, brightness: &br, alpha: &a)
        return UIColor(hue: h, saturation: max(0.3, min(1, sat * 1.1)), brightness: 0.95, alpha: 1)
    }
}

extension UIImage {
    /// Độ sáng cảm nhận (0...1) của phần dưới ảnh, nơi dải làm mờ và các nút nằm.
    func bottomLuminance() -> CGFloat? {
        guard let cg = cgImage else { return nil }
        let top = Int(Double(cg.height) * 0.55)
        guard let part = cg.cropping(to: CGRect(x: 0, y: top, width: cg.width, height: cg.height - top)),
              let color = UIImage(cgImage: part).averageColor() else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

extension UIColor {
    /// Pha màu với màu khác theo tỉ lệ (0...1).
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}

extension UITableView {
    /// Cho các dòng đang hiện trượt vào lần lượt (hiệu ứng khi mở danh sách).
    func animateRowsIn() {
        layoutIfNeeded()
        let cells = visibleCells
        for (i, cell) in cells.enumerated() {
            cell.alpha = 0
            cell.transform = CGAffineTransform(translationX: 0, y: 24)
            UIView.animate(withDuration: 0.55, delay: 0.035 * Double(min(i, 12)), usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0.2, options: [.allowUserInteraction], animations: {
                cell.alpha = 1
                cell.transform = CGAffineTransform.identity
            }, completion: nil)
        }
    }
}

extension UIView {
    /// Hiệu ứng "bật" (dùng cho nút tim).
    func pop() {
        transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 8,
                       options: [.allowUserInteraction], animations: {
            self.transform = CGAffineTransform.identity
        }, completion: nil)
    }
}

/// Thông báo nhỏ nổi lên rồi tự biến mất.
enum Toast {
    static func show(_ text: String) {
        DispatchQueue.main.async {
            guard let window = (UIApplication.shared.delegate as? AppDelegate)?.window else { return }
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: Theme.blurStyle))
            blur.layer.cornerRadius = 20
            blur.clipsToBounds = true
            let label = UILabel()
            label.text = text
            label.font = Theme.bold(14)
            label.textColor = Theme.primaryText
            label.numberOfLines = 2
            label.textAlignment = .center
            let maxWidth = window.bounds.width - 80
            let size = label.sizeThatFits(CGSize(width: maxWidth, height: 200))
            let width = min(maxWidth, size.width) + 36
            let height = size.height + 24
            blur.frame = CGRect(x: (window.bounds.width - width) / 2, y: window.safeAreaInsets.top + 12,
                                width: width, height: height)
            label.frame = blur.contentView.bounds.insetBy(dx: 18, dy: 12)
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blur.contentView.addSubview(label)
            blur.alpha = 0
            blur.transform = CGAffineTransform(translationX: 0, y: -20).scaledBy(x: 0.9, y: 0.9)
            window.addSubview(blur)
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5,
                           options: [], animations: {
                blur.alpha = 1
                blur.transform = CGAffineTransform.identity
            }, completion: nil)
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
                blur.alpha = 0
                blur.transform = CGAffineTransform(translationX: 0, y: -12)
            }, completion: { _ in blur.removeFromSuperview() })
        }
    }
}
