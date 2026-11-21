import Foundation

// MARK: - Geo

public struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double
    /// Horizontal accuracy in meters, if known.
    public var accuracy: Double?

    public init(lat: Double, lon: Double, accuracy: Double? = nil) {
        self.lat = lat
        self.lon = lon
        self.accuracy = accuracy
    }

    /// Great-circle distance in meters (haversine).
    public func distance(to other: GeoPoint) -> Double {
        let r = 6_371_000.0
        let p1 = lat * .pi / 180, p2 = other.lat * .pi / 180
        let dp = (other.lat - lat) * .pi / 180
        let dl = (other.lon - lon) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// Result of reverse geocoding.
public struct PlaceInfo: Codable, Equatable, Sendable {
    /// Point of interest, street or area ("Bosco del Cansiglio", "Via Roma").
    public var name: String?
    /// Town or city ("Treviso").
    public var locality: String?

    public init(name: String? = nil, locality: String? = nil) {
        self.name = name
        self.locality = locality
    }
}

public struct WeatherInfo: Codable, Equatable, Sendable {
    /// SF Symbol name ("cloud.rain.fill").
    public var symbol: String
    /// Italian description ("Pioggia").
    public var condition: String
    public var temperatureC: Double

    public init(symbol: String, condition: String, temperatureC: Double) {
        self.symbol = symbol
        self.condition = condition
        self.temperatureC = temperatureC
    }
}

// MARK: - Clip

/// One ambient recording (5–30 s of AAC mono).
public struct Clip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var recordedAt: Date
    /// Local day of the recording (stored: never recomputed with another time zone).
    public var day: DayDate
    /// Local minute of the day (0…1439) at the start of the recording.
    public var minuteOfDay: Int
    /// Seconds.
    public var duration: Double
    /// Path relative to the storage root ("clips/2026/11/….m4a").
    public var fileName: String
    public var byteSize: Int
    public var location: GeoPoint?
    public var placeName: String?
    public var locality: String?
    public var weather: WeatherInfo?
    public var note: String
    public var emoji: String
    public var isFavorite: Bool
    /// Peak levels 0…255, `Waveform.defaultBins` values.
    public var waveform: [UInt8]

    public init(id: UUID = UUID(), recordedAt: Date, day: DayDate, minuteOfDay: Int, duration: Double,
                fileName: String, byteSize: Int = 0, location: GeoPoint? = nil, placeName: String? = nil,
                locality: String? = nil, weather: WeatherInfo? = nil, note: String = "", emoji: String = "",
                isFavorite: Bool = false, waveform: [UInt8] = []) {
        self.id = id
        self.recordedAt = recordedAt
        self.day = day
        self.minuteOfDay = minuteOfDay
        self.duration = duration
        self.fileName = fileName
        self.byteSize = byteSize
        self.location = location
        self.placeName = placeName
        self.locality = locality
        self.weather = weather
        self.note = note
        self.emoji = emoji
        self.isFavorite = isFavorite
        self.waveform = waveform
    }

    public var hour: Int { minuteOfDay / 60 }

    /// Best name to show for the place.
    public var displayPlace: String? {
        if let n = placeName?.trimmed, !n.isEmpty { return n }
        if let l = locality?.trimmed, !l.isEmpty { return l }
        return nil
    }

    /// "Bosco del Cansiglio · Fregona"
    public var placeLine: String? {
        guard let p = displayPlace else { return nil }
        if let l = locality?.trimmed, !l.isEmpty, l != p { return "\(p) · \(l)" }
        return p
    }

    /// Chronological order inside a day (and across days).
    public static func chronological(_ a: Clip, _ b: Clip) -> Bool {
        if a.day != b.day { return a.day < b.day }
        if a.minuteOfDay != b.minuteOfDay { return a.minuteOfDay < b.minuteOfDay }
        return a.recordedAt < b.recordedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, recordedAt, day, minuteOfDay, duration, fileName, byteSize, location, placeName, locality
        case weather, note, emoji, isFavorite, waveform
    }

    /// Tolerant decoding: fields added in later versions are optional.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        day = try c.decodeIfPresent(DayDate.self, forKey: .day) ?? DayDate(date: recordedAt)
        minuteOfDay = try c.decodeIfPresent(Int.self, forKey: .minuteOfDay) ?? SonoroCore.minuteOfDay(recordedAt)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        fileName = try c.decode(String.self, forKey: .fileName)
        byteSize = try c.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0
        location = try c.decodeIfPresent(GeoPoint.self, forKey: .location)
        placeName = try c.decodeIfPresent(String.self, forKey: .placeName)
        locality = try c.decodeIfPresent(String.self, forKey: .locality)
        weather = try c.decodeIfPresent(WeatherInfo.self, forKey: .weather)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        waveform = try c.decodeIfPresent([UInt8].self, forKey: .waveform) ?? []
    }
}

// MARK: - Daily soundtrack

/// The clips of one day merged with crossfades into a single audio file.
public struct DailySoundtrack: Codable, Equatable, Identifiable, Sendable {
    public var day: DayDate
    public var fileName: String
    public var duration: Double
    /// Clips used, in chronological order: if they change the soundtrack is rebuilt.
    public var clipIDs: [UUID]
    public var createdAt: Date
    public var byteSize: Int
    public var waveform: [UInt8]

    public var id: DayDate { day }

    public init(day: DayDate, fileName: String, duration: Double, clipIDs: [UUID], createdAt: Date,
                byteSize: Int = 0, waveform: [UInt8] = []) {
        self.day = day
        self.fileName = fileName
        self.duration = duration
        self.clipIDs = clipIDs
        self.createdAt = createdAt
        self.byteSize = byteSize
        self.waveform = waveform
    }
}

// MARK: - Settings

public enum AudioQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    case compact, standard, high

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .compact: return "Compatta"
        case .standard: return "Standard"
        case .high: return "Alta"
        }
    }

    public var sampleRate: Double {
        switch self {
        case .compact: return 22_050
        case .standard, .high: return 44_100
        }
    }

    /// AAC mono bit rate (bit/s).
    public var bitRate: Int {
        switch self {
        case .compact: return 32_000
        case .standard: return 64_000
        case .high: return 128_000
        }
    }

    /// Estimated size of `seconds` of audio (AAC payload + ~2 KB of container).
    public func estimatedBytes(seconds: Double) -> Int {
        Int((Double(bitRate) / 8 * max(0, seconds)).rounded()) + 2_048
    }
}

public enum Appearance: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Automatico"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }
}

/// Hour and minute of the day ("21:30").
public struct ClockTime: Codable, Equatable, Hashable, Sendable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    public init(minutes: Int) {
        let m = positiveModulo(minutes, 24 * 60)
        self.init(hour: m / 60, minute: m % 60)
    }

    public var minutes: Int { hour * 60 + minute }
    public var label: String { pad(hour, 2) + ":" + pad(minute, 2) }

    public static func < (a: ClockTime, b: ClockTime) -> Bool { a.minutes < b.minutes }
}

public struct DiarySettings: Codable, Equatable, Sendable {
    public static let durationRange = 5...30
    public static let crossfadeRange = 0.0...3.0

    /// Seconds recorded by one press (5…30).
    public var clipDuration: Int { didSet { clipDuration = Self.clamp(clipDuration) } }
    public var quality: AudioQuality
    public var saveLocation: Bool
    public var saveWeather: Bool
    /// When opened from widget / control / Siri, start recording right away (tap to stop).
    public var quickStartRecording: Bool
    public var haptics: Bool
    /// When the daily soundtrack is assembled.
    public var soundtrackTime: ClockTime
    /// Crossfade between clips, seconds (0…3).
    public var crossfade: Double
    public var soundtrackNotification: Bool
    public var anniversaryNotification: Bool
    public var anniversaryTime: ClockTime
    public var appearance: Appearance
    public var requireFaceID: Bool
    /// Daily "È ora della tua registrazione audio" at a random moment of the window.
    public var reminderEnabled: Bool
    public var reminderStart: ClockTime
    public var reminderEnd: ClockTime
    /// No reminder on a day that already has a clip.
    public var reminderSkipIfRecorded: Bool

    public init(clipDuration: Int = 10, quality: AudioQuality = .standard, saveLocation: Bool = true,
                saveWeather: Bool = false, quickStartRecording: Bool = false, haptics: Bool = true,
                soundtrackTime: ClockTime = ClockTime(hour: 21, minute: 30), crossfade: Double = 1.0,
                soundtrackNotification: Bool = true, anniversaryNotification: Bool = true,
                anniversaryTime: ClockTime = ClockTime(hour: 9, minute: 0), appearance: Appearance = .system,
                requireFaceID: Bool = false, reminderEnabled: Bool = false,
                reminderStart: ClockTime = ClockTime(hour: 10, minute: 0),
                reminderEnd: ClockTime = ClockTime(hour: 20, minute: 0),
                reminderSkipIfRecorded: Bool = true) {
        self.clipDuration = Self.clamp(clipDuration)
        self.quality = quality
        self.saveLocation = saveLocation
        self.saveWeather = saveWeather
        self.quickStartRecording = quickStartRecording
        self.haptics = haptics
        self.soundtrackTime = soundtrackTime
        self.crossfade = min(Self.crossfadeRange.upperBound, max(Self.crossfadeRange.lowerBound, crossfade))
        self.soundtrackNotification = soundtrackNotification
        self.anniversaryNotification = anniversaryNotification
        self.anniversaryTime = anniversaryTime
        self.appearance = appearance
        self.requireFaceID = requireFaceID
        self.reminderEnabled = reminderEnabled
        self.reminderStart = reminderStart
        self.reminderEnd = reminderEnd
        self.reminderSkipIfRecorded = reminderSkipIfRecorded
    }

    static func clamp(_ v: Int) -> Int { min(durationRange.upperBound, max(durationRange.lowerBound, v)) }

    enum CodingKeys: String, CodingKey {
        case clipDuration, quality, saveLocation, saveWeather, quickStartRecording, haptics, soundtrackTime
        case crossfade, soundtrackNotification, anniversaryNotification, anniversaryTime, appearance, requireFaceID
        case reminderEnabled, reminderStart, reminderEnd, reminderSkipIfRecorded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DiarySettings()
        self.init(
            clipDuration: try c.decodeIfPresent(Int.self, forKey: .clipDuration) ?? d.clipDuration,
            quality: (try? c.decodeIfPresent(AudioQuality.self, forKey: .quality)) ?? d.quality,
            saveLocation: try c.decodeIfPresent(Bool.self, forKey: .saveLocation) ?? d.saveLocation,
            saveWeather: try c.decodeIfPresent(Bool.self, forKey: .saveWeather) ?? d.saveWeather,
            quickStartRecording: try c.decodeIfPresent(Bool.self, forKey: .quickStartRecording) ?? d.quickStartRecording,
            haptics: try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics,
            soundtrackTime: try c.decodeIfPresent(ClockTime.self, forKey: .soundtrackTime) ?? d.soundtrackTime,
            crossfade: try c.decodeIfPresent(Double.self, forKey: .crossfade) ?? d.crossfade,
            soundtrackNotification: try c.decodeIfPresent(Bool.self, forKey: .soundtrackNotification) ?? d.soundtrackNotification,
            anniversaryNotification: try c.decodeIfPresent(Bool.self, forKey: .anniversaryNotification) ?? d.anniversaryNotification,
            anniversaryTime: try c.decodeIfPresent(ClockTime.self, forKey: .anniversaryTime) ?? d.anniversaryTime,
            appearance: (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance,
            requireFaceID: try c.decodeIfPresent(Bool.self, forKey: .requireFaceID) ?? d.requireFaceID,
            reminderEnabled: try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? d.reminderEnabled,
            reminderStart: try c.decodeIfPresent(ClockTime.self, forKey: .reminderStart) ?? d.reminderStart,
            reminderEnd: try c.decodeIfPresent(ClockTime.self, forKey: .reminderEnd) ?? d.reminderEnd,
            reminderSkipIfRecorded: try c.decodeIfPresent(Bool.self, forKey: .reminderSkipIfRecorded) ?? d.reminderSkipIfRecorded)
    }
}

// MARK: - Whole diary

public struct DiaryData: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var clips: [Clip]
    public var soundtracks: [DailySoundtrack]
    public var settings: DiarySettings

    public init(clips: [Clip] = [], soundtracks: [DailySoundtrack] = [], settings: DiarySettings = DiarySettings()) {
        version = Self.currentVersion
        self.clips = clips
        self.soundtracks = soundtracks
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey { case version, clips, soundtracks, settings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
        soundtracks = try c.decodeIfPresent([DailySoundtrack].self, forKey: .soundtracks) ?? []
        settings = try c.decodeIfPresent(DiarySettings.self, forKey: .settings) ?? DiarySettings()
    }

    // MARK: Queries

    public func clip(_ id: UUID) -> Clip? { clips.first { $0.id == id } }

    /// Clips of `day` in chronological order.
    public func clips(on day: DayDate) -> [Clip] {
        clips.filter { $0.day == day }.sorted(by: Clip.chronological)
    }

    public func soundtrack(for day: DayDate) -> DailySoundtrack? {
        soundtracks.first { $0.day == day }
    }

    /// Days with at least one clip, newest first.
    public var recordedDays: [DayDate] {
        Array(Set(clips.map(\.day))).sorted(by: >)
    }

    public var years: [Int] {
        Array(Set(clips.map(\.day.year))).sorted(by: >)
    }

    // MARK: Mutations

    public mutating func add(_ clip: Clip) {
        if let i = clips.firstIndex(where: { $0.id == clip.id }) {
            clips[i] = clip
        } else {
            clips.append(clip)
        }
    }

    public mutating func update(_ id: UUID, _ change: (inout Clip) -> Void) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        change(&clips[i])
    }

    /// Removes clips; returns the removed ones (to delete their files).
    @discardableResult
    public mutating func removeClips(_ ids: Set<UUID>) -> [Clip] {
        let removed = clips.filter { ids.contains($0.id) }
        clips.removeAll { ids.contains($0.id) }
        return removed
    }

    public mutating func setSoundtrack(_ s: DailySoundtrack) {
        soundtracks.removeAll { $0.day == s.day }
        soundtracks.append(s)
    }

    @discardableResult
    public mutating func removeSoundtrack(for day: DayDate) -> DailySoundtrack? {
        guard let i = soundtracks.firstIndex(where: { $0.day == day }) else { return nil }
        return soundtracks.remove(at: i)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
