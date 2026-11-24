import UIKit

/// Thẻ vuông (album, đĩa đơn, video, nghệ sĩ) trong hàng ngang hoặc lưới.
final class BrowseCardItem: UICollectionViewCell {
    static let reuseId = "BrowseCardItem"
    private let art = UIImageView()
    private let titleLabel = UILabel()
    private let subLabel = UILabel()
    private var representedURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        art.contentMode = .scaleAspectFill
        art.clipsToBounds = true
        art.backgroundColor = Theme.placeholder
        contentView.addSubview(art)
        titleLabel.font = Theme.bold(14)
        titleLabel.textColor = Theme.primaryText
        subLabel.font = Theme.regular(12.5)
        subLabel.textColor = Theme.secondaryText
        contentView.addSubview(titleLabel)
        contentView.addSubview(subLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        art.frame = CGRect(x: 0, y: 0, width: w, height: w)
        titleLabel.frame = CGRect(x: 0, y: w + 8, width: w, height: 18)
        subLabel.frame = CGRect(x: 0, y: w + 27, width: w, height: 16)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        art.image = nil
    }

    func configure(card: BrowseCard) {
        titleLabel.text = card.title
        subLabel.text = card.subtitle
        representedURL = card.thumbnail
        art.layer.cornerRadius = card.browseId.hasPrefix("UC") ? bounds.width / 2 : 12
        art.image = nil
        if let url = card.thumbnail {
            ImageLoader.shared.load(url) { [weak self] image in
                guard let self = self, self.representedURL == url else { return }
                self.art.alpha = 0
                self.art.image = image
                UIView.animate(withDuration: 0.25) { self.art.alpha = 1 }
            }
        }
    }

    override var isHighlighted: Bool {
        didSet {
            let pressed = isHighlighted
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 4,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.transform = pressed ? CGAffineTransform(scaleX: 0.95, y: 0.95) : CGAffineTransform.identity
            }, completion: nil)
        }
    }
}

/// Mở một thẻ YouTube Music: nghệ sĩ, album/playlist, hoặc phát thẳng video.
enum CardRouter {
    static func open(_ card: BrowseCard, from vc: UIViewController) {
        if card.browseId.hasPrefix("video:") {
            let id = String(card.browseId.dropFirst(6))
            let song = Song(videoId: id, title: card.title, artist: card.subtitle, subtitle: "", duration: nil, thumbnailURL: card.thumbnail)
            PlayerEngine.shared.play(queue: [song], index: 0)
        } else if card.browseId.hasPrefix("UC") {
            vc.navigationController?.pushViewController(ArtistViewController(id: card.browseId, name: card.title), animated: true)
        } else {
            vc.navigationController?.pushViewController(MusicPageViewController(kind: .album(id: card.browseId, title: card.title)), animated: true)
        }
    }
}

/// Một dòng của bảng chứa hàng ngang các thẻ.
final class CardShelfCell: UITableViewCell, UICollectionViewDataSource, UICollectionViewDelegate {
    static let reuseId = "CardShelfCell"
    static let itemWidth: CGFloat = 144
    static let height: CGFloat = 144 + 52

    private let collectionView: UICollectionView
    private var cards: [BrowseCard] = []
    var onSelect: ((BrowseCard) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: CardShelfCell.itemWidth, height: CardShelfCell.height)
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
        collectionView.register(BrowseCardItem.self, forCellWithReuseIdentifier: BrowseCardItem.reuseId)
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

    func configure(cards: [BrowseCard]) {
        self.cards = cards
        collectionView.setContentOffset(.zero, animated: false)
        collectionView.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return cards.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BrowseCardItem.reuseId, for: indexPath) as! BrowseCardItem
        cell.configure(card: cards[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Haptics.tap()
        onSelect?(cards[indexPath.item])
    }
}

/// Trang nghệ sĩ: ảnh lớn tràn đầu trang, tên + người nghe, nút Phát/Ngẫu nhiên, bài nổi bật,
/// rồi các hàng ngang Album, Đĩa đơn & EP, Video, Nghệ sĩ tương tự — mỗi hàng có "Xem tất cả".
final class ArtistViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let artistId: String?
    private let artistName: String
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let header = UIView()
    private let hero = UIImageView()
    private let heroShade = GradientView()
    private let topShade = GradientView()
    private let nameLabel = UILabel()
    private let infoLabel = UILabel()
    private let playButton = PressableButton(type: .custom)
    private let shuffleButton = PressableButton(type: .custom)
    private let spinner = UIActivityIndicatorView(style: Theme.spinnerStyle())
    private let messageLabel = UILabel()
    private var page = ArtistPage(name: "", thumbnail: nil, songs: [], sections: [])
    private var songs: [Song] = []
    private var expanded = false
    private var loadingAll = false
    private var heroURL: URL?
    private let collapsedCount = 5

    init(id: String?, name: String) {
        artistId = id
        artistName = name
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Đóng", style: .plain, target: self, action: #selector(close))
        }
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.separator
        tableView.dataSource = self
        tableView.delegate = self
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(SongCell.self, forCellReuseIdentifier: SongCell.reuseId)
        tableView.register(CardShelfCell.self, forCellReuseIdentifier: CardShelfCell.reuseId)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "More")
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
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
        hero.contentMode = .scaleAspectFill
        hero.clipsToBounds = true
        hero.backgroundColor = Theme.placeholder
        header.addSubview(hero)
        heroShade.gradientLayer.colors = [UIColor(white: 0, alpha: 0).cgColor, Theme.background.withAlphaComponent(0.55).cgColor, Theme.background.cgColor]
        heroShade.gradientLayer.locations = [0.35, 0.78, 1]
        header.addSubview(heroShade)
        topShade.gradientLayer.colors = [UIColor(white: 0, alpha: 0.45).cgColor, UIColor(white: 0, alpha: 0).cgColor]
        header.addSubview(topShade)
        nameLabel.font = Theme.heavy(36)
        nameLabel.textColor = Theme.primaryText
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.6
        nameLabel.text = artistName
        header.addSubview(nameLabel)
        infoLabel.font = Theme.bold(14)
        infoLabel.textColor = Theme.secondaryText
        header.addSubview(infoLabel)
        playButton.setTitle("  Phát", for: .normal)
        playButton.setImage(Icons.play(16), for: .normal)
        playButton.tintColor = UIColor.white
        playButton.setTitleColor(UIColor.white, for: .normal)
        playButton.backgroundColor = Theme.accent
        shuffleButton.setTitle("  Ngẫu nhiên", for: .normal)
        shuffleButton.setImage(Icons.shuffle(16), for: .normal)
        shuffleButton.tintColor = Theme.accent
        shuffleButton.setTitleColor(Theme.accent, for: .normal)
        shuffleButton.backgroundColor = Theme.chip
        for b in [playButton, shuffleButton] {
            b.titleLabel?.font = Theme.bold(15)
            b.layer.cornerRadius = 22
            b.isHidden = true
            header.addSubview(b)
        }
        playButton.addTarget(self, action: #selector(playAll), for: .touchUpInside)
        shuffleButton.addTarget(self, action: #selector(shuffleAll), for: .touchUpInside)
        tableView.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        guard w > 0 else { return }
        let heroH = round(w * 0.86)
        let height = heroH + 14 + 44 + 18
        if header.frame.width != w || header.frame.height != height {
            header.frame = CGRect(x: 0, y: 0, width: w, height: height)
            tableView.tableHeaderView = header
        }
        hero.frame = CGRect(x: 0, y: 0, width: w, height: heroH)
        heroShade.frame = hero.frame
        topShade.frame = CGRect(x: 0, y: 0, width: w, height: 120)
        infoLabel.frame = CGRect(x: 20, y: heroH - 28, width: w - 40, height: 20)
        nameLabel.frame = CGRect(x: 20, y: heroH - 28 - 46, width: w - 40, height: 44)
        let each = (w - 32 - 12) / 2
        playButton.frame = CGRect(x: 16, y: heroH + 14, width: each, height: 44)
        shuffleButton.frame = CGRect(x: 28 + each, y: heroH + 14, width: each, height: 44)
        tableView.contentInset.bottom = view.safeAreaInsets.bottom
        tableView.scrollIndicatorInsets.bottom = view.safeAreaInsets.bottom
    }

    // MARK: - Dữ liệu

    private func load() {
        spinner.startAnimating()
        if let id = artistId {
            fetch(id)
        } else {
            InnerTube.shared.findArtistId(name: artistName) { [weak self] found in
                guard let self = self else { return }
                if let found = found { self.fetch(found) } else { self.fail("Không tìm thấy trang nghệ sĩ \"\(self.artistName)\".") }
            }
        }
    }

    private func fetch(_ id: String) {
        InnerTube.shared.artistPage(id: id) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let p):
                self.page = p
                self.songs = p.songs
                self.spinner.stopAnimating()
                self.nameLabel.text = p.name.isEmpty ? self.artistName : p.name
                self.infoLabel.text = p.subtitle
                self.playButton.isHidden = p.songs.isEmpty
                self.shuffleButton.isHidden = p.songs.isEmpty
                self.heroURL = p.thumbnail
                if let url = p.thumbnail {
                    ImageLoader.shared.load(url) { [weak self] image in
                        guard let self = self, self.heroURL == url else { return }
                        UIView.transition(with: self.hero, duration: 0.35, options: .transitionCrossDissolve, animations: {
                            self.hero.image = image
                        }, completion: nil)
                    }
                }
                self.tableView.reloadData()
                self.tableView.animateRowsIn()
            case .failure(let error):
                self.fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        spinner.stopAnimating()
        messageLabel.text = message
    }

    @objc private func playAll() {
        guard !songs.isEmpty else { return }
        PlayerEngine.shared.setShuffle(false)
        PlayerEngine.shared.play(queue: songs, index: 0, context: page.name)
    }

    @objc private func shuffleAll() {
        guard !songs.isEmpty else { return }
        PlayerEngine.shared.playShuffled(songs)
    }

    /// Tải đủ bài của nghệ sĩ khi bấm "Xem tất cả bài hát".
    private func expandSongs() {
        guard !loadingAll else { return }
        guard let list = page.moreSongsId else { expanded = true; tableView.reloadData(); return }
        loadingAll = true
        tableView.reloadData()
        InnerTube.shared.playlistSongs(listId: list) { [weak self] result in
            guard let self = self else { return }
            self.loadingAll = false
            self.expanded = true
            if case .success(let r) = result, r.songs.count > self.songs.count {
                let name = self.page.name
                self.songs = r.songs.map { s in
                    s.artist.isEmpty ? Song(videoId: s.videoId, title: s.title, artist: name, subtitle: s.subtitle, duration: s.duration, thumbnailURL: s.thumbnailURL) : s
                }
            }
            self.tableView.reloadData()
        }
    }

    // MARK: - Bảng

    private var hasSongs: Bool { return !songs.isEmpty }
    private var shownSongs: Int { return expanded ? songs.count : min(songs.count, collapsedCount) }
    private var hasMoreRow: Bool { return hasSongs && !expanded && (songs.count > collapsedCount || page.moreSongsId != nil) }

    func numberOfSections(in tableView: UITableView) -> Int {
        return (hasSongs ? 1 : 0) + page.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if hasSongs && section == 0 { return shownSongs + (hasMoreRow ? 1 : 0) }
        return 1
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if hasSongs && indexPath.section == 0 { return indexPath.row < shownSongs ? 66 : 48 }
        return CardShelfCell.height + 10
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 50
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        container.backgroundColor = Theme.background
        let label = UILabel()
        label.font = Theme.heavy(22)
        label.textColor = Theme.primaryText
        var more = false
        if hasSongs && section == 0 {
            label.text = "Bài hát nổi bật"
        } else {
            let s = page.sections[section - (hasSongs ? 1 : 0)]
            label.text = s.title
            more = s.moreBrowseId != nil
        }
        label.frame = CGRect(x: 16, y: 14, width: tableView.bounds.width - 140, height: 28)
        container.addSubview(label)
        if more {
            let b = UIButton(type: .system)
            b.setTitle("Xem tất cả", for: .normal)
            b.titleLabel?.font = Theme.bold(14)
            b.setTitleColor(Theme.accent, for: .normal)
            b.contentHorizontalAlignment = .right
            b.frame = CGRect(x: tableView.bounds.width - 126, y: 12, width: 110, height: 32)
            b.autoresizingMask = [.flexibleLeftMargin]
            b.tag = section
            b.addTarget(self, action: #selector(seeAll(_:)), for: .touchUpInside)
            container.addSubview(b)
        }
        return container
    }

    @objc private func seeAll(_ sender: UIButton) {
        let index = sender.tag - (hasSongs ? 1 : 0)
        guard index >= 0, index < page.sections.count, let id = page.sections[index].moreBrowseId else { return }
        let s = page.sections[index]
        navigationController?.pushViewController(DiscographyViewController(title: s.title, browseId: id, params: s.moreParams, fallback: s.cards), animated: true)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if hasSongs && indexPath.section == 0 {
            if indexPath.row < shownSongs {
                let cell = tableView.dequeueReusableCell(withIdentifier: SongCell.reuseId, for: indexPath) as! SongCell
                let song = songs[indexPath.row]
                cell.configure(song: song, isCurrent: PlayerEngine.shared.currentSong == song)
                cell.onMore = { [weak self, weak cell] in
                    guard let self = self else { return }
                    SongActions.present(for: song, from: self, sourceView: cell)
                }
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "More", for: indexPath)
            cell.backgroundColor = Theme.background
            cell.textLabel?.text = loadingAll ? "Đang tải…" : "Xem tất cả bài hát"
            cell.textLabel?.font = Theme.bold(15)
            cell.textLabel?.textColor = Theme.accent
            cell.textLabel?.textAlignment = .center
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: CardShelfCell.reuseId, for: indexPath) as! CardShelfCell
        cell.configure(cards: page.sections[indexPath.section - (hasSongs ? 1 : 0)].cards)
        cell.onSelect = { [weak self] card in
            guard let self = self else { return }
            CardRouter.open(card, from: self)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard hasSongs && indexPath.section == 0 else { return }
        if indexPath.row < shownSongs {
            PlayerEngine.shared.play(queue: songs, index: indexPath.row, context: page.name)
        } else {
            expandSongs()
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return hasSongs && indexPath.section == 0
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let show = scrollView.contentOffset.y > view.bounds.width * 0.6
        let name = page.name.isEmpty ? artistName : page.name
        if show != (title != nil && !(title ?? "").isEmpty) { title = show ? name : "" }
    }
}

/// "Xem tất cả": toàn bộ album / đĩa đơn / video của một nghệ sĩ dạng lưới 2 cột.
final class DiscographyViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    private let browseId: String
    private let params: String?
    private var cards: [BrowseCard]
    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: Theme.spinnerStyle())

    init(title: String, browseId: String, params: String?, fallback: [BrowseCard]) {
        self.browseId = browseId
        self.params = params
        cards = fallback
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 18
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Theme.background
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(BrowseCardItem.self, forCellWithReuseIdentifier: BrowseCardItem.reuseId)
        view.addSubview(collectionView)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()
        InnerTube.shared.discography(browseId: browseId, params: params) { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            if case .success(let r) = result, r.cards.count >= self.cards.count {
                self.cards = r.cards
                self.collectionView.reloadData()
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return cards.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BrowseCardItem.reuseId, for: indexPath) as! BrowseCardItem
        cell.configure(card: cards[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let w = floor((collectionView.bounds.width - 32 - 14) / 2)
        return CGSize(width: w, height: w + 50)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Haptics.tap()
        CardRouter.open(cards[indexPath.item], from: self)
    }
}
