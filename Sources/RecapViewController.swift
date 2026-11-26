import UIKit

/// Recap: tổng kết thời gian nghe, bài và nghệ sĩ nghe nhiều nhất theo tuần / tháng / năm / tất cả.
final class RecapViewController: UIViewController {
    private enum Period: Int, CaseIterable {
        case week, month, year, all
        var title: String {
            switch self {
            case .week: return L("Tuần")
            case .month: return L("Tháng")
            case .year: return L("Năm")
            case .all: return L("Tất cả")
            }
        }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return nil
            }
        }
    }

    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let segmented = UISegmentedControl(items: Period.allCases.map { $0.title })

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recap"
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share))

        segmented.selectedSegmentIndex = Period.month.rawValue
        segmented.tintColor = Theme.accent
        segmented.addTarget(self, action: #selector(periodChanged), for: .valueChanged)
        segmented.translatesAutoresizingMaskIntoConstraints = false

        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmented)
        view.addSubview(scroll)
        scroll.addSubview(content)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: guide.topAnchor, constant: 10),
            segmented.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmented.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -110),
            content.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32)
        ])
        rebuild()
    }

    @objc private func periodChanged() { rebuild() }

    // MARK: - Tính toán

    private func records(in period: Period) -> [PlayRecord] {
        let all = PlayLog.shared.records
        guard let days = period.days else { return all }
        let from = Date().addingTimeInterval(-Double(days) * 86400)
        return all.filter { $0.date >= from }
    }

    private func minutes(_ seconds: Double) -> Int { return Int((seconds / 60).rounded()) }

    private func rebuild() {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let period = Period(rawValue: segmented.selectedSegmentIndex) ?? .month
        let list = records(in: period)
        if list.isEmpty {
            content.addArrangedSubview(label(L("Chưa có dữ liệu nghe trong khoảng này.\nNghe nhạc một lúc rồi quay lại nhé."), font: Theme.regular(16), color: Theme.secondaryText, centered: true))
            return
        }
        // Lượt nghe cũ (trước khi có Recap) chưa có thời gian: ước tính 3 phút rưỡi mỗi bài.
        let totalSeconds = list.reduce(0.0) { $0 + ($1.seconds > 0 ? $1.seconds : 210) }
        let uniqueSongs = Set(list.map { $0.id }).count
        let uniqueArtists = Set(list.map { $0.artist }).filter { !$0.isEmpty }.count

        content.addArrangedSubview(heroCard(minutes: minutes(totalSeconds), plays: list.count, songs: uniqueSongs, artists: uniqueArtists))

        var songCounts: [String: (record: PlayRecord, count: Int)] = [:]
        var artistSeconds: [String: Double] = [:]
        var weekdays = [Int](repeating: 0, count: 8)
        var hours = [Int](repeating: 0, count: 24)
        let calendar = Calendar.current
        var days = Set<Date>()
        for r in list {
            var entry = songCounts[r.id] ?? (r, 0)
            entry.count += 1
            songCounts[r.id] = entry
            if !r.artist.isEmpty { artistSeconds[r.artist, default: 0] += r.seconds > 0 ? r.seconds : 210 }
            weekdays[calendar.component(.weekday, from: r.date)] += 1
            hours[calendar.component(.hour, from: r.date)] += 1
            days.insert(calendar.startOfDay(for: r.date))
        }
        let topSongs = songCounts.values.sorted { $0.count > $1.count }.prefix(5)
        content.addArrangedSubview(section(L("Bài nghe nhiều nhất"), rows: topSongs.enumerated().map { i, e in
            (String(i + 1), e.record.title, e.record.artist, Lf("%@ lần", e.count), e.record.thumb)
        }))
        let topArtists = artistSeconds.sorted { $0.value > $1.value }.prefix(5)
        content.addArrangedSubview(section(L("Nghệ sĩ nghe nhiều nhất"), rows: topArtists.enumerated().map { i, e in
            (String(i + 1), e.key, "", Lf("%@ phút", minutes(e.value)), nil)
        }))

        let names = ["", L("Chủ nhật"), L("Thứ Hai"), L("Thứ Ba"), L("Thứ Tư"), L("Thứ Năm"), L("Thứ Sáu"), L("Thứ Bảy")]
        let bestDay = (1...7).max { weekdays[$0] < weekdays[$1] } ?? 1
        let bestHour = (0..<24).max { hours[$0] < hours[$1] } ?? 0
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86400)
        }
        content.addArrangedSubview(section(L("Thói quen"), rows: [
            ("", L("Ngày nghe nhiều nhất"), names[bestDay], "", nil),
            ("", L("Giờ nghe nhiều nhất"), Lf("%@ giờ", bestHour), "", nil),
            ("", L("Chuỗi ngày liên tiếp"), Lf("%@ ngày", streak), "", nil),
            ("", L("Số ngày có nghe"), Lf("%@ ngày", days.count), "", nil)
        ]))
    }

    // MARK: - Dựng thẻ

    private func label(_ text: String, font: UIFont, color: UIColor, centered: Bool = false) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.numberOfLines = 0
        if centered { l.textAlignment = .center }
        return l
    }

    private func heroCard(minutes: Int, plays: Int, songs: Int, artists: Int) -> UIView {
        let card = GradientView()
        card.gradientLayer.colors = [Theme.accent.cgColor, UIColor(red: 0.55, green: 0.1, blue: 0.9, alpha: 1).cgColor]
        card.gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        card.gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        card.layer.cornerRadius = 20
        card.clipsToBounds = true
        let caption = label(L("Bạn đã nghe"), font: Theme.bold(15), color: UIColor(white: 1, alpha: 0.8))
        let big = label(Lf("%@ phút", minutes), font: Theme.bold(44), color: .white)
        let hours = minutes >= 60 ? String(format: L("≈ %.1f giờ"), Double(minutes) / 60) : " "
        let sub = label(hours, font: Theme.bold(16), color: UIColor(white: 1, alpha: 0.85))
        let stats = label(Lf("%@ lượt nghe · %@ bài · %@ nghệ sĩ", plays, songs, artists), font: Theme.regular(15), color: UIColor(white: 1, alpha: 0.9))
        let stack = UIStackView(arrangedSubviews: [caption, big, sub, stats])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        ])
        return card
    }

    private func section(_ title: String, rows: [(String, String, String, String, String?)]) -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.card
        card.layer.cornerRadius = 16
        let heading = label(title, font: Theme.bold(18), color: Theme.primaryText)
        var views: [UIView] = [heading]
        for row in rows { views.append(rowView(rank: row.0, title: row.1, subtitle: row.2, trailing: row.3, thumb: row.4)) }
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        return card
    }

    private func rowView(rank: String, title: String, subtitle: String, trailing: String, thumb: String?) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        if !rank.isEmpty {
            let r = label(rank, font: Theme.bold(16), color: Theme.accent)
            r.widthAnchor.constraint(equalToConstant: 16).isActive = true
            row.addArrangedSubview(r)
        }
        if let thumb = thumb, let url = URL(string: thumb) {
            let image = UIImageView()
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 6
            image.backgroundColor = Theme.placeholder
            image.widthAnchor.constraint(equalToConstant: 40).isActive = true
            image.heightAnchor.constraint(equalToConstant: 40).isActive = true
            ImageLoader.shared.load(url) { img in image.image = img }
            row.addArrangedSubview(image)
        }
        let texts = UIStackView(arrangedSubviews: [label(title, font: Theme.bold(15), color: Theme.primaryText)])
        texts.axis = .vertical
        texts.spacing = 1
        if !subtitle.isEmpty { texts.addArrangedSubview(label(subtitle, font: Theme.regular(13), color: Theme.secondaryText)) }
        row.addArrangedSubview(texts)
        if !trailing.isEmpty {
            let t = label(trailing, font: Theme.bold(14), color: Theme.secondaryText)
            t.setContentHuggingPriority(.required, for: .horizontal)
            t.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(t)
        }
        return row
    }

    // MARK: - Chia sẻ

    @objc private func share() {
        UIGraphicsBeginImageContextWithOptions(content.bounds.size, true, 2)
        Theme.background.setFill()
        UIRectFill(CGRect(origin: .zero, size: content.bounds.size))
        content.drawHierarchy(in: content.bounds, afterScreenUpdates: true)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let picture = image else { return }
        let controller = UIActivityViewController(activityItems: [picture], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(controller, animated: true, completion: nil)
    }
}
