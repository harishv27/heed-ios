import SwiftUI
import SwiftData
import UserNotifications

@main
struct HeedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .modelContainer(SharedStore.container)
                .task { await DemoData.seedIfRequested(SharedStore.container) }
                .onOpenURL { url in
                    // heed://add opens quick-add; the widget's + button uses it.
                    if url.host == "add" { appState.quickAdd() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appState.refreshDay()
            Task { @MainActor in
                let context = SharedStore.container.mainContext
                TaskActions.purgeExpiredTrash(in: context)
                BackupService.runDailyBackup(context: context)
                SharedStore.reloadWidgets()
                await Reminders.syncAll()
            }
        }
    }
}

/// Handles notification buttons. The Done and Snooze buttons work from the lock screen without opening the app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let idString = response.notification.request.content.userInfo["taskID"] as? String,
              let id = UUID(uuidString: idString) else { return }
        let title = response.notification.request.content.title

        switch response.actionIdentifier {
        case Reminders.doneAction:
            let context = SharedStore.makeContext()
            if let item = try? context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })).first, !item.isCompleted {
                TaskActions.complete(item, in: context)
            }
        case Reminders.snoozeAction:
            await Reminders.snooze(taskID: idString, title: title)
        case UNNotificationDefaultActionIdentifier:
            await MainActor.run { NotificationCenter.default.post(name: .heedOpenTask, object: idString) }
        default:
            break
        }
    }
}
