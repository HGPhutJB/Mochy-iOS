import Foundation

extension Notification.Name {
    static let downloadChanged = Notification.Name("MochyiOSDownloadChanged")
    static let downloadFailed = Notification.Name("MochyiOSDownloadFailed")
}

/// Tải âm thanh về máy để nghe offline. Tải từng khúc 1 MB bằng HTTP Range (YouTube hay chặn tải một lần cả tệp).
final class DownloadManager {
    static let shared = DownloadManager()

    /// Tiến độ (0...1) của các bài đang tải.
    private(set) var progress: [String: Double] = [:]
    private var cancelled = Set<String>()
    private let session: URLSession
    private let chunkSize: Int64 = 1_048_576

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    func isActive(_ videoId: String) -> Bool {
        return progress[videoId] != nil
    }

    func start(_ song: Song) {
        guard progress[song.videoId] == nil, !Library.shared.isDownloaded(song) else { return }
        progress[song.videoId] = 0
        cancelled.remove(song.videoId)
        post()
        InnerTube.shared.resolveStream(videoId: song.videoId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.finish(song, error: error.localizedDescription)
            case .success(let info):
                self.begin(song, info: info)
            }
        }
    }

    private var waiting: [Song] = []
    private let maxParallel = 2

    /// Tải nhiều bài: xếp hàng, tối đa 2 bài cùng lúc. Trả về số bài được xếp (bỏ qua bài đã tải/đang tải).
    @discardableResult
    func enqueue(_ songs: [Song]) -> Int {
        var added = 0
        for song in songs where !Library.shared.isDownloaded(song) && progress[song.videoId] == nil
            && !waiting.contains(where: { $0.videoId == song.videoId }) {
            waiting.append(song)
            added += 1
        }
        pump()
        return added
    }

    var queuedCount: Int { return waiting.count }

    func cancelQueue() {
        waiting.removeAll()
    }

    private func pump() {
        while progress.count < maxParallel, !waiting.isEmpty {
            start(waiting.removeFirst())
        }
    }

    func cancel(_ videoId: String) {
        if progress[videoId] != nil {
            cancelled.insert(videoId)
        }
    }

    // MARK: - Nội bộ

    private func post() {
        NotificationCenter.default.post(name: .downloadChanged, object: nil)
    }

    private func finish(_ song: Song, error: String?) {
        progress[song.videoId] = nil
        cancelled.remove(song.videoId)
        post()
        if let error = error {
            NotificationCenter.default.post(name: .downloadFailed, object: nil,
                                            userInfo: ["message": "\(song.title)\n\(error)"])
        }
        pump()
    }

    private func begin(_ song: Song, info: StreamInfo) {
        let temp = Library.downloadsDirectory.appendingPathComponent(song.videoId + ".part")
        try? FileManager.default.removeItem(at: temp)
        FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: nil)
        guard let handle = FileHandle(forWritingAtPath: temp.path) else {
            finish(song, error: "Không tạo được tệp tạm.")
            return
        }
        fetch(song, info: info, handle: handle, temp: temp, offset: 0, total: nil)
    }

    private func abort(_ song: Song, handle: FileHandle, temp: URL, error: String?) {
        handle.closeFile()
        try? FileManager.default.removeItem(at: temp)
        finish(song, error: error)
    }

    private func complete(_ song: Song, info: StreamInfo, handle: FileHandle, temp: URL) {
        handle.closeFile()
        // Tệp thiếu so với dung lượng khai báo = tải bị cắt giữa chừng: báo lỗi thay vì lưu một bài hụt.
        let written = ((try? FileManager.default.attributesOfItem(atPath: temp.path))?[.size] as? NSNumber)?.int64Value ?? 0
        if info.contentLength > 0 && written < Int64(Double(info.contentLength) * 0.98) {
            try? FileManager.default.removeItem(at: temp)
            finish(song, error: "Tệp tải về bị thiếu (\(written) / \(info.contentLength) byte). Hãy thử tải lại.")
            return
        }
        let target = Library.downloadsDirectory.appendingPathComponent(song.videoId + ".m4a")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.moveItem(at: temp, to: target)
        } catch {
            finish(song, error: "Không lưu được tệp: \(error.localizedDescription)")
            return
        }
        // Độ dài thật + lời bài hát được lưu cạnh tệp nhạc để nghe offline đúng độ dài, có lời.
        let real = info.durationSeconds > 0 ? info.durationSeconds : LyricsService.seconds(song.duration)
        DownloadStore.update(song.videoId) { $0.duration = real > 0 ? real : nil }
        DownloadStore.normalize(file: target, realDuration: real) { [weak self] in
            Library.shared.addDownload(song)
            self?.progress[song.videoId] = nil
            self?.post()
            self?.pump()
            LyricsService.shared.storeForDownload(song, durationHint: real)
        }
    }

    private func fetch(_ song: Song, info: StreamInfo, handle: FileHandle, temp: URL, offset: Int64, total: Int64?) {
        if cancelled.contains(song.videoId) {
            abort(song, handle: handle, temp: temp, error: nil)
            return
        }
        var request = URLRequest(url: info.url)
        request.setValue(info.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=\(offset)-\(offset + chunkSize - 1)", forHTTPHeaderField: "Range")
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.abort(song, handle: handle, temp: temp, error: error.localizedDescription)
                    return
                }
                guard let http = response as? HTTPURLResponse, let data = data else {
                    self.abort(song, handle: handle, temp: temp, error: "Không có phản hồi.")
                    return
                }
                if http.statusCode == 416 && offset > 0 {
                    self.complete(song, info: info, handle: handle, temp: temp)
                    return
                }
                if http.statusCode == 200 {
                    // Máy chủ bỏ qua Range và trả cả tệp.
                    handle.write(data)
                    self.complete(song, info: info, handle: handle, temp: temp)
                    return
                }
                guard http.statusCode == 206 else {
                    self.abort(song, handle: handle, temp: temp, error: "Máy chủ trả về HTTP \(http.statusCode).")
                    return
                }
                handle.write(data)
                let newOffset = offset + Int64(data.count)
                var totalBytes = total
                if totalBytes == nil,
                   let range = http.allHeaderFields["Content-Range"] as? String,
                   let slash = range.lastIndex(of: "/") {
                    totalBytes = Int64(range[range.index(after: slash)...])
                }
                if let t = totalBytes, t > 0 {
                    self.progress[song.videoId] = min(1, Double(newOffset) / Double(t))
                    self.post()
                }
                if data.isEmpty || (totalBytes != nil && newOffset >= totalBytes!) {
                    self.complete(song, info: info, handle: handle, temp: temp)
                } else {
                    self.fetch(song, info: info, handle: handle, temp: temp, offset: newOffset, total: totalBytes)
                }
            }
        }.resume()
    }
}
