#if os(macOS)
import AppKit
import GatinhoCore
import SwiftUI

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

/// Implementa o `Painter` do núcleo sobre o GraphicsContext do SwiftUI (desenho na GPU).
final class SwiftUIPainter: Painter {
    private var stack: [GraphicsContext]

    init(_ ctx: GraphicsContext) { stack = [ctx] }

    private var top: GraphicsContext {
        get { stack[stack.count - 1] }
        set { stack[stack.count - 1] = newValue }
    }

    private func path(_ p: Path2D) -> Path {
        Path { out in
            for e in p.elements {
                switch e {
                case .move(let pt): out.move(to: pt)
                case .line(let pt): out.addLine(to: pt)
                case .quad(let c, let pt): out.addQuadCurve(to: pt, control: c)
                case .cubic(let c1, let c2, let pt): out.addCurve(to: pt, control1: c1, control2: c2)
                case .close: out.closeSubpath()
                }
            }
        }
    }

    private func shading(_ paint: Paint) -> GraphicsContext.Shading {
        switch paint {
        case .solid(let c, let a):
            return .color(c.color.opacity(a))
        case .radial(let center, let r0, let r1, let stops):
            let g = Gradient(stops: stops.map { Gradient.Stop(color: $0.color.color.opacity($0.alpha), location: $0.location) })
            return .radialGradient(g, center: center, startRadius: r0, endRadius: r1)
        }
    }

    func save() { stack.append(top) }
    func restore() { if stack.count > 1 { stack.removeLast() } }
    func translate(_ x: CGFloat, _ y: CGFloat) { top.translateBy(x: x, y: y) }
    func rotate(_ r: CGFloat) { top.rotate(by: .radians(Double(r))) }
    func scale(_ x: CGFloat, _ y: CGFloat) { top.scaleBy(x: x, y: y) }
    func multiplyOpacity(_ o: Double) { top.opacity *= o }
    func clip(_ p: Path2D) { top.clip(to: path(p)) }
    func fill(_ p: Path2D, _ paint: Paint) { top.fill(path(p), with: shading(paint)) }

    func stroke(_ p: Path2D, _ paint: Paint, _ s: StrokeStyle2) {
        let style = StrokeStyle(lineWidth: s.width, lineCap: s.cap == .round ? .round : .butt,
                                lineJoin: .round, dash: s.dash, dashPhase: s.dashPhase)
        top.stroke(path(p), with: shading(paint), style: style)
    }

    func text(_ s: String, center: CGPoint, size: CGFloat, color: RGB) {
        top.draw(Text(s).font(.system(size: size, weight: .bold, design: .rounded)).foregroundColor(color.color), at: center)
    }
}

/// Converte coordenadas do macOS (y para cima) para as do núcleo (y para baixo).
enum MacCoords {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func pointer() -> CGPoint {
        let m = NSEvent.mouseLocation
        return CGPoint(x: m.x, y: primaryHeight - m.y)
    }

    static func frame(_ f: NSRect) -> CGRect {
        CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }
}

struct CatRootView: View {
    let sim: CatSim
    let scale: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, _ in
                sim.pointer = MacCoords.pointer()
                sim.step(to: timeline.date.timeIntervalSinceReferenceDate)
                CatRenderer.draw(sim, SwiftUIPainter(ctx), scale: scale)
            }
        }
        .frame(width: Geo.size.width * scale, height: Geo.size.height * scale)
    }
}

/// Janela flutuante sem borda: nunca rouba o foco de quem está digitando.
final class CatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Recebe os cliques do gato: cabeça = carinho, resto = arrastar, botão direito = menu.
final class CatHostingView: NSHostingView<CatRootView> {
    var sim: CatSim?
    var scale: CGFloat = 1
    var menuProvider: (() -> NSMenu)?
    var onMoved: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func designPoint(_ e: NSEvent) -> CGPoint {
        var p = convert(e.locationInWindow, from: nil)
        if !isFlipped { p.y = bounds.height - p.y }
        return CGPoint(x: p.x / scale, y: p.y / scale)
    }

    override func mouseDown(with e: NSEvent) {
        guard let sim else { return }
        let p = designPoint(e)
        if Geo.hitsHead(p) {
            sim.beginPet(at: p)
        } else {
            window?.performDrag(with: e)
            onMoved?()
        }
    }

    override func mouseDragged(with e: NSEvent) {
        if let sim, sim.petting { sim.movePet(to: designPoint(e)) }
    }

    override func mouseUp(with e: NSEvent) { sim?.endPet() }

    override func rightMouseDown(with e: NSEvent) {
        if let menu = menuProvider?() { NSMenu.popUpContextMenu(menu, with: e, for: self) }
    }
}
#endif
