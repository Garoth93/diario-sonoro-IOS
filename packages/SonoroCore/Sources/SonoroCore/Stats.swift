import Foundation

public struct PlaceCount: Identifiable, Equatable, Sendable {
    public let name: String
    public let clips: Int
    public let days: Int
    public let duration: Double
    public var id: String { name }
}

public struct MonthCount: Identifiable, Equatable, Sendable {
    public let month: MonthRef
    public let clips: Int
    public let days: Int
    public var id: String { month.id }
}

/// Everything shown in the Statistics tab.
public struct DiaryStats: Equatable, Sendable {
    public let recordedDays: Int
    public let totalClips: Int
    /// Seconds.
    public let totalDuration: Double
    public let currentStreak: Int
    public let longestStreak: Int
    public let longestStreakEnd: DayDate?
    public let firstDay: DayDate?
    public let favorites: Int
    public let soundtracks: Int
    /// Clips per recorded day.
    public let averagePerDay: Double
    /// Share of days recorded since the first clip (0…1).
    public let coverage: Double
    public let busiestDay: DaySummary?
    public let topPlaces: [PlaceCount]
    public let distinctPlaces: Int
    /// 24 values.
    public let byHour: [Int]
    /// 7 values, Monday first.
    public let byWeekday: [Int]
    /// The last `monthsBack` months, oldest first.
    public let byMonth: [MonthCount]
    public let typicalHour: Int?
    public let clipBytes: Int
    public let soundtrackBytes: Int

    public var totalBytes: Int { clipBytes + soundtrackBytes }
    public var totalMinutes: Double { totalDuration / 60 }
    public var isEmpty: Bool { totalClips == 0 }

    public init(data: DiaryData, today: DayDate, monthsBack: Int = 12, topPlacesLimit: Int = 5) {
        let clips = data.clips
        let days = Set(clips.map(\.day))
        recordedDays = days.count
        totalClips = clips.count
        totalDuration = clips.reduce(0) { $0 + $1.duration }
        favorites = clips.filter(\.isFavorite).count
        soundtracks = data.soundtracks.count
        firstDay = days.min()
        averagePerDay = days.isEmpty ? 0 : Double(clips.count) / Double(days.count)
        if let first = firstDay {
            let span = DayDate.daysBetween(first, max(today, first)) + 1
            coverage = Double(days.count) / Double(span)
        } else {
            coverage = 0
        }

        // Streaks
        let streaks = Self.streaks(days: days, today: today)
        currentStreak = streaks.current
        longestStreak = streaks.longest
        longestStreakEnd = streaks.longestEnd

        let groups = DayGrouping.group(clips)
        busiestDay = groups.max { a, b in a.count != b.count ? a.count < b.count : a.day < b.day }

        // Places
        var placeClips: [String: (clips: Int, days: Set<DayDate>, duration: Double)] = [:]
        for c in clips {
            guard let p = c.displayPlace else { continue }
            var e = placeClips[p] ?? (0, [], 0)
            e.clips += 1
            e.days.insert(c.day)
            e.duration += c.duration
            placeClips[p] = e
        }
        distinctPlaces = placeClips.count
        topPlaces = placeClips
            .map { PlaceCount(name: $0.key, clips: $0.value.clips, days: $0.value.days.count, duration: $0.value.duration) }
            .sorted { $0.clips != $1.clips ? $0.clips > $1.clips : $0.name < $1.name }
            .prefix(topPlacesLimit)
            .map { $0 }

        var hours = Array(repeating: 0, count: 24)
        var weekdays = Array(repeating: 0, count: 7)
        for c in clips {
            hours[c.hour.clamped(0, 23)] += 1
            weekdays[c.day.weekdayFromMonday] += 1
        }
        byHour = hours
        byWeekday = weekdays
        typicalHour = clips.isEmpty ? nil : hours.indices.max { hours[$0] != hours[$1] ? hours[$0] < hours[$1] : $0 > $1 }

        let end = MonthRef(today)
        byMonth = (0..<max(0, monthsBack)).reversed().map { back in
            let m = end.adding(months: -back)
            let mc = clips.filter { m.contains($0.day) }
            return MonthCount(month: m, clips: mc.count, days: Set(mc.map(\.day)).count)
        }

        clipBytes = clips.reduce(0) { $0 + $1.byteSize }
        soundtrackBytes = data.soundtracks.reduce(0) { $0 + $1.byteSize }
    }

    /// Current streak: consecutive days ending today, or yesterday if today
    /// has no clip yet (the streak is still alive until midnight).
    public static func streaks(days: Set<DayDate>, today: DayDate) -> (current: Int, longest: Int, longestEnd: DayDate?) {
        var current = 0
        var cursor = days.contains(today) ? today : today.adding(days: -1)
        while days.contains(cursor) {
            current += 1
            cursor = cursor.adding(days: -1)
        }
        var longest = 0
        var longestEnd: DayDate?
        var run = 0
        var previous: DayDate?
        for d in days.sorted() {
            if let p = previous, DayDate.daysBetween(p, d) == 1 { run += 1 } else { run = 1 }
            if run >= longest {
                longest = run
                longestEnd = d
            }
            previous = d
        }
        return (current, longest, longestEnd)
    }
}
