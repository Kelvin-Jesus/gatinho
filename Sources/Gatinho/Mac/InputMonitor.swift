#if os(macOS)
import AppKit
import ApplicationServices
import GatinhoCore

/// Escuta teclado e mouse do sistema todo e repassa para o CatSim.
/// Teclado global exige permissão de Acessibilidade; mouse não exige.
final class InputMonitor {
    private let sim: CatSim
    private let onLockHotkey: () -> Void
    private var keyMonitors: [Any] = []
    private var mouseMonitors: [Any] = []
    private var trusted = false
    private var timer: Timer?

    init(sim: CatSim, onLockHotkey: @escaping () -> Void) {
        self.sim = sim
        self.onLockHotkey = onLockHotkey
    }

    private var keyEvents = 0

    /// Diagnóstico em ~/Library/Logs/Gatinho.log (sem conteúdo de teclas: só contagens e estado).
    static func log(_ msg: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Gatinho.log")
        let line = "\(Date()) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    func start() {
        trusted = AXIsProcessTrusted()
        Self.log("início: pid \(getpid()), acessibilidade \(trusted)")
        installKeyMonitors()
        installMouseMonitors()
        // Quando a permissão é concedida com o app aberto, reinstala os monitores de teclado.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkTrust()
        }
    }

    private func checkTrust() {
        let now = AXIsProcessTrusted()
        Self.logCount(keyEvents)
        guard now != trusted else { return }
        Self.log("acessibilidade mudou para \(now)")
        trusted = now
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        keyMonitors.removeAll()
        installKeyMonitors()
    }

    private func installKeyMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handleKey(e) }) {
            keyMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handleKey(e); return e }) {
            keyMonitors.append(l)
        }
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                           .otherMouseDown, .otherMouseUp, .scrollWheel]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handleMouse(e) }) {
            mouseMonitors.append(g)
        }
    }

    private static var lastLogged = -1
    private static func logCount(_ n: Int) {
        guard n != lastLogged else { return }
        lastLogged = n
        log("eventos de teclado recebidos até agora: \(n)")
    }

    private func handleKey(_ e: NSEvent) {
        keyEvents += 1
        switch e.type {
        case .keyDown:
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.keyCode == 37, f.contains(.control), f.contains(.option), !e.isARepeat { // ⌃⌥L
                onLockHotkey()
            }
            sim.keyDown(code: e.keyCode, label: MacKeyLabel.label(for: e), isRepeat: e.isARepeat)
        case .keyUp:
            sim.keyUp(code: e.keyCode)
        case .flagsChanged:
            sim.modifierChanged(code: e.keyCode)
        default:
            break
        }
    }

    private func handleMouse(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown: sim.mouseButton(0, down: true)
        case .leftMouseUp: sim.mouseButton(0, down: false)
        case .rightMouseDown: sim.mouseButton(1, down: true)
        case .rightMouseUp: sim.mouseButton(1, down: false)
        case .otherMouseDown: sim.mouseButton(2, down: true)
        case .otherMouseUp: sim.mouseButton(2, down: false)
        case .scrollWheel:
            let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY * 0.15 : e.scrollingDeltaY * 1.5
            sim.scroll(dy)
        default:
            break
        }
    }
}

enum MacKeyLabel {
    /// Rótulo do keycap: símbolo da tecla especial ou o caractere do layout atual.
    static func label(for e: NSEvent) -> String {
        let special = KeyLabels.label(code: e.keyCode)
        if !special.isEmpty, special.count > 1 || "⏎⌫⌦␣⇥⇧⌘⌥⌃⇪←→↑↓".contains(special) { return special }
        guard let chars = e.charactersIgnoringModifiers, let first = chars.first else { return special }
        if first.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) { return special }
        return String(first).uppercased()
    }
}
#endif
