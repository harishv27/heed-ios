import Foundation

/// Anything that can be matched up between a backup and the live store.
public protocol Mergeable {
    var id: UUID { get }
    var modifiedAt: Date { get }
}

public struct BackupTask: Codable, Equatable, Identifiable, Mergeable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var dueDay: Int?
    public var dueMinutes: Int?
    public var recurrence: Recurrence?
    public var priority: Int
    public var listID: UUID?
    public var tags: [String]
    public var checklist: [ChecklistItem]
    public var reminderLeadMinutes: Int?
    public var sortOrder: Int
    public var timesCompleted: Int
    public var createdAt: Date
    public var modifiedAt: Date
    public var completedAt: Date?
    public var deletedAt: Date?
    public var lastDoneAt: Date?

    public init(id: UUID, title: String, notes: String = "", dueDay: Int? = nil, dueMinutes: Int? = nil,
                recurrence: Recurrence? = nil, priority: Int = 0, listID: UUID? = nil, tags: [String] = [],
                checklist: [ChecklistItem] = [], reminderLeadMinutes: Int? = nil, sortOrder: Int = 0,
                timesCompleted: Int = 0, createdAt: Date, modifiedAt: Date, completedAt: Date? = nil, deletedAt: Date? = nil,
                lastDoneAt: Date? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDay = dueDay
        self.dueMinutes = dueMinutes
        self.recurrence = recurrence
        self.priority = priority
        self.listID = listID
        self.tags = tags
        self.checklist = checklist
        self.reminderLeadMinutes = reminderLeadMinutes
        self.sortOrder = sortOrder
        self.timesCompleted = timesCompleted
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.lastDoneAt = lastDoneAt
    }
}

public struct BackupList: Codable, Equatable, Identifiable, Mergeable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var colorIndex: Int
    public var sortOrder: Int
    public var modifiedAt: Date

    public init(id: UUID, name: String, symbol: String, colorIndex: Int, sortOrder: Int, modifiedAt: Date) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.sortOrder = sortOrder
        self.modifiedAt = modifiedAt
    }
}

public struct BackupFilter: Codable, Equatable, Identifiable, Mergeable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var filter: TaskFilter
    public var sortOrder: Int
    public var modifiedAt: Date

    public init(id: UUID, name: String, symbol: String, filter: TaskFilter, sortOrder: Int, modifiedAt: Date) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.filter = filter
        self.sortOrder = sortOrder
        self.modifiedAt = modifiedAt
    }
}

/// Everything Heed knows, as one readable JSON file you can keep anywhere.
public struct BackupDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var app: String
    public var version: Int
    public var exportedAt: Date
    public var lists: [BackupList]
    public var tasks: [BackupTask]
    public var filters: [BackupFilter]

    public init(exportedAt: Date, lists: [BackupList], tasks: [BackupTask], filters: [BackupFilter] = []) {
        self.app = "Heed"
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.lists = lists
        self.tasks = tasks
        self.filters = filters
    }
}

public enum BackupError: Error, Equatable, LocalizedError {
    case notABackup
    case newerThanThisApp(version: Int)

    public var errorDescription: String? {
        switch self {
        case .notABackup: return "This file isn't a Heed backup."
        case .newerThanThisApp(let version):
            return "This backup was made by a newer version of Heed (format \(version)). Update Heed to open it."
        }
    }
}

public enum BackupCodec {
    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Reads a backup, refusing files that are not Heed's or that a newer Heed wrote.
    public static func decode(_ data: Data) throws -> BackupDocument {
        struct Header: Decodable { let app: String?; let version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.app == "Heed",
              let version = header.version else { throw BackupError.notABackup }
        guard version <= BackupDocument.currentVersion else { throw BackupError.newerThanThisApp(version: version) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(BackupDocument.self, from: data) } catch { throw BackupError.notABackup }
    }
}

/// Importing is additive and never destructive: a backup can add what is missing and refresh what it has newer
/// copies of, but it can never overwrite something edited since the backup was made, and it never deletes.
public struct MergePlan: Equatable, Sendable {
    public var insert: [UUID]
    public var update: [UUID]
    public var skip: [UUID]

    public static func make<Item: Mergeable>(existing: [UUID: Date], incoming: [Item]) -> MergePlan {
        var plan = MergePlan(insert: [], update: [], skip: [])
        for item in incoming {
            if let current = existing[item.id] {
                if item.modifiedAt > current { plan.update.append(item.id) } else { plan.skip.append(item.id) }
            } else {
                plan.insert.append(item.id)
            }
        }
        return plan
    }
}
