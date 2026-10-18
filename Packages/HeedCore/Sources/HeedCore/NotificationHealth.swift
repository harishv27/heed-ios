import Foundation

/// What iOS currently allows Heed to do with notifications. A plain copy of the relevant `UNNotificationSettings`,
/// so the checks below can be tested without a device.
public struct NotificationSnapshot: Equatable, Sendable {
    public enum Authorization: Equatable, Sendable { case notDetermined, denied, authorized, provisional }
    public enum Setting: Equatable, Sendable { case enabled, disabled, notSupported }

    public var authorization: Authorization
    public var alerts: Setting
    public var sound: Setting
    public var lockScreen: Setting
    public var notificationCenter: Setting
    /// Reminders currently pending with iOS.
    public var pendingCount: Int
    /// Reminders planned but held back by the system cap.
    public var deferredCount: Int

    public init(authorization: Authorization, alerts: Setting = .enabled, sound: Setting = .enabled,
                lockScreen: Setting = .enabled, notificationCenter: Setting = .enabled, pendingCount: Int = 0,
                deferredCount: Int = 0) {
        self.authorization = authorization
        self.alerts = alerts
        self.sound = sound
        self.lockScreen = lockScreen
        self.notificationCenter = notificationCenter
        self.pendingCount = pendingCount
        self.deferredCount = deferredCount
    }
}

public struct HealthIssue: Equatable, Identifiable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case info = 0, warning = 1, problem = 2
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Fix: Equatable, Sendable {
        /// Nothing the app can do; the user changes it in Settings.
        case openSettings
        /// The permission prompt has not been shown yet.
        case askPermission
        case none
    }

    public var id: String
    public var severity: Severity
    public var title: String
    public var detail: String
    public var fix: Fix
}

/// Looks at the notification settings and says, in plain words, why a reminder might not show up.
public enum NotificationHealth {
    /// Problems first, then warnings, then notes. Empty means reminders should arrive as expected.
    public static func evaluate(_ snapshot: NotificationSnapshot) -> [HealthIssue] {
        var issues: [HealthIssue] = []

        switch snapshot.authorization {
        case .notDetermined:
            issues.append(HealthIssue(id: "not-asked", severity: .problem, title: "Heed hasn't been allowed to notify you",
                                      detail: "Reminders can't appear until you allow notifications.", fix: .askPermission))
        case .denied:
            issues.append(HealthIssue(id: "denied", severity: .problem, title: "Notifications are turned off for Heed",
                                      detail: "Reminders are saved, but iOS won't show them. Turn on Allow Notifications in Settings.",
                                      fix: .openSettings))
        case .provisional:
            issues.append(HealthIssue(id: "quiet", severity: .warning, title: "Reminders are delivered quietly",
                                      detail: "They land in Notification Center without a banner or sound. Turn on banners in Settings to be alerted.",
                                      fix: .openSettings))
        case .authorized:
            break
        }

        if snapshot.authorization == .authorized || snapshot.authorization == .provisional {
            if snapshot.alerts == .disabled {
                issues.append(HealthIssue(id: "no-alerts", severity: .problem, title: "Alerts are switched off",
                                          detail: "Notifications are allowed but nothing is shown on screen. Choose a banner style in Settings.",
                                          fix: .openSettings))
            }
            if snapshot.lockScreen == .disabled {
                issues.append(HealthIssue(id: "no-lock-screen", severity: .warning, title: "Not shown on the Lock Screen",
                                          detail: "You won't see reminders when your phone is locked.", fix: .openSettings))
            }
            if snapshot.notificationCenter == .disabled {
                issues.append(HealthIssue(id: "no-center", severity: .warning, title: "Not kept in Notification Center",
                                          detail: "A reminder you miss won't wait for you there.", fix: .openSettings))
            }
            if snapshot.sound == .disabled {
                issues.append(HealthIssue(id: "no-sound", severity: .info, title: "Sound is off",
                                          detail: "Reminders arrive silently.", fix: .openSettings))
            }
        }

        if snapshot.deferredCount > 0 {
            issues.append(HealthIssue(id: "cap", severity: .info,
                                      title: "\(snapshot.deferredCount) later reminders are waiting",
                                      detail: "iOS holds \(ReminderPlanner.systemLimit) at a time. Heed schedules the rest automatically as they get closer.",
                                      fix: .none))
        }

        return issues.sorted { $0.severity > $1.severity }
    }

    /// True when there is nothing worse than a note.
    public static func isHealthy(_ issues: [HealthIssue]) -> Bool {
        !issues.contains { $0.severity >= .warning }
    }
}
