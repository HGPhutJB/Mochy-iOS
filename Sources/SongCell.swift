import UIKit

/// Một dòng bài hát: ảnh bìa vuông bo góc + tên + nghệ sĩ + nút "…" (giống danh sách Apple Music).
final class SongCell: UITableViewCell {
    static let reuseId = "SongCell"

    private let thumb = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let downloadedIcon = UIImageView()
    private let moreButton = ControlButton(type: .custom)
    private var representedURL: URL?
    var onMore: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = Theme.background
        selectedBackgroundView = Theme.selectionView()

        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 8
        thumb.backgroundColor = Theme.placeholder
        contentView.addSubview(thumb)

        titleLabel.font = Theme.bold(16)
        titleLabel.textColor = Theme.primaryText
        subtitleLabel.font = Theme.regular(14)
        subtitleLabel.textColor = Theme.secondaryText

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        downloadedIcon.translatesAutoresizingMaskIntoConstraints = false
        downloadedIcon.image = Icons.check(14)
        downloadedIcon.tintColor = Theme.accent
        downloadedIcon.contentMode = .scaleAspectFit
        downloadedIcon.isHidden = true
        contentView.addSubview(downloadedIcon)

        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.setImage(Icons.more(22), for: .normal)
        moreButton.tintColor = Theme.secondaryText
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        contentView.addSubview(moreButton)

        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumb.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 50),
            thumb.heightAnchor.constraint(equalToConstant: 50),
            stack.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: downloadedIcon.leadingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            downloadedIcon.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -2),
            downloadedIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            downloadedIcon.widthAnchor.constraint(equalToConstant: 16),
            downloadedIcon.heightAnchor.constraint(equalToConstant: 16),
            moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            moreButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 40),
            moreButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var entered = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !entered else { return }
        entered = true
        materialEntrance(force: true)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        thumb.image = nil
        onMore = nil
    }

    @objc private func moreTapped() {
        Haptics.tap()
        onMore?()
    }

    func configure(song: Song, isCurrent: Bool, showMore: Bool = true) {
        titleLabel.text = song.title
        titleLabel.textColor = isCurrent ? Theme.accent : Theme.primaryText
        subtitleLabel.text = song.subtitle.isEmpty ? song.artist : song.subtitle
        downloadedIcon.isHidden = !Library.shared.isDownloaded(song)
        moreButton.isHidden = !showMore
        representedURL = song.thumbnailURL
        thumb.image = nil
        if let url = song.thumbnailURL {
            ImageLoader.shared.load(url) { [weak self] image in
                guard let self = self, self.representedURL == url else { return }
                self.thumb.alpha = 0
                self.thumb.image = image
                UIView.animate(withDuration: 0.25) { self.thumb.alpha = 1 }
            }
        }
    }
}
