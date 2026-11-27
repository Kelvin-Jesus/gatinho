import Foundation

/// Preferências salvas em JSON (Windows e Linux; o Mac usa UserDefaults).
public struct Settings: Codable {
    public var coat = "tuxedo"
    public var scale = 1.0
    public var opacity = 1.0
    public var showKeys = true
    public var x: Int?
    public var y: Int?

    public init() {}

    public static let sizes: [(String, Double)] = [("Mini", 0.6), ("Pequeno", 0.8), ("Normal", 1.0), ("Grande", 1.3)]
    public static let opacities: [Double] = [1, 0.85, 0.7, 0.5]

    public static func load(_ url: URL) -> Settings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    public func save(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url) }
    }
}
