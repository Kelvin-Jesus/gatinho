import AppKit
import SwiftUI

struct CatRootView: View {
    let sim: CatSim
    let scale: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, _ in
                sim.step(to: timeline.date.timeIntervalSinceReferenceDate)
                CatRenderer.draw(sim, in: &ctx)
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
    var menuProvider: (() -> NSMenu)?
    var onMoved: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func designPoint(_ e: NSEvent) -> CGPoint {
        var p = convert(e.locationInWindow, from: nil)
        if !isFlipped { p.y = bounds.height - p.y }
        let s = sim?.scale ?? 1
        return CGPoint(x: p.x / s, y: p.y / s)
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
