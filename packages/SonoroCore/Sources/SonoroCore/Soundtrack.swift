import Foundation

// MARK: - Plan (pure timeline math)

/// Where one clip goes in the merged soundtrack.
public struct SoundtrackSegment: Equatable, Sendable {
    public let clipID: UUID
    /// Seconds of the source clip used (the whole clip).
    public let duration: Double
    /// Start in the output timeline (seconds).
    public let start: Double
    /// Volume ramps 0→1 at the start and 1→0 at the end (seconds).
    public let fadeIn: Double
    public let fadeOut: Double
    /// Clips alternate on two tracks so that crossfades can overlap.
    public let track: Int

    public var end: Double { start + duration }
}

/// Timeline of the daily soundtrack: clips in chronological order, each
/// overlapping the previous one by the crossfade.
///
/// The crossfade between two clips never exceeds half of the shorter one, so
/// a 2-second clip is never swallowed by its neighbours. The very first and
/// last clip get a short edge fade to avoid clicks.
public struct SoundtrackPlan: Equatable, Sendable {
    public let segments: [SoundtrackSegment]
    public let totalDuration: Double

    public init(clips: [(id: UUID, duration: Double)], crossfade: Double, edgeFade: Double = 0.3) {
        let items = clips.filter { $0.duration > 0 }
        let xf = max(0, crossfade)
        var overlaps: [Double] = []
        for i in 0..<max(0, items.count - 1) {
            overlaps.append(min(xf, items[i].duration / 2, items[i + 1].duration / 2))
        }
        var segments: [SoundtrackSegment] = []
        var t = 0.0
        for (i, item) in items.enumerated() {
            let fadeIn = i == 0 ? min(edgeFade, item.duration / 2) : overlaps[i - 1]
            let fadeOut = i == items.count - 1 ? min(edgeFade, item.duration / 2) : overlaps[i]
            segments.append(SoundtrackSegment(clipID: item.id, duration: item.duration, start: t,
                                              fadeIn: fadeIn, fadeOut: fadeOut, track: i % 2))
            t += item.duration - (i < overlaps.count ? overlaps[i] : 0)
        }
        self.segments = segments
        totalDuration = segments.last?.end ?? 0
    }

    public init(clips: [Clip], crossfade: Double) {
        self.init(clips: clips.sorted(by: Clip.chronological).map { (id: $0.id, duration: $0.duration) }, crossfade: crossfade)
    }

    public var isEmpty: Bool { segments.isEmpty }

    /// Index of the segment playing at `time` (the later one during a crossfade).
    public func segmentIndex(at time: Double) -> Int? {
        guard !segments.isEmpty else { return nil }
        if time <= 0 { return 0 }
        return segments.lastIndex { $0.start <= time } ?? 0
    }
}

// MARK: - Scheduling

public enum SoundtrackScheduler {
    /// True when `day`'s soundtrack is missing or built from other clips.
    public static func needsBuild(_ day: DayDate, in data: DiaryData) -> Bool {
        let ids = data.clips(on: day).map(\.id)
        guard !ids.isEmpty else { return false }
        guard let s = data.soundtrack(for: day) else { return true }
        return s.clipIDs != ids
    }

    /// Days whose soundtrack must be (re)built now: every past day with clips,
    /// and today once the configured evening time has passed.
    public static func dueDays(data: DiaryData, today: DayDate, minuteNow: Int) -> [DayDate] {
        let time = data.settings.soundtrackTime
        return data.recordedDays
            .filter { $0 < today || ($0 == today && minuteNow >= time.minutes) }
            .filter { needsBuild($0, in: data) }
            .sorted(by: >)
    }

    /// Soundtracks whose day has no clips any more (all deleted).
    public static func orphans(in data: DiaryData) -> [DailySoundtrack] {
        let days = Set(data.clips.map(\.day))
        return data.soundtracks.filter { !days.contains($0.day) }
    }

    /// Next occurrence of `time` strictly after `now`.
    public static func nextRun(after now: Date, time: ClockTime, timeZone: TimeZone = .current) -> Date {
        let today = DayDate(date: now, timeZone: timeZone)
        let candidate = today.date(minuteOfDay: time.minutes, timeZone: timeZone)
        return candidate > now ? candidate : today.adding(days: 1).date(minuteOfDay: time.minutes, timeZone: timeZone)
    }
}

// MARK: - Building (behind a protocol)

public enum SoundtrackError: Error, Equatable {
    case noClips
    case missingFiles([String])
    case mergeFailed(String)
}

/// Merges audio files following a `SoundtrackPlan` (AVFoundation in the app,
/// a fake in the tests).
public protocol AudioMerging: AnyObject {
    func merge(inputs: [URL], plan: SoundtrackPlan, output: URL, quality: AudioQuality) async throws
}

/// Builds the soundtrack of one day: plan, merge, model.
public final class SoundtrackBuilder {
    public let merger: AudioMerging
    public let root: URL
    private let now: () -> Date

    public init(merger: AudioMerging, root: URL, now: @escaping () -> Date = Date.init) {
        self.merger = merger
        self.root = root
        self.now = now
    }

    public func build(day: DayDate, data: DiaryData) async throws -> DailySoundtrack {
        let clips = data.clips(on: day)
        guard !clips.isEmpty else { throw SoundtrackError.noClips }
        let fm = FileManager.default
        let missing = clips.map(\.fileName).filter { !fm.fileExists(atPath: root.appendingPathComponent($0).path) }
        let usable = clips.filter { !missing.contains($0.fileName) }
        guard !usable.isEmpty else { throw SoundtrackError.missingFiles(missing) }
        let plan = SoundtrackPlan(clips: usable, crossfade: data.settings.crossfade)
        let path = FileNaming.soundtrackPath(day: day)
        let output = root.appendingPathComponent(path)
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
        do {
            try await merger.merge(inputs: usable.map { root.appendingPathComponent($0.fileName) }, plan: plan,
                                   output: output, quality: data.settings.quality)
        } catch {
            throw SoundtrackError.mergeFailed(String(describing: error))
        }
        let size = FileInfo.size(of: output)
        let wave = Waveform.concat(usable.map { (Waveform.dequantize($0.waveform), $0.duration) }, bins: 64)
        // `clipIDs` lists every clip of the day: a missing file must not cause endless rebuilds.
        return DailySoundtrack(day: day, fileName: path, duration: plan.totalDuration, clipIDs: clips.map(\.id),
                               createdAt: now(), byteSize: size, waveform: Waveform.quantize(wave))
    }
}
