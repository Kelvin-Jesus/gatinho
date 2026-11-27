#if GATINHO_WEB
import WASILibc
#else
import Foundation
#endif

public enum Paw { case left, right }

struct KeySlot {
    let codes: [UInt16]
    let rect: CGRect
    let paw: Paw
    let accent: Bool
    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

/// Teclado ANSI em miniatura. A identidade de cada tecla é o keyCode virtual do macOS;
/// Windows e Linux traduzem os seus códigos para ele com `KeyMaps`.
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

public enum LabelStyle { case mac, windows, linux }

public enum KeyLabels {
    private static let special: [UInt16: String] = [
        36: "⏎", 76: "⏎", 51: "⌫", 117: "⌦", 49: "␣", 48: "⇥", 53: "ESC",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        56: "⇧", 60: "⇧", 55: "⌘", 54: "⌘", 58: "⌥", 61: "⌥", 59: "⌃", 62: "⌃", 57: "⇪", 63: "FN",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// Caracteres do layout US por keyCode do macOS.
    static let chars: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    ]

    public static func label(code: UInt16, style: LabelStyle = .mac) -> String {
        if style != .mac {
            switch code {
            case 59, 62: return "CTRL"
            case 58, 61: return "ALT"
            case 55, 54: return style == .windows ? "WIN" : "SUPER"
            default: break
            }
        }
        return special[code] ?? chars[code] ?? ""
    }
}

/// Tradução de códigos de tecla de cada sistema para o keyCode do macOS.
public enum KeyMaps {
    private static let letterCodes: [Character: UInt16] = [
        "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34, "J": 38, "K": 40,
        "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1, "T": 17, "U": 32,
        "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6,
    ]
    private static let digitCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25] // 0...9
    private static let fKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    private static let windowsVK: [UInt32: UInt16] = [
        0x0D: 36, 0x08: 51, 0x09: 48, 0x20: 49, 0x1B: 53, 0x2E: 117,
        0x25: 123, 0x26: 126, 0x27: 124, 0x28: 125,
        0xA0: 56, 0xA1: 60, 0xA2: 59, 0xA3: 62, 0xA4: 58, 0xA5: 61, 0x5B: 55, 0x5C: 54,
        0x10: 56, 0x11: 59, 0x12: 58, 0x14: 57,
        0xBA: 41, 0xBB: 24, 0xBC: 43, 0xBD: 27, 0xBE: 47, 0xBF: 44, 0xC0: 50,
        0xDB: 33, 0xDC: 42, 0xDD: 30, 0xDE: 39,
    ]

    /// Virtual-key do Windows (KBDLLHOOKSTRUCT.vkCode).
    public static func macCode(windowsVK vk: UInt32) -> UInt16 {
        if (0x41...0x5A).contains(vk), let c = letterCodes[Character(UnicodeScalar(UInt8(vk)))] { return c }
        if (0x30...0x39).contains(vk) { return digitCodes[Int(vk - 0x30)] }
        if (0x70...0x7B).contains(vk) { return fKeys[Int(vk - 0x70)] }
        return windowsVK[vk] ?? 0xFFFF
    }

    private static let evdev: [UInt16: UInt16] = [
        1: 53, 2: 18, 3: 19, 4: 20, 5: 21, 6: 23, 7: 22, 8: 26, 9: 28, 10: 25, 11: 29,
        12: 27, 13: 24, 14: 51, 15: 48, 16: 12, 17: 13, 18: 14, 19: 15, 20: 17, 21: 16, 22: 32,
        23: 34, 24: 31, 25: 35, 26: 33, 27: 30, 28: 36, 29: 59, 30: 0, 31: 1, 32: 2, 33: 3,
        34: 5, 35: 4, 36: 38, 37: 40, 38: 37, 39: 41, 40: 39, 41: 50, 42: 56, 43: 42,
        44: 6, 45: 7, 46: 8, 47: 9, 48: 11, 49: 45, 50: 46, 51: 43, 52: 47, 53: 44, 54: 60,
        56: 58, 57: 49, 58: 57, 59: 122, 60: 120, 61: 99, 62: 118, 63: 96, 64: 97, 65: 98,
        66: 100, 67: 101, 68: 109, 87: 103, 88: 111, 96: 76, 97: 62, 100: 61,
        103: 126, 105: 123, 106: 124, 108: 125, 111: 117, 125: 55, 126: 54,
    ]

    /// Código de tecla do kernel Linux (KEY_*). No X11, keycode = evdev + 8.
    public static func macCode(evdev code: UInt16) -> UInt16 { evdev[code] ?? 0xFFFF }
}
