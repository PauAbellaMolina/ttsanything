import AVFoundation
import AppKit

enum PlaybackState {
    case idle, loading, playing, paused
}

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var state: PlaybackState = .idle
    @Published var progress: Double = 0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var sayProcess: Process?
    private(set) var lastAudioData: Data?
    private(set) var lastPlaybackRate: Float = 1.0
    private(set) var lastSayText: String?
    private(set) var lastSayRate: Int?

    var hasLastAudio: Bool {
        lastAudioData != nil || lastSayText != nil
    }

    func play(data: Data, rate: Float = 1.0) {
        lastAudioData = data
        lastPlaybackRate = rate
        lastSayText = nil
        lastSayRate = nil
        stop()
        do {
            let audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer.delegate = self
            audioPlayer.enableRate = true
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            audioPlayer.rate = rate
            player = audioPlayer
            duration = audioPlayer.duration
            state = .playing
            startProgressTimer()
        } catch {
            state = .idle
        }
    }

    func replay() {
        if let data = lastAudioData {
            play(data: data, rate: lastPlaybackRate)
        } else if let text = lastSayText, let rate = lastSayRate {
            playWithSay(text: text, rate: rate)
        }
    }

    func playWithSay(text: String, rate: Int = 210) {
        lastSayText = text
        lastSayRate = rate
        lastAudioData = nil
        stop()
        state = .playing

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-r", "\(rate)", text]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.state = .idle
                self?.progress = 0
            }
        }
        sayProcess = process
        do {
            try process.run()
        } catch {
            state = .idle
        }
    }

    func pause() {
        guard let player = player, player.isPlaying else { return }
        player.pause()
        state = .paused
        stopProgressTimer()
    }

    func resume() {
        guard let player = player, state == .paused else { return }
        player.play()
        state = .playing
        startProgressTimer()
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        default: break
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if let p = sayProcess, p.isRunning { p.terminate() }
        sayProcess = nil
        state = .idle
        progress = 0
        currentTime = 0
        duration = 0
        stopProgressTimer()
    }

    func seek(to fraction: Double) {
        guard let player = player else { return }
        let target = max(0, min(player.duration, fraction * player.duration))
        player.currentTime = target
        updateProgress()
    }

    func skipForward(_ seconds: TimeInterval = 5) {
        guard let player = player else { return }
        player.currentTime = min(player.duration, player.currentTime + seconds)
        updateProgress()
    }

    func skipBackward(_ seconds: TimeInterval = 5) {
        guard let player = player else { return }
        player.currentTime = max(0, player.currentTime - seconds)
        updateProgress()
    }

    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.state = .idle
            self.progress = 0
            self.currentTime = 0
            self.duration = 0
            self.stopProgressTimer()
        }
    }

    // MARK: - Progress

    private func updateProgress() {
        guard let player = player else { return }
        currentTime = player.currentTime
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
