import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    MainActor.assumeIsolated { Snapshot.render(to: args[i + 1]) }
    exit(0)
}

if args.contains("--check-smooth") {
    exit(Snapshot.checkSmoothness() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // sem ícone no Dock; vive na barra de menus
app.run()
