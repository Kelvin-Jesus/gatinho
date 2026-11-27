#if os(Linux)
import Foundation
import GatinhoCore

/// Ronronar no Linux: toca um .wav temporário com o primeiro tocador que existir
/// (pw-play do PipeWire, paplay do PulseAudio ou aplay do ALSA). Sem nenhum, fica mudo.
final class LinuxPurr {
    private var process: Process?
    private lazy var player: URL? = {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for name in ["pw-play", "paplay", "aplay"] {
            for dir in path.split(separator: ":") {
                let url = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }()
    // 60 s de laço; um carinho mais longo que isso termina em silêncio.
    private lazy var file: URL? = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gatinho-ronronar.wav")
        return (try? Purr.wav(seconds: 60).write(to: url)) != nil ? url : nil
    }()

    func set(_ on: Bool) {
        if on {
            guard process?.isRunning != true, let player, let file else { return }
            let p = Process()
            p.executableURL = player
            p.arguments = player.lastPathComponent == "aplay" ? ["-q", file.path] : [file.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            process = p
        } else {
            process?.terminate()
            process = nil
        }
    }
}
#endif
