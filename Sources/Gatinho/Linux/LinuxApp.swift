#if os(Linux)
import CX11
import Foundation
import GatinhoCore
import Glibc

enum LinuxApp {
    static func main() {
        guard let app = LinuxCat() else { exit(1) }
        app.run()
    }
}

/// Constantes do Xlib definidas como macros com cast (não chegam ao Swift).
private enum X {
    static let cwBackPixel: UInt = 1 << 1
    static let cwBorderPixel: UInt = 1 << 3
    static let cwColormap: UInt = 1 << 13
    static let buttonPressMask = 1 << 2
    static let buttonReleaseMask = 1 << 3
    static let leaveWindowMask = 1 << 5
    static let pointerMotionMask = 1 << 6
    static let exposureMask = 1 << 15
    static let structureNotifyMask = 1 << 17
    static let xaAtom: Atom = 4
    static let xaCardinal: Atom = 6
    static let propModeReplace: Int32 = 0
    static let shapeBounding: Int32 = 0
    static let shapeInput: Int32 = 2
    static let shapeSet: Int32 = 0
    // XInput2
    static let rawKeyPress: Int32 = 13
    static let rawKeyRelease: Int32 = 14
    static let rawButtonPress: Int32 = 15
    static let rawButtonRelease: Int32 = 16
    static let keyRepeatFlag: Int32 = 1 << 16
}

/// O gato no Linux: janela X11 (nativa ou via XWayland) desenhada pelo SoftPainter.
///
/// Transparência: com compositor, janela ARGB de 32 bits; sem compositor, máscara XShape
/// recortada pelo alfa do desenho. Teclado e mouse globais: XInput2 (eventos "raw") no X11,
/// que não pede permissão; no Wayland o X11 não vê o que acontece fora das janelas X, então
/// lê /dev/input direto (o usuário precisa estar no grupo `input`).
final class LinuxCat {
    private let dpy: OpaquePointer
    private let screen: Int32
    private let root: Window
    private let cat: DesktopCat

    private var win: Window = 0
    private var visual: UnsafeMutablePointer<Visual>!
    private var depth: Int32 = 24
    private var gc: GC!
    private var image: UnsafeMutablePointer<XImage>?

    private var winX = 0, winY = 0
    private var curW = 0, curH = 0
    private var composited = false
    private var lastCompositorCheck = 0.0
    private var lastMask: [UInt8] = []
    private var lastShapeMode = ""

    private var atomDelete: Atom = 0
    private var atomCM: Atom = 0
    private var xiOpcode: Int32 = -1
    private var evdevFDs: [Int32] = []

    private var running = true
    private var dragging = false
    private var dragOff = (x: 0, y: 0)

    private var now: TimeInterval { Date().timeIntervalSinceReferenceDate }

    init?() {
        guard let d = XOpenDisplay(nil) else {
            fputs("Gatinho: não encontrei a tela do X11 (variável DISPLAY vazia?).\n", stderr)
            fputs("No Wayland, o Gatinho roda pelo XWayland, que vem ativo na maioria das distros.\n", stderr)
            return nil
        }
        dpy = d
        screen = XDefaultScreen(d)
        root = XRootWindow(d, screen)
        cat = DesktopCat(settingsURL: LinuxCat.settingsURL, labelStyle: .linux, dpi: LinuxCat.readDPI(d))
        atomDelete = atom("WM_DELETE_WINDOW")
        atomCM = atom("_NET_WM_CM_S\(screen)")
        createWindow()
        setupGlobalInput()
    }

    private static var settingsURL: URL {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory()).appendingPathComponent(".config")
        return base.appendingPathComponent("gatinho/settings.json")
    }

    /// Escala da tela: GATINHO_SCALE, senão Xft.dpi / 96 (o que GNOME e KDE publicam em HiDPI).
    private static func readDPI(_ d: OpaquePointer) -> CGFloat {
        if let v = ProcessInfo.processInfo.environment["GATINHO_SCALE"].flatMap(Double.init) {
            return CGFloat(max(0.5, min(4, v)))
        }
        guard let rm = XResourceManagerString(d) else { return 1 }
        for line in String(cString: rm).split(separator: "\n") where line.hasPrefix("Xft.dpi:") {
            if let v = Double(line.dropFirst(8).trimmingCharacters(in: .whitespaces)) {
                return CGFloat(max(1, min(4, v / 96)))
            }
        }
        return 1
    }

    private func atom(_ name: String) -> Atom { XInternAtom(dpy, name, 0) }

    // MARK: - Janela

    private func createWindow() {
        var vinfo = XVisualInfo()
        if XMatchVisualInfo(dpy, screen, 32, TrueColor, &vinfo) != 0 {
            visual = vinfo.visual
            depth = 32
        } else {
            visual = XDefaultVisual(dpy, screen)
            depth = XDefaultDepth(dpy, screen)
        }

        curW = cat.pixelWidth
        curH = cat.pixelHeight
        let sw = Int(XDisplayWidth(dpy, screen)), sh = Int(XDisplayHeight(dpy, screen))
        winX = min(max(cat.settings.x ?? (sw - curW - 30), 0), max(0, sw - 40))
        winY = min(max(cat.settings.y ?? (sh - curH - 60), 0), max(0, sh - 40))

        var attrs = XSetWindowAttributes()
        attrs.colormap = XCreateColormap(dpy, root, visual, AllocNone)
        attrs.border_pixel = 0
        attrs.background_pixel = 0
        win = XCreateWindow(dpy, root, Int32(winX), Int32(winY), UInt32(curW), UInt32(curH), 0, depth,
                            UInt32(InputOutput), visual, X.cwColormap | X.cwBorderPixel | X.cwBackPixel, &attrs)

        XStoreName(dpy, win, "Gatinho")
        if let ch = XAllocClassHint() {
            "gatinho".withCString { n in
                ch.pointee.res_name = UnsafeMutablePointer(mutating: n)
                ch.pointee.res_class = UnsafeMutablePointer(mutating: n)
                XSetClassHint(dpy, win, ch)
            }
            XFree(ch)
        }
        // Nunca recebe o foco do teclado: quem está digitando continua digitando.
        if let wm = XAllocWMHints() {
            wm.pointee.flags = 1 // InputHint
            wm.pointee.input = 0
            XSetWMHints(dpy, win, wm)
            XFree(wm)
        }
        setSizeHints()
        setAtoms("_NET_WM_WINDOW_TYPE", [atom("_NET_WM_WINDOW_TYPE_UTILITY")])
        setAtoms("_NET_WM_STATE", ["_NET_WM_STATE_ABOVE", "_NET_WM_STATE_SKIP_TASKBAR",
                                   "_NET_WM_STATE_SKIP_PAGER", "_NET_WM_STATE_STICKY"].map(atom))
        setLongs("_MOTIF_WM_HINTS", atom("_MOTIF_WM_HINTS"), [2, 0, 0, 0, 0]) // sem decoração
        setLongs("_NET_WM_DESKTOP", X.xaCardinal, [0xFFFF_FFFF])               // todas as áreas de trabalho
        var del = atomDelete
        XSetWMProtocols(dpy, win, &del, 1)

        XSelectInput(dpy, win, X.exposureMask | X.buttonPressMask | X.buttonReleaseMask
            | X.pointerMotionMask | X.structureNotifyMask | X.leaveWindowMask)
        gc = XCreateGC(dpy, win, 0, nil)
        makeImage()
        checkCompositor(force: true)
        XMapWindow(dpy, win)
        XMoveWindow(dpy, win, Int32(winX), Int32(winY)) // alguns gerenciadores ignoram a posição inicial
        XFlush(dpy)
    }

    private func setSizeHints() {
        guard let sh = XAllocSizeHints() else { return }
        sh.pointee.flags = (1 << 0) | (1 << 2) | (1 << 4) | (1 << 5) // USPosition, PPosition, PMinSize, PMaxSize
        sh.pointee.x = Int32(winX)
        sh.pointee.y = Int32(winY)
        sh.pointee.min_width = Int32(curW)
        sh.pointee.max_width = Int32(curW)
        sh.pointee.min_height = Int32(curH)
        sh.pointee.max_height = Int32(curH)
        XSetWMNormalHints(dpy, win, sh)
        XFree(sh)
    }

    private func setAtoms(_ prop: String, _ values: [Atom]) {
        setLongs(prop, X.xaAtom, values.map { UInt($0) })
    }

    /// Propriedade de formato 32: no Xlib, cada item ocupa um `long`.
    private func setLongs(_ prop: String, _ type: Atom, _ values: [UInt]) {
        values.withUnsafeBytes { b in
            _ = XChangeProperty(dpy, win, atom(prop), type, 32, X.propModeReplace,
                                b.baseAddress!.assumingMemoryBound(to: UInt8.self), Int32(values.count))
        }
    }

    private func makeImage() {
        if let old = image { _ = old.pointee.f.destroy_image?(old) } // libera também o buffer
        let bytes = curW * curH * 4
        let data = malloc(bytes)!.assumingMemoryBound(to: CChar.self)
        image = XCreateImage(dpy, visual, UInt32(depth), ZPixmap, 0, data, UInt32(curW), UInt32(curH), 32, 0)
        lastMask = []
    }

    private func applyResize() {
        let w = cat.pixelWidth, h = cat.pixelHeight
        guard w != curW || h != curH else { return }
        // Mantém o canto inferior direito no lugar, como no Mac.
        winX += curW - w
        winY += curH - h
        curW = w
        curH = h
        setSizeHints()
        XMoveResizeWindow(dpy, win, Int32(winX), Int32(winY), UInt32(w), UInt32(h))
        makeImage()
        cat.setPosition(x: winX, y: winY)
    }

    private func checkCompositor(force: Bool = false) {
        let t = now
        guard force || t - lastCompositorCheck > 2 else { return }
        lastCompositorCheck = t
        // Sem visual de 32 bits não há transparência real, mesmo com compositor.
        let c = depth == 32 && XGetSelectionOwner(dpy, atomCM) != 0
        if c != composited || force {
            composited = c
            lastShapeMode = ""
        }
    }

    // MARK: - Quadro

    private func pointer() -> CGPoint {
        var r: Window = 0, c: Window = 0
        var rx: Int32 = 0, ry: Int32 = 0, wx: Int32 = 0, wy: Int32 = 0
        var m: UInt32 = 0
        XQueryPointer(dpy, root, &r, &c, &rx, &ry, &wx, &wy, &m)
        return CGPoint(x: CGFloat(rx), y: CGFloat(ry))
    }

    private func present() {
        guard let img = image else { return }
        checkCompositor()
        let frame = CGRect(x: winX, y: winY, width: curW, height: curH)
        cat.renderFrame(time: now, pointer: pointer(), windowFrame: frame)

        let count = curW * curH
        img.pointee.data.withMemoryRebound(to: UInt8.self, capacity: count * 4) { px in
            if composited {
                cat.canvas.writeBGRA(into: px, opacity: cat.opacity)
            } else {
                // Sem compositor o fundo some pela máscara; cores sem pré-multiplicar evitam borda escura.
                cat.canvas.writeBGRA(into: px, opacity: 1)
                for i in 0..<count {
                    let a = Int(px[i * 4 + 3])
                    guard a > 0, a < 255 else { continue }
                    for k in 0..<3 { px[i * 4 + k] = UInt8(min(255, Int(px[i * 4 + k]) * 255 / a)) }
                }
            }
            updateShape(px)
        }
        XPutImage(dpy, win, gc, img, 0, 0, 0, 0, UInt32(curW), UInt32(curH))
        XFlush(dpy)
    }

    /// Recorta a janela pelo alfa: sem compositor, recorta o desenho; com compositor, só a
    /// área que recebe cliques (o transparente deixa o clique passar, como no Mac).
    private func updateShape(_ px: UnsafeMutablePointer<UInt8>) {
        let stride = (curW + 7) / 8
        var mask = [UInt8](repeating: 0, count: stride * curH)
        for y in 0..<curH {
            let row = y * curW
            for x in 0..<curW where px[(row + x) * 4 + 3] >= 128 {
                mask[y * stride + x >> 3] |= UInt8(1 << (x & 7))
            }
        }
        let mode = "\(composited)-\(cat.locked)"
        guard mode != lastShapeMode || mask != lastMask else { return }
        let modeChanged = mode != lastShapeMode
        lastShapeMode = mode
        lastMask = mask

        let pixmap = mask.withUnsafeBufferPointer { b in
            b.baseAddress!.withMemoryRebound(to: CChar.self, capacity: b.count) {
                XCreateBitmapFromData(dpy, win, $0, UInt32(curW), UInt32(curH))
            }
        }
        defer { XFreePixmap(dpy, pixmap) }

        if composited {
            if modeChanged { XShapeCombineMask(dpy, win, X.shapeBounding, 0, 0, 0, X.shapeSet) }
            if cat.locked {
                if modeChanged { XShapeCombineRectangles(dpy, win, X.shapeInput, 0, 0, nil, 0, X.shapeSet, 0) }
            } else {
                XShapeCombineMask(dpy, win, X.shapeInput, 0, 0, pixmap, X.shapeSet)
            }
        } else {
            XShapeCombineMask(dpy, win, X.shapeBounding, 0, 0, pixmap, X.shapeSet)
            if modeChanged {
                if cat.locked {
                    XShapeCombineRectangles(dpy, win, X.shapeInput, 0, 0, nil, 0, X.shapeSet, 0)
                } else {
                    XShapeCombineMask(dpy, win, X.shapeInput, 0, 0, 0, X.shapeSet)
                }
            }
        }
    }

    // MARK: - Laço principal

    func run() {
        let frame = 1.0 / 60
        var next = now
        while running {
            pumpX()
            pumpEvdev()
            let t = now
            if t >= next {
                present()
                next += frame
                if next < t { next = t + frame }
            }
            if XPending(dpy) == 0 {
                var fds = [pollfd(fd: XConnectionNumber(dpy), events: Int16(POLLIN), revents: 0)]
                fds += evdevFDs.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
                let ms = Int32(max(0, (next - now) * 1000))
                _ = poll(&fds, nfds_t(fds.count), ms)
            }
        }
        evdevFDs.forEach { close($0) }
        XCloseDisplay(dpy)
    }

    private func pumpX() {
        var ev = XEvent()
        while XPending(dpy) > 0 {
            XNextEvent(dpy, &ev)
            handle(&ev)
        }
    }

    private func handle(_ ev: inout XEvent) {
        switch ev.type {
        case ButtonPress:
            buttonPress(ev.xbutton)
        case ButtonRelease:
            if ev.xbutton.button == 1 {
                if dragging {
                    dragging = false
                    cat.setPosition(x: winX, y: winY)
                }
                cat.sim.endPet()
            }
        case MotionNotify:
            motion(ev.xmotion)
        case LeaveNotify:
            if cat.menu.isOpen { cat.menu.hovered = nil }
        case ConfigureNotify:
            if !dragging {
                var x: Int32 = 0, y: Int32 = 0
                var child: Window = 0
                XTranslateCoordinates(dpy, win, root, 0, 0, &x, &y, &child)
                winX = Int(x)
                winY = Int(y)
            }
        case ClientMessage:
            if UInt(bitPattern: ev.xclient.data.l.0) == atomDelete { running = false }
        case GenericEvent:
            guard ev.xcookie.extension == xiOpcode, XGetEventData(dpy, &ev.xcookie) != 0 else { return }
            defer { XFreeEventData(dpy, &ev.xcookie) }
            let raw = ev.xcookie.data.assumingMemoryBound(to: XIRawEvent.self).pointee
            switch ev.xcookie.evtype {
            case X.rawKeyPress:
                key(evdev: UInt16(max(0, raw.detail - 8)), down: true, isRepeat: raw.flags & X.keyRepeatFlag != 0)
            case X.rawKeyRelease:
                key(evdev: UInt16(max(0, raw.detail - 8)), down: false, isRepeat: false)
            case X.rawButtonPress:
                globalButton(Int(raw.detail), down: true)
            case X.rawButtonRelease:
                globalButton(Int(raw.detail), down: false)
            default:
                break
            }
        default:
            break
        }
    }

    private func buttonPress(_ b: XButtonEvent) {
        let p = cat.designPoint(x: Double(b.x), y: Double(b.y))
        if cat.menu.isOpen {
            guard b.button == 1 || b.button == 3 else { return }
            if let row = cat.menu.row(at: p) {
                switch cat.activateMenuRow(row, backward: b.button == 3) {
                case .resized: applyResize()
                case .lockChanged: lockChanged()
                case .quit: running = false
                case .none: break
                }
            } else {
                cat.closeMenu()
            }
            return
        }
        switch b.button {
        case 1:
            if Geo.hitsHead(p) {
                cat.sim.beginPet(at: p)
            } else {
                dragging = true
                dragOff = (Int(b.x_root) - winX, Int(b.y_root) - winY)
            }
        case 3:
            cat.openMenu()
        default:
            break
        }
    }

    private func motion(_ m: XMotionEvent) {
        if dragging {
            winX = Int(m.x_root) - dragOff.x
            winY = Int(m.y_root) - dragOff.y
            XMoveWindow(dpy, win, Int32(winX), Int32(winY))
        } else if cat.sim.petting {
            cat.sim.movePet(to: cat.designPoint(x: Double(m.x), y: Double(m.y)))
        } else if cat.menu.isOpen {
            cat.menu.hovered = cat.menu.row(at: cat.designPoint(x: Double(m.x), y: Double(m.y)))
        }
    }

    private func lockChanged() {
        lastShapeMode = ""
        print(cat.locked ? "Gatinho travado: cliques atravessam. Ctrl+Alt+L destrava."
                         : "Gatinho destravado.")
    }

    // MARK: - Entrada global

    private func setupGlobalInput() {
        let env = ProcessInfo.processInfo.environment
        let wayland = env["WAYLAND_DISPLAY"] != nil || env["XDG_SESSION_TYPE"] == "wayland"
        let choice = env["GATINHO_INPUT"] ?? (wayland ? "evdev" : "xi2")
        if choice == "evdev" {
            openEvdev()
            if evdevFDs.isEmpty {
                fputs("""
                Gatinho: sem acesso a /dev/input, então só vejo o teclado e o mouse sobre janelas X11.
                Para o gato ver tudo no Wayland, entre no grupo input e faça login de novo:
                    sudo usermod -aG input $USER

                """, stderr)
                setupXI2()
            }
        } else {
            setupXI2()
        }
    }

    private func setupXI2() {
        var op: Int32 = 0, evb: Int32 = 0, erb: Int32 = 0
        guard XQueryExtension(dpy, "XInputExtension", &op, &evb, &erb) != 0 else {
            fputs("Gatinho: o servidor X não tem XInput2; o gato não vai ver o teclado.\n", stderr)
            return
        }
        var major: Int32 = 2, minor: Int32 = 0
        guard XIQueryVersion(dpy, &major, &minor) == Success else { return }
        xiOpcode = op
        var bits = [UInt8](repeating: 0, count: 3)
        for e in [X.rawKeyPress, X.rawKeyRelease, X.rawButtonPress, X.rawButtonRelease] {
            bits[Int(e >> 3)] |= UInt8(1 << (e & 7))
        }
        bits.withUnsafeMutableBufferPointer { b in
            var mask = XIEventMask(deviceid: XIAllMasterDevices, mask_len: Int32(b.count), mask: b.baseAddress)
            _ = XISelectEvents(dpy, root, &mask, 1)
        }
        XFlush(dpy)
    }

    private func openEvdev() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev/input")) ?? []
        for n in names where n.hasPrefix("event") {
            let fd = open("/dev/input/\(n)", O_RDONLY | O_NONBLOCK)
            if fd >= 0 { evdevFDs.append(fd) }
        }
    }

    private func pumpEvdev() {
        guard !evdevFDs.isEmpty else { return }
        let size = MemoryLayout<input_event>.stride
        var buf = [input_event](repeating: input_event(), count: 64)
        for fd in evdevFDs {
            while true {
                let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                guard n > 0 else { break }
                for e in buf.prefix(n / size) {
                    switch Int32(e.type) {
                    case EV_KEY:
                        if (BTN_LEFT...BTN_MIDDLE).contains(Int32(e.code)) {
                            guard e.value != 2 else { continue }
                            let b = [BTN_LEFT: 1, BTN_RIGHT: 3, BTN_MIDDLE: 2][Int32(e.code)] ?? 1
                            globalButton(b, down: e.value == 1)
                        } else if e.code < BTN_MISC {
                            key(evdev: e.code, down: e.value != 0, isRepeat: e.value == 2)
                        }
                    case EV_REL where Int32(e.code) == REL_WHEEL:
                        cat.sim.scroll(CGFloat(e.value) * 1.5)
                    default:
                        break
                    }
                }
            }
        }
    }

    /// Botões no padrão do X: 1 esquerdo, 2 meio, 3 direito, 4/5 rodinha.
    private func globalButton(_ b: Int, down: Bool) {
        switch b {
        case 1: cat.sim.mouseButton(0, down: down)
        case 2: cat.sim.mouseButton(2, down: down)
        case 3: cat.sim.mouseButton(1, down: down)
        case 4 where down: cat.sim.scroll(1.5)
        case 5 where down: cat.sim.scroll(-1.5)
        default: break
        }
    }

    private func key(evdev code: UInt16, down: Bool, isRepeat: Bool) {
        let mac = KeyMaps.macCode(evdev: code)
        let id = mac == 0xFFFF ? 0x8000 | code : mac // tecla sem par no Mac: id próprio, cai no meio do teclado
        guard down else {
            cat.sim.keyUp(code: id)
            return
        }
        if mac == 53, cat.menu.isOpen { cat.closeMenu() } // Esc fecha o menu
        if cat.isLockHotkey(macCode: mac, isRepeat: isRepeat) {
            cat.locked.toggle()
            lockChanged()
        }
        cat.sim.keyDown(code: id, label: label(evdev: code, mac: mac), isRepeat: isRepeat)
    }

    /// Símbolo da tecla especial ou o caractere do layout ativo (ABNT2 mostra Ç, por exemplo).
    private func label(evdev code: UInt16, mac: UInt16) -> String {
        let special = KeyLabels.label(code: mac, style: .linux)
        if special.count > 1 || (!special.isEmpty && "⏎⌫⌦␣⇥⇧⌘⌥⌃⇪←→↑↓".contains(special)) { return special }
        let ks = XkbKeycodeToKeysym(dpy, KeyCode(truncatingIfNeeded: Int(code) + 8), 0, 0)
        if (0x21...0x7E).contains(ks) || (0xC0...0xFF).contains(ks), let u = Unicode.Scalar(UInt32(ks)) {
            return String(Character(u)).uppercased()
        }
        return special
    }
}
#endif
