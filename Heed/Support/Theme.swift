import SwiftUI
import UIKit
import HeedCore

/// Colours and the few shared building blocks. Everything is semantic, so dark mode needs no special cases.
enum Theme {
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let line = Color(.separator).opacity(0.5)
    static let side: CGFloat = 20

    static func color(for priority: Priority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return Color(.tertiaryLabel)
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

extension Date {
    /// "Wednesday, 14 October".
    var longDay: String { formatted(.dateTime.weekday(.wide).day().month(.wide)) }
}

extension Notification.Name {
    /// Posted when a notification is tapped; the object is the task's id string.
    static let heedOpenTask = Notification.Name("heed.openTask")
}
