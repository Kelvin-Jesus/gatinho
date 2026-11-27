import CoreGraphics

/// Todas as medidas do desenho, num espaço fixo de 330 x 300 pontos (y cresce para baixo).
enum Geo {
    static let size = CGSize(width: 330, height: 300)
    static let cx: CGFloat = 155

    static let headCenter = CGPoint(x: 155, y: 112)
    static let neck = CGPoint(x: 155, y: 160)
    static let bodyBottom: CGFloat = 254

    static let shoulderL = CGPoint(x: 129, y: 172)
    static let shoulderR = CGPoint(x: 181, y: 172)
    static let restL = CGPoint(x: 131, y: 225)
    static let restR = CGPoint(x: 179, y: 225)

    static let eyeL = CGPoint(x: 133, y: 114)
    static let eyeR = CGPoint(x: 177, y: 114)
    static let eyeRadius: CGFloat = 12

    static let mouseCenter = CGPoint(x: 274, y: 254)
    static var mouseGrip: CGPoint { CGPoint(x: mouseCenter.x - 2, y: mouseCenter.y - 9) }

    static func hitsHead(_ p: CGPoint) -> Bool {
        let dx = (p.x - headCenter.x) / 68
        let dy = (p.y - (headCenter.y - 6)) / 58
        return dx * dx + dy * dy <= 1
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    func lerp(_ o: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: x + (o.x - x) * t, y: y + (o.y - y) * t) }
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

func rect(center c: CGPoint, w: CGFloat, h: CGFloat) -> CGRect {
    CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
}
