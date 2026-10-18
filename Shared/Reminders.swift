import Foundation
import SwiftData
import UserNotifications
import HeedCore

/// Turns the plan from `ReminderPlanner` into real notifications, and keeps them in step with the tasks.
///
/// The rule: never clear everything and re-add. Heed asks the planner what should be pending, compares that with what
/// is pending, and only adds the missing ones and removes the stale ones. There is no moment with nothing scheduled,
/// and running it twice (the app and a widget button at the same time) is harmless because identifiers are stable.
enum Reminders {
    static let categoryID = "heed.task"
    static let doneAction = "heed.done"
    static let snoozeAction = "heed.snooze"
    static let snoozePrefix = "heed.snooze."
    static let testID = "heed.test"

    private static let deferredKey = "reminders.deferred"
    private static let lastSyncKey = "reminders.lastSync"

    // MARK: Permission

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Asks the first time a reminder is actually wanted, instead of on launch before the user has seen anything.
    static func requestAuthorizationIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined { await requestAuthorization() }
    }

    /// Done / Snooze buttons on the notification itself.
    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze 1 hour", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [done, snooze], intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: Syncing

    static func syncAll(now: Date = .now) async {
        let context = SharedStore.makeContext()
        let open = (try? context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.deletedAt == nil && $0.completedAt == nil }))) ?? []
        let plan = ReminderPlanner.plan(open.map(\.reminderSource), now: now, calendar: .current,
                                        defaultMinutes: Preferences.defaultReminderMinutes)
        SharedStore.defaults.set(plan.deferred, forKey: deferredKey)

        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let pending = await center.pendingNotificationRequests().map(\.identifier).filter(ReminderPlanner.isTaskReminder)
        let diff = plan.diff(existing: Set(pending))
        if !diff.remove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: diff.remove) }
        for reminder in diff.add {
            try? await center.add(request(for: reminder))
        }
        SharedStore.defaults.set(now, forKey: lastSyncKey)
    }

    private static func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = body(for: reminder)
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = "heed.tasks"
        content.userInfo = ["taskID": reminder.taskID.uuidString]
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.components, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }

    /// Worded relative to the day the reminder fires, so a "1 day before" reminder says "Due tomorrow".
    private static func body(for reminder: PlannedReminder) -> String {
        if reminder.leadMinutes == 0 { return reminder.dueMinutes != nil ? "Due now" : "Due today" }
        let when = DateText.due(day: reminder.dueDay, minutes: reminder.dueMinutes, today: Day.key(for: reminder.fire)) ?? "soon"
        return "Due \(when.lowercasedFirst)"
    }

    // MARK: Test and health

    /// A reminder five seconds from now, to prove the whole path works on this phone.
    static func scheduleTest() async {
        let content = UNMutableNotificationContent()
        content.title = "Heed test reminder"
        content.body = "If you can see this, reminders will reach you."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: testID, content: content, trigger: trigger))
    }

    /// Pushes a reminder for `item` back by an hour without touching the task itself.
    static func snooze(taskID: String, title: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Snoozed reminder"
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["taskID": taskID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: snoozePrefix + taskID, content: content, trigger: trigger))
    }

    static func snapshot() async -> NotificationSnapshot {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests().filter { ReminderPlanner.isTaskReminder($0.identifier) }.count

        func map(_ value: UNNotificationSetting) -> NotificationSnapshot.Setting {
            switch value {
            case .enabled: return .enabled
            case .disabled: return .disabled
            default: return .notSupported
            }
        }
        let authorization: NotificationSnapshot.Authorization
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: authorization = .authorized
        case .provisional: authorization = .provisional
        case .denied: authorization = .denied
        default: authorization = .notDetermined
        }
        return NotificationSnapshot(authorization: authorization, alerts: map(settings.alertSetting), sound: map(settings.soundSetting),
                                    lockScreen: map(settings.lockScreenSetting),
                                    notificationCenter: map(settings.notificationCenterSetting), pendingCount: pending,
                                    deferredCount: SharedStore.defaults.integer(forKey: deferredKey))
    }

    static var lastSync: Date? { SharedStore.defaults.object(forKey: lastSyncKey) as? Date }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
