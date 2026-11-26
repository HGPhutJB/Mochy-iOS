import UIKit

/// Danh sách bài của Yêu thích / Đã tải / Lịch sử / một playlist, có nút Phát và Phát ngẫu nhiên.
final class SongListViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITableViewDataSource, UITableViewDelegate {
    enum Source {
        case liked
        case downloads
        case history
        case playlist(String)
    }

    private let source: Source
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let header = UIView()
    private let downloadButton = DownloadRingButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    private let cover = UIImageView()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private let playButton = PressableButton(type: .custom)
    private let shuffleButton = PressableButton(type: .custom)
    private let emptyLabel = UILabel()
    private var shownCover: URL?
    private var animatedOnce = false

    init(source: Source) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Dữ liệu

    private var songs: [Song] {
        switch source {
        case .liked: return Library.shared.liked
        case .downloads: return Library.shared.downloads
        case .history: return Library.shared.history.map { $0.song }
        case .playlist(let id): return Library.shared.playlist(id: id)?.songs ?? []
        }
    }

    private var listTitle: String {
        switch source {
        case .liked: return L("Yêu thích")
        case .downloads: return L("Đã tải xuống")
        case .history: return L("Lịch sử nghe")
        case .playlist(let id): return Library.shared.playlist(id: id)?.name ?? "Playlist"
        }
    }

    private var emptyText: String {
        switch source {
        case .liked: return L("Chưa có bài yêu thích.\nBấm biểu tượng trái tim ở màn hình đang phát.")
        case .downloads: return L("Chưa tải bài nào.\nChọn \"Tải xuống\" trong menu \"…\" của một bài.")
        case .history: return L("Lịch sử trống.\nCác bài bạn nghe sẽ hiện ở đây.")
        case .playlist: return L("Playlist trống.\nChọn \"Thêm vào playlist…\" trong menu \"…\" của một bài.")
        }
    }

    private var isPlaylist: Bool {
        if case .playlist = source { return true }
        return false
    }

    // MARK: - Dựng giao diện

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SongCell.self, forCellReuseIdentifier: SongCell.reuseId)
        tableView.rowHeight = 66
        tableView.separatorColor = Theme.separator
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 78, bottom: 0, right: 0)
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 16
        cover.backgroundColor = Theme.placeholder
        header.addSubview(cover)
        nameLabel.font = Theme.heavy(24)
        nameLabel.textColor = Theme.primaryText
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        countLabel.font = Theme.regular(14)
        countLabel.textColor = Theme.secondaryText
        countLabel.textAlignment = .center
        header.addSubview(nameLabel)
        header.addSubview(countLabel)

        playButton.setTitle(L("  Phát"), for: .normal)
        playButton.setImage(Icons.play(15), for: .normal)
        shuffleButton.setTitle(L(" Ngẫu nhiên"), for: .normal)
        shuffleButton.setImage(Icons.shuffle(17), for: .normal)
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        downloadButton.isHidden = true
        header.addSubview(downloadButton)
        for b in [playButton, shuffleButton] {
            b.tintColor = Theme.accent
            b.setTitleColor(Theme.accent, for: .normal)
            b.titleLabel?.font = Theme.bold(15)
            b.backgroundColor = Theme.chip
            b.layer.cornerRadius = 22
            header.addSubview(b)
        }
        playButton.addTarget(self, action: #selector(playAll), for: .touchUpInside)
        shuffleButton.addTarget(self, action: #selector(shuffleAll), for: .touchUpInside)

        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = Theme.regular(15)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.text = emptyText
        header.addSubview(emptyLabel)

        var items: [UIBarButtonItem] = []
        switch source {
        case .playlist:
            items.append(moreItem())
        case .history:
            items.append(UIBarButtonItem(title: L("Xoá hết"), style: .plain, target: self, action: #selector(clearHistory)))
        case .downloads:
            items.append(UIBarButtonItem(title: L("Xoá hết"), style: .plain, target: self, action: #selector(clearDownloads)))
        case .liked:
            break
        }
        navigationItem.rightBarButtonItems = items

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(dataChanged), name: .libraryChanged, object: nil)
        center.addObserver(self, selector: #selector(downloadProgressChanged), name: .downloadChanged, object: nil)
        center.addObserver(self, selector: #selector(dataChanged), name: .playerStateChanged, object: nil)
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHeader()
    }

    private func layoutHeader() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let coverSize: CGFloat = min(200, width - 120)
        let emptyExtra: CGFloat = songs.isEmpty ? 110 : 0
        let height: CGFloat = 16 + coverSize + 16 + 58 + 22 + 16 + 44 + 20 + emptyExtra
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        if header.frame != frame {
            header.frame = frame
            tableView.tableHeaderView = header
        }
        cover.frame = CGRect(x: (width - coverSize) / 2, y: 16, width: coverSize, height: coverSize)
        nameLabel.frame = CGRect(x: 20, y: cover.frame.maxY + 16, width: width - 40, height: 58)
        countLabel.frame = CGRect(x: 20, y: nameLabel.frame.maxY, width: width - 40, height: 22)
        let rowY = countLabel.frame.maxY + 16
        emptyLabel.frame = CGRect(x: 32, y: rowY + 44 + 24, width: width - 64, height: 70)
        if showsDownload {
            let avail = width - 32 - 24 - 44
            let playW = floor(avail * 0.47)
            playButton.frame = CGRect(x: 16, y: rowY, width: playW, height: 44)
            shuffleButton.frame = CGRect(x: 16 + playW + 12, y: rowY, width: avail - playW, height: 44)
            downloadButton.frame = CGRect(x: width - 16 - 44, y: rowY, width: 44, height: 44)
        } else {
            let buttonWidth = (width - 32 - 12) / 2
            playButton.frame = CGRect(x: 16, y: rowY, width: buttonWidth, height: 44)
            shuffleButton.frame = CGRect(x: 16 + buttonWidth + 12, y: rowY, width: buttonWidth, height: 44)
        }
    }

    @objc private func downloadProgressChanged() {
        updateDownloadButton()
    }

    @objc private func dataChanged() {
        if !tableView.isEditing { refresh() }
    }

    private var lastSignature = ""

    private func refresh() {
        let list = songs
        var customFile = ""
        if case .playlist(let pid) = source { customFile = Library.shared.playlist(id: pid)?.customCover ?? "" }
        let sig = listTitle + "|" + customFile + "|" + list.map { $0.videoId }.joined(separator: ",") + "|" + (PlayerEngine.shared.currentSong?.videoId ?? "")
        if sig == lastSignature && !tableView.isDragging {
            updateDownloadButton()
            return
        }
        lastSignature = sig
        nameLabel.text = listTitle
        var count = Lf("%@ bài", list.count)
        if case .downloads = source {
            count += " · " + ByteCountFormatter.string(fromByteCount: Library.shared.totalDownloadBytes(), countStyle: .file)
        }
        countLabel.text = count
        emptyLabel.isHidden = !list.isEmpty
        playButton.isEnabled = !list.isEmpty
        shuffleButton.isEnabled = !list.isEmpty
        playButton.alpha = list.isEmpty ? 0.4 : 1
        shuffleButton.alpha = list.isEmpty ? 0.4 : 1
        var custom: UIImage?
        if case .playlist(let pid) = source, let pl = Library.shared.playlist(id: pid) { custom = PlaylistCover.image(for: pl) }
        if let custom = custom {
            shownCover = nil
            cover.image = custom
        } else if let url = list.first?.largeThumbnailURL {
            if shownCover != url {
                shownCover = url
                ImageLoader.shared.load(url) { [weak self] image in
                    guard let self = self, self.shownCover == url else { return }
                    UIView.transition(with: self.cover, duration: 0.3, options: .transitionCrossDissolve, animations: {
                        self.cover.image = image
                    }, completion: nil)
                }
            }
        } else {
            shownCover = nil
            cover.image = nil
        }
        tableView.reloadData()
        layoutHeader()
        updateDownloadButton()
        if !animatedOnce && !list.isEmpty {
            animatedOnce = true
            tableView.animateRowsIn()
        }
    }

    // MARK: - Hành động

    @objc private func playAll() {
        let list = songs
        guard !list.isEmpty else { return }
        PlayerEngine.shared.setShuffle(false)
        PlayerEngine.shared.play(queue: list, index: 0, context: listTitle)
    }

    private var downloadBase = 0.0

    private var showsDownload: Bool {
        if case .downloads = source { return false }
        return true
    }

    @objc private func downloadTapped() {
        let list = songs
        guard !list.isEmpty else { return }
        let manager = DownloadManager.shared
        switch downloadButton.phase {
        case .done:
            Toast.show(L("Tất cả bài trong danh sách đã được tải"))
        case .active:
            manager.cancelQueue()
            for s in list where manager.isActive(s.videoId) { manager.cancel(s.videoId) }
            Toast.show(L("Đã dừng tải"))
        case .idle:
            let todo = list.filter { !Library.shared.isDownloaded($0) && !manager.isActive($0.videoId) }
            downloadBase = Double(list.count - todo.count)
            let added = manager.enqueue(todo)
            Toast.show(Lf("Đang tải %@ bài (2 bài cùng lúc)…", added))
        }
        updateDownloadButton()
    }

    private func updateDownloadButton() {
        guard showsDownload else { return }
        let list = songs
        downloadButton.isHidden = list.isEmpty
        guard !list.isEmpty else { return }
        let manager = DownloadManager.shared
        var done = 0.0, partial = 0.0
        var busy = false
        for s in list {
            if Library.shared.isDownloaded(s) { done += 1 }
            else if let p = manager.progress[s.videoId] { partial += p; busy = true }
            else if manager.isQueued(s.videoId) { busy = true }
        }
        let total = Double(list.count)
        if done >= total {
            downloadButton.set(.done)
        } else if busy {
            let base = min(downloadBase, done)
            let span = max(1, total - base)
            downloadButton.setProgress((done - base + partial) / span)
        } else {
            downloadButton.set(.idle)
        }
    }

    @objc private func shuffleAll() {
        PlayerEngine.shared.playShuffled(songs)
    }

    private func moreItem() -> UIBarButtonItem {
        return UIBarButtonItem(image: Icons.more(24).withRenderingMode(.alwaysTemplate), style: .plain, target: self, action: #selector(playlistOptions))
    }

    private func setEditingMode(_ editing: Bool) {
        tableView.setEditing(editing, animated: true)
        navigationItem.rightBarButtonItems = editing
            ? [UIBarButtonItem(title: L("Xong"), style: .done, target: self, action: #selector(finishEditing))]
            : [moreItem()]
        if !editing { refresh() }
    }

    @objc private func finishEditing() { setEditingMode(false) }

    /// Một nút ⋯ gộp mọi tuỳ chọn của playlist (sắp xếp, đổi tên, ảnh bìa, tải, xoá).
    @objc private func playlistOptions() {
        guard case .playlist(let id) = source, let list = Library.shared.playlist(id: id) else { return }
        let sheet = UIAlertController(title: list.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L("Sắp xếp bài hát"), style: .default) { [weak self] _ in self?.setEditingMode(true) })
        sheet.addAction(UIAlertAction(title: L("Đổi tên"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            SongActions.promptNewPlaylist(from: self, initial: list.name, title: L("Đổi tên playlist"), confirm: L("Lưu")) { name in
                Library.shared.renamePlaylist(id: id, name: name)
            }
        })
        sheet.addAction(UIAlertAction(title: L("Đặt ảnh bìa…"), style: .default) { [weak self] _ in self?.coverOptions() })
        sheet.addAction(UIAlertAction(title: L("Tải tất cả bài"), style: .default) { [weak self] _ in self?.downloadTapped() })
        sheet.addAction(UIAlertAction(title: L("Xoá playlist"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            DeleteDialogViewController.present(from: self, title: L("Xoá playlist này?"),
                                               message: LibraryViewController.deleteMessage(for: list)) {
                Library.shared.deletePlaylist(id: id)
                self.navigationController?.popViewController(animated: true)
            }
        })
        sheet.addAction(UIAlertAction(title: L("Đóng"), style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(sheet, animated: true, completion: nil)
    }

    // MARK: - Ảnh bìa playlist

    private func coverOptions() {
        guard case .playlist(let id) = source, let list = Library.shared.playlist(id: id) else { return }
        let sheet = UIAlertController(title: L("Ảnh bìa playlist"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L("Chọn từ thư viện ảnh"), style: .default) { [weak self] _ in
            guard let self = self, UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true   // cắt vuông ngay trong bộ chọn
            picker.delegate = self
            self.present(picker, animated: true)
        })
        if !list.songs.isEmpty {
            sheet.addAction(UIAlertAction(title: L("Dùng ảnh bìa của một bài hát"), style: .default) { [weak self] _ in self?.songCoverPicker() })
        }
        if list.customCover != nil {
            sheet.addAction(UIAlertAction(title: L("Xoá ảnh bìa (về tự động)"), style: .destructive) { [weak self] _ in
                Library.shared.clearCustomCover(id: id)
                self?.lastSignature = ""
                self?.refresh()
            })
        }
        sheet.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(sheet, animated: true)
    }

    private func songCoverPicker() {
        guard case .playlist(let id) = source, let list = Library.shared.playlist(id: id) else { return }
        let sheet = UIAlertController(title: L("Chọn bài để lấy ảnh bìa"), message: nil, preferredStyle: .actionSheet)
        for song in list.songs.prefix(12) {
            sheet.addAction(UIAlertAction(title: song.title, style: .default) { _ in
                guard let url = song.largeThumbnailURL else { return }
                ImageLoader.shared.load(url) { [weak self] image in
                    guard let image = image else { Toast.show(L("Không tải được ảnh bìa")); return }
                    Library.shared.setCustomCover(id: id, image: image)
                    self?.lastSignature = ""
                    self?.refresh()
                }
            })
        }
        sheet.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel, handler: nil))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(sheet, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true)
        guard let picked = image, case .playlist(let id) = source else { return }
        Library.shared.setCustomCover(id: id, image: picked)
        lastSignature = ""
        refresh()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    @objc private func clearHistory() {
        confirm(L("Xoá toàn bộ lịch sử nghe?"), button: L("Xoá hết")) { Library.shared.clearHistory() }
    }

    @objc private func clearDownloads() {
        confirm(L("Xoá tất cả bài đã tải xuống?"), button: L("Xoá hết")) { Library.shared.removeAllDownloads() }
    }

    private func confirm(_ message: String, button: String, _ action: @escaping () -> Void) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("Huỷ"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: button, style: .destructive) { _ in action() })
        present(alert, animated: true, completion: nil)
    }

    private func removeSong(at index: Int) {
        switch source {
        case .liked: Library.shared.removeLiked(at: index)
        case .downloads:
            let list = Library.shared.downloads
            if index < list.count { Library.shared.removeDownload(list[index]) }
        case .history: Library.shared.removeHistory(at: index)
        case .playlist(let id): Library.shared.removeSong(at: index, fromPlaylist: id)
        }
    }

    // MARK: - Bảng

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return songs.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SongCell.reuseId, for: indexPath) as! SongCell
        let list = songs
        guard indexPath.row < list.count else { return cell }
        let song = list[indexPath.row]
        cell.configure(song: song, isCurrent: PlayerEngine.shared.currentSong == song)
        let row = indexPath.row
        cell.onMore = { [weak self, weak cell] in
            guard let self = self else { return }
            SongActions.present(for: song, from: self, sourceView: cell, removeTitle: L("Xoá khỏi danh sách")) {
                self.removeSong(at: row)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        PlayerEngine.shared.play(queue: songs, index: indexPath.row, context: listTitle)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        removeSong(at: indexPath.row)
        if tableView.isEditing { tableView.reloadData() }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return isPlaylist
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        if case .playlist(let id) = source {
            Library.shared.moveSong(from: sourceIndexPath.row, to: destinationIndexPath.row, inPlaylist: id)
        }
    }
}
