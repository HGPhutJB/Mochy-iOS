import UIKit

/// Tab "Cài đặt": cập nhật phần mềm (kiểm tra tự động, kênh Ổn định / Nhà phát triển), thông tin bản dựng, giới thiệu.
final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Row {
        case theme
        case quality
        case downloadsInfo
        case clearDownloads
        case clearHistory
        case credits
        case version
        case channel
        case autoCheck
        case checkNow
        case updateAvailable
        case info(String, String)
        case link(String, String, String)
    }

    private struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var sections: [Section] = []
    private var documentController: UIDocumentInteractionController?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cài đặt"
        view.backgroundColor = Theme.groupedBackground
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.groupedBackground
        tableView.separatorColor = Theme.separator
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(updateStateChanged),
                                               name: .updateStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateStateChanged),
                                               name: .libraryChanged, object: nil)
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuild()
        tableView.reloadData()
    }

    @objc private func updateStateChanged() {
        rebuild()
        tableView.reloadData()
    }

    private func rebuild() {
        var updateRows: [Row] = [.version, .channel, .autoCheck, .checkNow]
        if Updater.shared.available != nil {
            updateRows.append(.updateAvailable)
        }
        let channelFooter: String
        if AppSettings.channel == .dev {
            channelFooter = "Kênh Nhà phát triển nhận bản dựng mới nhất sau mỗi lần cập nhật mã nguồn, có thể còn lỗi. Bản cập nhật được kiểm tra chữ ký và SHA-256 trước khi cho cài."
        } else {
            channelFooter = "Kênh Ổn định chỉ nhận các bản đã được phát hành chính thức. Bản cập nhật được kiểm tra chữ ký và SHA-256 trước khi cho cài."
        }
        let installKind = AppInfo.isJailbreakInstall ? "Jailbreak (.deb)" : "Sideload (.ipa)"
        let builtChannel = AppInfo.builtChannel == "dev" ? "Nhà phát triển" : "Ổn định"
        sections = [
            Section(title: "Giao diện", footer: "\"Tự động\" theo chế độ sáng/tối của hệ thống (iOS 13 trở lên). Trên iOS 12 chế độ tự động dùng giao diện tối.",
                    rows: [.theme]),
            Section(title: "Âm thanh", footer: "\"Tiết kiệm\" chọn luồng âm thanh có bitrate thấp nhất, dùng ít dữ liệu hơn. Áp dụng từ bài kế tiếp.",
                    rows: [.quality]),
            Section(title: "Bộ nhớ", footer: nil, rows: [.downloadsInfo, .clearDownloads, .clearHistory]),
            Section(title: "Cập nhật phần mềm", footer: channelFooter, rows: updateRows),
            Section(title: "Thông tin bản dựng", footer: nil, rows: [
                .info("Kênh của bản dựng", builtChannel),
                .info("Commit", AppInfo.commit.isEmpty ? "—" : AppInfo.commit),
                .info("Cách cài", installKind),
                .info("iOS", AppInfo.osVersion)
            ]),
            Section(title: "Giới thiệu", footer: nil, rows: [
                .credits,
                .link("Mã nguồn Mochy iOS", "GitHub", UpdateConfig.repoPage)
            ])
        ]
    }

    // MARK: - Bảng

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return sections[section].footer
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let updater = Updater.shared
        let cell: UITableViewCell
        switch row {
        case .theme:
            cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            let control = UISegmentedControl(items: [ThemeMode.system.title, ThemeMode.light.title, ThemeMode.dark.title])
            control.selectedSegmentIndex = Theme.mode.rawValue
            control.tintColor = Theme.accent
            control.frame = CGRect(x: 0, y: 0, width: 260, height: 30)
            control.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
            cell.accessoryView = control
            cell.textLabel?.text = "Chế độ"
            cell.selectionStyle = .none

        case .quality:
            cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            let control = UISegmentedControl(items: ["Cao nhất", "Tiết kiệm"])
            control.selectedSegmentIndex = AppSettings.audioQuality == .best ? 0 : 1
            control.tintColor = Theme.accent
            control.frame = CGRect(x: 0, y: 0, width: 190, height: 30)
            control.addTarget(self, action: #selector(qualityChanged(_:)), for: .valueChanged)
            cell.accessoryView = control
            cell.textLabel?.text = "Chất lượng"
            cell.selectionStyle = .none

        case .downloadsInfo:
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Bài đã tải xuống"
            let size = ByteCountFormatter.string(fromByteCount: Library.shared.totalDownloadBytes(), countStyle: .file)
            cell.detailTextLabel?.text = "\(Library.shared.downloads.count) bài · \(size)"
            cell.selectionStyle = .none

        case .clearDownloads:
            cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Xoá tất cả bài đã tải"
            cell.textLabel?.textColor = Theme.accent

        case .clearHistory:
            cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Xoá lịch sử nghe"
            cell.textLabel?.textColor = Theme.accent

        case .credits:
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Credit và giấy phép"
            cell.detailTextLabel?.text = "Mochy Music"
            cell.accessoryType = .disclosureIndicator

        case .version:
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Phiên bản hiện tại"
            cell.detailTextLabel?.text = "\(AppInfo.version) (build \(AppInfo.build))"
            cell.selectionStyle = .none

        case .channel:
            cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Kênh cập nhật"
            let control = UISegmentedControl(items: [UpdateChannel.stable.title, UpdateChannel.dev.title])
            control.selectedSegmentIndex = AppSettings.channel == .stable ? 0 : 1
            control.tintColor = Theme.accent
            control.frame = CGRect(x: 0, y: 0, width: 200, height: 30)
            control.addTarget(self, action: #selector(channelChanged(_:)), for: .valueChanged)
            cell.accessoryView = control
            cell.selectionStyle = .none

        case .autoCheck:
            cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Tự động kiểm tra cập nhật"
            let toggle = UISwitch()
            toggle.isOn = AppSettings.autoCheck
            toggle.onTintColor = Theme.accent
            toggle.addTarget(self, action: #selector(autoCheckChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none

        case .checkNow:
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = "Kiểm tra cập nhật ngay"
            cell.textLabel?.textColor = Theme.accent
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = Theme.secondaryText
            if updater.isChecking {
                cell.detailTextLabel?.text = "Đang kiểm tra…"
                let spinner = UIActivityIndicatorView(style: Theme.spinnerStyle())
                spinner.startAnimating()
                cell.accessoryView = spinner
            } else if updater.lastMessage.isEmpty {
                cell.detailTextLabel?.text = nil
            } else {
                cell.detailTextLabel?.text = updater.lastMessage
            }

        case .updateAvailable:
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if let info = updater.available {
                cell.textLabel?.text = "Có bản mới: \(info.version) (build \(info.build))"
                let kind = info.channel == "dev" ? "Bản thử nghiệm" : "Bản ổn định"
                cell.detailTextLabel?.text = "\(kind) · chạm để xem chi tiết và tải về"
            }
            cell.textLabel?.textColor = Theme.accent
            cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            cell.detailTextLabel?.textColor = Theme.secondaryText
            cell.accessoryType = .disclosureIndicator

        case .info(let title, let value):
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = value
            cell.selectionStyle = .none

        case .link(let title, let value, _):
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = value
            cell.accessoryType = .disclosureIndicator
        }
        let keepColor = cell.textLabel?.textColor
        Theme.style(cell: cell, grouped: true)
        switch row {
        case .checkNow, .updateAvailable, .clearDownloads, .clearHistory:
            cell.textLabel?.textColor = keepColor
        default:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .credits:
            navigationController?.pushViewController(CreditsViewController(), animated: true)
        case .clearDownloads:
            confirm("Xoá tất cả bài đã tải xuống?", button: "Xoá") { Library.shared.removeAllDownloads() }
        case .clearHistory:
            confirm("Xoá toàn bộ lịch sử nghe?", button: "Xoá") { Library.shared.clearHistory() }
        case .checkNow:
            Updater.shared.check(manual: true)
        case .updateAvailable:
            presentUpdateSheet()
        case .link(_, _, let urlString):
            open(urlString)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    // MARK: - Hành động

    @objc private func themeChanged(_ sender: UISegmentedControl) {
        guard let mode = ThemeMode(rawValue: sender.selectedSegmentIndex) else { return }
        Theme.mode = mode
        NotificationCenter.default.post(name: .themeChanged, object: nil)
    }

    @objc private func qualityChanged(_ sender: UISegmentedControl) {
        AppSettings.audioQuality = sender.selectedSegmentIndex == 0 ? .best : .saver
    }

    private func confirm(_ message: String, button: String, _ action: @escaping () -> Void) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: button, style: .destructive) { _ in action() })
        present(alert, animated: true, completion: nil)
    }

    @objc private func channelChanged(_ sender: UISegmentedControl) {
        AppSettings.channel = sender.selectedSegmentIndex == 0 ? .stable : .dev
        Updater.shared.channelDidChange()
    }

    @objc private func autoCheckChanged(_ sender: UISwitch) {
        AppSettings.autoCheck = sender.isOn
        if sender.isOn {
            Updater.shared.autoCheckIfNeeded()
        }
    }

    private func open(_ string: String) {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "sileo" else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func sizeText(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func presentUpdateSheet() {
        guard let info = Updater.shared.available else { return }
        var message = "Phiên bản \(info.version) (build \(info.build))"
        if !info.commit.isEmpty { message += ", commit \(info.commit)" }
        message += "\n"
        message += info.signed ? "Chữ ký số: hợp lệ ✓" : "Chữ ký số: chưa có (chỉ kiểm SHA-256)"
        if !info.notes.isEmpty {
            message += "\n\n" + String(info.notes.prefix(600))
        }
        let alert = UIAlertController(title: "Có bản cập nhật", message: message, preferredStyle: .alert)

        if let file = Updater.shared.preferredFile(for: info) {
            let kind = file.name.lowercased().hasSuffix(".deb") ? ".deb" : ".ipa"
            alert.addAction(UIAlertAction(title: "Tải bản \(kind) (\(sizeText(file.size)))", style: .default) { [weak self] _ in
                self?.startDownload(file)
            })
        }
        if AppInfo.isJailbreakInstall && info.channel == "stable" {
            alert.addAction(UIAlertAction(title: "Mở Sileo (nguồn repo)", style: .default) { [weak self] _ in
                self?.open("sileo://package/\(UpdateConfig.appId)")
            })
        }
        alert.addAction(UIAlertAction(title: "Xem trên GitHub", style: .default) { [weak self] _ in
            self?.open(UpdateConfig.releasesPage)
        })
        alert.addAction(UIAlertAction(title: "Để sau", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func startDownload(_ file: UpdateFile) {
        let alert = UIAlertController(title: "Đang tải", message: "\(file.name)\n0%", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in
            Updater.shared.cancelDownload()
        })
        present(alert, animated: true, completion: nil)

        Updater.shared.download(file, progress: { fraction in
            alert.message = "\(file.name)\n\(Int(fraction * 100))%"
        }, completion: { [weak self] result in
            if case .failure(let error) = result, error.cancelled { return }
            alert.dismiss(animated: true) {
                switch result {
                case .success(let url):
                    self?.presentDownloaded(url, file: file)
                case .failure(let error):
                    self?.showMessage("Tải thất bại", error.message)
                }
            }
        })
    }

    private func presentDownloaded(_ url: URL, file: UpdateFile) {
        let hint: String
        if file.name.lowercased().hasSuffix(".deb") {
            hint = "Chọn Sileo (hoặc Filza) rồi bấm Cài đặt."
        } else {
            hint = "Chọn ESign / Sideloadly / AltStore để ký rồi cài."
        }
        let alert = UIAlertController(title: "Đã tải và xác minh",
                                      message: "\(file.name)\nSHA-256 khớp với bản phát hành.\n\(hint)",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Mở bằng ứng dụng khác…", style: .default) { [weak self] _ in
            self?.openInOtherApp(url)
        })
        alert.addAction(UIAlertAction(title: "Chia sẻ / Lưu vào Tệp…", style: .default) { [weak self] _ in
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self?.present(controller, animated: true, completion: nil)
        })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func openInOtherApp(_ url: URL) {
        let controller = UIDocumentInteractionController(url: url)
        documentController = controller
        let anchor = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        if !controller.presentOpenInMenu(from: anchor, in: view, animated: true) {
            showMessage("Không có ứng dụng phù hợp",
                        "Không tìm thấy ứng dụng nào mở được tệp này. Hãy dùng \"Chia sẻ / Lưu vào Tệp…\" rồi mở bằng Sileo, Filza hoặc ESign.")
        }
    }
}
