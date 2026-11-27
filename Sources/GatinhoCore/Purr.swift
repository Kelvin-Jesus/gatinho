// Fora do site: depende de Foundation (arquivos, Data, URL).
#if !GATINHO_WEB
import Foundation

/// Som do ronronar: um gato de verdade gravado (Pixabay, "Real cat purring sound",
/// de feedthestraycats, licença de conteúdo do Pixabay). Recortamos 8 s do meio da
/// gravação, emendamos o fim no começo com fade cruzado (o laço não tem costura),
/// tiramos o ronco abaixo de 30 Hz e normalizamos o volume. Fica embutido no binário
/// (PurrSample.swift), então o app continua sendo um arquivo só.
public enum Purr {
    public static let sampleRate = 16_000

    /// O laço completo em PCM 16 bits mono.
    public static func loop() -> [Int16] {
        guard let data = Data(base64Encoded: recording) else { return [] }
        return data.withUnsafeBytes { raw in
            (0..<data.count / 2).map { Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self)) }
        }
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

#endif
