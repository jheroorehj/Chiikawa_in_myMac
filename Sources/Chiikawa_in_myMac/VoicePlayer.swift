import AVFoundation

/// 우사기 음성을 재생한다. 한 번에 하나만 낸다.
@MainActor
final class VoicePlayer {
    var isMuted = false
    private var player: AVAudioPlayer?

    /// 음성 파일의 길이(초). 말풍선을 소리가 끝날 때까지 띄워 두는 데 쓴다.
    func duration(of name: String?) -> TimeInterval {
        guard let name, let url = PetLocator.voiceURL(name), let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return player.duration
    }

    func play(_ name: String?) {
        guard !isMuted, let name, let url = PetLocator.voiceURL(name) else { return }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func stop() {
        player?.stop()
    }
}
