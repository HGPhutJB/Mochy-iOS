import UIKit

/// Thanh tab nổi kính lỏng (liquid glass): nền mờ tự đổi sáng/tối theo nội dung phía sau, icon tự đổi màu,
/// "thấu kính" chọn tab trượt bằng lò xo và co giãn như giọt nước, chạm thì nảy, kéo ngón tay để lướt qua các tab.
/// Khi cuộn xuống thanh thu gọn thành viên tròn chỉ còn icon tab đang chọn.
final class FloatingTabBar: UIView {
    static let height: CGFloat = 58

    var onSelect: ((Int) -> Void)?
    var onTapWhileCollapsed: (() -> Void)?
    /// View nằm phía sau thanh, dùng để đo độ sáng nền.
    weak var backdrop: UIView?
    private(set) var selectedIndex = 0
    private(set) var collapsed = false

    private let glass = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let tint = UIView()
    private let sheen = CAGradientLayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let lens = UIView()
    private let lensRim = CAGradientLayer()
    private let lensRimMask = CAShapeLayer()
    private let lensSheen = CAGradientLayer()
    private var buttons: [PressableButton] = []
    private let badge = UIView()
    private var lightBackdrop: Bool?
    private var dragging = false
    private var dragCenterX: CGFloat = 0

    init(icons: [UIImage]) {
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 20
        layer.shadowOffset = CGSize(width: 0, height: 8)

        glass.clipsToBounds = true
        addSubview(glass)
        tint.isUserInteractionEnabled = false
        glass.contentView.addSubview(tint)
        sheen.colors = [UIColor(white: 1, alpha: 0.16).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        sheen.startPoint = CGPoint(x: 0.5, y: 0)
        sheen.endPoint = CGPoint(x: 0.5, y: 0.7)

        lens.isUserInteractionEnabled = false
        lens.layer.shadowColor = UIColor.black.cgColor
        lens.layer.shadowOpacity = 0.22
        lens.layer.shadowRadius = 8
        lens.layer.shadowOffset = CGSize(width: 0, height: 3)
        lensSheen.colors = [UIColor(white: 1, alpha: 0.5).cgColor, UIColor(white: 1, alpha: 0.04).cgColor, UIColor(white: 1, alpha: 0.12).cgColor]
        lensSheen.locations = [0, 0.55, 1]
        lensSheen.startPoint = CGPoint(x: 0.5, y: 0)
        lensSheen.endPoint = CGPoint(x: 0.5, y: 1)
        lensRim.colors = [UIColor(white: 1, alpha: 0.85).cgColor, UIColor(white: 1, alpha: 0.12).cgColor, UIColor(white: 1, alpha: 0.5).cgColor]
        lensRim.startPoint = CGPoint(x: 0.2, y: 0)
        lensRim.endPoint = CGPoint(x: 0.8, y: 1)
        lensRimMask.fillColor = UIColor.clear.cgColor
        lensRimMask.strokeColor = UIColor.black.cgColor
        lensRimMask.lineWidth = 1.4
        lensRim.mask = lensRimMask
        glass.contentView.addSubview(lens)

        rim.colors = [UIColor(white: 1, alpha: 0.5).cgColor, UIColor(white: 1, alpha: 0.06).cgColor, UIColor(white: 1, alpha: 0.28).cgColor]
        rim.startPoint = CGPoint(x: 0.1, y: 0)
        rim.endPoint = CGPoint(x: 0.9, y: 1)
        rimMask.fillColor = UIColor.clear.cgColor
        rimMask.strokeColor = UIColor.black.cgColor
        rimMask.lineWidth = 1.2
        rim.mask = rimMask

        for (i, icon) in icons.enumerated() {
            let button = PressableButton(type: .custom)
            button.setImage(icon.withRenderingMode(.alwaysTemplate), for: .normal)
            button.tag = i
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(touchDown(_:)), for: .touchDown)
            glass.contentView.addSubview(button)
            buttons.append(button)
        }
        badge.backgroundColor = Theme.accent
        badge.layer.cornerRadius = 4.5
        badge.isHidden = true
        glass.contentView.addSubview(badge)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.cancelsTouchesInView = true
        addGestureRecognizer(pan)
        applyLook(light: !Theme.isDark, animated: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Bố cục

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        glass.layer.cornerRadius = bounds.height / 2
        tint.frame = glass.bounds
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2)
        layer.shadowPath = path.cgPath
        layoutItems()
    }

    private func itemFrame(_ index: Int) -> CGRect {
        let count = max(1, buttons.count)
        let width = bounds.width / CGFloat(count)
        return CGRect(x: width * CGFloat(index), y: 0, width: width, height: bounds.height)
    }

    private func lensSize() -> CGSize {
        if collapsed { return CGSize(width: bounds.height - 10, height: bounds.height - 10) }
        let item = itemFrame(0)
        return CGSize(width: item.width - 8, height: bounds.height - 10)
    }

    private func layoutItems() {
        for (i, button) in buttons.enumerated() {
            if collapsed {
                button.frame = bounds
                button.alpha = i == selectedIndex ? 1 : 0
            } else {
                button.frame = itemFrame(i)
                button.alpha = 1
            }
        }
        if !dragging {
            let size = lensSize()
            lens.bounds = CGRect(origin: .zero, size: size)
            lens.center = CGPoint(x: collapsed ? bounds.midX : itemFrame(selectedIndex).midX, y: bounds.midY)
            lens.alpha = collapsed ? 0 : 1
            layoutLensLayers()
        }
        if let last = buttons.last {
            badge.frame = CGRect(x: last.frame.midX + 6, y: last.frame.minY + 12, width: 9, height: 9)
            badge.alpha = collapsed ? 0 : 1
        }
    }

    private func layoutLensLayers() {
        let b = lens.bounds
        lens.layer.cornerRadius = b.height / 2
        lens.layer.shadowPath = UIBezierPath(roundedRect: b, cornerRadius: b.height / 2).cgPath
    }

    // MARK: - Giao diện sáng/tối theo nền

    private var inkColor: UIColor { return lightBackdrop == true ? UIColor(white: 0.08, alpha: 1) : UIColor.white }

    private func applyLook(light: Bool, animated: Bool) {
        lightBackdrop = light
        let changes = {
            self.glass.effect = UIBlurEffect(style: light ? .extraLight : .dark)
            self.tint.backgroundColor = light ? UIColor(white: 1, alpha: 0.18) : UIColor(white: 0, alpha: 0.16)
            self.lens.backgroundColor = light ? UIColor(white: 0, alpha: 0.09) : UIColor(white: 1, alpha: 0.14)
            self.updateTints()
        }
        if animated { UIView.animate(withDuration: 0.35, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: changes, completion: nil) } else { changes() }
        layer.shadowOpacity = light ? 0.16 : 0.38
    }

    private func updateTints() {
        for (i, button) in buttons.enumerated() {
            button.tintColor = i == selectedIndex ? Theme.accent : inkColor.withAlphaComponent(0.78)
        }
    }

    /// Đo độ sáng phần nền ngay phía sau thanh; gọi định kỳ khi nội dung cuộn hoặc đổi tab.
    func adaptToBackdrop() {
        guard let host = backdrop, host.bounds.width > 0, bounds.width > 0, window != nil else { return }
        let rect = host.convert(bounds, from: self).intersection(host.bounds)
        guard rect.width > 1, rect.height > 1,
              let snap = host.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return }
        let w = 24, h = 6
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // Chỉ chụp đúng dải nằm sau thanh (bằng GPU) rồi thu nhỏ, thay vì vẽ lại cả màn hình.
        snap.frame = CGRect(origin: .zero, size: rect.size)
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(w) / rect.width, y: -CGFloat(h) / rect.height)
        UIGraphicsPushContext(ctx)
        snap.drawHierarchy(in: snap.bounds, afterScreenUpdates: false)
        UIGraphicsPopContext()
        var total: CGFloat = 0
        var alphaSum: CGFloat = 0
        for i in 0..<(w * h) {
            total += 0.299 * CGFloat(pixels[i * 4]) + 0.587 * CGFloat(pixels[i * 4 + 1]) + 0.114 * CGFloat(pixels[i * 4 + 2])
            alphaSum += CGFloat(pixels[i * 4 + 3])
        }
        // Chụp không được (ảnh trong suốt) thì đừng coi là "đen"; dùng chế độ giao diện của app.
        let luminance: CGFloat = alphaSum / CGFloat(w * h) / 255 < 0.5 ? (Theme.isDark ? 0 : 1) : total / CGFloat(w * h) / 255
        // Có độ trễ để không nhấp nháy quanh ngưỡng.
        let wantLight = lightBackdrop == true ? luminance > 0.52 : luminance > 0.64
        if wantLight != lightBackdrop { applyLook(light: wantLight, animated: true) }
    }

    func setBadge(visible: Bool) {
        if badge.isHidden == !visible { return }
        if visible {
            badge.isHidden = false
            badge.pop()
        } else {
            badge.isHidden = true
        }
    }

    // MARK: - Thu gọn khi cuộn

    func setCollapsed(_ value: Bool, animated: Bool) {
        guard value != collapsed else { return }
        collapsed = value
        let changes = { self.layoutItems() }
        if animated {
            // Chạy cùng nhịp với thay đổi bề rộng do ràng buộc ở bên ngoài.
            UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.4,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: changes, completion: nil)
        } else {
            changes()
        }
    }

    // MARK: - Chọn tab

    func select(_ index: Int, animated: Bool) {
        guard index >= 0 && index < buttons.count else { return }
        let changed = index != selectedIndex
        selectedIndex = index
        if collapsed {
            for (i, b) in buttons.enumerated() { b.alpha = i == index ? 1 : 0 }
            updateTints()
            return
        }
        let target = CGPoint(x: itemFrame(index).midX, y: bounds.midY)
        if animated {
            moveLens(to: target, stretch: changed)
            if changed { bounce(buttons[index]) }
            UIView.animate(withDuration: 0.3) { self.updateTints() }
        } else {
            lens.center = target
            updateTints()
        }
    }

    /// Thấu kính trượt bằng lò xo; giữa chừng bị kéo dãn theo chiều ngang, tới nơi thì co lại và nảy.
    private func moveLens(to point: CGPoint, stretch: Bool) {
        UIView.animate(withDuration: 0.62, delay: 0, usingSpringWithDamping: 0.68, initialSpringVelocity: 0.8,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.lens.center = point
        }, completion: nil)
        guard stretch else { return }
        UIView.animateKeyframes(withDuration: 0.62, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.3) {
                self.lens.transform = CGAffineTransform(scaleX: 1.38, y: 0.86)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.3) {
                self.lens.transform = CGAffineTransform(scaleX: 0.94, y: 1.1)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.4) {
                self.lens.transform = .identity
            }
        }, completion: nil)
    }

    private func bounce(_ button: UIButton) {
        button.imageView?.transform = CGAffineTransform(scaleX: 0.62, y: 0.62)
        UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.38, initialSpringVelocity: 9,
                       options: [.allowUserInteraction], animations: {
            button.imageView?.transform = .identity
        }, completion: nil)
    }

    @objc private func touchDown(_ sender: UIButton) {
        guard !collapsed else { return }
        // Chạm xuống: thấu kính phồng lên như giọt nước dưới ngón tay.
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 4,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.lens.transform = CGAffineTransform(scaleX: 1.14, y: 1.12)
        }, completion: nil)
    }

    @objc private func tapped(_ sender: UIButton) {
        Haptics.tap()
        if collapsed {
            onTapWhileCollapsed?()
            return
        }
        if sender.tag == selectedIndex {
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 6,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: { self.lens.transform = .identity }, completion: nil)
            bounce(sender)
        }
        onSelect?(sender.tag)
    }

    // MARK: - Kéo để lướt qua các tab

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        guard !collapsed else { return }
        let x = min(max(g.location(in: self).x, itemFrame(0).midX), itemFrame(buttons.count - 1).midX)
        switch g.state {
        case .began:
            dragging = true
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 3,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.lens.transform = CGAffineTransform(scaleX: 1.18, y: 1.14)
                self.lens.center = CGPoint(x: x, y: self.bounds.midY)
            }, completion: nil)
        case .changed:
            lens.center = CGPoint(x: x, y: bounds.midY)
            let width = bounds.width / CGFloat(buttons.count)
            let hover = min(buttons.count - 1, max(0, Int(x / width)))
            for (i, b) in buttons.enumerated() {
                b.tintColor = i == hover ? Theme.accent : inkColor.withAlphaComponent(0.78)
            }
        case .ended, .cancelled, .failed:
            dragging = false
            let width = bounds.width / CGFloat(buttons.count)
            let index = min(buttons.count - 1, max(0, Int(x / width)))
            let changed = index != selectedIndex
            if changed { Haptics.tap() }
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.5,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.lens.transform = .identity
                self.lens.center = CGPoint(x: self.itemFrame(index).midX, y: self.bounds.midY)
            }, completion: nil)
            if changed { bounce(buttons[index]) }
            selectedIndex = index
            updateTints()
            if changed { onSelect?(index) }
        default:
            break
        }
    }
}
