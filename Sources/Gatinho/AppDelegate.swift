import AppKit
import ApplicationServices
import SwiftUI

/// Item de menu que chama uma closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) não usado") }

    @objc private func fire() { handler() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: CatPanel!
    private var host: CatHostingView!
    private var sim: CatSim!
    private var input: InputMonitor!
    private var statusItem: NSStatusItem!
    private let defaults = UserDefaults.standard
    private var locked = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        sim = CatSim(coat: Coat.find(defaults.string(forKey: "coat")))
        sim.scale = defaults.object(forKey: "scale") == nil ? 1 : CGFloat(defaults.double(forKey: "scale"))
        sim.showKeyLabels = defaults.object(forKey: "showKeys") as? Bool ?? true

        makePanel()
        makeStatusItem()

        input = InputMonitor(sim: sim) { [weak self] in self?.toggleLock() }
        input.start()

        if !AXIsProcessTrusted() { requestAccessibility() }
    }

    // MARK: - Janela

    private func makePanel() {
        let size = NSSize(width: Geo.size.width * sim.scale, height: Geo.size.height * sim.scale)
        let origin: NSPoint
        if defaults.object(forKey: "originX") != nil {
            origin = NSPoint(x: defaults.double(forKey: "originX"), y: defaults.double(forKey: "originY"))
        } else {
            let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            origin = NSPoint(x: vf.maxX - size.width - 30, y: vf.minY + 10)
        }

        panel = CatPanel(contentRect: NSRect(origin: origin, size: size),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.alphaValue = defaults.object(forKey: "opacity") == nil ? 1 : CGFloat(defaults.double(forKey: "opacity"))

        host = CatHostingView(rootView: CatRootView(sim: sim, scale: sim.scale))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.sim = sim
        host.menuProvider = { [weak self] in self?.buildMenu() ?? NSMenu() }
        host.onMoved = { [weak self] in self?.windowMoved() }
        panel.contentView = host
        panel.orderFrontRegardless()
        sim.windowFrame = panel.frame

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            self?.windowMoved()
        }
    }

    private func windowMoved() {
        sim.windowFrame = panel.frame
        defaults.set(Double(panel.frame.minX), forKey: "originX")
        defaults.set(Double(panel.frame.minY), forKey: "originY")
    }

    private func setScale(_ s: CGFloat) {
        sim.scale = s
        defaults.set(Double(s), forKey: "scale")
        let size = NSSize(width: Geo.size.width * s, height: Geo.size.height * s)
        // Mantém o canto inferior direito no lugar
        let f = panel.frame
        let newFrame = NSRect(x: f.maxX - size.width, y: f.minY, width: size.width, height: size.height)
        host.rootView = CatRootView(sim: sim, scale: s)
        panel.setFrame(newFrame, display: true)
        host.frame = NSRect(origin: .zero, size: size)
        windowMoved()
    }

    private func setOpacity(_ o: CGFloat) {
        panel.alphaValue = o
        defaults.set(Double(o), forKey: "opacity")
    }

    private func toggleLock() {
        locked.toggle()
        panel.ignoresMouseEvents = locked
        statusItem.button?.image = NSImage(systemSymbolName: locked ? "lock.fill" : "cat.fill",
                                           accessibilityDescription: "Gatinho")
    }

    // MARK: - Menu

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Gatinho")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        populate(m)
        return m
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach { sub.addItem($0) }
        item.submenu = sub
        return item
    }

    private func populate(_ m: NSMenu) {
        m.addItem(submenu("Pelagem", Coat.all.map { coat in
            ActionItem(coat.name, checked: coat.id == sim.coat.id) { [weak self] in
                self?.sim.coat = coat
                self?.defaults.set(coat.id, forKey: "coat")
            }
        }))
        let sizes: [(String, CGFloat)] = [("Mini", 0.6), ("Pequeno", 0.8), ("Normal", 1.0), ("Grande", 1.3)]
        m.addItem(submenu("Tamanho", sizes.map { name, s in
            ActionItem(name, checked: abs(sim.scale - s) < 0.01) { [weak self] in self?.setScale(s) }
        }))
        let opacities: [CGFloat] = [1, 0.85, 0.7, 0.5]
        m.addItem(submenu("Opacidade", opacities.map { o in
            ActionItem("\(Int(o * 100))%", checked: abs(panel.alphaValue - o) < 0.01) { [weak self] in self?.setOpacity(o) }
        }))
        m.addItem(ActionItem("Mostrar teclas digitadas", checked: sim.showKeyLabels) { [weak self] in
            guard let self else { return }
            sim.showKeyLabels.toggle()
            defaults.set(sim.showKeyLabels, forKey: "showKeys")
        })
        m.addItem(ActionItem("Travar no lugar (cliques atravessam)  ⌃⌥L", checked: locked) { [weak self] in
            self?.toggleLock()
        })
        if !AXIsProcessTrusted() {
            m.addItem(.separator())
            m.addItem(ActionItem("Permitir acesso ao teclado…") { [weak self] in self?.requestAccessibility() })
        }
        m.addItem(.separator())
        m.addItem(ActionItem("Sair do Gatinho") { NSApp.terminate(nil) })
    }

    private func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
