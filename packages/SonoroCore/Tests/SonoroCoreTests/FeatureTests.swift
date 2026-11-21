import XCTest
@testable import SonoroCore

final class FileNamingTests: XCTestCase {
    func testClipPathIsChronologicalAndParsable() {
        let id = UUID(uuidString: "1A2B3C4D-0000-4000-8000-000000000000")!
        let path = FileNaming.clipPath(id: id, recordedAt: at("2026-11-21", 18, 30, 5), timeZone: rome)
        XCTAssertEqual(path, "clips/2026/11/20261121-183005-1a2b3c4d.m4a")
        let info = FileNaming.parseClip(path)
        XCTAssertEqual(info?.day, day("2026-11-21"))
        XCTAssertEqual(info?.minuteOfDay, 18 * 60 + 30)
        XCTAssertEqual(info?.second, 5)
        XCTAssertEqual(info?.idPrefix, "1a2b3c4d")
        XCTAssertNil(FileNaming.parseClip("clips/2026/11/nota.m4a"))
        XCTAssertNil(FileNaming.parseClip("20261321-183005-1a2b3c4d.m4a"))
    }

    func testOtherNames() {
        XCTAssertEqual(FileNaming.soundtrackPath(day: day("2026-11-21")), "soundtracks/2026/2026-11-21.m4a")
        XCTAssertEqual(FileNaming.soundtrackExportName(day: day("2026-11-21")), "Diario Sonoro 2026-11-21.m4a")
        XCTAssertEqual(FileNaming.clipExportName(makeClip("2026-11-21", 7, 5)), "Diario Sonoro 2026-11-21 07.05.m4a")
        XCTAssertEqual(FileNaming.backupName(day: day("2026-11-21")), "diario-sonoro-backup-2026-11-21.zip")
        XCTAssertEqual(FileNaming.csvName(day: day("2026-11-21")), "diario-sonoro-clip-2026-11-21.csv")
    }

    func testSafePaths() {
        XCTAssertTrue(FileNaming.isSafeRelativePath("clips/2026/11/a.m4a"))
        XCTAssertFalse(FileNaming.isSafeRelativePath("../etc/passwd"))
        XCTAssertFalse(FileNaming.isSafeRelativePath("/abs.m4a"))
        XCTAssertFalse(FileNaming.isSafeRelativePath("clips//a.m4a"))
        XCTAssertFalse(FileNaming.isSafeRelativePath("clips/./a.m4a"))
        XCTAssertTrue(FileNaming.isAudioPath("soundtracks/2026/2026-11-21.m4a"))
        XCTAssertFalse(FileNaming.isAudioPath("diario.json"))
        XCTAssertFalse(FileNaming.isAudioPath("clips/x.wav"))
    }
}

final class AnniversaryTests: XCTestCase {
    func testOneTwoThreeYearsAgo() {
        let clips = [
            makeClip("2025-11-21", 8, place: "Bosco"), makeClip("2025-11-21", 7, place: "Casa"),
            makeClip("2024-11-21", 12), makeClip("2023-11-20", 9), makeClip("2026-11-21", 9)
        ]
        let groups = Anniversary.groups(for: day("2026-11-21"), in: clips)
        XCTAssertEqual(groups.map(\.yearsAgo), [1, 2])
        XCTAssertEqual(groups[0].title, "Un anno fa")
        XCTAssertEqual(groups[1].title, "2 anni fa")
        XCTAssertEqual(groups[0].clips.map(\.minuteOfDay), [7 * 60, 8 * 60])
        XCTAssertEqual(groups[0].year, 2025)
        XCTAssertEqual(groups[0].totalDuration, 20)
        XCTAssertTrue(Anniversary.groups(for: day("2026-11-21"), in: clips, maxYears: 0).isEmpty)
    }

    func testLeapDay() {
        let leap = makeClip("2024-02-29", 10)
        let feb28 = makeClip("2024-02-28", 10)
        // 28 Feb 2025 (not leap) shows both 28 and 29 Feb 2024.
        let g = Anniversary.groups(for: day("2025-02-28"), in: [leap, feb28])
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].clips.count, 2)
        XCTAssertEqual(g[0].days, [day("2024-02-28"), day("2024-02-29")])
        // 29 Feb 2028: 4 years ago is 29 Feb 2024; non-leap years were shown on the 28th.
        let g2 = Anniversary.groups(for: day("2028-02-29"), in: [leap, makeClip("2027-02-28", 9)])
        XCTAssertEqual(g2.map(\.yearsAgo), [4])
        // 1 March is never confused with 29 February.
        XCTAssertTrue(Anniversary.groups(for: day("2025-03-01"), in: [leap]).isEmpty)
    }

    func testUpcoming() {
        let clips = [makeClip("2025-11-23", 8), makeClip("2024-11-25", 9)]
        let up = Anniversary.upcoming(from: day("2026-11-21"), count: 7, in: clips)
        XCTAssertEqual(up.map(\.day), [day("2026-11-23"), day("2026-11-25")])
        XCTAssertEqual(up[1].groups.first?.yearsAgo, 2)
    }
}

final class StatsTests: XCTestCase {
    func testTotalsStreaksAndPlaces() {
        var clips: [Clip] = []
        // Streak of 3 ending yesterday (today empty): still alive.
        for d in ["2026-11-18", "2026-11-19", "2026-11-20"] { clips.append(makeClip(d, 8, place: "Lungo Sile")) }
        // Older streak of 4.
        for d in ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"] { clips.append(makeClip(d, 19, place: "Bosco")) }
        clips.append(makeClip("2026-10-04", 7, duration: 30, place: "Bosco", favorite: true))
        clips.append(makeClip("2026-10-04", 7, duration: 5, place: nil))
        var data = DiaryData(clips: clips)
        data.setSoundtrack(DailySoundtrack(day: day("2026-10-04"), fileName: "s.m4a", duration: 40, clipIDs: [], createdAt: Date(), byteSize: 300_000))
        let s = DiaryStats(data: data, today: day("2026-11-21"))
        XCTAssertEqual(s.recordedDays, 7)
        XCTAssertEqual(s.totalClips, 9)
        XCTAssertEqual(s.totalDuration, 7 * 10 + 30 + 5)
        XCTAssertEqual(s.currentStreak, 3)
        XCTAssertEqual(s.longestStreak, 4)
        XCTAssertEqual(s.longestStreakEnd, day("2026-10-04"))
        XCTAssertEqual(s.favorites, 1)
        XCTAssertEqual(s.topPlaces.first?.name, "Bosco")
        XCTAssertEqual(s.topPlaces.first?.clips, 5)
        XCTAssertEqual(s.topPlaces.first?.days, 4)
        XCTAssertEqual(s.distinctPlaces, 2)
        XCTAssertEqual(s.byHour[8], 3)
        XCTAssertEqual(s.byHour[7], 2)
        XCTAssertEqual(s.typicalHour, 19 > 8 ? 19 : 8) // 4 clips at 19
        XCTAssertEqual(s.byWeekday.reduce(0, +), 9)
        XCTAssertEqual(s.byMonth.count, 12)
        XCTAssertEqual(s.byMonth.last?.month, MonthRef(year: 2026, month: 11))
        XCTAssertEqual(s.byMonth.last?.clips, 3)
        XCTAssertEqual(s.byMonth[10].days, 4)
        XCTAssertEqual(s.busiestDay?.day, day("2026-10-04"))
        XCTAssertEqual(s.clipBytes, 9 * 80_000)
        XCTAssertEqual(s.soundtrackBytes, 300_000)
        XCTAssertEqual(s.totalBytes, 1_020_000)
        XCTAssertEqual(s.averagePerDay, 9.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(s.firstDay, day("2026-10-01"))
    }

    func testStreakBrokenAndEmpty() {
        let s = DiaryStats(data: DiaryData(clips: [makeClip("2026-11-10", 9)]), today: day("2026-11-21"))
        XCTAssertEqual(s.currentStreak, 0)
        XCTAssertEqual(s.longestStreak, 1)
        let empty = DiaryStats(data: DiaryData(), today: day("2026-11-21"))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNil(empty.typicalHour)
        XCTAssertEqual(empty.coverage, 0)
        let todayOnly = DiaryStats.streaks(days: [day("2026-11-21"), day("2026-11-20")], today: day("2026-11-21"))
        XCTAssertEqual(todayOnly.current, 2)
    }
}

final class SearchTests: XCTestCase {
    func testTextIsAccentAndCaseInsensitive() {
        let a = makeClip("2026-11-21", 9, place: "Città Alta", locality: "Bergamo", note: "Campane della Città")
        let b = makeClip("2026-11-20", 9, place: "Lungo Sile", note: "Corsa", emoji: "🏃", favorite: true)
        let f = ClipFilter(text: "citta campane")
        XCTAssertEqual(f.apply([a, b]).map(\.id), [a.id])
        XCTAssertEqual(ClipFilter(text: "novembre").apply([a, b]).count, 2)
        XCTAssertEqual(ClipFilter(text: "SILE").apply([a, b]).map(\.id), [b.id])
        XCTAssertEqual(ClipFilter(emoji: "🏃").apply([a, b]).map(\.id), [b.id])
        XCTAssertEqual(ClipFilter(favoritesOnly: true).apply([a, b]).map(\.id), [b.id])
        XCTAssertEqual(ClipFilter(place: "Città Alta").apply([a, b]).map(\.id), [a.id])
        XCTAssertEqual(ClipFilter(from: day("2026-11-21")).apply([a, b]).map(\.id), [a.id])
        XCTAssertEqual(ClipFilter(to: day("2026-11-20")).apply([a, b]).map(\.id), [b.id])
        XCTAssertEqual(ClipFilter().apply([b, a]).map(\.id), [a.id, b.id]) // newest first
        XCTAssertTrue(ClipFilter(text: "  ").isEmpty)
    }

    func testEmojiAndPlaceFacets() {
        let clips = [makeClip("2026-11-21", 9, place: "A", emoji: "🐦"), makeClip("2026-11-21", 10, place: "A", emoji: "🐦"),
                     makeClip("2026-11-21", 11, place: "B", emoji: "🌊")]
        XCTAssertEqual(SearchText.emojis(in: clips).map(\.emoji), ["🐦", "🌊"])
        XCTAssertEqual(SearchText.places(in: clips).map(\.name), ["A", "B"])
        XCTAssertEqual(SearchText.normalize("  Perché   così "), "perche cosi")
    }
}

final class MapTests: XCTestCase {
    let sile = GeoPoint(lat: 45.6638, lon: 12.2533)
    let sileNear = GeoPoint(lat: 45.6640, lon: 12.2540)   // ~60 m
    let bosco = GeoPoint(lat: 46.0612, lon: 12.4021)

    func testFiltersBySeasonYearAndTime() {
        let summer = makeClip("2025-07-10", 9, location: sile)
        let winter = makeClip("2026-01-10", 21, location: sile)
        let noLocation = makeClip("2026-01-10", 21)
        XCTAssertEqual(MapFilter().apply([summer, winter, noLocation]).count, 2)
        XCTAssertEqual(MapFilter(year: 2026).apply([summer, winter]).map(\.id), [winter.id])
        XCTAssertEqual(MapFilter(season: .summer).apply([summer, winter]).map(\.id), [summer.id])
        XCTAssertEqual(MapFilter(timeOfDay: .evening).apply([summer, winter]).map(\.id), [winter.id])
        XCTAssertEqual(Season.of(month: 12), .winter)
        XCTAssertEqual(Season.of(month: 3), .spring)
        XCTAssertEqual(TimeOfDay.of(hour: 4), .night)
        XCTAssertEqual(TimeOfDay.of(hour: 12), .afternoon)
    }

    func testSpotsGroupNearbyClips() {
        let clips = [makeClip("2026-11-01", 9, place: "Lungo Sile", location: sile),
                     makeClip("2026-11-02", 9, place: "Lungo Sile", location: sileNear),
                     makeClip("2026-11-03", 9, place: "Ponte", location: sileNear),
                     makeClip("2026-11-04", 9, place: "Bosco", location: bosco)]
        let spots = PlaceSpots.spots(from: clips, radius: 150)
        XCTAssertEqual(spots.count, 2)
        let s = spots.first { $0.count == 3 }!
        XCTAssertEqual(s.name, "Lungo Sile")
        XCTAssertEqual(s.clips.first?.day, day("2026-11-03")) // newest first
        XCTAssertEqual(PlaceSpots.spots(from: clips, radius: 10).count, 3)
    }

    func testClustersDependOnZoom() {
        let clips = [makeClip("2026-11-01", 9, place: "Sile", location: sile),
                     makeClip("2026-11-04", 9, place: "Bosco", location: bosco),
                     makeClip("2026-11-05", 9, place: "Bosco", location: bosco)]
        let spots = PlaceSpots.spots(from: clips)
        let far = MapClusterer.clusters(spots, cell: MapClusterer.cellSize(latitudeDelta: 6))
        XCTAssertEqual(far.count, 1)
        XCTAssertEqual(far[0].clipCount, 3)
        XCTAssertEqual(far[0].title, "2 luoghi")
        // Center weighted towards Bosco (2 clips).
        XCTAssertGreaterThan(far[0].center.lat, (sile.lat + bosco.lat) / 2)
        let near = MapClusterer.clusters(spots, cell: MapClusterer.cellSize(latitudeDelta: 0.1))
        XCTAssertEqual(near.count, 2)
        XCTAssertEqual(near[0].title, "Bosco")
        XCTAssertTrue(near[0].isSingleSpot)
        let region = MapClusterer.region(fitting: [sile, bosco])!
        XCTAssertGreaterThan(region.latitudeDelta, bosco.lat - sile.lat)
        XCTAssertNil(MapClusterer.region(fitting: []))
    }

    func testDistance() {
        XCTAssertEqual(sile.distance(to: sileNear), 60, accuracy: 15)
        XCTAssertEqual(sile.distance(to: bosco) / 1000, 46, accuracy: 3)
    }
}

final class FormatTests: XCTestCase {
    func testItalianLabels() {
        XCTAssertEqual(ItalianFormat.dayTitle(day("2026-11-21")), "sabato 21 novembre 2026")
        XCTAssertEqual(ItalianFormat.monthTitle(MonthRef(year: 2026, month: 11)), "Novembre 2026")
        XCTAssertEqual(ItalianFormat.relativeDay(day("2026-11-21"), today: day("2026-11-21")), "Oggi")
        XCTAssertEqual(ItalianFormat.relativeDay(day("2026-11-20"), today: day("2026-11-21")), "Ieri")
        XCTAssertEqual(ItalianFormat.relativeDay(day("2026-11-02"), today: day("2026-11-21")), "Lunedì 2 novembre")
        XCTAssertEqual(ItalianFormat.relativeDay(day("2025-11-02"), today: day("2026-11-21")), "Domenica 2 novembre 2025")
        XCTAssertEqual(ItalianFormat.dayShort(day("2026-01-05")), "5 gen 2026")
        XCTAssertEqual(ItalianFormat.time(minuteOfDay: 7 * 60 + 5), "07:05")
    }

    func testNumbers() {
        XCTAssertEqual(ItalianFormat.duration(10), "10 s")
        XCTAssertEqual(ItalianFormat.duration(65), "1 min 5 s")
        XCTAssertEqual(ItalianFormat.duration(720), "12 min")
        XCTAssertEqual(ItalianFormat.duration(7_500), "2 h 5 min")
        XCTAssertEqual(ItalianFormat.clock(65.9), "1:05")
        XCTAssertEqual(ItalianFormat.clock(3_723), "1:02:03")
        XCTAssertEqual(ItalianFormat.bytes(820_000), "820 KB")
        XCTAssertEqual(ItalianFormat.bytes(12_400_000), "12,4 MB")
        XCTAssertEqual(ItalianFormat.bytes(1_250_000_000), "1,3 GB")
        XCTAssertEqual(ItalianFormat.number(1_234_567), "1.234.567")
        XCTAssertEqual(ItalianFormat.decimal(1.5), "1,5")
        XCTAssertEqual(ItalianFormat.decimal(2.0), "2")
        XCTAssertEqual(ItalianFormat.days(1), "1 giorno")
        XCTAssertEqual(ItalianFormat.days(3), "3 giorni")
        XCTAssertEqual(ItalianFormat.yearsAgo(3), "3 anni fa")
        XCTAssertEqual(ItalianFormat.temperature(8.6), "9°")
    }
}

final class LinksTests: XCTestCase {
    func testRoundTrip() {
        let links: [DeepLink] = [.record(.widget), .record(.control), .day(day("2026-11-21")),
                                 .soundtrack(day("2026-11-21")), .anniversary, .calendar, .map, .stats]
        for l in links { XCTAssertEqual(DeepLink(url: l.url), l, l.url.absoluteString) }
        XCTAssertEqual(DeepLink.record(.siri).url.absoluteString, "diariosonoro://record?source=siri")
        XCTAssertEqual(DeepLink(url: URL(string: "diariosonoro://record")!), .record(.app))
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/record")!))
        XCTAssertNil(DeepLink(url: URL(string: "diariosonoro://day/2026-02-30")!))
    }

    func testWidgetSnapshot() {
        let today = day("2026-11-21")
        var data = DiaryData(clips: [makeClip("2026-11-21", 7, place: "Casa"), makeClip("2026-11-21", 18, place: "Lungo Sile"),
                                     makeClip("2026-11-20", 9), makeClip("2025-11-21", 9)])
        let s = WidgetSnapshot.make(data: data, today: today)
        XCTAssertEqual(s.todayClips, 2)
        XCTAssertEqual(s.todayDuration, 20)
        XCTAssertEqual(s.streak, 2)
        XCTAssertEqual(s.lastPlace, "Lungo Sile")
        XCTAssertEqual(s.lastMinute, 18 * 60)
        XCTAssertEqual(s.anniversaryYears, [1])
        XCTAssertFalse(s.soundtrackReady)
        XCTAssertEqual(s.waveform.count, 32)
        let ids = data.clips(on: today).map(\.id)
        data.setSoundtrack(DailySoundtrack(day: today, fileName: "x", duration: 19, clipIDs: ids, createdAt: Date()))
        XCTAssertTrue(WidgetSnapshot.make(data: data, today: today).soundtrackReady)
        // Seen tomorrow: counts reset, streak kept; two days later: streak lost.
        let tomorrow = s.effective(on: today.adding(days: 1))
        XCTAssertEqual(tomorrow.todayClips, 0)
        XCTAssertEqual(tomorrow.streak, 2)
        XCTAssertEqual(s.effective(on: today.adding(days: 2)).streak, 0)
        XCTAssertEqual(s.effective(on: today), s)
    }

    func testNotifications() {
        let today = day("2026-11-21")
        let clips = [makeClip("2026-11-21", 7, place: "Casa"), makeClip("2026-11-21", 18, place: "Lungo Sile"),
                     makeClip("2025-11-22", 9, place: "Bosco")]
        let n = NotificationPlanner.soundtrack(day: today, clips: clips, time: ClockTime(hour: 21, minute: 30))!
        XCTAssertEqual(n.title, "La colonna sonora di oggi è pronta")
        XCTAssertEqual(n.body, "2 clip · 20 s · Casa e 1 luogo in più. Tocca per ascoltarla.")
        XCTAssertEqual(n.link, .soundtrack(today))
        XCTAssertNil(NotificationPlanner.soundtrack(day: day("2026-11-19"), clips: clips, time: ClockTime(hour: 21, minute: 0)))
        let ann = NotificationPlanner.anniversaries(from: today, days: 30, clips: clips, time: ClockTime(hour: 9, minute: 0), minuteNow: 600)
        XCTAssertEqual(ann.count, 1)
        XCTAssertEqual(ann[0].day, day("2026-11-22"))
        XCTAssertEqual(ann[0].title, "Un anno fa oggi")
        XCTAssertEqual(ann[0].body, "Riascolta 1 clip: Bosco.")
        // Today's anniversary already past its time is skipped.
        let late = NotificationPlanner.anniversaries(from: day("2026-11-22"), days: 1, clips: clips, time: ClockTime(hour: 9, minute: 0), minuteNow: 600)
        XCTAssertTrue(late.isEmpty)
    }
}

final class ReminderTests: XCTestCase {
    let ten = ClockTime(hour: 10, minute: 0)
    let twenty = ClockTime(hour: 20, minute: 0)

    func testMomentIsInsideWindowStableAndVaried() {
        var minutes = Set<Int>()
        var d = day("2026-01-01")
        for _ in 0..<120 {
            let m = NotificationPlanner.reminderMinute(day: d, start: ten, end: twenty)
            XCTAssertTrue((600...1200).contains(m), "\(m)")
            XCTAssertEqual(m, NotificationPlanner.reminderMinute(day: d, start: ten, end: twenty)) // stable
            minutes.insert(m)
            d = d.adding(days: 1)
        }
        XCTAssertGreaterThan(minutes.count, 60) // a different moment almost every day
        // Fixed time when start == end.
        XCTAssertEqual(NotificationPlanner.reminderMinute(day: d, start: ten, end: ten), 600)
    }

    func testWindowAcrossMidnight() {
        let late = ClockTime(hour: 22, minute: 0), early = ClockTime(hour: 1, minute: 0)
        for i in 0..<60 {
            let m = NotificationPlanner.reminderMinute(day: day("2026-03-01").adding(days: i), start: late, end: early)
            XCTAssertTrue((22 * 60...25 * 60).contains(m), "\(m)")
        }
    }

    func testPlannedReminders() {
        let today = day("2026-11-21")
        let all = NotificationPlanner.reminders(from: today, days: 7, start: ten, end: twenty, minuteNow: 0, skipToday: false)
        XCTAssertEqual(all.count, 7)
        XCTAssertEqual(all[0].id, "reminder.2026-11-21")
        XCTAssertEqual(all[0].title, "È ora della tua registrazione audio")
        XCTAssertEqual(all[0].link, .record(.notification))
        XCTAssertFalse(all[0].body.isEmpty)
        XCTAssertTrue(all.allSatisfy { (600...1200).contains($0.time.minutes) })
        // Already recorded today → today skipped.
        let skipped = NotificationPlanner.reminders(from: today, days: 7, start: ten, end: twenty, minuteNow: 0, skipToday: true)
        XCTAssertEqual(skipped.first?.day, day("2026-11-22"))
        // Today's moment already passed → skipped.
        let late = NotificationPlanner.reminders(from: today, days: 3, start: ten, end: twenty, minuteNow: 23 * 60, skipToday: false)
        XCTAssertEqual(late.map(\.day), [day("2026-11-22"), day("2026-11-23")])
        // A window crossing midnight fires on the next calendar day.
        let night = NotificationPlanner.reminders(from: today, days: 1, start: ClockTime(hour: 23, minute: 50),
                                                  end: ClockTime(hour: 0, minute: 10), minuteNow: 0, skipToday: false)
        XCTAssertEqual(night.count, 1)
        XCTAssertTrue(night[0].day == today || night[0].day == today.adding(days: 1))
    }

    func testSettingsDefaultsAndDecoding() throws {
        let s = DiarySettings()
        XCTAssertFalse(s.reminderEnabled)
        XCTAssertEqual(s.reminderStart, ten)
        XCTAssertEqual(s.reminderEnd, twenty)
        XCTAssertTrue(s.reminderSkipIfRecorded)
        let decoded = try JSONDecoder().decode(DiarySettings.self, from: Data("{\"reminderEnabled\": true}".utf8))
        XCTAssertTrue(decoded.reminderEnabled)
        XCTAssertEqual(decoded.reminderEnd, twenty)
    }
}
