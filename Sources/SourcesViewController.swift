import UIKit

/// Khoá cho các nguồn nâng cao: cookie sp_dc của Spotify (video Canvas) và API key Spicy Lyrics.
final class SourcesViewController: UIViewController {
    private let spdc = UITextField()
    private let spicy = UITextField()
    private let note = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Nguồn nâng cao"
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        for (f, p) in [(spdc, "Cookie sp_dc của Spotify"), (spicy, "API key Spicy Lyrics (sl_sk_… / sl_pk_…)")] {
            f.placeholder = p
            f.font = Theme.regular(15)
            f.textColor = Theme.primaryText
            f.backgroundColor = Theme.card
            f.layer.cornerRadius = 10
            f.autocapitalizationType = .none
            f.autocorrectionType = .no
            f.clearButtonMode = .whileEditing
            f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 10))
            f.leftViewMode = .always
            f.heightAnchor.constraint(equalToConstant: 46).isActive = true
        }
        spdc.text = SpotifyCanvas.cookie
        spicy.text = UserDefaults.standard.string(forKey: "spicy.key")
        note.numberOfLines = 0
        note.font = Theme.regular(13)
        note.textColor = Theme.secondaryText
        note.text = """
        • sp_dc: đăng nhập open.spotify.com trên trình duyệt, mở công cụ nhà phát triển ▸ Cookies, sao chép giá trị sp_dc. Dùng để lấy video Canvas của bài hát; bài không có Canvas thì app dùng MV YouTube, không có nữa thì hiện ảnh bìa. Đây là API không chính thức của Spotify, có thể ngừng hoạt động hoặc vi phạm điều khoản của họ, hãy cân nhắc. Cookie chỉ lưu trên máy này.
        • Spicy Lyrics: tạo ứng dụng tại developers.spicylyrics.org rồi dán key vào đây; bật "Allow requests with no Origin header" nếu dùng key client.
        • Các nguồn còn lại (BiniLyrics, Musixmatch, Unison, NetEase, LRCLIB, QQ Music, KuGou, Genius, YouLy+, SimpMusic) không cần khoá.
        """
        let save = UIButton(type: .system)
        save.setTitle("Lưu", for: .normal)
        save.titleLabel?.font = Theme.bold(17)
        save.setTitleColor(.white, for: .normal)
        save.backgroundColor = Theme.accent
        save.layer.cornerRadius = 12
        save.heightAnchor.constraint(equalToConstant: 48).isActive = true
        save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [spdc, spicy, save, note])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:))))
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        SpotifyCanvas.cookie = spdc.text ?? ""
        UserDefaults.standard.set((spicy.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spicy.key")
        Toast.show("Đã lưu")
    }
}
