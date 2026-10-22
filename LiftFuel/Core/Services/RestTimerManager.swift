import ActivityKit
import Foundation
import Observation

/// Rest timer that survives backgrounding: the end date is absolute, a local
/// notification fires at the end, and a Live Activity shows the countdown.
@MainActor
@Observable
final class RestTimerManager {
    private(set) var endDate: Date?
    private(set) var totalSeconds: Int = 0
    private(set) var exerciseName: String = ""
    private(set) var nextSetDescription: String = ""
    /// Bumped every time a timer finishes, so views can trigger haptics/animations.
    private(set) var finishedCount = 0

    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var activity: Activity<RestTimerAttributes>?

    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date = .now) -> TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - remaining(at: date) / Double(totalSeconds)
    }

    func start(seconds: Int, exerciseName: String, nextSet: String) {
        guard seconds > 0 else { return }
        let end = Date.now.addingTimeInterval(TimeInterval(seconds))
        self.endDate = end
        self.totalSeconds = seconds
        self.exerciseName = exerciseName
        self.nextSetDescription = nextSet
        scheduleFinish()
        NotificationService.shared.scheduleRestTimer(endDate: end, exerciseName: exerciseName)
        startOrUpdateActivity()
    }

    /// Adds (or with a negative value removes) time from the running timer.
    func adjust(by seconds: Int) {
        guard let endDate else { return }
        let newEnd = endDate.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > .now else {
            skip()
            return
        }
        self.endDate = newEnd
        totalSeconds = max(1, totalSeconds + seconds)
        scheduleFinish()
        NotificationService.shared.scheduleRestTimer(endDate: newEnd, exerciseName: exerciseName)
        startOrUpdateActivity()
    }

    func skip() {
        finishTask?.cancel()
        finishTask = nil
        endDate = nil
        NotificationService.shared.cancelRestTimer()
        endActivity()
    }

    /// Called when returning to the foreground: completes a timer that ran out in the background.
    func refresh() {
        guard let endDate else { return }
        if endDate <= .now {
            complete(withHaptics: false)
        } else {
            scheduleFinish()
        }
    }

    private func scheduleFinish() {
        finishTask?.cancel()
        let delay = remaining()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.complete(withHaptics: true)
        }
    }

    private func complete(withHaptics: Bool) {
        finishTask = nil
        endDate = nil
        finishedCount += 1
        if withHaptics {
            Haptics.success()
        }
        endActivity()
    }

    // MARK: Live Activity

    private func startOrUpdateActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let endDate else { return }
        let state = RestTimerAttributes.ContentState(endDate: endDate, totalSeconds: totalSeconds, nextSetDescription: nextSetDescription)
        let content = ActivityContent(state: state, staleDate: endDate.addingTimeInterval(60))
        if let activity {
            Task { await activity.update(content) }
        } else {
            do {
                activity = try Activity.request(
                    attributes: RestTimerAttributes(exerciseName: exerciseName),
                    content: content,
                    pushType: nil
                )
            } catch {
                activity = nil
            }
        }
    }

    private func endActivity() {
        guard let current = activity else { return }
        activity = nil
        let state = RestTimerAttributes.ContentState(endDate: .now, totalSeconds: totalSeconds, nextSetDescription: nextSetDescription)
        Task {
            await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
