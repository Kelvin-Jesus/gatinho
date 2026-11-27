import AppKit
import SwiftUI

/// `Gatinho --snapshot saida.png`: renderiza vários estados numa grade, para conferir o desenho.
enum Snapshot {
    struct Cell { let title: String; let sim: CatSim }

    private struct StaticCat: View {
        let sim: CatSim
        var body: some View {
            Canvas { ctx, _ in CatRenderer.draw(sim, in: &ctx) }
                .frame(width: Geo.size.width, height: Geo.size.height)
        }
    }

    private static func simulate(_ sim: CatSim, seconds: Double) {
        var t = Date().timeIntervalSinceReferenceDate
        sim.windowFrame = NSRect(x: 0, y: 0, width: Geo.size.width, height: Geo.size.height)
        for _ in 0..<Int(seconds * 60) {
            t += 1.0 / 60
            sim.step(to: t)
        }
    }

    private static func cell(_ title: String, _ coat: String, seconds: Double = 0.5, _ setup: (CatSim) -> Void) -> Cell {
        let sim = CatSim(coat: Coat.find(coat))
        setup(sim)
        simulate(sim, seconds: seconds)
        return Cell(title: title, sim: sim)
    }

    /// `Gatinho --check-smooth`: passa por acordado → sonhando → dormindo → acordando e mede
    /// o maior salto de rabo/respiração entre dois quadros. Sai com código 1 se pular.
    static func checkSmoothness() -> Bool {
        let sim = CatSim(coat: Coat.find(nil))
        sim.daydreamAfter = 2
        sim.sleepAfter = 6
        sim.windowFrame = NSRect(x: 0, y: 0, width: Geo.size.width, height: Geo.size.height)
        var t = Date().timeIntervalSinceReferenceDate
        let start = t
        var woke = false
        var prevTail: Double?, prevBreath: Double?, prevOld: Double?
        var maxTail = 0.0, maxBreath = 0.0, maxOld = 0.0
        for _ in 0..<(14 * 60) {
            t += 1.0 / 60
            if !woke, t - start > 10 { sim.keyDown(code: 0, label: "A", isRepeat: false); woke = true }
            sim.step(to: t)
            let tail = sin(sim.tailPhase), breath = sin(sim.breathPhase)
            let old = sin(t * sim.tailSpeed) // fórmula antiga, para mostrar o bug
            if let p = prevTail { maxTail = max(maxTail, abs(tail - p)) }
            if let p = prevBreath { maxBreath = max(maxBreath, abs(breath - p)) }
            if let p = prevOld { maxOld = max(maxOld, abs(old - p)) }
            prevTail = tail; prevBreath = breath; prevOld = old
        }
        print(String(format: "maior salto por quadro: rabo %.4f, respiração %.4f (fórmula antiga: %.4f)",
                     maxTail, maxBreath, maxOld))
        return maxTail < 0.05 && maxBreath < 0.05
    }

    @MainActor
    static func render(to path: String) {
        let cells: [Cell] = [
            cell("Parado", "tuxedo") { _ in },
            cell("Digitando A + K", "laranja", seconds: 0.25) { s in
                s.keyDown(code: 0, label: "A", isRepeat: false)
                s.keyDown(code: 40, label: "K", isRepeat: false)
            },
            cell("Clicando o mouse", "siames", seconds: 0.3) { s in
                s.keyDown(code: 1, label: "S", isRepeat: false)
                s.mouseButton(0, down: true)
            },
            cell("Carinho", "calico", seconds: 0.8) { s in s.beginPet(at: CGPoint(x: 175, y: 90)) },
            cell("Dormindo", "cinza", seconds: 7) { s in s.sleepAfter = -1 },
            cell("Sonhando acordado", "branco", seconds: 3) { s in s.daydreamAfter = -1; s.sleepAfter = 1000 },
            cell("Rajado marrom", "marrom") { _ in },
            cell("Preto", "preto") { _ in },
            cell("Cinza e branco", "cinzabranco", seconds: 0.25) { s in
                s.keyDown(code: 49, label: "␣", isRepeat: false)
                s.keyDown(code: 36, label: "⏎", isRepeat: false)
            },
        ]

        let grid = VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { c in
                        let cell = cells[r * 3 + c]
                        VStack(spacing: 2) {
                            Text(cell.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.black)
                            StaticCat(sim: cell.sim)
                        }
                        .padding(6)
                    }
                }
            }
        }
        .background(Color(red: 0.98, green: 0.86, blue: 0.55))

        let renderer = ImageRenderer(content: grid)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { print("falha ao renderizar"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: path))
        print("ok: \(path)")
    }
}
