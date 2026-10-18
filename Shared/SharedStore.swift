import Foundation
import SwiftData
import SwiftUI
import WidgetKit
import HeedCore

/// The one SwiftData store, kept in an App Group container so the app, the widget and Shortcuts all read and write
/// the same tasks.
enum SharedStore {
    static let appGroup = "group.com.harishv27.heed"
    static let cloudContainer = "iCloud.com.harishv27.heed"

    static let schema = Schema([TodoItem.self, TodoList.self, SavedFilter.self])

    /// Why the real store could not be opened, or nil when all is well.
    private(set) static var openError: String?

    static let container: ModelContainer = {
        #if HEED_ICLOUD
        let configuration = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup),
                                               cloudKitDatabase: .private(cloudContainer))
        #else
        let configuration = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup), cloudKitDatabase: .none)
        #endif
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Never crash on launch and never overwrite what is on disk: fall back to an empty in-memory store, tell
            // the user, and leave the real file untouched so a fixed version can still open it.
            openError = "\(error.localizedDescription)"
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }()

    /// A fresh context for work outside the main view hierarchy (widget buttons, Shortcuts, notification actions).
    static func makeContext() -> ModelContext { ModelContext(container) }

    static func reloadWidgets() { WidgetCenter.shared.reloadAllTimelines() }

    /// Settings shared with the widget and intents.
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
}

enum Preferences {
    private static let reminderTimeKey = "defaultReminderMinutes"

    /// Minutes after midnight for reminders on tasks that only have a date. 9:00 by default.
    static var defaultReminderMinutes: Int {
        get { SharedStore.defaults.object(forKey: reminderTimeKey) as? Int ?? 9 * 60 }
        set { SharedStore.defaults.set(newValue, forKey: reminderTimeKey) }
    }
}

/// Colours for lists, shared so the widget can draw them too.
enum HeedPalette {
    static let colors: [Color] = [.indigo, .blue, .teal, .green, .orange, .red, .pink, .purple]
    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
}

/// Short human text for days and times.
enum DateText {
    static func day(_ key: Int, today: Int, calendar: Calendar = .current) -> String {
        switch key - today {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return Day.date(for: key, calendar: calendar).formatted(.dateTime.weekday(.wide))
        default:
            let date = Day.date(for: key, calendar: calendar)
            let sameYear = Day.ymd(key).year == Day.ymd(today).year
            return sameYear ? date.formatted(.dateTime.day().month(.abbreviated))
                            : date.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    static func time(_ minutes: Int, calendar: Calendar = .current) -> String {
        let midnight = calendar.startOfDay(for: .now)
        let date = calendar.date(byAdding: .minute, value: minutes, to: midnight) ?? midnight
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "Today, 6:00 PM", "Fri", "Oct 25".
    static func due(day: Int?, minutes: Int?, today: Int) -> String? {
        guard let day else { return minutes.map { time($0) } }
        let label = Self.day(day, today: today)
        return minutes.map { "\(label), \(time($0))" } ?? label
    }
}
