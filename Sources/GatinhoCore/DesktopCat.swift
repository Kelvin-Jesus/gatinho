// Fora do site: depende de Foundation (arquivos, Data, URL).
#if !GATINHO_WEB
import Foundation

/// Parte comum do app no Windows e no Linux: preferências, escala, quadro em software e menu.
/// Cada sistema só cuida da janela e da entrada, e pergunta a esta classe o que desenhar.
public final class DesktopCat {
    public let sim: CatSim
    public private(set) var settings: Settings
    private let settingsURL: URL
    public let menu = OverlayMenu()
    public private(set) var canvas: SoftCanvas
    public var locked = false

    /// Pixels por ponto do monitor (1 em 96 dpi, 2 em telas HiDPI).
    public var dpi: CGFloat { didSet { resizeCanvas() } }

    public init(settingsURL: URL, labelStyle: LabelStyle, dpi: CGFloat = 1) {
        self.settingsURL = settingsURL
        settings = Settings.load(settingsURL)
        self.dpi = dpi
        sim = CatSim(coat: Coat.find(settings.coat))
        sim.labelStyle = labelStyle
        sim.showKeyLabels = settings.showKeys
        canvas = SoftCanvas(width: 1, height: 1)
        resizeCanvas()
    }

    // MARK: - Tamanho

    /// Pixels de tela por ponto do desenho.
    public var pixelScale: CGFloat { CGFloat(settings.scale) * dpi }
    public var pixelWidth: Int { Int((Geo.size.width * pixelScale).rounded()) }
    public var pixelHeight: Int { Int((Geo.size.height * pixelScale).rounded()) }

    private func resizeCanvas() {
        sim.screenScale = pixelScale
        if canvas.width != pixelWidth || canvas.height != pixelHeight {
            canvas = SoftCanvas(width: pixelWidth, height: pixelHeight)
        }
    }

    /// Ponto do desenho a partir de um pixel da janela.
    public func designPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) / pixelScale, y: CGFloat(y) / pixelScale)
    }

    // MARK: - Quadro

    /// Anima até `time` e desenha o quadro no `canvas` (BGRA via `canvas.writeBGRA`).
    public func renderFrame(time: TimeInterval, pointer: CGPoint, windowFrame: CGRect) {
        sim.pointer = pointer
        sim.windowFrame = windowFrame
        sim.step(to: time)
        canvas.clear()
        let painter = SoftPainter(canvas)
        CatRenderer.draw(sim, painter, scale: pixelScale)
        menu.draw(painter, scale: pixelScale)
    }

    public var opacity: Float { Float(settings.opacity) }

    // MARK: - Preferências

    public func setCoat(_ id: String) {
        sim.coat = Coat.find(id)
        settings.coat = sim.coat.id
        save()
    }

    public func setScale(_ s: Double) {
        settings.scale = s
        resizeCanvas()
        save()
    }

    public func setOpacity(_ o: Double) {
        settings.opacity = o
        save()
    }

    public func toggleKeys() {
        sim.showKeyLabels.toggle()
        settings.showKeys = sim.showKeyLabels
        save()
    }

    public var purrSound: Bool { settings.purrSound ?? true }

    public func togglePurrSound() {
        settings.purrSound = !purrSound
        save()
    }

    public func setPosition(x: Int, y: Int) {
        settings.x = x
        settings.y = y
        save()
    }

    private func save() { settings.save(settingsURL) }

    // MARK: - Menu dentro da janela (Linux)

    public enum MenuResult { case none, resized, lockChanged, quit }

    private var coatName: String { sim.coat.name }
    private var sizeName: String {
        Settings.sizes.first { abs($0.1 - settings.scale) < 0.01 }?.0 ?? "Normal"
    }

    /// Linhas do menu: as três primeiras giram entre as opções a cada clique
    /// (botão esquerdo avança, direito volta), para o menu caber na janela do gato.
    public func refreshMenuRows() {
        menu.rows = [
            "Pelagem: \(coatName)",
            "Tamanho: \(sizeName)",
            "Opacidade: \(Int((settings.opacity * 100).rounded()))%",
            "[\(sim.showKeyLabels ? "x" : " ")] Mostrar teclas",
            "[\(purrSound ? "x" : " ")] Ronronar com som",
            "Travar no lugar (Ctrl+Alt+L)",
            "Fechar menu",
            "Sair do Gatinho",
        ]
    }

    public func openMenu() {
        refreshMenuRows()
        menu.isOpen = true
        menu.hovered = nil
    }

    public func closeMenu() {
        menu.isOpen = false
        menu.hovered = nil
    }

    private func cycle<T>(_ list: [T], current: Int?, backward: Bool) -> T {
        let i = current ?? 0
        let n = list.count
        return list[(i + (backward ? n - 1 : 1)) % n]
    }

    /// Clique numa linha do menu.
    public func activateMenuRow(_ row: Int, backward: Bool = false) -> MenuResult {
        switch row {
        case 0:
            let i = Coat.all.firstIndex { $0.id == sim.coat.id }
            setCoat(cycle(Coat.all, current: i, backward: backward).id)
        case 1:
            let i = Settings.sizes.firstIndex { abs($0.1 - settings.scale) < 0.01 } ?? 2
            setScale(cycle(Settings.sizes, current: i, backward: backward).1)
            refreshMenuRows()
            return .resized
        case 2:
            let i = Settings.opacities.firstIndex { abs($0 - settings.opacity) < 0.01 }
            setOpacity(cycle(Settings.opacities, current: i, backward: backward))
        case 3:
            toggleKeys()
        case 4:
            togglePurrSound()
        case 5:
            closeMenu()
            locked.toggle()
            return .lockChanged
        case 6:
            closeMenu()
        case 7:
            return .quit
        default:
            break
        }
        refreshMenuRows()
        return .none
    }

    // MARK: - Atalho global

    /// Ctrl+Alt+L (keyCode do Mac 37) alterna o modo "cliques atravessam".
    public func isLockHotkey(macCode: UInt16, isRepeat: Bool) -> Bool {
        guard macCode == 37, !isRepeat else { return false }
        let ctrl = sim.isHeld(59) || sim.isHeld(62)
        let alt = sim.isHeld(58) || sim.isHeld(61)
        return ctrl && alt
    }
}
#endif
