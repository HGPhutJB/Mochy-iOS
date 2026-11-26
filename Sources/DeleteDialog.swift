import UIKit

/// Biểu tượng thùng rác vẽ bằng lớp: nắp lật mở, tài liệu rơi vào, nắp đóng lại, thân thùng bóp nhẹ.
/// Chuyển từ phần tử #436 (thời lượng 1,25 s, các đường cong và mốc thời gian giữ nguyên).
final class TrashIconView: UIView {
    private let tile = CALayer()
    private let icon = CALayer()          // hệ toạ độ 32 × 32 như viewBox gốc
    private let lid = CAShapeLayer()
    private let body = CAShapeLayer()
    private let docClip = CALayer()
    private let doc = CALayer()
    private let docShape = CAShapeLayer()
    private let docLines = CAShapeLayer()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        build()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        let color = M3.danger
        tile.frame = bounds
        tile.cornerRadius = 18
        tile.backgroundColor = color.withAlphaComponent(0.13).cgColor
        layer.addSublayer(tile)

        let scale: CGFloat = 38.0 / 32.0
        icon.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        icon.position = CGPoint(x: 30, y: 30)
        icon.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        tile.addSublayer(icon)

        func style(_ s: CAShapeLayer, width: CGFloat = 1.9) {
            s.fillColor = UIColor.clear.cgColor
            s.strokeColor = color.cgColor
            s.lineWidth = width
            s.lineCap = .round
            s.lineJoin = .round
        }

        // Tài liệu (bị cắt ở mép trên của thùng để trông như rơi vào trong).
        docClip.bounds = CGRect(x: -10, y: -30, width: 52, height: 40.5)
        docClip.position = CGPoint(x: -10 + 26, y: -30 + 20.25)
        docClip.masksToBounds = true
        icon.addSublayer(docClip)
        doc.bounds = CGRect(x: 0, y: 0, width: 8, height: 11)
        doc.position = CGPoint(x: 16.5, y: 4)
        doc.opacity = 0
        docClip.addSublayer(doc)
        let dp = UIBezierPath()
        dp.move(to: CGPoint(x: 0, y: 0))
        dp.addLine(to: CGPoint(x: 5, y: 0))
        dp.addLine(to: CGPoint(x: 8, y: 3))
        dp.addLine(to: CGPoint(x: 8, y: 11))
        dp.addLine(to: CGPoint(x: 0, y: 11))
        dp.close()
        docShape.frame = doc.bounds
        docShape.path = dp.cgPath
        style(docShape, width: 1.5)
        docShape.fillColor = M3.surfaceHigh.cgColor
        doc.addSublayer(docShape)
        let lp = UIBezierPath()
        lp.move(to: CGPoint(x: 2, y: 5)); lp.addLine(to: CGPoint(x: 5.5, y: 5))
        lp.move(to: CGPoint(x: 2, y: 7.5)); lp.addLine(to: CGPoint(x: 5.5, y: 7.5))
        docLines.frame = doc.bounds
        docLines.path = lp.cgPath
        style(docLines, width: 1.2)
        doc.addSublayer(docLines)

        // Nắp: gốc xoay ở (6, 9.5).
        lid.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        lid.anchorPoint = CGPoint(x: 6.0 / 32.0, y: 9.5 / 32.0)
        lid.position = CGPoint(x: 6, y: 9.5)
        let lidPath = UIBezierPath()
        lidPath.move(to: CGPoint(x: 5.5, y: 9.5)); lidPath.addLine(to: CGPoint(x: 26.5, y: 9.5))
        lidPath.move(to: CGPoint(x: 12.5, y: 9)); lidPath.addLine(to: CGPoint(x: 12.5, y: 7))
        lidPath.addQuadCurve(to: CGPoint(x: 14, y: 5.5), controlPoint: CGPoint(x: 12.5, y: 5.5))
        lidPath.addLine(to: CGPoint(x: 18, y: 5.5))
        lidPath.addQuadCurve(to: CGPoint(x: 19.5, y: 7), controlPoint: CGPoint(x: 19.5, y: 5.5))
        lidPath.addLine(to: CGPoint(x: 19.5, y: 9))
        lid.path = lidPath.cgPath
        style(lid)
        icon.addSublayer(lid)

        // Thân: gốc co giãn ở (16, 27).
        body.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        body.anchorPoint = CGPoint(x: 0.5, y: 27.0 / 32.0)
        body.position = CGPoint(x: 16, y: 27)
        let bp = UIBezierPath()
        bp.move(to: CGPoint(x: 8, y: 10.5))
        bp.addLine(to: CGPoint(x: 9.3, y: 25.1))
        bp.addQuadCurve(to: CGPoint(x: 11.7, y: 27.3), controlPoint: CGPoint(x: 9.5, y: 27.3))
        bp.addLine(to: CGPoint(x: 20.3, y: 27.3))
        bp.addQuadCurve(to: CGPoint(x: 22.7, y: 25.1), controlPoint: CGPoint(x: 22.5, y: 27.3))
        bp.addLine(to: CGPoint(x: 24, y: 10.5))
        bp.move(to: CGPoint(x: 13.5, y: 15)); bp.addLine(to: CGPoint(x: 13.5, y: 22.5))
        bp.move(to: CGPoint(x: 18.5, y: 15)); bp.addLine(to: CGPoint(x: 18.5, y: 22.5))
        body.path = bp.cgPath
        style(body)
        icon.addSublayer(body)
    }

    private func keyframes(_ keyPath: String, values: [CGFloat], times: [Double], timing: CAMediaTimingFunction,
                           duration: Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values.map { NSNumber(value: Double($0)) }
        a.keyTimes = times.map { NSNumber(value: $0) }
        a.timingFunctions = Array(repeating: timing, count: max(0, values.count - 1))
        a.duration = duration
        return a
    }

    /// Chạy hoạt ảnh xoá. `duration` mặc định 1,25 s như bản gốc.
    func playDelete(duration: Double = 1.25) {
        let rad = { (d: CGFloat) -> CGFloat in return d * CGFloat.pi / 180 }
        // Nắp: none → -38° (22–58%) → 7° (74%) → none (86–100%), đường cong (.3,1.3,.5,1).
        let lidTiming = CAMediaTimingFunction(controlPoints: 0.3, 1.3, 0.5, 1)
        lid.add(keyframes("transform.rotation.z", values: [0, rad(-38), rad(-38), rad(7), 0, 0],
                          times: [0, 0.22, 0.58, 0.74, 0.86, 1], timing: lidTiming, duration: duration), forKey: "lid")

        // Tài liệu: mờ → hiện → rơi xuống 14 pt, đường cong (.5,0,.6,1).
        let docTiming = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.6, 1)
        let times: [Double] = [0, 0.14, 0.26, 0.52, 0.6, 1]
        let docY = keyframes("transform.translation.y", values: [-14, -14, -12, 9, 14, 14], times: times, timing: docTiming, duration: duration)
        let docRot = keyframes("transform.rotation.z", values: [rad(-8), rad(-8), rad(-4), 0, 0, 0], times: times, timing: docTiming, duration: duration)
        let docOp = keyframes("opacity", values: [0, 0, 1, 1, 1, 1], times: times, timing: docTiming, duration: duration)
        for a in [docY, docRot, docOp] { a.fillMode = .forwards; a.isRemovedOnCompletion = false }
        doc.add(docY, forKey: "docY")
        doc.add(docRot, forKey: "docRot")
        doc.add(docOp, forKey: "docOp")

        // Thân thùng bóp: scale(1.07, .9) → (.97, 1.04) → 1.
        let ease = CAMediaTimingFunction(name: .easeOut)
        let bt: [Double] = [0, 0.72, 0.8, 0.9, 1]
        body.add(keyframes("transform.scale.x", values: [1, 1, 1.07, 0.97, 1], times: bt, timing: ease, duration: duration), forKey: "bx")
        body.add(keyframes("transform.scale.y", values: [1, 1, 0.9, 1.04, 1], times: bt, timing: ease, duration: duration), forKey: "by")

        // Ô nền nảy: +2 pt → -1 pt → 0.
        tile.add(keyframes("transform.translation.y", values: [0, 0, 2, -1, 0], times: [0, 0.74, 0.8, 0.9, 1],
                           timing: ease, duration: duration), forKey: "tile")
    }

    func reset() {
        for l in [lid, body, tile, doc] { l.removeAllAnimations() }
        doc.opacity = 0
    }
}

/// Nút trong hộp thoại: bo 12, cao 42, nhún khi chạm (scale .94 rồi bật lại bằng lò xo).
final class DialogButton: UIControl {
    let label = UILabel()
    private let filled: Bool

    init(title: String, filled: Bool) {
        self.filled = filled
        super.init(frame: .zero)
        layer.cornerRadius = 12
        label.text = title
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        if filled {
            backgroundColor = M3.dangerButton
            label.textColor = UIColor.white
        } else {
            backgroundColor = UIColor.clear
            label.textColor = Theme.primaryText
            layer.borderWidth = 1
            layer.borderColor = Theme.separator.cgColor
        }
        addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    @objc private func down() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }, completion: nil)
    }

    @objc private func up() {
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.transform = CGAffineTransform.identity
        }, completion: nil)
    }

    func lock(_ locked: Bool) {
        isUserInteractionEnabled = !locked
        UIView.animate(withDuration: 0.2) { self.alpha = locked && !self.filled ? 0.45 : 1 }
    }
}

/// Hộp thoại xác nhận xoá playlist (Material 3 + hoạt ảnh thùng rác).
final class DeleteDialogViewController: UIViewController {
    private let dim = UIView()
    private let dialog = UIView()
    private let trash = TrashIconView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let cancelButton = DialogButton(title: L("Huỷ"), filled: false)
    private let deleteButton = DialogButton(title: L("Xoá"), filled: true)
    private let titleText: String
    private let messageText: String
    private var onConfirm: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var busy = false
    private var reduce: Bool { return UIAccessibility.isReduceMotionEnabled }

    /// Hiện hộp thoại từ một màn hình bất kỳ.
    static func present(from presenter: UIViewController, title: String, message: String,
                        onConfirm: @escaping () -> Void, onCancel: (() -> Void)? = nil) {
        let vc = DeleteDialogViewController(title: title, message: message)
        vc.onConfirm = onConfirm
        vc.onCancel = onCancel
        var top: UIViewController = presenter
        while let next = top.presentedViewController { top = next }
        top.present(vc, animated: false, completion: nil)
    }

    private init(title: String, message: String) {
        titleText = title
        messageText = message
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { return true }

    override var keyCommands: [UIKeyCommand]? {
        return [UIKeyCommand(input: "UIKeyInputEscape", modifierFlags: [], action: #selector(cancelTapped))]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.clear
        dim.frame = view.bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor(white: 0, alpha: 0.5)
        dim.alpha = 0
        view.addSubview(dim)

        dialog.backgroundColor = M3.surfaceHigh
        dialog.layer.cornerRadius = 20
        dialog.layer.borderWidth = 1
        dialog.layer.borderColor = Theme.separator.cgColor
        dialog.layer.shadowColor = UIColor.black.cgColor
        dialog.layer.shadowOpacity = 0.35
        dialog.layer.shadowRadius = 28
        dialog.layer.shadowOffset = CGSize(width: 0, height: 14)
        view.addSubview(dialog)

        dialog.addSubview(trash)
        titleLabel.text = titleText
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 0
        dialog.addSubview(titleLabel)
        messageLabel.text = messageText
        messageLabel.font = UIFont.systemFont(ofSize: 13)
        messageLabel.textColor = Theme.secondaryText
        messageLabel.numberOfLines = 0
        dialog.addSubview(messageLabel)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        dialog.addSubview(cancelButton)
        dialog.addSubview(deleteButton)

        dialog.alpha = 0
        dialog.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.9, y: 0.9)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width: CGFloat = min(296, view.bounds.width - 48)
        let pad: CGFloat = 22
        let inner = width - 2 * pad
        trash.frame = CGRect(x: pad, y: pad, width: 60, height: 60)
        var y = pad + 60 + 16
        let tH = titleLabel.sizeThatFits(CGSize(width: inner, height: 1000)).height
        titleLabel.frame = CGRect(x: pad, y: y, width: inner, height: tH)
        y += tH + 6
        let mH = messageLabel.sizeThatFits(CGSize(width: inner, height: 1000)).height
        messageLabel.frame = CGRect(x: pad, y: y, width: inner, height: mH)
        y += mH + 20
        let bw = (inner - 8) / 2
        cancelButton.frame = CGRect(x: pad, y: y, width: bw, height: 42)
        deleteButton.frame = CGRect(x: pad + bw + 8, y: y, width: bw, height: 42)
        let height = y + 42 + 20
        dialog.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        dialog.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIView.animate(withDuration: 0.2) { self.dim.alpha = 1 }
        UIView.animate(withDuration: reduce ? 0.01 : 0.5, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.4,
                       options: [], animations: {
            self.dialog.alpha = 1
            self.dialog.transform = CGAffineTransform.identity
        }, completion: nil)
    }

    @objc private func cancelTapped() {
        guard !busy else { return }
        busy = true
        cancelButton.lock(true)
        deleteButton.lock(true)
        close { [weak self] in self?.onCancel?() }
    }

    @objc private func deleteTapped() {
        guard !busy else { return }
        busy = true
        cancelButton.lock(true)
        deleteButton.lock(true)
        let wait: Double = reduce ? 0.2 : 1.35
        if !reduce { trash.playDelete() }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.close { self?.onConfirm?() }
        }
    }

    private func close(_ done: @escaping () -> Void) {
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseIn], animations: {
            self.dialog.transform = CGAffineTransform(translationX: 0, y: 10).scaledBy(x: 0.92, y: 0.92)
            self.dialog.alpha = 0
            self.dim.alpha = 0
        }, completion: { _ in
            self.dismiss(animated: false) { done() }
        })
    }
}
