import UIKit

/// Tải ảnh bìa, có cache trong bộ nhớ (giới hạn nhỏ cho iPhone 6).
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 80
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    /// Giải mã sẵn ảnh ở luồng nền (UIImage mặc định giải mã trễ ở luồng chính khi vẽ lần đầu → giật khi cuộn/mở màn hình).
    private static func predecoded(_ image: UIImage) -> UIImage {
        guard image.cgImage != nil else { return image }
        let maxSide: CGFloat = 900
        var size = image.size
        let longest = max(size.width, size.height)
        if longest > maxSide { size = CGSize(width: size.width * maxSide / longest, height: size.height * maxSide / longest) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        session.dataTask(with: url) { [weak self] data, _, _ in
            var image: UIImage? = nil
            if let data = data {
                image = UIImage(data: data).map { ImageLoader.predecoded($0) }
            }
            if let image = image {
                self?.cache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}
