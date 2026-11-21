import Foundation

/// Nguồn gợi ý cho trang chủ: bảng xếp hạng, nhạc mới, và "Vì bạn nghe …" theo lịch sử nghe. Lưu cache theo ngày.
final class HomeFeed {
    static let shared = HomeFeed()

    private(set) var shelves: [Shelf] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private struct Cache: Codable {
        let day: String
        let shelves: [Shelf]
    }

    private init() {
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            shelves = cache.shelves
        }
    }

    private var cacheURL: URL {
        return Library.supportDirectory.appendingPathComponent("home.json")
    }

    private static func dayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func cachedForToday() -> Bool {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return false }
        return cache.day == HomeFeed.dayString() && !cache.shelves.isEmpty
    }

    /// Bài nổi bật hôm nay (đổi theo ngày, lấy từ hàng nhạc mới đầu tiên).
    func heroSong() -> (song: Song, kicker: String)? {
        guard let shelf = shelves.first(where: { $0.title.hasPrefix("Vì bạn nghe") }) ?? shelves.first else { return nil }
        let pool = Array(shelf.songs.prefix(10))
        if pool.isEmpty { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let song = pool[day % pool.count]
        let kicker = shelf.title.hasPrefix("Vì bạn nghe") ? shelf.title.uppercased() : "GỢI Ý HÔM NAY"
        return (song, kicker)
    }

    func load(force: Bool, completion: @escaping () -> Void) {
        if isLoading { return }
        if !force && cachedForToday() {
            completion()
            return
        }
        isLoading = true
        lastError = nil
        let year = Calendar.current.component(.year, from: Date())
        let group = DispatchGroup()
        // Mỗi nguồn ghi vào ô riêng, sau đó ghép đúng thứ tự.
        var personal: [Shelf] = []
        var charts: [Shelf] = []
        var vietNew: [Shelf] = []
        var worldNew: [Shelf] = []
        var errors: [String] = []

        if let artist = Library.shared.topArtists(limit: 1).first {
            group.enter()
            InnerTube.shared.search(artist) { result in
                switch result {
                case .success(let songs):
                    if songs.count >= 3 {
                        personal = [Shelf(title: "Vì bạn nghe \(artist)", songs: Array(songs.prefix(20)))]
                    }
                case .failure(let error):
                    errors.append(error.localizedDescription)
                }
                group.leave()
            }
        }

        group.enter()
        InnerTube.shared.browse("FEmusic_charts", formData: ["selectedValues": ["VN"]]) { result in
            if case .success(let found) = result, let first = found.first {
                charts = [Shelf(title: "Thịnh hành", songs: Array(first.songs.prefix(20)))]
            }
            group.leave()
        }

        group.enter()
        InnerTube.shared.search("nhạc việt mới \(year)") { result in
            switch result {
            case .success(let songs):
                if !songs.isEmpty { vietNew = [Shelf(title: "Nhạc Việt mới", songs: Array(songs.prefix(20)))] }
            case .failure(let error):
                errors.append(error.localizedDescription)
            }
            group.leave()
        }

        group.enter()
        InnerTube.shared.search("new songs \(year)") { result in
            switch result {
            case .success(let songs):
                if !songs.isEmpty { worldNew = [Shelf(title: "Nhạc quốc tế mới", songs: Array(songs.prefix(20)))] }
            case .failure(let error):
                errors.append(error.localizedDescription)
            }
            group.leave()
        }

        group.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            let merged = personal + vietNew + charts + worldNew
            if merged.isEmpty {
                self.lastError = errors.first ?? "Không tải được gợi ý. Kéo xuống để thử lại."
            } else {
                self.shelves = merged
                let cache = Cache(day: HomeFeed.dayString(), shelves: merged)
                if let data = try? JSONEncoder().encode(cache) {
                    try? data.write(to: self.cacheURL, options: .atomic)
                }
            }
            completion()
        }
    }
}
