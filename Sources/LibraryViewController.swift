import UIKit

/// Dòng trong thư viện: ô icon/ảnh bo góc + tên + số lượng.
final class LibraryRowCell: UITableViewCell {
    static let reuseId = "LibraryRowCell"
    private let tile = UIImageView()
    private let glyph = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var representedURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        selectedBackgroundView = Theme.selectionView()
        accessoryType = .disclosureIndicator

        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.contentMode = .scaleAspectFill
        tile.clipsToBounds = true
        tile.layer.cornerRadius = 10
        contentView.addSubview(tile)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.contentMode = .scaleAspectFit
        glyph.tintColor = UIColor.white
        contentView.addSubview(glyph)

        titleLabel.font = Theme.bold(17)
        titleLabel.textColor = Theme.primaryText
        detailLabel.font = Theme.regular(14)
        detailLabel.textColor = Theme.secondaryText
        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            tile.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 52),
            tile.heightAnchor.constraint(equalToConstant: 52),
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 26),
            glyph.heightAnchor.constraint(equalToConstant: 26),
            stack.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        tile.image = nil
        glyph.image = nil
    }

    func configure(title: String, detail: String, icon: UIImage?, color: UIColor, coverURL: URL? = nil, coverImage: UIImage? = nil) {
        titleLabel.text = title
        detailLabel.text = detail
        tile.backgroundColor = color
        tile.image = nil
        glyph.image = icon
        representedURL = coverURL
        if let img = coverImage {
            glyph.image = nil
            tile.image = img
        } else if let url = coverURL {
            glyph.image = nil
            ImageLoader.shared.load(url) { [weak self] image in
                guard let self = self, self.representedURL == url else { return }
                self.tile.image = image
            }
        }
    }
}

/// Tab "Thư viện": Yêu thích, Đã tải xuống, Lịch sử và danh sách playlist.
final class LibraryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .grouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("Thư viện")
        view.backgroundColor = Theme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: L("Playlist mới"), style: .plain, target: self, action: #selector(newPlaylist))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: L("Nhập"), style: .plain, target: self, action: #selector(openImport))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(LibraryRowCell.self, forCellReuseIdentifier: LibraryRowCell.reuseId)
        tableView.rowHeight = 72
        tableView.separatorColor = Theme.separator
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 82, bottom: 0, right: 0)
        tableView.tableFooterView = UIView()
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(dataChanged), name: .libraryChanged, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func dataChanged() {
        tableView.reloadData()
    }

    @objc private func openImport() {
        navigationController?.pushViewController(ImportViewController(), animated: true)
    }

    @objc private func newPlaylist() {
        SongActions.promptNewPlaylist(from: self) { name in
            Library.shared.createPlaylist(name: name)
        }
    }

    // MARK: - Bảng

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 3 : Library.shared.playlists.count
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == 1 && !Library.shared.playlists.isEmpty ? 44 : 0.01
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1, !Library.shared.playlists.isEmpty else { return nil }
        let container = UIView()
        container.backgroundColor = Theme.background
        let label = UILabel()
        label.text = "Playlist"
        label.font = Theme.heavy(20)
        label.textColor = Theme.primaryText
        label.frame = CGRect(x: 16, y: 12, width: 200, height: 28)
        container.addSubview(label)
        return container
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LibraryRowCell.reuseId, for: indexPath) as! LibraryRowCell
        let library = Library.shared
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                cell.configure(title: L("Yêu thích"), detail: Lf("%@ bài", library.liked.count),
                               icon: Icons.heart(26, filled: true), color: Theme.accent)
            case 1:
                let size = ByteCountFormatter.string(fromByteCount: library.totalDownloadBytes(), countStyle: .file)
                cell.configure(title: L("Đã tải xuống"), detail: Lf("%@ bài · %@", library.downloads.count, size),
                               icon: Icons.download(26), color: UIColor(red: 0.2, green: 0.6, blue: 0.95, alpha: 1))
            default:
                cell.configure(title: L("Lịch sử nghe"), detail: Lf("%@ lượt nghe", library.history.count),
                               icon: Icons.clock(26), color: UIColor(red: 0.45, green: 0.35, blue: 0.85, alpha: 1))
            }
        } else {
            let list = library.playlists[indexPath.row]
            cell.configure(title: list.name, detail: Lf("%@ bài", list.songs.count), icon: Icons.music(26),
                           color: Theme.placeholder, coverURL: list.songs.first?.thumbnailURL,
                           coverImage: PlaylistCover.image(for: list) ?? MusicCover.image(for: list.cover))
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let vc: SongListViewController
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0: vc = SongListViewController(source: .liked)
            case 1: vc = SongListViewController(source: .downloads)
            default: vc = SongListViewController(source: .history)
            }
        } else {
            vc = SongListViewController(source: .playlist(Library.shared.playlists[indexPath.row].id))
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, indexPath.section == 1 else { return }
        let list = Library.shared.playlists[indexPath.row]
        DeleteDialogViewController.present(from: self, title: L("Xoá playlist này?"), message: LibraryViewController.deleteMessage(for: list),
                                           onConfirm: { Library.shared.deletePlaylist(id: list.id) },
                                           onCancel: { [weak self] in self?.tableView.reloadData() })
    }

    static func deleteMessage(for list: Playlist) -> String {
        var text = Lf("Playlist “%@” sẽ bị xoá khỏi thư viện. Các bài đã thích và đã tải xuống vẫn được giữ.", list.name)
        if (list.sourceURL ?? "").hasPrefix("acct:") { text += L(" Playlist đồng bộ này sẽ không được tạo lại nữa.") }
        return text + L(" Không thể hoàn tác.")
    }
}
