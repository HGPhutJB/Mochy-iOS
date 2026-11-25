import UIKit

/// Một hàng người dùng: ảnh đại diện, tên, huy hiệu và nút Theo dõi.
final class UserCell: UITableViewCell {
    static let reuseId = "UserCell"
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let badgeView = UIImageView()
    private let ownerLabel = UILabel()
    let followButton = UIButton(type: .custom)
    var username = ""
    var onFollow: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        selectionStyle = .none
        avatar.layer.cornerRadius = 22
        avatar.clipsToBounds = true
        nameLabel.font = Theme.bold(17)
        nameLabel.textColor = Theme.primaryText
        badgeView.contentMode = .scaleAspectFit
        ownerLabel.text = " OWNER "
        ownerLabel.font = Theme.bold(10)
        ownerLabel.layer.cornerRadius = 8
        ownerLabel.clipsToBounds = true
        followButton.titleLabel?.font = Theme.bold(14)
        followButton.layer.cornerRadius = 16
        followButton.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        for v in [avatar, nameLabel, badgeView, ownerLabel, followButton] as [UIView] { contentView.addSubview(v) }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = contentView.bounds.height
        avatar.frame = CGRect(x: 16, y: (h - 44) / 2, width: 44, height: 44)
        followButton.frame = CGRect(x: contentView.bounds.width - 16 - 112, y: (h - 32) / 2, width: 112, height: 32)
        var x = avatar.frame.maxX + 12
        let maxName = followButton.frame.minX - x - 8
        let nameSize = nameLabel.sizeThatFits(CGSize(width: 1000, height: 30))
        let nameW = min(nameSize.width, max(40, maxName - 70))
        nameLabel.frame = CGRect(x: x, y: (h - 24) / 2, width: nameW, height: 24)
        x = nameLabel.frame.maxX + 6
        if !badgeView.isHidden {
            badgeView.frame = CGRect(x: x, y: (h - 18) / 2, width: 18, height: 18)
            x = badgeView.frame.maxX + 6
        }
        if !ownerLabel.isHidden {
            ownerLabel.frame = CGRect(x: x, y: (h - 16) / 2, width: 52, height: 16)
        }
    }

    func configure(_ user: CloudUser, showFollow: Bool = true) {
        username = user.username
        nameLabel.text = "@" + user.username
        badgeView.isHidden = !user.isVerified
        badgeView.image = user.isVerified ? AccountAvatarButton.verifiedTick(size: 18) : nil
        ownerLabel.isHidden = !user.isOwner
        ownerLabel.textColor = Theme.isDark ? .black : .white
        ownerLabel.backgroundColor = Theme.isDark ? .white : .black
        avatar.image = AccountAvatarButton.render(letter: String(user.username.prefix(1)).uppercased(), photo: nil, side: 44)
        let name = user.username
        MochyCloud.shared.avatar(of: name) { [weak self] image in
            guard let self = self, self.username == name, let image = image else { return }
            self.avatar.image = AccountAvatarButton.render(letter: nil, photo: image, side: 44)
        }
        followButton.isHidden = !showFollow
        applyFollow(user.following)
        setNeedsLayout()
    }

    func applyFollow(_ following: Bool) {
        if following {
            followButton.setTitle("Đang theo dõi", for: .normal)
            followButton.setTitleColor(Theme.accent, for: .normal)
            followButton.backgroundColor = Theme.chip
        } else {
            followButton.setTitle("Theo dõi", for: .normal)
            followButton.setTitleColor(.white, for: .normal)
            followButton.backgroundColor = Theme.accent
        }
    }

    @objc private func tapped() { onFollow?() }
}

/// Danh sách người dùng: tìm kiếm có gợi ý, đang theo dõi, hoặc người theo dõi.
final class UserListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    enum Mode { case search, following, followers }

    private let mode: Mode
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let statusLabel = UILabel()
    private var users: [CloudUser] = []
    private var debounce: DispatchWorkItem?
    private var searchToken = 0

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch mode {
        case .search: title = "Tìm người dùng"
        case .following: title = "Đang theo dõi"
        case .followers: title = "Người theo dõi"
        }
        view.backgroundColor = Theme.background
        if #available(iOS 11.0, *) { navigationItem.largeTitleDisplayMode = .never }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorStyle = .none
        tableView.rowHeight = 64
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UserCell.self, forCellReuseIdentifier: UserCell.reuseId)
        view.addSubview(tableView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = Theme.regular(15)
        statusLabel.textColor = Theme.secondaryText
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        var topInset: CGFloat = 110
        if mode == .search {
            searchBar.placeholder = "Nhập tên người dùng (ví dụ: puc)"
            searchBar.autocapitalizationType = .none
            searchBar.autocorrectionType = .no
            searchBar.searchBarStyle = .minimal
            searchBar.keyboardAppearance = Theme.isDark ? .dark : .light
            searchBar.delegate = self
            searchBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 56)
            tableView.tableHeaderView = searchBar
            statusLabel.text = "Gõ vài chữ đầu của tên để tìm người dùng."
            topInset = 100
        } else {
            statusLabel.text = "Đang tải…"
        }
        tableView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: 120, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        tableView.contentOffset = CGPoint(x: 0, y: -topInset)

        guard MochyCloud.shared.isLoggedIn else {
            statusLabel.text = "Hãy đăng nhập tài khoản Mochy để theo dõi người khác."
            searchBar.isUserInteractionEnabled = false
            return
        }
        if mode != .search { loadFollows() } else { searchBar.becomeFirstResponder() }
    }

    private func loadFollows() {
        MochyCloud.shared.loadFollows { [weak self] following, followers, error in
            guard let self = self else { return }
            self.users = self.mode == .following ? following : followers
            if let error = error { self.statusLabel.text = error }
            else { self.statusLabel.text = self.users.isEmpty ? (self.mode == .following ? "Bạn chưa theo dõi ai." : "Chưa có người theo dõi.") : nil }
            self.tableView.reloadData()
        }
    }

    // MARK: Tìm kiếm có gợi ý

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        debounce?.cancel()
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            users = []
            tableView.reloadData()
            statusLabel.text = "Gõ vài chữ đầu của tên để tìm người dùng."
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.runSearch(q) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }

    private func runSearch(_ q: String) {
        searchToken += 1
        let token = searchToken
        MochyCloud.shared.searchUsers(q) { [weak self] list, error in
            guard let self = self, token == self.searchToken else { return }
            if let list = list {
                self.users = list
                self.statusLabel.text = list.isEmpty ? "Không thấy ai tên bắt đầu bằng \"\(q)\"." : nil
            } else {
                self.statusLabel.text = error
            }
            self.tableView.reloadData()
        }
    }

    // MARK: Bảng

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return users.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: UserCell.reuseId, for: indexPath) as! UserCell
        let user = users[indexPath.row]
        cell.configure(user)
        cell.onFollow = { [weak self] in self?.toggleFollow(at: indexPath.row) }
        return cell
    }

    private func toggleFollow(at index: Int) {
        guard index < users.count else { return }
        let target = users[index].username
        let want = !users[index].following
        users[index].following = want
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        MochyCloud.shared.setFollowing(target, follow: want) { [weak self] error in
            guard let self = self, let error = error else { return }
            if let i = self.users.firstIndex(where: { $0.username == target }) {
                self.users[i].following = !want
                self.tableView.reloadRows(at: [IndexPath(row: i, section: 0)], with: .none)
            }
            Toast.show(error)
        }
    }
}
