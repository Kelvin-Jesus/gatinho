#if os(macOS)
import AVFoundation
import GatinhoCore

/// Toca o ronronar em laço enquanto o gato recebe carinho, entrando e saindo suave.
final class PurrPlayer {
    private let player = try? AVAudioPlayer(data: Purr.wav())
    var enabled = true { didSet { if !enabled { set(false) } } }

    init() {
        player?.numberOfLoops = -1
        player?.volume = 0
        player?.prepareToPlay()
    }

    func set(_ on: Bool) {
        guard let player else { return }
        if on && enabled {
            if !player.isPlaying { player.currentTime = 0; player.play() }
            player.setVolume(0.8, fadeDuration: 0.4)
        } else if player.isPlaying {
            player.setVolume(0, fadeDuration: 0.35)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if let p = self?.player, p.volume == 0 { p.pause() }
            }
        }
    }
}
#endif
