import UIKit

/// Hàng đợi phát: chạm để nhảy tới bài, kéo để sắp xếp lại, vuốt để xoá.
final class QueueViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var editButton: UIBarButtonItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Hàng đợi"
        view.backgroundColor = Theme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Sắp xếp", style: .plain, target: self, action: #selector(toggleEditing))
        editButton = navigationItem.leftBarButtonItem
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Xong", style: .done, target: self, action: #selector(close))

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
        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged), name: .playerStateChanged, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let index = PlayerEngine.shared.index
        if index >= 0 && index < PlayerEngine.shared.queue.count {
            tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
        }
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func toggleEditing() {
        let editing = !tableView.isEditing
        tableView.setEditing(editing, animated: true)
        editButton?.title = editing ? "Xong sắp xếp" : "Sắp xếp"
    }

    @objc private func stateChanged() {
        if !tableView.isEditing { tableView.reloadData() }
    }

    // MARK: - Bảng

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return PlayerEngine.shared.queue.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SongCell.reuseId, for: indexPath) as! SongCell
        let engine = PlayerEngine.shared
        let song = engine.queue[indexPath.row]
        cell.configure(song: song, isCurrent: indexPath.row == engine.index, showMore: false)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        PlayerEngine.shared.jump(to: indexPath.row)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            PlayerEngine.shared.removeFromQueue(at: indexPath.row)
            if PlayerEngine.shared.queue.isEmpty {
                dismiss(animated: true, completion: nil)
            } else {
                tableView.reloadData()
            }
        }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        PlayerEngine.shared.moveInQueue(from: sourceIndexPath.row, to: destinationIndexPath.row)
    }
}
