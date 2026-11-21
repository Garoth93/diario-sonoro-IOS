import XCTest
@testable import SonoroCore

final class DayDateTests: XCTestCase {
    func testParseAndFormat() {
        XCTAssertEqual(day("2026-11-21").iso, "2026-11-21")
        XCTAssertEqual(day("2026-11-21").compact, "20261121")
        XCTAssertNil(DayDate(iso: "2026-02-30"))
        XCTAssertNil(DayDate(iso: "2026-13-01"))
        XCTAssertNil(DayDate(iso: "26-11-21"))
        XCTAssertNotNil(DayDate(iso: "2024-02-29"))
        XCTAssertNil(DayDate(iso: "2025-02-29"))
    }

    func testArithmeticAcrossDST() {
        let d = day("2026-03-28")
        XCTAssertEqual(d.adding(days: 1), day("2026-03-29"))
        XCTAssertEqual(d.adding(days: 4), day("2026-04-01"))
        XCTAssertEqual(DayDate.daysBetween(day("2025-12-31"), day("2026-01-01")), 1)
        XCTAssertEqual(day("2026-11-21").weekdayFromMonday, 5) // sabato
        XCTAssertEqual(day("2026-11-23").weekdayFromMonday, 0) // lunedì
    }

    func testLocalDayUsesTimeZone() {
        // 23:30 in Rome on 21 Nov is 22:30 UTC: same local day in Rome.
        let date = at("2026-11-21", 23, 30)
        XCTAssertEqual(DayDate(date: date, timeZone: rome), day("2026-11-21"))
        XCTAssertEqual(DayDate(date: date, timeZone: TimeZone(identifier: "Asia/Tokyo")!), day("2026-11-22"))
        XCTAssertEqual(minuteOfDay(date, timeZone: rome), 23 * 60 + 30)
    }

    func testCodableAsString() throws {
        let data = try JSONEncoder().encode([day("2026-01-05")])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2026-01-05\"]")
        XCTAssertEqual(try JSONDecoder().decode([DayDate].self, from: data), [day("2026-01-05")])
    }

    func testMonthRef() {
        let m = MonthRef(year: 2026, month: 12)
        XCTAssertEqual(m.next, MonthRef(year: 2027, month: 1))
        XCTAssertEqual(MonthRef(year: 2026, month: 1).previous, MonthRef(year: 2025, month: 12))
        XCTAssertEqual(MonthRef(year: 2024, month: 2).numberOfDays, 29)
        XCTAssertEqual(m.adding(months: -14), MonthRef(year: 2025, month: 10))
        XCTAssertTrue(m.contains(day("2026-12-31")))
    }
}

final class MonthGridTests: XCTestCase {
    func testNovember2026Layout() {
        // 1 Nov 2026 is a Sunday: 6 empty cells before it (Monday first).
        let counts = [day("2026-11-01"): 1, day("2026-11-21"): 3, day("2026-11-10"): 8]
        let grid = MonthGrid(month: MonthRef(year: 2026, month: 11), counts: counts,
                             soundtracks: [day("2026-11-10")], today: day("2026-11-21"))
        XCTAssertEqual(grid.cells.count % 7, 0)
        XCTAssertEqual(grid.cells.prefix(6).filter { $0.day == nil }.count, 6)
        XCTAssertEqual(grid.cells[6].day, day("2026-11-01"))
        XCTAssertEqual(grid.cells.compactMap(\.day).count, 30)
        XCTAssertEqual(grid.weeks.count, 6)
        XCTAssertEqual(grid.recordedDays, 3)
        XCTAssertEqual(grid.clipCount, 12)
        let today = grid.cells.first { $0.isToday }!
        XCTAssertEqual(today.day, day("2026-11-21"))
        XCTAssertEqual(today.level, 2)
        XCTAssertTrue(grid.cells.first { $0.day == day("2026-11-10") }!.hasSoundtrack)
        XCTAssertEqual(grid.cells.first { $0.day == day("2026-11-10") }!.level, 4)
        XCTAssertTrue(grid.cells.first { $0.day == day("2026-11-22") }!.isFuture)
    }

    func testMonthStartingOnMondayHasNoPadding() {
        let grid = MonthGrid(month: MonthRef(year: 2026, month: 6), counts: [:], today: day("2026-11-21"))
        XCTAssertEqual(grid.cells.first?.day, day("2026-06-01"))
        XCTAssertEqual(grid.cells.count, 35)
    }

    func testIntensityScaleIsConfigurable() {
        let s = IntensityScale.default
        XCTAssertEqual([0, 1, 2, 3, 4, 6, 7, 20].map(s.level), [0, 1, 2, 2, 3, 3, 4, 4])
        let custom = IntensityScale(thresholds: [1, 5])
        XCTAssertEqual([0, 1, 4, 5, 9].map(custom.level), [0, 1, 1, 2, 2])
    }

    func testMonthRange() {
        let clips = [makeClip("2026-09-03", 10)]
        let months = MonthRange.months(clips: clips, today: day("2026-11-21"))
        XCTAssertEqual(months.map(\.id), ["2026-09", "2026-10", "2026-11"])
        XCTAssertEqual(MonthRange.months(clips: [], today: day("2026-11-21")).map(\.id), ["2026-11"])
    }
}

final class DayGroupingTests: XCTestCase {
    func testGroupsChronologicallyNewestDayFirst() {
        let a = makeClip("2026-11-20", 18, place: "Lungo Sile")
        let b = makeClip("2026-11-21", 9, place: "Bosco")
        let c = makeClip("2026-11-21", 7, place: "Casa", emoji: "🐦")
        let d = makeClip("2026-11-21", 12, place: "Bosco", emoji: "🐦", favorite: true)
        let groups = DayGrouping.group([a, b, c, d])
        XCTAssertEqual(groups.map(\.day), [day("2026-11-21"), day("2026-11-20")])
        XCTAssertEqual(groups[0].clips.map(\.minuteOfDay), [7 * 60, 9 * 60, 12 * 60])
        XCTAssertEqual(groups[0].places, ["Casa", "Bosco"])
        XCTAssertEqual(groups[0].emojis, ["🐦"])
        XCTAssertEqual(groups[0].totalDuration, 30)
        XCTAssertEqual(groups[0].favorites, 1)
        XCTAssertEqual(DayGrouping.counts([a, b, c])[day("2026-11-21")], 2)
    }

    func testDiaryQueriesAndMutations() {
        var data = DiaryData()
        let a = makeClip("2026-11-21", 9)
        let b = makeClip("2026-11-21", 8)
        data.add(a)
        data.add(b)
        data.add(a) // upsert, no duplicate
        XCTAssertEqual(data.clips.count, 2)
        XCTAssertEqual(data.clips(on: day("2026-11-21")).map(\.id), [b.id, a.id])
        data.update(a.id) { $0.note = "Campane" }
        XCTAssertEqual(data.clip(a.id)?.note, "Campane")
        let removed = data.removeClips([b.id])
        XCTAssertEqual(removed.map(\.id), [b.id])
        XCTAssertEqual(data.recordedDays, [day("2026-11-21")])
    }
}
