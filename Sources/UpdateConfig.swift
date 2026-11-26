import Foundation
import Security
import CommonCrypto

/// Mọi thứ liên quan tới nơi lấy bản cập nhật được cố định ở đây.
enum UpdateConfig {
    static let appId = "com.puc.mochyios"
    static let repoPage = "https://github.com/HGPhutJB/Mochy-iOS"
    static let releasesPage = "https://github.com/HGPhutJB/Mochy-iOS/releases"
    /// Bản ổn định: release mới nhất (không tính bản thử nghiệm).
    static let stableManifest = "https://github.com/HGPhutJB/Mochy-iOS/releases/latest/download/update.json"
    /// Kênh nhà phát triển: release thử nghiệm cố định tên "dev", được ghi đè sau mỗi lần build.
    static let devManifest = "https://github.com/HGPhutJB/Mochy-iOS/releases/download/dev/update.json"
    /// Tệp tải về chỉ được nằm dưới đường dẫn này của github.com.
    static let downloadPathPrefix = "/HGPhutJB/Mochy-iOS/releases/download/"
    /// Khoá công khai ECDSA P-256 (điểm X9.63 65 byte, base64) để kiểm tra chữ ký update.json.
    static let publicKeyBase64 = "BAIlKg5FHx7m1huTuOUWpFewsZUz9ZMje1E0kt3+O0MVsl+GCiBCLnXG6iZK+0tUCXjs9XA49f5VeNTorRvS0bs="
    static let maxDownloadBytes: Int64 = 80 * 1024 * 1024
    static let maxManifestBytes = 256 * 1024
    static let checkInterval: TimeInterval = 6 * 3600
}

/// Các bước kiểm tra an toàn cho bản cập nhật.
enum UpdateVerifier {
    /// Host được phép (kể cả khi GitHub chuyển hướng tới CDN).
    static func isAllowedHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "githubusercontent.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// Kiểm tra chữ ký ECDSA P-256 / SHA-256 của update.json bằng khoá công khai gắn sẵn trong app.
    static func verifySignature(data: Data, signature: Data) -> Bool {
        guard let keyData = Data(base64Encoded: UpdateConfig.publicKeyBase64) else { return false }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256
        ]
        var keyError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &keyError) else {
            return false
        }
        var verifyError: Unmanaged<CFError>?
        return SecKeyVerifySignature(key, .ecdsaSignatureMessageX962SHA256,
                                     data as CFData, signature as CFData, &verifyError)
    }

    /// Link tải trong manifest phải là github.com, đúng repo, đúng tên tệp, đuôi .deb/.ipa.
    static func isTrustedDownload(url: URL, name: String, size: Int64, sha256: String) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com" else { return false }
        guard url.path.lowercased().hasPrefix(UpdateConfig.downloadPathPrefix.lowercased()) else { return false }
        guard url.lastPathComponent == name else { return false }
        guard size > 0 && size <= UpdateConfig.maxDownloadBytes else { return false }
        guard sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { return false }
        guard name.range(of: "^[A-Za-z0-9._-]{1,100}$", options: .regularExpression) != nil else { return false }
        let lower = name.lowercased()
        return lower.hasSuffix(".deb") || lower.hasSuffix(".ipa")
    }

    static func sha256Hex(ofFileAt url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            CC_SHA256_Update(&context, buffer, CC_LONG(count))
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Trả về lỗi nếu kích thước hoặc SHA-256 của tệp đã tải không khớp manifest.
    static func verifyFile(at url: URL, expectedSize: Int64, expectedSHA256: String) -> UpdateError? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        if size != expectedSize {
            return UpdateError(Lf("Kích thước tệp không khớp (nhận %@, cần %@)", size, expectedSize))
        }
        guard let actual = sha256Hex(ofFileAt: url) else {
            return UpdateError(L("Không tính được SHA-256 của tệp đã tải"))
        }
        if actual != expectedSHA256.lowercased() {
            return UpdateError(L("SHA-256 không khớp, tệp có thể đã bị sửa. Không cài đặt."))
        }
        return nil
    }
}
