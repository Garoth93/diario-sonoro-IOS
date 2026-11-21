import XCTest
@testable import SonoroCore

final class RecordingRulesTests: XCTestCase {
    func testDurationIsClampedAndOutcome() {
        XCTAssertEqual(RecordingRules(clipDuration: 2).maxDuration, 5)
        XCTAssertEqual(RecordingRules(clipDuration: 90).maxDuration, 30)
        let r = RecordingRules(clipDuration: 10)
        XCTAssertEqual(r.progress(elapsed: 5), 0.5)
        XCTAssertEqual(r.progress(elapsed: 12), 1)
        XCTAssertEqual(r.remainingSeconds(elapsed: 0), 10)
        XCTAssertEqual(r.remainingSeconds(elapsed: 0.2), 10)
        XCTAssertEqual(r.remainingSeconds(elapsed: 9.5), 1)
        XCTAssertEqual(r.remainingSeconds(elapsed: 11), 0)
        XCTAssertTrue(r.shouldAutoStop(elapsed: 10))
        XCTAssertEqual(r.outcome(elapsed: 1.5), .tooShort(duration: 1.5))
        XCTAssertEqual(r.outcome(elapsed: 2), .save(duration: 2))
        XCTAssertEqual(r.outcome(elapsed: 10.4), .save(duration: 10))
    }

    func testSettingsClampAndTolerantDecoding() throws {
        var s = DiarySettings(clipDuration: 50, crossfade: 9)
        XCTAssertEqual(s.clipDuration, 30)
        XCTAssertEqual(s.crossfade, 3)
        s.clipDuration = 1
        XCTAssertEqual(s.clipDuration, 5)
        let decoded = try JSONDecoder().decode(DiarySettings.self, from: Data("{\"clipDuration\": 20, \"quality\": \"futura\"}".utf8))
        XCTAssertEqual(decoded.clipDuration, 20)
        XCTAssertEqual(decoded.quality, .standard)
        XCTAssertEqual(decoded.soundtrackTime, ClockTime(hour: 21, minute: 30))
        let data = try JSONDecoder().decode(DiaryData.self, from: Data("{}".utf8))
        XCTAssertTrue(data.clips.isEmpty)
    }

    func testQualityEstimates() {
        XCTAssertEqual(AudioQuality.standard.estimatedBytes(seconds: 10), 80_000 + 2_048)
        XCTAssertLessThan(AudioQuality.compact.estimatedBytes(seconds: 10), AudioQuality.high.estimatedBytes(seconds: 10))
    }
}

final class WaveformTests: XCTestCase {
    func testLevelsAndResampling() {
        XCTAssertEqual(Waveform.level(decibels: -80), 0)
        XCTAssertEqual(Waveform.level(decibels: 0), 1)
        XCTAssertEqual(Waveform.level(decibels: -.infinity), 0)
        XCTAssertGreaterThan(Waveform.level(decibels: -10), Waveform.level(decibels: -30))
        let shrunk = Waveform.resample([0, 1, 0, 0, 0.5, 0], to: 3)
        XCTAssertEqual(shrunk, [1, 0, 0.5])
        let stretched = Waveform.resample([0, 1], to: 3)
        XCTAssertEqual(stretched, [0, 0.5, 1])
        XCTAssertEqual(Waveform.resample([], to: 4), [0, 0, 0, 0])
        XCTAssertEqual(Waveform.clipWaveform(levels: [0.1, 0.2, 0.4], bins: 3), [64, 128, 255])
        XCTAssertEqual(Waveform.dequantize([255, 0]), [1, 0])
        XCTAssertEqual(Waveform.normalize([0, 0]), [0, 0])
        XCTAssertEqual(Waveform.playedBars(progress: 0.5, bars: 48), 24)
    }

    func testConcatSharesByDuration() {
        let out = Waveform.concat([([1], 30), ([0], 10)], bins: 8)
        XCTAssertEqual(out.count, 8)
        XCTAssertEqual(out.filter { $0 == 1 }.count, 6)
    }
}

final class SoundtrackPlanTests: XCTestCase {
    func testCrossfadedTimeline() {
        let ids = (0..<3).map { _ in UUID() }
        let plan = SoundtrackPlan(clips: [(ids[0], 10), (ids[1], 10), (ids[2], 4)], crossfade: 3)
        XCTAssertEqual(plan.segments.map(\.start), [0, 7, 15])
        XCTAssertEqual(plan.segments.map(\.track), [0, 1, 0])
        XCTAssertEqual(plan.segments[1].fadeIn, 3)
        // The last crossfade is limited to half of the 4-second clip.
        XCTAssertEqual(plan.segments[1].fadeOut, 2)
        XCTAssertEqual(plan.segments[2].fadeIn, 2)
        XCTAssertEqual(plan.segments[0].fadeIn, 0.3)
        XCTAssertEqual(plan.totalDuration, 19)
        XCTAssertEqual(plan.segmentIndex(at: 8), 1)
        XCTAssertEqual(plan.segmentIndex(at: 0), 0)
        XCTAssertEqual(plan.segmentIndex(at: 18), 2)
    }

    func testSingleAndNoCrossfade() {
        let single = SoundtrackPlan(clips: [(UUID(), 10)], crossfade: 1)
        XCTAssertEqual(single.totalDuration, 10)
        XCTAssertEqual(single.segments[0].fadeOut, 0.3)
        let plain = SoundtrackPlan(clips: [(UUID(), 5), (UUID(), 5)], crossfade: 0)
        XCTAssertEqual(plain.totalDuration, 10)
        XCTAssertTrue(SoundtrackPlan(clips: [], crossfade: 1).isEmpty)
    }

    func testPlanFromClipsIsChronological() {
        let late = makeClip("2026-11-21", 20)
        let early = makeClip("2026-11-21", 7)
        let plan = SoundtrackPlan(clips: [late, early], crossfade: 1)
        XCTAssertEqual(plan.segments.map(\.clipID), [early.id, late.id])
    }

    func testScheduler() {
        let today = day("2026-11-21")
        let t1 = makeClip("2026-11-21", 9), t2 = makeClip("2026-11-21", 10)
        let y = makeClip("2026-11-20", 9)
        var data = DiaryData(clips: [t1, t2, y])
        // Before 21:30 only yesterday is due.
        XCTAssertEqual(SoundtrackScheduler.dueDays(data: data, today: today, minuteNow: 20 * 60), [day("2026-11-20")])
        XCTAssertEqual(SoundtrackScheduler.dueDays(data: data, today: today, minuteNow: 21 * 60 + 30), [today, day("2026-11-20")])
        data.setSoundtrack(DailySoundtrack(day: today, fileName: "x", duration: 19, clipIDs: [t1.id, t2.id], createdAt: Date()))
        XCTAssertFalse(SoundtrackScheduler.needsBuild(today, in: data))
        // A clip recorded after the soundtrack makes it outdated.
        data.add(makeClip("2026-11-21", 23))
        XCTAssertTrue(SoundtrackScheduler.needsBuild(today, in: data))
        // No clips → never due; soundtrack without clips is an orphan.
        data.removeClips(Set(data.clips(on: today).map(\.id)))
        XCTAssertFalse(SoundtrackScheduler.needsBuild(today, in: data))
        XCTAssertEqual(SoundtrackScheduler.orphans(in: data).map(\.day), [today])
    }

    func testNextRun() {
        let now = at("2026-11-21", 20, 0)
        let next = SoundtrackScheduler.nextRun(after: now, time: ClockTime(hour: 21, minute: 30), timeZone: rome)
        XCTAssertEqual(next, at("2026-11-21", 21, 30))
        let after = SoundtrackScheduler.nextRun(after: at("2026-11-21", 22, 0), time: ClockTime(hour: 21, minute: 30), timeZone: rome)
        XCTAssertEqual(after, at("2026-11-22", 21, 30))
    }

    func testBuilderWithFakeMerger() async throws {
        let root = tempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = makeClip("2026-11-21", 9), b = makeClip("2026-11-21", 7), missing = makeClip("2026-11-21", 12)
        for c in [a, b] {
            let url = root.appendingPathComponent(c.fileName)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 100).write(to: url)
        }
        var data = DiaryData(clips: [a, b, missing])
        data.settings.crossfade = 2
        let merger = FakeMerger()
        let builder = SoundtrackBuilder(merger: merger, root: root, now: { at("2026-11-21", 21, 30) })
        let s = try await builder.build(day: day("2026-11-21"), data: data)
        XCTAssertEqual(s.fileName, "soundtracks/2026/2026-11-21.m4a")
        XCTAssertEqual(s.duration, 18)
        XCTAssertEqual(s.byteSize, 200)
        XCTAssertEqual(s.clipIDs, [b.id, a.id, missing.id])
        XCTAssertEqual(s.waveform.count, 64)
        XCTAssertEqual(merger.lastPlan?.segments.map(\.clipID), [b.id, a.id])
        XCTAssertEqual(merger.lastInputs.map(\.lastPathComponent), [b, a].map { ($0.fileName as NSString).lastPathComponent })
        XCTAssertTrue(FileInfo.exists(root.appendingPathComponent(s.fileName)))

        do {
            _ = try await builder.build(day: day("2026-11-01"), data: data)
            XCTFail("expected noClips")
        } catch {
            XCTAssertEqual(error as? SoundtrackError, .noClips)
        }
        merger.fail = true
        do {
            _ = try await builder.build(day: day("2026-11-21"), data: data)
            XCTFail("expected mergeFailed")
        } catch let e as SoundtrackError {
            if case .mergeFailed = e {} else { XCTFail("\(e)") }
        }
    }
}

final class CaptureTests: XCTestCase {
    var root: URL!

    override func setUp() { root = tempFolder() }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func controller(_ rec: FakeRecorder, _ loc: FakeLocation?, _ weather: FakeWeather? = nil) -> CaptureController {
        let id = UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000000")!
        return CaptureController(recorder: rec, location: loc, weather: weather, root: root,
                                 now: { at("2026-11-21", 7, 42, 9) }, timeZone: { rome }, makeID: { id })
    }

    func testFullPressSavesClipWithPlaceAndWeather() async throws {
        let rec = FakeRecorder()
        let loc = FakeLocation(access: .allowed)
        let weather = FakeWeather()
        let c = controller(rec, loc, weather)
        var settings = DiarySettings()
        settings.saveWeather = true
        settings.quality = .compact
        try await c.begin(settings: settings)
        XCTAssertTrue(c.isRecording)
        XCTAssertEqual(rec.quality, .compact)
        do {
            try await c.begin(settings: settings)
            XCTFail("double begin")
        } catch {
            XCTAssertEqual(error as? CaptureError, .alreadyRecording)
        }
        guard case .saved(let clip) = try await c.finish() else { return XCTFail("not saved") }
        XCTAssertFalse(c.isRecording)
        XCTAssertEqual(clip.fileName, "clips/2026/11/20261121-074209-abcdef01.m4a")
        XCTAssertEqual(clip.day, day("2026-11-21"))
        XCTAssertEqual(clip.minuteOfDay, 7 * 60 + 42)
        XCTAssertEqual(clip.duration, 10)
        XCTAssertEqual(clip.byteSize, 1_000)
        XCTAssertEqual(clip.waveform.count, Waveform.defaultBins)
        XCTAssertNil(clip.location)

        let enriched = await c.enrich(clip, settings: settings)
        XCTAssertEqual(enriched.location?.lat, 46.0612)
        XCTAssertEqual(enriched.placeName, "Bosco del Cansiglio")
        XCTAssertEqual(enriched.locality, "Fregona")
        XCTAssertEqual(enriched.weather?.condition, "Pioggia")
        XCTAssertEqual(loc.fixes, 1) // one single request, started at begin
        XCTAssertEqual(loc.requests, 0)
        XCTAssertEqual(weather.calls, 1)
    }

    func testShortPressIsDiscarded() async throws {
        let rec = FakeRecorder()
        rec.elapsed = 1.2
        let c = controller(rec, nil)
        try await c.begin(settings: DiarySettings())
        let url = rec.startedURL!
        XCTAssertTrue(FileInfo.exists(url))
        let result = try await c.finish()
        XCTAssertEqual(result, .tooShort(duration: 1.2))
        XCTAssertFalse(FileInfo.exists(url))
    }

    func testEarlyReleaseKeepsWhatWasRecorded() async throws {
        let rec = FakeRecorder()
        rec.elapsed = 4.3
        let c = controller(rec, nil)
        try await c.begin(settings: DiarySettings(clipDuration: 15))
        guard case .saved(let clip) = try await c.finish() else { return XCTFail() }
        XCTAssertEqual(clip.duration, 4.3, accuracy: 0.001)
    }

    func testPermissionAskedAfterRecordingTheFirstTime() async throws {
        let rec = FakeRecorder()
        let loc = FakeLocation(access: .notDetermined)
        let c = controller(rec, loc)
        try await c.begin(settings: DiarySettings())
        XCTAssertEqual(loc.fixes, 0) // no fix while permission is unknown
        guard case .saved(let clip) = try await c.finish() else { return XCTFail() }
        let enriched = await c.enrich(clip, settings: DiarySettings())
        XCTAssertEqual(loc.requests, 1)
        XCTAssertEqual(loc.fixes, 1)
        XCTAssertEqual(enriched.placeName, "Bosco del Cansiglio")
        XCTAssertNil(enriched.weather) // weather off by default
    }

    func testLocationDisabledOrDenied() async throws {
        let rec = FakeRecorder()
        let loc = FakeLocation(access: .denied)
        let c = controller(rec, loc)
        try await c.begin(settings: DiarySettings())
        guard case .saved(let clip) = try await c.finish() else { return XCTFail() }
        let enriched = await c.enrich(clip, settings: DiarySettings())
        XCTAssertNil(enriched.location)
        XCTAssertEqual(loc.requests, 0)

        let off = FakeLocation(access: .allowed)
        let c2 = controller(FakeRecorder(), off)
        var settings = DiarySettings()
        settings.saveLocation = false
        try await c2.begin(settings: settings)
        guard case .saved(let clip2) = try await c2.finish() else { return XCTFail() }
        let e2 = await c2.enrich(clip2, settings: settings)
        XCTAssertNil(e2.location)
        XCTAssertEqual(off.fixes, 0)
    }

    func testRecorderFailureAndCancel() async throws {
        let rec = FakeRecorder()
        rec.fail = true
        let c = controller(rec, nil)
        do {
            try await c.begin(settings: DiarySettings())
            XCTFail()
        } catch {
            if case .recorderFailed = error as? CaptureError {} else { XCTFail("\(error)") }
        }
        XCTAssertFalse(c.isRecording)
        do {
            _ = try await c.finish()
            XCTFail()
        } catch {
            XCTAssertEqual(error as? CaptureError, .notRecording)
        }
        let rec2 = FakeRecorder()
        let c2 = controller(rec2, nil)
        try await c2.begin(settings: DiarySettings())
        await c2.cancel()
        XCTAssertFalse(c2.isRecording)
        XCTAssertFalse(FileInfo.exists(rec2.startedURL!))
    }
}

final class BackupTests: XCTestCase {
    func testZipRoundTrip() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let zip = folder.appendingPathComponent("t.zip")
        let w = try ZipWriter(url: zip, date: at("2026-11-21", 10))
        try w.add(Data("ciao".utf8), as: "a.txt")
        try w.add(Data(repeating: 9, count: 70_000), as: "clips/2026/11/b.m4a")
        XCTAssertThrowsError(try w.add(Data(), as: "../evil"))
        try w.finish()
        let r = try ZipReader(url: zip)
        XCTAssertEqual(r.entries.map(\.name), ["a.txt", "clips/2026/11/b.m4a"])
        XCTAssertEqual(String(data: try r.data(for: r.entries[0]), encoding: .utf8), "ciao")
        XCTAssertEqual(try r.data(for: r.entries[1]).count, 70_000)
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        let bogus = folder.appendingPathComponent("bogus.zip")
        try Data("not a zip at all, sorry".utf8).write(to: bogus)
        XCTAssertThrowsError(try ZipReader(url: bogus))
    }

    func testBackupAndRestore() throws {
        let root = tempFolder(), other = tempFolder()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
        let a = makeClip("2026-11-21", 9, note: "Campane"), b = makeClip("2026-11-20", 9)
        var data = DiaryData(clips: [a, b])
        data.settings.clipDuration = 15
        data.setSoundtrack(DailySoundtrack(day: a.day, fileName: FileNaming.soundtrackPath(day: a.day), duration: 10, clipIDs: [a.id], createdAt: Date()))
        data.setSoundtrack(DailySoundtrack(day: b.day, fileName: FileNaming.soundtrackPath(day: b.day), duration: 10, clipIDs: [b.id], createdAt: Date()))
        for (path, byte) in [(a.fileName, UInt8(1)), (b.fileName, 2), (data.soundtracks[0].fileName, 3)] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: byte, count: 500).write(to: url)
        }
        let zip = root.appendingPathComponent("backup.zip")
        let summary = try BackupArchive.create(data: data, root: root, to: zip, appVersion: "1.0.0")
        XCTAssertEqual(summary.audioFiles, 3)
        XCTAssertEqual(summary.missingFiles, 1) // second soundtrack has no file
        let manifest = try BackupArchive.inspect(zip)
        XCTAssertEqual(manifest.data.clips.count, 2)
        XCTAssertEqual(manifest.appVersion, "1.0.0")

        // Existing content in the destination is replaced.
        let stale = other.appendingPathComponent("clips/old.m4a")
        try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: stale)
        let restored = try BackupArchive.restore(zip, into: other)
        XCTAssertEqual(restored.clips.map(\.id).sorted { $0.uuidString < $1.uuidString }, [a.id, b.id].sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(restored.settings.clipDuration, 15)
        XCTAssertEqual(restored.soundtracks.map(\.day), [a.day]) // the missing one is dropped
        XCTAssertEqual(try Data(contentsOf: other.appendingPathComponent(a.fileName)).first, 1)
        XCTAssertFalse(FileInfo.exists(stale))

        let notBackup = root.appendingPathComponent("x.zip")
        let w = try ZipWriter(url: notBackup)
        try w.add(Data("{}".utf8), as: "other.json")
        try w.finish()
        XCTAssertThrowsError(try BackupArchive.inspect(notBackup)) { XCTAssertEqual($0 as? BackupError, .notABackup) }
    }

    func testCSV() {
        var c = makeClip("2026-11-21", 7, 5, duration: 9.5, place: "Bosco; nord", locality: "Fregona",
                         location: GeoPoint(lat: 46.06123, lon: 12.40211), note: "Detto \"ciao\"", emoji: "🌲", favorite: true)
        c.weather = WeatherInfo(symbol: "sun.max.fill", condition: "Sereno", temperatureC: 12.25)
        let csv = CSVExport.clips([c])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}data;ora;durata_s"))
        let row = csv.components(separatedBy: "\r\n")[1]
        XCTAssertEqual(row, "2026-11-21;07:05;9,5;\"Bosco; nord\";Fregona;46,06123;12,40211;Sereno;12,3;🌲;\"Detto \"\"ciao\"\"\";sì;\(c.fileName)")
    }
}

final class DemoDataTests: XCTestCase {
    func testDeterministicAndRich() {
        let today = day("2026-11-21")
        let a = DemoData.make(today: today)
        let b = DemoData.make(today: today)
        XCTAssertEqual(a, b)
        XCTAssertGreaterThan(a.clips.count, 500)
        XCTAssertFalse(a.clips(on: today).isEmpty)
        XCTAssertEqual(Anniversary.groups(for: today, in: a.clips).prefix(2).map(\.yearsAgo), [1, 2])
        let stats = DiaryStats(data: a, today: today)
        XCTAssertGreaterThanOrEqual(stats.currentStreak, 12)
        XCTAssertGreaterThan(stats.distinctPlaces, 5)
        XCTAssertNil(a.soundtrack(for: today))
        XCTAssertNotNil(a.soundtrack(for: today.adding(days: -1)))
        XCTAssertTrue(a.clips.allSatisfy { $0.location != nil && FileNaming.parseClip($0.fileName)?.day == $0.day })
        XCTAssertTrue(a.clips(on: today).allSatisfy { $0.minuteOfDay < 18 * 60 + 40 })
        // JSON round trip.
        let json = try! JSONFileStore<DiaryData>.encoder.encode(a)
        XCTAssertEqual(try! JSONFileStore<DiaryData>.decoder.decode(DiaryData.self, from: json).clips.count, a.clips.count)
    }
}
