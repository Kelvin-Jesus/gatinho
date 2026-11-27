// Fora do site: depende de Foundation (arquivos, Data, URL).
#if !GATINHO_WEB
import Foundation

/// Grava cenas curtas em quadros RGBA crus (para virar GIF com ffmpeg).
/// O tempo é simulado: cada quadro avança 1/fps, então o resultado não depende da máquina.
public enum Recorder {
    public static let scenes = ["digitando", "carinho", "soneca", "coruja", "caca", "bolinha", "cochilo"]

    private struct Cue { let at: Double; let run: (CatSim) -> Void }

    /// Códigos de tecla do Mac (os mesmos que o KeyLayout usa para escolher a pata).
    private static let macCode: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, " ": 49,
    ]

    private static func typing(_ text: String, from start: Double, gap: Double) -> [Cue] {
        var cues: [Cue] = []
        for (i, ch) in text.enumerated() {
            guard let code = macCode[ch] else { continue }
            let t = start + Double(i) * gap
            let label = ch == " " ? "␣" : String(ch).uppercased()
            cues.append(Cue(at: t) { $0.keyDown(code: code, label: label, isRepeat: false) })
            cues.append(Cue(at: t + gap * 0.6) { $0.keyUp(code: code) })
        }
        return cues
    }

    private static func scene(_ name: String) -> (coat: String, seconds: Double, setup: (CatSim) -> Void, cues: [Cue], pointer: (Double) -> CGPoint)? {
        let still: (Double) -> CGPoint = { _ in CGPoint(x: 520, y: 120) }
        switch name {
        case "digitando":
            var cues = typing("oi gatinho", from: 0.6, gap: 0.2)
            cues += typing("bom dia", from: 3.4, gap: 0.17)
            cues.append(Cue(at: 5.4) { $0.mouseButton(0, down: true) })
            cues.append(Cue(at: 5.55) { $0.mouseButton(0, down: false) })
            for i in 0..<10 { cues.append(Cue(at: 5.9 + Double(i) * 0.06) { $0.scroll(-3) }) }
            return ("laranja", 7.5, { _ in }, cues, { t in
                // o ponteiro passeia pela tela para os olhos acompanharem
                t < 5 ? still(t) : CGPoint(x: 520 - 300 * sin(min(t - 5, 2.5) / 2.5 * .pi), y: 120 + 140 * sin((t - 5) * 1.3))
            })
        case "carinho":
            return ("calico", 4.5, { _ in }, [
                Cue(at: 0.5) { $0.beginPet(at: CGPoint(x: 165, y: 90)) },
                Cue(at: 1.4) { $0.movePet(to: CGPoint(x: 185, y: 88)) },
                Cue(at: 2.2) { $0.movePet(to: CGPoint(x: 160, y: 92)) },
                Cue(at: 3.6) { $0.endPet() },
            ], still)
        case "soneca":
            return ("cinza", 10, { s in s.daydreamAfter = 1.2; s.sleepAfter = 3.2 }, [
                Cue(at: 8.6) { $0.keyDown(code: 0, label: "A", isRepeat: false) },
                Cue(at: 8.75) { $0.keyUp(code: 0) },
            ], still)
        case "coruja":
            // Parado um tempo; o cursor se mexe longe e ele faz cara de coruja.
            return ("laranja", 8, { _ in }, [], { t in
                t < 4.5 ? CGPoint(x: 520, y: 120) : CGPoint(x: 520 - 60 * min(t - 4.5, 0.6), y: 120 + 20 * min(t - 4.5, 0.6))
            })
        case "caca":
            // O cursor chega perto, para; ele abaixa, mexe o rabo e dá a patada. Depois de novo, do outro lado.
            return ("laranja", 9, { _ in }, [], { t in
                func go(_ a: CGPoint, _ b: CGPoint, _ t0: Double, _ t1: Double) -> CGPoint {
                    let k = min(max((t - t0) / (t1 - t0), 0), 1)
                    let e = k * k * (3 - 2 * k)
                    return CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
                }
                let p0 = CGPoint(x: 560, y: 60), p1 = CGPoint(x: 300, y: 120), p2 = CGPoint(x: 30, y: 150)
                return t < 4.5 ? go(p0, p1, 0.4, 1.4) : go(p1, p2, 4.5, 5.6)
            })
        case "bolinha":
            return ("laranja", 15, { s in s.daydreamAfter = 60; s.sleepAfter = 90 }, [
                Cue(at: 13.4) { $0.keyDown(code: 0, label: "A", isRepeat: false) },
                Cue(at: 13.55) { $0.keyUp(code: 0) },
            ], still)
        case "cochilo":
            // Lambe a pata, dorme com a pata nos olhos, acorda: sacode, espreguiça e boceja.
            return ("laranja", 15, { s in s.daydreamAfter = 0.5; s.sleepAfter = 6.5; s.forceCoverEyes = true }, [
                Cue(at: 11.5) { $0.keyDown(code: 0, label: "A", isRepeat: false) },
                Cue(at: 11.6) { $0.keyUp(code: 0) },
            ], still)
        default:
            return nil
        }
    }

    /// Grava a cena em `path` (RGBA cru, quadro após quadro) e devolve largura e altura.
    public static func record(_ name: String, to path: String, scale: CGFloat = 1.5, background: RGB = RGB(0xF7EEDF), fps: Double = 30) -> Bool {
        guard let sc = scene(name) else { print("cena desconhecida: \(name)"); return false }
        var t = Date().timeIntervalSinceReferenceDate
        let sim = CatSim(coat: Coat.find(sc.coat))
        sim.clock = { t }
        sim.labelStyle = .linux
        sim.windowFrame = CGRect(origin: .zero, size: Geo.size)
        sc.setup(sim)
        sim.pointer = sc.pointer(0)

        let w = Int(Geo.size.width * scale), h = Int(Geo.size.height * scale)
        let canvas = SoftCanvas(width: w, height: h)
        guard FileManager.default.createFile(atPath: path, contents: nil),
              let out = FileHandle(forWritingAtPath: path) else { print("falha ao gravar \(path)"); return false }
        defer { try? out.close() }

        var cues = sc.cues.sorted { $0.at < $1.at }
        // um segundo de aquecimento para as molas assentarem antes do primeiro quadro
        for _ in 0..<60 { t += 1.0 / 60; sim.step(to: t) }
        let begin = t
        let frames = Int(sc.seconds * fps)
        let sub = 4 // passos de simulação por quadro
        for _ in 0..<frames {
            for _ in 0..<sub {
                t += 1.0 / (fps * Double(sub))
                let local = t - begin
                while let c = cues.first, c.at <= local { c.run(sim); cues.removeFirst() }
                sim.pointer = sc.pointer(local)
                sim.step(to: t)
            }
            canvas.fillBackground(background)
            CatRenderer.draw(sim, SoftPainter(canvas), scale: scale)
            out.write(Data(canvas.rgbaStraight()))
        }
        print("ok: \(name) \(w)x\(h) \(frames) quadros")
        return true
    }
}
#endif
