import UIKit

/// Tab "Tìm kiếm": ô tìm + kết quả; khi chưa tìm thì hiện các lần tìm gần đây.
final class SearchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private enum Mode {
        case recents
        case suggestions
        case results
    }

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: Theme.spinnerStyle())
    private var songs: [Song] = []
    private var mode: Mode = .recents
    private var searchToken = 0
    private var suggestions: [String] = []
    private var suggestToken = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tìm kiếm"
        view.backgroundColor = Theme.background

        searchBar.placeholder = "Bài hát, nghệ sĩ"
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.returnKeyType = .search
        searchBar.delegate = self
        searchBar.frame = CGRect(x: 0, y: 0, width: 320, height: 56)
        Theme.style(searchBar: searchBar)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SongCell.self, forCellReuseIdentifier: SongCell.reuseId)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "recent")
        tableView.separatorColor = Theme.separator
        tableView.keyboardDismissMode = .onDrag
        tableView.tableHeaderView = searchBar
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = Theme.regular(15)
        messageLabel.textColor = Theme.secondaryText
        view.addSubview(messageLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 40),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: messageLabel.topAnchor, constant: -12)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(refreshRows), name: .playerStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshRows), name: .libraryChanged, object: nil)
        showRecents()
    }

    @objc private func refreshRows() {
        if mode == .results { tableView.reloadData() }
    }

    private func showRecents() {
        mode = .recents
        songs = []
        messageLabel.text = AppSettings.recentSearches.isEmpty ? "Nhập tên bài hát hoặc nghệ sĩ rồi bấm Tìm." : nil
        tableView.reloadData()
    }

    // MARK: - Tìm kiếm

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        let query = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        runSearch(query)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestToken += 1
        if text.isEmpty {
            searchToken += 1
            spinner.stopAnimating()
            showRecents()
            return
        }
        let token = suggestToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self = self, token == self.suggestToken else { return }
            InnerTube.shared.suggestions(text) { [weak self] list in
                guard let self = self, token == self.suggestToken, !list.isEmpty else { return }
                // Chỉ hiện gợi ý khi chưa chuyển sang kết quả cho đúng nội dung đang gõ.
                self.searchToken += 1
                self.spinner.stopAnimating()
                self.mode = .suggestions
                self.songs = []
                self.suggestions = list
                self.messageLabel.text = nil
                self.tableView.reloadData()
            }
        }
    }

    private func runSearch(_ query: String) {
        guard !query.isEmpty else { return }
        var recents = AppSettings.recentSearches.filter { $0.lowercased() != query.lowercased() }
        recents.insert(query, at: 0)
        AppSettings.recentSearches = recents

        suggestToken += 1
        searchToken += 1
        let token = searchToken
        mode = .results
        songs = []
        tableView.reloadData()
        messageLabel.text = nil
        spinner.startAnimating()
        InnerTube.shared.search(query) { [weak self] result in
            guard let self = self, token == self.searchToken else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let found):
                self.songs = found
                self.messageLabel.text = found.isEmpty ? "Không tìm thấy kết quả cho \"\(query)\"." : nil
                self.tableView.reloadData()
                self.tableView.animateRowsIn()
            case .failure(let error):
                self.songs = []
                self.tableView.reloadData()
                self.messageLabel.text = "Lỗi tìm kiếm:\n\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Bảng

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .results: return songs.count
        case .suggestions: return suggestions.count
        case .recents: return AppSettings.recentSearches.count
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return mode == .results ? 66 : 48
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if mode == .suggestions {
            let cell = tableView.dequeueReusableCell(withIdentifier: "recent", for: indexPath)
            Theme.style(cell: cell, grouped: false)
            let text = suggestions[indexPath.row]
            let typed = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let attributed = NSMutableAttributedString(string: text, attributes: [.font: Theme.bold(16), .foregroundColor: Theme.primaryText])
            if !typed.isEmpty, text.lowercased().hasPrefix(typed.lowercased()) {
                attributed.addAttributes([.font: Theme.regular(16), .foregroundColor: Theme.secondaryText],
                                         range: NSRange(location: 0, length: (typed as NSString).length))
            }
            cell.textLabel?.attributedText = attributed
            cell.imageView?.image = Icons.search(18)
            cell.imageView?.tintColor = Theme.secondaryText
            return cell
        }
        if mode == .recents {
            let cell = tableView.dequeueReusableCell(withIdentifier: "recent", for: indexPath)
            Theme.style(cell: cell, grouped: false)
            cell.textLabel?.text = AppSettings.recentSearches[indexPath.row]
            cell.textLabel?.font = Theme.regular(16)
            cell.imageView?.image = Icons.clock(18)
            cell.imageView?.tintColor = Theme.secondaryText
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: SongCell.reuseId, for: indexPath) as! SongCell
        let song = songs[indexPath.row]
        cell.configure(song: song, isCurrent: PlayerEngine.shared.currentSong == song)
        cell.onMore = { [weak self, weak cell] in
            guard let self = self else { return }
            SongActions.present(for: song, from: self, sourceView: cell)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return nil
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard mode == .recents, !AppSettings.recentSearches.isEmpty else { return nil }
        let container = UIView()
        container.backgroundColor = Theme.background
        let label = UILabel()
        label.text = "Tìm gần đây"
        label.font = Theme.heavy(20)
        label.textColor = Theme.primaryText
        label.frame = CGRect(x: 16, y: 10, width: 200, height: 28)
        container.addSubview(label)
        let clear = UIButton(type: .system)
        clear.setTitle("Xoá", for: .normal)
        clear.titleLabel?.font = Theme.bold(15)
        clear.tintColor = Theme.accent
        clear.frame = CGRect(x: tableView.bounds.width - 76, y: 8, width: 60, height: 32)
        clear.autoresizingMask = [.flexibleLeftMargin]
        clear.addTarget(self, action: #selector(clearRecents), for: .touchUpInside)
        container.addSubview(clear)
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return (mode == .recents && !AppSettings.recentSearches.isEmpty) ? 46 : 0.01
    }

    @objc private func clearRecents() {
        AppSettings.recentSearches = []
        showRecents()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if mode == .suggestions {
            let query = suggestions[indexPath.row]
            searchBar.text = query
            searchBar.resignFirstResponder()
            runSearch(query)
            return
        }
        if mode == .recents {
            let query = AppSettings.recentSearches[indexPath.row]
            searchBar.text = query
            runSearch(query)
            return
        }
        PlayerEngine.shared.play(queue: songs, index: indexPath.row)
    }
}
