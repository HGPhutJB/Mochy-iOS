import Foundation
import AVFoundation
import MobileCoreServices

/// YouTube giới hạn mỗi yêu cầu tải liền (~1 MiB ≈ 59 giây âm thanh) rồi cắt luồng.
/// Bộ nạp này đưa cho AVPlayer một "tệp" ảo và tự tải từng đoạn nhỏ (như yt-dlp), nên nhạc không bị đứng giữa chừng.
final class ChunkedLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "mochychunk"
    private static let chunkSize: Int64 = 768 * 1024

    let delegateQueue = DispatchQueue(label: "mochy.chunkloader.delegate")
    private let work = DispatchQueue(label: "mochy.chunkloader.work", attributes: .concurrent)
    private let stream: StreamInfo
    private let session: URLSession
    private let lock = NSLock()
    private var totalLength: Int64
    private(set) var assetURL: URL

    init?(stream: StreamInfo) {
        guard stream.contentLength > 0,
              var comps = URLComponents(url: stream.url, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = ChunkedLoader.scheme
        guard let url = comps.url else { return nil }
        self.stream = stream
        self.assetURL = url
        self.totalLength = stream.contentLength
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": stream.userAgent,
                                         "Accept": "*/*",
                                         "Accept-Language": "en-US,en;q=0.9",
                                         "Referer": "https://www.youtube.com/",
                                         "Origin": "https://www.youtube.com"]
        self.session = URLSession(configuration: config)
        super.init()
    }

    deinit { session.invalidateAndCancel() }

    private func total() -> Int64 { lock.lock(); defer { lock.unlock() }; return totalLength }
    private func setTotal(_ v: Int64) { lock.lock(); totalLength = v; lock.unlock() }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard loadingRequest.request.url?.scheme == ChunkedLoader.scheme else { return false }
        work.async { [weak self] in self?.handle(loadingRequest) }
        return true
    }

    // MARK: - Tải

    /// Tải một đoạn [start, end] (gồm cả hai đầu). Thử tham số `range=` trước, rồi tới header Range.
    private func fetch(_ start: Int64, _ end: Int64) -> (Data, Int64?)? {
        var attempts: [URLRequest] = []
        if var comps = URLComponents(url: stream.url, resolvingAgainstBaseURL: false) {
            var items = (comps.queryItems ?? []).filter { $0.name != "range" }
            items.append(URLQueryItem(name: "range", value: "\(start)-\(end)"))
            comps.queryItems = items
            if let u = comps.url {
                attempts.append(URLRequest(url: u))
            }
        }
        var headerReq = URLRequest(url: stream.url)
        headerReq.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        attempts.append(headerReq)

        for req in attempts {
            let sem = DispatchSemaphore(value: 0)
            var result: (Data, Int64?)?
            session.dataTask(with: req) { data, response, _ in
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data = data, !data.isEmpty {
                    var total: Int64?
                    if let cr = http.allHeaderFields["Content-Range"] as? String,
                       let slash = cr.lastIndex(of: "/") {
                        total = Int64(cr[cr.index(after: slash)...])
                    }
                    result = (data, total)
                }
                sem.signal()
            }.resume()
            sem.wait()
            if let r = result {
                // Nếu máy chủ trả cả tệp (bỏ qua range) thì cắt đúng đoạn cần.
                if Int64(r.0.count) > end - start + 1, r.0.count >= Int(end + 1) {
                    return (r.0.subdata(in: Int(start)..<Int(end + 1)), r.1)
                }
                return r
            }
        }
        return nil
    }

    private func handle(_ request: AVAssetResourceLoadingRequest) {
        // Biết tổng dung lượng trước đã.
        if total() <= 0 {
            guard let first = fetch(0, ChunkedLoader.chunkSize - 1) else {
                request.finishLoading(with: NSError(domain: "Mochy", code: -1, userInfo: [NSLocalizedDescriptionKey: L("Không tải được luồng nhạc")]))
                return
            }
            if let t = first.1 { setTotal(t) }
        }
        let length = total()
        if let info = request.contentInformationRequest {
            info.contentType = stream.mimeType.hasPrefix("audio/") ? "com.apple.m4a-audio" : "public.mpeg-4"
            info.isByteRangeAccessSupported = true
            info.contentLength = length > 0 ? length : Int64.max
        }
        guard let data = request.dataRequest else {
            request.finishLoading()
            return
        }
        var offset = data.requestedOffset
        let wantedEnd: Int64 = data.requestsAllDataToEndOfResource
            ? (length > 0 ? length : Int64.max)
            : data.requestedOffset + Int64(data.requestedLength)
        let endLimit = length > 0 ? min(wantedEnd, length) : wantedEnd

        while offset < endLimit {
            if request.isCancelled { return }
            let last = min(offset + ChunkedLoader.chunkSize, endLimit) - 1
            var piece: (Data, Int64?)?
            for _ in 0..<3 {
                piece = fetch(offset, last)
                if piece != nil || request.isCancelled { break }
                Thread.sleep(forTimeInterval: 0.4)
            }
            guard let got = piece else {
                if !request.isCancelled {
                    request.finishLoading(with: NSError(domain: "Mochy", code: -2, userInfo: [NSLocalizedDescriptionKey: L("Luồng nhạc bị ngắt giữa chừng")]))
                }
                return
            }
            data.respond(with: got.0)
            offset += Int64(got.0.count)
        }
        if !request.isCancelled { request.finishLoading() }
    }
}
