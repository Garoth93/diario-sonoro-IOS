import Foundation

/// Italian labels, computed by hand so they are identical on Linux and iOS.
public enum ItalianFormat {
    public static let months = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio",
                                "agosto", "settembre", "ottobre", "novembre", "dicembre"]
    public static let shortMonths = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
    /// Monday first.
    public static let weekdays = ["lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica"]
    public static let shortWeekdays = ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]

    public static func monthName(_ m: Int) -> String { months[(m - 1).clamped(0, 11)] }

    /// "Novembre 2026"
    public static func monthTitle(_ m: MonthRef) -> String { capitalized(monthName(m.month)) + " " + String(m.year) }

    /// "sabato 21 novembre 2026"
    public static func dayTitle(_ d: DayDate) -> String {
        "\(weekdays[d.weekdayFromMonday]) \(d.day) \(monthName(d.month)) \(d.year)"
    }

    /// "sabato 21 novembre"
    public static func dayTitleNoYear(_ d: DayDate) -> String {
        "\(weekdays[d.weekdayFromMonday]) \(d.day) \(monthName(d.month))"
    }

    /// "21 nov 2026"
    public static func dayShort(_ d: DayDate, year: Bool = true) -> String {
        "\(d.day) \(shortMonths[d.month - 1])" + (year ? " \(d.year)" : "")
    }

    /// "Oggi", "Ieri", "Sabato 21 novembre" (same year) or "Sabato 21 novembre 2025".
    public static func relativeDay(_ d: DayDate, today: DayDate) -> String {
        switch DayDate.daysBetween(d, today) {
        case 0: return "Oggi"
        case 1: return "Ieri"
        default: return capitalized(d.year == today.year ? dayTitleNoYear(d) : dayTitle(d))
        }
    }

    /// "07:42"
    public static func time(minuteOfDay m: Int) -> String {
        ClockTime(minutes: m).label
    }

    /// "10 s", "1 min 5 s", "12 min", "2 h 5 min"
    public static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 {
            let m = s / 60, r = s % 60
            return r == 0 || m >= 10 ? "\(m) min" : "\(m) min \(r) s"
        }
        let h = s / 3600, m = (s % 3600) / 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Player clock "0:07", "1:05", "1:02:03".
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        if s >= 3600 { return "\(s / 3600):" + pad((s % 3600) / 60, 2) + ":" + pad(s % 60, 2) }
        return "\(s / 60):" + pad(s % 60, 2)
    }

    /// "820 KB", "12,4 MB", "1,2 GB" (decimal units, like iOS Settings).
    public static func bytes(_ b: Int) -> String {
        let v = Double(max(0, b))
        if v < 1_000 { return "\(Int(v)) B" }
        if v < 1_000_000 { return "\(Int((v / 1_000).rounded())) KB" }
        if v < 1_000_000_000 { return decimal(v / 1_000_000, digits: v < 100_000_000 ? 1 : 0) + " MB" }
        return decimal(v / 1_000_000_000, digits: 1) + " GB"
    }

    /// "1,5" (Italian decimal comma, trailing ",0" removed).
    public static func decimal(_ v: Double, digits: Int = 1) -> String {
        let f = pow(10, Double(digits))
        let r = (v * f).rounded() / f
        if digits == 0 || r == r.rounded() { return number(Int(r.rounded())) }
        let whole = Int(r.rounded(.towardZero))
        let frac = Int((abs(r - Double(whole)) * f).rounded())
        return (r < 0 && whole == 0 ? "-" : "") + number(whole) + "," + pad(frac, digits)
    }

    /// "1.234"
    public static func number(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    public static func clips(_ n: Int) -> String { "\(number(n)) clip" }
    public static func days(_ n: Int) -> String { n == 1 ? "1 giorno" : "\(number(n)) giorni" }
    public static func places(_ n: Int) -> String { n == 1 ? "1 luogo" : "\(number(n)) luoghi" }

    /// "Un anno fa", "2 anni fa"
    public static func yearsAgo(_ n: Int) -> String { n == 1 ? "Un anno fa" : "\(n) anni fa" }

    /// "12°"
    public static func temperature(_ c: Double) -> String { "\(Int(c.rounded()))°" }

    /// "7–8"
    public static func hourRange(_ h: Int) -> String { "\(h)–\((h + 1) % 24)" }

    public static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    public static func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }
}
