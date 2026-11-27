import SwiftUI

/// Desenha o gato inteiro num GraphicsContext, a partir do estado do CatSim.
enum CatRenderer {
    static let ink = RGB(0x2D2A2E)
    static let keyFace = RGB(0xF4F0E6)
    static let keyLit = RGB(0xFFC94D)
    static let keyAccent = RGB(0xF08A5D)

    static func draw(_ sim: CatSim, in base: inout GraphicsContext) {
        var ctx = base
        ctx.scaleBy(x: sim.scale, y: sim.scale)
        let c = sim.coat
        let t = sim.time

        // Respiração: o corpo estica a partir da base; ombros e cabeça acompanham.
        let b = CGFloat(sin(sim.breathPhase))
        let amp: CGFloat = 0.012 + 0.016 * sim.sleep.value
        let bodyScaleY = 1 + b * amp + 0.035 * sim.dream.value - 0.03 * sim.sleep.value
        let rise = (Geo.bodyBottom - Geo.shoulderL.y) * (bodyScaleY - 1)

        drawShadow(&ctx)
        drawTail(sim, &ctx)

        var bodyCtx = ctx
        bodyCtx.translateBy(x: Geo.cx, y: Geo.bodyBottom)
        bodyCtx.scaleBy(x: 1 - b * amp * 0.3, y: bodyScaleY)
        bodyCtx.translateBy(x: -Geo.cx, y: -Geo.bodyBottom)
        drawBody(c, &bodyCtx, outline: true)

        drawKeyboard(sim, &ctx)
        drawMouse(sim, &ctx)

        // Braços: contorno, depois o corpo de novo por cima (só acima do teclado), depois o preenchimento.
        let shL = Geo.shoulderL - CGPoint(x: 0, y: rise)
        let shR = Geo.shoulderR - CGPoint(x: 0, y: rise)
        let pL = pawPosition(sim.leftPaw, press: sim.leftPress.value)
        let pR = pawPosition(sim.rightPaw, press: sim.rightPress.value)
        for (s, p) in [(shL, pL), (shR, pR)] {
            ctx.stroke(armPath(s, p), with: .color(c.shade.color), style: StrokeStyle(lineWidth: 22.5, lineCap: .round))
        }
        var refill = bodyCtx
        refill.clip(to: Path(CGRect(x: 0, y: 0, width: Geo.size.width, height: KeyLayout.board.minY)))
        drawBody(c, &refill, outline: true)
        for (s, p) in [(shL, pL), (shR, pR)] {
            ctx.stroke(armPath(s, p), with: .color(c.base.color), style: StrokeStyle(lineWidth: 19.5, lineCap: .round))
        }
        drawPaw(at: pL, press: sim.leftPress.value, coat: c, &ctx)
        drawPaw(at: pR, press: sim.rightPress.value, coat: c, &ctx)

        // Cabeça
        var head = ctx
        head.translateBy(x: 0, y: sim.headLift.value - rise * 1.1)
        head.translateBy(x: Geo.neck.x, y: Geo.neck.y)
        head.rotate(by: .radians(Double(sim.headTilt.value + sim.shakeAngle)))
        head.translateBy(x: -Geo.neck.x, y: -Geo.neck.y)
        drawEars(sim, &head)
        drawHead(c, &head)
        drawFace(sim, &head, breath: b)

        drawParticles(sim, &ctx)
    }

    // MARK: - Partes

    private static func drawShadow(_ ctx: inout GraphicsContext) {
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 5))
            l.fill(Path(ellipseIn: CGRect(x: 44, y: 272, width: 280, height: 16)), with: .color(.black.opacity(0.18)))
        }
    }

    private static func tailPath(_ sim: CatSim) -> Path {
        let s = sim.sleep.value, d = sim.dream.value
        let w = CGFloat(sin(sim.tailPhase)) * (1 - 0.55 * d)
        let w2 = CGFloat(sin(sim.tailPhase + 0.9)) * (1 - 0.55 * d)
        let awake = [CGPoint(x: 200, y: 236), CGPoint(x: 252, y: 246),
                     CGPoint(x: 266 + w * 6, y: 196 + w * 10), CGPoint(x: 254 + w * 16, y: 166 + w2 * 6)]
        let asleep = [CGPoint(x: 200, y: 240), CGPoint(x: 240, y: 252),
                      CGPoint(x: 268, y: 246), CGPoint(x: 272, y: 222)]
        let p = zip(awake, asleep).map { $0.lerp($1, s) }
        return Path { path in
            path.move(to: p[0])
            path.addCurve(to: p[3], control1: p[1], control2: p[2])
        }
    }

    private static func drawTail(_ sim: CatSim, _ ctx: inout GraphicsContext) {
        let c = sim.coat
        let path = tailPath(sim)
        ctx.stroke(path, with: .color(c.shade.color), style: StrokeStyle(lineWidth: 15.5, lineCap: .round))
        ctx.stroke(path, with: .color(c.tailColor.color), style: StrokeStyle(lineWidth: 12.5, lineCap: .round))
        if c.pattern == .tabby {
            ctx.stroke(path, with: .color(c.accent.color), style: StrokeStyle(lineWidth: 12.5, lineCap: .butt, dash: [5, 8], dashPhase: 3))
        }
    }

    static func bodyPath() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 155, y: 136))
            p.addCurve(to: CGPoint(x: 213, y: 222), control1: CGPoint(x: 195, y: 136), control2: CGPoint(x: 215, y: 180))
            p.addCurve(to: CGPoint(x: 155, y: 256), control1: CGPoint(x: 212, y: 250), control2: CGPoint(x: 185, y: 256))
            p.addCurve(to: CGPoint(x: 97, y: 222), control1: CGPoint(x: 125, y: 256), control2: CGPoint(x: 98, y: 250))
            p.addCurve(to: CGPoint(x: 155, y: 136), control1: CGPoint(x: 95, y: 180), control2: CGPoint(x: 115, y: 136))
            p.closeSubpath()
        }
    }

    private static func drawBody(_ c: Coat, _ ctx: inout GraphicsContext, outline: Bool) {
        let body = bodyPath()
        ctx.fill(body, with: .color(c.base.color))
        var pat = ctx
        pat.clip(to: body)
        switch c.pattern {
        case .tuxedo, .bicolor:
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 155, y: 202), w: 58, h: 88)), with: .color(c.accent.color))
        case .tabby:
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 155, y: 210), w: 48, h: 74)), with: .color(c.accent2.color.opacity(0.7)))
            let stripes = Path { p in
                for (y, len) in [(184.0, 16.0), (200.0, 18.0), (216.0, 16.0)] as [(CGFloat, CGFloat)] {
                    p.move(to: CGPoint(x: 96, y: y)); p.addQuadCurve(to: CGPoint(x: 96 + len, y: y + 3), control: CGPoint(x: 104, y: y - 3))
                    p.move(to: CGPoint(x: 214, y: y)); p.addQuadCurve(to: CGPoint(x: 214 - len, y: y + 3), control: CGPoint(x: 206, y: y - 3))
                }
            }
            pat.stroke(stripes, with: .color(c.accent.color), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        case .calico:
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 122, y: 214), w: 52, h: 44)), with: .color(c.accent.color))
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 198, y: 196), w: 40, h: 38)), with: .color(c.accent2.color))
        case .siamese:
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 155, y: 250), w: 140, h: 60)),
                     with: .color(c.shade.color.opacity(0.25)))
        case .solid:
            break
        }
        if outline {
            ctx.stroke(body, with: .color(c.shade.color), lineWidth: 1.6)
        }
    }

    private static func armPath(_ shoulder: CGPoint, _ paw: CGPoint) -> Path {
        Path { p in
            p.move(to: shoulder)
            let mid = CGPoint(x: (shoulder.x + paw.x) / 2 + (paw.x < Geo.cx ? -3 : 3), y: (shoulder.y + paw.y) / 2)
            p.addQuadCurve(to: paw + CGPoint(x: 0, y: -3), control: mid)
        }
    }

    private static func pawPosition(_ s: Spring2, press: CGFloat) -> CGPoint {
        let lift = min(7, s.speed * 0.012)
        return CGPoint(x: s.value.x, y: s.value.y - lift + press * 2)
    }

    private static func drawPaw(at p: CGPoint, press: CGFloat, coat c: Coat, _ ctx: inout GraphicsContext) {
        let h = 15 * (1 - 0.15 * clamp(press, 0, 1))
        let r = rect(center: p, w: 23, h: h)
        ctx.fill(Path(ellipseIn: r), with: .color(c.paw.color))
        ctx.stroke(Path(ellipseIn: r), with: .color(c.shade.color), lineWidth: 1.6)
        let toes = Path { t in
            for dx in [-4.0, 4.0] as [CGFloat] {
                t.move(to: CGPoint(x: p.x + dx, y: r.maxY - 4.5))
                t.addLine(to: CGPoint(x: p.x + dx, y: r.maxY - 1.5))
            }
        }
        ctx.stroke(toes, with: .color(c.shade.color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    private static func drawKeyboard(_ sim: CatSim, _ ctx: inout GraphicsContext) {
        let board = KeyLayout.board
        ctx.fill(Path(roundedRect: board.offsetBy(dx: 0, dy: 4), cornerRadius: 8), with: .color(RGB(0x1C1A1D).color))
        ctx.fill(Path(roundedRect: board, cornerRadius: 8), with: .color(ink.color))
        for (i, slot) in KeyLayout.slots.enumerated() {
            let g = sim.keyGlow[i]
            let baseColor = slot.accent ? keyAccent : keyFace
            let face = baseColor.mix(keyLit, Double(g))
            let r = slot.rect.offsetBy(dx: 0, dy: g * 1.0)
            ctx.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: 1.3), cornerRadius: 1.8),
                     with: .color(face.mix(RGB(0x000000), 0.25).color))
            ctx.fill(Path(roundedRect: r, cornerRadius: 1.8), with: .color(face.color))
        }
    }

    private static func drawMouse(_ sim: CatSim, _ ctx: inout GraphicsContext) {
        let ctr = Geo.mouseCenter + sim.mouseJiggle.value
        let r = rect(center: ctr, w: 26, h: 38)
        let shell = Path(roundedRect: r, cornerRadius: 13)
        let cord = Path { p in
            p.move(to: CGPoint(x: ctr.x, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: ctr.x + 18, y: r.minY - 18), control: CGPoint(x: ctr.x + 2, y: r.minY - 16))
        }
        ctx.stroke(cord, with: .color(ink.color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        ctx.fill(shell, with: .color(keyFace.color))

        var inner = ctx
        inner.clip(to: shell)
        let split = r.minY + 15
        if sim.mouseButtons.contains(0) {
            inner.fill(Path(CGRect(x: r.minX, y: r.minY, width: 13, height: 15)), with: .color(keyLit.color))
        }
        if sim.mouseButtons.contains(1) {
            inner.fill(Path(CGRect(x: ctr.x, y: r.minY, width: 13, height: 15)), with: .color(keyLit.color))
        }
        let lines = Path { p in
            p.move(to: CGPoint(x: r.minX, y: split)); p.addLine(to: CGPoint(x: r.maxX, y: split))
            p.move(to: CGPoint(x: ctr.x, y: r.minY)); p.addLine(to: CGPoint(x: ctr.x, y: split))
        }
        inner.stroke(lines, with: .color(ink.color.opacity(0.6)), lineWidth: 1.2)

        // Rodinha: os sulcos deslizam com o scroll de verdade.
        let wheel = CGRect(x: ctr.x - 2.6, y: r.minY + 3.5, width: 5.2, height: 9)
        let wheelLit = sim.mouseButtons.contains(2)
        ctx.fill(Path(roundedRect: wheel, cornerRadius: 2.6), with: .color((wheelLit ? keyLit : ink).color))
        var w = ctx
        w.clip(to: Path(roundedRect: wheel, cornerRadius: 2.6))
        let phase = sim.wheelPhase.truncatingRemainder(dividingBy: 3)
        let ridges = Path { p in
            for k in -1...4 {
                let y = wheel.minY + CGFloat(k) * 3 + (phase < 0 ? phase + 3 : phase)
                p.move(to: CGPoint(x: wheel.minX, y: y)); p.addLine(to: CGPoint(x: wheel.maxX, y: y))
            }
        }
        w.stroke(ridges, with: .color(.white.opacity(0.55)), lineWidth: 0.9)

        ctx.stroke(shell, with: .color(ink.color), lineWidth: 2)
    }

    private static func earPath(left: Bool, inner: Bool) -> Path {
        let pts: [CGPoint] = inner
            ? [CGPoint(x: 109, y: 90), CGPoint(x: 115, y: 60), CGPoint(x: 135, y: 77)]
            : [CGPoint(x: 99, y: 100), CGPoint(x: 111, y: 46), CGPoint(x: 144, y: 74)]
        let m = left ? pts : pts.map { CGPoint(x: 2 * Geo.cx - $0.x, y: $0.y) }
        return Path { p in p.addLines(m); p.closeSubpath() }
    }

    private static func drawEars(_ sim: CatSim, _ ctx: inout GraphicsContext) {
        let c = sim.coat
        for left in [true, false] {
            var e = ctx
            let pivot = CGPoint(x: left ? 124 : 2 * Geo.cx - 124, y: 88)
            // No carinho as orelhas abaixam para fora; de vez em quando uma dá um tremelique.
            let flatten = sim.pet.value * 0.32 + sim.sleep.value * 0.12
            let angle = (left ? -flatten : flatten) + sim.earTwitchAngle(left: left) * (left ? -1 : 1)
            e.translateBy(x: pivot.x, y: pivot.y)
            e.rotate(by: .radians(Double(angle)))
            e.translateBy(x: -pivot.x, y: -pivot.y)
            let outer = earPath(left: left, inner: false)
            e.stroke(outer, with: .color(c.shade.color), style: StrokeStyle(lineWidth: 10, lineJoin: .round))
            e.fill(outer, with: .color(c.earColor(left: left).color))
            e.stroke(outer, with: .color(c.earColor(left: left).color), style: StrokeStyle(lineWidth: 7, lineJoin: .round))
            let inner = earPath(left: left, inner: true)
            e.fill(inner, with: .color(c.innerEar.color))
            e.stroke(inner, with: .color(c.innerEar.color), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        }
    }

    static func headPath() -> Path {
        Path { p in
            p.move(to: CGPoint(x: 155, y: 62))
            p.addCurve(to: CGPoint(x: 218, y: 118), control1: CGPoint(x: 192, y: 62), control2: CGPoint(x: 218, y: 84))
            p.addCurve(to: CGPoint(x: 155, y: 163), control1: CGPoint(x: 218, y: 148), control2: CGPoint(x: 192, y: 163))
            p.addCurve(to: CGPoint(x: 92, y: 118), control1: CGPoint(x: 118, y: 163), control2: CGPoint(x: 92, y: 148))
            p.addCurve(to: CGPoint(x: 155, y: 62), control1: CGPoint(x: 92, y: 84), control2: CGPoint(x: 118, y: 62))
            p.closeSubpath()
        }
    }

    private static func drawHead(_ c: Coat, _ ctx: inout GraphicsContext) {
        let head = headPath()
        ctx.fill(head, with: .color(c.base.color))
        var pat = ctx
        pat.clip(to: head)
        switch c.pattern {
        case .tuxedo:
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 155, y: 144), w: 62, h: 42)), with: .color(c.accent.color))
        case .bicolor:
            let blaze = Path { p in
                p.move(to: CGPoint(x: 155, y: 98))
                p.addLine(to: CGPoint(x: 168, y: 132)); p.addLine(to: CGPoint(x: 142, y: 132)); p.closeSubpath()
            }
            pat.fill(blaze, with: .color(c.accent.color))
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 155, y: 144), w: 64, h: 42)), with: .color(c.accent.color))
        case .tabby:
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 155, y: 142), w: 50, h: 30)), with: .color(c.accent2.color))
            let forehead = Path { p in
                p.move(to: CGPoint(x: 144, y: 70)); p.addLine(to: CGPoint(x: 147, y: 88))
                p.move(to: CGPoint(x: 155, y: 66)); p.addLine(to: CGPoint(x: 155, y: 90))
                p.move(to: CGPoint(x: 166, y: 70)); p.addLine(to: CGPoint(x: 163, y: 88))
            }
            pat.stroke(forehead, with: .color(c.accent.color), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            let cheeks = Path { p in
                for (y, len) in [(118.0, 14.0), (128.0, 12.0)] as [(CGFloat, CGFloat)] {
                    p.move(to: CGPoint(x: 92, y: y)); p.addLine(to: CGPoint(x: 92 + len, y: y + 2))
                    p.move(to: CGPoint(x: 218, y: y)); p.addLine(to: CGPoint(x: 218 - len, y: y + 2))
                }
            }
            pat.stroke(cheeks, with: .color(c.accent.color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        case .siamese:
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 155, y: 130), w: 104, h: 84)),
                     with: .radialGradient(Gradient(colors: [c.accent.color, c.accent.color.opacity(0.85), c.accent.color.opacity(0)]),
                                           center: CGPoint(x: 155, y: 134), startRadius: 6, endRadius: 50))
        case .calico:
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 118, y: 76), w: 52, h: 46)), with: .color(c.accent.color))
            pat.fill(Path(ellipseIn: rect(center: CGPoint(x: 194, y: 76), w: 46, h: 40)), with: .color(c.accent2.color))
        case .solid:
            break
        }
        ctx.stroke(head, with: .color(c.shade.color), lineWidth: 1.8)
    }

    private static func drawFace(_ sim: CatSim, _ ctx: inout GraphicsContext, breath b: CGFloat) {
        let c = sim.coat
        let pet = sim.pet.value

        // Bochechas coradas (mais fortes no carinho)
        for x in [121.0, 189.0] as [CGFloat] {
            ctx.fill(Path(ellipseIn: rect(center: CGPoint(x: x, y: 131), w: 16, h: 8)),
                     with: .color(RGB(0xF28C9C).color.opacity(Double(0.22 + 0.5 * pet))))
        }

        for (center, left) in [(Geo.eyeL, true), (Geo.eyeR, false)] {
            drawEye(sim, center: center, left: left, &ctx)
        }

        // Nariz e boca
        let nose = Path { p in
            p.addLines([CGPoint(x: 150.5, y: 128), CGPoint(x: 159.5, y: 128), CGPoint(x: 155, y: 133.5)]); p.closeSubpath()
        }
        let noseColor = c.pattern == .siamese ? RGB(0x3A2A22) : RGB(0xE88A9A)
        ctx.fill(nose, with: .color(noseColor.color))
        ctx.stroke(nose, with: .color(noseColor.color), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        let smile = 1 + pet * 0.8
        let mouth = Path { p in
            p.move(to: CGPoint(x: 155, y: 134)); p.addLine(to: CGPoint(x: 155, y: 137))
            p.addQuadCurve(to: CGPoint(x: 155 - 7 * smile, y: 139), control: CGPoint(x: 155 - 3, y: 141 + pet))
            p.move(to: CGPoint(x: 155, y: 137))
            p.addQuadCurve(to: CGPoint(x: 155 + 7 * smile, y: 139), control: CGPoint(x: 155 + 3, y: 141 + pet))
        }
        ctx.stroke(mouth, with: .color(c.mouthLine.color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

        // Bigodes: tremem de leve quando ronrona no carinho
        let purr = CGFloat(sin(sim.time * 38)) * 0.9 * pet
        let whiskers = Path { p in
            for (y0, y1, len) in [(133.0, 127.0, 30.0), (137.0, 138.0, 32.0), (141.0, 148.0, 28.0)] as [(CGFloat, CGFloat, CGFloat)] {
                p.move(to: CGPoint(x: 129, y: y0)); p.addLine(to: CGPoint(x: 129 - len, y: y1 + purr))
                p.move(to: CGPoint(x: 181, y: y0)); p.addLine(to: CGPoint(x: 181 + len, y: y1 - purr))
            }
        }
        ctx.stroke(whiskers, with: .color(c.whisker.color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

        // Bolha de ronco: enche e esvazia com a respiração
        if sim.sleep.value > 0.6 {
            let k = (sim.sleep.value - 0.6) / 0.4
            let r = (2.5 + 5 * (0.5 + 0.5 * b)) * k
            let ctr = CGPoint(x: 161 + r * 0.7, y: 133 + r * 0.3)
            ctx.fill(Path(ellipseIn: rect(center: ctr, w: r * 2, h: r * 2)), with: .color(RGB(0xBFE3F5).color.opacity(0.55)))
            ctx.stroke(Path(ellipseIn: rect(center: ctr, w: r * 2, h: r * 2)), with: .color(.white.opacity(0.85)), lineWidth: 0.9)
            ctx.fill(Path(ellipseIn: rect(center: ctr + CGPoint(x: -r * 0.35, y: -r * 0.35), w: r * 0.5, h: r * 0.5)),
                     with: .color(.white.opacity(0.9)))
        }
    }

    private static func drawEye(_ sim: CatSim, center p: CGPoint, left: Bool, _ ctx: inout GraphicsContext) {
        let c = sim.coat
        // Carinho: olhinhos de "^ ^"
        if sim.pet.value > 0.5 {
            let squint = Path { s in
                s.move(to: CGPoint(x: p.x - 9, y: p.y + 3))
                s.addQuadCurve(to: CGPoint(x: p.x + 9, y: p.y + 3), control: CGPoint(x: p.x, y: p.y - 8))
            }
            ctx.stroke(squint, with: .color(c.eyeLine.color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            return
        }
        let o = sim.eyeOpenness
        if o < 0.1 {
            let closed = Path { s in
                s.move(to: CGPoint(x: p.x - 9, y: p.y))
                s.addQuadCurve(to: CGPoint(x: p.x + 9, y: p.y), control: CGPoint(x: p.x, y: p.y + 6))
            }
            ctx.stroke(closed, with: .color(c.eyeLine.color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            return
        }
        let r = Geo.eyeRadius + sim.dream.value
        let circle = Path(ellipseIn: rect(center: p, w: r * 2, h: r * 2))
        ctx.fill(circle, with: .color(c.eye.color))
        var e = ctx
        e.clip(to: circle)
        let round = sim.pupilRound.value
        let pw = lerp(4.5, 11.5, round) + sim.dream.value * 1.5
        let ph = lerp(19, 14, round) + sim.dream.value * 1.5
        let pc = p + sim.pupil.value * (r / Geo.eyeRadius)
        e.fill(Path(ellipseIn: rect(center: pc, w: pw, h: ph)), with: .color(RGB(0x161616).color))
        e.fill(Path(ellipseIn: rect(center: pc + CGPoint(x: -3.5, y: -4.5), w: 5.4, h: 5.4)), with: .color(.white))
        e.fill(Path(ellipseIn: rect(center: pc + CGPoint(x: 3, y: 3.5), w: 2.2, h: 2.2)), with: .color(.white.opacity(0.85)))
        // Pálpebra: desce do topo conforme o olho fecha (piscada, sonolência)
        if o < 0.98 {
            let lidY = p.y - r + 2 * r * (1 - o)
            let lid = Path { s in
                s.move(to: CGPoint(x: p.x - r - 1, y: p.y - r - 1))
                s.addLine(to: CGPoint(x: p.x + r + 1, y: p.y - r - 1))
                s.addLine(to: CGPoint(x: p.x + r + 1, y: lidY))
                s.addQuadCurve(to: CGPoint(x: p.x - r - 1, y: lidY), control: CGPoint(x: p.x, y: lidY + 3))
                s.closeSubpath()
            }
            e.fill(lid, with: .color(c.lidColor.color))
            let edge = Path { s in
                s.move(to: CGPoint(x: p.x - r - 1, y: lidY))
                s.addQuadCurve(to: CGPoint(x: p.x + r + 1, y: lidY), control: CGPoint(x: p.x, y: lidY + 3))
            }
            e.stroke(edge, with: .color(c.eyeLine.color), lineWidth: 1.6)
        }
        ctx.stroke(circle, with: .color(c.shade.color.opacity(0.7)), lineWidth: 1.2)
    }

    private static func drawParticles(_ sim: CatSim, _ ctx: inout GraphicsContext) {
        for part in sim.particles {
            let p = CGFloat((sim.time - part.born) / part.life)
            var l = ctx
            switch part.kind {
            case .keycap(let label):
                let pos = part.origin + CGPoint(x: part.drift * 10 * p, y: -26 * p)
                l.opacity = Double(p < 0.65 ? 1 : max(0, (1 - p) / 0.35))
                let pop = 0.75 + 0.25 * min(1, p * 6)
                let w = max(16, CGFloat(label.count) * 7 + 8) * pop, h = 16 * pop
                let r = rect(center: pos, w: w, h: h)
                l.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: 1.8), cornerRadius: 4), with: .color(ink.color))
                l.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(.white))
                l.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(ink.color), lineWidth: 1.4)
                l.draw(Text(label).font(.system(size: 9 * pop, weight: .bold, design: .rounded)).foregroundColor(ink.color), at: pos)
            case .z:
                let pos = part.origin + CGPoint(x: 16 * p + 3 * sin(p * 8) + part.drift * 6, y: -40 * p)
                l.opacity = Double(sin(.pi * p))
                l.draw(Text("z").font(.system(size: 9 + 10 * p, weight: .heavy, design: .rounded))
                    .foregroundColor(RGB(0x4A5A80).color), at: pos)
            case .heart:
                let pos = part.origin + CGPoint(x: part.drift * 10 * p, y: -28 * p)
                l.opacity = Double(1 - p)
                l.draw(Text("♥").font(.system(size: 9 + 4 * p, weight: .bold))
                    .foregroundColor(RGB(0xF06C8B).color), at: pos)
            }
        }
    }
}
