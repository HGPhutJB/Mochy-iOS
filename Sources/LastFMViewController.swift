import UIKit

/// Đăng nhập Last.fm bằng khoá API riêng (tạo tại last.fm/api/account/create).
final class LastFMViewController: UIViewController {
    private let key = UITextField(), secret = UITextField(), user = UITextField(), pass = UITextField()
    private let status = UILabel()
    private let toggle = UISwitch()
    private let action = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Last.fm"
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        for (f, p) in [(key, "API key"), (secret, "Shared secret"), (user, "Tên đăng nhập"), (pass, "Mật khẩu")] {
            f.placeholder = p
            f.font = Theme.regular(16)
            f.textColor = Theme.primaryText
            f.backgroundColor = Theme.card
            f.layer.cornerRadius = 10
            f.autocapitalizationType = .none
            f.autocorrectionType = .no
            f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 10))
            f.leftViewMode = .always
            f.heightAnchor.constraint(equalToConstant: 46).isActive = true
        }
        pass.isSecureTextEntry = true
        status.numberOfLines = 0
        status.font = Theme.regular(14)
        status.textColor = Theme.secondaryText
        action.titleLabel?.font = Theme.bold(17)
        action.setTitleColor(.white, for: .normal)
        action.backgroundColor = Theme.accent
        action.layer.cornerRadius = 12
        action.heightAnchor.constraint(equalToConstant: 48).isActive = true
        action.addTarget(self, action: #selector(tapAction), for: .touchUpInside)
        toggle.onTintColor = Theme.accent
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        let toggleLabel = UILabel()
        toggleLabel.text = "Tự động scrobble"
        toggleLabel.font = Theme.regular(16)
        toggleLabel.textColor = Theme.primaryText
        let toggleRow = UIStackView(arrangedSubviews: [toggleLabel, toggle])
        let stack = UIStackView(arrangedSubviews: [status, key, secret, user, pass, toggleRow, action])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:))))
        refresh()
    }

    private func refresh() {
        let on = LastFM.shared.isLoggedIn
        [key, secret, user, pass].forEach { $0.isHidden = on }
        toggle.superview?.isHidden = !on
        toggle.isOn = LastFM.shared.scrobbleEnabled
        action.setTitle(on ? "Đăng xuất" : "Đăng nhập", for: .normal)
        status.text = on ? "Đã đăng nhập: \(LastFM.shared.username)" :
            "Tạo API key miễn phí tại last.fm/api/account/create rồi nhập vào đây. Mật khẩu chỉ dùng một lần để lấy khoá phiên, không được lưu."
    }

    @objc private func toggled() {
        LastFM.shared.scrobbleEnabled = toggle.isOn
    }

    @objc private func tapAction() {
        view.endEditing(true)
        if LastFM.shared.isLoggedIn {
            LastFM.shared.logout()
            refresh()
            return
        }
        let k = (key.text ?? "").trimmingCharacters(in: .whitespaces)
        let s = (secret.text ?? "").trimmingCharacters(in: .whitespaces)
        let u = (user.text ?? "").trimmingCharacters(in: .whitespaces)
        let p = pass.text ?? ""
        if k.isEmpty || s.isEmpty || u.isEmpty || p.isEmpty {
            status.text = "Hãy điền đủ 4 ô."
            return
        }
        status.text = "Đang đăng nhập…"
        LastFM.shared.login(key: k, secret: s, username: u, password: p) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: self?.pass.text = ""; self?.refresh()
                case .failure(let e): self?.status.text = "Lỗi: \(e.message)"
                }
            }
        }
    }
}
