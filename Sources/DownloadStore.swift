import Foundation
import AVFoundation

/// Dữ liệu đi kèm mỗi bài đã tải (tệp <videoId>.json cạnh tệp .m4a): độ dài thật và lời bài hát để nghe offline.
struct DownloadMeta: Codable {
    var duration: Double?
    var lyrics: StoredLyrics?
}

struct StoredWord: Codable {
    let t: String
    let s: Double
    let e: Double
}

struct StoredLine: Codable {
    let time: Double
    let text: String
    let words: [StoredWord]
}

struct StoredLyrics: Codable {
    let lines: [StoredLine]
    let plain: String?
    let source: String
}

extension LyricsResult {
    var stored: StoredLyrics {
        let lines = synced.map { line in
            StoredLine(time: line.time, text: line.text, words: line.words.map { StoredWord(t: $0.text, s: $0.start, e: $0.end) })
        }
        return StoredLyrics(lines: lines, plain: plain, source: source)
    }

    init(stored: StoredLyrics) {
        let lines = stored.lines.map { line -> LyricLine in
            var l = LyricLine(time: line.time, text: line.text)
            l.words = line.words.map { LyricWord(text: $0.t, start: $0.s, end: $0.e) }
            return l
        }
        self.init(synced: lines, plain: stored.plain, source: stored.source)
    }
}

enum DownloadStore {
    private static let queue = DispatchQueue(label: "mochyios.downloadstore")

    static func url(_ videoId: String) -> URL {
        return Library.downloadsDirectory.appendingPathComponent(videoId + ".json")
    }

    static func meta(_ videoId: String) -> DownloadMeta? {
        guard let data = try? Data(contentsOf: url(videoId)) else { return nil }
        return try? JSONDecoder().decode(DownloadMeta.self, from: data)
    }

    /// Đọc - sửa - ghi trên một hàng đợi riêng để hai nơi cùng cập nhật (độ dài, lời) không đè nhau.
    static func update(_ videoId: String, _ change: @escaping (inout DownloadMeta) -> Void) {
        queue.async {
            var meta = DownloadStore.meta(videoId) ?? DownloadMeta(duration: nil, lyrics: nil)
            change(&meta)
            if let data = try? JSONEncoder().encode(meta) {
                try? data.write(to: url(videoId), options: .atomic)
            }
        }
    }

    static func lyrics(_ videoId: String) -> LyricsResult? {
        guard let stored = meta(videoId)?.lyrics else { return nil }
        return LyricsResult(stored: stored)
    }

    static func remove(_ videoId: String) {
        try? FileManager.default.removeItem(at: url(videoId))
    }

    /// Độ dài thật của bài đã tải (giây), 0 nếu chưa biết.
    static func realDuration(for song: Song) -> Double {
        if let d = meta(song.videoId)?.duration, d > 0 { return d }
        return LyricsService.seconds(song.duration)
    }

    /// Tệp DASH của YouTube hay khai độ dài sai (bài 3:54 hiện 6:50). Nếu độ dài trong tệp lệch hơn 2 giây so với
    /// độ dài thật thì ghi lại tệp (không nén lại) chỉ lấy đúng đoạn thật, để tệp có độ dài chuẩn.
    /// `done` luôn được gọi, kể cả khi không sửa được (khi đó engine vẫn dùng độ dài thật từ tệp .json).
    static func normalize(file: URL, realDuration: Double, done: @escaping () -> Void) {
        guard realDuration > 5 else { done(); return }
        let asset = AVURLAsset(url: file)
        let current = asset.duration.seconds
        guard current.isFinite, abs(current - realDuration) > 2 else { done(); return }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough),
              export.supportedFileTypes.contains(.m4a) else { done(); return }
        let temp = file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".fix.m4a")
        try? FileManager.default.removeItem(at: temp)
        export.outputURL = temp
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: realDuration, preferredTimescale: 600))
        export.exportAsynchronously {
            var replaced = false
            if export.status == .completed {
                let fixed = AVURLAsset(url: temp).duration.seconds
                if fixed.isFinite, abs(fixed - realDuration) <= 1.5 {
                    do {
                        _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
                        replaced = true
                    } catch {
                        replaced = false
                    }
                }
            }
            if !replaced { try? FileManager.default.removeItem(at: temp) }
            DispatchQueue.main.async { done() }
        }
    }
}
