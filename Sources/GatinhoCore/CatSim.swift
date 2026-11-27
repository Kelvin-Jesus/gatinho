#if GATINHO_WEB
import WASILibc
#else
import Foundation
#endif

/// Mola amortecida 2D: toda posição animada persegue um alvo com ela.
public struct Spring2 {
    public var value: CGPoint
    var velocity = CGPoint.zero

    mutating func step(to t: CGPoint, dt: CGFloat, k: CGFloat, zeta: CGFloat = 0.8) {
        let c = 2 * k.squareRoot() * zeta
        velocity.x += (k * (t.x - value.x) - c * velocity.x) * dt
        velocity.y += (k * (t.y - value.y) - c * velocity.y) * dt
        value.x += velocity.x * dt
        value.y += velocity.y * dt
    }

    var speed: CGFloat { (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot() }
}

public struct Spring1 {
    public var value: CGFloat
    var velocity: CGFloat = 0

    mutating func step(to t: CGFloat, dt: CGFloat, k: CGFloat, zeta: CGFloat = 1) {
        let c = 2 * k.squareRoot() * zeta
        velocity += (k * (t - value) - c * velocity) * dt
        value += velocity * dt
    }
}

struct Particle {
    enum Kind { case keycap(String), z, heart }
    let kind: Kind
    let origin: CGPoint
    let born: TimeInterval
    let life: TimeInterval
    let drift: CGFloat
}

public enum Mood { case awake, daydream, sleeping }

/// Bolinha de lã que rola na mesa, na frente do teclado (só no eixo x).
struct YarnBall {
    static let y: CGFloat = 287
    static let radius: CGFloat = 8
    var x: CGFloat
    var vx: CGFloat
    var spin: CGFloat = 0
    var leaving = false
}

/// Estado do gato. Os eventos de teclado/mouse mudam os alvos; `step` anima tudo a cada quadro.
/// Teclas só ficam em memória enquanto estão pressionadas: nada é gravado.
///
/// Coordenadas de tela: y para baixo, na mesma unidade de `windowFrame` e `pointer`
/// (pontos no Mac, pixels no Windows/Linux). `screenScale` converte pontos do desenho para elas.
public final class CatSim {
    public var coat: Coat
    public var showKeyLabels = true
    public var labelStyle: LabelStyle = .mac

    public var windowFrame: CGRect = .zero
    public var pointer: CGPoint = .zero
    public var screenScale: CGFloat = 1

    public var daydreamAfter: TimeInterval = 15
    public var sleepAfter: TimeInterval = 40

    // Entrada
    private var heldKeys: [UInt16: (slot: Int, paw: Paw, at: TimeInterval, seen: TimeInterval)] = [:]
    private var lastKey: [Paw: (slot: Int, at: TimeInterval)] = [:]
    private var scheduledReleases: [(code: UInt16, at: TimeInterval)] = []
    private(set) var keyGlow = [CGFloat](repeating: 0, count: KeyLayout.slots.count)
    private(set) var mouseButtons: Set<Int> = []
    private var lastMouseActivity: TimeInterval = -100
    private var lastActivity: TimeInterval
    private var lastPointer: CGPoint?
    private(set) var wheelPhase: CGFloat = 0
    public private(set) var petting = false
    private var petPoint: CGPoint = .zero
    private var petStart: TimeInterval = 0
    /// Ronronando: começa depois de um instante de carinho e para quando a mão sai.
    public private(set) var purring = false
    /// Chamado quando o ronronar começa ou para (cada sistema liga o som aqui).
    public var onPurrChange: ((Bool) -> Void)?

    // Animação
    private(set) var leftPaw = Spring2(value: Geo.restL)
    private(set) var rightPaw = Spring2(value: Geo.restR)
    private(set) var leftPress = Spring1(value: 0)
    private(set) var rightPress = Spring1(value: 0)
    private(set) var pupil = Spring2(value: .zero)
    private(set) var pupilRound = Spring1(value: 0)
    private(set) var headTilt = Spring1(value: 0)
    private(set) var headLift = Spring1(value: 0)
    private(set) var sleep = Spring1(value: 0)
    private(set) var dream = Spring1(value: 0)
    private(set) var pet = Spring1(value: 0)
    private(set) var purr = Spring1(value: 0)
    private(set) var mouseJiggle = Spring2(value: .zero)
    private var jiggleTarget = CGPoint.zero

    private var blinkStart: TimeInterval = -10
    private var blinkDuration: TimeInterval = 0.16
    private var nextBlink: TimeInterval = 0
    private(set) var shakeStart: TimeInterval = -10
    private(set) var earTwitchStart: TimeInterval = -10
    private(set) var earTwitchLeft = true
    private var nextEarTwitch: TimeInterval = 0
    private(set) var particles: [Particle] = []
    private var lastZ: TimeInterval = 0
    private var lastHeart: TimeInterval = 0

    // Gato parado: coruja, caça ao cursor, bolinha, lambida, pata nos olhos e espreguiçada.
    private var lastTyping: TimeInterval = -100
    private var lastPointerMove: TimeInterval = -100
    private(set) var owlStart: TimeInterval = -100
    private var nextOwlChance: TimeInterval = 0
    private var swatStart: TimeInterval = -100
    private var swatPaw: Paw = .right
    private var swatTarget: CGPoint = .zero
    private var swatArmed = false
    private(set) var ball: YarnBall?
    private var ballAllowedAt: TimeInterval = 0
    private var nextBat: TimeInterval = 0
    private var batStart: TimeInterval = -100
    private var batPaw: Paw = .left
    private var batX: CGFloat = 0
    private var batKicked = true
    private var stretchStart: TimeInterval = -100
    private var napCoversEyes = false
    /// Para as gravações: fixa se o próximo cochilo é com a pata nos olhos.
    var forceCoverEyes: Bool?
    private(set) var owl = Spring1(value: 0)
    private(set) var crouch = Spring1(value: 0)
    private(set) var cover = Spring1(value: 0)
    private(set) var yawn = Spring1(value: 0)
    private(set) var lick = Spring1(value: 0)
    /// Fase da lambida na pata (sobe e desce ~2 vezes por segundo).
    public private(set) var lickPhase: Double = 0

    public private(set) var time: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    public private(set) var mood: Mood = .awake

    /// Fases acumuladas quadro a quadro. Nunca calcular `sin(tempoAbsoluto * velocidade)`
    /// com velocidade variável: com o tempo na casa de 10^8 s, qualquer mudança de
    /// velocidade faz a fase saltar e a animação "enlouquece".
    public private(set) var tailPhase: Double = 0
    public private(set) var breathPhase: Double = 0
    /// Fase da vibração do ronronar (~24 vibrações por segundo).
    public private(set) var purrPhase: Double = 0

    public init(coat: Coat) {
        self.coat = coat
        let now = Date().timeIntervalSinceReferenceDate
        lastActivity = now
        nextBlink = now + 2
        nextEarTwitch = now + 6
        nextOwlChance = now + 10
        ballAllowedAt = now
    }

    /// Relógio dos eventos. O gravador de GIFs troca por um relógio simulado.
    public var clock: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    private var now: TimeInterval { clock() }

    // MARK: - Eventos

    public func keyDown(code: UInt16, label: String, isRepeat: Bool) {
        let t = now
        markActivity(t)
        lastTyping = t
        if var b = ball, !b.leaving {
            // De volta ao trabalho: a bolinha rola pra fora pelo lado mais perto.
            b.leaving = true
            b.vx = b.x < Geo.cx ? -320 : 320
            ball = b
        }
        let slot = KeyLayout.slotIndex(for: code)
        let paw = KeyLayout.slots[slot].paw
        if let held = heldKeys[code] {
            heldKeys[code] = (held.slot, held.paw, held.at, t)
        } else {
            heldKeys[code] = (slot, paw, t, t)
        }
        lastKey[paw] = (slot, t)
        keyGlow[slot] = 1
        if !isRepeat {
            if paw == .left { leftPress.velocity += 6 } else { rightPress.velocity += 6 }
            if showKeyLabels, !label.isEmpty {
                let c = KeyLayout.slots[slot].center
                particles.append(Particle(kind: .keycap(label), origin: CGPoint(x: c.x, y: c.y - 22),
                                          born: t, life: 0.75, drift: CGFloat.random(in: -1...1)))
            }
        }
    }

    public func keyUp(code: UInt16) {
        if let h = heldKeys.removeValue(forKey: code) { lastKey[h.paw] = (h.slot, now) }
    }

    public func isHeld(_ code: UInt16) -> Bool { heldKeys[code] != nil }

    /// Modificadores no macOS chegam como flagsChanged, sem "solto" explícito: alterna.
    public func modifierChanged(code: UInt16) {
        let label = KeyLabels.label(code: code, style: labelStyle)
        if code == 57 { // Caps Lock: trata como um toque rápido
            keyDown(code: code, label: label, isRepeat: false)
            scheduledReleases.append((code, now + 0.15))
            return
        }
        if heldKeys[code] != nil { keyUp(code: code) }
        else { keyDown(code: code, label: label, isRepeat: false) }
    }

    /// 0 = esquerdo, 1 = direito, 2 = meio.
    public func mouseButton(_ b: Int, down: Bool) {
        let t = now
        if down { mouseButtons.insert(b) } else { mouseButtons.remove(b) }
        lastMouseActivity = t
        markActivity(t)
        if down { rightPress.velocity += 4 }
    }

    public func scroll(_ dy: CGFloat) {
        let t = now
        wheelPhase += dy
        lastMouseActivity = t
        markActivity(t)
    }

    public func beginPet(at p: CGPoint) {
        if !petting { petStart = now }
        petting = true; petPoint = p; markActivity(now)
    }
    public func movePet(to p: CGPoint) { petPoint = p; markActivity(now) }
    public func endPet() { petting = false }

    /// Um clique na bolinha (em pontos do desenho): ela quica para longe do clique.
    @discardableResult
    public func poke(at p: CGPoint) -> Bool {
        guard var b = ball, !b.leaving else { return false }
        let dx = b.x - p.x, dy = YarnBall.y - p.y
        guard dx * dx + dy * dy <= (YarnBall.radius + 6) * (YarnBall.radius + 6) else { return false }
        b.vx = (dx >= 0 ? 1 : -1) * CGFloat.random(in: 170...240)
        ball = b
        owlStart = now // "o que foi isso?"
        return true
    }
    public var hasBall: Bool { ball != nil }

    private func markActivity(_ t: TimeInterval) {
        if mood == .sleeping || sleep.value > 0.45 {
            if t - shakeStart > 1 {
                shakeStart = t
                stretchStart = t + 0.7 // sacode a cabeça, depois se espreguiça e boceja
            }
        } else if mood == .daydream {
            blinkStart = t
            blinkDuration = 0.18
        }
        lastActivity = t
        if mood != .awake { mood = .awake }
    }

    // MARK: - Quadro

    public func step(to t: TimeInterval) {
        if lastTime == 0 { lastTime = t }
        let dt = CGFloat(min(max(t - lastTime, 0), 0.05))
        lastTime = t
        time = t

        for r in scheduledReleases where r.at <= t { keyUp(code: r.code) }
        scheduledReleases.removeAll { $0.at <= t }

        pollPointer(t)
        dropStaleKeys(t)

        let idle = t - lastActivity
        let newMood: Mood = petting ? .awake : idle > sleepAfter ? .sleeping : idle > daydreamAfter ? .daydream : .awake
        if newMood == .sleeping, mood != .sleeping { napCoversEyes = forceCoverEyes ?? (Double.random(in: 0...1) < 0.45) }
        mood = newMood

        updateHunt(t)
        updateBall(t, dt: dt, idle: idle)
        let owlT: CGFloat = owlActive ? 1 : 0
        let stalking = isStalking(t)
        let crouchT: CGFloat = stalking ? 1 : 0
        let licking = mood == .daydream && idle > sleepAfter - 6 && idle < sleepAfter - 0.8
        let lickT: CGFloat = licking ? 1 : 0
        let coverT: CGFloat = mood == .sleeping && napCoversEyes && sleep.value > 0.7 ? 1 : 0
        let stretchE = stretchEnvelope
        let yawnT: CGFloat = stretchE > 0.25 ? 1 : 0

        let (lt, lp) = pawTarget(.left, t)
        let (rt, rp) = pawTarget(.right, t)
        let (pupilT, roundT, tiltT) = gazeTargets()
        var liftT: CGFloat = petting ? 3 : mood == .sleeping ? 10 : mood == .daydream ? -6 : 0
        liftT += 9 * crouchT - 8 * stretchE
        let sleepT: CGFloat = mood == .sleeping ? 1 : 0
        let dreamT: CGFloat = mood == .daydream ? 1 : 0
        let petT: CGFloat = petting ? 1 : 0
        let shouldPurr = petting && t - petStart > 0.35
        if shouldPurr != purring {
            purring = shouldPurr
            onPurrChange?(purring)
        }
        let purrT: CGFloat = purring ? 1 : 0

        let n = max(1, Int((dt / (1.0 / 240)).rounded(.up)))
        let h = dt / CGFloat(n)
        for _ in 0..<n {
            leftPaw.step(to: lt, dt: h, k: 900, zeta: 0.72)
            rightPaw.step(to: rt, dt: h, k: 900, zeta: 0.72)
            leftPress.step(to: lp, dt: h, k: 1400, zeta: 0.55)
            rightPress.step(to: rp, dt: h, k: 1400, zeta: 0.55)
            pupil.step(to: pupilT, dt: h, k: 220, zeta: 0.9)
            pupilRound.step(to: roundT, dt: h, k: 90)
            headTilt.step(to: tiltT, dt: h, k: 60, zeta: 0.7)
            headLift.step(to: liftT, dt: h, k: 40, zeta: 0.8)
            sleep.step(to: sleepT, dt: h, k: sleepT > sleep.value ? 2.5 : 90)
            dream.step(to: dreamT, dt: h, k: 6)
            pet.step(to: petT, dt: h, k: 140)
            purr.step(to: purrT, dt: h, k: purring ? 20 : 60)
            mouseJiggle.step(to: jiggleTarget, dt: h, k: 500, zeta: 0.6)
            owl.step(to: owlT, dt: h, k: 70)
            crouch.step(to: crouchT, dt: h, k: 50)
            lick.step(to: lickT, dt: h, k: 40)
            cover.step(to: coverT, dt: h, k: 12)
            yawn.step(to: yawnT, dt: h, k: 45)
        }

        tailPhase = (tailPhase + Double(dt) * tailSpeed).truncatingRemainder(dividingBy: 2 * .pi)
        breathPhase = (breathPhase + Double(dt) * 2 * .pi / breathPeriod).truncatingRemainder(dividingBy: 2 * .pi)
        purrPhase = (purrPhase + Double(dt) * 2 * .pi * 24).truncatingRemainder(dividingBy: 2 * .pi)
        lickPhase = (lickPhase + Double(dt) * 2 * .pi * 2.2).truncatingRemainder(dividingBy: 2 * .pi)

        updateBlinkAndTwitch(t)
        updateParticles(t)

        for i in keyGlow.indices where keyGlow[i] > 0 {
            let held = heldKeys.values.contains { $0.slot == i }
            keyGlow[i] = held ? 1 : max(0, keyGlow[i] - dt * 3.5)
        }
    }

    private func pollPointer(_ t: TimeInterval) {
        let m = pointer
        let last = lastPointer ?? m
        lastPointer = m
        let dx = m.x - last.x, dy = m.y - last.y
        let units = 1 / max(screenScale, 0.01)
        if abs(dx) + abs(dy) > 0.5, !petting {
            // Algo se mexeu depois de um tempo parado: cara de coruja.
            let wasIdle = t - lastActivity
            if mood != .sleeping, wasIdle > 4, t - owlStart > 6, t - lastTyping > 3 { owlStart = t }
            lastPointerMove = t
            swatArmed = true
            lastMouseActivity = t
            markActivity(t)
        }
        jiggleTarget = CGPoint(x: clamp(dx * units * 0.35, -5, 5), y: clamp(dy * units * 0.35, -4, 4))
    }

    private func dropStaleKeys(_ t: TimeInterval) {
        for (code, k) in heldKeys where t - k.seen > 10 { heldKeys.removeValue(forKey: code) }
    }

    private func pawPoint(onKey slot: Int) -> CGPoint {
        let c = KeyLayout.slots[slot].center
        return CGPoint(x: c.x, y: c.y - 4)
    }

    private func pawTarget(_ paw: Paw, _ t: TimeInterval) -> (CGPoint, CGFloat) {
        if let held = heldKeys.values.filter({ $0.paw == paw }).max(by: { $0.at < $1.at }) {
            return (pawPoint(onKey: held.slot), 1)
        }
        if let last = lastKey[paw], t - last.at < 0.4 {
            return (pawPoint(onKey: last.slot) + CGPoint(x: 0, y: -5), 0)
        }
        if paw == swatPaw, t - swatStart < 0.28 { return (swatTarget, 0) }
        if paw == batPaw, t - batStart < 0.22 { return (CGPoint(x: batX, y: 280), 0.6) }
        let e = stretchEnvelope
        if e > 0.02 {
            let rest = paw == .left ? Geo.restL : Geo.restR
            let out = paw == .left ? CGPoint(x: 86, y: 238) : CGPoint(x: 224, y: 238)
            return (rest.lerp(out, e), 0)
        }
        if paw == .left, lick.value > 0.05, mood == .daydream {
            return (CGPoint(x: 136, y: 147 + CGFloat(sin(lickPhase)) * 3), 0)
        }
        if paw == .left, mood == .sleeping, napCoversEyes, sleep.value > 0.7 {
            return (CGPoint(x: Geo.eyeL.x + 2, y: Geo.eyeL.y + 6 + headLift.value), 0)
        }
        if paw == .right, crouch.value > 0.4 { return (Geo.restR + CGPoint(x: 4, y: 2), 0) }
        if paw == .right, t - lastMouseActivity < 2.5 {
            return (Geo.mouseGrip + mouseJiggle.value, mouseButtons.isEmpty ? 0 : 0.7)
        }
        let rest = paw == .left ? Geo.restL : Geo.restR
        if mood == .sleeping { return (rest + CGPoint(x: paw == .left ? 5 : -5, y: 1), 0) }
        return (rest, 0)
    }

    /// Para onde os olhos olham, se a pupila fica redonda e quanto a cabeça inclina.
    private func gazeTargets() -> (CGPoint, CGFloat, CGFloat) {
        switch mood {
        case .sleeping: return (.zero, 1, 0.13)
        case .daydream: return (CGPoint(x: 0, y: -1.5), 1, 0)
        case .awake: break
        }
        if petting {
            let side = clamp((petPoint.x - Geo.headCenter.x) / 60, -1, 1)
            return (.zero, 1, side * 0.17)
        }
        if owlActive {
            // Inclina para um lado, para o outro, e fica olhando de pupila redonda.
            let s = time - owlStart
            let tilt: CGFloat = s < 0.8 ? 0.2 : s < 1.6 ? -0.2 : 0.06
            let (dir, _, _) = gazeAtPointer()
            return (dir, 1, tilt)
        }
        if let b = ball, isPlaying(time) {
            let mid = CGPoint(x: (Geo.eyeL.x + Geo.eyeR.x) / 2, y: Geo.eyeL.y)
            let dx = b.x - mid.x, dy = YarnBall.y - mid.y
            let d = max(0.001, (dx * dx + dy * dy).squareRoot())
            return (CGPoint(x: dx / d, y: dy / d * 0.8) * 4.5, 0.85, clamp(dx / 1200, -0.1, 0.1))
        }
        return gazeAtPointer()
    }

    private func gazeAtPointer() -> (CGPoint, CGFloat, CGFloat) {
        let s = max(screenScale, 0.01)
        let mid = CGPoint(x: (Geo.eyeL.x + Geo.eyeR.x) / 2, y: Geo.eyeL.y)
        let eye = CGPoint(x: windowFrame.minX + mid.x * s, y: windowFrame.minY + mid.y * s)
        // Distâncias em pontos do desenho, para valerem igual em qualquer escala/DPI.
        let dx = (pointer.x - eye.x) / s, dy = (pointer.y - eye.y) / s
        let d = (dx * dx + dy * dy).squareRoot()
        let mag = min(1, d / 220) * 4.5
        let dir = d > 0.001 ? CGPoint(x: dx / d, y: dy / d * 0.8) : .zero
        return (dir * mag, d < 210 ? 1 : 0, clamp(dx / 2500, -0.07, 0.07))
    }

    // MARK: - Gato parado

    var owlActive: Bool { time - owlStart >= 0 && time - owlStart < 2.6 }

    /// Cursor em pontos do desenho (pode cair fora de 0...330 x 0...300).
    private var designPointer: CGPoint {
        let s = max(screenScale, 0.01)
        return CGPoint(x: (pointer.x - windowFrame.minX) / s, y: (pointer.y - windowFrame.minY) / s)
    }

    private var pointerNear: Bool {
        let p = designPointer
        return p.x > -110 && p.x < Geo.size.width + 110 && p.y > -90 && p.y < Geo.size.height + 40
            && !Geo.hitsHead(p)
    }

    /// Abaixado, de olho no cursor parado ali perto.
    private func isStalking(_ t: TimeInterval) -> Bool {
        mood == .awake && !petting && !owlActive && t - lastTyping > 2
            && t - lastPointerMove < 6 && pointerNear
    }

    private func updateHunt(_ t: TimeInterval) {
        // O cursor parou perto: ele mira e dá uma patada (uma por parada, no máximo a cada 3 s).
        guard swatArmed, crouch.value > 0.6, isStalking(t), t - lastPointerMove > 0.9, t - swatStart > 3 else { return }
        swatArmed = false
        guard Double.random(in: 0...1) < 0.75 else { return }
        let p = designPointer
        swatPaw = p.x < Geo.cx ? .left : .right
        let shoulder = swatPaw == .left ? Geo.shoulderL : Geo.shoulderR
        let dx = p.x - shoulder.x, dy = p.y - shoulder.y
        let d = max(0.001, (dx * dx + dy * dy).squareRoot())
        let reach = min(d, 95)
        swatTarget = CGPoint(x: clamp(shoulder.x + dx / d * reach, 14, Geo.size.width - 14),
                             y: clamp(shoulder.y + dy / d * reach, 24, Geo.size.height - 14))
        swatStart = t
    }

    /// Brincando com a bolinha: acordado, sem ninguém digitando nem mexendo no mouse agora.
    private func isPlaying(_ t: TimeInterval) -> Bool {
        mood == .awake && !petting && !owlActive && crouch.value < 0.3
            && t - lastTyping > 3 && t - lastActivity > 2.5
    }

    private func updateBall(_ t: TimeInterval, dt: CGFloat, idle: TimeInterval) {
        if ball == nil {
            // Depois de uns segundos à toa, uma bolinha de lã entra rolando pela esquerda.
            if mood == .awake, !petting, idle > 7, t - lastTyping > 7, t >= ballAllowedAt {
                ball = YarnBall(x: -12, vx: 180)
                nextBat = t + 1.2
            }
            return
        }
        guard var b = ball else { return }
        b.x += b.vx * dt
        b.spin += b.vx * dt / YarnBall.radius
        let friction = 150 * dt
        b.vx = abs(b.vx) <= friction ? 0 : b.vx - (b.vx > 0 ? friction : -friction)
        if b.leaving {
            if b.x < -24 || b.x > Geo.size.width + 24 { ball = nil; ballAllowedAt = t + 45; return }
            if abs(b.vx) < 120 { b.vx = b.vx < 0 || b.x < Geo.cx ? -320 : 320 }
        } else {
            let lo: CGFloat = 12, hi = Geo.size.width - 12
            if b.x < lo, b.vx < 0 { b.x = lo; b.vx = -b.vx * 0.55 }
            if b.x > hi, b.vx > 0 { b.x = hi; b.vx = -b.vx * 0.55 }
        }
        // A patada só empurra a bolinha quando a pata chega nela.
        if !batKicked, t - batStart > 0.11 {
            batKicked = true
            if abs(b.x - batX) < 16 {
                var dir: CGFloat = Bool.random() ? 1 : -1
                if b.x < 90 { dir = 1 } else if b.x > 220 { dir = -1 }
                b.vx = dir * CGFloat.random(in: 70...170)
            }
        }
        if !b.leaving, isPlaying(t), t >= nextBat, abs(b.vx) < 40 {
            let paw: Paw = b.x < Geo.cx ? .left : .right
            let reach: ClosedRange<CGFloat> = paw == .left ? 55...165 : 145...255
            if reach.contains(b.x) {
                batPaw = paw; batX = b.x; batStart = t; batKicked = false
                nextBat = t + Double.random(in: 0.9...2.2)
            }
        }
        ball = b
    }

    /// 0...1...0 ao longo da espreguiçada que vem logo depois de acordar.
    var stretchEnvelope: CGFloat {
        let s = time - stretchStart
        guard s >= 0, s < 1.8 else { return 0 }
        return CGFloat(sin(.pi * s / 1.8))
    }

    /// Os dois "pulinhos" de cabeça no fim da cara de coruja.
    var owlBob: CGFloat {
        let s = time - owlStart
        for a in [1.85, 2.12] where s >= a && s < a + 0.16 {
            return -CGFloat(sin(.pi * (s - a) / 0.16)) * 3.5
        }
        return 0
    }

    private func updateBlinkAndTwitch(_ t: TimeInterval) {
        if t >= nextOwlChance {
            if mood == .awake, !petting, t - lastActivity > 3, t - lastTyping > 4,
               Double.random(in: 0...1) < 0.3 { owlStart = t }
            nextOwlChance = t + Double.random(in: 6...14)
        }
        if t >= nextBlink, !owlActive {
            blinkStart = t
            if mood == .daydream {
                blinkDuration = 0.55
                nextBlink = t + Double.random(in: 4...8)
            } else {
                blinkDuration = 0.16
                nextBlink = t + (Double.random(in: 0...1) < 0.2 ? 0.3 : Double.random(in: 2...5.5))
            }
        }
        if t >= nextEarTwitch {
            if mood == .awake && !petting {
                earTwitchStart = t
                earTwitchLeft = Bool.random()
            }
            nextEarTwitch = t + Double.random(in: 5...12)
        }
    }

    private func updateParticles(_ t: TimeInterval) {
        particles.removeAll { t - $0.born > $0.life }
        if mood == .sleeping, sleep.value > 0.8, t - lastZ > 1.4 {
            lastZ = t
            particles.append(Particle(kind: .z, origin: CGPoint(x: 202, y: 70 + headLift.value),
                                      born: t, life: 2.6, drift: CGFloat.random(in: -0.4...0.4)))
        }
        if pet.value > 0.5, t - lastHeart > 0.45 {
            lastHeart = t
            let o = petPoint + CGPoint(x: CGFloat.random(in: -14...14), y: -10)
            particles.append(Particle(kind: .heart, origin: o, born: t, life: 1.1,
                                      drift: CGFloat.random(in: -1...1)))
        }
    }

    // MARK: - Valores derivados para o desenho

    /// Radianos por segundo do balanço do rabo: mais lento sonhando.
    public var tailSpeed: Double { 1.7 - 1.0 * Double(dream.value) + 5 * Double(crouch.value) }
    /// Segundos por respiração: mais lenta dormindo.
    public var breathPeriod: Double { 3.2 + 1.6 * Double(sleep.value) }

    /// 1 = olho aberto, 0 = fechado. Junta piscada e sono.
    var eyeOpenness: CGFloat {
        let bt = time - blinkStart
        var blink: CGFloat = 1
        if bt >= 0, bt < blinkDuration {
            let p = CGFloat(bt / blinkDuration)
            blink = abs(1 - 2 * p)
        }
        return blink * clamp(1 - sleep.value * 1.15 - yawn.value * 1.1, 0, 1)
    }

    /// Sacudida de cabeça ao acordar.
    var shakeAngle: CGFloat {
        let s = time - shakeStart
        guard s >= 0, s < 0.9 else { return 0 }
        return CGFloat(sin(s * 30) * 0.16 * exp(-s * 4))
    }

    func earTwitchAngle(left: Bool) -> CGFloat {
        guard left == earTwitchLeft else { return 0 }
        let s = time - earTwitchStart
        guard s >= 0, s < 0.5 else { return 0 }
        return CGFloat(sin(s * 45) * 0.16 * exp(-s * 9))
    }
}
