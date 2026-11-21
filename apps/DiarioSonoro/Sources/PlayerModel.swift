import Foundation
import AVFoundation
import MediaPlayer
import SonoroCore

/// One thing to play: a clip or a daily soundtrack.
struct PlayItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let title: String
    let subtitle: String
    let duration: Double
    let waveform: [UInt8]
    let day: DayDate
    var clipID: UUID?

    static func clip(_ c: Clip, root: URL) -> PlayItem {
        PlayItem(id: c.id.uuidString, url: root.appendingPathComponent(c.fileName),
                 title: c.displayPlace ?? "Clip delle \(ItalianFormat.time(minuteOfDay: c.minuteOfDay))",
                 subtitle: "\(ItalianFormat.dayShort(c.day)) · \(ItalianFormat.time(minuteOfDay: c.minuteOfDay))" + (c.emoji.isEmpty ? "" : " \(c.emoji)"),
                 duration: c.duration, waveform: c.waveform, day: c.day, clipID: c.id)
    }

    static func soundtrack(_ s: DailySoundtrack, root: URL) -> PlayItem {
        PlayItem(id: "soundtrack-\(s.day.iso)", url: root.appendingPathComponent(s.fileName),
                 title: "Colonna sonora", subtitle: ItalianFormat.capitalized(ItalianFormat.dayTitle(s.day)),
                 duration: s.duration, waveform: s.waveform, day: s.day)
    }
}

/// Minimal player: queue, speed, seek, background audio and Lock Screen
/// controls. In demo mode (CI screenshots, no audio files) playback is simulated.
@MainActor
@Observable
final class PlayerModel {
    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    private(set) var queue: [PlayItem] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var rate: Float = 1
    var errorMessage: String?
    var simulate = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let delegate = FinishDelegate()
    @ObservationIgnored private var commandsReady = false

    var current: PlayItem? { queue.indices.contains(index) ? queue[index] : nil }
    var isActive: Bool { current != nil }
    private(set) var duration: Double = 0
    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }
    var hasNext: Bool { index + 1 < queue.count }

    init() {
        delegate.onFinish = { [weak self] in
            Task { @MainActor in self?.next(auto: true) }
        }
    }

    func isCurrent(_ id: String) -> Bool { current?.id == id }

    // MARK: Control

    func play(_ items: [PlayItem], startAt: Int = 0) {
        guard !items.isEmpty else { return }
        queue = items
        index = min(max(0, startAt), items.count - 1)
        load(autoplay: true)
    }

    /// Tap on an item: toggles if it is the current one, otherwise plays it.
    func toggle(_ item: PlayItem, in list: [PlayItem]? = nil) {
        if isCurrent(item.id) {
            isPlaying ? pause() : resume()
        } else {
            let items = list ?? [item]
            play(items, startAt: items.firstIndex { $0.id == item.id } ?? 0)
        }
    }

    func resume() {
        guard current != nil else { return }
        if player == nil && !simulate { load(autoplay: true); return }
        AudioSessionHelper.activateForPlayback()
        player?.play()
        isPlaying = true
        startTicker()
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
        updateNowPlaying()
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func next(auto: Bool = false) {
        guard hasNext else {
            if auto {
                pause()
                currentTime = 0
                player?.currentTime = 0
            }
            return
        }
        index += 1
        load(autoplay: true)
    }

    func previous() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            index -= 1
            load(autoplay: true)
        }
    }

    func seek(to time: Double) {
        let t = min(max(0, time), duration)
        player?.currentTime = t
        currentTime = t
        updateNowPlaying()
    }

    func cycleRate() {
        let i = Self.rates.firstIndex(of: rate) ?? 1
        setRate(Self.rates[(i + 1) % Self.rates.count])
    }

    func setRate(_ r: Float) {
        rate = r
        player?.rate = r
        updateNowPlaying()
    }

    func stop() {
        player?.stop()
        player = nil
        queue = []
        index = 0
        isPlaying = false
        currentTime = 0
        stopTicker()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Internals

    private func load(autoplay: Bool) {
        player?.stop()
        player = nil
        currentTime = 0
        guard let item = current else { return }
        duration = item.duration
        setupRemoteCommands()
        if simulate {
            isPlaying = autoplay
            if autoplay { startTicker() }
            updateNowPlaying()
            return
        }
        do {
            AudioSessionHelper.activateForPlayback()
            let p = try AVAudioPlayer(contentsOf: item.url)
            p.enableRate = true
            p.rate = rate
            p.delegate = delegate
            p.prepareToPlay()
            player = p
            duration = p.duration
            if autoplay {
                p.play()
                isPlaying = true
                startTicker()
            }
        } catch {
            isPlaying = false
            errorMessage = "Impossibile riprodurre l'audio: il file non è disponibile."
        }
        updateNowPlaying()
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        if simulate {
            guard isPlaying else { return }
            currentTime += 0.05 * Double(rate)
            if currentTime >= duration { next(auto: true) }
        } else if let p = player {
            currentTime = p.currentTime
        }
    }

    // MARK: Lock Screen

    private func updateNowPlaying() {
        guard let item = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: "Diario Sonoro",
            MPMediaItemPropertyAlbumTitle: item.subtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0
        ]
    }

    private func setupRemoteCommands() {
        guard !commandsReady else { return }
        commandsReady = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self?.seek(to: t) }
            return .success
        }
    }
}

private final class FinishDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
