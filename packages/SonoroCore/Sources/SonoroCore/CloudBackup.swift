import Foundation

/// One recorded day, written in the backup for readability (the restore
/// uses `data`; this is a summary anyone can read in the Files app).
public struct BackupDay: Codable, Equatable, Sendable {
    public var day: DayDate
    public var clips: Int
    public var seconds: Double
    public var places: [String]
    public var favorites: Int

    public init(_ s: DaySummary) {
        day = s.day
        clips = s.count
        seconds = (s.totalDuration * 10).rounded() / 10
        places = s.places
        favorites = s.favorites
    }
}

public enum CloudBackupError: Error, Equatable, LocalizedError {
    case wrongApp
    case newerVersion(Int)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .wrongApp: return "Questo file non è un backup di Diario Sonoro."
        case .newerVersion(let v): return "Il backup è di una versione più recente dell'app (v\(v)): aggiorna Diario Sonoro e riprova."
        case .unreadable: return "Backup non leggibile."
        }
    }
}

/// Versioned JSON backup kept in iCloud Drive: clips (metadata), days,
/// settings. Soundtracks are not included: they are rebuilt from the clips.
/// Audio files are separate files, only when `includesAudio`.
/// No tokens or secrets exist in the app, nothing sensitive is written.
public struct CloudBackupFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let appName = "DiarioSonoro"

    public var version: Int
    public var app: String
    public var exportedAt: Date
    public var appVersion: String
    /// True when the audio of the clips was copied to `audio/`.
    public var includesAudio: Bool
    public var days: [BackupDay]
    public var data: DiaryData

    public init(data: DiaryData, includesAudio: Bool, appVersion: String = "", now: Date = Date()) {
        version = Self.currentVersion
        app = Self.appName
        exportedAt = now
        self.appVersion = appVersion
        self.includesAudio = includesAudio
        var clean = data
        clean.soundtracks = []
        clean.clips.sort(by: Clip.chronological)
        days = DayGrouping.group(clean.clips).map(BackupDay.init)
        self.data = clean
    }

    public func encoded() throws -> Data {
        try JSONFileStore<CloudBackupFile>.encoder.encode(self)
    }

    public static func decode(_ raw: Data) throws -> CloudBackupFile {
        struct Header: Decodable { var app: String?; var version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: raw) else {
            throw CloudBackupError.unreadable
        }
        guard header.app == appName else { throw CloudBackupError.wrongApp }
        if let v = header.version, v > currentVersion { throw CloudBackupError.newerVersion(v) }
        do {
            return try JSONFileStore<CloudBackupFile>.decoder.decode(CloudBackupFile.self, from: raw)
        } catch {
            throw CloudBackupError.unreadable
        }
    }

    /// Audio files (iCloud name → clip path) the backup refers to.
    public var audioFiles: [(name: String, path: String)] {
        data.clips.map { (CloudBackupPlan.audioName(for: $0.fileName), $0.fileName) }
    }
}

/// Automatic backups in iCloud Drive: shared container
/// `iCloud.com.garoth93.backup`, sub-folder "DiarioSonoro", visible in Files
/// as iCloud Drive › Backup › DiarioSonoro.
///
/// Files: `DiarioSonoro-backup-yyyy-MM-dd.json` (one per day, overwritten
/// during the day, the last `keepDaily` kept), `DiarioSonoro-backup-latest.json`,
/// and — only if enabled — `audio/<clip file name>.m4a`, written once (a clip
/// never changes).
public enum CloudBackupPlan {
    public static let containerID = "iCloud.com.garoth93.backup"
    public static let folderName = "DiarioSonoro"
    public static let prefix = "DiarioSonoro-backup-"
    public static let latestName = "DiarioSonoro-backup-latest.json"
    public static let audioFolder = "audio"
    public static let keepDaily = 30
    /// Wait after a change before writing (many edits → one backup).
    public static let debounceSeconds = 8.0

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        /// Day of the backup (nil for "latest").
        public var day: DayDate?
        public var isLatest: Bool { day == nil }
    }

    public static func dailyName(for day: DayDate) -> String { "\(prefix)\(day.iso).json" }

    /// Clip path "clips/2026/11/x.m4a" → "x.m4a" (names are unique: time + id).
    public static func audioName(for clipPath: String) -> String {
        clipPath.split(separator: "/").last.map(String.init) ?? clipPath
    }

    /// iCloud placeholder of a file not downloaded yet: ".name.json.icloud".
    public static func realName(_ fileName: String) -> String {
        guard fileName.hasPrefix("."), fileName.hasSuffix(".icloud") else { return fileName }
        return String(fileName.dropFirst().dropLast(".icloud".count))
    }

    /// Backups found in the folder, newest first ("latest" on top).
    public static func entries(fromFileNames names: [String]) -> [Entry] {
        var latest: Entry?
        var daily: [Entry] = []
        for raw in Set(names.map(realName)) {
            if raw == latestName {
                latest = Entry(name: raw, day: nil)
            } else if raw.hasPrefix(prefix), raw.hasSuffix(".json"),
                      let d = DayDate(iso: String(raw.dropFirst(prefix.count).dropLast(5))) {
                daily.append(Entry(name: raw, day: d))
            }
        }
        daily.sort { $0.day! > $1.day! }
        return (latest.map { [$0] } ?? []) + daily
    }

    /// Daily files beyond the newest `keep`.
    public static func namesToPrune(_ names: [String], keep: Int = keepDaily) -> [String] {
        let daily = entries(fromFileNames: names).filter { !$0.isLatest }
        return daily.count > keep ? daily[keep...].map(\.name) : []
    }

    /// Files to upload: wanted ones not yet in iCloud.
    public static func missing(_ wanted: [String], existing: [String]) -> [String] {
        let have = Set(existing.map(realName))
        var seen = Set<String>()
        return wanted.filter { !have.contains($0) && seen.insert($0).inserted }
    }

    /// Fingerprint of what a backup contains, not of when it was made: an
    /// unchanged fingerprint means no new backup is needed.
    public static func fingerprint(_ backup: CloudBackupFile) -> String {
        var b = backup
        b.exportedAt = Date(timeIntervalSince1970: 0)
        guard let data = try? JSONFileStore<CloudBackupFile>.encoder.encode(b) else { return "" }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            h ^= UInt64(byte)
            h = h &* 0x100_0000_01b3
        }
        return String(h, radix: 16) + "-" + String(data.count)
    }

    /// An empty diary never overwrites existing backups.
    public static func shouldBackup(_ data: DiaryData) -> Bool { !data.clips.isEmpty }

    /// The restored diary: settings and clips from the backup, no soundtracks
    /// (rebuilt from the audio available on the phone).
    public static func restoredData(from backup: CloudBackupFile) -> DiaryData {
        var d = backup.data
        d.soundtracks = []
        return d
    }
}
