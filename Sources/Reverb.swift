import Foundation
import AVFoundation
import MediaToolbox
import UIKit

extension Notification.Name {
    static let reverbChanged = Notification.Name("MochyiOSReverbChanged")
}

/// Kiểu phòng vang.
enum ReverbPreset: Int, CaseIterable {
    case small = 0, hall, cathedral
    var title: String {
        switch self {
        case .small: return L("Phòng nhỏ")
        case .hall: return L("Hội trường")
        case .cathedral: return L("Nhà thờ")
        }
    }
    /// Kích thước phòng (độ dài đuôi vang) và độ hút cao tần.
    var room: Float {
        switch self {
        case .small: return 0.45
        case .hall: return 0.75
        case .cathedral: return 0.93
        }
    }
    var damping: Float {
        switch self {
        case .small: return 0.55
        case .hall: return 0.40
        case .cathedral: return 0.25
        }
    }
}

/// Cài đặt reverb (lưu UserDefaults). Bộ xử lý âm thanh đọc trực tiếp các giá trị này nên chỉnh thanh là nghe thay đổi ngay.
enum ReverbSettings {
    private static let defaults = UserDefaults.standard

    static var enabled: Bool {
        get { return defaults.bool(forKey: "reverb.enabled") }
        set { defaults.set(newValue, forKey: "reverb.enabled"); sync(); NotificationCenter.default.post(name: .reverbChanged, object: nil) }
    }
    /// Độ vang 0...1.
    static var amount: Float {
        get { return defaults.object(forKey: "reverb.amount") == nil ? 0.35 : defaults.float(forKey: "reverb.amount") }
        set { defaults.set(min(1, max(0, newValue)), forKey: "reverb.amount"); sync() }
    }
    static var preset: ReverbPreset {
        get { return ReverbPreset(rawValue: defaults.integer(forKey: "reverb.preset")) ?? .hall }
        set { defaults.set(newValue.rawValue, forKey: "reverb.preset"); sync() }
    }

    /// Đẩy giá trị sang vùng nhớ mà luồng âm thanh đọc.
    static func sync() {
        ReverbParams.shared.wet = amount
        ReverbParams.shared.room = preset.room
        ReverbParams.shared.damping = preset.damping
    }
}

/// Tham số dùng chung giữa giao diện và luồng âm thanh (đọc/ghi số đơn giản, lệch một nhịp cũng không sao).
final class ReverbParams {
    static let shared = ReverbParams()
    var wet: Float = 0.35
    var room: Float = 0.75
    var damping: Float = 0.4
    /// Trạng thái hiển thị cho người dùng (để biết reverb có đang chạy trên bài này không).
    var status: String = L("Chưa gắn vào bài nào")
    var frames: Int = 0
}

/// Reverb kiểu Freeverb (Schroeder/Moorer): 8 bộ lọc lược song song + 4 bộ lọc thông-tất qua mỗi kênh.
final class ReverbDSP {
    private let combTunings: [Int] = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private let allpassTunings: [Int] = [556, 441, 341, 225]
    private let stereoSpread = 23

    private struct FilterState {
        var buf: UnsafeMutablePointer<Float>
        var size: Int
        var index: Int
        var store: Float
    }

    private var combsL: UnsafeMutablePointer<FilterState>?
    private var combsR: UnsafeMutablePointer<FilterState>?
    private var allpassL: UnsafeMutablePointer<FilterState>?
    private var allpassR: UnsafeMutablePointer<FilterState>?
    private(set) var ready = false
    private var interleaved = false
    private var channels = 2

    private func makeBank(_ tunings: [Int], extra: Int, scale: Double) -> UnsafeMutablePointer<FilterState> {
        let bank = UnsafeMutablePointer<FilterState>.allocate(capacity: tunings.count)
        for (i, t) in tunings.enumerated() {
            let size = max(1, Int(Double(t + extra) * scale))
            let buf = UnsafeMutablePointer<Float>.allocate(capacity: size)
            buf.initialize(repeating: 0, count: size)
            (bank + i).initialize(to: FilterState(buf: buf, size: size, index: 0, store: 0))
        }
        return bank
    }

    private func freeBank(_ bank: UnsafeMutablePointer<FilterState>?, count: Int) {
        guard let bank = bank else { return }
        for i in 0..<count { bank[i].buf.deallocate() }
        bank.deallocate()
    }

    private func freeAll() {
        freeBank(combsL, count: combTunings.count); combsL = nil
        freeBank(combsR, count: combTunings.count); combsR = nil
        freeBank(allpassL, count: allpassTunings.count); allpassL = nil
        freeBank(allpassR, count: allpassTunings.count); allpassR = nil
    }

    deinit { freeAll() }

    /// Gọi khi biết định dạng âm thanh. Chỉ hỗ trợ Float32 (định dạng thường gặp trên iOS); khác thì bỏ qua (nghe như cũ).
    func prepare(_ asbd: AudioStreamBasicDescription) {
        freeAll()
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && asbd.mBitsPerChannel == 32
        guard isFloat, asbd.mSampleRate > 8000 else {
            ready = false
            ReverbParams.shared.status = Lf("Không áp dụng được: định dạng âm thanh %@-bit không hỗ trợ", asbd.mBitsPerChannel)
            return
        }
        let scale = asbd.mSampleRate / 44100.0
        combsL = makeBank(combTunings, extra: 0, scale: scale)
        combsR = makeBank(combTunings, extra: stereoSpread, scale: scale)
        allpassL = makeBank(allpassTunings, extra: 0, scale: scale)
        allpassR = makeBank(allpassTunings, extra: stereoSpread, scale: scale)
        interleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        channels = Int(asbd.mChannelsPerFrame)
        ready = channels >= 1 && channels <= 2
        ReverbParams.shared.status = ready ? Lf("Đang hoạt động (%@ Hz, %@ kênh)", Int(asbd.mSampleRate), channels) : Lf("Không áp dụng được: %@ kênh", channels)
    }

    @inline(__always)
    private func run(_ input: Float, combs: UnsafeMutablePointer<FilterState>, allpass: UnsafeMutablePointer<FilterState>,
                     feedback: Float, damp: Float) -> Float {
        var out: Float = 0
        for k in 0..<8 {
            let v = combs[k].buf[combs[k].index]
            combs[k].store = v * (1 - damp) + combs[k].store * damp
            combs[k].buf[combs[k].index] = input + combs[k].store * feedback
            combs[k].index += 1
            if combs[k].index >= combs[k].size { combs[k].index = 0 }
            out += v
        }
        for k in 0..<4 {
            let bufout = allpass[k].buf[allpass[k].index]
            let v = out
            allpass[k].buf[allpass[k].index] = v + bufout * 0.5
            out = bufout - v
            allpass[k].index += 1
            if allpass[k].index >= allpass[k].size { allpass[k].index = 0 }
        }
        return out
    }

    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard ready, frames > 0, let cL = combsL, let cR = combsR, let aL = allpassL, let aR = allpassR else { return }
        let params = ReverbParams.shared
        params.frames += frames
        let wet = params.wet
        if wet < 0.005 { return }
        let feedback = params.room * 0.28 + 0.7
        let damp = params.damping * 0.4
        let dryGain: Float = 1 - 0.45 * wet
        let wetGain: Float = wet * 2.6
        let buffers = UnsafeMutableAudioBufferListPointer(list)

        if interleaved {
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return }
            let step = max(1, Int(first.mNumberChannels))
            for i in 0..<frames {
                let l = data[i * step]
                let r = step > 1 ? data[i * step + 1] : l
                let input = (l + r) * 0.015
                let wl = run(input, combs: cL, allpass: aL, feedback: feedback, damp: damp)
                let wr = step > 1 ? run(input, combs: cR, allpass: aR, feedback: feedback, damp: damp) : wl
                data[i * step] = clamp(l * dryGain + wl * wetGain)
                if step > 1 { data[i * step + 1] = clamp(r * dryGain + wr * wetGain) }
            }
        } else {
            guard buffers.count >= 1, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            let right: UnsafeMutablePointer<Float>? = buffers.count >= 2 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            for i in 0..<frames {
                let l = left[i]
                let r = right?[i] ?? l
                let input = (l + r) * 0.015
                let wl = run(input, combs: cL, allpass: aL, feedback: feedback, damp: damp)
                left[i] = clamp(l * dryGain + wl * wetGain)
                if let right = right {
                    let wr = run(input, combs: cR, allpass: aR, feedback: feedback, damp: damp)
                    right[i] = clamp(r * dryGain + wr * wetGain)
                }
            }
        }
    }

    @inline(__always)
    private func clamp(_ x: Float) -> Float { return max(-1, min(1, x)) }
}

// MARK: - Gắn vào luồng phát (MTAudioProcessingTap)

private let reverbTapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

private let reverbTapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<ReverbDSP>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let reverbTapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    let dsp = Unmanaged<ReverbDSP>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    dsp.prepare(format.pointee)
}

private let reverbTapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

private let reverbTapProcess: MTAudioProcessingTapProcessCallback = { tap, frames, _, bufferList, framesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut)
    guard status == noErr else { return }
    let dsp = Unmanaged<ReverbDSP>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    dsp.process(bufferList, frames: Int(framesOut.pointee))
}

enum ReverbTap {
    /// Tạo audioMix có gắn bộ reverb cho đoạn âm thanh của bài; nil nếu không gắn được (khi đó nghe như cũ).
    static func makeMix(for track: AVAssetTrack) -> AVAudioMix? {
        ReverbSettings.sync()
        let dsp = ReverbDSP()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(dsp).toOpaque(),
            init: reverbTapInit,
            finalize: reverbTapFinalize,
            prepare: reverbTapPrepare,
            unprepare: reverbTapUnprepare,
            process: reverbTapProcess)
        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tapRef)
        guard status == noErr, let tap = tapRef else {
            Unmanaged.passUnretained(dsp).release()
            ReverbParams.shared.status = Lf("Không tạo được bộ lọc (mã %@)", status)
            return nil
        }
        ReverbParams.shared.status = L("Đã gắn, đang chờ âm thanh…")
        ReverbParams.shared.frames = 0
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }
}

// MARK: - Bảng chỉnh reverb

/// Thẻ nổi ở đáy màn hình: công tắc, thanh độ vang và kiểu phòng.
final class ReverbPanelViewController: UIViewController, UIGestureRecognizerDelegate {
    private let statusLabel = UILabel()
    private var statusTimer: Timer?
    private let card = UIView()
    private let toggle = M3Switch()
    private let slider = UISlider()
    private let valueLabel = UILabel()
    private let presetControl = M3Segmented(items: ReverbPreset.allCases.map { $0.title }, selected: ReverbSettings.preset.rawValue)

    static func present(from presenter: UIViewController) {
        let vc = ReverbPanelViewController()
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        presenter.present(vc, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(close))
        dismissTap.delegate = self
        view.addGestureRecognizer(dismissTap)

        card.backgroundColor = Theme.isDark ? UIColor(white: 0.14, alpha: 1) : UIColor(white: 0.97, alpha: 1)
        card.layer.cornerRadius = 28
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let title = UILabel()
        title.text = "Reverb"
        title.font = Theme.heavy(22)
        title.textColor = Theme.primaryText
        toggle.isOn = ReverbSettings.enabled
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        let titleRow = UIStackView(arrangedSubviews: [title, UIView(), toggle])
        titleRow.alignment = .center

        let amountTitle = UILabel()
        amountTitle.text = L("Độ vang")
        amountTitle.font = Theme.bold(15)
        amountTitle.textColor = Theme.primaryText
        valueLabel.font = Theme.regular(15)
        valueLabel.textColor = Theme.secondaryText
        let amountRow = UIStackView(arrangedSubviews: [amountTitle, UIView(), valueLabel])

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = ReverbSettings.amount
        slider.minimumTrackTintColor = Theme.accent
        slider.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)

        let roomTitle = UILabel()
        roomTitle.text = L("Kiểu phòng")
        roomTitle.font = Theme.bold(15)
        roomTitle.textColor = Theme.primaryText
        presetControl.addTarget(self, action: #selector(presetChanged), for: .valueChanged)
        let presetHolder = UIView()
        presetControl.translatesAutoresizingMaskIntoConstraints = false
        presetHolder.addSubview(presetControl)
        NSLayoutConstraint.activate([
            presetControl.leadingAnchor.constraint(equalTo: presetHolder.leadingAnchor),
            presetControl.topAnchor.constraint(equalTo: presetHolder.topAnchor),
            presetControl.bottomAnchor.constraint(equalTo: presetHolder.bottomAnchor),
            presetControl.widthAnchor.constraint(equalToConstant: max(260, presetControl.bounds.width)),
            presetControl.heightAnchor.constraint(equalToConstant: 32)
        ])

        let note = UILabel()
        note.text = L("Reverb áp dụng ngay cho bài đang phát; tắt đi thì phát nguyên bản.")
        note.font = Theme.regular(12)
        note.textColor = Theme.secondaryText
        note.numberOfLines = 0

        statusLabel.font = Theme.regular(12)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleRow, amountRow, slider, roomTitle, presetHolder, statusLabel, note])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22)
        ])
        updateValueLabel()
        updateEnabledLook()
        updateStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateStatus() }
    }

    deinit { statusTimer?.invalidate() }

    /// Chỉ chạm ra ngoài thẻ mới đóng; chạm trong thẻ để các điều khiển tự xử lý.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return !card.frame.contains(touch.location(in: view))
    }

    private func updateStatus() {
        if !ReverbSettings.enabled { statusLabel.text = L("Đang tắt"); return }
        let p = ReverbParams.shared
        statusLabel.text = p.status + (p.frames > 0 ? Lf(" · đã xử lý %@k mẫu", p.frames / 1000) : "")
    }

    private func updateValueLabel() { valueLabel.text = "\(Int(round(slider.value * 100)))%" }

    private func updateEnabledLook() {
        let on = ReverbSettings.enabled
        slider.alpha = on ? 1 : 0.4
        presetControl.alpha = on ? 1 : 0.4
        slider.isUserInteractionEnabled = on
        presetControl.isUserInteractionEnabled = on
    }

    @objc private func toggled() {
        ReverbSettings.enabled = toggle.isOn
        updateEnabledLook()
        updateStatus()
    }

    @objc private func sliderMoved() {
        ReverbSettings.amount = slider.value
        updateValueLabel()
    }

    @objc private func presetChanged() {
        ReverbSettings.preset = ReverbPreset(rawValue: presetControl.selectedSegmentIndex) ?? .hall
    }

    @objc private func close() {
        dismiss(animated: true) { NotificationCenter.default.post(name: .reverbChanged, object: nil) }
    }
}
