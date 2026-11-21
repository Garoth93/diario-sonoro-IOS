import Foundation
import AVFoundation
import SonoroCore

// Real implementations of the SonoroCore protocols (the tests use fakes).

enum AudioSessionHelper {
    /// Recording ambience: mono microphone, playback still allowed.
    static func activateForRecording() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try s.setActive(true)
    }

    /// Playback (also in background and from the Lock Screen).
    static func activateForPlayback() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    static var microphoneAllowed: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    static var microphoneUndetermined: Bool {
        AVAudioApplication.shared.recordPermission == .undetermined
    }

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

/// AAC mono recorder with metering (levels sampled every 50 ms).
final class AVRecorderService: NSObject, AudioRecording {
    private var recorder: AVAudioRecorder?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "diariosonoro.meter")
    private var levels: [Float] = []
    private var lastLevel: Float = 0

    var currentLevel: Float { queue.sync { lastLevel } }

    func start(to url: URL, quality: AudioQuality) async throws {
        try AudioSessionHelper.activateForRecording()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: quality.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: quality.bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        guard r.prepareToRecord(), r.record() else {
            throw NSError(domain: "DiarioSonoro", code: 1, userInfo: [NSLocalizedDescriptionKey: "Il microfono non è disponibile."])
        }
        queue.sync {
            levels = []
            lastLevel = 0
            recorder = r
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
        t.setEventHandler { [weak self] in
            guard let self, let rec = self.recorder else { return }
            rec.updateMeters()
            let level = Waveform.level(decibels: rec.averagePower(forChannel: 0))
            self.lastLevel = level
            self.levels.append(level)
        }
        timer = t
        t.resume()
    }

    func stop() async -> RecordedAudio {
        timer?.cancel()
        timer = nil
        return queue.sync {
            guard let r = recorder else { return RecordedAudio(duration: 0, levels: []) }
            let duration = r.currentTime
            r.stop()
            recorder = nil
            let out = RecordedAudio(duration: duration, levels: levels)
            levels = []
            lastLevel = 0
            return out
        }
    }
}

/// Merges the clips of a day with crossfades: two alternating composition
/// tracks with volume ramps, exported as AAC (.m4a).
final class AVMergeService: AudioMerging {
    func merge(inputs: [URL], plan: SoundtrackPlan, output: URL, quality: AudioQuality) async throws {
        let composition = AVMutableComposition()
        guard let t0 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let t1 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "DiarioSonoro", code: 2, userInfo: [NSLocalizedDescriptionKey: "Composizione non disponibile."])
        }
        let tracks = [t0, t1]
        let params = tracks.map { AVMutableAudioMixInputParameters(track: $0) }
        let scale: CMTimeScale = 44_100
        func time(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: scale) }

        for (segment, url) in zip(plan.segments, inputs) {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let assetDuration = try await asset.load(.duration)
            let duration = CMTimeMinimum(time(segment.duration), assetDuration)
            let track = tracks[segment.track]
            let start = time(segment.start)
            let end = track.timeRange.end
            if CMTimeCompare(start, end) > 0 {
                track.insertEmptyTimeRange(CMTimeRange(start: end, end: start))
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: start)
            let p = params[segment.track]
            if segment.fadeIn > 0 {
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: start, duration: time(segment.fadeIn)))
            } else {
                p.setVolume(1, at: start)
            }
            if segment.fadeOut > 0 {
                let fadeStart = CMTimeSubtract(CMTimeAdd(start, duration), time(segment.fadeOut))
                p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: fadeStart, duration: time(segment.fadeOut)))
            }
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "DiarioSonoro", code: 3, userInfo: [NSLocalizedDescriptionKey: "Esportazione non disponibile."])
        }
        export.audioMix = mix
        try await export.export(to: output, as: .m4a)
    }
}
