import Foundation

/// A calendar day without time or time zone ("YYYY-MM-DD").
///
/// Every clip stores the local day it was recorded on, so grouping, the
/// calendar and "un anno fa oggi" never depend on the current time zone.
/// Arithmetic uses a plain day count: immune to daylight saving time and
/// identical on Linux and iOS.
public struct DayDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Days since 1970-01-01.
    public init(dayNumber: Int) {
        let c = DayDate.civil(fromDays: dayNumber)
        year = c.y
        month = c.m
        day = c.d
    }

    /// Returns `nil` for impossible dates (no roll-over: 31 April is invalid).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= DayDate.daysIn(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD".
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Local day of `date` in `timeZone`.
    public init(date: Date, timeZone: TimeZone = .current) {
        let c = DayDate.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(dayNumber: DayDate.days(fromCivil: c.year ?? 1970, c.month ?? 1, c.day ?? 1))
    }

    public static func today(timeZone: TimeZone = .current) -> DayDate {
        DayDate(date: Date(), timeZone: timeZone)
    }

    /// Start of `minuteOfDay` on this day in `timeZone` (noon by default).
    public func date(minuteOfDay: Int = 12 * 60, timeZone: TimeZone = .current) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = minuteOfDay / 60
        c.minute = minuteOfDay % 60
        return DayDate.calendar(timeZone).date(from: c)
            ?? Date(timeIntervalSince1970: TimeInterval(dayNumber) * 86_400 + TimeInterval(minuteOfDay * 60))
    }

    public var dayNumber: Int { DayDate.days(fromCivil: year, month, day) }

    public var iso: String { pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2) }

    /// "20261121"
    public var compact: String { pad(year, 4) + pad(month, 2) + pad(day, 2) }

    public var description: String { iso }

    public func adding(days n: Int) -> DayDate { DayDate(dayNumber: dayNumber + n) }

    /// Calendar days from `a` to `b` (b - a).
    public static func daysBetween(_ a: DayDate, _ b: DayDate) -> Int { b.dayNumber - a.dayNumber }

    /// 0 = Monday … 6 = Sunday.
    public var weekdayFromMonday: Int { positiveModulo(dayNumber + 3, 7) }

    public var isLeapYear: Bool { DayDate.isLeap(year) }

    public static func < (lhs: DayDate, rhs: DayDate) -> Bool { lhs.dayNumber < rhs.dayNumber }

    public static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    // MARK: Codable as "YYYY-MM-DD"

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = DayDate(iso: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid day \(s)")
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }

    // MARK: Helpers

    static func calendar(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    // Howard Hinnant's civil-from-days algorithms (proleptic Gregorian).
    static func days(fromCivil y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(fromDays z0: Int) -> (y: Int, m: Int, d: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

func positiveModulo(_ a: Int, _ n: Int) -> Int {
    let r = a % n
    return r < 0 ? r + n : r
}

func pad(_ v: Int, _ width: Int) -> String {
    let s = String(abs(v))
    let padded = s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    return v < 0 ? "-" + padded : padded
}

/// Minute of the day of `date` in `timeZone` (0…1439).
public func minuteOfDay(_ date: Date, timeZone: TimeZone = .current) -> Int {
    let c = DayDate.calendar(timeZone).dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

/// A month of a year, used by the calendar.
public struct MonthRef: Hashable, Comparable, Sendable, Codable, Identifiable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        // Normalise overflowing months (13 → January of next year).
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = positiveModulo(index, 12) + 1
    }

    public init(_ day: DayDate) {
        self.init(year: day.year, month: day.month)
    }

    public var id: String { pad(year, 4) + "-" + pad(month, 2) }
    public var firstDay: DayDate { DayDate(year: year, month: month, day: 1)! }
    public var numberOfDays: Int { DayDate.daysIn(month: month, year: year) }
    public var lastDay: DayDate { DayDate(year: year, month: month, day: numberOfDays)! }
    public func adding(months n: Int) -> MonthRef { MonthRef(year: year, month: month + n) }
    public var next: MonthRef { adding(months: 1) }
    public var previous: MonthRef { adding(months: -1) }
    public func contains(_ d: DayDate) -> Bool { d.year == year && d.month == month }

    public static func < (a: MonthRef, b: MonthRef) -> Bool { (a.year, a.month) < (b.year, b.month) }
}
