import Foundation
import Observation

/// Publishes "now" and ticks over at local midnight so every screen rolls to the new day.
@MainActor
@Observable
final class DayClock {
    private(set) var now: Date = .now
    @ObservationIgnored private var midnightTask: Task<Void, Never>?

    var today: Date { Calendar.current.startOfDay(for: now) }

    init() {
        scheduleMidnightTick()
    }

    func refresh() {
        now = .now
        scheduleMidnightTick()
    }

    private func scheduleMidnightTick() {
        midnightTask?.cancel()
        let calendar = Calendar.current
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) else { return }
        let delay = max(1, midnight.timeIntervalSinceNow + 1)
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
