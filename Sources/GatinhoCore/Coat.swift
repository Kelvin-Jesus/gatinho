#if GATINHO_WEB
import WASILibc
#else
import Foundation
#endif

/// Cor RGB simples, para poder misturar (lerp) cores no desenho.
public struct RGB {
    public var r: Double, g: Double, b: Double

    public init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    public func mix(_ o: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }
}

public enum CoatPattern { case solid, tuxedo, bicolor, tabby, siamese, calico }

/// Pelagem: as cores e o padrão do gato.
public struct Coat {
    public let id: String
    public let name: String
    let base: RGB       // pelo principal
    let shade: RGB      // contorno
    let accent: RGB     // branco do tuxedo, listras, pontas do siamês, mancha laranja
    let accent2: RGB    // focinho claro do rajado, mancha preta do calico
    let innerEar: RGB
    let eye: RGB
    let paw: RGB
    let eyeLine: RGB    // traço de olho fechado
    let mouthLine: RGB
    let whisker: RGB
    let pattern: CoatPattern

    public static let all: [Coat] = [
        Coat(id: "tuxedo", name: "Tuxedo (preto e branco)",
             base: RGB(0x232327), shade: RGB(0x0F0F12), accent: RGB(0xF7F4EE), accent2: RGB(0xF7F4EE),
             innerEar: RGB(0xC97F8D), eye: RGB(0xF2C230), paw: RGB(0xF7F4EE),
             eyeLine: RGB(0x9A9AA3), mouthLine: RGB(0x3A3A40), whisker: RGB(0xDADADF), pattern: .tuxedo),
        Coat(id: "laranja", name: "Laranja rajado",
             base: RGB(0xF2A65A), shade: RGB(0xB8702F), accent: RGB(0xD27F35), accent2: RGB(0xFFF1DE),
             innerEar: RGB(0xF4B2B0), eye: RGB(0x86B83A), paw: RGB(0xFFF1DE),
             eyeLine: RGB(0x5A3A22), mouthLine: RGB(0x5A3A22), whisker: RGB(0x7A5A40), pattern: .tabby),
        Coat(id: "marrom", name: "Rajado marrom",
             base: RGB(0xA98C6B), shade: RGB(0x6D5640), accent: RGB(0x6F5840), accent2: RGB(0xEADDC8),
             innerEar: RGB(0xE9A7A3), eye: RGB(0x9CCB55), paw: RGB(0xEADDC8),
             eyeLine: RGB(0x3E2F22), mouthLine: RGB(0x3E2F22), whisker: RGB(0x5A4632), pattern: .tabby),
        Coat(id: "siames", name: "Siamês",
             base: RGB(0xF2E8D6), shade: RGB(0xB9A68A), accent: RGB(0x5C4537), accent2: RGB(0x5C4537),
             innerEar: RGB(0x8A6A5A), eye: RGB(0x5AAEEA), paw: RGB(0x5C4537),
             eyeLine: RGB(0xD9C9B0), mouthLine: RGB(0x2E211A), whisker: RGB(0xD9C9B0), pattern: .siamese),
        Coat(id: "calico", name: "Calico (três cores)",
             base: RGB(0xFBF7F0), shade: RGB(0xC9BBA8), accent: RGB(0xE99547), accent2: RGB(0x2F2B2B),
             innerEar: RGB(0xF2A9B2), eye: RGB(0x8FC14A), paw: RGB(0xFBF7F0),
             eyeLine: RGB(0x3A2E2A), mouthLine: RGB(0x3A2E2A), whisker: RGB(0x8A7A70), pattern: .calico),
        Coat(id: "preto", name: "Preto",
             base: RGB(0x29282E), shade: RGB(0x111114), accent: RGB(0x29282E), accent2: RGB(0x29282E),
             innerEar: RGB(0x6A4A55), eye: RGB(0xF2B33D), paw: RGB(0x29282E),
             eyeLine: RGB(0x9A9AA3), mouthLine: RGB(0x9A9AA3), whisker: RGB(0xCFCFD6), pattern: .solid),
        Coat(id: "branco", name: "Branco",
             base: RGB(0xFAF8F4), shade: RGB(0xC9C2B6), accent: RGB(0xFAF8F4), accent2: RGB(0xFAF8F4),
             innerEar: RGB(0xF2A9B2), eye: RGB(0x6EC3E8), paw: RGB(0xFAF8F4),
             eyeLine: RGB(0x3A2E2A), mouthLine: RGB(0x3A2E2A), whisker: RGB(0x9A8E86), pattern: .solid),
        Coat(id: "cinza", name: "Cinza-azulado",
             base: RGB(0x8E9BAA), shade: RGB(0x5A6573), accent: RGB(0x8E9BAA), accent2: RGB(0x8E9BAA),
             innerEar: RGB(0xD9A3AE), eye: RGB(0xEDBA45), paw: RGB(0xA9B3BF),
             eyeLine: RGB(0x2D333B), mouthLine: RGB(0x2D333B), whisker: RGB(0xE4E8EE), pattern: .solid),
        Coat(id: "cinzabranco", name: "Cinza e branco",
             base: RGB(0x7D8188), shade: RGB(0x4E5157), accent: RGB(0xF7F4EE), accent2: RGB(0xF7F4EE),
             innerEar: RGB(0xE6A1AD), eye: RGB(0x8CC152), paw: RGB(0xF7F4EE),
             eyeLine: RGB(0x2D333B), mouthLine: RGB(0x3A3A40), whisker: RGB(0xB9BBC0), pattern: .bicolor),
    ]

    public static func find(_ id: String?) -> Coat { all.first { $0.id == id } ?? all[0] }

    var tailColor: RGB {
        switch pattern {
        case .siamese: return accent
        case .calico: return accent2
        default: return base
        }
    }

    var lidColor: RGB { pattern == .siamese ? accent : base }

    func earColor(left: Bool) -> RGB {
        switch pattern {
        case .siamese: return accent
        case .calico: return left ? accent : accent2
        default: return base
        }
    }
}
