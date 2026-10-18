import AppIntents

/// Registers the Siri / Shortcuts / Action Button phrases. Lives in the app target only; the widget shares the intents.
struct HeedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(), phrases: ["Add a task in \(.applicationName)", "New task in \(.applicationName)"],
                    shortTitle: "Add a task", systemImageName: "plus.circle")
        AppShortcut(intent: CompleteTaskIntent(), phrases: ["Complete a task in \(.applicationName)", "Tick off a task in \(.applicationName)"],
                    shortTitle: "Complete a task", systemImageName: "checkmark.circle")
    }
}
