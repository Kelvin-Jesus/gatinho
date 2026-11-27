import Foundation

/// Desenha o gato inteiro em qualquer `Painter`, a partir do estado do CatSim.
public enum CatRenderer {
    static let ink = RGB(0x2D2A2E)
    static let keyFace = RGB(0xF4F0E6)
    static let keyLit = RGB(0xFFC94D)
    static let keyAccent = RGB(0xF08A5D)

    /// `scale`: quantas unidades do destino valem um ponto do desenho (330 x 300).
    public static func draw(_ sim: CatSim, _ g: Painter, scale: CGFloat) {
        g.save(); defer { g.restore() }
        g.scale(scale, scale)
        let c = sim.coat

        // Respiração: o corpo estica a partir da base; ombros e cabeça acompanham.
        let b = CGFloat(sin(sim.breathPhase))
        let amp: CGFloat = 0.012 + 0.016 * sim.sleep.value
        let bodyScaleY = 1 + b * amp + 0.035 * sim.dream.value - 0.03 * sim.sleep.value
        let rise = (Geo.bodyBottom - Geo.shoulderL.y) * (bodyScaleY - 1)

        func bodyTransform() {
            g.translate(Geo.cx, Geo.bodyBottom)
            g.scale(1 - b * amp * 0.3, bodyScaleY)
            g.translate(-Geo.cx, -Geo.bodyBottom)
        }

        drawShadow(g)
        drawTail(sim, g)

        g.save(); bodyTransform(); drawBody(c, g); g.restore()

        drawKeyboard(sim, g)
        drawMouse(sim, g)

        // Braços: contorno, depois o corpo de novo por cima (só acima do teclado), depois o preenchimento.
        let shL = Geo.shoulderL - CGPoint(x: 0, y: rise)
        let shR = Geo.shoulderR - CGPoint(x: 0, y: rise)
        let pL = pawPosition(sim.leftPaw, press: sim.leftPress.value)
        let pR = pawPosition(sim.rightPaw, press: sim.rightPress.value)
        for (s, p) in [(shL, pL), (shR, pR)] {
            g.stroke(armPath(s, p), .color(c.shade), StrokeStyle2(22.5, cap: .round))
        }
        g.save()
        g.clip(.rect(CGRect(x: 0, y: 0, width: Geo.size.width, height: KeyLayout.board.minY)))
        bodyTransform()
        drawBody(c, g)
        g.restore()
        for (s, p) in [(shL, pL), (shR, pR)] {
            g.stroke(armPath(s, p), .color(c.base), StrokeStyle2(19.5, cap: .round))
        }
        drawPaw(at: pL, press: sim.leftPress.value, coat: c, g)
        drawPaw(at: pR, press: sim.rightPress.value, coat: c, g)

        // Cabeça
        g.save()
        g.translate(0, sim.headLift.value - rise * 1.1)
        g.translate(Geo.neck.x, Geo.neck.y)
        g.rotate(sim.headTilt.value + sim.shakeAngle)
        g.translate(-Geo.neck.x, -Geo.neck.y)
        drawEars(sim, g)
        drawHead(c, g)
        drawFace(sim, g, breath: b)
        g.restore()

        drawParticles(sim, g)
    }

    // MARK: - Partes

    private static func drawShadow(_ g: Painter) {
        g.save()
        g.translate(184, 280)
        g.scale(1, 9.0 / 140)
        g.fill(.ellipse(CGRect(x: -140, y: -140, width: 280, height: 280)),
               .radial(center: .zero, startRadius: 0, endRadius: 140,
                       stops: [GradientStop(RGB(0x000000), 0.2, 0), GradientStop(RGB(0x000000), 0.12, 0.55),
                               GradientStop(RGB(0x000000), 0, 1)]))
        g.restore()
    }

    private static func tailPath(_ sim: CatSim) -> Path2D {
        let s = sim.sleep.value, d = sim.dream.value
        let w = CGFloat(sin(sim.tailPhase)) * (1 - 0.55 * d)
        let w2 = CGFloat(sin(sim.tailPhase + 0.9)) * (1 - 0.55 * d)
        let awake = [CGPoint(x: 200, y: 236), CGPoint(x: 252, y: 246),
                     CGPoint(x: 266 + w * 6, y: 196 + w * 10), CGPoint(x: 254 + w * 16, y: 166 + w2 * 6)]
        let asleep = [CGPoint(x: 200, y: 240), CGPoint(x: 240, y: 252),
                      CGPoint(x: 268, y: 246), CGPoint(x: 272, y: 222)]
        let p = zip(awake, asleep).map { $0.lerp($1, s) }
        return Path2D { path in
            path.move(to: p[0])
            path.addCurve(to: p[3], control1: p[1], control2: p[2])
        }
    }

    private static func drawTail(_ sim: CatSim, _ g: Painter) {
        let c = sim.coat
        let path = tailPath(sim)
        g.stroke(path, .color(c.shade), StrokeStyle2(15.5, cap: .round))
        g.stroke(path, .color(c.tailColor), StrokeStyle2(12.5, cap: .round))
        if c.pattern == .tabby {
            g.stroke(path, .color(c.accent), StrokeStyle2(12.5, dash: [5, 8], dashPhase: 3))
        }
    }

    static func bodyPath() -> Path2D {
        Path2D { p in
            p.move(to: CGPoint(x: 155, y: 136))
            p.addCurve(to: CGPoint(x: 213, y: 222), control1: CGPoint(x: 195, y: 136), control2: CGPoint(x: 215, y: 180))
            p.addCurve(to: CGPoint(x: 155, y: 256), control1: CGPoint(x: 212, y: 250), control2: CGPoint(x: 185, y: 256))
            p.addCurve(to: CGPoint(x: 97, y: 222), control1: CGPoint(x: 125, y: 256), control2: CGPoint(x: 98, y: 250))
            p.addCurve(to: CGPoint(x: 155, y: 136), control1: CGPoint(x: 95, y: 180), control2: CGPoint(x: 115, y: 136))
            p.closeSubpath()
        }
    }

    private static func ellipse(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat) -> Path2D {
        .ellipse(rect(center: c, w: w, h: h))
    }

    private static func drawBody(_ c: Coat, _ g: Painter) {
        let body = bodyPath()
        g.fill(body, .color(c.base))
        g.save()
        g.clip(body)
        switch c.pattern {
        case .tuxedo, .bicolor:
            g.fill(ellipse(CGPoint(x: 155, y: 202), 58, 88), .color(c.accent))
        case .tabby:
            g.fill(ellipse(CGPoint(x: 155, y: 210), 48, 74), .color(c.accent2, 0.7))
            let stripes = Path2D { p in
                for (y, len) in [(184.0, 16.0), (200.0, 18.0), (216.0, 16.0)] as [(CGFloat, CGFloat)] {
                    p.move(to: CGPoint(x: 96, y: y)); p.addQuadCurve(to: CGPoint(x: 96 + len, y: y + 3), control: CGPoint(x: 104, y: y - 3))
                    p.move(to: CGPoint(x: 214, y: y)); p.addQuadCurve(to: CGPoint(x: 214 - len, y: y + 3), control: CGPoint(x: 206, y: y - 3))
                }
            }
            g.stroke(stripes, .color(c.accent), StrokeStyle2(4.5, cap: .round))
        case .calico:
            g.fill(ellipse(CGPoint(x: 122, y: 214), 52, 44), .color(c.accent))
            g.fill(ellipse(CGPoint(x: 198, y: 196), 40, 38), .color(c.accent2))
        case .siamese:
            g.fill(ellipse(CGPoint(x: 155, y: 250), 140, 60), .color(c.shade, 0.25))
        case .solid:
            break
        }
        g.restore()
        g.stroke(body, .color(c.shade), StrokeStyle2(1.6))
    }

    private static func armPath(_ shoulder: CGPoint, _ paw: CGPoint) -> Path2D {
        Path2D { p in
            p.move(to: shoulder)
            let mid = CGPoint(x: (shoulder.x + paw.x) / 2 + (paw.x < Geo.cx ? -3 : 3), y: (shoulder.y + paw.y) / 2)
            p.addQuadCurve(to: paw + CGPoint(x: 0, y: -3), control: mid)
        }
    }

    private static func pawPosition(_ s: Spring2, press: CGFloat) -> CGPoint {
        let lift = min(7, s.speed * 0.012)
        return CGPoint(x: s.value.x, y: s.value.y - lift + press * 2)
    }

    private static func drawPaw(at p: CGPoint, press: CGFloat, coat c: Coat, _ g: Painter) {
        let h = 15 * (1 - 0.15 * clamp(press, 0, 1))
        let r = rect(center: p, w: 23, h: h)
        g.fill(.ellipse(r), .color(c.paw))
        g.stroke(.ellipse(r), .color(c.shade), StrokeStyle2(1.6))
        let toes = Path2D { t in
            for dx in [-4.0, 4.0] as [CGFloat] {
                t.move(to: CGPoint(x: p.x + dx, y: r.maxY - 4.5))
                t.addLine(to: CGPoint(x: p.x + dx, y: r.maxY - 1.5))
            }
        }
        g.stroke(toes, .color(c.shade), StrokeStyle2(1.3, cap: .round))
    }

    private static func drawKeyboard(_ sim: CatSim, _ g: Painter) {
        let board = KeyLayout.board
        g.fill(.roundedRect(board.offsetBy(dx: 0, dy: 4), 8), .color(RGB(0x1C1A1D)))
        g.fill(.roundedRect(board, 8), .color(ink))
        for (i, slot) in KeyLayout.slots.enumerated() {
            let glow = sim.keyGlow[i]
            let face = (slot.accent ? keyAccent : keyFace).mix(keyLit, Double(glow))
            let r = slot.rect.offsetBy(dx: 0, dy: glow)
            g.fill(.roundedRect(r.offsetBy(dx: 0, dy: 1.3), 1.8), .color(face.mix(RGB(0x000000), 0.25)))
            g.fill(.roundedRect(r, 1.8), .color(face))
        }
    }

    private static func drawMouse(_ sim: CatSim, _ g: Painter) {
        let ctr = Geo.mouseCenter + sim.mouseJiggle.value
        let r = rect(center: ctr, w: 26, h: 38)
        let shell = Path2D.roundedRect(r, 13)
        let cord = Path2D { p in
            p.move(to: CGPoint(x: ctr.x, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: ctr.x + 18, y: r.minY - 18), control: CGPoint(x: ctr.x + 2, y: r.minY - 16))
        }
        g.stroke(cord, .color(ink), StrokeStyle2(1.6, cap: .round))
        g.fill(shell, .color(keyFace))

        g.save()
        g.clip(shell)
        let split = r.minY + 15
        if sim.mouseButtons.contains(0) {
            g.fill(.rect(CGRect(x: r.minX, y: r.minY, width: 13, height: 15)), .color(keyLit))
        }
        if sim.mouseButtons.contains(1) {
            g.fill(.rect(CGRect(x: ctr.x, y: r.minY, width: 13, height: 15)), .color(keyLit))
        }
        let lines = Path2D { p in
            p.move(to: CGPoint(x: r.minX, y: split)); p.addLine(to: CGPoint(x: r.maxX, y: split))
            p.move(to: CGPoint(x: ctr.x, y: r.minY)); p.addLine(to: CGPoint(x: ctr.x, y: split))
        }
        g.stroke(lines, .color(ink, 0.6), StrokeStyle2(1.2))
        g.restore()

        // Rodinha: os sulcos deslizam com o scroll de verdade.
        let wheel = CGRect(x: ctr.x - 2.6, y: r.minY + 3.5, width: 5.2, height: 9)
        g.fill(.roundedRect(wheel, 2.6), .color(sim.mouseButtons.contains(2) ? keyLit : ink))
        g.save()
        g.clip(.roundedRect(wheel, 2.6))
        let phase = sim.wheelPhase.truncatingRemainder(dividingBy: 3)
        let ridges = Path2D { p in
            for k in -1...4 {
                let y = wheel.minY + CGFloat(k) * 3 + (phase < 0 ? phase + 3 : phase)
                p.move(to: CGPoint(x: wheel.minX, y: y)); p.addLine(to: CGPoint(x: wheel.maxX, y: y))
            }
        }
        g.stroke(ridges, .color(RGB(0xFFFFFF), 0.55), StrokeStyle2(0.9))
        g.restore()

        g.stroke(shell, .color(ink), StrokeStyle2(2))
    }

    private static func earPath(left: Bool, inner: Bool) -> Path2D {
        let pts: [CGPoint] = inner
            ? [CGPoint(x: 109, y: 90), CGPoint(x: 115, y: 60), CGPoint(x: 135, y: 77)]
            : [CGPoint(x: 99, y: 100), CGPoint(x: 111, y: 46), CGPoint(x: 144, y: 74)]
        let m = left ? pts : pts.map { CGPoint(x: 2 * Geo.cx - $0.x, y: $0.y) }
        return Path2D { p in p.addLines(m); p.closeSubpath() }
    }

    private static func drawEars(_ sim: CatSim, _ g: Painter) {
        let c = sim.coat
        for left in [true, false] {
            g.save()
            let pivot = CGPoint(x: left ? 124 : 2 * Geo.cx - 124, y: 88)
            // No carinho as orelhas abaixam para fora; de vez em quando uma dá um tremelique.
            let flatten = sim.pet.value * 0.32 + sim.sleep.value * 0.12
            let angle = (left ? -flatten : flatten) + sim.earTwitchAngle(left: left) * (left ? -1 : 1)
            g.translate(pivot.x, pivot.y)
            g.rotate(angle)
            g.translate(-pivot.x, -pivot.y)
            let outer = earPath(left: left, inner: false)
            g.stroke(outer, .color(c.shade), StrokeStyle2(10))
            g.fill(outer, .color(c.earColor(left: left)))
            g.stroke(outer, .color(c.earColor(left: left)), StrokeStyle2(7))
            let inner = earPath(left: left, inner: true)
            g.fill(inner, .color(c.innerEar))
            g.stroke(inner, .color(c.innerEar), StrokeStyle2(4))
            g.restore()
        }
    }

    static func headPath() -> Path2D {
        Path2D { p in
            p.move(to: CGPoint(x: 155, y: 62))
            p.addCurve(to: CGPoint(x: 218, y: 118), control1: CGPoint(x: 192, y: 62), control2: CGPoint(x: 218, y: 84))
            p.addCurve(to: CGPoint(x: 155, y: 163), control1: CGPoint(x: 218, y: 148), control2: CGPoint(x: 192, y: 163))
            p.addCurve(to: CGPoint(x: 92, y: 118), control1: CGPoint(x: 118, y: 163), control2: CGPoint(x: 92, y: 148))
            p.addCurve(to: CGPoint(x: 155, y: 62), control1: CGPoint(x: 92, y: 84), control2: CGPoint(x: 118, y: 62))
            p.closeSubpath()
        }
    }

    private static func drawHead(_ c: Coat, _ g: Painter) {
        let head = headPath()
        g.fill(head, .color(c.base))
        g.save()
        g.clip(head)
        switch c.pattern {
        case .tuxedo:
            g.fill(ellipse(CGPoint(x: 155, y: 144), 62, 42), .color(c.accent))
        case .bicolor:
            let blaze = Path2D { p in
                p.addLines([CGPoint(x: 155, y: 98), CGPoint(x: 168, y: 132), CGPoint(x: 142, y: 132)])
                p.closeSubpath()
            }
            g.fill(blaze, .color(c.accent))
            g.fill(ellipse(CGPoint(x: 155, y: 144), 64, 42), .color(c.accent))
        case .tabby:
            g.fill(ellipse(CGPoint(x: 155, y: 142), 50, 30), .color(c.accent2))
            let forehead = Path2D { p in
                p.move(to: CGPoint(x: 144, y: 70)); p.addLine(to: CGPoint(x: 147, y: 88))
                p.move(to: CGPoint(x: 155, y: 66)); p.addLine(to: CGPoint(x: 155, y: 90))
                p.move(to: CGPoint(x: 166, y: 70)); p.addLine(to: CGPoint(x: 163, y: 88))
            }
            g.stroke(forehead, .color(c.accent), StrokeStyle2(4.5, cap: .round))
            let cheeks = Path2D { p in
                for (y, len) in [(118.0, 14.0), (128.0, 12.0)] as [(CGFloat, CGFloat)] {
                    p.move(to: CGPoint(x: 92, y: y)); p.addLine(to: CGPoint(x: 92 + len, y: y + 2))
                    p.move(to: CGPoint(x: 218, y: y)); p.addLine(to: CGPoint(x: 218 - len, y: y + 2))
                }
            }
            g.stroke(cheeks, .color(c.accent), StrokeStyle2(3.5, cap: .round))
        case .siamese:
            g.fill(ellipse(CGPoint(x: 155, y: 130), 104, 84),
                   .radial(center: CGPoint(x: 155, y: 134), startRadius: 6, endRadius: 50,
                           stops: [GradientStop(c.accent, 1, 0), GradientStop(c.accent, 0.85, 0.5), GradientStop(c.accent, 0, 1)]))
        case .calico:
            g.fill(ellipse(CGPoint(x: 118, y: 76), 52, 46), .color(c.accent))
            g.fill(ellipse(CGPoint(x: 194, y: 76), 46, 40), .color(c.accent2))
        case .solid:
            break
        }
        g.restore()
        g.stroke(head, .color(c.shade), StrokeStyle2(1.8))
    }

    private static func drawFace(_ sim: CatSim, _ g: Painter, breath b: CGFloat) {
        let c = sim.coat
        let pet = sim.pet.value

        // Bochechas coradas (mais fortes no carinho)
        for x in [121.0, 189.0] as [CGFloat] {
            g.fill(ellipse(CGPoint(x: x, y: 131), 16, 8), .color(RGB(0xF28C9C), Double(0.22 + 0.5 * pet)))
        }

        drawEye(sim, center: Geo.eyeL, g)
        drawEye(sim, center: Geo.eyeR, g)

        // Nariz e boca
        let nose = Path2D { p in
            p.addLines([CGPoint(x: 150.5, y: 128), CGPoint(x: 159.5, y: 128), CGPoint(x: 155, y: 133.5)])
            p.closeSubpath()
        }
        let noseColor = c.pattern == .siamese ? RGB(0x3A2A22) : RGB(0xE88A9A)
        g.fill(nose, .color(noseColor))
        g.stroke(nose, .color(noseColor), StrokeStyle2(2.5))
        let smile = 1 + pet * 0.8
        let mouth = Path2D { p in
            p.move(to: CGPoint(x: 155, y: 134)); p.addLine(to: CGPoint(x: 155, y: 137))
            p.addQuadCurve(to: CGPoint(x: 155 - 7 * smile, y: 139), control: CGPoint(x: 155 - 3, y: 141 + pet))
            p.move(to: CGPoint(x: 155, y: 137))
            p.addQuadCurve(to: CGPoint(x: 155 + 7 * smile, y: 139), control: CGPoint(x: 155 + 3, y: 141 + pet))
        }
        g.stroke(mouth, .color(c.mouthLine), StrokeStyle2(1.6, cap: .round))

        // Bigodes: tremem de leve quando ronrona no carinho
        let purr = CGFloat(sin(sim.time.truncatingRemainder(dividingBy: 1000) * 38)) * 0.9 * pet
        let whiskers = Path2D { p in
            for (y0, y1, len) in [(133.0, 127.0, 30.0), (137.0, 138.0, 32.0), (141.0, 148.0, 28.0)] as [(CGFloat, CGFloat, CGFloat)] {
                p.move(to: CGPoint(x: 129, y: y0)); p.addLine(to: CGPoint(x: 129 - len, y: y1 + purr))
                p.move(to: CGPoint(x: 181, y: y0)); p.addLine(to: CGPoint(x: 181 + len, y: y1 - purr))
            }
        }
        g.stroke(whiskers, .color(c.whisker, 0.85), StrokeStyle2(1.1, cap: .round))

        // Bolha de ronco: enche e esvazia com a respiração
        if sim.sleep.value > 0.6 {
            let k = (sim.sleep.value - 0.6) / 0.4
            let r = (2.5 + 5 * (0.5 + 0.5 * b)) * k
            let ctr = CGPoint(x: 161 + r * 0.7, y: 133 + r * 0.3)
            g.fill(ellipse(ctr, r * 2, r * 2), .color(RGB(0xBFE3F5), 0.55))
            g.stroke(ellipse(ctr, r * 2, r * 2), .color(RGB(0xFFFFFF), 0.85), StrokeStyle2(0.9))
            g.fill(ellipse(ctr + CGPoint(x: -r * 0.35, y: -r * 0.35), r * 0.5, r * 0.5), .color(RGB(0xFFFFFF), 0.9))
        }
    }

    private static func drawEye(_ sim: CatSim, center p: CGPoint, _ g: Painter) {
        let c = sim.coat
        // Carinho: olhinhos de "^ ^"
        if sim.pet.value > 0.5 {
            let squint = Path2D { s in
                s.move(to: CGPoint(x: p.x - 9, y: p.y + 3))
                s.addQuadCurve(to: CGPoint(x: p.x + 9, y: p.y + 3), control: CGPoint(x: p.x, y: p.y - 8))
            }
            g.stroke(squint, .color(c.eyeLine), StrokeStyle2(2.6, cap: .round))
            return
        }
        let o = sim.eyeOpenness
        if o < 0.1 {
            let closed = Path2D { s in
                s.move(to: CGPoint(x: p.x - 9, y: p.y))
                s.addQuadCurve(to: CGPoint(x: p.x + 9, y: p.y), control: CGPoint(x: p.x, y: p.y + 6))
            }
            g.stroke(closed, .color(c.eyeLine), StrokeStyle2(2.4, cap: .round))
            return
        }
        let r = Geo.eyeRadius + sim.dream.value
        let circle = ellipse(p, r * 2, r * 2)
        g.fill(circle, .color(c.eye))
        g.save()
        g.clip(circle)
        let round = sim.pupilRound.value
        let pw = lerp(4.5, 11.5, round) + sim.dream.value * 1.5
        let ph = lerp(19, 14, round) + sim.dream.value * 1.5
        let pc = p + sim.pupil.value * (r / Geo.eyeRadius)
        g.fill(ellipse(pc, pw, ph), .color(RGB(0x161616)))
        g.fill(ellipse(pc + CGPoint(x: -3.5, y: -4.5), 5.4, 5.4), .color(RGB(0xFFFFFF)))
        g.fill(ellipse(pc + CGPoint(x: 3, y: 3.5), 2.2, 2.2), .color(RGB(0xFFFFFF), 0.85))
        // Pálpebra: desce do topo conforme o olho fecha (piscada, sonolência)
        if o < 0.98 {
            let lidY = p.y - r + 2 * r * (1 - o)
            let lid = Path2D { s in
                s.move(to: CGPoint(x: p.x - r - 1, y: p.y - r - 1))
                s.addLine(to: CGPoint(x: p.x + r + 1, y: p.y - r - 1))
                s.addLine(to: CGPoint(x: p.x + r + 1, y: lidY))
                s.addQuadCurve(to: CGPoint(x: p.x - r - 1, y: lidY), control: CGPoint(x: p.x, y: lidY + 3))
                s.closeSubpath()
            }
            g.fill(lid, .color(c.lidColor))
            let edge = Path2D { s in
                s.move(to: CGPoint(x: p.x - r - 1, y: lidY))
                s.addQuadCurve(to: CGPoint(x: p.x + r + 1, y: lidY), control: CGPoint(x: p.x, y: lidY + 3))
            }
            g.stroke(edge, .color(c.eyeLine), StrokeStyle2(1.6))
        }
        g.restore()
        g.stroke(circle, .color(c.shade, 0.7), StrokeStyle2(1.2))
    }

    static func heartPath(_ c: CGPoint, _ s: CGFloat) -> Path2D {
        Path2D { p in
            p.move(to: c + CGPoint(x: 0, y: s * 0.38))
            p.addCurve(to: c + CGPoint(x: -s * 0.5, y: -s * 0.08), control1: c + CGPoint(x: -s * 0.18, y: s * 0.18), control2: c + CGPoint(x: -s * 0.5, y: s * 0.1))
            p.addCurve(to: c + CGPoint(x: 0, y: -s * 0.22), control1: c + CGPoint(x: -s * 0.5, y: -s * 0.42), control2: c + CGPoint(x: -s * 0.08, y: -s * 0.45))
            p.addCurve(to: c + CGPoint(x: s * 0.5, y: -s * 0.08), control1: c + CGPoint(x: s * 0.08, y: -s * 0.45), control2: c + CGPoint(x: s * 0.5, y: -s * 0.42))
            p.addCurve(to: c + CGPoint(x: 0, y: s * 0.38), control1: c + CGPoint(x: s * 0.5, y: s * 0.1), control2: c + CGPoint(x: s * 0.18, y: s * 0.18))
            p.closeSubpath()
        }
    }

    private static func drawParticles(_ sim: CatSim, _ g: Painter) {
        for part in sim.particles {
            let p = CGFloat((sim.time - part.born) / part.life)
            g.save()
            switch part.kind {
            case .keycap(let label):
                let pos = part.origin + CGPoint(x: part.drift * 10 * p, y: -26 * p)
                g.multiplyOpacity(Double(p < 0.65 ? 1 : max(0, (1 - p) / 0.35)))
                let pop = 0.75 + 0.25 * min(1, p * 6)
                let w = max(16, CGFloat(label.count) * 7 + 8) * pop, h = 16 * pop
                let r = rect(center: pos, w: w, h: h)
                g.fill(.roundedRect(r.offsetBy(dx: 0, dy: 1.8), 4), .color(ink))
                g.fill(.roundedRect(r, 4), .color(RGB(0xFFFFFF)))
                g.stroke(.roundedRect(r, 4), .color(ink), StrokeStyle2(1.4))
                g.text(label, center: pos, size: 9 * pop, color: ink)
            case .z:
                let pos = part.origin + CGPoint(x: 16 * p + 3 * sin(p * 8) + part.drift * 6, y: -40 * p)
                g.multiplyOpacity(Double(sin(.pi * p)))
                g.text("z", center: pos, size: 9 + 10 * p, color: RGB(0x4A5A80))
            case .heart:
                let pos = part.origin + CGPoint(x: part.drift * 10 * p, y: -28 * p)
                g.multiplyOpacity(Double(1 - p))
                g.fill(heartPath(pos, 10 + 4 * p), .color(RGB(0xF06C8B)))
            }
            g.restore()
        }
    }
}
