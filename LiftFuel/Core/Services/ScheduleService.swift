import Foundation

/// Weekly Push/Pull/Rest template keyed by Calendar weekday (1 = Sunday … 7 = Saturday).
struct WeeklyTemplate: Equatable, Sendable {
    var days: [Int: SplitDay]

    /// Mon Pull · Tue Push · Wed Rest · Thu Rest · Fri Pull · Sat Push · Sun Rest
    static let `default` = WeeklyTemplate(days: [
        2: .pull,
        3: .push,
        4: .rest,
        5: .rest,
        6: .pull,
        7: .push,
        1: .rest
    ])

    func split(forWeekday weekday: Int) -> SplitDay {
        days[weekday] ?? .rest
    }

    var trainingDaysPerWeek: Int {
        days.values.filter(\.isTraining).count
    }

    /// Weekdays in Monday-first order.
    static let mondayFirstWeekdays = [2, 3, 4, 5, 6, 7, 1]
}

struct PlannedDay: Equatable, Identifiable, Sendable {
    var date: Date
    var split: SplitDay
    var isOverride: Bool

    var id: Date { date }
}

/// Pure schedule logic. Everything is computed from the date passed in, never cached.
struct ScheduleService: Sendable {
    var template: WeeklyTemplate
    /// dayKey → split for one-off changes.
    var overrides: [Int: SplitDay]
    var calendar: Calendar

    init(template: WeeklyTemplate = .default, overrides: [Int: SplitDay] = [:], calendar: Calendar = .current) {
        self.template = template
        self.overrides = overrides
        var cal = calendar
        cal.firstWeekday = 2 // weeks start on Monday
        cal.minimumDaysInFirstWeek = 4
        self.calendar = cal
    }

    // MARK: Day keys

    static func dayKey(for date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    func dayKey(for date: Date) -> Int {
        Self.dayKey(for: date, calendar: calendar)
    }

    func date(fromDayKey key: Int) -> Date? {
        let components = DateComponents(year: key / 10_000, month: (key / 100) % 100, day: key % 100)
        return calendar.date(from: components)
    }

    // MARK: Planning

    func templateSplit(on date: Date) -> SplitDay {
        template.split(forWeekday: calendar.component(.weekday, from: date))
    }

    func plannedSplit(on date: Date) -> SplitDay {
        overrides[dayKey(for: date)] ?? templateSplit(on: date)
    }

    func plannedDay(on date: Date) -> PlannedDay {
        let start = calendar.startOfDay(for: date)
        let key = dayKey(for: start)
        return PlannedDay(date: start, split: overrides[key] ?? templateSplit(on: start), isOverride: overrides[key] != nil)
    }

    /// The `count` days after `date` (not including it).
    func upcoming(after date: Date, count: Int) -> [PlannedDay] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: date)
        return (1...count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map(plannedDay(on:))
        }
    }

    func nextTrainingDay(after date: Date, searchDays: Int = 14) -> PlannedDay? {
        upcoming(after: date, count: searchDays).first { $0.split.isTraining }
    }

    // MARK: Weeks

    /// Monday 00:00 … next Monday 00:00 for the week containing `date`.
    func weekInterval(containing date: Date) -> DateInterval {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return interval
        }
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, duration: 7 * 86_400)
    }

    func daysOfWeek(containing date: Date) -> [PlannedDay] {
        let start = weekInterval(containing: date).start
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map(plannedDay(on:))
        }
    }

    func plannedTrainingDays(inWeekContaining date: Date) -> Int {
        daysOfWeek(containing: date).filter(\.split.isTraining).count
    }

    /// Number of distinct days in the week of `date` with a completed workout.
    func completedDays(inWeekContaining date: Date, completedDayKeys: Set<Int>) -> Int {
        daysOfWeek(containing: date).filter { completedDayKeys.contains(dayKey(for: $0.date)) }.count
    }

    // MARK: Streak

    /// Consecutive planned training days that were completed, walking back from today.
    /// Rest days are skipped, today doesn't break the streak until it's over,
    /// and extra workouts on rest days add to it.
    func streak(completedDayKeys: Set<Int>, today: Date, maxLookbackDays: Int = 730) -> Int {
        var streak = 0
        let todayStart = calendar.startOfDay(for: today)
        for offset in 0..<maxLookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { break }
            let completed = completedDayKeys.contains(dayKey(for: day))
            if completed {
                streak += 1
            } else if offset == 0 || !plannedSplit(on: day).isTraining {
                continue
            } else {
                break
            }
        }
        return streak
    }

    // MARK: Month grid

    /// All dates shown in a Monday-first month grid (leading/trailing days are nil).
    func monthGrid(for month: Date) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// Swap two days' planned splits via overrides; the weekly template is untouched.
    func swapped(_ first: Date, _ second: Date) -> [Int: SplitDay] {
        var result = overrides
        let a = plannedSplit(on: first)
        let b = plannedSplit(on: second)
        result[dayKey(for: first)] = b
        result[dayKey(for: second)] = a
        return result
    }
}
