import UIKit

/// Trang "Credit và giấy phép": gom mọi ghi công tác giả gốc (Mochy Music và các dự án nó dựa trên), giấy phép GPL-3.0, mã nguồn.
final class CreditsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct Item {
        let title: String
        let detail: String
        let url: String?
    }

    private struct Block {
        let title: String
        let footer: String?
        let items: [Item]
    }

    private let blocks: [Block] = [
        Block(title: L("Dự án gốc"),
              footer: L("Mochy iOS là bản viết lại bằng Swift/UIKit cho iOS 12 trở lên, dựa trên ý tưởng, cách gọi YouTube Music, bộ thông số client và thiết kế giao diện của Mochy Music. Ported from Mochy Music."),
              items: [Item(title: "Mochy Music", detail: "realidkroo", url: "https://github.com/realidkroo/mochy-music")]),
        Block(title: L("Nền tảng của Mochy Music"),
              footer: L("Mochy Music là bản phát triển từ ViviMusic và xây trên Metrolist. Ghi công của họ được giữ nguyên."),
              items: [Item(title: "ViviMusic", detail: "vivizzz007Z", url: nil),
                      Item(title: "Metrolist", detail: "Mostafa Alagamy", url: nil),
                      Item(title: "InnerTube (RiMusic)", detail: "fast4x", url: nil)]),
        Block(title: L("Dịch vụ dùng ở các mốc sau"),
              footer: L("Mỗi dịch vụ thuộc về tác giả của nó."),
              items: [Item(title: "LRCLIB", detail: "tranxuanthang", url: nil),
                      Item(title: "SimpMusic", detail: "maxrave-dev", url: nil),
                      Item(title: "LyricsPlus", detail: "Ibra Al Tabian", url: nil),
                      Item(title: "Better Lyrics API", detail: "Boidushya", url: nil),
                      Item(title: "AutoEq", detail: "AutoEq", url: nil)]),
        Block(title: L("Giấy phép và mã nguồn"),
              footer: L("Mochy iOS giữ giấy phép GPL-3.0. Nếu bạn phát hành bản chỉnh sửa, hãy giữ các ghi công này và công khai mã nguồn."),
              items: [Item(title: "GPL-3.0", detail: L("Toàn văn giấy phép"), url: "https://www.gnu.org/licenses/gpl-3.0.html"),
                      Item(title: L("Mã nguồn Mochy iOS"), detail: "GitHub", url: UpdateConfig.repoPage)]),
        Block(title: L("Lưu ý"),
              footer: L("Mochy iOS là dự án không chính thức, không liên kết với YouTube, Google, Apple hay dịch vụ nào nó kết nối tới. App không lưu trữ hay phân phối nhạc."),
              items: [])
    ]

    private let tableView = UITableView(frame: .zero, style: .grouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("Credit và giấy phép")
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.groupedBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.groupedBackground
        tableView.separatorColor = Theme.separator
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return blocks.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return blocks[section].items.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return blocks[section].title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return blocks[section].footer
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = Theme.secondaryText
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = blocks[indexPath.section].items[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.detail
        cell.accessoryType = item.url != nil ? .disclosureIndicator : .none
        cell.selectionStyle = item.url != nil ? .default : .none
        Theme.style(cell: cell, grouped: true)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = blocks[indexPath.section].items[indexPath.row]
        guard let string = item.url, let url = URL(string: string), url.scheme?.lowercased() == "https" else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
