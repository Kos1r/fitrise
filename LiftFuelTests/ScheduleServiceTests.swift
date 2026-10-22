import XCTest
@testable import LiftFuel

final class ScheduleServiceTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Ljubljana") ?? .gmt
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private var service: ScheduleService { ScheduleService(calendar: calendar) }

    /// Thursday 22 Oct 2026 — the reference date from the brief.
    private var thursday: Date { date(2026, 10, 22) }

    func testReferenceDateIsThursday() {
        XCTAssertEqual(calendar.component(.weekday, from: thursday), 5)
    }

    func testDefaultWeeklyTemplate() {
        let s = service
        XCTAssertEqual(s.plannedSplit(on: date(2026, 10, 19)), .pull)  // Mon
        XCTAssertEqual(s.plannedSplit(on: date(2026, 10, 20)), .push)  // Tue
        XCTAssertEqual(s.plannedSplit(on: date(2026, 10, 21)), .rest)  // Wed
        XCTAssertEqual(s.plannedSplit(on: thursday), .rest)            // Thu
        XCTAssertEqual(s.plannedSplit(on: date(2026, 10, 23)), .pull)  // Fri
        XCTAssertEqual(s.plannedSplit(on: date(2026, 10, 24)), .push)  // Sat
        XCTAssertEqual(s.plannedSplit(on: date(2026, 10, 25)), .rest)  // Sun
    }

    func testUpcomingFromThursday() {
        let upcoming = service.upcoming(after: thursday, count: 7).map(\.split)
        // Fri Pull, Sat Push, Sun Rest, Mon Pull, Tue Push, Wed Rest, Thu Rest
        XCTAssertEqual(upcoming, [.pull, .push, .rest, .pull, .push, .rest, .rest])
    }

    func testNextTrainingDayFromThursdayIsFridayPull() throws {
        let next = try XCTUnwrap(service.nextTrainingDay(after: thursday))
        XCTAssertEqual(next.split, .pull)
        XCTAssertTrue(calendar.isDate(next.date, inSameDayAs: date(2026, 10, 23)))
    }

    func testWeekStartsMondayAcrossMonthBoundary() {
        // Sunday 1 Nov 2026 belongs to the week of Monday 26 Oct.
        let interval = service.weekInterval(containing: date(2026, 11, 1))
        XCTAssertTrue(calendar.isDate(interval.start, inSameDayAs: date(2026, 10, 26)))
        XCTAssertTrue(calendar.isDate(interval.end, inSameDayAs: date(2026, 11, 2)))
    }

    func testWeekAcrossYearBoundary() {
        // Thu 31 Dec 2026 → week Mon 28 Dec 2026 … Sun 3 Jan 2027
        let days = service.daysOfWeek(containing: date(2026, 12, 31))
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(calendar.isDate(days[0].date, inSameDayAs: date(2026, 12, 28)))
        XCTAssertTrue(calendar.isDate(days[6].date, inSameDayAs: date(2027, 1, 3)))
        XCTAssertEqual(days.map(\.split), [.pull, .push, .rest, .rest, .pull, .push, .rest])
    }

    func testPlannedTrainingDaysPerWeek() {
        XCTAssertEqual(service.plannedTrainingDays(inWeekContaining: thursday), 4)
    }

    func testOverrideChangesOnlyThatDate() {
        var s = service
        s.overrides = [s.dayKey(for: thursday): .push]
        XCTAssertEqual(s.plannedSplit(on: thursday), .push)
        XCTAssertTrue(s.plannedDay(on: thursday).isOverride)
        XCTAssertEqual(s.plannedSplit(on: date(2026, 10, 29)), .rest) // next Thursday unchanged
        XCTAssertEqual(s.templateSplit(on: thursday), .rest)
    }

    func testSwapDays() {
        let s = service
        let swapped = s.swapped(thursday, date(2026, 10, 23))
        let after = ScheduleService(template: s.template, overrides: swapped, calendar: calendar)
        XCTAssertEqual(after.plannedSplit(on: thursday), .pull)
        XCTAssertEqual(after.plannedSplit(on: date(2026, 10, 23)), .rest)
    }

    func testCompletedThisWeek() {
        let s = service
        let keys: Set<Int> = [s.dayKey(for: date(2026, 10, 19)), s.dayKey(for: date(2026, 10, 20)), s.dayKey(for: date(2026, 10, 18))]
        // Sunday 18th is the previous week.
        XCTAssertEqual(s.completedDays(inWeekContaining: thursday, completedDayKeys: keys), 2)
    }

    func testStreakSkipsRestDaysAndToleratesToday() {
        let s = service
        // Completed: Fri 16, Sat 17, Mon 19, Tue 20. Today Thu 22 (rest). Wed rest.
        let keys = Set([16, 17, 19, 20].map { s.dayKey(for: date(2026, 10, $0)) })
        XCTAssertEqual(s.streak(completedDayKeys: keys, today: thursday), 4)
    }

    func testStreakBreaksOnMissedTrainingDay() {
        let s = service
        // Missed Mon 19 (Pull), did Tue 20.
        let keys: Set<Int> = [s.dayKey(for: date(2026, 10, 17)), s.dayKey(for: date(2026, 10, 20))]
        XCTAssertEqual(s.streak(completedDayKeys: keys, today: thursday), 1)
    }

    func testStreakNotBrokenByUntrainedToday() {
        let s = service
        // Friday 23 (Pull) not yet trained; Tue 20 and Mon 19 done.
        let keys: Set<Int> = [s.dayKey(for: date(2026, 10, 19)), s.dayKey(for: date(2026, 10, 20))]
        XCTAssertEqual(s.streak(completedDayKeys: keys, today: date(2026, 10, 23, hour: 8)), 2)
    }

    func testDayKeyRoundTrip() {
        let key = service.dayKey(for: thursday)
        XCTAssertEqual(key, 20261022)
        let back = service.date(fromDayKey: key)
        XCTAssertNotNil(back)
        XCTAssertTrue(calendar.isDate(back ?? .distantPast, inSameDayAs: thursday))
    }

    func testMonthGridStartsOnMonday() {
        // October 2026 starts on a Thursday → 3 leading blanks.
        let grid = service.monthGrid(for: thursday)
        XCTAssertEqual(grid.prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertNotNil(grid[3])
        XCTAssertEqual(grid.count % 7, 0)
        XCTAssertEqual(grid.compactMap { $0 }.count, 31)
    }

    func testLateEveningStillSameDay() {
        // 23:30 on Thursday is still Thursday (Rest).
        XCTAssertEqual(service.plannedSplit(on: date(2026, 10, 22, hour: 23)), .rest)
        XCTAssertEqual(service.plannedSplit(on: date(2026, 10, 23, hour: 0)), .pull)
    }
}
