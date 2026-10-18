import Foundation
import SwiftData
import HeedCore

/// Moves tasks between the live store and a backup file. The format and the merge rules live in `HeedCore`; this
/// file only maps SwiftData rows to and from them.
enum BackupService {
    struct ImportResult: Equatable {
        var inserted = 0
        var updated = 0
        var skipped = 0
        var total: Int { inserted + updated + skipped }
    }

    // MARK: Export

    static func makeDocument(from context: ModelContext) -> BackupDocument {
        let items = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let lists = (try? context.fetch(FetchDescriptor<TodoList>())) ?? []
        let filters = (try? context.fetch(FetchDescriptor<SavedFilter>())) ?? []
        return BackupDocument(exportedAt: .now, lists: lists.map(backup), tasks: items.map(backup), filters: filters.map(backup))
    }

    static func export(from context: ModelContext) throws -> Data {
        try BackupCodec.encode(makeDocument(from: context))
    }

    // MARK: Import

    /// Adds what is missing and refreshes what the backup has newer copies of. Never deletes, and never replaces
    /// something edited after the backup was made.
    @discardableResult
    static func restore(_ data: Data, into context: ModelContext) throws -> ImportResult {
        let document = try BackupCodec.decode(data)
        var result = ImportResult()

        let existingLists = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<TodoList>())) ?? []).map { ($0.id, $0) })
        let listPlan = MergePlan.make(existing: existingLists.mapValues(\.modifiedAt), incoming: document.lists)
        for incoming in document.lists {
            if listPlan.insert.contains(incoming.id) {
                let list = TodoList(name: incoming.name, symbol: incoming.symbol, colorIndex: incoming.colorIndex, sortOrder: incoming.sortOrder)
                list.id = incoming.id
                list.modifiedAt = incoming.modifiedAt
                context.insert(list)
            } else if listPlan.update.contains(incoming.id), let list = existingLists[incoming.id] {
                list.name = incoming.name
                list.symbol = incoming.symbol
                list.colorIndex = incoming.colorIndex
                list.sortOrder = incoming.sortOrder
                list.modifiedAt = incoming.modifiedAt
            }
        }

        let existingFilters = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<SavedFilter>())) ?? []).map { ($0.id, $0) })
        let filterPlan = MergePlan.make(existing: existingFilters.mapValues(\.modifiedAt), incoming: document.filters)
        for incoming in document.filters {
            if filterPlan.insert.contains(incoming.id) {
                let filter = SavedFilter(name: incoming.name, symbol: incoming.symbol, filter: incoming.filter, sortOrder: incoming.sortOrder)
                filter.id = incoming.id
                filter.modifiedAt = incoming.modifiedAt
                context.insert(filter)
            } else if filterPlan.update.contains(incoming.id), let filter = existingFilters[incoming.id] {
                filter.name = incoming.name
                filter.symbol = incoming.symbol
                filter.filter = incoming.filter
                filter.sortOrder = incoming.sortOrder
                filter.modifiedAt = incoming.modifiedAt
            }
        }

        let existingItems = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<TodoItem>())) ?? []).map { ($0.id, $0) })
        let plan = MergePlan.make(existing: existingItems.mapValues(\.modifiedAt), incoming: document.tasks)
        for incoming in document.tasks {
            if plan.insert.contains(incoming.id) {
                let item = TodoItem(title: incoming.title)
                item.id = incoming.id
                apply(incoming, to: item)
                context.insert(item)
            } else if plan.update.contains(incoming.id), let item = existingItems[incoming.id] {
                apply(incoming, to: item)
            }
        }
        result.inserted = plan.insert.count
        result.updated = plan.update.count
        result.skipped = plan.skip.count
        TaskActions.commit(context)
        return result
    }

    // MARK: Automatic backups

    struct BackupFile: Identifiable, Equatable {
        var id: URL { url }
        let url: URL
        let date: Date
        let size: Int
    }

    static let keepCount = 14

    static var folder: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Backups", isDirectory: true)
    }

    /// Writes today's backup if there is not one yet and there is something to keep, then trims old ones. Called when
    /// the app comes to the foreground, so it costs one small file a day.
    @discardableResult
    static func runDailyBackup(context: ModelContext, now: Date = .now) -> URL? {
        guard let folder else { return nil }
        let name = "heed-\(now.formatted(.iso8601.year().month().day())).json"
        let url = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return nil }
        let document = makeDocument(from: context)
        guard !document.tasks.isEmpty || !document.lists.isEmpty else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try BackupCodec.encode(document).write(to: url, options: .atomic)
            prune()
            return url
        } catch {
            return nil
        }
    }

    static func files() -> [BackupFile] {
        guard let folder, let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return [] }
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return BackupFile(url: url, date: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
        }.sorted { $0.date > $1.date }
    }

    private static func prune() {
        for old in files().dropFirst(keepCount) { try? FileManager.default.removeItem(at: old.url) }
    }

    // MARK: Mapping

    private static func backup(_ item: TodoItem) -> BackupTask {
        BackupTask(id: item.id, title: item.title, notes: item.notes, dueDay: item.dueDay, dueMinutes: item.dueMinutes,
                   recurrence: item.recurrence, priority: item.priorityRaw, listID: item.listID, tags: item.tags,
                   checklist: item.checklist, reminderLeadMinutes: item.reminderLead, sortOrder: item.sortOrder,
                   timesCompleted: item.timesCompleted, createdAt: item.createdAt, modifiedAt: item.modifiedAt,
                   completedAt: item.completedAt, deletedAt: item.deletedAt, lastDoneAt: item.lastDoneAt)
    }

    private static func backup(_ list: TodoList) -> BackupList {
        BackupList(id: list.id, name: list.name, symbol: list.symbol, colorIndex: list.colorIndex, sortOrder: list.sortOrder,
                   modifiedAt: list.modifiedAt)
    }

    private static func backup(_ filter: SavedFilter) -> BackupFilter {
        BackupFilter(id: filter.id, name: filter.name, symbol: filter.symbol, filter: filter.filter, sortOrder: filter.sortOrder,
                     modifiedAt: filter.modifiedAt)
    }

    private static func apply(_ backup: BackupTask, to item: TodoItem) {
        item.title = backup.title
        item.notes = backup.notes
        item.dueDay = backup.dueDay
        item.dueMinutes = backup.dueMinutes
        item.recurrence = backup.recurrence
        item.priorityRaw = backup.priority
        item.listID = backup.listID
        item.tags = backup.tags
        item.checklist = backup.checklist
        item.reminderLead = backup.reminderLeadMinutes
        item.sortOrder = backup.sortOrder
        item.timesCompleted = backup.timesCompleted
        item.createdAt = backup.createdAt
        item.modifiedAt = backup.modifiedAt
        item.completedAt = backup.completedAt
        item.lastDoneAt = backup.lastDoneAt
        item.deletedAt = backup.deletedAt
    }
}
