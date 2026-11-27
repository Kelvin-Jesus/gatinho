import AppKit

enum Paw { case left, right }

struct KeySlot {
    let codes: [UInt16]
    let rect: CGRect
    let paw: Paw
    let accent: Bool
    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

/// Teclado ANSI em miniatura: cada tecla física (keyCode do macOS) vira uma tecla do desenho.
enum KeyLayout {
    static let board = CGRect(x: 58, y: 228, width: 194, height: 50)
    static let keyArea = CGRect(x: 64, y: 233, width: 182, height: 39)
    static let units: CGFloat = 15

    // (keyCodes, largura em unidades). Cada fileira soma 15 unidades.
    private static let rows: [[([UInt16], CGFloat)]] = [
        [([50, 53], 1), ([18, 122], 1), ([19, 120], 1), ([20, 99], 1), ([21, 118], 1), ([23, 96], 1),
         ([22, 97], 1), ([26, 98], 1), ([28, 100], 1), ([25, 101], 1), ([29, 109], 1), ([27, 103], 1),
         ([24, 111], 1), ([51, 117], 2)],
        [([48], 1.5), ([12], 1), ([13], 1), ([14], 1), ([15], 1), ([17], 1), ([16], 1), ([32], 1),
         ([34], 1), ([31], 1), ([35], 1), ([33], 1), ([30], 1), ([42], 1.5)],
        [([57], 1.75), ([0], 1), ([1], 1), ([2], 1), ([3], 1), ([5], 1), ([4], 1), ([38], 1),
         ([40], 1), ([37], 1), ([41], 1), ([39], 1), ([36, 76], 2.25)],
        [([56], 2.25), ([6], 1), ([7], 1), ([8], 1), ([9], 1), ([11], 1), ([45], 1), ([46], 1),
         ([43], 1), ([47], 1), ([44], 1), ([60], 2.75)],
        [([59, 63], 1), ([58], 1), ([55], 1.5), ([49], 6), ([54], 1.5), ([61, 62], 1),
         ([123], 1), ([125, 126], 1), ([124], 1)],
    ]

    // Onde a mão esquerda termina em cada fileira (em unidades): 5/T/G/B ficam à esquerda.
    private static let splits: [CGFloat] = [6.0, 6.5, 6.75, 7.25, 7.6]
    private static let accentCodes: Set<UInt16> = [50, 36]

    static let slots: [KeySlot] = {
        var out: [KeySlot] = []
        let pitch = keyArea.width / units
        let rowH = keyArea.height / CGFloat(rows.count)
        for (r, row) in rows.enumerated() {
            var x: CGFloat = 0
            for (codes, w) in row {
                let rect = CGRect(x: keyArea.minX + x * pitch + 0.7,
                                  y: keyArea.minY + CGFloat(r) * rowH + 0.7,
                                  width: w * pitch - 1.4, height: rowH - 1.4)
                let mid = x + w / 2
                out.append(KeySlot(codes: codes, rect: rect,
                                   paw: mid < splits[r] ? .left : .right,
                                   accent: codes.contains { accentCodes.contains($0) }))
                x += w
            }
        }
        return out
    }()

    private static let byCode: [UInt16: Int] = {
        var m: [UInt16: Int] = [:]
        for (i, s) in slots.enumerated() { for c in s.codes { m[c] = i } }
        return m
    }()

    /// Tecla desconhecida (teclado numérico etc.) cai no "G", no meio.
    static func slotIndex(for code: UInt16) -> Int { byCode[code] ?? byCode[5]! }
}

enum KeyLabels {
    private static let special: [UInt16: String] = [
        36: "⏎", 76: "⏎", 51: "⌫", 117: "⌦", 49: "␣", 48: "⇥", 53: "esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        56: "⇧", 60: "⇧", 55: "⌘", 54: "⌘", 58: "⌥", 61: "⌥", 59: "⌃", 62: "⌃", 57: "⇪", 63: "fn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func label(code: UInt16) -> String { special[code] ?? "" }

    static func label(for e: NSEvent) -> String {
        if let s = special[e.keyCode] { return s }
        guard let chars = e.charactersIgnoringModifiers, let first = chars.first else { return "" }
        if first.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) { return "" }
        return String(first).uppercased()
    }
}
