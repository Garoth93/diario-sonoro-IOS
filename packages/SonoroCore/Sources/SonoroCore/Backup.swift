import Foundation

/// `diario.json` at the root of a backup ZIP.
public struct BackupManifest: Codable, Equatable, Sendable {
    public static let formatID = "diario-sonoro-backup"
    public static let entryName = "diario.json"

    public var format: String
    public var version: Int
    public var createdAt: Date
    public var appVersion: String
    public var data: DiaryData

    public init(createdAt: Date, appVersion: String, data: DiaryData) {
        format = Self.formatID
        version = 1
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.data = data
    }
}

public struct BackupSummary: Equatable, Sendable {
    public let clips: Int
    public let soundtracks: Int
    public let audioFiles: Int
    public let missingFiles: Int
    public let bytes: Int
}

public enum BackupError: Error, Equatable {
    case notABackup
    case newerVersion(Int)
}

/// Backup = ZIP with `diario.json` + every audio file at its relative path.
public enum BackupArchive {
    @discardableResult
    public static func create(data: DiaryData, root: URL, to zipURL: URL, createdAt: Date = Date(),
                              appVersion: String = "") throws -> BackupSummary {
        let writer = try ZipWriter(url: zipURL, date: createdAt)
        let manifest = BackupManifest(createdAt: createdAt, appVersion: appVersion, data: data)
        try writer.add(try JSONFileStore<BackupManifest>.encoder.encode(manifest), as: BackupManifest.entryName)
        var files = 0, missing = 0
        let paths = data.clips.map(\.fileName) + data.soundtracks.map(\.fileName)
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            let url = root.appendingPathComponent(path)
            guard FileNaming.isAudioPath(path), FileInfo.exists(url) else { missing += 1; continue }
            try writer.addFile(at: url, as: path)
            files += 1
        }
        try writer.finish()
        return BackupSummary(clips: data.clips.count, soundtracks: data.soundtracks.count, audioFiles: files,
                             missingFiles: missing, bytes: FileInfo.size(of: zipURL))
    }

    /// Reads only the manifest (to ask for confirmation before restoring).
    public static func inspect(_ zipURL: URL) throws -> BackupManifest {
        let reader: ZipReader
        do { reader = try ZipReader(url: zipURL) } catch { throw BackupError.notABackup }
        guard let entry = reader.entry(named: BackupManifest.entryName) else { throw BackupError.notABackup }
        let manifest: BackupManifest
        do {
            manifest = try JSONFileStore<BackupManifest>.decoder.decode(BackupManifest.self, from: try reader.data(for: entry))
        } catch {
            throw BackupError.notABackup
        }
        guard manifest.format == BackupManifest.formatID else { throw BackupError.notABackup }
        guard manifest.version <= 1 else { throw BackupError.newerVersion(manifest.version) }
        return manifest
    }

    /// Replaces the audio folders under `root` with the backup content and
    /// returns the restored data (the caller saves it). Extraction happens in a
    /// staging folder first: a broken ZIP leaves the current diary untouched.
    public static func restore(_ zipURL: URL, into root: URL) throws -> DiaryData {
        let manifest = try inspect(zipURL)
        let reader = try ZipReader(url: zipURL)
        let fm = FileManager.default
        let staging = root.appendingPathComponent(".restore-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for entry in reader.entries where entry.name != BackupManifest.entryName {
            guard FileNaming.isAudioPath(entry.name) else { continue }
            _ = try reader.extract(entry, into: staging)
        }
        for folder in [FileNaming.clipsFolder, FileNaming.soundtracksFolder] {
            let target = root.appendingPathComponent(folder)
            let source = staging.appendingPathComponent(folder)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            if fm.fileExists(atPath: source.path) { try fm.moveItem(at: source, to: target) }
        }
        var data = manifest.data
        // Soundtracks whose file was not in the backup are rebuilt later.
        data.soundtracks.removeAll { !FileInfo.exists(root.appendingPathComponent($0.fileName)) }
        return data
    }
}

/// CSV of all clips (`;` separated, UTF-8 with BOM for Excel / Numbers).
public enum CSVExport {
    public static let header = ["data", "ora", "durata_s", "luogo", "localita", "lat", "lon", "meteo",
                                "temperatura_c", "emoji", "nota", "preferito", "file"]

    public static func clips(_ clips: [Clip]) -> String {
        var lines = [header.joined(separator: ";")]
        for c in clips.sorted(by: Clip.chronological) {
            let row: [String] = [
                c.day.iso,
                ItalianFormat.time(minuteOfDay: c.minuteOfDay),
                ItalianFormat.decimal(c.duration, digits: 1),
                c.placeName ?? "",
                c.locality ?? "",
                c.location.map { coordinate($0.lat) } ?? "",
                c.location.map { coordinate($0.lon) } ?? "",
                c.weather?.condition ?? "",
                c.weather.map { ItalianFormat.decimal($0.temperatureC, digits: 1) } ?? "",
                c.emoji,
                c.note,
                c.isFavorite ? "sì" : "no",
                c.fileName
            ]
            lines.append(row.map(escape).joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func coordinate(_ v: Double) -> String {
        String(format: "%.5f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func escape(_ s: String) -> String {
        if s.contains(";") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
