import Foundation

/// Som do ronronar, sintetizado aqui mesmo (nenhum arquivo de áudio no projeto).
///
/// Um ronronar de verdade é uma sequência de "batidas" de ~25 por segundo, mais
/// forte quando o gato solta o ar e mais fraca quando puxa. Cada batida aqui é um
/// pacote de ruído grave com um envelope curto; o ciclo expira + inspira vira um
/// laço de ~2 s que fecha sem emenda, porque começa e termina em silêncio.
public enum Purr {
    public static let sampleRate = 22_050

    /// Um ciclo completo (expira e inspira) em PCM 16 bits mono.
    public static func loop() -> [Int16] {
        var rng = SplitMix(seed: 0x6A7_1A0)
        var out: [Int16] = []
        // Expira: 28 batidas a 25 Hz, forte. Inspira: 20 batidas a 22 Hz, mais fraca.
        let phases: [(beats: Int, hz: Double, gain: Double)] = [(28, 25, 1.0), (20, 22, 0.55)]
        var low = 0.0, band = 0.0
        for phase in phases {
            let beatLen = Int(Double(sampleRate) / phase.hz)
            let total = beatLen * phase.beats
            for i in 0..<total {
                let beatPos = Double(i % beatLen) / Double(beatLen)
                let cyclePos = Double(i) / Double(total)
                // Envelope da batida: subida rápida, queda suave.
                let beat = pow(sin(.pi * min(1, beatPos * 1.6)), 2)
                // Envelope do fôlego: entra e sai suave, silêncio nas pontas.
                let breath = pow(sin(.pi * cyclePos), 0.6)
                // Ruído filtrado: dois polos simples dão o "rrr" grave e aveludado.
                let noise = rng.nextSigned()
                low += 0.09 * (noise - low)
                band += 0.25 * (low - band)
                let body = sin(2 * .pi * 110 * Double(i) / Double(sampleRate)) * 0.15
                let s = (band * 2.6 + body * beat) * beat * breath * phase.gain
                out.append(Int16(max(-1, min(1, s * 0.55)) * 32_767))
            }
            // Pausa curta entre expirar e inspirar.
            out.append(contentsOf: repeatElement(0, count: sampleRate / 20))
        }
        return out
    }

    /// Arquivo WAV com o laço repetido até cobrir `seconds` (pelo menos um ciclo).
    public static func wav(seconds: Double = 0) -> Data {
        let one = loop()
        var samples = one
        while Double(samples.count) / Double(sampleRate) < seconds { samples += one }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16)
        u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }
}

/// Gerador pseudoaleatório fixo, para o som sair igual em toda máquina.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Valor entre -1 e 1.
    mutating func nextSigned() -> Double { Double(next() >> 11) / Double(1 << 52) - 1 }
}
