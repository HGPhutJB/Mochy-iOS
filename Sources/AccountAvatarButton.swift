import UIKit

/// Nút tài khoản ở góc phải trang chủ (giống App Store): chưa đăng nhập hiện hình người kiểu iOS 16, đã đăng nhập hiện chữ cái đầu.
final class AccountAvatarButton: UIButton {
    static let size: CGFloat = 34

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: AccountAvatarButton.size, height: AccountAvatarButton.size))
        adjustsImageWhenHighlighted = true
        accessibilityLabel = "Tài khoản"
        widthAnchor.constraint(equalToConstant: AccountAvatarButton.size).isActive = true
        heightAnchor.constraint(equalToConstant: AccountAvatarButton.size).isActive = true
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .cloudStateChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func refresh() {
        let cloud = MochyCloud.shared
        let letter = cloud.isLoggedIn ? String((cloud.username ?? "?").prefix(1)).uppercased() : nil
        setImage(AccountAvatarButton.render(letter: letter), for: .normal)
    }

    static func render(letter: String?) -> UIImage {
        let s = size
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        return renderer.image { ctx in
            let c = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: s, height: s)
            c.saveGState()
            c.addEllipse(in: rect)
            c.clip()
            if let letter = letter {
                let colors = [UIColor(red: 1.0, green: 0.36, blue: 0.45, alpha: 1).cgColor, Theme.accent.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])
                }
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: s * 0.5, weight: .semibold),
                                                            .foregroundColor: UIColor.white]
                let size = (letter as NSString).size(withAttributes: attrs)
                (letter as NSString).draw(at: CGPoint(x: (s - size.width) / 2, y: (s - size.height) / 2), withAttributes: attrs)
            } else {
                // Nền xám nhạt + hình người (đầu tròn, vai bán nguyệt) như biểu tượng person.crop.circle.fill.
                (Theme.isDark ? UIColor(white: 0.30, alpha: 1) : UIColor(white: 0.84, alpha: 1)).setFill()
                c.fill(rect)
                (Theme.isDark ? UIColor(white: 0.62, alpha: 1) : UIColor(white: 0.62, alpha: 1)).setFill()
                UIBezierPath(ovalIn: CGRect(x: s * 0.31, y: s * 0.17, width: s * 0.38, height: s * 0.38)).fill()
                UIBezierPath(ovalIn: CGRect(x: s * 0.14, y: s * 0.60, width: s * 0.72, height: s * 0.70)).fill()
            }
            c.restoreGState()
        }
    }
}
