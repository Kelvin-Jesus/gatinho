// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Gatinho",
    platforms: [.macOS(.v14)],
    targets: [
        // Lógica, desenho e rasterizador por software: só Foundation, roda nos 3 sistemas.
        .target(name: "GatinhoCore", path: "Sources/GatinhoCore"),

        // Xlib + XShape + XInput2 (só Linux). Precisa de libx11-dev, libxext-dev e libxi-dev.
        .systemLibrary(name: "CX11", path: "Sources/CX11", pkgConfig: "x11",
                       providers: [.apt(["libx11-dev", "libxext-dev", "libxi-dev"])]),

        // Janela e entrada de cada sistema (Mac/, Windows/, Linux/, cada arquivo com #if os(...)).
        .executableTarget(
            name: "Gatinho",
            dependencies: [
                "GatinhoCore",
                .target(name: "CX11", condition: .when(platforms: [.linux])),
            ],
            path: "Sources/Gatinho",
            linkerSettings: [
                .linkedLibrary("User32", .when(platforms: [.windows])),
                .linkedLibrary("Gdi32", .when(platforms: [.windows])),
                .linkedLibrary("Shell32", .when(platforms: [.windows])),
                .linkedLibrary("Winmm", .when(platforms: [.windows])), // PlaySound (ronronar)
                // App de janela (sem console preto); a entrada continua sendo o main do Swift.
                .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"],
                             .when(platforms: [.windows])),
            ]
        ),
    ]
)
