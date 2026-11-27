import Foundation

/// Codificador PNG mínimo (deflate sem compressão), para snapshots sem dependências.
public enum PNG {
    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let t = Array(type.utf8)
        return be32(UInt32(data.count)) + t + data + be32(crc(t + data))
    }

    public static func encode(rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        var raw: [UInt8] = []
        raw.reserveCapacity((width * 4 + 1) * height)
        for y in 0..<height {
            raw.append(0)
            raw.append(contentsOf: rgba[(y * width * 4)..<((y + 1) * width * 4)])
        }
        var z: [UInt8] = [0x78, 0x01]
        var i = 0
        repeat {
            let n = min(65535, raw.count - i)
            let final: UInt8 = i + n >= raw.count ? 1 : 0
            z.append(final)
            z.append(UInt8(n & 0xFF)); z.append(UInt8(n >> 8))
            z.append(UInt8(~n & 0xFF)); z.append(UInt8((~n >> 8) & 0xFF))
            z.append(contentsOf: raw[i..<(i + n)])
            i += n
        } while i < raw.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        z += be32((b << 16) | a)

        let ihdr = be32(UInt32(width)) + be32(UInt32(height)) + [8, 6, 0, 0, 0]
        return [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            + chunk("IHDR", ihdr) + chunk("IDAT", z) + chunk("IEND", [])
    }
}
