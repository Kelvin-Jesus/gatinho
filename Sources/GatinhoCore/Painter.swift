import Foundation

/// Caminho vetorial independente de plataforma (y para baixo).
public struct Path2D {
    public enum Element {
        case move(CGPoint)
        case line(CGPoint)
        case quad(CGPoint, CGPoint)            // controle, destino
        case cubic(CGPoint, CGPoint, CGPoint)  // controle1, controle2, destino
        case close
    }

    public private(set) var elements: [Element] = []

    public init() {}
    public init(_ build: (inout Path2D) -> Void) { build(&self) }

    public mutating func move(to p: CGPoint) { elements.append(.move(p)) }
    public mutating func addLine(to p: CGPoint) { elements.append(.line(p)) }
    public mutating func addQuadCurve(to p: CGPoint, control c: CGPoint) { elements.append(.quad(c, p)) }
    public mutating func addCurve(to p: CGPoint, control1 c1: CGPoint, control2 c2: CGPoint) {
        elements.append(.cubic(c1, c2, p))
    }
    public mutating func closeSubpath() { elements.append(.close) }

    public mutating func addLines(_ pts: [CGPoint]) {
        guard let first = pts.first else { return }
        move(to: first)
        for p in pts.dropFirst() { addLine(to: p) }
    }

    public mutating func addEllipse(in r: CGRect) {
        let k: CGFloat = 0.5522847498
        let cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2
        move(to: CGPoint(x: cx + rx, y: cy))
        addCurve(to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + k * ry), control2: CGPoint(x: cx + k * rx, y: cy + ry))
        addCurve(to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - k * rx, y: cy + ry), control2: CGPoint(x: cx - rx, y: cy + k * ry))
        addCurve(to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - k * ry), control2: CGPoint(x: cx - k * rx, y: cy - ry))
        addCurve(to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + k * rx, y: cy - ry), control2: CGPoint(x: cx + rx, y: cy - k * ry))
        closeSubpath()
    }

    public mutating func addRoundedRect(_ r: CGRect, radius: CGFloat) {
        let rr = min(radius, r.width / 2, r.height / 2)
        let k = 0.5522847498 * rr
        move(to: CGPoint(x: r.minX + rr, y: r.minY))
        addLine(to: CGPoint(x: r.maxX - rr, y: r.minY))
        addCurve(to: CGPoint(x: r.maxX, y: r.minY + rr), control1: CGPoint(x: r.maxX - rr + k, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + rr - k))
        addLine(to: CGPoint(x: r.maxX, y: r.maxY - rr))
        addCurve(to: CGPoint(x: r.maxX - rr, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY - rr + k), control2: CGPoint(x: r.maxX - rr + k, y: r.maxY))
        addLine(to: CGPoint(x: r.minX + rr, y: r.maxY))
        addCurve(to: CGPoint(x: r.minX, y: r.maxY - rr), control1: CGPoint(x: r.minX + rr - k, y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY - rr + k))
        addLine(to: CGPoint(x: r.minX, y: r.minY + rr))
        addCurve(to: CGPoint(x: r.minX + rr, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + rr - k), control2: CGPoint(x: r.minX + rr - k, y: r.minY))
        closeSubpath()
    }

    public mutating func addRect(_ r: CGRect) {
        addLines([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                  CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)])
        closeSubpath()
    }

    public static func ellipse(_ r: CGRect) -> Path2D { Path2D { $0.addEllipse(in: r) } }
    public static func roundedRect(_ r: CGRect, _ radius: CGFloat) -> Path2D { Path2D { $0.addRoundedRect(r, radius: radius) } }
    public static func rect(_ r: CGRect) -> Path2D { Path2D { $0.addRect(r) } }
}

public enum LineCap { case butt, round }

/// Estilo de traço. As junções são sempre arredondadas.
public struct StrokeStyle2 {
    public var width: CGFloat
    public var cap: LineCap
    public var dash: [CGFloat]
    public var dashPhase: CGFloat

    public init(_ width: CGFloat, cap: LineCap = .butt, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {
        self.width = width; self.cap = cap; self.dash = dash; self.dashPhase = dashPhase
    }
}

public struct GradientStop {
    public var color: RGB
    public var alpha: Double
    public var location: Double
    public init(_ color: RGB, _ alpha: Double, _ location: Double) {
        self.color = color; self.alpha = alpha; self.location = location
    }
}

public enum Paint {
    case solid(RGB, Double)
    case radial(center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, stops: [GradientStop])

    public static func color(_ c: RGB, _ alpha: Double = 1) -> Paint { .solid(c, alpha) }
}

/// O que cada plataforma precisa saber desenhar. Mac: SwiftUI; Windows/Linux: SoftPainter.
/// Transformações valem para o que vier depois (como no Core Graphics); save/restore empilham estado.
public protocol Painter: AnyObject {
    func save()
    func restore()
    func translate(_ x: CGFloat, _ y: CGFloat)
    func rotate(_ radians: CGFloat)
    func scale(_ x: CGFloat, _ y: CGFloat)
    func multiplyOpacity(_ o: Double)
    func clip(_ p: Path2D)
    func fill(_ p: Path2D, _ paint: Paint)
    func stroke(_ p: Path2D, _ paint: Paint, _ style: StrokeStyle2)
    /// Texto em negrito, centralizado no ponto.
    func text(_ s: String, center: CGPoint, size: CGFloat, color: RGB)
}
