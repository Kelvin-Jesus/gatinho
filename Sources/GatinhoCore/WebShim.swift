// Só no build do site (WebAssembly): o que o núcleo usa do Foundation, sem puxar o Foundation
// inteiro (com ICU ele passa de 40 MB). Fora do wasm este arquivo não compila nada.
#if GATINHO_WEB
import WASILibc

public typealias CGFloat = Double
public typealias TimeInterval = Double

public struct CGPoint: Equatable {
    public var x: CGFloat, y: CGFloat
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public init() { x = 0; y = 0 }
    public static let zero = CGPoint(x: 0, y: 0)
}

public struct CGSize: Equatable {
    public var width: CGFloat, height: CGFloat
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
    public static let zero = CGSize(width: 0, height: 0)
}

public struct CGRect: Equatable {
    public var origin: CGPoint, size: CGSize
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        origin = CGPoint(x: x, y: y); size = CGSize(width: width, height: height)
    }
    public static let zero = CGRect(x: 0, y: 0, width: 0, height: 0)

    // Como no Foundation: as bordas valem também para largura/altura negativas.
    public var width: CGFloat { abs(size.width) }
    public var height: CGFloat { abs(size.height) }
    public var minX: CGFloat { Swift.min(origin.x, origin.x + size.width) }
    public var maxX: CGFloat { Swift.max(origin.x, origin.x + size.width) }
    public var minY: CGFloat { Swift.min(origin.y, origin.y + size.height) }
    public var maxY: CGFloat { Swift.max(origin.y, origin.y + size.height) }
    public var midX: CGFloat { origin.x + size.width / 2 }
    public var midY: CGFloat { origin.y + size.height / 2 }
    public var isEmpty: Bool { size.width == 0 || size.height == 0 }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: origin.x + dx, y: origin.y + dy, width: size.width, height: size.height)
    }
    public func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: minX + dx, y: minY + dy, width: width - 2 * dx, height: height - 2 * dy)
    }
    public func contains(_ p: CGPoint) -> Bool { p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY }
}

/// Só o relógio (segundos desde 1/1/2001, como o Foundation).
public struct Date {
    public let timeIntervalSinceReferenceDate: TimeInterval
    public init() {
        var tv = timeval()
        gettimeofday(&tv, nil)
        timeIntervalSinceReferenceDate = Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6 - 978_307_200
    }
    public static var timeIntervalSinceReferenceDate: TimeInterval { Date().timeIntervalSinceReferenceDate }
}
#endif
