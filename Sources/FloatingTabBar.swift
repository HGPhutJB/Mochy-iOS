import UIKit

/// Thanh tab nổi dạng viên thuốc (như Mochy Music): nền mờ, ô sáng trượt theo tab đang chọn bằng hiệu ứng lò xo.
final class FloatingTabBar: UIView {
    static let height: CGFloat = 58

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: Theme.blurStyle))
    private let highlight = UIView()
    private var buttons: [PressableButton] = []
    private let badge = UIView()

    init(icons: [UIImage]) {
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Theme.isDark ? 0.5 : 0.18
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 6)

        blur.clipsToBounds = true
        addSubview(blur)
        highlight.backgroundColor = Theme.chip
        blur.contentView.addSubview(highlight)

        for (i, icon) in icons.enumerated() {
            let button = PressableButton(type: .custom)
            button.setImage(icon, for: .normal)
            button.tag = i
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            blur.contentView.addSubview(button)
            buttons.append(button)
        }
        badge.backgroundColor = Theme.accent
        badge.layer.cornerRadius = 4.5
        badge.isHidden = true
        blur.contentView.addSubview(badge)
        updateTints()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        blur.layer.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        layoutItems()
    }

    private func itemFrame(_ index: Int) -> CGRect {
        let count = max(1, buttons.count)
        let width = bounds.width / CGFloat(count)
        return CGRect(x: width * CGFloat(index), y: 0, width: width, height: bounds.height)
    }

    private func layoutItems() {
        for (i, button) in buttons.enumerated() {
            button.frame = itemFrame(i)
        }
        highlight.frame = itemFrame(selectedIndex).insetBy(dx: 6, dy: 6)
        highlight.layer.cornerRadius = highlight.bounds.height / 2
        if let last = buttons.last {
            badge.frame = CGRect(x: last.frame.midX + 6, y: last.frame.minY + 12, width: 9, height: 9)
        }
    }

    private func updateTints() {
        for (i, button) in buttons.enumerated() {
            button.tintColor = i == selectedIndex ? Theme.primaryText : Theme.secondaryText
        }
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

    func select(_ index: Int, animated: Bool) {
        guard index >= 0 && index < buttons.count else { return }
        selectedIndex = index
        let target = itemFrame(index).insetBy(dx: 6, dy: 6)
        let changes = {
            self.highlight.frame = target
            self.updateTints()
        }
        if animated {
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.6,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: changes, completion: nil)
        } else {
            changes()
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        Haptics.tap()
        onSelect?(sender.tag)
    }
}
