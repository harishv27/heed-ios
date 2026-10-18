import SwiftUI
import SwiftData
import HeedCore

// MARK: - Task row

/// One task in a list: a checkbox, the title, and a line of small facts. Tap to edit, swipe to finish, reschedule or
/// delete, long-press for the rest.
struct TaskRow: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app

    let item: TodoItem
    let lists: [UUID: TodoList]
    /// Show the date in the details line. Today hides it, since every row there is already today.
    var showDate = true
    var showList = true
    /// A repeating task ticked off today. It has already moved to its next date, so it is shown as done and its
    /// checkbox does nothing (ticking it again would skip another occurrence).
    var doneToday = false

    private var showsDone: Bool { item.isCompleted || doneToday }

    var body: some View {
        let today = app.today
        HStack(alignment: .top, spacing: 10) {
            Button { app.toggle(item, in: context) } label: {
                Image(systemName: showsDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(showsDone ? Color.accentColor : Theme.color(for: item.priority))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(doneToday)
            .accessibilityLabel(showsDone ? "Done" : "Mark as done")
            .accessibilityHint(item.title)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .strikethrough(showsDone)
                    .foregroundStyle(showsDone ? .secondary : .primary)
                details(today: today)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 5)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.editing = item }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !doneToday {
                Button { app.toggle(item, in: context) } label: {
                    Label(item.isCompleted ? "Reopen" : "Done", systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { app.trash(item, in: context) } label: { Label("Delete", systemImage: "trash") }
            if !showsDone {
                Button { app.reschedule(item, to: .tomorrow, in: context) } label: { Label("Tomorrow", systemImage: "sunrise") }
                    .tint(.indigo)
            }
        }
        .contextMenu {
            if !showsDone {
                Section("Move to") {
                    ForEach(Reschedule.allCases, id: \.self) { option in
                        Button { app.reschedule(item, to: option, in: context) } label: { Label(option.label, systemImage: option.symbol) }
                    }
                }
            }
            Button { app.editing = item } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { app.trash(item, in: context) } label: { Label("Move to Trash", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func details(today: Int) -> some View {
        let dueText = showDate ? DateText.due(day: item.dueDay, minutes: item.dueMinutes, today: today)
                               : item.dueMinutes.map { DateText.time($0) }
        let overdue = !item.isCompleted && (item.dueDay.map { $0 < today } ?? false)
        let checklist = Checklist.progress(item.checklist)
        let list = showList ? item.listID.flatMap { lists[$0] } : nil
        if dueText != nil || item.recurrence != nil || checklist != nil || list != nil || !item.tags.isEmpty {
            HStack(spacing: 10) {
                if let dueText {
                    Text(dueText).foregroundStyle(overdue ? Color.red : (item.dueDay == today ? Color.accentColor : .secondary))
                }
                if item.recurrence != nil { Image(systemName: "arrow.triangle.2.circlepath").accessibilityLabel("Repeats") }
                if item.reminderLead != nil, item.dueDay != nil { Image(systemName: "bell.fill").accessibilityLabel("Has a reminder") }
                if let checklist {
                    Label("\(checklist.done)/\(checklist.total)", systemImage: "checklist")
                        .labelStyle(.titleAndIcon)
                }
                if let list {
                    HStack(spacing: 4) {
                        Circle().fill(HeedPalette.color(list.colorIndex)).frame(width: 7, height: 7)
                        Text(list.name).lineLimit(1)
                    }
                }
                if !item.tags.isEmpty { Text(item.tags.map { "@\($0)" }.joined(separator: " ")).lineLimit(1) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Floating add button and undo banner

/// The round + button, and above it the Undo banner after a change. Applied to every screen that lists tasks.
struct FloatingChrome: ViewModifier {
    @Environment(AppState.self) private var app
    var list: UUID?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let undo = app.undo {
                    UndoBanner(message: undo.message) { app.performUndo() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack {
                    Spacer()
                    Button { app.quickAdd(list: list) } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(Color.accentColor, in: Circle())
                            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                    }
                    .accessibilityLabel("Add task")
                }
            }
            .padding(.horizontal, Theme.side)
            .padding(.bottom, 10)
            .animation(.snappy, value: app.undo != nil)
        }
    }
}

extension View {
    func floatingChrome(list: UUID? = nil) -> some View { modifier(FloatingChrome(list: list)) }
}

struct UndoBanner: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack {
            Text(message).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 12)
            Button("Undo", action: undo).font(.subheadline.weight(.bold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Chips

struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Lookups

extension Collection where Element == TodoList {
    /// Lists by id. Tolerates duplicate ids, which a merged backup or a sync conflict could in theory produce.
    var byID: [UUID: TodoList] { Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
}

extension Collection where Element == TodoItem {
    var byID: [UUID: TodoItem] { Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
}
