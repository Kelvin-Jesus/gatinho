#if GATINHO_WEB
import WASILibc
#else
import Foundation
#endif

/// Transformação afim 2D: x' = a·x + c·y + tx, y' = b·x + d·y + ty.
struct Affine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    @inline(__always) func apply(_ p: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
    }

    /// self ∘ t: aplica `t` primeiro (semântica do Core Graphics).
    func then(_ t: Affine) -> Affine {
        Affine(a: a * t.a + c * t.b, b: b * t.a + d * t.b,
               c: a * t.c + c * t.d, d: b * t.c + d * t.d,
               tx: a * t.tx + c * t.ty + tx, ty: b * t.tx + d * t.ty + ty)
    }

    var inverse: Affine {
        let det = a * d - b * c
        guard abs(det) > 1e-12 else { return Affine() }
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return Affine(a: ia, b: ib, c: ic, d: id, tx: -(ia * tx + ic * ty), ty: -(ib * tx + id * ty))
    }

    var scaleFactor: Double { abs(a * d - b * c).squareRoot() }
}

/// Cobertura (0...1) de uma região retangular da tela.
struct Coverage {
    let x0: Int, y0: Int, w: Int, h: Int
    var data: [Float]

    @inline(__always) func value(_ x: Int, _ y: Int) -> Float {
        let lx = x - x0, ly = y - y0
        guard lx >= 0, ly >= 0, lx < w, ly < h else { return 0 }
        return data[ly * w + lx]
    }
}

/// Imagem RGBA em float, pré-multiplicada.
public final class SoftCanvas {
    public let width: Int
    public let height: Int
    var px: [Float]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        px = [Float](repeating: 0, count: width * height * 4)
    }

    public func clear() {
        px.withUnsafeMutableBufferPointer { buf in
            for i in buf.indices { buf[i] = 0 }
        }
    }

    /// BGRA 8 bits pré-multiplicado (Windows UpdateLayeredWindow, X11 ARGB32).
    public func writeBGRA(into out: UnsafeMutablePointer<UInt8>, opacity: Float = 1) {
        px.withUnsafeBufferPointer { src in
            for i in 0..<(width * height) {
                let s = i * 4
                out[s] = UInt8(min(255, max(0, src[s + 2] * opacity * 255 + 0.5)))
                out[s + 1] = UInt8(min(255, max(0, src[s + 1] * opacity * 255 + 0.5)))
                out[s + 2] = UInt8(min(255, max(0, src[s] * opacity * 255 + 0.5)))
                out[s + 3] = UInt8(min(255, max(0, src[s + 3] * opacity * 255 + 0.5)))
            }
        }
    }

    /// RGBA 8 bits não pré-multiplicado (PNG).
    public func rgbaStraight() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let s = i * 4
            let a = px[s + 3]
            guard a > 0.0001 else { continue }
            out[s] = UInt8(min(255, px[s] / a * 255 + 0.5))
            out[s + 1] = UInt8(min(255, px[s + 1] / a * 255 + 0.5))
            out[s + 2] = UInt8(min(255, px[s + 2] / a * 255 + 0.5))
            out[s + 3] = UInt8(min(255, a * 255 + 0.5))
        }
        return out
    }

    /// RGBA 8 bits não pré-multiplicado num buffer já alocado (o canvas do site, sem alocar por quadro).
    public func writeRGBAStraight(into out: UnsafeMutablePointer<UInt8>) {
        px.withUnsafeBufferPointer { src in
            for i in 0..<(width * height) {
                let s = i * 4
                let a = src[s + 3]
                guard a > 0.0001 else { out[s] = 0; out[s + 1] = 0; out[s + 2] = 0; out[s + 3] = 0; continue }
                out[s] = UInt8(min(255, src[s] / a * 255 + 0.5))
                out[s + 1] = UInt8(min(255, src[s + 1] / a * 255 + 0.5))
                out[s + 2] = UInt8(min(255, src[s + 2] / a * 255 + 0.5))
                out[s + 3] = UInt8(min(255, a * 255 + 0.5))
            }
        }
    }

    /// Opacidade (0...1) de um pixel — usada para recortar a área clicável da janela.
    public func alpha(x: Int, y: Int) -> Float { px[(y * width + x) * 4 + 3] }

    /// Preenche tudo com uma cor opaca (fundo do snapshot).
    public func fillBackground(_ c: RGB) {
        for i in 0..<(width * height) {
            px[i * 4] = Float(c.r); px[i * 4 + 1] = Float(c.g); px[i * 4 + 2] = Float(c.b); px[i * 4 + 3] = 1
        }
    }
}

/// Rasterizador por software: preenchimento nonzero com anti-serrilhado
/// (4 sub-linhas por pixel e cobertura horizontal exata), traços convertidos em polígonos.
public final class SoftPainter: Painter {
    private struct State { var ctm = Affine(); var clip: Coverage?; var alpha: Double = 1 }
    private struct Poly { var pts: [SIMD2<Double>]; var closed: Bool }
    private struct Edge { var x0: Double, y0: Double, y1: Double, slope: Double, dir: Int }

    private let canvas: SoftCanvas
    private var st = State()
    private var stack: [State] = []

    public init(_ canvas: SoftCanvas) { self.canvas = canvas }

    // MARK: Estado

    public func save() { stack.append(st) }
    public func restore() { if let s = stack.popLast() { st = s } }
    public func translate(_ x: CGFloat, _ y: CGFloat) { st.ctm = st.ctm.then(Affine(tx: Double(x), ty: Double(y))) }
    public func rotate(_ r: CGFloat) {
        let c = cos(Double(r)), s = sin(Double(r))
        st.ctm = st.ctm.then(Affine(a: c, b: s, c: -s, d: c))
    }
    public func scale(_ x: CGFloat, _ y: CGFloat) { st.ctm = st.ctm.then(Affine(a: Double(x), d: Double(y))) }
    public func multiplyOpacity(_ o: Double) { st.alpha *= o }

    public func clip(_ p: Path2D) {
        let polys = flatten(p).map { $0.pts.map(st.ctm.apply) }
        guard var cov = rasterize(polys) else {
            st.clip = Coverage(x0: 0, y0: 0, w: 0, h: 0, data: [])
            return
        }
        if let old = st.clip {
            for y in 0..<cov.h {
                for x in 0..<cov.w { cov.data[y * cov.w + x] *= old.value(cov.x0 + x, cov.y0 + y) }
            }
        }
        st.clip = cov
    }

    // MARK: Desenho

    public func fill(_ p: Path2D, _ paint: Paint) {
        let polys = flatten(p).map { $0.pts.map(st.ctm.apply) }
        if let cov = rasterize(polys) { composite(cov, paint) }
    }

    public func stroke(_ p: Path2D, _ paint: Paint, _ style: StrokeStyle2) {
        let polys = strokePolygons(p, style).map { $0.map(st.ctm.apply) }
        if let cov = rasterize(polys) { composite(cov, paint) }
    }

    public func text(_ s: String, center: CGPoint, size: CGFloat, color: RGB) {
        let path = StrokeFont.path(s, center: center, size: size)
        stroke(path, .color(color), StrokeStyle2(max(1, size * 0.15), cap: .round))
    }

    // MARK: Achatamento de curvas

    private func flatten(_ path: Path2D) -> [Poly] {
        let scale = max(st.ctm.scaleFactor, 0.01)
        var out: [Poly] = []
        var cur: [SIMD2<Double>] = []
        var start = SIMD2<Double>(0, 0)

        func v(_ p: CGPoint) -> SIMD2<Double> { SIMD2(Double(p.x), Double(p.y)) }
        func flush(_ closed: Bool) {
            if cur.count > 1 { out.append(Poly(pts: cur, closed: closed)) }
            cur = []
        }
        func steps(_ length: Double) -> Int { max(2, min(48, Int((length * scale / 3).rounded(.up)))) }
        func dist(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { let d = b - a; return (d.x * d.x + d.y * d.y).squareRoot() }

        for e in path.elements {
            switch e {
            case .move(let p):
                flush(false)
                start = v(p)
                cur = [start]
            case .line(let p):
                if cur.isEmpty { cur = [start] }
                cur.append(v(p))
            case .quad(let c, let p):
                if cur.isEmpty { cur = [start] }
                let p0 = cur[cur.count - 1], c1 = v(c), p1 = v(p)
                let n = steps(dist(p0, c1) + dist(c1, p1))
                for i in 1...n {
                    let t = Double(i) / Double(n), u = 1 - t
                    cur.append(p0 * (u * u) + c1 * (2 * u * t) + p1 * (t * t))
                }
            case .cubic(let c1p, let c2p, let p):
                if cur.isEmpty { cur = [start] }
                let p0 = cur[cur.count - 1], c1 = v(c1p), c2 = v(c2p), p1 = v(p)
                let n = steps(dist(p0, c1) + dist(c1, c2) + dist(c2, p1))
                for i in 1...n {
                    let t = Double(i) / Double(n), u = 1 - t
                    cur.append(p0 * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + p1 * (t * t * t))
                }
            case .close:
                flush(true)
                cur = []
            }
        }
        flush(false)
        return out
    }

    // MARK: Traço → polígonos

    private func strokePolygons(_ path: Path2D, _ s: StrokeStyle2) -> [[SIMD2<Double>]] {
        var subs = flatten(path)
        if !s.dash.isEmpty { subs = dashed(subs, s.dash.map { Double($0) }, Double(s.dashPhase)) }
        let hw = Double(s.width) / 2
        let scale = st.ctm.scaleFactor
        let circleN = max(10, min(40, Int(hw * scale * 2.2)))
        var out: [[SIMD2<Double>]] = []

        func oriented(_ poly: [SIMD2<Double>]) -> [SIMD2<Double>] {
            var area = 0.0
            for i in 0..<poly.count {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                area += a.x * b.y - b.x * a.y
            }
            return area < 0 ? poly.reversed() : poly
        }
        func circle(_ c: SIMD2<Double>) -> [SIMD2<Double>] {
            (0..<circleN).map { i in
                let a = Double(i) / Double(circleN) * 2 * .pi
                return c + SIMD2(cos(a), sin(a)) * hw
            }
        }
        func unit(_ d: SIMD2<Double>) -> SIMD2<Double> {
            let l = (d.x * d.x + d.y * d.y).squareRoot()
            return l > 1e-9 ? d / l : SIMD2(1, 0)
        }

        for sub in subs {
            var pts: [SIMD2<Double>] = []
            for p in sub.pts {
                if let last = pts.last {
                    let d = p - last
                    if d.x * d.x + d.y * d.y < 1e-10 { continue }
                }
                pts.append(p)
            }
            if sub.closed, pts.count > 2, let f = pts.first, let l = pts.last {
                let d = f - l
                if d.x * d.x + d.y * d.y < 1e-10 { pts.removeLast() }
            }
            let n = pts.count
            if n == 1 {
                if s.cap == .round { out.append(circle(pts[0])) }
                continue
            }
            guard n >= 2 else { continue }
            let closed = sub.closed && n > 2
            let segCount = closed ? n : n - 1
            for i in 0..<segCount {
                let a = pts[i], b = pts[(i + 1) % n]
                let dir = unit(b - a)
                let nrm = SIMD2(-dir.y, dir.x) * hw
                out.append(oriented([a + nrm, b + nrm, b - nrm, a - nrm]))
            }
            let joints: [Int] = closed ? Array(0..<n) : (n > 2 ? Array(1..<(n - 1)) : [])
            for i in joints {
                let p = pts[i]
                let d0 = unit(p - pts[(i - 1 + n) % n]), d1 = unit(pts[(i + 1) % n] - p)
                let cosang = d0.x * d1.x + d0.y * d1.y
                if cosang > 0.87 {
                    // Curva suave: cunhas fecham a fresta entre os segmentos.
                    let n0 = SIMD2(-d0.y, d0.x) * hw, n1 = SIMD2(-d1.y, d1.x) * hw
                    out.append(oriented([p, p + n0, p + n1]))
                    out.append(oriented([p, p - n0, p - n1]))
                } else {
                    out.append(circle(p))
                }
            }
            if !closed, s.cap == .round {
                out.append(circle(pts[0]))
                out.append(circle(pts[n - 1]))
            }
        }
        return out
    }

    private func dashed(_ subs: [Poly], _ dash: [Double], _ phase: Double) -> [Poly] {
        let total = dash.reduce(0, +)
        guard total > 0 else { return subs }
        var out: [Poly] = []
        for sub in subs {
            var pts = sub.pts
            if sub.closed, let f = pts.first { pts.append(f) }
            guard pts.count > 1 else { continue }
            var idx = 0, rem = dash[0], on = true
            var ph = phase.truncatingRemainder(dividingBy: total)
            if ph < 0 { ph += total }
            while ph > 0 {
                if ph >= rem { ph -= rem; idx = (idx + 1) % dash.count; rem = dash[idx]; on.toggle() }
                else { rem -= ph; ph = 0 }
            }
            var cur: [SIMD2<Double>] = on ? [pts[0]] : []
            for i in 0..<(pts.count - 1) {
                var a = pts[i]
                let b = pts[i + 1]
                var seg = { () -> Double in let d = b - a; return (d.x * d.x + d.y * d.y).squareRoot() }()
                while seg > 1e-9 {
                    if rem >= seg {
                        rem -= seg
                        if on { cur.append(b) }
                        seg = 0
                    } else {
                        let m = a + (b - a) * (rem / seg)
                        if on {
                            cur.append(m)
                            if cur.count > 1 { out.append(Poly(pts: cur, closed: false)) }
                            cur = []
                        } else {
                            cur = [m]
                        }
                        seg -= rem
                        a = m
                        idx = (idx + 1) % dash.count
                        rem = dash[idx]
                        on.toggle()
                    }
                }
            }
            if on, cur.count > 1 { out.append(Poly(pts: cur, closed: false)) }
        }
        return out
    }

    // MARK: Rasterização

    private func rasterize(_ polys: [[SIMD2<Double>]]) -> Coverage? {
        var edges: [Edge] = []
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for poly in polys where poly.count >= 3 {
            for i in 0..<poly.count {
                let p0 = poly[i], p1 = poly[(i + 1) % poly.count]
                minX = min(minX, p0.x); maxX = max(maxX, p0.x); minY = min(minY, p0.y); maxY = max(maxY, p0.y)
                if p0.y == p1.y { continue }
                let (top, bot, dir) = p0.y < p1.y ? (p0, p1, 1) : (p1, p0, -1)
                edges.append(Edge(x0: top.x, y0: top.y, y1: bot.y, slope: (bot.x - top.x) / (bot.y - top.y), dir: dir))
            }
        }
        guard !edges.isEmpty else { return nil }
        var bx0 = max(0, Int(minX.rounded(.down))), bx1 = min(canvas.width, Int(maxX.rounded(.up)) + 1)
        var by0 = max(0, Int(minY.rounded(.down))), by1 = min(canvas.height, Int(maxY.rounded(.up)) + 1)
        if let c = st.clip {
            bx0 = max(bx0, c.x0); bx1 = min(bx1, c.x0 + c.w)
            by0 = max(by0, c.y0); by1 = min(by1, c.y0 + c.h)
        }
        guard bx1 > bx0, by1 > by0 else { return nil }
        let w = bx1 - bx0, h = by1 - by0
        edges.sort { $0.y0 < $1.y0 }

        var acc = [Float](repeating: 0, count: w * h)
        let subRows = 4
        let weight = Float(1) / Float(subRows)
        var active: [Int] = []
        var next = 0
        var xs: [(Double, Int)] = []
        xs.reserveCapacity(64)
        let fw = Double(w)

        acc.withUnsafeMutableBufferPointer { a in
            for row in by0..<by1 {
                let base = (row - by0) * w
                for s in 0..<subRows {
                    let sy = Double(row) + (Double(s) + 0.5) / Double(subRows)
                    while next < edges.count, edges[next].y0 <= sy { active.append(next); next += 1 }
                    active.removeAll { edges[$0].y1 <= sy }
                    if active.count < 2 { continue }
                    xs.removeAll(keepingCapacity: true)
                    for i in active {
                        let e = edges[i]
                        xs.append((e.x0 + (sy - e.y0) * e.slope - Double(bx0), e.dir))
                    }
                    xs.sort { $0.0 < $1.0 }
                    var wind = 0
                    var start = 0.0
                    for (x, d) in xs {
                        let prev = wind
                        wind += d
                        if prev == 0, wind != 0 {
                            start = x
                        } else if prev != 0, wind == 0 {
                            let x0 = max(0, start), x1 = min(fw, x)
                            if x1 <= x0 { continue }
                            let i0 = Int(x0), i1 = Int(x1)
                            if i0 == i1 {
                                if i0 < w { a[base + i0] += Float(x1 - x0) * weight }
                            } else {
                                a[base + i0] += Float(Double(i0 + 1) - x0) * weight
                                if i0 + 1 < i1 { for i in (i0 + 1)..<i1 { a[base + i] += weight } }
                                if i1 < w { a[base + i1] += Float(x1 - Double(i1)) * weight }
                            }
                        }
                    }
                }
            }
        }
        return Coverage(x0: bx0, y0: by0, w: w, h: h, data: acc)
    }

    private func composite(_ cov: Coverage, _ paint: Paint) {
        let W = canvas.width
        let gAlpha = Float(st.alpha)
        let clip = st.clip
        var solid: (Float, Float, Float, Float)?
        var radial: (inv: Affine, c: SIMD2<Double>, r0: Double, r1: Double, stops: [GradientStop])?
        switch paint {
        case .solid(let c, let a):
            solid = (Float(c.r), Float(c.g), Float(c.b), Float(a) * gAlpha)
        case .radial(let center, let r0, let r1, let stops):
            radial = (st.ctm.inverse, SIMD2(Double(center.x), Double(center.y)), Double(r0), Double(r1), stops)
        }
        canvas.px.withUnsafeMutableBufferPointer { px in
            cov.data.withUnsafeBufferPointer { cd in
                for ly in 0..<cov.h {
                    let y = cov.y0 + ly
                    for lx in 0..<cov.w {
                        var c = min(cd[ly * cov.w + lx], 1)
                        if c <= 0.001 { continue }
                        let x = cov.x0 + lx
                        if let clip { c *= clip.value(x, y); if c <= 0.001 { continue } }
                        var r: Float, g: Float, b: Float, a: Float
                        if let s = solid {
                            (r, g, b) = (s.0, s.1, s.2)
                            a = s.3 * c
                        } else if let rad = radial {
                            let u = rad.inv.apply(SIMD2(Double(x) + 0.5, Double(y) + 0.5)) - rad.c
                            let dist = (u.x * u.x + u.y * u.y).squareRoot()
                            let t = min(1, max(0, (dist - rad.r0) / max(rad.r1 - rad.r0, 1e-9)))
                            let (col, al) = SoftPainter.sample(rad.stops, t)
                            (r, g, b) = (Float(col.r), Float(col.g), Float(col.b))
                            a = Float(al) * gAlpha * c
                        } else { continue }
                        if a <= 0.0005 { continue }
                        let i = (y * W + x) * 4
                        let k = 1 - a
                        px[i] = r * a + px[i] * k
                        px[i + 1] = g * a + px[i + 1] * k
                        px[i + 2] = b * a + px[i + 2] * k
                        px[i + 3] = a + px[i + 3] * k
                    }
                }
            }
        }
    }

    private static func sample(_ stops: [GradientStop], _ t: Double) -> (RGB, Double) {
        guard let first = stops.first, let last = stops.last else { return (RGB(0), 0) }
        if t <= first.location { return (first.color, first.alpha) }
        for i in 1..<stops.count where t <= stops[i].location {
            let s0 = stops[i - 1], s1 = stops[i]
            let u = (t - s0.location) / max(s1.location - s0.location, 1e-9)
            return (s0.color.mix(s1.color, u), s0.alpha + (s1.alpha - s0.alpha) * u)
        }
        return (last.color, last.alpha)
    }
}
