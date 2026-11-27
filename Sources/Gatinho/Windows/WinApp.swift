#if os(Windows)
import Foundation
import GatinhoCore
import WinSDK

enum WinApp {
    static func main() {
        WinCat.shared = WinCat()
        WinCat.shared.run()
    }
}

/// String do Swift para UTF-16 terminada em zero (o "W" das APIs do Windows).
private func wide(_ s: String) -> [WCHAR] { Array(s.utf16) + [0] }

/// Constantes do Win32 com valor fixo (várias são macros com cast que não chegam ao Swift).
private enum W32 {
    static let wsPopup: DWORD = 0x8000_0000
    static let exLayered: DWORD = 0x0008_0000
    static let exToolWindow: DWORD = 0x0000_0080 // fora da barra de tarefas e do Alt+Tab
    static let exTopmost: DWORD = 0x0000_0008
    static let exNoActivate: DWORD = 0x0800_0000 // nunca rouba o foco
    static let exTransparent: DWORD = 0x0000_0020
    static let gwlExStyle: Int32 = -20

    static let wmDestroy: UINT = 0x0002
    static let wmMouseActivate: UINT = 0x0021
    static let wmCommand: UINT = 0x0111
    static let wmTimer: UINT = 0x0113
    static let wmMouseMove: UINT = 0x0200
    static let wmLButtonDown: UINT = 0x0201
    static let wmLButtonUp: UINT = 0x0202
    static let wmRButtonDown: UINT = 0x0204
    static let wmRButtonUp: UINT = 0x0205
    static let wmMButtonDown: UINT = 0x0207
    static let wmMButtonUp: UINT = 0x0208
    static let wmMouseWheel: UINT = 0x020A
    static let wmKeyDown: UINT = 0x0100
    static let wmKeyUp: UINT = 0x0101
    static let wmSysKeyDown: UINT = 0x0104
    static let wmSysKeyUp: UINT = 0x0105
    static let wmNCLButtonDown: UINT = 0x00A1
    static let wmExitSizeMove: UINT = 0x0232
    static let wmDpiChanged: UINT = 0x02E0
    static let wmTray: UINT = 0x8001 // WM_APP + 1

    static let htCaption: WPARAM = 2
    static let maNoActivate: LRESULT = 3

    static let mfString: UINT = 0x0000
    static let mfChecked: UINT = 0x0008
    static let mfPopup: UINT = 0x0010
    static let mfSeparator: UINT = 0x0800
    static let tpmRightButton: UINT = 0x0002

    static let swpNoZOrder: UINT = 0x0004
    static let swpNoActivate: UINT = 0x0010
}

/// Ids dos itens do menu.
private enum Cmd {
    static let coat = 100, size = 200, opacity = 300
    static let keys = 400, lock = 401, quit = 402, purr = 403
}

/// O gato no Windows: janela em camadas desenhada pelo SoftPainter.
/// Teclado e mouse globais por ganchos de baixo nível (WH_KEYBOARD_LL / WH_MOUSE_LL),
/// que não pedem permissão de administrador. Nada do que é digitado é gravado.
final class WinCat {
    static var shared: WinCat!

    let cat: DesktopCat
    private let purr = WinPurr()
    private let hInstance = GetModuleHandleW(nil)
    private let className = wide("GatinhoCat")
    private var hwnd: HWND?

    private var screenDC: HDC?
    private var memDC: HDC?
    private var dib: HBITMAP?
    private var oldBitmap: HGDIOBJ?
    private var bits: UnsafeMutableRawPointer?
    private var dibW = 0, dibH = 0

    private var keyboardHook: HHOOK?
    private var mouseHook: HHOOK?
    private var heldVK = Set<DWORD>()
    private var icon: HICON?

    init() {
        // Coordenadas em pixels físicos em todos os monitores, cada um com sua escala.
        _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4)) // PER_MONITOR_AWARE_V2
        let env = ProcessInfo.processInfo.environment
        let base = env["APPDATA"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("AppData/Roaming")
        cat = DesktopCat(settingsURL: base.appendingPathComponent("Gatinho/settings.json"),
                         labelStyle: .windows, dpi: CGFloat(GetDpiForSystem()) / 96)
        cat.sim.onPurrChange = { [weak self] on in
            guard let self else { return }
            purr.set(on && cat.purrSound)
        }
    }

    func run() {
        icon = makeIcon()
        createWindow()
        addTrayIcon()
        installHooks()
        var msg = MSG()
        while GetMessageW(&msg, nil, 0, 0) {
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
        }
    }

    // MARK: - Janela

    private func createWindow() {
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.lpfnWndProc = { h, m, w, l in WinCat.shared.wndProc(h, m, w, l) }
        wc.hInstance = hInstance
        wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)) // IDC_ARROW
        wc.hIcon = icon
        wc.hIconSm = icon
        className.withUnsafeBufferPointer { name in
            wc.lpszClassName = name.baseAddress
            _ = RegisterClassExW(&wc)
        }

        let w = cat.pixelWidth, h = cat.pixelHeight
        var (x, y) = defaultOrigin(w: w, h: h)
        if let sx = cat.settings.x, let sy = cat.settings.y,
           MonitorFromPoint(POINT(x: LONG(sx + w / 2), y: LONG(sy + h / 2)), DWORD(0)) != nil { // ainda está numa tela
            (x, y) = (sx, sy)
        }

        let ex = W32.exLayered | W32.exToolWindow | W32.exTopmost | W32.exNoActivate
        hwnd = CreateWindowExW(ex, className, wide("Gatinho"), W32.wsPopup,
                               Int32(x), Int32(y), Int32(w), Int32(h), nil, nil, hInstance, nil)
        guard let hwnd else { fatalError("CreateWindowExW falhou: \(GetLastError())") }

        // O monitor onde a janela abriu pode ter outra escala que o principal.
        let dpi = CGFloat(GetDpiForWindow(hwnd)) / 96
        if abs(dpi - cat.dpi) > 0.01 {
            cat.dpi = dpi
            resizeKeepingCorner()
        }
        screenDC = GetDC(nil)
        memDC = CreateCompatibleDC(screenDC)
        present()
        _ = ShowWindow(hwnd, 4) // SW_SHOWNOACTIVATE
        SetTimer(hwnd, 1, 15, nil) // ~60 quadros por segundo
    }

    /// Canto inferior direito da área de trabalho (acima da barra de tarefas).
    private func defaultOrigin(w: Int, h: Int) -> (Int, Int) {
        var wa = RECT()
        _ = SystemParametersInfoW(UINT(0x0030), 0, &wa, 0) // SPI_GETWORKAREA
        return (Int(wa.right) - w - 30, Int(wa.bottom) - h - 10)
    }

    private func windowRect() -> RECT {
        var r = RECT()
        if let hwnd { _ = GetWindowRect(hwnd, &r) }
        return r
    }

    private func resizeKeepingCorner() {
        guard let hwnd else { return }
        let r = windowRect()
        let w = cat.pixelWidth, h = cat.pixelHeight
        _ = SetWindowPos(hwnd, nil, r.right - LONG(w), r.bottom - LONG(h), Int32(w), Int32(h),
                         W32.swpNoZOrder | W32.swpNoActivate)
        savePosition()
    }

    private func savePosition() {
        let r = windowRect()
        cat.setPosition(x: Int(r.left), y: Int(r.top))
    }

    // MARK: - Quadro

    /// Bitmap 32 bits de cima para baixo onde o SoftPainter escreve BGRA pré-multiplicado.
    private func ensureDIB() {
        let w = cat.pixelWidth, h = cat.pixelHeight
        guard w != dibW || h != dibH || dib == nil else { return }
        if let old = oldBitmap { SelectObject(memDC, old) }
        if let d = dib { DeleteObject(UnsafeMutableRawPointer(d)) }

        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = LONG(w)
        bmi.bmiHeader.biHeight = -LONG(h)
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = 0 // BI_RGB
        var p: UnsafeMutableRawPointer?
        dib = CreateDIBSection(screenDC, &bmi, 0, &p, nil, 0) // DIB_RGB_COLORS
        bits = p
        oldBitmap = SelectObject(memDC, UnsafeMutableRawPointer(dib))
        dibW = w
        dibH = h
    }

    private func present() {
        guard let hwnd else { return }
        ensureDIB()
        guard let bits else { return }
        var cursor = POINT()
        _ = GetCursorPos(&cursor)
        let r = windowRect()
        cat.renderFrame(time: Date().timeIntervalSinceReferenceDate,
                        pointer: CGPoint(x: Int(cursor.x), y: Int(cursor.y)),
                        windowFrame: CGRect(x: Int(r.left), y: Int(r.top), width: dibW, height: dibH))
        GdiFlush()
        cat.canvas.writeBGRA(into: bits.assumingMemoryBound(to: UInt8.self), opacity: cat.opacity)

        var size = SIZE(cx: LONG(dibW), cy: LONG(dibH))
        var src = POINT(x: 0, y: 0)
        var blend = BLENDFUNCTION(BlendOp: 0, BlendFlags: 0, SourceConstantAlpha: 255, AlphaFormat: 1) // AC_SRC_ALPHA
        _ = UpdateLayeredWindow(hwnd, screenDC, nil, &size, memDC, &src, 0, &blend, 2) // ULW_ALPHA
    }

    // MARK: - Mensagens da janela

    private func clientPoint(_ lp: LPARAM) -> CGPoint {
        let x = Int16(truncatingIfNeeded: lp & 0xFFFF)
        let y = Int16(truncatingIfNeeded: (lp >> 16) & 0xFFFF)
        return cat.designPoint(x: Double(x), y: Double(y))
    }

    fileprivate func wndProc(_ h: HWND?, _ msg: UINT, _ wp: WPARAM, _ lp: LPARAM) -> LRESULT {
        switch msg {
        case W32.wmTimer:
            present()
            return 0
        case W32.wmMouseActivate:
            return W32.maNoActivate
        case W32.wmLButtonDown:
            let p = clientPoint(lp)
            if Geo.hitsHead(p) {
                cat.sim.beginPet(at: p)
                SetCapture(h)
            } else {
                // Deixa o Windows arrastar a janela como se fosse a barra de título.
                _ = ReleaseCapture()
                _ = SendMessageW(h, W32.wmNCLButtonDown, W32.htCaption, 0)
            }
            return 0
        case W32.wmMouseMove:
            if cat.sim.petting { cat.sim.movePet(to: clientPoint(lp)) }
            return 0
        case W32.wmLButtonUp:
            cat.sim.endPet()
            _ = ReleaseCapture()
            return 0
        case W32.wmRButtonUp:
            showMenu()
            return 0
        case W32.wmExitSizeMove:
            savePosition()
            return 0
        case W32.wmDpiChanged:
            cat.dpi = CGFloat(wp & 0xFFFF) / 96
            resizeKeepingCorner()
            return 0
        case W32.wmTray:
            let event = UINT(lp & 0xFFFF)
            if event == W32.wmRButtonUp || event == W32.wmLButtonUp { showMenu() }
            return 0
        case W32.wmCommand:
            command(Int(wp & 0xFFFF))
            return 0
        case W32.wmDestroy:
            if let k = keyboardHook { _ = UnhookWindowsHookEx(k) }
            if let m = mouseHook { _ = UnhookWindowsHookEx(m) }
            removeTrayIcon()
            PostQuitMessage(0)
            return 0
        default:
            return DefWindowProcW(h, msg, wp, lp)
        }
    }

    // MARK: - Menu

    private func append(_ menu: HMENU?, _ title: String, id: Int, checked: Bool = false) {
        _ = AppendMenuW(menu, W32.mfString | (checked ? W32.mfChecked : 0), UINT_PTR(id), wide(title))
    }

    private func submenu(_ menu: HMENU?, _ title: String, _ sub: HMENU?) {
        _ = AppendMenuW(menu, W32.mfPopup, UINT_PTR(UInt(bitPattern: sub)), wide(title))
    }

    private func showMenu() {
        guard let hwnd else { return }
        let menu = CreatePopupMenu()

        let coats = CreatePopupMenu()
        for (i, c) in Coat.all.enumerated() {
            append(coats, c.name, id: Cmd.coat + i, checked: c.id == cat.sim.coat.id)
        }
        submenu(menu, "Pelagem", coats)

        let sizes = CreatePopupMenu()
        for (i, s) in Settings.sizes.enumerated() {
            append(sizes, s.0, id: Cmd.size + i, checked: abs(s.1 - cat.settings.scale) < 0.01)
        }
        submenu(menu, "Tamanho", sizes)

        let ops = CreatePopupMenu()
        for (i, o) in Settings.opacities.enumerated() {
            append(ops, "\(Int(o * 100))%", id: Cmd.opacity + i, checked: abs(o - cat.settings.opacity) < 0.01)
        }
        submenu(menu, "Opacidade", ops)

        append(menu, "Mostrar teclas digitadas", id: Cmd.keys, checked: cat.sim.showKeyLabels)
        append(menu, "Ronronar com som", id: Cmd.purr, checked: cat.purrSound)
        append(menu, "Travar no lugar (cliques atravessam)\tCtrl+Alt+L", id: Cmd.lock, checked: cat.locked)
        _ = AppendMenuW(menu, W32.mfSeparator, 0, nil)
        append(menu, "Sair do Gatinho", id: Cmd.quit)

        var pt = POINT()
        _ = GetCursorPos(&pt)
        // Sem isso o menu não fecha ao clicar fora (comportamento documentado do TrackPopupMenu).
        _ = SetForegroundWindow(hwnd)
        _ = TrackPopupMenu(menu, W32.tpmRightButton, pt.x, pt.y, 0, hwnd, nil)
        _ = PostMessageW(hwnd, 0, 0, 0) // WM_NULL
        _ = DestroyMenu(menu)
    }

    private func command(_ id: Int) {
        switch id {
        case Cmd.coat..<(Cmd.coat + Coat.all.count):
            cat.setCoat(Coat.all[id - Cmd.coat].id)
        case Cmd.size..<(Cmd.size + Settings.sizes.count):
            cat.setScale(Settings.sizes[id - Cmd.size].1)
            resizeKeepingCorner()
        case Cmd.opacity..<(Cmd.opacity + Settings.opacities.count):
            cat.setOpacity(Settings.opacities[id - Cmd.opacity])
        case Cmd.keys:
            cat.toggleKeys()
        case Cmd.purr:
            cat.togglePurrSound()
            purr.set(cat.sim.purring && cat.purrSound)
        case Cmd.lock:
            toggleLock()
        case Cmd.quit:
            if let hwnd { _ = DestroyWindow(hwnd) }
        default:
            break
        }
    }

    private func toggleLock() {
        guard let hwnd else { return }
        cat.locked.toggle()
        var ex = GetWindowLongPtrW(hwnd, W32.gwlExStyle)
        let flag = LONG_PTR(W32.exTransparent)
        if cat.locked { ex |= flag } else { ex &= ~flag }
        _ = SetWindowLongPtrW(hwnd, W32.gwlExStyle, ex)
    }

    // MARK: - Bandeja do sistema

    private func trayData() -> NOTIFYICONDATAW {
        var nid = NOTIFYICONDATAW()
        nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        nid.hWnd = hwnd
        nid.uID = 1
        return nid
    }

    /// Ícone perto do relógio: dá para abrir o menu mesmo com o gato travado.
    private func addTrayIcon() {
        var nid = trayData()
        nid.uFlags = UINT(0x1 | 0x2 | 0x4) // NIF_MESSAGE | NIF_ICON | NIF_TIP
        nid.uCallbackMessage = W32.wmTray
        nid.hIcon = icon
        let tip = Array("Gatinho".utf16) + [0]
        withUnsafeMutableBytes(of: &nid.szTip) { b in
            for (i, c) in tip.enumerated() where (i + 1) * 2 <= b.count {
                b.storeBytes(of: c, toByteOffset: i * 2, as: UInt16.self)
            }
        }
        _ = Shell_NotifyIconW(DWORD(0), &nid) // NIM_ADD
    }

    private func removeTrayIcon() {
        var nid = trayData()
        _ = Shell_NotifyIconW(DWORD(2), &nid) // NIM_DELETE
    }

    /// Ícone 32 x 32 com a cara do próprio gato, desenhado pelo SoftPainter.
    private func makeIcon() -> HICON? {
        let n = 32
        let canvas = SoftCanvas(width: n, height: n)
        let painter = SoftPainter(canvas)
        let s = CGFloat(n) / 150
        painter.translate(-80 * s, -36 * s) // recorta a cabeça (x 80…230, y 36…186 do desenho)
        CatRenderer.draw(cat.sim, painter, scale: s)

        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = LONG(n)
        bmi.bmiHeader.biHeight = -LONG(n)
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        var p: UnsafeMutableRawPointer?
        guard let color = CreateDIBSection(nil, &bmi, 0, &p, nil, 0), let p else { return nil }
        canvas.writeBGRA(into: p.assumingMemoryBound(to: UInt8.self))
        let mask = CreateBitmap(Int32(n), Int32(n), 1, 1, nil)
        var info = ICONINFO()
        info.fIcon = true
        info.hbmMask = mask
        info.hbmColor = color
        let icon = CreateIconIndirect(&info)
        DeleteObject(UnsafeMutableRawPointer(color))
        if let mask { DeleteObject(UnsafeMutableRawPointer(mask)) }
        return icon
    }

    // MARK: - Teclado e mouse globais

    private func installHooks() {
        keyboardHook = SetWindowsHookExW(13, { c, w, l in WinCat.shared.keyboard(c, w, l) }, hInstance, 0) // WH_KEYBOARD_LL
        mouseHook = SetWindowsHookExW(14, { c, w, l in WinCat.shared.mouse(c, w, l) }, hInstance, 0)       // WH_MOUSE_LL
    }

    fileprivate func keyboard(_ code: Int32, _ wp: WPARAM, _ lp: LPARAM) -> LRESULT {
        if code >= 0, let k = UnsafePointer<KBDLLHOOKSTRUCT>(bitPattern: Int(lp))?.pointee {
            let msg = UINT(wp)
            let vk = k.vkCode
            let mac = KeyMaps.macCode(windowsVK: UInt32(vk))
            let id = mac == 0xFFFF ? UInt16(0x8000 | (vk & 0xFF)) : mac // sem par no Mac: id próprio
            if msg == W32.wmKeyDown || msg == W32.wmSysKeyDown {
                // O gancho não marca repetição: tecla que já estava descida é repetição.
                let isRepeat = !heldVK.insert(vk).inserted
                if cat.isLockHotkey(macCode: mac, isRepeat: isRepeat) { toggleLock() }
                cat.sim.keyDown(code: id, label: label(vk: vk, mac: mac), isRepeat: isRepeat)
            } else if msg == W32.wmKeyUp || msg == W32.wmSysKeyUp {
                heldVK.remove(vk)
                cat.sim.keyUp(code: id)
            }
        }
        return CallNextHookEx(nil, code, wp, lp)
    }

    fileprivate func mouse(_ code: Int32, _ wp: WPARAM, _ lp: LPARAM) -> LRESULT {
        if code >= 0 {
            switch UINT(wp) {
            case W32.wmLButtonDown: cat.sim.mouseButton(0, down: true)
            case W32.wmLButtonUp: cat.sim.mouseButton(0, down: false)
            case W32.wmRButtonDown: cat.sim.mouseButton(1, down: true)
            case W32.wmRButtonUp: cat.sim.mouseButton(1, down: false)
            case W32.wmMButtonDown: cat.sim.mouseButton(2, down: true)
            case W32.wmMButtonUp: cat.sim.mouseButton(2, down: false)
            case W32.wmMouseWheel:
                if let m = UnsafePointer<MSLLHOOKSTRUCT>(bitPattern: Int(lp))?.pointee {
                    let delta = Int16(truncatingIfNeeded: m.mouseData >> 16)
                    cat.sim.scroll(CGFloat(delta) / 120 * 1.5)
                }
            default:
                break
            }
        }
        return CallNextHookEx(nil, code, wp, lp)
    }

    /// Símbolo da tecla especial ou o caractere do layout ativo (ABNT2 mostra Ç).
    private func label(vk: DWORD, mac: UInt16) -> String {
        let special = KeyLabels.label(code: mac, style: .windows)
        if special.count > 1 || (!special.isEmpty && "⏎⌫⌦␣⇥⇧⌘⌥⌃⇪←→↑↓".contains(special)) { return special }
        let ch = MapVirtualKeyW(UINT(vk), 2) & 0x7FFF // MAPVK_VK_TO_CHAR
        if ch >= 0x21, let u = Unicode.Scalar(ch) { return String(Character(u)).uppercased() }
        return special
    }
}
#endif
