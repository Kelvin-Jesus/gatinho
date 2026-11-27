// O gato do site: o mesmo GatinhoCore do app, compilado para WebAssembly.
// O JavaScript manda o relógio e os eventos, pede um quadro e copia os pixels para um <canvas>.
// Fora do wasm este alvo não faz nada (só existe para o `swift build` dos três sistemas passar).
#if arch(wasm32)
import GatinhoCore

private var now: Double = 0
private var sim = CatSim(coat: Coat.all[0])
private var scale: CGFloat = 2
private var canvas = SoftCanvas(width: 1, height: 1)
private var pixels = [UInt8](repeating: 0, count: 4)

private func resize() {
    let w = Int((Geo.size.width * scale).rounded()), h = Int((Geo.size.height * scale).rounded())
    if canvas.width != w || canvas.height != h {
        canvas = SoftCanvas(width: w, height: h)
        pixels = [UInt8](repeating: 0, count: w * h * 4)
    }
    sim.screenScale = scale
}

/// Começa um gato novo. `coat` é o índice em `Coat.all`; `t` é o relógio em segundos.
@_expose(wasm, "gato_iniciar")
public func iniciar(_ coat: Int32, _ s: Double, _ t: Double) {
    now = t
    sim = CatSim(coat: Coat.all[Int(coat) % Coat.all.count])
    sim.clock = { now }
    sim.labelStyle = .mac
    scale = CGFloat(s)
    resize()
}

@_expose(wasm, "gato_pelagem")
public func pelagem(_ coat: Int32) { sim.coat = Coat.all[Int(coat) % Coat.all.count] }

@_expose(wasm, "gato_pelagens")
public func pelagens() -> Int32 { Int32(Coat.all.count) }

@_expose(wasm, "gato_escala")
public func escala(_ s: Double) { scale = CGFloat(s); resize() }

@_expose(wasm, "gato_relogio")
public func relogio(_ t: Double) { now = t }

/// `label` é um caractere Unicode (0 = sem rótulo; o gato usa o rótulo padrão da tecla).
@_expose(wasm, "gato_tecla")
public func tecla(_ code: Int32, _ label: Int32, _ down: Int32, _ isRepeat: Int32) {
    let k = UInt16(truncatingIfNeeded: code)
    if down != 0 {
        let text = label > 0 ? Unicode.Scalar(UInt32(label)).map { String(Character($0)) } ?? "" : ""
        sim.keyDown(code: k, label: text, isRepeat: isRepeat != 0)
    } else {
        sim.keyUp(code: k)
    }
}

@_expose(wasm, "gato_modificador")
public func modificador(_ code: Int32) { sim.modifierChanged(code: UInt16(truncatingIfNeeded: code)) }

@_expose(wasm, "gato_botao")
public func botao(_ b: Int32, _ down: Int32) { sim.mouseButton(Int(b), down: down != 0) }

@_expose(wasm, "gato_rolar")
public func rolar(_ dy: Double) { sim.scroll(CGFloat(dy)) }

/// Carinho em pontos do desenho (0...330 x 0...300). fase: 0 começa, 1 move, 2 termina.
@_expose(wasm, "gato_carinho")
public func carinho(_ fase: Int32, _ x: Double, _ y: Double) {
    let p = CGPoint(x: x, y: y)
    switch fase {
    case 0: sim.beginPet(at: p)
    case 1: sim.movePet(to: p)
    default: sim.endPet()
    }
}

/// Diz se um ponto do desenho cai na cabeça (onde o carinho funciona).
@_expose(wasm, "gato_na_cabeca")
public func naCabeca(_ x: Double, _ y: Double) -> Int32 { Geo.hitsHead(CGPoint(x: x, y: y)) ? 1 : 0 }

/// Clique na bolinha de lã (pontos do desenho). Devolve 1 se acertou (ela quica).
@_expose(wasm, "gato_cutucar")
public func cutucar(_ x: Double, _ y: Double) -> Int32 { sim.poke(at: CGPoint(x: x, y: y)) ? 1 : 0 }

@_expose(wasm, "gato_tem_bolinha")
public func temBolinha() -> Int32 { sim.hasBall ? 1 : 0 }

@_expose(wasm, "gato_ronronando")
public func ronronando() -> Int32 { sim.purring ? 1 : 0 }

/// 0 acordado, 1 sonhando acordado, 2 dormindo.
@_expose(wasm, "gato_humor")
public func humor() -> Int32 {
    switch sim.mood { case .awake: 0; case .daydream: 1; case .sleeping: 2 }
}

/// Anima até `t` e desenha. Ponteiro e janela em pixels de tela (y para baixo), como no app.
/// Devolve o endereço dos pixels RGBA (sem pré-multiplicar), prontos para um ImageData.
@_expose(wasm, "gato_quadro")
public func quadro(_ t: Double, _ px: Double, _ py: Double,
                   _ wx: Double, _ wy: Double, _ ww: Double, _ wh: Double) -> Int32 {
    now = t
    sim.pointer = CGPoint(x: px, y: py)
    sim.windowFrame = CGRect(x: wx, y: wy, width: ww, height: wh)
    sim.step(to: t)
    canvas.clear()
    CatRenderer.draw(sim, SoftPainter(canvas), scale: scale)
    return pixels.withUnsafeMutableBufferPointer { buf in
        canvas.writeRGBAStraight(into: buf.baseAddress!)
        return Int32(Int(bitPattern: buf.baseAddress!))
    }
}

@_expose(wasm, "gato_largura")
public func largura() -> Int32 { Int32(canvas.width) }

@_expose(wasm, "gato_altura")
public func altura() -> Int32 { Int32(canvas.height) }
#endif
