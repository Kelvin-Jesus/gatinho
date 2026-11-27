#if os(Windows)
import Foundation
import GatinhoCore
import WinSDK

/// Ronronar no Windows: PlaySound toca o WAV direto da memória, em laço e sem bloquear.
final class WinPurr {
    // O PlaySound lê da memória enquanto toca: o buffer precisa viver tanto quanto o app.
    private let wav: UnsafeMutableRawPointer = {
        let d = Purr.wav()
        let p = UnsafeMutableRawPointer.allocate(byteCount: d.count, alignment: 4)
        d.copyBytes(to: p.assumingMemoryBound(to: UInt8.self), count: d.count)
        return p
    }()
    private var playing = false

    func set(_ on: Bool) {
        guard on != playing else { return }
        playing = on
        if on {
            let ptr = wav.assumingMemoryBound(to: WCHAR.self)
            _ = PlaySoundW(ptr, nil, DWORD(SND_MEMORY | SND_ASYNC | SND_LOOP | SND_NODEFAULT))
        } else {
            _ = PlaySoundW(nil, nil, 0)
        }
    }
}
#endif
