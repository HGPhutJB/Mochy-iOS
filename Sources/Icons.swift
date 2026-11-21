import UIKit

/// Icon vẽ bằng code (iOS 12 không có SF Symbols). Trả về ảnh "template" để tô màu bằng tintColor.
enum Icons {
    private static func make(_ size: CGFloat, _ draw: @escaping (CGFloat) -> Void) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { _ in
            UIColor.black.setFill()
            UIColor.black.setStroke()
            draw(size)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private static func line(_ p: UIBezierPath, _ s: CGFloat, _ width: CGFloat = 0.085) {
        p.lineWidth = s * width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    private static func triangle(_ s: CGFloat, x0: CGFloat, x1: CGFloat) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: s * x0, y: s * 0.14))
        p.addLine(to: CGPoint(x: s * x1, y: s * 0.5))
        p.addLine(to: CGPoint(x: s * x0, y: s * 0.86))
        p.close()
        p.fill()
    }

    private static func backTriangle(_ s: CGFloat, x0: CGFloat, x1: CGFloat) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: s * x1, y: s * 0.14))
        p.addLine(to: CGPoint(x: s * x0, y: s * 0.5))
        p.addLine(to: CGPoint(x: s * x1, y: s * 0.86))
        p.close()
        p.fill()
    }

    private static func arrowHead(_ s: CGFloat, at tip: CGPoint, pointingRight: Bool) {
        let d = s * 0.12
        let p = UIBezierPath()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x + (pointingRight ? -d : d), y: tip.y - d))
        p.addLine(to: CGPoint(x: tip.x + (pointingRight ? -d : d), y: tip.y + d))
        p.close()
        p.fill()
    }

    // MARK: - Phát nhạc

    static func play(_ size: CGFloat) -> UIImage {
        return make(size) { s in Icons.triangle(s, x0: 0.22, x1: 0.9) }
    }

    static func pause(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            UIBezierPath(roundedRect: CGRect(x: s * 0.2, y: s * 0.14, width: s * 0.22, height: s * 0.72), cornerRadius: s * 0.04).fill()
            UIBezierPath(roundedRect: CGRect(x: s * 0.58, y: s * 0.14, width: s * 0.22, height: s * 0.72), cornerRadius: s * 0.04).fill()
        }
    }

    static func next(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            Icons.triangle(s, x0: 0.08, x1: 0.56)
            Icons.triangle(s, x0: 0.44, x1: 0.92)
        }
    }

    static func previous(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            Icons.backTriangle(s, x0: 0.08, x1: 0.56)
            Icons.backTriangle(s, x0: 0.44, x1: 0.92)
        }
    }

    static func shuffle(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let a = UIBezierPath()
            a.move(to: CGPoint(x: s * 0.1, y: s * 0.7))
            a.addCurve(to: CGPoint(x: s * 0.78, y: s * 0.3),
                       controlPoint1: CGPoint(x: s * 0.45, y: s * 0.7), controlPoint2: CGPoint(x: s * 0.5, y: s * 0.3))
            Icons.line(a, s)
            let b = UIBezierPath()
            b.move(to: CGPoint(x: s * 0.1, y: s * 0.3))
            b.addCurve(to: CGPoint(x: s * 0.78, y: s * 0.7),
                       controlPoint1: CGPoint(x: s * 0.45, y: s * 0.3), controlPoint2: CGPoint(x: s * 0.5, y: s * 0.7))
            Icons.line(b, s)
            Icons.arrowHead(s, at: CGPoint(x: s * 0.92, y: s * 0.3), pointingRight: true)
            Icons.arrowHead(s, at: CGPoint(x: s * 0.92, y: s * 0.7), pointingRight: true)
        }
    }

    static func repeatAll(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath(roundedRect: CGRect(x: s * 0.12, y: s * 0.27, width: s * 0.76, height: s * 0.46), cornerRadius: s * 0.2)
            Icons.line(p, s)
            Icons.arrowHead(s, at: CGPoint(x: s * 0.62, y: s * 0.27), pointingRight: true)
        }
    }

    static func repeatOne(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath(roundedRect: CGRect(x: s * 0.12, y: s * 0.27, width: s * 0.76, height: s * 0.46), cornerRadius: s * 0.2)
            Icons.line(p, s)
            Icons.arrowHead(s, at: CGPoint(x: s * 0.62, y: s * 0.27), pointingRight: true)
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: s * 0.34, weight: .heavy),
                                                        .foregroundColor: UIColor.black]
            let text = "1" as NSString
            let box = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: s * 0.5 - box.width / 2, y: s * 0.5 - box.height / 2), withAttributes: attrs)
        }
    }

    static func queue(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            for y in [CGFloat(0.28), 0.5, 0.72] {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: s * 0.4, y: s * y))
                p.addLine(to: CGPoint(x: s * 0.9, y: s * y))
                Icons.line(p, s)
                UIBezierPath(ovalIn: CGRect(x: s * 0.1, y: s * y - s * 0.05, width: s * 0.1, height: s * 0.1)).fill()
            }
        }
    }

    static func timer(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let ring = UIBezierPath(ovalIn: CGRect(x: s * 0.12, y: s * 0.12, width: s * 0.76, height: s * 0.76))
            Icons.line(ring, s)
            let hands = UIBezierPath()
            hands.move(to: CGPoint(x: s * 0.5, y: s * 0.28))
            hands.addLine(to: CGPoint(x: s * 0.5, y: s * 0.5))
            hands.addLine(to: CGPoint(x: s * 0.66, y: s * 0.6))
            Icons.line(hands, s)
        }
    }

    // MARK: - Thư viện

    static func heart(_ size: CGFloat, filled: Bool) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: s * 0.5, y: s * 0.86))
            p.addCurve(to: CGPoint(x: s * 0.12, y: s * 0.38),
                       controlPoint1: CGPoint(x: s * 0.2, y: s * 0.66), controlPoint2: CGPoint(x: s * 0.1, y: s * 0.52))
            p.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.28),
                       controlPoint1: CGPoint(x: s * 0.14, y: s * 0.2), controlPoint2: CGPoint(x: s * 0.4, y: s * 0.18))
            p.addCurve(to: CGPoint(x: s * 0.88, y: s * 0.38),
                       controlPoint1: CGPoint(x: s * 0.6, y: s * 0.18), controlPoint2: CGPoint(x: s * 0.86, y: s * 0.2))
            p.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.86),
                       controlPoint1: CGPoint(x: s * 0.9, y: s * 0.52), controlPoint2: CGPoint(x: s * 0.8, y: s * 0.66))
            p.close()
            if filled {
                p.fill()
            } else {
                Icons.line(p, s, 0.075)
            }
        }
    }

    static func plus(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: s * 0.5, y: s * 0.18))
            p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.82))
            p.move(to: CGPoint(x: s * 0.18, y: s * 0.5))
            p.addLine(to: CGPoint(x: s * 0.82, y: s * 0.5))
            Icons.line(p, s, 0.1)
        }
    }

    static func more(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            for x in [CGFloat(0.2), 0.5, 0.8] {
                UIBezierPath(ovalIn: CGRect(x: s * x - s * 0.07, y: s * 0.5 - s * 0.07, width: s * 0.14, height: s * 0.14)).fill()
            }
        }
    }

    static func download(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: s * 0.5, y: s * 0.12))
            p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.62))
            p.move(to: CGPoint(x: s * 0.28, y: s * 0.42))
            p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.64))
            p.addLine(to: CGPoint(x: s * 0.72, y: s * 0.42))
            p.move(to: CGPoint(x: s * 0.2, y: s * 0.84))
            p.addLine(to: CGPoint(x: s * 0.8, y: s * 0.84))
            Icons.line(p, s, 0.09)
        }
    }

    static func check(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: s * 0.2, y: s * 0.52))
            p.addLine(to: CGPoint(x: s * 0.42, y: s * 0.74))
            p.addLine(to: CGPoint(x: s * 0.82, y: s * 0.26))
            Icons.line(p, s, 0.11)
        }
    }

    static func close(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: s * 0.24, y: s * 0.24))
            p.addLine(to: CGPoint(x: s * 0.76, y: s * 0.76))
            p.move(to: CGPoint(x: s * 0.76, y: s * 0.24))
            p.addLine(to: CGPoint(x: s * 0.24, y: s * 0.76))
            Icons.line(p, s, 0.1)
        }
    }

    static func chevronDown(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: s * 0.2, y: s * 0.36))
            p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.66))
            p.addLine(to: CGPoint(x: s * 0.8, y: s * 0.36))
            Icons.line(p, s, 0.1)
        }
    }

    // MARK: - Thanh tab

    static func home(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: s * 0.12, y: s * 0.48))
            p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.14))
            p.addLine(to: CGPoint(x: s * 0.88, y: s * 0.48))
            p.move(to: CGPoint(x: s * 0.24, y: s * 0.4))
            p.addLine(to: CGPoint(x: s * 0.24, y: s * 0.84))
            p.addLine(to: CGPoint(x: s * 0.76, y: s * 0.84))
            p.addLine(to: CGPoint(x: s * 0.76, y: s * 0.4))
            Icons.line(p, s, 0.085)
        }
    }

    static func search(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let ring = UIBezierPath(ovalIn: CGRect(x: s * 0.14, y: s * 0.14, width: s * 0.52, height: s * 0.52))
            Icons.line(ring, s, 0.095)
            let handle = UIBezierPath()
            handle.move(to: CGPoint(x: s * 0.62, y: s * 0.62))
            handle.addLine(to: CGPoint(x: s * 0.86, y: s * 0.86))
            Icons.line(handle, s, 0.11)
        }
    }

    static func library(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let box = UIBezierPath(roundedRect: CGRect(x: s * 0.12, y: s * 0.12, width: s * 0.76, height: s * 0.76), cornerRadius: s * 0.16)
            Icons.line(box, s, 0.08)
            UIBezierPath(ovalIn: CGRect(x: s * 0.31, y: s * 0.54, width: s * 0.17, height: s * 0.14)).fill()
            UIBezierPath(rect: CGRect(x: s * 0.44, y: s * 0.3, width: s * 0.045, height: s * 0.33)).fill()
            let flag = UIBezierPath()
            flag.move(to: CGPoint(x: s * 0.44, y: s * 0.3))
            flag.addLine(to: CGPoint(x: s * 0.69, y: s * 0.26))
            flag.addLine(to: CGPoint(x: s * 0.69, y: s * 0.36))
            flag.addLine(to: CGPoint(x: s * 0.44, y: s * 0.4))
            flag.close()
            flag.fill()
        }
    }

    static func sliders(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            let ys: [CGFloat] = [0.24, 0.5, 0.76]
            let xs: [CGFloat] = [0.68, 0.3, 0.55]
            for i in 0..<3 {
                let bar = CGRect(x: s * 0.1, y: s * ys[i] - s * 0.03, width: s * 0.8, height: s * 0.06)
                UIBezierPath(roundedRect: bar, cornerRadius: s * 0.03).fill()
                let knob = CGRect(x: s * xs[i] - s * 0.12, y: s * ys[i] - s * 0.12, width: s * 0.24, height: s * 0.24)
                UIBezierPath(ovalIn: knob).fill()
            }
        }
    }

    static func music(_ size: CGFloat) -> UIImage {
        return make(size) { s in
            UIBezierPath(ovalIn: CGRect(x: s * 0.14, y: s * 0.60, width: s * 0.30, height: s * 0.26)).fill()
            UIBezierPath(rect: CGRect(x: s * 0.40, y: s * 0.16, width: s * 0.07, height: s * 0.60)).fill()
            let flag = UIBezierPath()
            flag.move(to: CGPoint(x: s * 0.40, y: s * 0.16))
            flag.addLine(to: CGPoint(x: s * 0.86, y: s * 0.08))
            flag.addLine(to: CGPoint(x: s * 0.86, y: s * 0.26))
            flag.addLine(to: CGPoint(x: s * 0.40, y: s * 0.36))
            flag.close()
            flag.fill()
        }
    }

    static func clock(_ size: CGFloat) -> UIImage {
        return timer(size)
    }
}
