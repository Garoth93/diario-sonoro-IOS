import Foundation

/// Every file name the app writes, relative to the storage root.
///
/// Layout:
/// ```
/// diary.json
/// clips/2026/11/20261121-183005-1a2b3c4d.m4a
/// soundtracks/2026/2026-11-21.m4a
/// ```
/// Names sort chronologically and stay unique (short id suffix).
public enum FileNaming {
    public static let dataFile = "diary.json"
    public static let clipsFolder = "clips"
    public static let soundtracksFolder = "soundtracks"
    public static let audioExtension = "m4a"

    /// "clips/2026/11/20261121-183005-1a2b3c4d.m4a"
    public static func clipPath(id: UUID, recordedAt: Date, timeZone: TimeZone = .current) -> String {
        let c = DayDate.calendar(timeZone).dateComponents([.year, .month, .day, .hour, .minute, .second], from: recordedAt)
        let y = pad(c.year ?? 1970, 4), m = pad(c.month ?? 1, 2), d = pad(c.day ?? 1, 2)
        let time = pad(c.hour ?? 0, 2) + pad(c.minute ?? 0, 2) + pad(c.second ?? 0, 2)
        let suffix = String(id.uuidString.lowercased().prefix(8))
        return "\(clipsFolder)/\(y)/\(m)/\(y)\(m)\(d)-\(time)-\(suffix).\(audioExtension)"
    }

    /// "soundtracks/2026/2026-11-21.m4a"
    public static func soundtrackPath(day: DayDate) -> String {
        "\(soundtracksFolder)/\(pad(day.year, 4))/\(day.iso).\(audioExtension)"
    }

    /// Parsed parts of a clip file name.
    public struct ClipNameInfo: Equatable, Sendable {
        public let day: DayDate
        public let minuteOfDay: Int
        public let second: Int
        public let idPrefix: String
    }

    /// Reads day, time and id prefix back from a clip path (or bare file name).
    public static func parseClip(_ path: String) -> ClipNameInfo? {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard name.hasSuffix("." + audioExtension) else { return nil }
        let base = name.dropLast(audioExtension.count + 1)
        let parts = base.split(separator: "-")
        guard parts.count == 3, parts[0].count == 8, parts[1].count == 6, parts[2].count == 8,
              let y = Int(parts[0].prefix(4)), let mo = Int(parts[0].dropFirst(4).prefix(2)), let d = Int(parts[0].suffix(2)),
              let h = Int(parts[1].prefix(2)), let mi = Int(parts[1].dropFirst(2).prefix(2)), let s = Int(parts[1].suffix(2)),
              let day = DayDate(year: y, month: mo, day: d), h < 24, mi < 60, s < 60 else { return nil }
        return ClipNameInfo(day: day, minuteOfDay: h * 60 + mi, second: s, idPrefix: String(parts[2]))
    }

    /// File name used when sharing a soundtrack: "Diario Sonoro 2026-11-21.m4a".
    public static func soundtrackExportName(day: DayDate) -> String {
        "Diario Sonoro \(day.iso).\(audioExtension)"
    }

    /// "Diario Sonoro 2026-11-21 18.30.m4a"
    public static func clipExportName(_ clip: Clip) -> String {
        let t = pad(clip.minuteOfDay / 60, 2) + "." + pad(clip.minuteOfDay % 60, 2)
        return "Diario Sonoro \(clip.day.iso) \(t).\(audioExtension)"
    }

    /// "diario-sonoro-backup-2026-11-21.zip"
    public static func backupName(day: DayDate) -> String { "diario-sonoro-backup-\(day.iso).zip" }

    /// "diario-sonoro-clip-2026-11-21.csv"
    public static func csvName(day: DayDate) -> String { "diario-sonoro-clip-\(day.iso).csv" }

    /// Relative path that cannot escape the storage root (used when restoring a ZIP).
    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Audio files a backup may contain.
    public static func isAudioPath(_ path: String) -> Bool {
        isSafeRelativePath(path)
            && (path.hasPrefix(clipsFolder + "/") || path.hasPrefix(soundtracksFolder + "/"))
            && path.hasSuffix("." + audioExtension)
    }
}
