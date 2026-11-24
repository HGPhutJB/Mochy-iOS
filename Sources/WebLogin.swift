import UIKit
import WebKit

/// Trang đăng nhập thật của dịch vụ nhạc (trong app). Khi thấy cookie đăng nhập thì tự đóng và trả cookie về,
/// Mochy dùng cookie đó để đọc thư viện của tài khoản. Cookie chỉ lưu trong Keychain trên máy này.
final class WebLoginViewController: UIViewController, WKNavigationDelegate {
    private let service: MusicService
    private let startURL: URL
    private let required: [String]
    private let domains: [String]
    private var completion: ((String?, [String: String]) -> Void)?
    private let webView: WKWebView
    private var timer: Timer?
    private var finished = false

    /// - Parameters:
    ///   - required: tên cookie cần có để coi là đã đăng nhập.
    ///   - domains: chỉ lấy cookie có miền chứa một trong các chuỗi này.
    init(service: MusicService, startURL: URL, required: [String], domains: [String],
         completion: @escaping (String?, [String: String]) -> Void) {
        self.service = service
        self.startURL = startURL
        self.required = required
        self.domains = domains
        self.completion = completion
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Hiện trang đăng nhập; `completion` nhận (chuỗi Cookie, từng cookie) hoặc nil nếu người dùng đóng.
    static func present(from presenter: UIViewController, service: MusicService, startURL: URL, required: [String],
                        domains: [String], completion: @escaping (String?, [String: String]) -> Void) {
        let vc = WebLoginViewController(service: service, startURL: startURL, required: required, domains: domains, completion: completion)
        let nav = UINavigationController(rootViewController: vc)
        Theme.style(navigationBar: nav.navigationBar)
        nav.navigationBar.setBackgroundImage(nil, for: .default)
        nav.navigationBar.barTintColor = Theme.background
        nav.modalPresentationStyle = .fullScreen
        var top = presenter
        while let next = top.presentedViewController { top = next }
        top.present(nav, animated: true, completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Đăng nhập \(service.title)"
        view.backgroundColor = Theme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Huỷ", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Xong", style: .done, target: self, action: #selector(doneTapped))
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)
        webView.load(URLRequest(url: startURL))
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
    }

    deinit { timer?.invalidate() }

    @objc private func cancel() {
        finish(nil, [:])
    }

    @objc private func doneTapped() {
        readCookies { [weak self] header, jar in
            guard let self = self else { return }
            if self.required.allSatisfy({ jar[$0] != nil }) {
                self.finish(header, jar)
            } else {
                let alert = UIAlertController(title: "Chưa thấy đăng nhập",
                                              message: "Hãy đăng nhập xong trong trang này (nếu đã đăng nhập thì mở trang chủ của \(self.service.title) một lần) rồi bấm Xong lại.",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Đóng", style: .cancel, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }

    @objc private func poll() {
        guard !finished else { return }
        readCookies { [weak self] header, jar in
            guard let self = self, !self.finished else { return }
            if self.required.allSatisfy({ jar[$0] != nil }) { self.finish(header, jar) }
        }
    }

    private func readCookies(_ done: @escaping (String, [String: String]) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var jar: [String: String] = [:]
            var parts: [String] = []
            for c in cookies where self.domains.contains(where: { c.domain.contains($0) }) {
                jar[c.name] = c.value
                parts.append("\(c.name)=\(c.value)")
            }
            DispatchQueue.main.async { done(parts.joined(separator: "; "), jar) }
        }
    }

    private func finish(_ header: String?, _ jar: [String: String]) {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        let block = completion
        completion = nil
        dismiss(animated: true) { block?(header, jar) }
    }
}
