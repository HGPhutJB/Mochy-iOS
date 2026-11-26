import UIKit

/// Tab "Cài đặt": cập nhật phần mềm (kiểm tra tự động, kênh Ổn định / Nhà phát triển), thông tin bản dựng, giới thiệu.
final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private enum Row {
        case theme
        case quality
        case reverb
        case translateLang
        case crossfade
        case language
        case videoBackdrop
        case downloadsInfo
        case clearDownloads
        case clearHistory
        case backup
        case restore
        case lastfm
        case accounts
        case mochyAccount
        case advanced
        case importList
        case recap
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
        title = L("Cài đặt")
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.groupedBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.groupedBackground
        tableView.separatorStyle = .none
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
        NotificationCenter.default.addObserver(self, selector: #selector(updateStateChanged),
                                               name: .reverbChanged, object: nil)
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
            channelFooter = L("Kênh Nhà phát triển nhận bản dựng mới nhất sau mỗi lần cập nhật mã nguồn, có thể còn lỗi. Bản cập nhật được kiểm tra chữ ký và SHA-256 trước khi cho cài.")
        } else {
            channelFooter = L("Kênh Ổn định chỉ nhận các bản đã được phát hành chính thức. Bản cập nhật được kiểm tra chữ ký và SHA-256 trước khi cho cài.")
        }
        let installKind = AppInfo.isJailbreakInstall ? "Jailbreak (.deb)" : "Sideload (.ipa)"
        let builtChannel = AppInfo.builtChannel == "dev" ? L("Nhà phát triển") : L("Ổn định")
        var accountSections: [Section] = []
        if MochyCloud.shared.isConfigured {
            accountSections = [Section(title: L("Tài khoản"), footer: L("Đăng nhập để đồng bộ yêu thích, playlist, lịch sử nghe, cài đặt và danh sách bài đã tải giữa các máy."), rows: [.mochyAccount])]
        }
        sections = accountSections + [
            Section(title: L("Giao diện"), footer: L("\"Tự động\" theo chế độ sáng/tối của hệ thống (iOS 13 trở lên). Trên iOS 12 chế độ tự động dùng giao diện tối."),
                    rows: [.theme, .language]),
            Section(title: L("Âm thanh"), footer: L("\"Cao nhất\" chọn luồng âm thanh bitrate cao nhất mà YouTube Music cung cấp (tối đa khoảng 256 kbps, định dạng nén). YouTube không có nhạc lossless thật nên Mochy không ghi nhãn Lossless. \"Tiết kiệm\" chọn bitrate thấp nhất. Áp dụng từ bài kế tiếp."),
                    rows: [.quality, .crossfade, .reverb, .translateLang, .videoBackdrop]),
            Section(title: L("Tính năng"), footer: nil, rows: [.recap, .importList, .advanced]),
            Section(title: L("Bộ nhớ"), footer: nil, rows: [.downloadsInfo, .clearDownloads, .clearHistory]),
            Section(title: L("Dữ liệu"), footer: L("Sao lưu gồm yêu thích, playlist, lịch sử nghe và cài đặt (không gồm tệp nhạc đã tải). Tệp nằm trong Tệp ▸ Mochy ▸ MochyBackup. Khôi phục luôn là gộp, không xoá dữ liệu đang có. App tự sao lưu mỗi khi mở và trước khi cập nhật."),
                    rows: [.backup, .restore]),
            Section(title: L("Cập nhật phần mềm"), footer: channelFooter, rows: updateRows),
            Section(title: L("Thông tin bản dựng"), footer: nil, rows: [
                .info(L("Kênh của bản dựng"), builtChannel),
                .info("Commit", AppInfo.commit.isEmpty ? "—" : AppInfo.commit),
                .info(L("Cách cài"), installKind),
                .info("iOS", AppInfo.osVersion)
            ]),
            Section(title: L("Giới thiệu"), footer: nil, rows: [
                .credits,
                .link(L("Mã nguồn Mochy iOS"), "GitHub", UpdateConfig.repoPage)
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

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = sections[section].title else { return nil }
        return M3.headerView(title)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return sections[section].title == nil ? 12 : 40
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let footer = sections[section].footer else { return nil }
        return M3.footerView(footer)
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard let footer = sections[section].footer else { return 8 }
        return M3.footerHeight(footer, width: tableView.bounds.width)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let m3 = cell as? M3Cell else { return }
        let count = sections[indexPath.section].rows.count
        if count == 1 { m3.position = .single }
        else if indexPath.row == 0 { m3.position = .top }
        else if indexPath.row == count - 1 { m3.position = .bottom }
        else { m3.position = .middle }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let updater = Updater.shared
        let cell: UITableViewCell
        switch row {
        case .theme:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            let control = M3Segmented(items: [ThemeMode.system.title, ThemeMode.light.title, ThemeMode.dark.title], selected: Theme.mode.rawValue)
            control.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
            cell.accessoryView = control
            cell.textLabel?.text = L("Chế độ")
            cell.selectionStyle = .none

        case .quality:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            let control = M3Segmented(items: [L("Cao nhất"), L("Tiết kiệm")], selected: AppSettings.audioQuality == .best ? 0 : 1)
            control.addTarget(self, action: #selector(qualityChanged(_:)), for: .valueChanged)
            cell.accessoryView = control
            cell.textLabel?.text = L("Chất lượng")
            cell.selectionStyle = .none

        case .reverb:
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = L("Reverb (độ vang)")
            cell.detailTextLabel?.text = ReverbSettings.enabled ? Lf("Bật · %@%", Int(round(ReverbSettings.amount * 100))) : L("Tắt")
            cell.accessoryType = .disclosureIndicator

        case .language:
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = L("Ngôn ngữ")
            cell.detailTextLabel?.text = Lang.setting.title
            cell.accessoryType = .disclosureIndicator

        case .crossfade:
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = L("Chuyển bài mượt")
            cell.detailTextLabel?.text = SettingsViewController.crossfadeTitle(CrossfadeSettings.seconds)
            cell.accessoryType = .disclosureIndicator

        case .translateLang:
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = L("Dịch lời sang")
            cell.detailTextLabel?.text = TranslateSettings.targetName
            cell.accessoryType = .disclosureIndicator

        case .downloadsInfo:
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = L("Bài đã tải xuống")
            let size = ByteCountFormatter.string(fromByteCount: Library.shared.totalDownloadBytes(), countStyle: .file)
            cell.detailTextLabel?.text = Lf("%@ bài · %@", Library.shared.downloads.count, size)
            cell.selectionStyle = .none

        case .clearDownloads:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = L("Xoá tất cả bài đã tải")
            cell.textLabel?.textColor = Theme.accent

        case .clearHistory:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = L("Xoá lịch sử nghe")
            cell.textLabel?.textColor = Theme.accent

        case .backup:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = L("Sao lưu dữ liệu ngay…")
            cell.textLabel?.textColor = Theme.accent

        case .restore:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = L("Khôi phục từ tệp sao lưu…")
            cell.textLabel?.textColor = Theme.accent

        case .accounts, .mochyAccount, .recap, .importList, .lastfm, .advanced:
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            switch row {
            case .accounts:
                cell.textLabel?.text = L("Tài khoản nhạc (đồng bộ playlist)")
                let n = AccountSync.shared.linkedServices.count
                cell.detailTextLabel?.text = n == 0 ? L("Chưa liên kết") : Lf("%@ tài khoản", n)
            case .mochyAccount:
                cell.textLabel?.text = L("Tài khoản Mochy")
                cell.detailTextLabel?.text = MochyCloud.shared.isLoggedIn ? "@" + (MochyCloud.shared.username ?? "") : L("Chưa đăng nhập")
            case .advanced: cell.textLabel?.text = L("Nguồn nâng cao (Canvas, Spicy Lyrics)")
            case .recap: cell.textLabel?.text = "Recap"
            case .importList: cell.textLabel?.text = L("Nhập playlist từ link")
            default:
                cell.textLabel?.text = "Last.fm"
                cell.detailTextLabel?.text = LastFM.shared.isLoggedIn ? LastFM.shared.username : L("Chưa đăng nhập")
            }
            cell.accessoryType = .disclosureIndicator

        case .credits:
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = L("Credit và giấy phép")
            cell.detailTextLabel?.text = "Mochy Music"
            cell.accessoryType = .disclosureIndicator

        case .version:
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = L("Phiên bản hiện tại")
            cell.detailTextLabel?.text = "\(AppInfo.version) (build \(AppInfo.build))"
            cell.selectionStyle = .none

        case .channel:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = L("Kênh cập nhật")
            let control = M3Segmented(items: [UpdateChannel.stable.title, UpdateChannel.dev.title], selected: AppSettings.channel == .stable ? 0 : 1)
            control.addTarget(self, action: #selector(channelChanged(_:)), for: .valueChanged)
            cell.accessoryView = control
            cell.selectionStyle = .none

        case .videoBackdrop:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = L("Video làm nền khi phát (nếu có)")
            let toggle = M3Switch()
            toggle.isOn = AppSettings.videoBackdrop
            toggle.addTarget(self, action: #selector(videoBackdropChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none

        case .autoCheck:
            cell = M3Cell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = L("Tự động kiểm tra cập nhật")
            let toggle = M3Switch()
            toggle.isOn = AppSettings.autoCheck
            toggle.addTarget(self, action: #selector(autoCheckChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none

        case .checkNow:
            cell = M3Cell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = L("Kiểm tra cập nhật ngay")
            cell.textLabel?.textColor = Theme.accent
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = Theme.secondaryText
            if updater.isChecking {
                cell.detailTextLabel?.text = L("Đang kiểm tra…")
                let spinner = UIActivityIndicatorView(style: Theme.spinnerStyle())
                spinner.startAnimating()
                cell.accessoryView = spinner
            } else if updater.lastMessage.isEmpty {
                cell.detailTextLabel?.text = nil
            } else {
                cell.detailTextLabel?.text = updater.lastMessage
            }

        case .updateAvailable:
            cell = M3Cell(style: .subtitle, reuseIdentifier: nil)
            if let info = updater.available {
                cell.textLabel?.text = Lf("Có bản mới: %@ (build %@)", info.version, info.build)
                let kind = info.channel == "dev" ? L("Bản thử nghiệm") : L("Bản ổn định")
                cell.detailTextLabel?.text = Lf("%@ · chạm để xem chi tiết và tải về", kind)
            }
            cell.textLabel?.textColor = Theme.accent
            cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            cell.detailTextLabel?.textColor = Theme.secondaryText
            cell.accessoryType = .disclosureIndicator

        case .info(let title, let value):
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = value
            cell.selectionStyle = .none

        case .link(let title, let value, _):
            cell = M3Cell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = value
            cell.accessoryType = .disclosureIndicator
        }
        let keepColor = cell.textLabel?.textColor
        Theme.style(cell: cell, grouped: true)
        cell.backgroundColor = Theme.cellBackground
        if case .updateAvailable = row {} else { cell.textLabel?.font = Theme.regular(16) }
        cell.detailTextLabel?.font = Theme.regular(14)
        switch row {
        case .checkNow, .updateAvailable, .clearDownloads, .clearHistory, .backup, .restore:
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
        case .accounts:
            AccountsSheetViewController.present(from: self)
        case .mochyAccount:
            navigationController?.pushViewController(MochyAccountViewController(), animated: true)
        case .reverb:
            ReverbPanelViewController.present(from: self)
        case .translateLang:
            chooseTranslateLanguage()
        case .crossfade:
            chooseCrossfade()
        case .language:
            chooseLanguage()
        case .recap:
            navigationController?.pushViewController(RecapViewController(), animated: true)
        case .importList:
            navigationController?.pushViewController(ImportViewController(), animated: true)
        case .advanced:
            navigationController?.pushViewController(SourcesViewController(), animated: true)
        case .lastfm:
            navigationController?.pushViewController(LastFMViewController(), animated: true)
        case .credits:
            navigationController?.pushViewController(CreditsViewController(), animated: true)
        case .clearDownloads:
            confirm(L("Xoá tất cả bài đã tải xuống?"), button: L("Xoá")) { Library.shared.removeAllDownloads() }
        case .clearHistory:
            confirm(L("Xoá toàn bộ lịch sử nghe?"), button: L("Xoá")) { Library.shared.clearHistory() }
        case .backup:
            backupNow()
        case .restore:
            pickBackup()
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


    // MARK: - Hành động

    @objc private func themeChanged(_ sender: M3Segmented) {
        guard let mode = ThemeMode(rawValue: sender.selectedSegmentIndex) else { return }
        Theme.mode = mode
        NotificationCenter.default.post(name: .themeChanged, object: nil)
    }

    private func chooseLanguage() {
        let sheet = UIAlertController(title: L("Ngôn ngữ"), message: L("Áp dụng đầy đủ sau khi mở lại app."), preferredStyle: .actionSheet)
        for lang in [AppLanguage.auto, .vietnamese, .english] {
            let title = (lang == Lang.setting ? "✓ " : "") + lang.title
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                Lang.setting = lang
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel, handler: nil))
        if let pop = sheet.popoverPresentationController { pop.sourceView = view; pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1); pop.permittedArrowDirections = [] }
        present(sheet, animated: true, completion: nil)
    }

    static func crossfadeTitle(_ seconds: Int) -> String {
        if seconds < 0 { return L("Tắt") }
        if seconds == 0 { return L("Liền mạch") }
        return Lf("%@ giây", seconds)
    }

    private func chooseCrossfade() {
        let sheet = UIAlertController(title: L("Chuyển bài mượt"),
                                      message: L("Tải sẵn bài kế tiếp để không bị im giữa hai bài. \"Liền mạch\" nối ngay khi hết bài; số giây là thời gian hai bài hoà vào nhau."),
                                      preferredStyle: .actionSheet)
        for value in CrossfadeSettings.options {
            let title = (value == CrossfadeSettings.seconds ? "✓ " : "") + SettingsViewController.crossfadeTitle(value)
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                CrossfadeSettings.seconds = value
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel, handler: nil))
        if let pop = sheet.popoverPresentationController { pop.sourceView = view; pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1); pop.permittedArrowDirections = [] }
        present(sheet, animated: true, completion: nil)
    }

    private func chooseTranslateLanguage() {
        let sheet = UIAlertController(title: L("Dịch lời sang"), message: L("Nút dịch nằm cạnh tên bài trong màn hình lời."), preferredStyle: .actionSheet)
        for lang in TranslateSettings.languages {
            let title = (lang.code == TranslateSettings.target ? "✓ " : "") + lang.name
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                TranslateSettings.target = lang.code
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel, handler: nil))
        if let pop = sheet.popoverPresentationController { pop.sourceView = view; pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1); pop.permittedArrowDirections = [] }
        present(sheet, animated: true, completion: nil)
    }

    @objc private func qualityChanged(_ sender: M3Segmented) {
        AppSettings.audioQuality = sender.selectedSegmentIndex == 0 ? .best : .saver
    }

    private func confirm(_ message: String, button: String, _ action: @escaping () -> Void) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: button, style: .destructive) { _ in action() })
        present(alert, animated: true, completion: nil)
    }

    @objc private func channelChanged(_ sender: M3Segmented) {
        AppSettings.channel = sender.selectedSegmentIndex == 0 ? .stable : .dev
        Updater.shared.channelDidChange()
    }

    @objc private func videoBackdropChanged(_ sender: M3Switch) {
        AppSettings.videoBackdrop = sender.isOn
    }

    @objc private func autoCheckChanged(_ sender: M3Switch) {
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
        alert.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func presentUpdateSheet() {
        guard let info = Updater.shared.available else { return }
        var message = Lf("Phiên bản %@ (build %@)", info.version, info.build)
        if !info.commit.isEmpty { message += ", commit \(info.commit)" }
        message += "\n"
        message += info.signed ? L("Chữ ký số: hợp lệ ✓") : L("Chữ ký số: chưa có (chỉ kiểm SHA-256)")
        if !info.notes.isEmpty {
            message += "\n\n" + String(info.notes.prefix(600))
        }
        message += Lf("\n\nDữ liệu của bạn được sao lưu tự động trước khi tải. Khi ký .ipa hãy giữ nguyên Bundle ID %@ và cài đè lên bản cũ để không mất dữ liệu.", UpdateConfig.appId)
        let alert = UIAlertController(title: L("Có bản cập nhật"), message: message, preferredStyle: .alert)

        // Cả hai nguồn (.ipa để ký bằng ESign…, .deb cho Sileo/Filza) đều hiện ra; nguồn hợp với cách cài của bạn ghi "khuyên dùng".
        let recommended = Updater.shared.preferredFile(for: info)
        var files: [UpdateFile] = []
        if let first = recommended { files.append(first) }
        for other in [info.ipa, info.deb] {
            if let other = other, !files.contains(where: { $0.name == other.name }) { files.append(other) }
        }
        for file in files {
            let kind = file.name.lowercased().hasSuffix(".deb") ? ".deb (Sileo, Filza)" : L(".ipa (ký bằng ESign…)")
            let star = file.name == recommended?.name ? L(" — khuyên dùng") : ""
            alert.addAction(UIAlertAction(title: Lf("Tải %@%@ · %@", kind, star, sizeText(file.size)), style: .default) { [weak self] _ in
                self?.startDownload(file)
            })
        }
        if AppInfo.isJailbreakInstall && info.channel == "stable" {
            alert.addAction(UIAlertAction(title: L("Mở Sileo (nguồn repo)"), style: .default) { [weak self] _ in
                self?.open("sileo://package/\(UpdateConfig.appId)")
            })
        }
        alert.addAction(UIAlertAction(title: L("Xem trên GitHub"), style: .default) { [weak self] _ in
            self?.open(UpdateConfig.releasesPage)
        })
        alert.addAction(UIAlertAction(title: L("Để sau"), style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func startDownload(_ file: UpdateFile) {
        // Sao lưu dữ liệu trước khi cập nhật, phòng khi bản ký lại dùng Bundle ID khác hoặc phải gỡ app.
        BackupManager.backup(name: "truoc-cap-nhat")
        let alert = UIAlertController(title: L("Đang tải"), message: "\(file.name)\n0%", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel) { _ in
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
                    self?.showMessage(L("Tải thất bại"), error.message)
                }
            }
        })
    }

    private func presentDownloaded(_ url: URL, file: UpdateFile) {
        let hint: String
        if file.name.lowercased().hasSuffix(".deb") {
            hint = L("Chọn Sileo (hoặc Filza) rồi bấm Cài đặt.")
        } else {
            hint = L("Chọn ESign / Sideloadly / AltStore để ký rồi cài.")
        }
        let alert = UIAlertController(title: L("Đã tải và xác minh"),
                                      message: Lf("%@\nSHA-256 khớp với bản phát hành.\n%@", file.name, hint),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("Mở bằng ứng dụng khác…"), style: .default) { [weak self] _ in
            self?.openInOtherApp(url)
        })
        alert.addAction(UIAlertAction(title: L("Chia sẻ / Lưu vào Tệp…"), style: .default) { [weak self] _ in
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self?.present(controller, animated: true, completion: nil)
        })
        alert.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func openInOtherApp(_ url: URL) {
        let controller = UIDocumentInteractionController(url: url)
        documentController = controller
        let anchor = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        if !controller.presentOpenInMenu(from: anchor, in: view, animated: true) {
            showMessage(L("Không có ứng dụng phù hợp"),
                        L("Không tìm thấy ứng dụng nào mở được tệp này. Hãy dùng \"Chia sẻ / Lưu vào Tệp…\" rồi mở bằng Sileo, Filza hoặc ESign."))
        }
    }

    // MARK: - Sao lưu / khôi phục

    private func backupNow() {
        guard let url = BackupManager.backup(name: BackupManager.timestampName()) else {
            showMessage(L("Không sao lưu được"), L("Không ghi được tệp sao lưu."))
            return
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(controller, animated: true, completion: nil)
    }

    private func pickBackup() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.json", "public.data", "public.text"], in: .import)
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        switch BackupManager.restore(from: url) {
        case .success(let added):
            showMessage(L("Đã khôi phục"), added == 0 ? L("Không có mục nào mới, dữ liệu hiện tại đã đủ.") : Lf("Đã gộp thêm %@ mục vào thư viện.", added))
        case .failure(let error):
            showMessage(L("Không khôi phục được"), error.message)
        }
    }
}
