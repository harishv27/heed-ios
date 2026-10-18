import SwiftUI
import SwiftData
import HeedCore

/// Type a sentence, see what Heed understood, press return. The parsing runs on the device as you type.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: [SortDescriptor(\TodoList.sortOrder)]) private var lists: [TodoList]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = QuickAddParser.parse(text)
        let defaultList = app.quickAddList.flatMap { id in lists.first { $0.id == id } }

        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // A wrapping field, so a long sentence stays readable. Return finishes it, same as the Add button.
                TextField("What needs doing?", text: $text, axis: .vertical)
                    .font(.title3)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { add(parsed) }
                    .onChange(of: text) { _, new in
                        guard new.contains("\n") else { return }
                        text = new.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                        add(QuickAddParser.parse(text))
                    }

                preview(parsed, defaultList: defaultList)

                Divider()
                suggestions
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.side)
            .padding(.top, 8)
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add(parsed) }.fontWeight(.semibold).disabled(parsed.title.isEmpty)
                }
            }
        }
        .onAppear {
            text = app.quickAddText
            focused = true
        }
    }

    // MARK: Preview

    @ViewBuilder
    private func preview(_ parsed: ParsedTask, defaultList: TodoList?) -> some View {
        let today = app.today
        let existing = parsed.listName.flatMap { name in lists.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        let hasChips = parsed.hasDetails || defaultList != nil

        if hasChips {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let day = parsed.dueDay {
                        Chip(text: DateText.day(day, today: today) + (day - today >= 7 || day < today ? "" : ", " + Day.date(for: day).formatted(.dateTime.day().month(.abbreviated))),
                             symbol: "calendar", tint: day < today ? .red : .accentColor)
                    }
                    if let minutes = parsed.minutes { Chip(text: DateText.time(minutes), symbol: "clock") }
                    if let rule = parsed.recurrence { Chip(text: rule.summary(), symbol: "arrow.triangle.2.circlepath", tint: .teal) }
                    if parsed.priority != .none { Chip(text: parsed.priority.label, symbol: "flag.fill", tint: Theme.color(for: parsed.priority)) }
                    if let name = parsed.listName {
                        Chip(text: existing == nil ? "New list: \(name)" : (existing?.name ?? name), symbol: existing?.symbol ?? "plus.circle",
                             tint: existing.map { HeedPalette.color($0.colorIndex) } ?? .secondary)
                    } else if let defaultList {
                        Chip(text: defaultList.name, symbol: defaultList.symbol, tint: HeedPalette.color(defaultList.colorIndex))
                    }
                    ForEach(parsed.tags, id: \.self) { Chip(text: "@\($0)", symbol: "tag", tint: .secondary) }
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Try “call mum tomorrow 6pm”, “gym every mon wed fri”, “pay rent on the 1st every month”, or add !1 for high priority.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Suggestions

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add to your sentence").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["today", "tomorrow", "next week", "every day", "every weekday", "!1"], id: \.self) { token in
                        Button { append(token) } label: { Chip(text: token, tint: .secondary) }.buttonStyle(.plain)
                    }
                    ForEach(lists) { list in
                        Button { append("#" + list.name.replacingOccurrences(of: " ", with: "")) } label: {
                            Chip(text: "#\(list.name)", symbol: list.symbol, tint: HeedPalette.color(list.colorIndex))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func append(_ token: String) {
        if !text.isEmpty, !text.hasSuffix(" ") { text += " " }
        text += token + " "
        Haptics.tap()
    }

    // MARK: Adding

    private func add(_ parsed: ParsedTask) {
        guard !parsed.title.isEmpty else { return }
        let item = TaskActions.add(parsed, in: context, defaultList: app.quickAddList)
        if parsed.minutes != nil {
            Task {
                await Reminders.requestAuthorizationIfNeeded()
                await Reminders.syncAll()
            }
        }
        app.quickAddText = ""
        Haptics.success()
        dismiss()
        app.present(UndoAction(message: "Added “\(parsed.title)”") {
            context.delete(item)
            TaskActions.commit(context)
        })
    }
}
