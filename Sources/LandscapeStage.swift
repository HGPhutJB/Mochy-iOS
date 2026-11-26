import UIKit

/// Bố cục xoay ngang của màn hình đang phát: bên trái bìa + tên bài + tiến trình + điều khiển, bên phải là lời (do NowPlaying đặt).
final class LandscapeStage: UIView {
    let cover = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    let progress = ProgressBar()
    private let elapsed = UILabel()
    private let remaining = UILabel()
    let prev = UIButton(type: .custom)
    let play = UIButton(type: .custom)
    let next = UIButton(type: .custom)
    let close = UIButton(type: .custom)
    let translate = UIButton(type: .custom)
    let reverb = UIButton(type: .custom)
    let queue = UIButton(type: .custom)
    let more = UIButton(type: .custom)
    /// Các nút tự ẩn khi không chạm; bìa và tên bài luôn hiện.
    private var controls: [UIView] { return [progress, elapsed, remaining, prev, play, next, close, translate, reverb, queue, more] }

    var onScrub: ((Double, Bool) -> Void)?
    private(set) var controlsVisible = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 14
        cover.backgroundColor = UIColor(white: 0.15, alpha: 1)
        cover.layer.shadowColor = UIColor.black.cgColor
        titleLabel.font = RoundedFont.font(21, index: 6)
        titleLabel.textColor = .white
        artistLabel.font = RoundedFont.font(16, index: 4)
        artistLabel.textColor = UIColor(white: 1, alpha: 0.65)
        for l in [elapsed, remaining] {
            l.font = RoundedFont.font(12, index: 5)
            l.textColor = UIColor(white: 1, alpha: 0.7)
        }
        elapsed.text = "0:00"
        remaining.text = "-:--"
        remaining.textAlignment = .right
        progress.onScrub = { [weak self] v, ended in self?.onScrub?(v, ended) }
        prev.setImage(Icons.previous(40), for: .normal)
        next.setImage(Icons.next(40), for: .normal)
        play.setImage(Icons.pause(52), for: .normal)
        close.setImage(Icons.chevronDown(24), for: .normal)
        translate.setImage(InfoRow.translateImage(on: TranslateSettings.enabled), for: .normal)
        reverb.setImage(Icons.reverb(24), for: .normal)
        queue.setImage(Icons.queue(24), for: .normal)
        more.setImage(Icons.more(24), for: .normal)
        for b in [prev, play, next, close, translate, reverb, queue, more] { b.tintColor = .white }
        [cover, titleLabel, artistLabel].forEach { addSubview($0) }
        controls.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) chưa được hỗ trợ") }

    /// Chỉ nhận chạm ở các nút/thanh; vùng trống để lời phía sau cuộn được.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self || hit === cover || hit === titleLabel || hit === artistLabel { return nil }
        if !controlsVisible, hit != nil { return nil }
        return hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safe = safeAreaInsets
        let w = bounds.width, h = bounds.height
        let panel = w * 0.47
        let pad = max(safe.left, 20) + 20
        let inner = max(120, panel - pad - 24)
        // Chiều cao khối: bìa + 18 + tên/nghệ sĩ 50 + 12 + tiến trình 30 + thời gian 16 + 8 + điều khiển 60
        let rest: CGFloat = 18 + 50 + 12 + 30 + 16 + 8 + 60
        let s = max(90, min(inner, h - rest - safe.top - safe.bottom - 70))
        let total = s + rest
        var y = max(safe.top + 40, (h - total) / 2)
        let x = pad + (inner - s) / 2
        cover.frame = CGRect(x: x, y: y, width: s, height: s)
        cover.layer.shadowOpacity = 0.4
        cover.layer.shadowRadius = 22
        cover.layer.shadowOffset = CGSize(width: 0, height: 10)
        cover.layer.masksToBounds = false
        cover.clipsToBounds = true
        y += s + 18
        titleLabel.frame = CGRect(x: x, y: y, width: s, height: 26)
        artistLabel.frame = CGRect(x: x, y: y + 26, width: s, height: 22)
        y += 62
        progress.frame = CGRect(x: x, y: y, width: s, height: 30)
        y += 30
        elapsed.frame = CGRect(x: x, y: y, width: s / 2, height: 16)
        remaining.frame = CGRect(x: x + s / 2, y: y, width: s / 2, height: 16)
        y += 24
        let cy = y + 30
        play.frame = CGRect(x: 0, y: 0, width: 64, height: 64); play.center = CGPoint(x: x + s / 2, y: cy)
        prev.frame = CGRect(x: 0, y: 0, width: 56, height: 56); prev.center = CGPoint(x: x + s / 2 - 84, y: cy)
        next.frame = CGRect(x: 0, y: 0, width: 56, height: 56); next.center = CGPoint(x: x + s / 2 + 84, y: cy)

        close.frame = CGRect(x: max(safe.left, 12) + 8, y: max(safe.top, 8) + 8, width: 44, height: 44)
        var rx = w - max(safe.right, 12) - 8
        for b in [more, queue, reverb, translate] {
            rx -= 44
            b.frame = CGRect(x: rx, y: max(safe.top, 8) + 8, width: 44, height: 44)
            rx -= 4
        }
    }

    func set(title: String, artist: String, image: UIImage?) {
        titleLabel.text = title
        artistLabel.text = artist
        if let image = image, cover.image !== image {
            UIView.transition(with: cover, duration: 0.4, options: .transitionCrossDissolve, animations: { self.cover.image = image }, completion: nil)
        }
    }

    func setTime(fraction: Double, elapsedText: String, remainingText: String) {
        if !progress.isDragging { progress.value = fraction }
        elapsed.text = elapsedText
        remaining.text = remainingText
    }

    func setPlaying(_ playing: Bool) {
        play.setImage(playing ? Icons.pause(52) : Icons.play(52), for: .normal)
    }

    func setControls(visible: Bool, animated: Bool) {
        controlsVisible = visible
        let apply = { self.controls.forEach { $0.alpha = visible ? 1 : 0 } }
        if animated { UIView.animate(withDuration: 0.35, delay: 0, options: [.allowUserInteraction], animations: apply, completion: nil) } else { apply() }
    }
}
