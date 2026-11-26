import Foundation
import UIKit

extension Notification.Name {
    static let updateStateChanged = Notification.Name("MochyiOSUpdateStateChanged")
}

struct UpdateError: Error, LocalizedError {
    let message: String
    let notFound: Bool
    let cancelled: Bool

    init(_ message: String, notFound: Bool = false, cancelled: Bool = false) {
        self.message = message
        self.notFound = notFound
        self.cancelled = cancelled
    }

    var errorDescription: String? { return message }
}

struct UpdateFile {
    let name: String
    let url: URL
    let sha256: String
    let size: Int64
}

struct UpdateInfo {
    let version: String
    let build: Int
    let channel: String
    let commit: String
    let minOS: String
    let date: String
    let notes: String
    let signed: Bool
    let deb: UpdateFile?
    let ipa: UpdateFile?
}

enum UpdateResult {
    case upToDate
    case available(UpdateInfo)
    case failed(String)
}

/// Kiểm tra và tải bản cập nhật từ GitHub Releases của Mochy-iOS.
/// - Chỉ HTTPS, chỉ github.com / *.githubusercontent.com, chặn chuyển hướng ra ngoài.
/// - update.json được kiểm tra chữ ký ECDSA (nếu bản phát hành có chữ ký), tệp tải về được kiểm tra kích thước và SHA-256.
/// - Không bao giờ tự cài: người dùng tự mở tệp bằng Sileo / ESign sau khi đã xác minh.
final class Updater: NSObject, URLSessionDownloadDelegate {
    static let shared = Updater()

    private(set) var available: UpdateInfo?
    private(set) var isChecking = false
    private(set) var lastMessage = ""
    private(set) var lastCheck: Date?
    private(set) var lastCheckWasManual = false

    private var recheckRequested = false
    private var activeFile: UpdateFile?
    private var progressHandler: ((Double) -> Void)?
    private var completionHandler: ((Result<URL, UpdateError>) -> Void)?
    private var downloadTask: URLSessionDownloadTask?
    private var abortReason: String?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 900
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }()

    private override init() {
        super.init()
        lastCheck = UserDefaults.standard.object(forKey: "update.lastCheck") as? Date
    }

    private var userAgent: String {
        return "MochyiOS/\(AppInfo.version) (build \(AppInfo.build); iOS \(AppInfo.osVersion))"
    }

    static var updatesDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("MochyUpdates", isDirectory: true)
    }

    /// Tệp phù hợp với cách cài hiện tại: .deb cho jailbreak, .ipa cho sideload.
    func preferredFile(for info: UpdateInfo) -> UpdateFile? {
        if AppInfo.isJailbreakInstall {
            return info.deb ?? info.ipa
        }
        return info.ipa ?? info.deb
    }

    // MARK: - Kiểm tra cập nhật

    func autoCheckIfNeeded() {
        guard AppSettings.autoCheck else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < UpdateConfig.checkInterval { return }
        check(manual: false)
    }

    func channelDidChange() {
        available = nil
        lastMessage = ""
        if isChecking {
            recheckRequested = true
            postState()
        } else {
            check(manual: true)
        }
    }

    func check(manual: Bool, completion: ((UpdateResult) -> Void)? = nil) {
        if isChecking { return }
        isChecking = true
        lastCheckWasManual = manual
        postState()

        let channel = AppSettings.channel
        let manifestString = (channel == .stable) ? UpdateConfig.stableManifest : UpdateConfig.devManifest
        guard let manifestURL = URL(string: manifestString) else {
            finish(.failed(L("Địa chỉ cập nhật không hợp lệ")), completion)
            return
        }
        let signatureURL = manifestURL.appendingPathExtension("sig")

        fetch(manifestURL) { [weak self] manifestResult in
            guard let self = self else { return }
            switch manifestResult {
            case .failure(let error):
                if error.notFound {
                    let text = channel == .stable ? L("Chưa có bản ổn định nào trên GitHub") : L("Chưa có bản thử nghiệm nào trên GitHub")
                    self.finish(.failed(text), completion)
                } else {
                    self.finish(.failed(error.message), completion)
                }
            case .success(let manifestData):
                self.fetch(signatureURL) { signatureResult in
                    switch signatureResult {
                    case .success(let signatureData):
                        if UpdateVerifier.verifySignature(data: manifestData, signature: signatureData) {
                            self.finish(self.evaluate(manifestData, signed: true), completion)
                        } else {
                            self.finish(.failed(L("Chữ ký của bản cập nhật KHÔNG hợp lệ. Đã bỏ qua vì lý do an toàn.")), completion)
                        }
                    case .failure(let error):
                        if error.notFound {
                            self.finish(self.evaluate(manifestData, signed: false), completion)
                        } else {
                            self.finish(.failed(Lf("Không tải được chữ ký: %@", error.message)), completion)
                        }
                    }
                }
            }
        }
    }

    private func fetch(_ url: URL, completion: @escaping (Result<Data, UpdateError>) -> Void) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(UpdateError(error.localizedDescription)))
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 404 {
                    completion(.failure(UpdateError("HTTP 404", notFound: true)))
                    return
                }
                guard code == 200, let data = data else {
                    completion(.failure(UpdateError(Lf("Máy chủ trả về HTTP %@", code))))
                    return
                }
                if data.count > UpdateConfig.maxManifestBytes {
                    completion(.failure(UpdateError(L("Tệp cập nhật quá lớn"))))
                    return
                }
                completion(.success(data))
            }
        }
        task.resume()
    }

    private func evaluate(_ data: Data, signed: Bool) -> UpdateResult {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let json = object as? [String: Any] else {
            return .failed(L("update.json không đọc được"))
        }
        guard (json["app"] as? String) == UpdateConfig.appId else {
            return .failed(L("Bản cập nhật không dành cho ứng dụng này"))
        }
        guard let version = json["version"] as? String,
              let build = (json["build"] as? NSNumber)?.intValue else {
            return .failed(L("update.json thiếu version hoặc build"))
        }
        let files = json["files"] as? [String: Any] ?? [:]

        func parseFile(_ key: String) -> UpdateFile? {
            guard let entry = files[key] as? [String: Any],
                  let name = entry["name"] as? String,
                  let urlString = entry["url"] as? String,
                  let url = URL(string: urlString),
                  let sha = entry["sha256"] as? String,
                  let size = (entry["size"] as? NSNumber)?.int64Value else { return nil }
            guard UpdateVerifier.isTrustedDownload(url: url, name: name, size: size, sha256: sha) else { return nil }
            return UpdateFile(name: name, url: url, sha256: sha.lowercased(), size: size)
        }

        let info = UpdateInfo(
            version: version,
            build: build,
            channel: (json["channel"] as? String) ?? "stable",
            commit: (json["commit"] as? String) ?? "",
            minOS: (json["minOS"] as? String) ?? "12.0",
            date: (json["date"] as? String) ?? "",
            notes: (json["notes"] as? String) ?? "",
            signed: signed,
            deb: parseFile("deb"),
            ipa: parseFile("ipa")
        )

        // Chỉ chấp nhận build cao hơn bản đang chạy (chống hạ cấp / phát lại bản cũ).
        if info.build <= AppInfo.build { return .upToDate }
        if !versionAtLeast(AppInfo.osVersion, info.minOS) {
            return .failed(Lf("Bản mới cần iOS %@ trở lên", info.minOS))
        }
        if info.deb == nil && info.ipa == nil {
            return .failed(L("Bản mới không có tệp cài đặt hợp lệ"))
        }
        return .available(info)
    }

    private func finish(_ result: UpdateResult, _ completion: ((UpdateResult) -> Void)?) {
        isChecking = false
        let now = Date()
        lastCheck = now
        UserDefaults.standard.set(now, forKey: "update.lastCheck")
        switch result {
        case .available(let info):
            available = info
            lastMessage = Lf("Có bản mới %@ (build %@)", info.version, info.build)
        case .upToDate:
            available = nil
            lastMessage = L("Bạn đang dùng bản mới nhất")
        case .failed(let message):
            lastMessage = Lf("Không kiểm tra được: %@", message)
        }
        postState()
        completion?(result)
        if recheckRequested {
            recheckRequested = false
            check(manual: true)
        }
    }

    private func postState() {
        NotificationCenter.default.post(name: .updateStateChanged, object: nil)
    }

    // MARK: - Tải về

    func download(_ file: UpdateFile,
                  progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, UpdateError>) -> Void) {
        guard downloadTask == nil else {
            completion(.failure(UpdateError(L("Đang có một lần tải khác"))))
            return
        }
        guard UpdateVerifier.isTrustedDownload(url: file.url, name: file.name, size: file.size, sha256: file.sha256) else {
            completion(.failure(UpdateError(L("Liên kết tải không nằm trong repo cập nhật chính thức"))))
            return
        }
        activeFile = file
        progressHandler = progress
        completionHandler = completion
        abortReason = nil
        var request = URLRequest(url: file.url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let task = downloadSession.downloadTask(with: request)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    private func finishDownload(_ result: Result<URL, UpdateError>) {
        let handler = completionHandler
        completionHandler = nil
        progressHandler = nil
        activeFile = nil
        downloadTask = nil
        abortReason = nil
        handler?(result)
    }

    // MARK: - URLSession delegate

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, UpdateVerifier.isAllowedHost(url) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let file = activeFile else { return }
        if totalBytesWritten > file.size + 4096 || totalBytesWritten > UpdateConfig.maxDownloadBytes {
            abortReason = L("Tệp tải về lớn hơn khai báo, đã dừng")
            downloadTask.cancel()
            return
        }
        let total = file.size > 0 ? file.size : totalBytesExpectedToWrite
        if total > 0 {
            progressHandler?(min(1.0, Double(totalBytesWritten) / Double(total)))
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let file = activeFile else { return }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finishDownload(.failure(UpdateError(Lf("Máy chủ trả về HTTP %@", http.statusCode))))
            return
        }
        if let problem = UpdateVerifier.verifyFile(at: location, expectedSize: file.size, expectedSHA256: file.sha256) {
            finishDownload(.failure(problem))
            return
        }
        do {
            let manager = FileManager.default
            let directory = Updater.updatesDirectory
            try? manager.removeItem(at: directory)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let destination = directory.appendingPathComponent(file.name)
            try manager.moveItem(at: location, to: destination)
            finishDownload(.success(destination))
        } catch {
            finishDownload(.failure(UpdateError(Lf("Không lưu được tệp: %@", error.localizedDescription))))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error, completionHandler != nil else { return }
        let code = (error as NSError).code
        if let reason = abortReason {
            finishDownload(.failure(UpdateError(reason)))
        } else if code == NSURLErrorCancelled {
            finishDownload(.failure(UpdateError(L("Đã huỷ"), cancelled: true)))
        } else {
            finishDownload(.failure(UpdateError(error.localizedDescription)))
        }
    }
}
