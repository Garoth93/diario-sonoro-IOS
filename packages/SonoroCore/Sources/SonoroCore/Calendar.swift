import Foundation

// MARK: - Grouping by day

/// The clips of one day, in chronological order.
public struct DaySummary: Identifiable, Equatable, Sendable {
    public let day: DayDate
    public let clips: [Clip]

    public var id: DayDate { day }
    public var count: Int { clips.count }
    public var totalDuration: Double { clips.reduce(0) { $0 + $1.duration } }
    public var firstMinute: Int? { clips.first?.minuteOfDay }
    public var lastMinute: Int? { clips.last?.minuteOfDay }
    public var favorites: Int { clips.filter(\.isFavorite).count }

    /// Distinct place names in order of first appearance.
    public var places: [String] {
        var seen = Set<String>()
        return clips.compactMap(\.displayPlace).filter { seen.insert($0).inserted }
    }

    public var emojis: [String] {
        var seen = Set<String>()
        return clips.map(\.emoji).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public init(day: DayDate, clips: [Clip]) {
        self.day = day
        self.clips = clips.sorted(by: Clip.chronological)
    }
}

public enum DayGrouping {
    /// One summary per recorded day, newest day first.
    public static func group(_ clips: [Clip]) -> [DaySummary] {
        Dictionary(grouping: clips, by: \.day)
            .map { DaySummary(day: $0.key, clips: $0.value) }
            .sorted { $0.day > $1.day }
    }

    public static func counts(_ clips: [Clip]) -> [DayDate: Int] {
        var out: [DayDate: Int] = [:]
        for c in clips { out[c.day, default: 0] += 1 }
        return out
    }
}

// MARK: - Month grid

/// Maps a number of clips to a 0…4 intensity level (calendar dots / colors).
public struct IntensityScale: Equatable, Sendable {
    /// Minimum count for levels 1, 2, 3, 4.
    public let thresholds: [Int]

    public init(thresholds: [Int] = [1, 2, 4, 7]) {
        self.thresholds = thresholds
    }

    public func level(_ count: Int) -> Int {
        thresholds.lastIndex { count >= $0 }.map { $0 + 1 } ?? 0
    }

    public static let `default` = IntensityScale()
}

public struct CalendarCell: Identifiable, Equatable, Sendable {
    /// Position in the grid (0…41).
    public let id: Int
    /// `nil` for the padding cells before day 1 and after the last day.
    public let day: DayDate?
    public let count: Int
    public let level: Int
    public let isToday: Bool
    public let isFuture: Bool
    public let hasSoundtrack: Bool
}

/// Monday-first month layout for the calendar, padded to whole weeks.
public struct MonthGrid: Equatable, Sendable {
    public let month: MonthRef
    public let cells: [CalendarCell]

    /// "L M M G V S D"
    public static let weekdaySymbols = ["L", "M", "M", "G", "V", "S", "D"]

    public init(month: MonthRef, counts: [DayDate: Int], soundtracks: Set<DayDate> = [],
                today: DayDate, scale: IntensityScale = .default) {
        self.month = month
        let lead = month.firstDay.weekdayFromMonday
        let total = Int((Double(lead + month.numberOfDays) / 7).rounded(.up)) * 7
        var cells: [CalendarCell] = []
        for i in 0..<total {
            let n = i - lead + 1
            if n >= 1 && n <= month.numberOfDays, let d = DayDate(year: month.year, month: month.month, day: n) {
                let c = counts[d] ?? 0
                cells.append(CalendarCell(id: i, day: d, count: c, level: scale.level(c), isToday: d == today,
                                          isFuture: d > today, hasSoundtrack: soundtracks.contains(d)))
            } else {
                cells.append(CalendarCell(id: i, day: nil, count: 0, level: 0, isToday: false, isFuture: false, hasSoundtrack: false))
            }
        }
        self.cells = cells
    }

    public var weeks: [[CalendarCell]] {
        stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    public var recordedDays: Int { cells.filter { $0.count > 0 }.count }
    public var clipCount: Int { cells.reduce(0) { $0 + $1.count } }
}

/// Months that can be shown: from the first recorded month (or this one) to today.
public enum MonthRange {
    public static func months(clips: [Clip], today: DayDate) -> [MonthRef] {
        let end = MonthRef(today)
        let start = clips.map(\.day).min().map(MonthRef.init) ?? end
        var out: [MonthRef] = []
        var m = min(start, end)
        while m <= end {
            out.append(m)
            m = m.next
        }
        return out
    }
}
