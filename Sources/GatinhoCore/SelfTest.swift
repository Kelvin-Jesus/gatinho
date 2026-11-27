import Foundation

/// Ferramentas de verificação que rodam em qualquer sistema, sem janela.
public enum SelfTest {
    /// Passa por acordado → sonhando → dormindo → acordando e mede o maior salto de
    /// rabo/respiração entre dois quadros. Falha se a animação pular.
    public static func checkSmoothness() -> Bool {
        let sim = CatSim(coat: Coat.find(nil))
        sim.daydreamAfter = 2
        sim.sleepAfter = 6
        var t = Date().timeIntervalSinceReferenceDate
        let start = t
        var woke = false
        var prevTail: Double?, prevBreath: Double?
        var maxTail = 0.0, maxBreath = 0.0
        for _ in 0..<(14 * 60) {
            t += 1.0 / 60
            if !woke, t - start > 10 { sim.keyDown(code: 0, label: "A", isRepeat: false); woke = true }
            sim.step(to: t)
            let tail = sin(sim.tailPhase), breath = sin(sim.breathPhase)
            if let p = prevTail { maxTail = max(maxTail, abs(tail - p)) }
            if let p = prevBreath { maxBreath = max(maxBreath, abs(breath - p)) }
            prevTail = tail; prevBreath = breath
        }
        print(String(format: "maior salto por quadro: rabo %.4f, respiração %.4f", maxTail, maxBreath))
        return maxTail < 0.05 && maxBreath < 0.05
    }

    private static func simulate(_ sim: CatSim, seconds: Double) {
        var t = Date().timeIntervalSinceReferenceDate
        sim.windowFrame = CGRect(origin: .zero, size: Geo.size)
        sim.pointer = CGPoint(x: 600, y: 150)
        for _ in 0..<Int(seconds * 60) {
            t += 1.0 / 60
            sim.step(to: t)
        }
    }

    private static func cell(_ coat: String, seconds: Double = 0.5, _ setup: (CatSim) -> Void) -> CatSim {
        let sim = CatSim(coat: Coat.find(coat))
        sim.labelStyle = .linux
        setup(sim)
        simulate(sim, seconds: seconds)
        return sim
    }

    /// Os 9 estados da grade de conferência.
    public static func states() -> [CatSim] {
        [
            cell("tuxedo") { _ in },
            cell("laranja", seconds: 0.25) { s in
                s.keyDown(code: 0, label: "A", isRepeat: false)
                s.keyDown(code: 40, label: "K", isRepeat: false)
            },
            cell("siames", seconds: 0.3) { s in
                s.keyDown(code: 1, label: "S", isRepeat: false)
                s.mouseButton(0, down: true)
            },
            cell("calico", seconds: 0.8) { s in s.beginPet(at: CGPoint(x: 175, y: 90)) },
            cell("cinza", seconds: 7) { s in s.sleepAfter = -1 },
            cell("branco", seconds: 3) { s in s.daydreamAfter = -1; s.sleepAfter = 1000 },
            cell("marrom") { _ in },
            cell("preto", seconds: 0.25) { s in s.keyDown(code: 59, label: "CTRL", isRepeat: false) },
            cell("cinzabranco", seconds: 0.25) { s in
                s.keyDown(code: 49, label: "␣", isRepeat: false)
                s.keyDown(code: 36, label: "⏎", isRepeat: false)
            },
        ]
    }

    /// Grade 3 x 3 com os estados principais, desenhada pelo SoftPainter, salva em PNG.
    public static func snapshot(to path: String, withMenu: Bool = false) -> Bool {
        let cells = states()
        let cw = Int(Geo.size.width), ch = Int(Geo.size.height)
        let canvas = SoftCanvas(width: cw * 3, height: ch * 3)
        canvas.fillBackground(RGB(0xFADB8C))
        let painter = SoftPainter(canvas)
        for (i, sim) in cells.enumerated() {
            painter.save()
            painter.translate(CGFloat((i % 3) * cw), CGFloat((i / 3) * ch))
            CatRenderer.draw(sim, painter, scale: 1)
            if withMenu && i == 0 {
                let menu = OverlayMenu()
                menu.rows = ["Pelagem: Calico (três cores)", "Tamanho: Normal", "Opacidade: 100%", "[x] Mostrar teclas",
                             "Travar no lugar (Ctrl+Alt+L)", "Fechar menu", "Sair do Gatinho"]
                menu.isOpen = true
                menu.hovered = 1
                menu.draw(painter, scale: 1)
            }
            painter.restore()
        }
        let png = PNG.encode(rgba: canvas.rgbaStraight(), width: canvas.width, height: canvas.height)
        do {
            try Data(png).write(to: URL(fileURLWithPath: path))
            print("ok: \(path)")
            return true
        } catch {
            print("falha ao gravar \(path)")
            return false
        }
    }

    /// Quanto tempo leva um quadro desenhado por software (para checar se aguenta 60 fps).
    public static func benchmark(scale: CGFloat = 2) {
        let sim = cell("laranja") { s in s.keyDown(code: 0, label: "A", isRepeat: false) }
        let canvas = SoftCanvas(width: Int(Geo.size.width * scale), height: Int(Geo.size.height * scale))
        let start = Date()
        let frames = 120
        for _ in 0..<frames {
            canvas.clear()
            CatRenderer.draw(sim, SoftPainter(canvas), scale: scale)
        }
        let ms = Date().timeIntervalSince(start) * 1000 / Double(frames)
        print(String(format: "quadro em software (escala %.1f): %.2f ms", Double(scale), ms))
    }
}
