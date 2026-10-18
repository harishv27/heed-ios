import SwiftUI
import SwiftData
import HeedCore

enum AppTab: Hashable { case today, upcoming, lists, settings }

/// What the whole window is doing right now: which tab, which sheet, what can be undone. Sheets are presented once,
/// from `RootView`, so any screen can open the editor or quick-add with one call.
@MainActor @Observable
final class AppState {
    var tab: AppTab = .today
    var editing: TodoItem?
    var showQuickAdd = false
    var quickAddList: UUID?
    var quickAddText = ""
    var showTriage = false
    var undo: UndoAction?

    private var undoToken = 0
    private var dayTick = 0

    /// Today's day key. Reading it ties a view to the day rolling over, so Today and Upcoming update at midnight.
    var today: Int {
        _ = dayTick
        return TaskActions.today
    }

    func refreshDay() { dayTick += 1 }

    func quickAdd(text: String = "", list: UUID? = nil) {
        quickAddText = text
        quickAddList = list
        showQuickAdd = true
    }

    /// Shows the Undo banner for a few seconds.
    func present(_ action: UndoAction?) {
        guard let action else { return }
        undo = action
        undoToken += 1
        let token = undoToken
        Task {
            try? await Task.sleep(for: .seconds(6))
            if token == undoToken { undo = nil }
        }
    }

    func performUndo() {
        undo?.revert()
        undo = nil
        Haptics.tap()
    }

    func toggle(_ item: TodoItem, in context: ModelContext) {
        let wasCompleted = item.isCompleted
        present(TaskActions.toggle(item, in: context))
        if !wasCompleted { Haptics.success() } else { Haptics.tap() }
    }

    func trash(_ item: TodoItem, in context: ModelContext) {
        present(TaskActions.trash(item, in: context))
        Haptics.tap()
    }

    func reschedule(_ item: TodoItem, to option: Reschedule, in context: ModelContext) {
        let day = option.target(from: today, firstWeekday: Calendar.current.firstWeekday)
        present(TaskActions.reschedule(item, to: day, in: context))
        Haptics.tap()
    }
}
