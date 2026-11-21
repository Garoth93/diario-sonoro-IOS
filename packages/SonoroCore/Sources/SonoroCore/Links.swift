import Foundation

/// Where a quick recording was started from.
public enum LaunchSource: String, Codable, CaseIterable, Sendable {
    case app, widget, control, siri, notification
}

/// `diariosonoro://` links used by widgets, controls, Siri and notifications.
public enum DeepLink: Equatable, Sendable {
    case record(LaunchSource)
    case day(DayDate)
    case soundtrack(DayDate)
    case anniversary
    case calendar
    case map
    case stats

    public static let scheme = "diariosonoro"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { a, _ in a })
        switch host {
        case "record":
            self = .record(LaunchSource(rawValue: query["source"] ?? "") ?? .app)
        case "day":
            guard let s = parts.first, let d = DayDate(iso: s) else { return nil }
            self = .day(d)
        case "soundtrack":
            guard let s = parts.first, let d = DayDate(iso: s) else { return nil }
            self = .soundtrack(d)
        case "anniversary": self = .anniversary
        case "calendar": self = .calendar
        case "map": self = .map
        case "stats": self = .stats
        default: return nil
        }
    }

    public var url: URL {
        let s: String
        switch self {
        case .record(let src): s = "record?source=\(src.rawValue)"
        case .day(let d): s = "day/\(d.iso)"
        case .soundtrack(let d): s = "soundtrack/\(d.iso)"
        case .anniversary: s = "anniversary"
        case .calendar: s = "calendar"
        case .map: s = "map"
        case .stats: s = "stats"
        }
        return URL(string: "\(Self.scheme)://\(s)")!
    }
}

// MARK: - Widgets

/// The small JSON the widgets read from the App Group (never the whole diary).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var day: DayDate
    public var todayClips: Int
    public var todayDuration: Double
    public var streak: Int
    public var lastMinute: Int?
    public var lastPlace: String?
    public var soundtrackReady: Bool
    public var soundtrackTime: ClockTime
    public var anniversaryYears: [Int]
    public var anniversaryClips: Int
    /// Waveform of today's clips (or of the last clip), 0…255.
    public var waveform: [UInt8]
    public var clipDuration: Int
    public var totalDays: Int

    public init(day: DayDate, todayClips: Int = 0, todayDuration: Double = 0, streak: Int = 0, lastMinute: Int? = nil,
                lastPlace: String? = nil, soundtrackReady: Bool = false, soundtrackTime: ClockTime = ClockTime(hour: 21, minute: 30),
                anniversaryYears: [Int] = [], anniversaryClips: Int = 0, waveform: [UInt8] = [], clipDuration: Int = 10,
                totalDays: Int = 0) {
        self.day = day
        self.todayClips = todayClips
        self.todayDuration = todayDuration
        self.streak = streak
        self.lastMinute = lastMinute
        self.lastPlace = lastPlace
        self.soundtrackReady = soundtrackReady
        self.soundtrackTime = soundtrackTime
        self.anniversaryYears = anniversaryYears
        self.anniversaryClips = anniversaryClips
        self.waveform = waveform
        self.clipDuration = clipDuration
        self.totalDays = totalDays
    }

    public static func make(data: DiaryData, today: DayDate) -> WidgetSnapshot {
        let todays = data.clips(on: today)
        let days = Set(data.clips.map(\.day))
        let streak = DiaryStats.streaks(days: days, today: today).current
        let ann = Anniversary.groups(for: today, in: data.clips)
        let parts = todays.map { (Waveform.dequantize($0.waveform), $0.duration) }
        let wave = parts.isEmpty ? [] : Waveform.quantize(Waveform.concat(parts, bins: 32))
        let s = data.soundtrack(for: today)
        return WidgetSnapshot(
            day: today, todayClips: todays.count, todayDuration: todays.reduce(0) { $0 + $1.duration },
            streak: streak, lastMinute: todays.last?.minuteOfDay, lastPlace: todays.last?.displayPlace,
            soundtrackReady: s != nil && s?.clipIDs == todays.map(\.id),
            soundtrackTime: data.settings.soundtrackTime,
            anniversaryYears: ann.map(\.yearsAgo), anniversaryClips: ann.reduce(0) { $0 + $1.clips.count },
            waveform: wave, clipDuration: data.settings.clipDuration, totalDays: days.count)
    }

    /// The snapshot as seen on `today`: yesterday's counts are reset, the
    /// streak survives one day without clips.
    public func effective(on today: DayDate) -> WidgetSnapshot {
        let gap = DayDate.daysBetween(day, today)
        guard gap > 0 else { return self }
        var s = WidgetSnapshot(day: today, streak: gap == 1 && todayClips > 0 ? streak : 0,
                               soundtrackTime: soundtrackTime, clipDuration: clipDuration, totalDays: totalDays)
        s.anniversaryYears = []
        return s
    }

    public static let placeholder = WidgetSnapshot(
        day: DayDate(year: 2026, month: 11, day: 21)!, todayClips: 3, todayDuration: 30, streak: 12, lastMinute: 18 * 60 + 5,
        lastPlace: "Lungo Sile", soundtrackReady: false, anniversaryYears: [1], anniversaryClips: 2,
        waveform: (0..<32).map { UInt8(60 + (($0 * 37) % 150)) }, clipDuration: 10, totalDays: 214)
}

// MARK: - Local notifications

public struct PlannedNotification: Equatable, Sendable {
    public let id: String
    public let day: DayDate
    public let time: ClockTime
    public let title: String
    public let body: String
    public let link: DeepLink
}

public enum NotificationPlanner {
    public static let soundtrackPrefix = "soundtrack."
    public static let anniversaryPrefix = "anniversary."

    /// "La colonna sonora di oggi è pronta" for `day`, if it has clips.
    public static func soundtrack(day: DayDate, clips: [Clip], time: ClockTime) -> PlannedNotification? {
        let list = clips.filter { $0.day == day }.sorted(by: Clip.chronological)
        guard !list.isEmpty else { return nil }
        let summary = DaySummary(day: day, clips: list)
        var body = "\(ItalianFormat.clips(list.count)) · \(ItalianFormat.duration(summary.totalDuration))"
        let places = summary.places
        if let first = places.first {
            body += places.count > 1 ? " · \(first) e \(ItalianFormat.places(places.count - 1)) in più" : " · \(first)"
        }
        body += ". Tocca per ascoltarla."
        return PlannedNotification(id: soundtrackPrefix + day.iso, day: day, time: time,
                                   title: "La colonna sonora di oggi è pronta", body: body, link: .soundtrack(day))
    }

    /// One notification per upcoming day with clips 1, 2, 3… years before.
    public static func anniversaries(from today: DayDate, days: Int, clips: [Clip], time: ClockTime,
                                     minuteNow: Int) -> [PlannedNotification] {
        Anniversary.upcoming(from: today, count: days, in: clips).compactMap { item in
            if item.day == today && minuteNow >= time.minutes { return nil }
            let years = item.groups.map(\.yearsAgo)
            let title: String
            if years.count == 1 {
                title = years[0] == 1 ? "Un anno fa oggi" : "\(years[0]) anni fa oggi"
            } else {
                title = "Oggi, negli anni passati"
            }
            let n = item.groups.reduce(0) { $0 + $1.clips.count }
            let places = DaySummary(day: item.day, clips: item.groups.flatMap(\.clips)).places
            var body = "Riascolta \(ItalianFormat.clips(n))"
            if let p = places.first { body += ": \(p)" + (places.count > 1 ? " e altri luoghi" : "") }
            body += "."
            return PlannedNotification(id: anniversaryPrefix + item.day.iso, day: item.day, time: time,
                                       title: title, body: body, link: .anniversary)
        }
    }
}
