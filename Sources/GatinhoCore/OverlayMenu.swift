import Foundation

/// Menu desenhado dentro da própria janela do gato (Linux não tem um menu nativo comum a todos os desktops).
public final class OverlayMenu {
    public var rows: [String] = []
    public var isOpen = false
    public var hovered: Int?

    static let rowH: CGFloat = 25
    static let width: CGFloat = 300

    public init() {}

    var frame: CGRect {
        let h = CGFloat(rows.count) * Self.rowH + 12
        return CGRect(x: (Geo.size.width - Self.width) / 2, y: max(4, (Geo.size.height - h) / 2 - 10),
                      width: Self.width, height: h)
    }

    /// Linha sob o ponto (coordenadas do desenho), ou nil fora do menu.
    public func row(at p: CGPoint) -> Int? {
        let f = frame
        guard f.contains(p) else { return nil }
        let i = Int((p.y - f.minY - 6) / Self.rowH)
        return rows.indices.contains(i) ? i : nil
    }

    public func draw(_ g: Painter, scale: CGFloat) {
        guard isOpen else { return }
        g.save(); defer { g.restore() }
        g.scale(scale, scale)
        let f = frame
        g.fill(.roundedRect(f.offsetBy(dx: 0, dy: 3), 10), .color(RGB(0x000000), 0.25))
        g.fill(.roundedRect(f, 10), .color(RGB(0xFFFDF8)))
        g.stroke(.roundedRect(f, 10), .color(CatRenderer.ink), StrokeStyle2(1.5))
        for (i, title) in rows.enumerated() {
            let r = CGRect(x: f.minX + 6, y: f.minY + 6 + CGFloat(i) * Self.rowH, width: f.width - 12, height: Self.rowH)
            if i == hovered { g.fill(.roundedRect(r, 6), .color(CatRenderer.keyLit)) }
            let size: CGFloat = 12
            let tw = StrokeFont.width(title, size: size)
            g.save()
            g.text(title, center: CGPoint(x: r.minX + 10 + tw / 2, y: r.midY), size: size, color: CatRenderer.ink)
            g.restore()
        }
    }
}
