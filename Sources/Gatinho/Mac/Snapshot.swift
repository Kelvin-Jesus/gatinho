#if os(macOS)
import AppKit
import GatinhoCore
import SwiftUI

/// `Gatinho --snapshot-swiftui saida.png`: mesma grade do `--snapshot`, mas desenhada pelo SwiftUI,
/// para comparar os dois pintores lado a lado.
enum MacSnapshot {
    @MainActor
    static func render(to path: String) {
        // Reaproveita os estados do núcleo: desenha a grade com SwiftUIPainter num Canvas.
        let view = Canvas { ctx, _ in
            ctx.fill(Path(CGRect(x: 0, y: 0, width: Geo.size.width * 3, height: Geo.size.height * 3)),
                     with: .color(Color(red: 0.98, green: 0.86, blue: 0.55)))
            let painter = SwiftUIPainter(ctx)
            for (i, sim) in SelfTest.states().enumerated() {
                painter.save()
                painter.translate(CGFloat(i % 3) * Geo.size.width, CGFloat(i / 3) * Geo.size.height)
                CatRenderer.draw(sim, painter, scale: 1)
                painter.restore()
            }
        }
        .frame(width: Geo.size.width * 3, height: Geo.size.height * 3)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("falha ao renderizar"); return
        }
        try? data.write(to: URL(fileURLWithPath: path))
        print("ok: \(path)")
    }
}
#endif
