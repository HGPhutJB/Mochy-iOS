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
        guard let shelf = shelves.first(where: { $0.title.hasPrefix(L("Vì bạn nghe")) }) ?? shelves.first else { return nil }
        let pool = Array(shelf.songs.prefix(10))
        if pool.isEmpty { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let song = pool[day % pool.count]
        let kicker = shelf.title.hasPrefix(L("Vì bạn nghe")) ? shelf.title.uppercased() : L("GỢI Ý HÔM NAY")
        return (song, kicker)
    }

    // MARK: - Bộ lọc: chỉ nhạc Việt của nghệ sĩ trẻ, bản gốc

    /// Nghệ sĩ Việt trẻ / đang hot (so khớp theo tên đã bỏ dấu, viết thường).
    static let youngArtists: [String] = [
        "son tung", "hieuthuhai", "mck", "wren evans", "low g", "obito", "hurrykng", "tang duy tan", "amee", "orange",
        "grey d", "hoang dung", "vu.", "duc phuc", "hoa minzy", "bich phuong", "mono", "jack", "binz", "karik",
        "duong domic", "buitruonglinh", "phuong ly", "chi pu", "tlinh", "bray", "ca hoi hoang", "le hieu", "anh tu",
        "datkaa", "kay tran", "negav", "justatee", "andree right hand", "rhyder", "pháo", "phao", "da lab", "chillies",
        "thinh suy", "wxrdie", "gducky", "ngot", "madihu", "hoang duyen", "marzuz", "changg", "pialinh",
        "tuan hung", "nhu viet", "myra tran", "han sara", "juky san", "huong ly", "erik", "hoaprox", "citii", "mr.siro",
        "den vau", "lyly", "trung quan", "lou hoang", "vu cat tuong", "quanvrox", "cukak", "thanh hung", "vsoul",
        "6 kay", "nguyen hung", "tien tien", "ngo lan huong", "van mai huong", "thuy chi", "yuno bigboi", "wean",
        "khoi vu", "mikelodic", "pham quynh anh", "hoang ton", "dat g", "du uyen", "linh cao", "mew amazing",
        "trinh thang binh", "bui anh tuan", "ho quang hieu", "nguyen tran trung quan", "pion"
    ]

    private static let blockedWords: [String] = [
        "remix", "lofi", "lo-fi", "lo fi", "cover", "karaoke", "beat", "instrumental", "nightcore", "slowed", "sped up",
        "speed up", "reverb", "mashup", "live", "acoustic", "version", "ver.", "bolero", "tru tinh", "hat lai",
        "playlist", "1 hour", "tong hop", "lien khuc", "dj ", " edm", "extended", "vinahouse", "tone nu", "tone nam",
        "full album", "medley", "off vocal", "piano", "guitar", "sleep", "chill hop", "orinn", "house"
    ]

    private static let blockedArtists: [String] = [
        "quang le", "le quyen", "dam vinh hung", "nhu quynh", "tuan vu", "ngoc son", "phi nhung", "truong vu", "che linh",
        "duy khanh", "huong lan", "thanh tuyen", "elvis phuong", "ngoc ha", "giao tien", "le sang", "thien quang",
        "quynh trang", "dan nguyen", "lam truong", "bang kieu", "manh quynh", "cam ly", "ho ngoc ha", "tuan ngoc",
        "khanh ly", "ngoc lan", "dj", "various artists", "topic"
    ]

    private static func fold(_ text: String) -> String {
        let t = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
        return t.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d").lowercased()
    }

    /// Khớp nguyên từ (không khớp giữa chữ: "beat" không dính "heartbeat").
    private static func hasTerm(_ text: String, _ term: String) -> Bool {
        let t = term.trimmingCharacters(in: .whitespaces)
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: t, range: search) {
            let before = r.lowerBound == text.startIndex ? " " : String(text[text.index(before: r.lowerBound)])
            let after = r.upperBound == text.endIndex ? " " : String(text[r.upperBound])
            let isWord: (String) -> Bool = { $0.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil }
            if !isWord(before) && (!isWord(after) || t.hasSuffix(".")) { return true }
            search = r.upperBound..<text.endIndex
        }
        return false
    }

    private static func isOriginalTitle(_ song: Song) -> Bool {
        let title = fold(song.title)
        for word in blockedWords where hasTerm(title, word) { return false }
        let sub = fold(song.subtitle)
        if hasTerm(sub, "remix") || hasTerm(sub, "karaoke") { return false }
        return true
    }

    private static func isBlockedArtist(_ song: Song) -> Bool {
        let artist = fold(song.artist)
        return blockedArtists.contains { hasTerm(artist, $0) }
    }

    private static func isYoungArtist(_ song: Song) -> Bool {
        let artist = fold(song.artist)
        return youngArtists.contains { hasTerm(artist, $0) }
    }

    /// `requireYoung`: chỉ nhận nghệ sĩ nằm trong danh sách trẻ; không bật thì chỉ loại bản remix/cover và nghệ sĩ bolero/trung niên.
    static func clean(_ songs: [Song], requireYoung: Bool) -> [Song] {
        var seen = Set<String>()
        var out: [Song] = []
        for song in songs {
            guard isOriginalTitle(song), !isBlockedArtist(song) else { continue }
            if requireYoung && !isYoungArtist(song) { continue }
            let key = fold(song.title).trimmingCharacters(in: .whitespaces)
            if !seen.insert(song.videoId).inserted || !seen.insert(key).inserted { continue }
            out.append(song)
        }
        return out
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
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let group = DispatchGroup()
        let lock = NSLock()
        var personal: [Shelf] = []
        var charts: [Shelf] = []
        var tiktok: [Song] = []
        var fresh: [Song] = []
        var rising: [Int: [Song]] = [:]
        var errors: [String] = []

        func add(_ error: Error) { lock.lock(); errors.append(error.localizedDescription); lock.unlock() }

        if let artist = Library.shared.topArtists(limit: 1).first {
            group.enter()
            InnerTube.shared.search(artist) { result in
                switch result {
                case .success(let songs):
                    let ok = HomeFeed.clean(songs, requireYoung: false)
                    if ok.count >= 3 { personal = [Shelf(title: Lf("Vì bạn nghe %@", artist), songs: Array(ok.prefix(20)))] }
                case .failure(let error): add(error)
                }
                group.leave()
            }
        }

        group.enter()
        InnerTube.shared.browse("FEmusic_charts", formData: ["selectedValues": ["VN"]]) { result in
            if case .success(let found) = result, let first = found.first {
                let ok = HomeFeed.clean(first.songs, requireYoung: true)
                if ok.count >= 3 { charts = [Shelf(title: L("Thịnh hành"), songs: Array(ok.prefix(20)))] }
            }
            group.leave()
        }

        for query in ["nhạc việt hot tiktok \(year)", "bài hát viral tiktok việt nam", "nhạc trẻ trend tiktok gốc"] {
            group.enter()
            InnerTube.shared.search(query) { result in
                switch result {
                case .success(let songs):
                    lock.lock(); tiktok += HomeFeed.clean(songs, requireYoung: false); lock.unlock()
                case .failure(let error): add(error)
                }
                group.leave()
            }
        }

        for query in ["nhạc trẻ mới \(year)", "vpop hits mới \(year)"] {
            group.enter()
            InnerTube.shared.search(query) { result in
                switch result {
                case .success(let songs):
                    lock.lock(); fresh += HomeFeed.clean(songs, requireYoung: false); lock.unlock()
                case .failure(let error): add(error)
                }
                group.leave()
            }
        }

        // Mỗi ngày xoay vòng 5 nghệ sĩ trẻ để gợi ý đa dạng.
        let names = ["Sơn Tùng M-TP", "HIEUTHUHAI", "MCK", "Wren Evans", "Low G", "AMEE", "Grey D", "Hoàng Dũng", "Đức Phúc", "Tăng Duy Tân",
                     "Dương Domic", "buitruonglinh", "tlinh", "Orange", "Vũ.", "Obito", "HURRYKNG", "Binz", "Hòa Minzy", "Bích Phương",
                     "Justatee", "Phương Ly", "Rhyder", "Hoàng Duyên", "marzuz"]
        for k in 0..<5 {
            let name = names[(day * 5 + k) % names.count]
            group.enter()
            InnerTube.shared.search(name + " bài hát") { result in
                switch result {
                case .success(let songs):
                    let ok = HomeFeed.clean(songs, requireYoung: true)
                    lock.lock(); rising[k] = Array(ok.prefix(4)); lock.unlock()
                case .failure(let error): add(error)
                }
                group.leave()
            }
        }

        group.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            var shelves = personal
            let hot = HomeFeed.clean(tiktok, requireYoung: false)
            if hot.count >= 3 { shelves.append(Shelf(title: L("Hot TikTok"), songs: Array(hot.prefix(20)))) }
            let mix = HomeFeed.clean((0..<5).flatMap { rising[$0] ?? [] }, requireYoung: true)
            if mix.count >= 3 { shelves.append(Shelf(title: L("Nghệ sĩ trẻ đang lên"), songs: Array(mix.prefix(20)))) }
            let newer = HomeFeed.clean(fresh, requireYoung: false)
            if newer.count >= 3 { shelves.append(Shelf(title: L("Nhạc trẻ mới"), songs: Array(newer.prefix(20)))) }
            shelves += charts
            if shelves.isEmpty {
                self.lastError = errors.first ?? L("Không tải được gợi ý. Kéo xuống để thử lại.")
            } else {
                self.shelves = shelves
                let cache = Cache(day: HomeFeed.dayString(), shelves: shelves)
                if let data = try? JSONEncoder().encode(cache) {
                    try? data.write(to: self.cacheURL, options: .atomic)
                }
            }
            completion()
        }
    }
}
