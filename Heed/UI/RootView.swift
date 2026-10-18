import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @State private var storeProblem: String? = SharedStore.container.isFallback ? SharedStore.openError : nil

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            UpcomingView()
                .tabItem { Label("Upcoming", systemImage: "calendar") }
                .tag(AppTab.upcoming)
            ListsView()
                .tabItem { Label("Lists", systemImage: "list.bullet") }
                .tag(AppTab.lists)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .sheet(isPresented: $app.showQuickAdd) { QuickAddSheet().presentationDetents([.medium, .large]) }
        .sheet(item: $app.editing) { item in TaskDetailView(item: item) }
        .sheet(isPresented: $app.showTriage) { TriageSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .heedOpenTask)) { note in
            guard let idString = note.object as? String, let id = UUID(uuidString: idString),
                  let item = try? context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })).first else { return }
            app.editing = item
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            app.refreshDay()
        }
        .alert("Heed couldn't open its data", isPresented: Binding(get: { storeProblem != nil }, set: { if !$0 { storeProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your tasks have not been touched. Heed is running with an empty, temporary list until it can open them, so anything you add now will not be kept. Update the app or restart your phone, then try again.\n\n\(storeProblem ?? "")")
        }
    }
}

private extension ModelContainer {
    /// True when this is the temporary fallback store rather than the real one.
    var isFallback: Bool { configurations.contains { $0.isStoredInMemoryOnly } }
}
