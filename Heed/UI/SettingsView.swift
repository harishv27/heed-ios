import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HeedCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TodoItem> { $0.deletedAt != nil }) private var trashed: [TodoItem]
    @State private var reminderMinutes = Preferences.defaultReminderMinutes
    @State private var issues: [HealthIssue]?
    @State private var exportDocument: BackupFileDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date-only reminders at", selection: reminderTime, displayedComponents: .hourAndMinute)
                    NavigationLink { ReminderHealthView() } label: {
                        HStack {
                            Label("Reminder health", systemImage: "bell.badge")
                            Spacer()
                            healthBadge
                        }
                    }
                } header: { Text("Reminders") } footer: {
                    Text("Tasks that have a date but no time are reminded at this time of day.")
                }

                Section {
                    NavigationLink { TrashView() } label: {
                        HStack {
                            Label("Trash", systemImage: "trash")
                            Spacer()
                            if !trashed.isEmpty { Text("\(trashed.count)").foregroundStyle(.secondary) }
                        }
                    }
                    Button { exportBackup() } label: { Label("Export a backup", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Restore from a backup", systemImage: "square.and.arrow.down") }
                    NavigationLink { AutoBackupsView() } label: { Label("Automatic backups", systemImage: "clock.arrow.circlepath") }
                } header: { Text("Your data") } footer: {
                    Text("Heed saves a backup of everything once a day and keeps the last \(BackupService.keepCount). Deleted tasks stay in the Trash for \(Trash.retentionDays) days. Restoring never overwrites newer edits.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Sync") {
                        #if HEED_ICLOUD
                        Text("iCloud").foregroundStyle(.secondary)
                        #else
                        Text("This iPhone only").foregroundStyle(.secondary)
                        #endif
                    }
                    Text("No account, no ads, no tracking. Your tasks never leave this phone unless you export them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { await refreshHealth() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshHealth() } } }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                          defaultFilename: "Heed backup \(Date.now.formatted(.iso8601.year().month().day()))") { result in
                if case .failure(let error) = result { message = "The backup could not be saved: \(error.localizedDescription)" }
                else { message = "Backup saved." }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): restore(from: url)
                case .failure(let error): message = "The file could not be opened: \(error.localizedDescription)"
                }
            }
            .alert("Heed", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    // MARK: Reminders

    private var reminderTime: Binding<Date> {
        Binding(get: { Day.date(for: TaskActions.today, minutes: reminderMinutes) }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            Preferences.defaultReminderMinutes = reminderMinutes
            Task { await Reminders.syncAll() }
        })
    }

    @ViewBuilder
    private var healthBadge: some View {
        if let issues {
            if NotificationHealth.isHealthy(issues) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("All good")
            } else {
                let count = issues.filter { $0.severity >= .warning }.count
                Label("\(count)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(count) things need attention")
            }
        }
    }

    private func refreshHealth() async {
        issues = NotificationHealth.evaluate(await Reminders.snapshot())
    }

    // MARK: Backup

    private func exportBackup() {
        do {
            exportDocument = BackupFileDocument(data: try BackupService.export(from: context))
            exporting = true
        } catch {
            message = "The backup could not be created: \(error.localizedDescription)"
        }
    }

    private func restore(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let result = try BackupService.restore(data, into: context)
            message = "Added \(result.inserted), updated \(result.updated), kept \(result.skipped) as they were (already as new or newer)."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// A JSON file for `fileExporter`.
struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// MARK: - Reminder health

struct ReminderHealthView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: NotificationSnapshot?
    @State private var issues: [HealthIssue] = []
    @State private var testSent = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(healthy ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot == nil ? "Checking…" : (healthy ? "Reminders should arrive" : "Something may stop reminders")).font(.headline)
                        Text(healthy ? "iOS is allowing Heed to alert you." : "Fix the items below and reminders will start showing up.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !issues.isEmpty {
                Section("Checks") {
                    ForEach(issues) { issue in issueRow(issue) }
                }
            }

            if let snapshot {
                Section("Status") {
                    LabeledContent("Scheduled with iOS", value: "\(snapshot.pendingCount) of \(ReminderPlanner.systemLimit)")
                    if snapshot.deferredCount > 0 { LabeledContent("Waiting their turn", value: "\(snapshot.deferredCount)") }
                    if let last = Reminders.lastSync { LabeledContent("Last planned", value: last.formatted(date: .omitted, time: .shortened)) }
                }
            }

            Section {
                Button {
                    Task {
                        await Reminders.scheduleTest()
                        testSent = true
                    }
                } label: { Label("Send a test reminder", systemImage: "bell.and.waves.left.and.right") }
                .disabled(snapshot?.authorization == .denied)
                Button {
                    Task {
                        await Reminders.syncAll()
                        await load()
                    }
                } label: { Label("Plan reminders again", systemImage: "arrow.triangle.2.circlepath") }
            } header: { Text("Try it") } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if testSent { Text("Sent. It arrives in 5 seconds. Lock your phone to check the Lock Screen too.").foregroundStyle(.green) }
                    Text("If you use a Focus (Do Not Disturb, Work, Sleep), allow Heed under Settings ▸ Focus ▸ Apps, or its reminders will wait quietly.")
                }
            }
        }
        .navigationTitle("Reminder health")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }

    private var healthy: Bool { snapshot != nil && NotificationHealth.isHealthy(issues) }

    private func issueRow(_ issue: HealthIssue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.severity == .problem ? "xmark.octagon.fill" : (issue.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                .foregroundStyle(issue.severity == .problem ? .red : (issue.severity == .warning ? .orange : .blue))
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title).font(.subheadline.weight(.semibold))
                Text(issue.detail).font(.footnote).foregroundStyle(.secondary)
                switch issue.fix {
                case .openSettings:
                    Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                        .font(.footnote.weight(.semibold))
                case .askPermission:
                    Button("Allow notifications") { Task { await Reminders.requestAuthorization(); await Reminders.syncAll(); await load() } }
                        .font(.footnote.weight(.semibold))
                case .none:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        let current = await Reminders.snapshot()
        snapshot = current
        issues = NotificationHealth.evaluate(current)
    }
}

// MARK: - Trash

struct TrashView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TodoItem> { $0.deletedAt != nil }, sort: [SortDescriptor(\TodoItem.deletedAt, order: .reverse)]) private var trashed: [TodoItem]
    @State private var confirmEmpty = false

    var body: some View {
        List {
            if trashed.isEmpty {
                ContentUnavailableView("Trash is empty", systemImage: "trash",
                                       description: Text("Deleted tasks wait here for \(Trash.retentionDays) days, then go for good."))
                    .listRowBackground(Color.clear)
            }
            ForEach(trashed) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                    if let deletedAt = item.deletedAt {
                        let days = Trash.daysLeft(deletedAt: deletedAt)
                        Text(days == 0 ? "Goes today" : "\(days) \(days == 1 ? "day" : "days") left")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { TaskActions.restore(item, in: context) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }.tint(.green)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { TaskActions.deleteForever([item], in: context) } label: { Label("Delete for good", systemImage: "trash.slash") }
                }
            }
        }
        .navigationTitle("Trash")
        .toolbar {
            if !trashed.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Empty") { confirmEmpty = true } }
            }
        }
        .confirmationDialog("Delete \(trashed.count) \(trashed.count == 1 ? "task" : "tasks") for good?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { TaskActions.deleteForever(trashed, in: context) }
        } message: { Text("This can't be undone. Restore anything you still want first (swipe right).") }
    }
}

// MARK: - Automatic backups

struct AutoBackupsView: View {
    @Environment(\.modelContext) private var context
    @State private var files = BackupService.files()
    @State private var message: String?

    var body: some View {
        List {
            if files.isEmpty {
                ContentUnavailableView("No backups yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("The first one is saved the next time you open Heed with tasks in it."))
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(files) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.date.formatted(date: .abbreviated, time: .shortened))
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { restore(file) }.buttonStyle(.bordered)
                    }
                }
            } footer: {
                Text("Also visible in the Files app under On My iPhone ▸ Heed ▸ Backups. Restoring adds what is missing and never replaces newer edits.")
            }
        }
        .navigationTitle("Automatic backups")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Heed", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func restore(_ file: BackupService.BackupFile) {
        do {
            let result = try BackupService.restore(Data(contentsOf: file.url), into: context)
            message = "Added \(result.inserted), updated \(result.updated), kept \(result.skipped) as they were."
        } catch {
            message = error.localizedDescription
        }
    }
}
