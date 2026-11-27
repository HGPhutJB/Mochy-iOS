import UIKit

/// Bố cục xoay ngang của màn hình đang phát: bên trái bìa + tên bài + tiến trình + điều khiển, bên phải là lời (do NowPlaying đặt).
final class LandscapeStage: UIView {
    let cover = UIImageView()
    private let coverShadow = UIView()   // bóng đặt ở lớp riêng: lớp bìa cần cắt bo góc nên không thể vừa đổ bóng vừa cắt
    private let titleLabel = MarqueeLabel()
    private let artistLabel = UILabel()
    let progress = ProgressBar()
    private let elapsed = UILabel()
    private let remaining = UILabel()
    let prevBtn = ControlButton(type: .custom)
    let playBtn = ControlButton(type: .custom)
    let nextBtn = ControlButton(type: .custom)
    let close = ControlButton(type: .custom)
    let translate = ControlButton(type: .custom)
    let reverb = ControlButton(type: .custom)
    let queue = ControlButton(type: .custom)
    let more = ControlButton(type: .custom)
    /// Các nút tự ẩn khi không chạm; bìa và tên bài luôn hiện.
    private var controls: [UIView] { return [progress, elapsed, remaining, prevBtn, playBtn, nextBtn, close, translate, reverb, queue, more] }

    var onScrub: ((Double, Bool) -> Void)?
    private(set) var controlsVisible = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 14
        cover.backgroundColor = UIColor(white: 0.15, alpha: 1)
        coverShadow.backgroundColor = .clear
        coverShadow.layer.shadowColor = UIColor.black.cgColor
        coverShadow.layer.shadowOpacity = 0.4
        coverShadow.layer.shadowRadius = 22
        coverShadow.layer.shadowOffset = CGSize(width: 0, height: 10)
        titleLabel.label.font = RoundedFont.font(21, index: 6)
        titleLabel.label.textColor = .white
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
        prevBtn.setImage(Icons.previous(40), for: .normal)
        nextBtn.setImage(Icons.next(40), for: .normal)
        playBtn.setImage(Icons.pause(52), for: .normal)
        close.setImage(Icons.chevronDown(24), for: .normal)
        translate.setImage(InfoRow.translateImage(on: TranslateSettings.enabled), for: .normal)
        reverb.setImage(Icons.reverb(24), for: .normal)
        queue.setImage(Icons.queue(24), for: .normal)
        more.setImage(Icons.more(24), for: .normal)
        for b in [prevBtn, playBtn, nextBtn, close, translate, reverb, queue, more] { b.tintColor = .white }
        addSubview(coverShadow)
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
        let pad = max(safe.left, 16) + 52               // chừa cột bên trái cho nút đóng
        let inner = max(140, panel - pad - 16)
        let top = max(safe.top, 8) + 8
        let closeBottom = top
        let bottomMargin = max(safe.bottom, 10) + 10
        // Dưới bìa: tên/nghệ sĩ 46 + tiến trình 22 + giờ 14 + điều khiển 56 và các khoảng cách
        let rest: CGFloat = 10 + 46 + 4 + 22 + 14 + 6 + 56
        let s = max(80, min(inner, h - closeBottom - bottomMargin - rest))
        var y = closeBottom
        let x = pad
        cover.frame = CGRect(x: x, y: y, width: s, height: s)
        cover.layer.cornerRadius = 12
        cover.layer.masksToBounds = true
        coverShadow.frame = cover.frame
        coverShadow.layer.shadowPath = UIBezierPath(roundedRect: coverShadow.bounds, cornerRadius: 12).cgPath
        y += s + 10
        let tw = max(s, min(inner, 320))
        titleLabel.frame = CGRect(x: x, y: y, width: tw, height: 26)
        artistLabel.frame = CGRect(x: x, y: y + 24, width: tw, height: 20)
        y += 50
        progress.frame = CGRect(x: x, y: y, width: tw, height: 22)
        y += 22
        elapsed.frame = CGRect(x: x, y: y, width: tw / 2, height: 14)
        remaining.frame = CGRect(x: x + tw / 2, y: y, width: tw / 2, height: 14)
        y += 20
        // Hàng điều khiển: tua lùi – phát/dừng – tua tới, canh đều quanh giữa thanh tiến trình, nút phát lớn hơn.
        let cy = y + 28
        let mid = x + tw / 2
        playBtn.frame = CGRect(x: 0, y: 0, width: 56, height: 56); playBtn.center = CGPoint(x: mid, y: cy)
        prevBtn.frame = CGRect(x: 0, y: 0, width: 52, height: 52); prevBtn.center = CGPoint(x: mid - 78, y: cy)
        nextBtn.frame = CGRect(x: 0, y: 0, width: 52, height: 52); nextBtn.center = CGPoint(x: mid + 78, y: cy)

        close.frame = CGRect(x: max(safe.left, 12) + 2, y: max(safe.top, 8) + 4, width: 44, height: 44)
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
        playBtn.setImageAnimated(playing ? Icons.pause(52) : Icons.play(52))
    }

    func setControls(visible: Bool, animated: Bool) {
        controlsVisible = visible
        let apply = { self.controls.forEach { $0.alpha = visible ? 1 : 0 } }
        if animated { UIView.animate(withDuration: 0.35, delay: 0, options: [.allowUserInteraction], animations: apply, completion: nil) } else { apply() }
    }
}
