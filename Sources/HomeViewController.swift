import UIKit

/// Thẻ vuông trong một hàng ngang: ảnh bìa + tên + nghệ sĩ.
final class SongCardCell: UICollectionViewCell {
    static let reuseId = "SongCardCell"
    static let size = CGSize(width: 142, height: 200)

    private let art = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private var representedURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        art.translatesAutoresizingMaskIntoConstraints = false
        art.contentMode = .scaleAspectFill
        art.clipsToBounds = true
        art.layer.cornerRadius = 14
        art.backgroundColor = Theme.placeholder
        contentView.addSubview(art)
        titleLabel.font = Theme.bold(14)
        titleLabel.textColor = Theme.primaryText
        artistLabel.font = Theme.regular(13)
        artistLabel.textColor = Theme.secondaryText
        let stack = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
        stack.axis = .vertical
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            art.topAnchor.constraint(equalTo: contentView.topAnchor),
            art.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            art.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            art.heightAnchor.constraint(equalTo: art.widthAnchor),
            stack.topAnchor.constraint(equalTo: art.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        art.image = nil
    }

    func configure(song: Song) {
        titleLabel.text = song.title
        artistLabel.text = song.artist
        representedURL = song.thumbnailURL
        art.image = nil
        if let url = song.thumbnailURL {
            ImageLoader.shared.load(url) { [weak self] image in
                guard let self = self, self.representedURL == url else { return }
                self.art.alpha = 0
                self.art.image = image
                UIView.animate(withDuration: 0.3) { self.art.alpha = 1 }
            }
        }
    }

    override var isHighlighted: Bool {
        didSet {
            let pressed = isHighlighted
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 4,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.transform = pressed ? CGAffineTransform(scaleX: 0.94, y: 0.94) : CGAffineTransform.identity
            }, completion: nil)
        }
    }
}

/// Một dòng của bảng chứa hàng ngang bài hát.
final class ShelfCell: UITableViewCell, UICollectionViewDataSource, UICollectionViewDelegate {
    static let reuseId = "ShelfCell"

    private let collectionView: UICollectionView
    private var songs: [Song] = []
    var onSelect: ((Int) -> Void)?
    var onMore: ((Song, UIView) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = SongCardCell.size
        layout.minimumLineSpacing = 14
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        selectionStyle = .none
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = Theme.background
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(SongCardCell.self, forCellWithReuseIdentifier: SongCardCell.reuseId)
        contentView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(songs: [Song]) {
        self.songs = songs
        collectionView.setContentOffset(.zero, animated: false)
        collectionView.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return songs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SongCardCell.reuseId, for: indexPath) as! SongCardCell
        cell.configure(song: songs[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Haptics.tap()
        onSelect?(indexPath.item)
    }
}

/// Thẻ nổi bật đầu trang chủ: ảnh lớn, nhãn gợi ý, tên bài và nút Phát.
final class HeroView: UIView {
    private let art = UIImageView()
    private let shade = GradientView()
    private let kickerLabel = UILabel()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let playButton = PressableButton(type: .custom)
    private var representedURL: URL?
    var onPlay: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 26
        clipsToBounds = true
        backgroundColor = Theme.placeholder

        art.contentMode = .scaleAspectFill
        art.clipsToBounds = true
        addSubview(art)
        shade.gradientLayer.colors = [UIColor(white: 0, alpha: 0.0).cgColor, UIColor(white: 0, alpha: 0.78).cgColor]
        shade.gradientLayer.locations = [0.35, 1.0]
        addSubview(shade)

        kickerLabel.font = UIFont.systemFont(ofSize: 12, weight: .heavy)
        kickerLabel.textColor = UIColor(white: 1, alpha: 0.78)
        titleLabel.font = Theme.heavy(28)
        titleLabel.textColor = UIColor.white
        titleLabel.numberOfLines = 2
        artistLabel.font = Theme.bold(16)
        artistLabel.textColor = UIColor(white: 1, alpha: 0.8)
        for label in [kickerLabel, titleLabel, artistLabel] { addSubview(label) }

        playButton.setTitle(L("  Phát"), for: .normal)
        playButton.setImage(Icons.play(16), for: .normal)
        playButton.tintColor = UIColor.black
        playButton.setTitleColor(UIColor.black, for: .normal)
        playButton.titleLabel?.font = Theme.bold(16)
        playButton.backgroundColor = UIColor.white
        playButton.layer.cornerRadius = 20
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        addSubview(playButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func playTapped() {
        Haptics.tap()
        onPlay?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        art.frame = bounds
        shade.frame = bounds
        let pad: CGFloat = 20
        let width = bounds.width - pad * 2
        playButton.frame = CGRect(x: pad, y: bounds.height - pad - 40, width: 112, height: 40)
        let artistSize = artistLabel.sizeThatFits(CGSize(width: width, height: 30))
        artistLabel.frame = CGRect(x: pad, y: playButton.frame.minY - 12 - artistSize.height, width: width, height: artistSize.height)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: width, height: 80))
        titleLabel.frame = CGRect(x: pad, y: artistLabel.frame.minY - 2 - titleSize.height, width: width, height: titleSize.height)
        kickerLabel.frame = CGRect(x: pad, y: titleLabel.frame.minY - 6 - 16, width: width, height: 16)
    }

    func configure(song: Song, kicker: String) {
        kickerLabel.text = kicker
        titleLabel.text = song.title
        artistLabel.text = song.artist
        setNeedsLayout()
        let url = song.largeThumbnailURL
        if representedURL == url && art.image != nil { return }
        representedURL = url
        art.image = nil
        if let url = url {
            ImageLoader.shared.load(url) { [weak self] image in
                guard let self = self, self.representedURL == url else { return }
                UIView.transition(with: self.art, duration: 0.4, options: .transitionCrossDissolve, animations: {
                    self.art.image = image
                }, completion: nil)
            }
        }
    }
}

/// Tab "Trang chủ": thẻ gợi ý hôm nay, nghe gần đây, nhạc mới, bảng xếp hạng, "Vì bạn nghe …".
final class HomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let headerContainer = UIView()
    private let hero = HeroView()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: Theme.spinnerStyle())
    private var shelves: [Shelf] = []
    private var heroSong: Song?
    private var didAnimate = false

    @objc private func openAccount() {
        let vc = MochyAccountViewController()
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(title: L("Xong"), style: .done, target: self, action: #selector(closeAccount))
        let nav = GlassNavigationController(rootViewController: vc)
        Theme.style(navigationBar: nav.navigationBar)
        nav.view.backgroundColor = Theme.background
        present(nav, animated: true)
    }

    @objc private func closeAccount() {
        dismiss(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("Trang chủ")
        let avatar = AccountAvatarButton()
        avatar.addTarget(self, action: #selector(openAccount), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: avatar)
        view.backgroundColor = Theme.background

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ShelfCell.self, forCellReuseIdentifier: ShelfCell.reuseId)
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.tableFooterView = UIView()
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulledToRefresh(_:)), for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)

        hero.onPlay = { [weak self] in self?.playHero() }
        headerContainer.addSubview(hero)
        headerContainer.frame = CGRect(x: 0, y: 0, width: 320, height: 1)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = Theme.regular(15)
        statusLabel.textColor = Theme.secondaryText
        view.addSubview(statusLabel)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryChanged, object: nil)
        reload(animated: false)
        load(force: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHeader()
    }

    private func layoutHeader() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let showHero = heroSong != nil
        let height: CGFloat = showHero ? width * 0.95 + 8 : 1
        if headerContainer.frame.size.width != width || headerContainer.frame.size.height != height {
            headerContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = headerContainer
        }
        hero.isHidden = !showHero
        hero.frame = CGRect(x: 16, y: 4, width: width - 32, height: height - 8)
    }

    private func load(force: Bool) {
        if HomeFeed.shared.shelves.isEmpty {
            spinner.startAnimating()
            statusLabel.text = L("Đang tìm nhạc mới cho bạn…")
        }
        HomeFeed.shared.load(force: force) { [weak self] in
            guard let self = self else { return }
            self.tableView.refreshControl?.endRefreshing()
            self.spinner.stopAnimating()
            self.reload(animated: true)
        }
    }

    @objc private func pulledToRefresh(_ sender: UIRefreshControl) {
        load(force: true)
    }

    @objc private func libraryChanged() {
        // Cập nhật hàng "Nghe gần đây" khi lịch sử đổi, nhưng không dựng lại cả trang khi đang cuộn.
        if !tableView.isDragging && !tableView.isDecelerating {
            reload(animated: false)
        }
    }

    private func reload(animated: Bool) {
        // Bỏ các hàng cá nhân hoá kiểu "Nghe gần đây", "Vì bạn nghe …", "Bạn đã nghe …".
        let hidden = ["vì bạn nghe", "bạn đã nghe", "nghe gần đây", "nghe lại", "because you", "listen again", "recently"]
        let list = HomeFeed.shared.shelves.filter { shelf in
            let t = shelf.title.lowercased()
            return !hidden.contains { t.contains($0) }
        }
        shelves = list
        if let hero = HomeFeed.shared.heroSong() {
            heroSong = hero.song
            self.hero.configure(song: hero.song, kicker: hero.kicker)
        } else {
            heroSong = nil
        }
        if shelves.isEmpty {
            statusLabel.text = HomeFeed.shared.lastError ?? (HomeFeed.shared.isLoading ? L("Đang tìm nhạc mới cho bạn…") : L("Chưa có gợi ý. Kéo xuống để tải."))
        } else {
            statusLabel.text = nil
        }
        layoutHeader()
        tableView.reloadData()
        if animated && !didAnimate && !shelves.isEmpty {
            didAnimate = true
            tableView.animateRowsIn()
        }
    }

    private func playHero() {
        guard let song = heroSong else { return }
        let pool = HomeFeed.shared.shelves.first(where: { $0.songs.contains(song) })?.songs ?? [song]
        let index = pool.firstIndex(of: song) ?? 0
        PlayerEngine.shared.play(queue: pool, index: index)
    }

    // MARK: - Bảng

    func numberOfSections(in tableView: UITableView) -> Int {
        return shelves.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return SongCardCell.size.height + 8
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 48
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { return 0.01 }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { return UIView() }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        container.backgroundColor = Theme.background
        let label = UILabel()
        label.font = Theme.heavy(22)
        label.textColor = Theme.primaryText
        label.text = shelves[section].title
        label.frame = CGRect(x: 16, y: 12, width: tableView.bounds.width - 32, height: 28)
        label.autoresizingMask = [.flexibleWidth]
        container.addSubview(label)
        return container
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ShelfCell.reuseId, for: indexPath) as! ShelfCell
        let songs = shelves[indexPath.section].songs
        cell.configure(songs: songs)
        cell.onSelect = { index in
            PlayerEngine.shared.play(queue: songs, index: index)
        }
        return cell
    }
}
