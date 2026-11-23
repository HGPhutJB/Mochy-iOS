import Foundation

extension Notification.Name {
    static let libraryChanged = Notification.Name("MochyiOSLibraryChanged")
}

/// Thư viện của người dùng: yêu thích, playlist, lịch sử nghe, danh sách bài đã tải. Lưu thành JSON trong Application Support.
final class Library {
    static let shared = Library()

    private(set) var liked: [Song] = []
    private(set) var playlists: [Playlist] = []
    private(set) var history: [HistoryEntry] = []
    private(set) var downloads: [Song] = []

    struct Store: Codable {
        var liked: [Song]
        var playlists: [Playlist]
        var history: [HistoryEntry]
        var downloads: [Song]
    }

    private let ioQueue = DispatchQueue(label: "mochyios.library.io")
    private let historyLimit = 500

    // MARK: - Thư mục

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MochyiOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    static var downloadsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    private var fileURL: URL {
        return Library.supportDirectory.appendingPathComponent("library.json")
    }

    // MARK: - Nạp và lưu

    private init() {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return }
        liked = store.liked
        playlists = store.playlists
        history = store.history
        downloads = store.downloads
    }

    private func save() {
        let store = Store(liked: liked, playlists: playlists, history: history, downloads: downloads)
        let url = fileURL
        ioQueue.async {
            if let data = try? JSONEncoder().encode(store) {
                try? data.write(to: url, options: .atomic)
            }
        }
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
    }

    // MARK: - Sao lưu / khôi phục

    /// Bản chụp dữ liệu để sao lưu (không gồm tệp nhạc đã tải, chỉ gồm danh sách).
    func snapshot() -> Store {
        return Store(liked: liked, playlists: playlists, history: history, downloads: [])
    }

    /// Gộp dữ liệu từ bản sao lưu vào thư viện hiện tại, không xoá hay ghi đè gì đang có. Trả về số mục thêm mới.
    @discardableResult
    func merge(_ other: Store) -> Int {
        var added = 0
        for song in other.liked where !liked.contains(song) {
            liked.append(song)
            added += 1
        }
        for playlist in other.playlists {
            if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
                for song in playlist.songs where !playlists[index].songs.contains(song) {
                    playlists[index].songs.append(song)
                    added += 1
                }
            } else {
                playlists.append(playlist)
                added += 1 + playlist.songs.count
            }
        }
        let known = Set(history.map { "\($0.song.videoId)|\(Int($0.date.timeIntervalSince1970))" })
        for entry in other.history where !known.contains("\(entry.song.videoId)|\(Int(entry.date.timeIntervalSince1970))") {
            history.append(entry)
            added += 1
        }
        history.sort { $0.date > $1.date }
        if history.count > historyLimit { history = Array(history.prefix(historyLimit)) }
        save()
        return added
    }

    // MARK: - Yêu thích

    func isLiked(_ song: Song) -> Bool {
        return liked.contains(song)
    }

    @discardableResult
    func toggleLike(_ song: Song) -> Bool {
        if let index = liked.firstIndex(of: song) {
            liked.remove(at: index)
            save()
            return false
        }
        liked.insert(song, at: 0)
        save()
        return true
    }

    func removeLiked(at index: Int) {
        guard index >= 0 && index < liked.count else { return }
        liked.remove(at: index)
        save()
    }

    // MARK: - Playlist

    func playlist(id: String) -> Playlist? {
        return playlists.first { $0.id == id }
    }

    @discardableResult
    func createPlaylist(name: String, with song: Song? = nil) -> Playlist {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = Playlist(id: UUID().uuidString, name: clean.isEmpty ? "Playlist mới" : clean,
                            songs: song.map { [$0] } ?? [], created: Date())
        playlists.insert(list, at: 0)
        save()
        return list
    }

    /// Nhập một danh sách bài vào playlist: cùng link gốc thì cập nhật (chỉ thêm bài mới), không thì tạo playlist mới.
    @discardableResult
    func importPlaylist(name: String, songs: [Song], sourceURL: String) -> (playlist: Playlist, added: Int) {
        if let i = playlists.firstIndex(where: { $0.sourceURL == sourceURL }) {
            var added = 0
            for song in songs where !playlists[i].songs.contains(song) {
                playlists[i].songs.append(song)
                added += 1
            }
            save()
            return (playlists[i], added)
        }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var unique: [Song] = []
        for song in songs where !unique.contains(song) { unique.append(song) }
        var list = Playlist(id: UUID().uuidString, name: clean.isEmpty ? "Playlist nhập" : clean, songs: unique, created: Date())
        list.sourceURL = sourceURL
        playlists.insert(list, at: 0)
        save()
        return (list, unique.count)
    }

    func renamePlaylist(id: String, name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return }
        playlists[i].name = clean
        save()
    }

    func deletePlaylist(id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    /// false nếu bài đã có trong playlist.
    @discardableResult
    func add(_ song: Song, toPlaylist id: String) -> Bool {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return false }
        if playlists[i].songs.contains(song) { return false }
        playlists[i].songs.append(song)
        save()
        return true
    }

    func removeSong(at index: Int, fromPlaylist id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }),
              index >= 0 && index < playlists[i].songs.count else { return }
        playlists[i].songs.remove(at: index)
        save()
    }

    func moveSong(from: Int, to: Int, inPlaylist id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }),
              from >= 0, to >= 0, from < playlists[i].songs.count, to < playlists[i].songs.count else { return }
        let song = playlists[i].songs.remove(at: from)
        playlists[i].songs.insert(song, at: to)
        save()
    }

    // MARK: - Lịch sử

    func addHistory(_ song: Song) {
        if let first = history.first, first.song == song, Date().timeIntervalSince(first.date) < 30 { return }
        history.insert(HistoryEntry(song: song, date: Date()), at: 0)
        if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
        save()
    }

    func removeHistory(at index: Int) {
        guard index >= 0 && index < history.count else { return }
        history.remove(at: index)
        save()
    }

    func clearHistory() {
        history.removeAll()
        save()
    }

    /// Các bài nghe gần đây, không trùng.
    func recentSongs(limit: Int) -> [Song] {
        var seen = Set<String>()
        var out: [Song] = []
        for entry in history {
            if seen.contains(entry.song.videoId) { continue }
            seen.insert(entry.song.videoId)
            out.append(entry.song)
            if out.count >= limit { break }
        }
        return out
    }

    /// Nghệ sĩ nghe nhiều nhất (đếm theo lịch sử).
    func topArtists(limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for entry in history {
            let name = entry.song.artist.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            counts[name, default: 0] += 1
        }
        let sorted = counts.sorted { $0.value > $1.value }
        return sorted.prefix(limit).map { $0.key }
    }

    // MARK: - Tải xuống

    func isDownloaded(_ song: Song) -> Bool {
        return downloads.contains(song) && localURL(for: song.videoId) != nil
    }

    func localURL(for videoId: String) -> URL? {
        let url = Library.downloadsDirectory.appendingPathComponent(videoId + ".m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func addDownload(_ song: Song) {
        downloads.removeAll { $0 == song }
        downloads.insert(song, at: 0)
        save()
    }

    func removeDownload(_ song: Song) {
        let url = Library.downloadsDirectory.appendingPathComponent(song.videoId + ".m4a")
        try? FileManager.default.removeItem(at: url)
        DownloadStore.remove(song.videoId)
        downloads.removeAll { $0 == song }
        save()
    }

    func removeAllDownloads() {
        for song in downloads {
            let url = Library.downloadsDirectory.appendingPathComponent(song.videoId + ".m4a")
            try? FileManager.default.removeItem(at: url)
            DownloadStore.remove(song.videoId)
        }
        downloads.removeAll()
        save()
    }

    func fileSize(of song: Song) -> Int64 {
        guard let url = localURL(for: song.videoId),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    func totalDownloadBytes() -> Int64 {
        var total: Int64 = 0
        for song in downloads { total += fileSize(of: song) }
        return total
    }
}
