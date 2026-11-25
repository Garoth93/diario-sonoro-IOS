import XCTest
@testable import SonoroCore

final class CloudBackupTests: XCTestCase {
    func sample() -> DiaryData {
        var data = DiaryData(clips: [makeClip("2026-11-21", 9, place: "Bosco", favorite: true),
                                     makeClip("2026-11-20", 18, place: "Lungo Sile"),
                                     makeClip("2026-11-21", 7, place: "Casa")])
        data.settings.clipDuration = 15
        data.setSoundtrack(DailySoundtrack(day: day("2026-11-20"), fileName: "soundtracks/2026/2026-11-20.m4a",
                                           duration: 10, clipIDs: [], createdAt: Date()))
        return data
    }

    func testFileContentAndRoundTrip() throws {
        let file = CloudBackupFile(data: sample(), includesAudio: false, appVersion: "1.0.0", now: at("2026-11-21", 22))
        XCTAssertEqual(file.version, 1)
        XCTAssertEqual(file.app, "DiarioSonoro")
        XCTAssertTrue(file.data.soundtracks.isEmpty) // rebuilt from the clips
        XCTAssertEqual(file.data.clips.map(\.minuteOfDay), [18 * 60, 7 * 60, 9 * 60]) // chronological
        XCTAssertEqual(file.days.map(\.day), [day("2026-11-21"), day("2026-11-20")])
        XCTAssertEqual(file.days[0].clips, 2)
        XCTAssertEqual(file.days[0].places, ["Casa", "Bosco"])
        XCTAssertEqual(file.days[0].favorites, 1)
        XCTAssertEqual(file.data.settings.clipDuration, 15)
        let back = try CloudBackupFile.decode(try file.encoded())
        XCTAssertEqual(back, file)
        XCTAssertEqual(back.audioFiles.map(\.name), file.data.clips.map { ($0.fileName as NSString).lastPathComponent })
        let json = String(data: try file.encoded(), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"version\" : 1"))
        XCTAssertFalse(json.lowercased().contains("token"))
    }

    func testDecodeErrors() throws {
        XCTAssertThrowsError(try CloudBackupFile.decode(Data("nope".utf8))) { XCTAssertEqual($0 as? CloudBackupError, .unreadable) }
        XCTAssertThrowsError(try CloudBackupFile.decode(Data("{\"app\":\"Cresta\",\"version\":1}".utf8))) {
            XCTAssertEqual($0 as? CloudBackupError, .wrongApp)
        }
        XCTAssertThrowsError(try CloudBackupFile.decode(Data("{\"app\":\"DiarioSonoro\",\"version\":9}".utf8))) {
            XCTAssertEqual($0 as? CloudBackupError, .newerVersion(9))
        }
        XCTAssertNotNil(CloudBackupError.wrongApp.errorDescription)
    }

    func testNamesEntriesAndPruning() {
        XCTAssertEqual(CloudBackupPlan.dailyName(for: day("2026-11-21")), "DiarioSonoro-backup-2026-11-21.json")
        XCTAssertEqual(CloudBackupPlan.audioName(for: "clips/2026/11/20261121-090000-abcdef01.m4a"), "20261121-090000-abcdef01.m4a")
        XCTAssertEqual(CloudBackupPlan.realName(".DiarioSonoro-backup-latest.json.icloud"), "DiarioSonoro-backup-latest.json")
        let names = ["DiarioSonoro-backup-latest.json", ".DiarioSonoro-backup-2026-11-20.json.icloud",
                     "DiarioSonoro-backup-2026-11-21.json", "DiarioSonoro-backup-2026-11-19.json", "altro.txt", "audio"]
        let e = CloudBackupPlan.entries(fromFileNames: names)
        XCTAssertEqual(e.map(\.name), ["DiarioSonoro-backup-latest.json", "DiarioSonoro-backup-2026-11-21.json",
                                       "DiarioSonoro-backup-2026-11-20.json", "DiarioSonoro-backup-2026-11-19.json"])
        XCTAssertTrue(e[0].isLatest)
        XCTAssertEqual(e[1].day, day("2026-11-21"))
        XCTAssertEqual(CloudBackupPlan.namesToPrune(names, keep: 2), ["DiarioSonoro-backup-2026-11-19.json"])
        XCTAssertTrue(CloudBackupPlan.namesToPrune(names).isEmpty)
        XCTAssertEqual(CloudBackupPlan.missing(["a.m4a", "b.m4a", "b.m4a", "c.m4a"], existing: ["a.m4a", ".c.m4a.icloud"]), ["b.m4a"])
    }

    func testFingerprintIgnoresTimeButNotContent() {
        let base = sample()
        let a = CloudBackupFile(data: base, includesAudio: false, now: at("2026-11-21", 10))
        let b = CloudBackupFile(data: base, includesAudio: false, now: at("2026-11-22", 10))
        XCTAssertEqual(CloudBackupPlan.fingerprint(a), CloudBackupPlan.fingerprint(b))
        var changed = base
        changed.update(changed.clips[0].id) { $0.note = "Campane" }
        XCTAssertNotEqual(CloudBackupPlan.fingerprint(a), CloudBackupPlan.fingerprint(CloudBackupFile(data: changed, includesAudio: false)))
        XCTAssertNotEqual(CloudBackupPlan.fingerprint(a), CloudBackupPlan.fingerprint(CloudBackupFile(data: base, includesAudio: true)))
    }

    func testEmptyNeverOverwritesAndRestore() {
        XCTAssertFalse(CloudBackupPlan.shouldBackup(DiaryData()))
        XCTAssertTrue(CloudBackupPlan.shouldBackup(sample()))
        let restored = CloudBackupPlan.restoredData(from: CloudBackupFile(data: sample(), includesAudio: true))
        XCTAssertEqual(restored.clips.count, 3)
        XCTAssertTrue(restored.soundtracks.isEmpty)
        XCTAssertEqual(restored.settings.clipDuration, 15)
    }

    func testSettingsDefaults() throws {
        let s = DiarySettings()
        XCTAssertTrue(s.cloudBackup)
        XCTAssertFalse(s.cloudBackupAudio) // personal recordings: off by default
        let old = try JSONDecoder().decode(DiarySettings.self, from: Data("{}".utf8))
        XCTAssertTrue(old.cloudBackup)
        XCTAssertFalse(old.cloudBackupAudio)
    }
}
