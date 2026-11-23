import UIKit

/// Trang nghệ sĩ (ảnh, bài nổi bật, album, đĩa đơn…) và trang album của YouTube Music.
final class MusicPageViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    enum Kind {
        case artist(id: String?, name: String)
        case album(id: String, title: String)
    }

    /// Mở trang nghệ sĩ dưới dạng cửa sổ phủ (dùng được từ màn hình đang phát lẫn danh sách).
    static func present(artist name: String, id: String?, from vc: UIViewController) {
        let page = MusicPageViewController(kind: .artist(id: id, name: name))
        let nav = UINavigationController(rootViewController: page)
        nav.navigationBar.barStyle = Theme.isDark ? .black : .default
        vc.present(nav, animated: true, completion: nil)
    }

    private let kind: Kind
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let header = UIView()
    private let cover = UIImageView()
    private let nameLabel = UILabel()
    private let infoLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .gray)
    private let messageLabel = UILabel()
    private var songs: [Song] = []
    private var sections: [ArtistSection] = []
    private var pageName = ""

    init(kind: Kind) {
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        switch kind {
        case .artist(_, let name): pageName = name
        case .album(_, let title): pageName = title
        }
        title = pageName
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Đóng", style: .plain, target: self, action: #selector(close))
        }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.separator
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 66
        tableView.register(SongCell.self, forCellReuseIdentifier: SongCell.reuseId)
        tableView.register(CardCell.self, forCellReuseIdentifier: CardCell.reuseId)
        view.addSubview(tableView)

        buildHeader()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = Theme.regular(15)
        messageLabel.textColor = Theme.secondaryText
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        view.addSubview(spinner)
        view.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30)
        ])
        load()
    }

    @objc private func close() { dismiss(animated: true, completion: nil) }

    private func buildHeader() {
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 300)
        header.autoresizingMask = [.flexibleWidth]
        cover.frame = CGRect(x: (view.bounds.width - 150) / 2, y: 16, width: 150, height: 150)
        cover.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.backgroundColor = Theme.placeholder
        if case .artist = kind { cover.layer.cornerRadius = 75 } else { cover.layer.cornerRadius = 10 }
        header.addSubview(cover)
        nameLabel.frame = CGRect(x: 20, y: 176, width: view.bounds.width - 40, height: 30)
        nameLabel.autoresizingMask = [.flexibleWidth]
        nameLabel.font = Theme.bold(24)
        nameLabel.textColor = Theme.primaryText
        nameLabel.textAlignment = .center
        nameLabel.text = pageName
        header.addSubview(nameLabel)
        infoLabel.frame = CGRect(x: 20, y: 208, width: view.bounds.width - 40, height: 20)
        infoLabel.autoresizingMask = [.flexibleWidth]
        infoLabel.font = Theme.regular(14)
        infoLabel.textColor = Theme.secondaryText
        infoLabel.textAlignment = .center
        header.addSubview(infoLabel)
        for (button, title) in [(playButton, "Phát"), (shuffleButton, "Ngẫu nhiên")] {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = Theme.bold(16)
            button.layer.cornerRadius = 10
            button.isHidden = true
        }
        playButton.backgroundColor = Theme.accent
        playButton.setTitleColor(.white, for: .normal)
        shuffleButton.backgroundColor = Theme.chip
        shuffleButton.setTitleColor(Theme.accent, for: .normal)
        playButton.addTarget(self, action: #selector(playAll), for: .touchUpInside)
        shuffleButton.addTarget(self, action: #selector(shuffleAll), for: .touchUpInside)
        header.addSubview(playButton)
        header.addSubview(shuffleButton)
        tableView.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        let each = (w - 48) / 2
        playButton.frame = CGRect(x: 16, y: 244, width: each, height: 44)
        shuffleButton.frame = CGRect(x: 32 + each, y: 244, width: each, height: 44)
    }

    // MARK: - Dữ liệu

    private func load() {
        spinner.startAnimating()
        switch kind {
        case .artist(let id, let name):
            if let id = id {
                loadArtist(id)
            } else {
                InnerTube.shared.findArtistId(name: name) { [weak self] found in
                    guard let self = self else { return }
                    if let found = found { self.loadArtist(found) } else { self.fail("Không tìm thấy trang nghệ sĩ \"\(name)\".") }
                }
            }
        case .album(let id, _):
            InnerTube.shared.albumPage(id: id) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let page):
                    self.pageName = page.title
                    self.title = page.title
                    self.songs = page.songs
                    self.infoLabel.text = page.artist + " · \(page.songs.count) bài"
                    self.show(thumbnail: page.thumbnail)
                case .failure(let error):
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    private func loadArtist(_ id: String) {
        InnerTube.shared.artistPage(id: id) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let page):
                if !page.name.isEmpty { self.pageName = page.name; self.title = page.name }
                self.songs = page.songs
                self.sections = page.sections
                self.infoLabel.text = page.songs.isEmpty ? "" : "\(page.songs.count) bài nổi bật"
                self.show(thumbnail: page.thumbnail)
            case .failure(let error):
                self.fail(error.localizedDescription)
            }
        }
    }

    private func show(thumbnail: URL?) {
        spinner.stopAnimating()
        nameLabel.text = pageName
        playButton.isHidden = songs.isEmpty
        shuffleButton.isHidden = songs.isEmpty
        if let url = thumbnail {
            ImageLoader.shared.load(url) { [weak self] image in self?.cover.image = image }
        }
        tableView.reloadData()
    }

    private func fail(_ message: String) {
        spinner.stopAnimating()
        messageLabel.text = message
    }

    @objc private func playAll() {
        guard !songs.isEmpty else { return }
        PlayerEngine.shared.setShuffle(false)
        PlayerEngine.shared.play(queue: songs, index: 0, context: pageName)
    }

    @objc private func shuffleAll() {
        guard !songs.isEmpty else { return }
        PlayerEngine.shared.playShuffled(songs)
    }

    // MARK: - Bảng

    private var hasSongs: Bool { return !songs.isEmpty }

    func numberOfSections(in tableView: UITableView) -> Int {
        return (hasSongs ? 1 : 0) + sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if hasSongs && section == 0 { return songs.count }
        return sections[section - (hasSongs ? 1 : 0)].cards.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if hasSongs && section == 0 {
            if case .artist = kind { return "Bài hát" }
            return nil
        }
        return sections[section - (hasSongs ? 1 : 0)].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if hasSongs && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: SongCell.reuseId, for: indexPath) as! SongCell
            let song = songs[indexPath.row]
            cell.configure(song: song, isCurrent: PlayerEngine.shared.currentSong == song)
            cell.onMore = { [weak self, weak cell] in
                guard let self = self else { return }
                SongActions.present(for: song, from: self, sourceView: cell)
            }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: CardCell.reuseId, for: indexPath) as! CardCell
        cell.configure(card: sections[indexPath.section - (hasSongs ? 1 : 0)].cards[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if hasSongs && indexPath.section == 0 {
            PlayerEngine.shared.play(queue: songs, index: indexPath.row, context: pageName)
            return
        }
        let card = sections[indexPath.section - (hasSongs ? 1 : 0)].cards[indexPath.row]
        if card.browseId.hasPrefix("MPRE") {
            navigationController?.pushViewController(MusicPageViewController(kind: .album(id: card.browseId, title: card.title)), animated: true)
        } else if card.browseId.hasPrefix("UC") {
            navigationController?.pushViewController(MusicPageViewController(kind: .artist(id: card.browseId, name: card.title)), animated: true)
        } else {
            Toast.show("Chưa mở được mục này")
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.primaryText
    }
}

/// Một thẻ (album, đĩa đơn, nghệ sĩ liên quan) dạng hàng ngang.
final class CardCell: UITableViewCell {
    static let reuseId = "CardCell"
    private let thumb = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var representedURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        accessoryType = .disclosureIndicator
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 8
        thumb.backgroundColor = Theme.placeholder
        titleLabel.font = Theme.bold(16)
        titleLabel.textColor = Theme.primaryText
        subtitleLabel.font = Theme.regular(14)
        subtitleLabel.textColor = Theme.secondaryText
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumb)
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumb.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 50),
            thumb.heightAnchor.constraint(equalToConstant: 50),
            stack.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        thumb.image = nil
    }

    func configure(card: BrowseCard) {
        titleLabel.text = card.title
        subtitleLabel.text = card.subtitle
        representedURL = card.thumbnail
        thumb.layer.cornerRadius = card.browseId.hasPrefix("UC") ? 25 : 8
        if let url = card.thumbnail {
            ImageLoader.shared.load(url) { [weak self] image in
                guard let self = self, self.representedURL == url else { return }
                self.thumb.image = image
            }
        }
    }
}
