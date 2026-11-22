import Foundation

/// Một bài hát trong kết quả tìm kiếm / hàng đợi / thư viện.
struct Song: Codable, Hashable {
    let videoId: String
    let title: String
    let artist: String
    let subtitle: String      // "Nghệ sĩ · Album · 3:45"
    let duration: String?     // "3:45" nếu có
    let thumbnailURL: URL?

    /// Ảnh bìa lớn hơn (dùng cho màn hình đang phát).
    var largeThumbnailURL: URL? {
        guard let url = thumbnailURL else { return nil }
        let big = url.absoluteString.replacingOccurrences(of: "=w226-h226", with: "=w544-h544")
        return URL(string: big) ?? url
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        return lhs.videoId == rhs.videoId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(videoId)
    }
}

struct Playlist: Codable {
    let id: String
    var name: String
    var songs: [Song]
    let created: Date
}

struct HistoryEntry: Codable {
    let song: Song
    let date: Date
}

/// Một hàng ngang bài hát trên trang chủ.
struct Shelf: Codable {
    let title: String
    let songs: [Song]
}

/// Lỗi có thông điệp tiếng Việt để hiện thẳng lên màn hình (giúp tìm lỗi trên máy thật).
enum MochyError: Error, LocalizedError {
    case http(Int, String, String)
    case badResponse(String)
    case noStream(String)
    case playback(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let host, let snippet):
            return "Máy chủ \(host) trả về HTTP \(code)\n\(snippet)"
        case .badResponse(let s):
            return "Phản hồi không hợp lệ: \(s)"
        case .noStream(let s):
            return s
        case .playback(let s):
            return s
        }
    }
}

/// Luồng âm thanh đã giải ra được từ YouTube Music.
struct StreamInfo {
    let url: URL
    let userAgent: String
    let mimeType: String
    let clientName: String
    let bitrate: Int       // bit/giây, 0 nếu không rõ
    let sampleRate: Int    // Hz, 0 nếu không rõ
    var durationSeconds: Double = 0  // độ dài thật theo YouTube, 0 nếu không rõ
    var unverified = false      // không client nào qua kiểm tra byte cuối
    var contentLength: Int64 = 0  // byte, 0 nếu không rõ

    var codecLabel: String {
        return mimeType.hasPrefix("audio/mp4") ? "AAC" : "MP4"
    }

    /// Ví dụ "AAC · 44,1 kHz · 131 kbps" (kiểu "Stats for nerds" của Mochy).
    var badge: String {
        var parts = [codecLabel]
        if sampleRate > 0 {
            parts.append(String(format: "%.1f kHz", Double(sampleRate) / 1000.0).replacingOccurrences(of: ".", with: ","))
        }
        if bitrate > 0 { parts.append("\(bitrate / 1000) kbps") }
        parts.append(unverified ? clientName + " (bị cắt)" : clientName)
        return parts.joined(separator: " · ")
    }
}
