import Foundation

/// The clips recorded on the same day N years ago.
public struct AnniversaryGroup: Identifiable, Equatable, Sendable {
    public let yearsAgo: Int
    /// The past days shown (two only for 28 February ↔ 29 February).
    public let days: [DayDate]
    public let clips: [Clip]

    public var id: Int { yearsAgo }
    public var title: String { ItalianFormat.yearsAgo(yearsAgo) }
    public var totalDuration: Double { clips.reduce(0) { $0 + $1.duration } }
    public var year: Int { days.first?.year ?? 0 }
}

public enum Anniversary {
    /// The day(s) of `year` that correspond to `day`.
    ///
    /// 29 February in a non-leap year becomes 28 February; on 28 February of a
    /// non-leap year a leap year's 29 February is included too, so it is never lost.
    public static func matchingDays(of day: DayDate, in year: Int) -> [DayDate] {
        if day.month == 2 && day.day == 29 {
            if DayDate.isLeap(year) { return [DayDate(year: year, month: 2, day: 29)!] }
            return []  // already shown on 28 February
        }
        var out: [DayDate] = []
        if let d = DayDate(year: year, month: day.month, day: day.day) { out.append(d) }
        if day.month == 2 && day.day == 28 && !day.isLeapYear && DayDate.isLeap(year) {
            out.append(DayDate(year: year, month: 2, day: 29)!)
        }
        return out
    }

    /// Groups for 1, 2, 3 … `maxYears` years before `today`, only those with clips.
    public static func groups(for today: DayDate, in clips: [Clip], maxYears: Int = 10) -> [AnniversaryGroup] {
        guard maxYears > 0 else { return [] }
        let byDay = Dictionary(grouping: clips, by: \.day)
        var out: [AnniversaryGroup] = []
        for n in 1...maxYears {
            let days = matchingDays(of: today, in: today.year - n)
            let found = days.flatMap { byDay[$0] ?? [] }.sorted(by: Clip.chronological)
            if !found.isEmpty { out.append(AnniversaryGroup(yearsAgo: n, days: days, clips: found)) }
        }
        return out
    }

    /// Upcoming days (from `today`, `count` days) that have at least one anniversary.
    public static func upcoming(from today: DayDate, count: Int, in clips: [Clip], maxYears: Int = 10) -> [(day: DayDate, groups: [AnniversaryGroup])] {
        (0..<max(0, count)).compactMap { i in
            let d = today.adding(days: i)
            let g = groups(for: d, in: clips, maxYears: maxYears)
            return g.isEmpty ? nil : (d, g)
        }
    }
}
