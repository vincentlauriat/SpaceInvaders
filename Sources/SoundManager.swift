import AVFoundation

/// Plays the code-generated 8-bit WAVs. One AVAudioPlayer per effect.
final class SoundManager {
    static let shared = SoundManager()

    private var players: [String: AVAudioPlayer] = [:]
    private(set) var muted = false
    private var marchIndex = 0

    private init() {
        let names = ["shoot", "inv_hit", "explosion", "march1", "march2",
                     "march3", "march4", "ufo", "ufo_hit", "extra"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                continue
            }
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players[name] = player
            }
        }
        players["ufo"]?.numberOfLoops = -1
        players["ufo"]?.volume = 0.55
    }

    func toggleMute() {
        muted.toggle()
        if muted { stopUFO() }
    }

    func play(_ name: String) {
        guard !muted, let player = players[name] else { return }
        if player.isPlaying {
            player.currentTime = 0
        } else {
            player.play()
        }
    }

    func playMarchStep() {
        guard !muted else { return }
        play("march\(marchIndex + 1)")
        marchIndex = (marchIndex + 1) % 4
    }

    func resetMarch() { marchIndex = 0 }

    func startUFO() {
        guard !muted else { return }
        players["ufo"]?.play()
    }

    func stopUFO() {
        players["ufo"]?.stop()
        players["ufo"]?.currentTime = 0
    }
}
