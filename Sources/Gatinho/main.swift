import Foundation
import GatinhoCore
#if os(macOS)
import AppKit
#endif

let args = CommandLine.arguments

// Ferramentas de verificação (iguais nos 3 sistemas, sem abrir janela).
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    exit(SelfTest.snapshot(to: args[i + 1], withMenu: args.contains("--menu")) ? 0 : 1)
}
if args.contains("--check-smooth") {
    exit(SelfTest.checkSmoothness() ? 0 : 1)
}
// --scale 3 e --bg F7EEDF valem para --record e --stills.
func option(_ name: String) -> String? {
    args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
}
let recScale = option("--scale").flatMap(Double.init).map { CGFloat($0) }
let recBG = option("--bg").flatMap { UInt32($0, radix: 16) }.map { RGB($0) } ?? RGB(0xF7EEDF)
if let i = args.firstIndex(of: "--record"), i + 2 < args.count {
    exit(Recorder.record(args[i + 1], to: args[i + 2], scale: recScale ?? 1.5, background: recBG) ? 0 : 1)
}
if let dir = option("--stills") {
    exit(SelfTest.stills(to: dir, scale: recScale ?? 3, background: recBG) ? 0 : 1)
}
if let i = args.firstIndex(of: "--purr"), i + 1 < args.count {
    // Grava o som do ronronar (6 s) num .wav, para ouvir sem abrir o gato.
    exit((try? Purr.wav(seconds: 6).write(to: URL(fileURLWithPath: args[i + 1]))) != nil ? 0 : 1)
}
if args.contains("--benchmark") {
    SelfTest.benchmark(scale: 1)
    SelfTest.benchmark(scale: 2)
    exit(0)
}

#if os(macOS)
if let i = args.firstIndex(of: "--snapshot-swiftui"), i + 1 < args.count {
    MainActor.assumeIsolated { MacSnapshot.render(to: args[i + 1]) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // sem ícone no Dock; vive na barra de menus
app.run()

#elseif os(Windows)
WinApp.main()

#elseif os(Linux)
LinuxApp.main()
#endif
