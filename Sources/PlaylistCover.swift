import UIKit

/// Ảnh bìa do người dùng đặt cho playlist tự tạo (lưu thành tệp JPEG vuông trong thư mục của app).
enum PlaylistCover {
    private static let cache = NSCache<NSString, UIImage>()

    private static var directory: URL {
        let dir = Library.supportDirectory.appendingPathComponent("PlaylistCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func image(for list: Playlist) -> UIImage? {
        guard let name = list.customCover else { return nil }
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Cắt giữa ảnh thành hình vuông 512px rồi lưu; trả về tên tệp (mỗi lần đặt là tên mới để khỏi dính cache).
    static func save(_ image: UIImage, playlistId: String) -> String? {
        let side: CGFloat = 512
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let w = max(image.size.width, 1), h = max(image.size.height, 1)
            let scale = max(side / w, side / h)
            let size = CGSize(width: w * scale, height: h * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        guard let data = square.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(playlistId)-\(Int(Date().timeIntervalSince1970)).jpg"
        do { try data.write(to: directory.appendingPathComponent(name), options: .atomic) } catch { return nil }
        cache.setObject(square, forKey: name as NSString)
        return name
    }

    static func remove(file: String?) {
        guard let file = file else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        cache.removeObject(forKey: file as NSString)
    }
}
