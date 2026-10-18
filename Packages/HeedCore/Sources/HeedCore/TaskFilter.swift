import Foundation

/// A saved view over the tasks, such as "work, but not waiting-on, high priority, due this week". Free and unlimited:
/// filters are just data, and `matches` is plain logic.
public struct TaskFilter: Codable, Equatable, Hashable, Sendable {
    public enum Due: String, Codable, CaseIterable, Sendable {
        case any, hasDate, noDate, overdue, today, todayOrOverdue, next7Days, next30Days

        public var label: String {
            switch self {
            case .any: return "Any time"
            case .hasDate: return "Has a date"
            case .noDate: return "No date"
            case .overdue: return "Overdue"
            case .today: return "Today"
            case .todayOrOverdue: return "Today or overdue"
            case .next7Days: return "Next 7 days"
            case .next30Days: return "Next 30 days"
            }
        }
    }

    /// Match tasks in any of these lists. Empty means every list.
    public var listIDs: Set<UUID>
    /// Match tasks with at least one of these tags (case-insensitive). Empty means no tag requirement.
    public var anyTags: Set<String>
    /// Exclude tasks carrying any of these tags.
    public var excludedTags: Set<String>
    public var minimumPriority: Priority
    public var due: Due
    public var text: String
    public var includeCompleted: Bool

    public init(listIDs: Set<UUID> = [], anyTags: Set<String> = [], excludedTags: Set<String> = [],
                minimumPriority: Priority = .none, due: Due = .any, text: String = "", includeCompleted: Bool = false) {
        self.listIDs = listIDs
        self.anyTags = Set(anyTags.map { $0.lowercased() })
        self.excludedTags = Set(excludedTags.map { $0.lowercased() })
        self.minimumPriority = minimumPriority
        self.due = due
        self.text = text
        self.includeCompleted = includeCompleted
    }

    public func matches(_ task: TaskSummary, today: Int) -> Bool {
        if task.isCompleted && !includeCompleted { return false }
        if !listIDs.isEmpty {
            guard let list = task.listID, listIDs.contains(list) else { return false }
        }
        let tags = Set(task.tags.map { $0.lowercased() })
        if !anyTags.isEmpty, tags.isDisjoint(with: anyTags) { return false }
        if !excludedTags.isEmpty, !tags.isDisjoint(with: excludedTags) { return false }
        if task.priority < minimumPriority { return false }
        if !text.isEmpty, !Planning.matches(task, query: text) { return false }

        switch due {
        case .any: return true
        case .hasDate: return task.dueDay != nil
        case .noDate: return task.dueDay == nil
        case .overdue: return task.dueDay.map { $0 < today } ?? false
        case .today: return task.dueDay == today
        case .todayOrOverdue: return task.dueDay.map { $0 <= today } ?? false
        case .next7Days: return task.dueDay.map { $0 >= today && $0 < today + 7 } ?? false
        case .next30Days: return task.dueDay.map { $0 >= today && $0 < today + 30 } ?? false
        }
    }

    /// True when the filter would match everything open, i.e. nothing has been set yet.
    public var isEmpty: Bool {
        listIDs.isEmpty && anyTags.isEmpty && excludedTags.isEmpty && minimumPriority == .none && due == .any
            && text.isEmpty && !includeCompleted
    }

    public var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    public static func decode(_ data: Data) -> TaskFilter {
        (try? JSONDecoder().decode(TaskFilter.self, from: data)) ?? TaskFilter()
    }

    /// Ready-made filters shown to everyone.
    public struct Preset: Identifiable, Sendable {
        public var id: String { name }
        public let name: String
        public let symbol: String
        public let filter: TaskFilter
    }

    public static let presets: [Preset] = [
        Preset(name: "High priority", symbol: "flag.fill", filter: TaskFilter(minimumPriority: .high)),
        Preset(name: "Next 7 days", symbol: "calendar", filter: TaskFilter(due: .next7Days)),
        Preset(name: "No date", symbol: "tray", filter: TaskFilter(due: .noDate)),
        Preset(name: "Overdue", symbol: "exclamationmark.circle", filter: TaskFilter(due: .overdue)),
    ]
}
