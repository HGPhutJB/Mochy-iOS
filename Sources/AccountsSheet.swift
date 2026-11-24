import UIKit

/// Nút dịch vụ nhạc trong bảng liên kết: có trạng thái "đang kết nối" (vòng xoay) và "đã kết nối" (dấu ✓ tự vẽ).
final class AccountButton: UIControl {
    enum Phase { case idle, busy, ok }

    let service: MusicService
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let statusHost = UIView()
    private let ring = CAShapeLayer()
    private let check = CAShapeLayer()
    private let busyLabel = UILabel()
    private let okLabel = UILabel()
    private(set) var phase: Phase = .idle

    private var fg: UIColor {
        switch service {
        case .appleMusic: return Theme.isDark ? UIColor.black : UIColor.white
        case .spotify: return UIColor(white: 0, alpha: 0.85)
        default: return UIColor.white
        }
    }

    private var bg: UIColor {
        if service == .appleMusic { return Theme.isDark ? UIColor.white : UIColor.black }
        return service.brand
    }

    init(service: MusicService) {
        self.service = service
        super.init(frame: .zero)
        backgroundColor = bg
        layer.cornerRadius = 12
        icon.image = Icons.music(20)
        icon.tintColor = fg
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        addSubview(icon)

        titleLabel.font = UIFont.systemFont(ofSize: 14.5, weight: .semibold)
        titleLabel.textColor = fg
        titleLabel.textAlignment = .center
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)

        statusHost.isUserInteractionEnabled = false
        statusHost.alpha = 0
        statusHost.transform = CGAffineTransform(translationX: 0, y: 9)
        addSubview(statusHost)
        let circle = UIBezierPath(arcCenter: CGPoint(x: 8, y: 8), radius: 7, startAngle: -CGFloat.pi / 2,
                                  endAngle: CGFloat.pi, clockwise: true)
        ring.path = circle.cgPath
        ring.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = fg.cgColor
        ring.lineWidth = 2
        ring.lineCap = .round
        statusHost.layer.addSublayer(ring)
        let tick = UIBezierPath()
        tick.move(to: CGPoint(x: 3.2, y: 8.6))
        tick.addLine(to: CGPoint(x: 6.6, y: 11.8))
        tick.addLine(to: CGPoint(x: 12.8, y: 4.8))
        check.path = tick.cgPath
        check.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        check.fillColor = UIColor.clear.cgColor
        check.strokeColor = fg.cgColor
        check.lineWidth = 2.5
        check.lineCap = .round
        check.lineJoin = .round
        check.strokeEnd = 0
        statusHost.layer.addSublayer(check)
        for l in [busyLabel, okLabel] {
            l.font = UIFont.systemFont(ofSize: 14.5, weight: .semibold)
            l.textColor = fg
            statusHost.addSubview(l)
        }
        busyLabel.text = "Đang kết nối…"
        okLabel.text = "Đã kết nối"
        okLabel.alpha = 0
        okLabel.transform = CGAffineTransform(translationX: 0, y: 8)

        addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        refreshTitle()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshTitle() {
        if AccountSync.shared.isLinked(service), let name = AccountSync.shared.accountName(service) {
            titleLabel.text = "\(service.title) · \(name)"
        } else {
            titleLabel.text = "Liên kết \(service.title)"
        }
        accessibilityLabel = titleLabel.text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = CGRect(x: 16, y: (bounds.height - 20) / 2, width: 20, height: 20)
        titleLabel.frame = CGRect(x: 46, y: 0, width: bounds.width - 92, height: bounds.height)
        let busyW = ceil(busyLabel.sizeThatFits(CGSize(width: 200, height: 30)).width)
        let okW = ceil(okLabel.sizeThatFits(CGSize(width: 200, height: 30)).width)
        let textW = max(busyW, okW)
        let total = 16 + 8 + textW
        statusHost.bounds = CGRect(x: 0, y: 0, width: total, height: 20)
        statusHost.center = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.frame = CGRect(x: 0, y: 2, width: 16, height: 16)
        check.frame = CGRect(x: 0, y: 2, width: 16, height: 16)
        busyLabel.frame = CGRect(x: 24, y: 0, width: textW, height: 20)
        okLabel.frame = CGRect(x: 24, y: 0, width: textW, height: 20)
    }

    func setPhase(_ new: Phase) {
        guard new != phase else { return }
        let old = phase
        phase = new
        let spring = UIView.AnimationOptions.allowUserInteraction
        switch new {
        case .busy:
            startSpin()
            ring.opacity = 1
            ring.transform = CATransform3DIdentity
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.3, options: [spring], animations: {
                self.titleLabel.alpha = 0
                self.titleLabel.transform = CGAffineTransform(translationX: 0, y: -9)
                self.statusHost.alpha = 1
                self.statusHost.transform = CGAffineTransform.identity
                self.busyLabel.alpha = 1
                self.busyLabel.transform = CGAffineTransform.identity
                self.okLabel.alpha = 0
            }, completion: nil)
        case .ok:
            ring.removeAnimation(forKey: "spin")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.2
            ring.opacity = 0
            ring.add(fade, forKey: "fade")
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0; draw.toValue = 1; draw.duration = 0.4; draw.beginTime = CACurrentMediaTime() + 0.1
            draw.fillMode = .backwards
            draw.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            check.strokeEnd = 1
            check.add(draw, forKey: "draw")
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.3, options: [spring], animations: {
                self.busyLabel.alpha = 0
                self.busyLabel.transform = CGAffineTransform(translationX: 0, y: -8)
                self.okLabel.alpha = 1
                self.okLabel.transform = CGAffineTransform.identity
            }, completion: nil)
        case .idle:
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.3, options: [spring], animations: {
                self.titleLabel.alpha = 1
                self.titleLabel.transform = CGAffineTransform.identity
                self.statusHost.alpha = 0
                self.statusHost.transform = CGAffineTransform(translationX: 0, y: 9)
            }, completion: { _ in
                if self.phase == .idle {
                    self.check.removeAllAnimations()
                    self.check.strokeEnd = 0
                    self.ring.removeAllAnimations()
                    self.busyLabel.alpha = 1
                    self.busyLabel.transform = CGAffineTransform.identity
                    self.okLabel.alpha = 0
                    self.okLabel.transform = CGAffineTransform(translationX: 0, y: 8)
                }
            })
            _ = old
        }
    }

    private func startSpin() {
        check.removeAllAnimations()
        check.strokeEnd = 0
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 0.7
        spin.repeatCount = .infinity
        ring.add(spin, forKey: "spin")
    }

    @objc private func down() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.transform = self.transform.scaledBy(x: 0.96, y: 0.93)
        }, completion: nil)
    }

    @objc private func up() {
        // Trả về đúng vị trí hiện tại (không thay đổi dịch chuyển dọc do hoạt ảnh chọn).
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.6,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.transform = CGAffineTransform(translationX: 0, y: self.transform.ty)
        }, completion: nil)
    }
}

/// Bảng "Liên kết tài khoản nhạc" (phần tử #402): các nút lò xo vào lần lượt; bấm một nút thì nó trượt ra giữa
/// kèm vòng xoay, các nút còn lại gấp lại và mờ đi; xong hiện dấu ✓ rồi mọi thứ bật trở lại.
final class AccountsSheetViewController: UIViewController {
    private let dim = UIView()
    private let card = UIView()
    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private let stack = UIView()
    private var buttons: [AccountButton] = []
    private let syncButton = UIButton(type: .system)
    private let removeButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var picking = false
    private var entered = false
    private let rowHeight: CGFloat = 46
    private let rowGap: CGFloat = 10
    private let services = MusicService.allCases
    private var reduce: Bool { return UIAccessibility.isReduceMotionEnabled }

    static func present(from presenter: UIViewController) {
        let vc = AccountsSheetViewController()
        var top = presenter
        while let next = top.presentedViewController { top = next }
        top.present(vc, animated: false, completion: nil)
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.clear
        dim.frame = view.bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor(white: 0, alpha: 0.5)
        dim.alpha = 0
        view.addSubview(dim)
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeTapped)))

        card.backgroundColor = M3.surfaceHigh
        card.layer.cornerRadius = 28
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.35
        card.layer.shadowRadius = 30
        card.layer.shadowOffset = CGSize(width: 0, height: 14)
        card.alpha = 0
        view.addSubview(card)

        titleLabel.text = "Liên kết tài khoản nhạc"
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        card.addSubview(titleLabel)
        noteLabel.text = "Đăng nhập để Mochy tự tạo playlist \"Bài hát đã thích\" và các playlist của bạn, ảnh bìa là biểu tượng dịch vụ. Tự đồng bộ mỗi khi mở app."
        noteLabel.font = UIFont.systemFont(ofSize: 13)
        noteLabel.textColor = Theme.secondaryText
        noteLabel.numberOfLines = 0
        card.addSubview(noteLabel)
        card.addSubview(stack)

        for (i, s) in services.enumerated() {
            let b = AccountButton(service: s)
            b.tag = i
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            b.alpha = 0
            b.transform = CGAffineTransform(translationX: 0, y: 16).scaledBy(x: 0.94, y: 0.94)
            stack.addSubview(b)
            buttons.append(b)
        }
        for (b, title) in [(syncButton, "Đồng bộ ngay"), (removeButton, "Ngắt kết nối"), (closeButton, "Xong")] {
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            b.setTitleColor(M3.primary, for: .normal)
            card.addSubview(b)
        }
        syncButton.addTarget(self, action: #selector(syncTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        updateFooter()
    }

    private func updateFooter() {
        let linked = !AccountSync.shared.linkedServices.isEmpty
        syncButton.isHidden = !linked
        removeButton.isHidden = !linked
        buttons.forEach { $0.refreshTitle() }
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(340, view.bounds.width - 32)
        let pad: CGFloat = 24
        let inner = width - 2 * pad
        titleLabel.frame = CGRect(x: pad, y: 24, width: inner, height: 28)
        let nH = noteLabel.sizeThatFits(CGSize(width: inner, height: 1000)).height
        noteLabel.frame = CGRect(x: pad, y: 58, width: inner, height: nH)
        let stackTop = 58 + nH + 18
        let stackH = CGFloat(services.count) * rowHeight + CGFloat(services.count - 1) * rowGap
        stack.frame = CGRect(x: pad, y: stackTop, width: inner, height: stackH)
        if !picking {
            for (i, b) in buttons.enumerated() {
                let t = b.transform
                b.transform = CGAffineTransform.identity
                b.frame = CGRect(x: 0, y: CGFloat(i) * (rowHeight + rowGap), width: inner, height: rowHeight)
                b.transform = t
            }
        }
        let footY = stackTop + stackH + 12
        let linked = !AccountSync.shared.linkedServices.isEmpty
        syncButton.frame = CGRect(x: pad - 8, y: footY, width: 110, height: 40)
        removeButton.frame = CGRect(x: pad - 8 + 110, y: footY, width: 110, height: 40)
        closeButton.sizeToFit()
        closeButton.frame = CGRect(x: width - pad - max(60, closeButton.bounds.width + 16) + 8, y: footY,
                                   width: max(60, closeButton.bounds.width + 16), height: 40)
        _ = linked
        let height = footY + 40 + 14
        card.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        card.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIView.animate(withDuration: 0.2) { self.dim.alpha = 1 }
        card.transform = CGAffineTransform(translationX: 0, y: 24).scaledBy(x: 0.94, y: 0.94)
        UIView.animate(withDuration: reduce ? 0.01 : 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: [], animations: {
            self.card.alpha = 1
            self.card.transform = CGAffineTransform.identity
        }, completion: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !entered else { return }
        entered = true
        for (i, b) in buttons.enumerated() {
            UIView.animate(withDuration: reduce ? 0.01 : 0.7, delay: reduce ? 0 : Double(i) * 0.07 + 0.08, usingSpringWithDamping: 0.62,
                           initialSpringVelocity: 0.2, options: [.allowUserInteraction], animations: {
                b.alpha = 1
                b.transform = CGAffineTransform.identity
            }, completion: nil)
        }
    }

    // MARK: Hành động

    @objc private func closeTapped() {
        guard !picking else { return }
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn], animations: {
            self.card.alpha = 0
            self.card.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.94, y: 0.94)
            self.dim.alpha = 0
        }, completion: { _ in
            self.dismiss(animated: false, completion: nil)
        })
    }

    @objc private func syncTapped() {
        AccountSync.shared.syncAll(manual: true)
    }

    @objc private func removeTapped() {
        let linked = AccountSync.shared.linkedServices
        guard !linked.isEmpty else { return }
        let sheet = UIAlertController(title: "Ngắt kết nối", message: "Các playlist đã tạo vẫn được giữ lại trong thư viện.", preferredStyle: .actionSheet)
        for s in linked {
            sheet.addAction(UIAlertAction(title: s.title, style: .destructive) { [weak self] _ in
                AccountSync.shared.disconnect(s)
                Toast.show("Đã ngắt kết nối \(s.title)")
                self?.updateFooter()
            })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = removeButton
            pop.sourceRect = removeButton.bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    @objc private func tapped(_ sender: AccountButton) {
        guard !picking else { return }
        let s = sender.service
        if AccountSync.shared.isLinked(s) {
            let sheet = UIAlertController(title: s.title, message: AccountSync.shared.accountName(s), preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Đồng bộ ngay", style: .default) { _ in
                AccountSync.shared.syncSoon(s)
            })
            let relabel: String = s.isLinkBased ? "Thêm link playlist…" : (s == .spotify ? "Đăng nhập lại" : "Đổi tài khoản…")
            sheet.addAction(UIAlertAction(title: relabel, style: .default) { [weak self] _ in
                self?.pick(sender)
            })
            sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = sender
                pop.sourceRect = sender.bounds
            }
            present(sheet, animated: true, completion: nil)
            return
        }
        pick(sender)
    }

    private func pick(_ button: AccountButton) {
        guard !picking, let i = buttons.firstIndex(where: { $0 === button }) else { return }
        picking = true
        let mid = (stack.bounds.height - rowHeight) / 2
        for (k, o) in buttons.enumerated() {
            let top = CGFloat(k) * (rowHeight + rowGap)
            if k == i {
                let y = mid - top
                UIView.animate(withDuration: reduce ? 0.01 : 0.6, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.2,
                               options: [], animations: {
                    o.transform = CGAffineTransform(translationX: 0, y: y)
                }, completion: nil)
                stack.bringSubviewToFront(o)
            } else {
                let y = (mid - top) * 0.55
                UIView.animate(withDuration: reduce ? 0.01 : 0.5, delay: reduce ? 0 : Double(abs(k - i)) * 0.045, options: [.curveEaseOut], animations: {
                    o.alpha = 0
                    o.transform = CGAffineTransform(translationX: 0, y: y).scaledBy(x: 0.9, y: 0.9)
                }, completion: nil)
                o.isUserInteractionEnabled = false
            }
        }
        button.setPhase(.busy)
        let started = Date()
        AccountSync.shared.connect(button.service, from: self) { [weak self] result in
            guard let self = self else { return }
            let wait = max(0, 1.0 - Date().timeIntervalSince(started))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                switch result {
                case .success:
                    button.refreshTitle()
                    button.setPhase(.ok)
                    DispatchQueue.main.asyncAfter(deadline: .now() + (self.reduce ? 0.8 : 1.2)) { self.restore(picked: i) }
                case .failure(let e):
                    if !e.cancelled { Toast.show(e.message) }
                    self.restore(picked: i)
                }
            }
        }
    }

    private func restore(picked i: Int) {
        let button = buttons[i]
        button.setPhase(.idle)
        button.refreshTitle()
        for (k, o) in buttons.enumerated() {
            let d = Double(max(0, abs(k - i) - 1)) * 0.05
            UIView.animate(withDuration: reduce ? 0.01 : 0.6, delay: reduce ? 0 : d, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.2,
                           options: [.allowUserInteraction], animations: {
                o.alpha = 1
                o.transform = CGAffineTransform.identity
            }, completion: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0.05 : 0.8)) {
            self.buttons.forEach { $0.isUserInteractionEnabled = true }
            self.picking = false
            self.updateFooter()
        }
    }
}
