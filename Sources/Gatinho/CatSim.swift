import AppKit

/// Mola amortecida 2D: toda posição animada persegue um alvo com ela.
struct Spring2 {
    var value: CGPoint
    var velocity = CGVector.zero

    mutating func step(to t: CGPoint, dt: CGFloat, k: CGFloat, zeta: CGFloat = 0.8) {
        let c = 2 * sqrt(k) * zeta
        velocity.dx += (k * (t.x - value.x) - c * velocity.dx) * dt
        velocity.dy += (k * (t.y - value.y) - c * velocity.dy) * dt
        value.x += velocity.dx * dt
        value.y += velocity.dy * dt
    }

    var speed: CGFloat { hypot(velocity.dx, velocity.dy) }
}

struct Spring1 {
    var value: CGFloat
    var velocity: CGFloat = 0

    mutating func step(to t: CGFloat, dt: CGFloat, k: CGFloat, zeta: CGFloat = 1) {
        let c = 2 * sqrt(k) * zeta
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

enum Mood { case awake, daydream, sleeping }

/// Estado do gato. Os eventos de teclado/mouse mudam os alvos; `step` anima tudo a cada quadro.
/// Teclas só ficam em memória enquanto estão pressionadas: nada é gravado.
final class CatSim {
    var coat: Coat
    var scale: CGFloat = 1
    var showKeyLabels = true
    var windowFrame: NSRect = .zero
    var interactive = true

    var daydreamAfter: TimeInterval = 15
    var sleepAfter: TimeInterval = 40

    // Entrada
    private var heldKeys: [UInt16: (slot: Int, paw: Paw, at: TimeInterval, seen: TimeInterval)] = [:]
    private var lastKey: [Paw: (slot: Int, at: TimeInterval)] = [:]
    private(set) var keyGlow = [CGFloat](repeating: 0, count: KeyLayout.slots.count)
    private(set) var mouseButtons: Set<Int> = []
    private var lastMouseActivity: TimeInterval = -100
    private var lastActivity: TimeInterval
    private var lastMouseLoc: CGPoint
    private(set) var wheelPhase: CGFloat = 0
    private(set) var petting = false
    private var petPoint: CGPoint = .zero

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

    private(set) var time: TimeInterval = 0
    private var lastTime: TimeInterval = 0

    /// Fases acumuladas quadro a quadro. Nunca calcular `sin(tempoAbsoluto * velocidade)`
    /// com velocidade variável: com o tempo na casa de 10^8 s, qualquer mudança de
    /// velocidade faz a fase saltar e a animação "enlouquece".
    private(set) var tailPhase: Double = 0
    private(set) var breathPhase: Double = 0
    private(set) var mood: Mood = .awake

    init(coat: Coat) {
        self.coat = coat
        let now = Date().timeIntervalSinceReferenceDate
        lastActivity = now
        lastMouseLoc = NSEvent.mouseLocation
        nextBlink = now + 2
        nextEarTwitch = now + 6
    }

    private var now: TimeInterval { Date().timeIntervalSinceReferenceDate }

    // MARK: - Eventos

    func keyDown(code: UInt16, label: String, isRepeat: Bool) {
        let t = now
        markActivity(t)
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

    func keyUp(code: UInt16) {
        if let h = heldKeys.removeValue(forKey: code) { lastKey[h.paw] = (h.slot, now) }
    }

    /// Modificadores (⇧ ⌘ ⌥ ⌃) chegam como flagsChanged: alterna entre apertado e solto.
    func modifierChanged(code: UInt16) {
        if code == 57 { // Caps Lock: trata como um toque rápido
            keyDown(code: code, label: KeyLabels.label(code: code), isRepeat: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.keyUp(code: code) }
            return
        }
        if heldKeys[code] != nil { keyUp(code: code) }
        else { keyDown(code: code, label: KeyLabels.label(code: code), isRepeat: false) }
    }

    func mouseButton(_ b: Int, down: Bool) {
        let t = now
        if down { mouseButtons.insert(b) } else { mouseButtons.remove(b) }
        lastMouseActivity = t
        markActivity(t)
        if down { rightPress.velocity += 4 }
    }

    func scroll(_ dy: CGFloat) {
        let t = now
        wheelPhase += dy
        lastMouseActivity = t
        markActivity(t)
    }

    func beginPet(at p: CGPoint) { petting = true; petPoint = p; markActivity(now) }
    func movePet(to p: CGPoint) { petPoint = p; markActivity(now) }
    func endPet() { petting = false }

    private func markActivity(_ t: TimeInterval) {
        if mood == .sleeping || sleep.value > 0.45 {
            if t - shakeStart > 1 { shakeStart = t }
        } else if mood == .daydream {
            blinkStart = t
            blinkDuration = 0.18
        }
        lastActivity = t
        if mood != .awake { mood = .awake }
    }

    // MARK: - Quadro

    func step(to t: TimeInterval) {
        if lastTime == 0 { lastTime = t }
        let dt = CGFloat(min(max(t - lastTime, 0), 0.05))
        lastTime = t
        time = t

        pollMouse(t)
        dropStaleKeys(t)

        let idle = t - lastActivity
        mood = petting ? .awake : idle > sleepAfter ? .sleeping : idle > daydreamAfter ? .daydream : .awake

        let (lt, lp) = pawTarget(.left, t)
        let (rt, rp) = pawTarget(.right, t)
        let (pupilT, roundT, tiltT) = gazeTargets()
        let liftT: CGFloat = petting ? 3 : mood == .sleeping ? 10 : mood == .daydream ? -6 : 0
        let sleepT: CGFloat = mood == .sleeping ? 1 : 0
        let dreamT: CGFloat = mood == .daydream ? 1 : 0
        let petT: CGFloat = petting ? 1 : 0

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
            mouseJiggle.step(to: jiggleTarget, dt: h, k: 500, zeta: 0.6)
        }

        tailPhase = (tailPhase + Double(dt) * tailSpeed).truncatingRemainder(dividingBy: 2 * .pi)
        breathPhase = (breathPhase + Double(dt) * 2 * .pi / breathPeriod).truncatingRemainder(dividingBy: 2 * .pi)

        updateBlinkAndTwitch(t)
        updateParticles(t)

        for i in keyGlow.indices where keyGlow[i] > 0 {
            let held = heldKeys.values.contains { $0.slot == i }
            keyGlow[i] = held ? 1 : max(0, keyGlow[i] - dt * 3.5)
        }
    }

    private func pollMouse(_ t: TimeInterval) {
        let m = NSEvent.mouseLocation
        let dx = m.x - lastMouseLoc.x, dy = m.y - lastMouseLoc.y
        lastMouseLoc = m
        if abs(dx) + abs(dy) > 0.5, !petting {
            lastMouseActivity = t
            markActivity(t)
        }
        jiggleTarget = CGPoint(x: clamp(dx * 0.35, -5, 5), y: clamp(-dy * 0.35, -4, 4))
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
        let s = scale
        let mid = CGPoint(x: (Geo.eyeL.x + Geo.eyeR.x) / 2, y: Geo.eyeL.y)
        let eye = CGPoint(x: windowFrame.minX + mid.x * s, y: windowFrame.maxY - mid.y * s)
        let m = NSEvent.mouseLocation
        let dx = m.x - eye.x, dy = -(m.y - eye.y)
        let d = hypot(dx, dy)
        let mag = min(1, d / 220) * 4.5
        let dir = d > 0.001 ? CGPoint(x: dx / d, y: dy / d * 0.8) : .zero
        return (dir * mag, d < 170 * s + 40 ? 1 : 0, clamp(dx / 2500, -0.07, 0.07))
    }

    private func updateBlinkAndTwitch(_ t: TimeInterval) {
        if t >= nextBlink {
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
    var tailSpeed: Double { 1.7 - 1.0 * Double(dream.value) }
    /// Segundos por respiração: mais lenta dormindo.
    var breathPeriod: Double { 3.2 + 1.6 * Double(sleep.value) }

    /// 1 = olho aberto, 0 = fechado. Junta piscada e sono.
    var eyeOpenness: CGFloat {
        let bt = time - blinkStart
        var blink: CGFloat = 1
        if bt >= 0, bt < blinkDuration {
            let p = CGFloat(bt / blinkDuration)
            blink = abs(1 - 2 * p)
        }
        return blink * clamp(1 - sleep.value * 1.15, 0, 1)
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
