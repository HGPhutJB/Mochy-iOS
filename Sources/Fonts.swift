import UIKit

/// Font SF Pro Rounded đóng kèm app (đã cắt còn chữ Latin + tiếng Việt). Bảy mức đậm từ Light đến Black;
/// nếu font chưa nạp được thì dùng font hệ thống cùng độ đậm.
enum RoundedFont {
    static let names = ["SFProRounded-Light", "SFProRounded-Regular", "SFProRounded-Medium", "SFProRounded-Semibold",
                        "SFProRounded-Bold", "SFProRounded-Heavy", "SFProRounded-Black"]
    static let weights: [UIFont.Weight] = [.light, .regular, .medium, .semibold, .bold, .heavy, .black]
    static let titles = [L("Rất nhạt"), L("Nhạt"), L("Vừa"), L("Hơi đậm"), L("Đậm"), L("Rất đậm"), L("Đậm nhất")]
    static let defaultLyricIndex = 6   // mặc định chọn mức đậm nhất

    static func font(_ size: CGFloat, index: Int) -> UIFont {
        let i = min(max(index, 0), names.count - 1)
        return UIFont(name: names[i], size: size) ?? UIFont.systemFont(ofSize: size, weight: weights[i])
    }
}
