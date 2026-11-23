import Foundation
import UIKit

/// Sao lưu và khôi phục dữ liệu của người dùng (yêu thích, playlist, lịch sử, cài đặt) ra một tệp JSON.
/// Tệp nằm trong Documents/MochyBackup nên xem được trong ứng dụng Tệp; khôi phục luôn là GỘP, không xoá dữ liệu đang có.
enum BackupManager {
    struct Settings: Codable {
        var quality: Int
        var video: Bool
        var blur: Int
        var lyricWeight: Int
        var theme: Int
    }

    struct Envelope: Codable {
        var app: String
        var version: String
        var date: Date
        var library: Library.Store
        var settings: Settings
        var plays: [PlayRecord]?
    }

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("MochyBackup", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    private static func makeEnvelope() -> Envelope {
        let settings = Settings(quality: AppSettings.audioQuality.rawValue, video: AppSettings.videoBackdrop,
                                blur: AppSettings.playerBlur.rawValue, lyricWeight: AppSettings.lyricWeight, theme: Theme.mode.rawValue)
        return Envelope(app: UpdateConfig.appId, version: AppInfo.version, date: Date(),
                        library: Library.shared.snapshot(), settings: settings, plays: PlayLog.shared.records)
    }

    /// Ghi một bản sao lưu; `name` là phần tên tệp sau "Mochy-".
    @discardableResult
    static func backup(name: String) -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(makeEnvelope()) else { return nil }
        let url = directory.appendingPathComponent("Mochy-\(name).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Sao lưu tự động mỗi khi mở app (tối đa 12 giờ một lần). Chỉ giữ một tệp "tu-dong" nên không phình ra.
    static func autoBackupIfNeeded() {
        let key = "backup.lastAuto"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 12 * 3600 { return }
        let library = Library.shared
        if library.liked.isEmpty && library.playlists.isEmpty && library.history.isEmpty { return }
        DispatchQueue.global(qos: .utility).async {
            if backup(name: "tu-dong") != nil {
                UserDefaults.standard.set(Date(), forKey: key)
            }
        }
    }

    static func timestampName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    /// Đọc tệp sao lưu và gộp vào thư viện. Trả về số mục thêm mới hoặc thông báo lỗi.
    static func restore(from url: URL) -> Result<Int, UpdateError> {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return .failure(UpdateError("Không đọc được tệp.")) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let envelope = try? decoder.decode(Envelope.self, from: data), envelope.app == UpdateConfig.appId else {
            return .failure(UpdateError("Đây không phải tệp sao lưu của Mochy iOS."))
        }
        let added = Library.shared.merge(envelope.library)
        if let plays = envelope.plays { PlayLog.shared.merge(plays) }
        // Cài đặt chỉ áp dụng khi máy này đang để mặc định (chưa chỉnh gì), tránh ghi đè lựa chọn mới.
        if UserDefaults.standard.object(forKey: "lyrics.weight") == nil { AppSettings.lyricWeight = envelope.settings.lyricWeight }
        if UserDefaults.standard.object(forKey: "player.blur") == nil, let blur = PlayerBlur(rawValue: envelope.settings.blur) { AppSettings.playerBlur = blur }
        return .success(added)
    }
}
