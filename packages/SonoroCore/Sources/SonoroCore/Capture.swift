import Foundation

// MARK: - Rules of the hold-to-record button

public struct RecordingRules: Equatable, Sendable {
    /// Seconds recorded by a full press.
    public let maxDuration: Double
    /// Shorter recordings are discarded.
    public let minimumDuration: Double

    public init(clipDuration: Int, minimumDuration: Double = 2) {
        maxDuration = Double(DiarySettings.clamp(clipDuration))
        self.minimumDuration = minimumDuration
    }

    public enum Outcome: Equatable, Sendable {
        case save(duration: Double)
        case tooShort(duration: Double)
    }

    /// 0…1 for the progress ring.
    public func progress(elapsed: Double) -> Double {
        min(1, max(0, elapsed / maxDuration))
    }

    /// Whole seconds left, shown inside the button (10, 9, … 1).
    public func remainingSeconds(elapsed: Double) -> Int {
        Int((maxDuration - max(0, elapsed)).rounded(.up)).clamped(0, Int(maxDuration))
    }

    public func shouldAutoStop(elapsed: Double) -> Bool { elapsed >= maxDuration }

    /// What to do with what was recorded when the finger is lifted.
    public func outcome(elapsed: Double) -> Outcome {
        let d = min(max(0, elapsed), maxDuration)
        return d + 0.0001 >= minimumDuration ? .save(duration: d) : .tooShort(duration: d)
    }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(hi, Swift.max(lo, self)) }
}

// MARK: - Services behind protocols

/// What the recorder returns when stopped.
public struct RecordedAudio: Equatable, Sendable {
    public var duration: Double
    /// Input levels 0…1 sampled during the recording.
    public var levels: [Float]

    public init(duration: Double, levels: [Float]) {
        self.duration = duration
        self.levels = levels
    }
}

/// Microphone recorder (AVAudioRecorder in the app, a fake in the tests).
public protocol AudioRecording: AnyObject {
    /// Starts recording AAC mono to `url` immediately.
    func start(to url: URL, quality: AudioQuality) async throws
    /// Stops and returns duration and levels.
    func stop() async -> RecordedAudio
    /// Current input level 0…1 (for the live ring).
    var currentLevel: Float { get }
}

public enum LocationAccess: Equatable, Sendable {
    case allowed, notDetermined, denied
}

/// One-shot "while in use" location + reverse geocoding.
public protocol LocationProviding: AnyObject {
    var access: LocationAccess { get }
    /// Shows the system prompt once; returns the resulting access.
    func requestAccess() async -> LocationAccess
    /// A single fix (no continuous tracking), `nil` on timeout or error.
    func currentLocation() async -> GeoPoint?
    func placeInfo(for point: GeoPoint) async -> PlaceInfo?
}

/// Optional weather (WeatherKit in the app).
public protocol WeatherProviding: AnyObject {
    func weather(at point: GeoPoint, date: Date) async -> WeatherInfo?
}

// MARK: - Capture pipeline

public enum CaptureError: Error, Equatable {
    case alreadyRecording
    case notRecording
    case recorderFailed(String)
}

public enum CaptureResult: Equatable, Sendable {
    case saved(Clip)
    case tooShort(duration: Double)
}

/// Turns a press of the button into a saved `Clip`.
///
/// `begin` starts the recorder and, if allowed, asks for one location fix in
/// parallel. `finish` stops, applies the 2-second rule and returns the clip
/// right away; `enrich` then fills place name and weather (slower, network).
public final class CaptureController {
    public let recorder: AudioRecording
    public let location: LocationProviding?
    public let weather: WeatherProviding?
    public let root: URL

    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let makeID: () -> UUID

    private var current: (id: UUID, startedAt: Date, path: String, settings: DiarySettings)?
    private var fixTask: Task<GeoPoint?, Never>?

    public var isRecording: Bool { current != nil }
    public var startedAt: Date? { current?.startedAt }

    public init(recorder: AudioRecording, location: LocationProviding?, weather: WeatherProviding?, root: URL,
                now: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current },
                makeID: @escaping () -> UUID = UUID.init) {
        self.recorder = recorder
        self.location = location
        self.weather = weather
        self.root = root
        self.now = now
        self.timeZone = timeZone
        self.makeID = makeID
    }

    public func begin(settings: DiarySettings) async throws {
        guard current == nil else { throw CaptureError.alreadyRecording }
        let id = makeID()
        let start = now()
        let path = FileNaming.clipPath(id: id, recordedAt: start, timeZone: timeZone())
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try await recorder.start(to: url, quality: settings.quality)
        } catch {
            throw CaptureError.recorderFailed(String(describing: error))
        }
        current = (id, start, path, settings)
        if settings.saveLocation, let location, location.access == .allowed {
            fixTask = Task { await location.currentLocation() }
        } else {
            fixTask = nil
        }
    }

    /// Stops the recorder. Under the minimum duration the file is deleted.
    public func finish() async throws -> CaptureResult {
        guard let cur = current else { throw CaptureError.notRecording }
        let audio = await recorder.stop()
        current = nil
        let url = root.appendingPathComponent(cur.path)
        let rules = RecordingRules(clipDuration: cur.settings.clipDuration)
        switch rules.outcome(elapsed: audio.duration) {
        case .tooShort(let d):
            fixTask?.cancel()
            fixTask = nil
            try? FileManager.default.removeItem(at: url)
            return .tooShort(duration: d)
        case .save(let d):
            let tz = timeZone()
            let clip = Clip(id: cur.id, recordedAt: cur.startedAt, day: DayDate(date: cur.startedAt, timeZone: tz),
                            minuteOfDay: SonoroCore.minuteOfDay(cur.startedAt, timeZone: tz), duration: d,
                            fileName: cur.path, byteSize: FileInfo.size(of: url),
                            waveform: Waveform.clipWaveform(levels: audio.levels))
            return .saved(clip)
        }
    }

    /// Location, place name and weather for a clip just saved.
    /// Asks for location permission here (after recording) the first time.
    public func enrich(_ clip: Clip, settings: DiarySettings) async -> Clip {
        var out = clip
        let pending = fixTask
        fixTask = nil
        guard settings.saveLocation, let location else { return out }
        var point = await pending?.value
        if point == nil {
            var access = location.access
            if access == .notDetermined { access = await location.requestAccess() }
            if access == .allowed { point = await location.currentLocation() }
        }
        guard let point else { return out }
        out.location = point
        if let info = await location.placeInfo(for: point) {
            out.placeName = info.name
            out.locality = info.locality
        }
        if settings.saveWeather, let weather {
            out.weather = await weather.weather(at: point, date: clip.recordedAt)
        }
        return out
    }

    /// Abandons a recording (app sent to background, interruption).
    public func cancel() async {
        guard let cur = current else { return }
        _ = await recorder.stop()
        current = nil
        fixTask?.cancel()
        fixTask = nil
        try? FileManager.default.removeItem(at: root.appendingPathComponent(cur.path))
    }
}

/// Small file-system helpers that behave the same on Linux and iOS.
public enum FileInfo {
    public static func size(of url: URL) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        if let n = attrs[.size] as? NSNumber { return n.intValue }
        if let n = attrs[.size] as? Int { return n }
        if let n = attrs[.size] as? UInt64 { return Int(n) }
        return 0
    }

    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
