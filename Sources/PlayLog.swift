import Foundation

/// Mỗi lượt nghe: dùng cho Recap (khác lịch sử nghe, giữ lâu hơn và có thời gian nghe thật).
struct PlayRecord: Codable {
    let id: String
    let title: String
    let artist: String
    let thumb: String?
    let date: Date
    var seconds: Double
}

final class PlayLog {
    static let shared = PlayLog()
    private(set) var records: [PlayRecord] = []
    private var dirty = false
    private var saveScheduled = false
    private let limit = 30000
    private let io = DispatchQueue(label: "mochyios.playlog")

    private var fileURL: URL { return Library.supportDirectory.appendingPathComponent("plays.json") }

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: fileURL), let list = try? decoder.decode([PlayRecord].self, from: data) {
            records = list
        }
    }

    /// Ghi một lượt nghe mới (gọi khi bài bắt đầu phát).
    func record(_ song: Song) {
        records.append(PlayRecord(id: song.videoId, title: song.title, artist: song.artist,
                                  thumb: song.thumbnailURL?.absoluteString, date: Date(), seconds: 0))
        if records.count > limit { records.removeFirst(records.count - limit) }
        markDirty()
    }

    /// Cộng thời gian nghe thật vào lượt nghe gần nhất của bài này.
    func addListening(_ id: String, seconds: Double) {
        guard var last = records.last, last.id == id else { return }
        last.seconds += seconds
        records[records.count - 1] = last
        markDirty()
    }

    func merge(_ other: [PlayRecord]) {
        let known = Set(records.map { "\($0.id)|\(Int($0.date.timeIntervalSince1970))" })
        for r in other where !known.contains("\(r.id)|\(Int(r.date.timeIntervalSince1970))") { records.append(r) }
        records.sort { $0.date < $1.date }
        if records.count > limit { records.removeFirst(records.count - limit) }
        markDirty()
    }

    private func markDirty() {
        dirty = true
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.saveScheduled = false
            self?.flush()
        }
    }

    /// Ghi xuống đĩa (gọi thêm khi app xuống nền).
    func flush() {
        guard dirty else { return }
        dirty = false
        let snapshot = records
        let url = fileURL
        io.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }
}
