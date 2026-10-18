import Foundation

/// How much a task matters. Stored as its raw value; `none` is the default and sorts last.
public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0, low = 1, medium = 2, high = 3

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Quick-add shorthand: `!1` is the most urgent.
    public var shorthand: String? {
        switch self {
        case .none: return nil
        case .high: return "!1"
        case .medium: return "!2"
        case .low: return "!3"
        }
    }
}
