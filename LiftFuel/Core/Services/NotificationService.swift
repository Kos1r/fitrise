import Foundation
@preconcurrency import UserNotifications

/// Local notifications: rest timer end, training-day reminders, weekly summary.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let delegate = ForegroundNotificationDelegate()

    enum Identifier {
        static let restTimer = "rest-timer"
        static let trainingReminderPrefix = "training-reminder-"
        static let weeklySummary = "weekly-summary"
    }

    private init() {
        center.delegate = delegate
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: Rest timer

    func scheduleRestTimer(endDate: Date, exerciseName: String) {
        cancelRestTimer()
        let interval = endDate.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest over — next set!")
        content.body = String(localized: "Time for your next set of \(exerciseName).")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Identifier.restTimer, content: content, trigger: trigger))
    }

    func cancelRestTimer() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.restTimer])
        center.removeDeliveredNotifications(withIdentifiers: [Identifier.restTimer])
    }

    // MARK: Training reminders

    /// One repeating reminder per training weekday in the template.
    func scheduleTrainingReminders(template: WeeklyTemplate, hour: Int, minute: Int, enabled: Bool) {
        let ids = (1...7).map { "\(Identifier.trainingReminderPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled else { return }
        for weekday in 1...7 {
            let split = template.split(forWeekday: weekday)
            guard split.isTraining else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(split.dayTitle) today 💪")
            content.body = String(localized: "Your \(split.titleString.lowercased()) workout is ready. Two taps and you're logging.")
            content.sound = .default
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: "\(Identifier.trainingReminderPrefix)\(weekday)", content: content, trigger: trigger))
        }
    }

    // MARK: Weekly summary

    /// Sunday 19:00 nudge to open the weekly summary.
    func scheduleWeeklySummary(enabled: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.weeklySummary])
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your week in review")
        content.body = String(localized: "Workouts, volume, PRs and nutrition — see how this week went.")
        content.sound = .default
        content.userInfo = ["route": "weeklySummary"]
        var components = DateComponents()
        components.weekday = 1
        components.hour = 19
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: Identifier.weeklySummary, content: content, trigger: trigger))
    }
}

/// Shows banners while the app is in the foreground (e.g. rest timer end when the screen is on another tab).
private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.identifier == NotificationService.Identifier.restTimer {
            // The in-app timer already gives haptic + visual feedback.
            return [.sound]
        }
        return [.banner, .sound]
    }
}
