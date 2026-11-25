import UIKit

/// Màn hình tài khoản Mochy: đăng nhập / đăng ký, và khi đã đăng nhập thì xem trạng thái đồng bộ, đổi mật khẩu, đăng xuất, xoá tài khoản.
final class MochyAccountViewController: UIViewController, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let mode = M3Segmented(items: ["Đăng nhập", "Đăng ký"], selected: 0)
    private let userField = UITextField()
    private let passField = UITextField()
    private let confirmField = UITextField()
    private let actionButton = UIButton(type: .custom)
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: Theme.spinnerStyle())
    private var busy = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if MochyCloud.shared.isLoggedIn && !busy { rebuild() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tài khoản Mochy"
        view.backgroundColor = Theme.background
        if #available(iOS 11.0, *) { navigationItem.largeTitleDisplayMode = .never }

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 110),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -120)
        ])

        mode.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        configure(userField, placeholder: "Tên đăng nhập", secure: false)
        configure(passField, placeholder: "Mật khẩu", secure: true)
        configure(confirmField, placeholder: "Nhập lại mật khẩu", secure: true)
        actionButton.backgroundColor = Theme.accent
        actionButton.layer.cornerRadius = 26
        actionButton.titleLabel?.font = Theme.bold(17)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        actionButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
        messageLabel.numberOfLines = 0
        messageLabel.font = Theme.regular(14)
        messageLabel.textAlignment = .center
        spinner.hidesWhenStopped = true

        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged), name: .cloudStateChanged, object: nil)
        rebuild()
        if MochyCloud.shared.isLoggedIn {
            MochyCloud.shared.loadFollows { [weak self] _, _, _ in if self?.busy == false { self?.rebuild() } }
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configure(_ field: UITextField, placeholder: String, secure: Bool) {
        field.placeholder = placeholder
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = secure ? .go : .next
        field.keyboardAppearance = Theme.isDark ? .dark : .light
        field.textColor = Theme.primaryText
        field.font = Theme.regular(17)
        field.backgroundColor = Theme.card
        field.layer.cornerRadius = 18
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        field.leftViewMode = .always
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: Theme.secondaryText])
        field.delegate = self
        field.heightAnchor.constraint(equalToConstant: 52).isActive = true
    }

    private func label(_ text: String, font: UIFont, color: UIColor, align: NSTextAlignment = .natural) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.numberOfLines = 0
        l.textAlignment = align
        return l
    }

    private func rebuild() {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        let cloud = MochyCloud.shared
        if !cloud.isConfigured {
            stack.addArrangedSubview(label("Tài khoản Mochy", font: Theme.heavy(30), color: Theme.primaryText))
            stack.addArrangedSubview(label("Máy chủ tài khoản chưa được cấu hình trong bản này.", font: Theme.regular(16), color: Theme.secondaryText))
            return
        }
        if cloud.isLoggedIn { buildLoggedIn(cloud) } else { buildLoggedOut() }
    }

    private func buildLoggedOut() {
        stack.addArrangedSubview(label("Tài khoản Mochy", font: Theme.heavy(30), color: Theme.primaryText))
        stack.addArrangedSubview(label("Đăng nhập để lưu yêu thích, playlist, lịch sử nghe, cài đặt và danh sách bài đã tải, rồi dùng trên mọi máy.",
                                       font: Theme.regular(15), color: Theme.secondaryText))
        let holder = UIView()
        mode.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(mode)
        NSLayoutConstraint.activate([
            mode.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            mode.topAnchor.constraint(equalTo: holder.topAnchor),
            mode.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            mode.heightAnchor.constraint(equalToConstant: 32),
            mode.widthAnchor.constraint(equalToConstant: max(180, mode.bounds.width))
        ])
        stack.addArrangedSubview(holder)
        stack.addArrangedSubview(userField)
        stack.addArrangedSubview(passField)
        stack.addArrangedSubview(confirmField)
        stack.addArrangedSubview(actionButton)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(label("Mật khẩu được băm trên máy chủ, không ai (kể cả nhà phát triển) đọc được.",
                                       font: Theme.regular(12), color: Theme.secondaryText, align: .center))
        applyMode()
    }

    /// Trang cá nhân kiểu mạng xã hội: ảnh tròn bên trái, tên + huy hiệu, số liệu, hàng nút.
    private func buildLoggedIn(_ cloud: MochyCloud) {
        let big: CGFloat = 92
        let avatar = UIButton(type: .custom)
        avatar.setImage(AccountAvatarButton.render(letter: String((cloud.username ?? "?").prefix(1)).uppercased(), photo: cloud.avatarImage, side: big), for: .normal)
        avatar.widthAnchor.constraint(equalToConstant: big).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: big).isActive = true
        avatar.addTarget(self, action: #selector(pickAvatar), for: .touchUpInside)

        let following = UserDefaults.standard.integer(forKey: "cloud.followingCount")
        let followers = UserDefaults.standard.integer(forKey: "cloud.followersCount")
        let stats = UIStackView(arrangedSubviews: [
            statButton(number: following, caption: "Đang theo dõi", action: #selector(followingTapped)),
            statButton(number: followers, caption: "Người theo dõi", action: #selector(followersTapped)),
            statButton(number: Library.shared.liked.count, caption: "Yêu thích", action: nil)
        ])
        stats.axis = .horizontal
        stats.spacing = 16
        stats.alignment = .leading

        let info = UIStackView(arrangedSubviews: [nameRow(cloud), stats])
        info.axis = .vertical
        info.spacing = 8
        info.alignment = .leading

        let head = UIStackView(arrangedSubviews: [avatar, info])
        head.axis = .horizontal
        head.spacing = 16
        head.alignment = .center
        stack.addArrangedSubview(head)

        var status = "Chưa đồng bộ"
        if let t = cloud.lastSync {
            let f = DateFormatter()
            f.dateFormat = "HH:mm dd/MM"
            status = "Đồng bộ lần cuối lúc " + f.string(from: t)
        }
        if let e = cloud.lastError { status += "\n" + e }
        stack.addArrangedSubview(label(status, font: Theme.regular(13), color: cloud.lastError == nil ? Theme.secondaryText : M3.danger))

        let actions = UIStackView(arrangedSubviews: [
            pill("Tìm người", #selector(searchUsersTapped), prominent: true),
            pill("Đổi ảnh", #selector(pickAvatar), prominent: false),
            pill("Đồng bộ", #selector(syncTapped), prominent: false),
            pill("⋯", #selector(moreTapped), prominent: false, compact: true)
        ])
        actions.axis = .horizontal
        actions.spacing = 8
        actions.distribution = .fill
        stack.addArrangedSubview(actions)
        stack.addArrangedSubview(spinner)
    }

    private func statButton(number: Int, caption: String, action: Selector?) -> UIView {
        let b = UIButton(type: .custom)
        let text = NSMutableAttributedString(string: "\(number) ", attributes: [.font: Theme.heavy(16), .foregroundColor: Theme.primaryText])
        text.append(NSAttributedString(string: caption, attributes: [.font: Theme.regular(14), .foregroundColor: Theme.secondaryText]))
        b.setAttributedTitle(text, for: .normal)
        if let action = action { b.addTarget(self, action: action, for: .touchUpInside) }
        b.isUserInteractionEnabled = action != nil
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        return b
    }

    private func pill(_ title: String, _ action: Selector, prominent: Bool, compact: Bool = false) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = Theme.bold(15)
        b.layer.cornerRadius = 12
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        if compact { b.widthAnchor.constraint(equalToConstant: 48).isActive = true }
        else { b.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        b.backgroundColor = prominent ? Theme.accent : Theme.card
        b.setTitleColor(prominent ? .white : Theme.primaryText, for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    /// Menu "⋯": các thao tác ít dùng.
    @objc private func moreTapped() {
        let cloud = MochyCloud.shared
        let sheet = UIAlertController(title: "@" + (cloud.username ?? ""), message: nil, preferredStyle: .actionSheet)
        if cloud.avatarImage != nil {
            sheet.addAction(UIAlertAction(title: "Xoá ảnh đại diện", style: .default) { [weak self] _ in self?.removeAvatarTapped() })
        }
        sheet.addAction(UIAlertAction(title: "Đổi mật khẩu", style: .default) { [weak self] _ in self?.changePasswordTapped() })
        sheet.addAction(UIAlertAction(title: "Đăng xuất", style: .default) { [weak self] _ in self?.logoutTapped() })
        sheet.addAction(UIAlertAction(title: "Xoá tài khoản", style: .destructive) { [weak self] _ in self?.deleteTapped() })
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    /// Tên tài khoản kèm huy hiệu: tick đen (đã xác minh) và nhãn Owner.
    private func nameRow(_ cloud: MochyCloud) -> UIView {
        let name = label(cloud.username ?? "", font: Theme.heavy(24), color: Theme.primaryText)
        name.numberOfLines = 1
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.6
        let row = UIStackView(arrangedSubviews: [name])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        if cloud.isVerified {
            let tick = UIImageView(image: AccountAvatarButton.verifiedTick(size: 24))
            tick.setContentHuggingPriority(.required, for: .horizontal)
            tick.widthAnchor.constraint(equalToConstant: 24).isActive = true
            tick.heightAnchor.constraint(equalToConstant: 24).isActive = true
            row.addArrangedSubview(tick)
        }
        if cloud.isOwner {
            let pill = UILabel()
            pill.text = "  👑 OWNER  "
            pill.font = Theme.bold(12)
            pill.textColor = Theme.isDark ? .black : .white
            pill.backgroundColor = Theme.isDark ? .white : .black
            pill.layer.cornerRadius = 11
            pill.clipsToBounds = true
            pill.setContentHuggingPriority(.required, for: .horizontal)
            pill.heightAnchor.constraint(equalToConstant: 22).isActive = true
            row.addArrangedSubview(pill)
        }
        row.addArrangedSubview(UIView())
        return row
    }

    private func makeButton(_ title: String, filled: Bool, action: Selector, danger: Bool = false) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = Theme.bold(17)
        b.layer.cornerRadius = 26
        b.heightAnchor.constraint(equalToConstant: 52).isActive = true
        if filled {
            b.backgroundColor = Theme.accent
            b.setTitleColor(.white, for: .normal)
        } else {
            b.backgroundColor = Theme.card
            b.setTitleColor(danger ? M3.danger : Theme.accent, for: .normal)
        }
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func applyMode() {
        let register = mode.selectedSegmentIndex == 1
        confirmField.isHidden = !register
        passField.returnKeyType = register ? .next : .go
        actionButton.setTitle(register ? "Tạo tài khoản" : "Đăng nhập", for: .normal)
        messageLabel.text = nil
    }

    private func setBusy(_ on: Bool) {
        busy = on
        on ? spinner.startAnimating() : spinner.stopAnimating()
        view.isUserInteractionEnabled = !on
    }

    private func show(_ text: String?, error: Bool = true) {
        messageLabel.text = text
        messageLabel.textColor = error ? M3.danger : Theme.secondaryText
    }

    @objc private func modeChanged() { applyMode() }

    @objc private func stateChanged() { if !busy { rebuild() } }

    @objc private func submit() {
        guard !busy else { return }
        view.endEditing(true)
        let register = mode.selectedSegmentIndex == 1
        let name = (userField.text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let pass = passField.text ?? ""
        if name.isEmpty || pass.isEmpty { show("Nhập tên đăng nhập và mật khẩu."); return }
        if register && pass != (confirmField.text ?? "") { show("Hai lần nhập mật khẩu không khớp."); return }
        setBusy(true)
        show(nil)
        MochyCloud.shared.authenticate(register: register, username: name, password: pass) { [weak self] error in
            guard let self = self else { return }
            self.setBusy(false)
            if let error = error { self.show(error) } else { self.rebuild() }
        }
    }

    @objc private func syncTapped() {
        guard !busy else { return }
        setBusy(true)
        MochyCloud.shared.syncNow { [weak self] _ in
            self?.setBusy(false)
            self?.rebuild()
        }
    }

    @objc private func pickAvatar() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { info("Không mở được thư viện ảnh."); return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true   // cắt vuông ngay trong bộ chọn
        picker.delegate = self
        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true)
        guard let picked = image else { return }
        setBusy(true)
        MochyCloud.shared.uploadAvatar(picked) { [weak self] error in
            self?.setBusy(false)
            if let error = error { self?.info(error) }
            self?.rebuild()
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    @objc private func removeAvatarTapped() {
        setBusy(true)
        MochyCloud.shared.removeAvatar { [weak self] error in
            self?.setBusy(false)
            if let error = error { self?.info(error) }
            self?.rebuild()
        }
    }

    @objc private func searchUsersTapped() { navigationController?.pushViewController(UserListViewController(mode: .search), animated: true) }
    @objc private func followingTapped() { navigationController?.pushViewController(UserListViewController(mode: .following), animated: true) }
    @objc private func followersTapped() { navigationController?.pushViewController(UserListViewController(mode: .followers), animated: true) }

    @objc private func logoutTapped() {
        MochyCloud.shared.logout()
        rebuild()
    }

    @objc private func changePasswordTapped() {
        let alert = UIAlertController(title: "Đổi mật khẩu", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Mật khẩu hiện tại"; $0.isSecureTextEntry = true }
        alert.addTextField { $0.placeholder = "Mật khẩu mới (từ 6 ký tự)"; $0.isSecureTextEntry = true }
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        alert.addAction(UIAlertAction(title: "Đổi", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let f = alert?.textFields else { return }
            self.setBusy(true)
            MochyCloud.shared.changePassword(old: f[0].text ?? "", new: f[1].text ?? "") { error in
                self.setBusy(false)
                self.info(error ?? "Đã đổi mật khẩu.")
            }
        })
        present(alert, animated: true)
    }

    @objc private func deleteTapped() {
        DeleteDialogViewController.present(from: self, title: "Xoá tài khoản Mochy?",
                                           message: "Dữ liệu trên máy chủ sẽ bị xoá vĩnh viễn. Dữ liệu trên máy này vẫn còn.",
                                           onConfirm: { [weak self] in
            self?.setBusy(true)
            MochyCloud.shared.deleteAccount { error in
                self?.setBusy(false)
                if let error = error { self?.info(error) } else { self?.rebuild() }
            }
        }, onCancel: nil)
    }

    private func info(_ text: String) {
        let a = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === userField { passField.becomeFirstResponder() }
        else if textField === passField && mode.selectedSegmentIndex == 1 { confirmField.becomeFirstResponder() }
        else { submit() }
        return true
    }
}
