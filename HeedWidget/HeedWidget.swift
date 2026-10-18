import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import HeedCore

@main
struct HeedWidgetBundle: WidgetBundle {
    var body: some Widget { TodayWidget() }
}

/// What the widget needs to know about one task. Plain values, so the timeline entry is cheap to keep around.
struct WidgetTask: Identifiable {
    let id: UUID
    let title: String
    let time: String?
    let overdue: Bool
    let priority: Priority
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let openCount: Int
    let doneCount: Int

    var total: Int { openCount + doneCount }
    var fraction: Double { total == 0 ? 1 : Double(doneCount) / Double(total) }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, tasks: [
            WidgetTask(id: UUID(), title: "Submit expense report", time: "5:00 PM", overdue: false, priority: .high),
            WidgetTask(id: UUID(), title: "Call mum", time: "6:30 PM", overdue: false, priority: .none),
            WidgetTask(id: UUID(), title: "Water the plants", time: nil, overdue: false, priority: .low),
        ], openCount: 3, doneCount: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // One entry now, and a refresh just after midnight so a new day starts with the new day's list. The app also
        // reloads the widget on every change.
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1),
                                                 matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [load()], policy: .after(midnight)))
    }

    private func load() -> TodayEntry {
        let context = SharedStore.makeContext()
        let today = TaskActions.today
        let all = (try? context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let plan = Planning.dayPlan(all.map(\.summary), today: today)
        let tasks = (plan.overdue + plan.today).prefix(8).map { task in
            WidgetTask(id: task.id, title: task.title, time: task.dueMinutes.map { DateText.time($0) },
                       overdue: (task.dueDay ?? today) < today, priority: task.priority)
        }
        return TodayEntry(date: .now, tasks: Array(tasks), openCount: plan.openCount, doneCount: plan.doneToday.count)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "heed://today"))
        }
        .configurationDisplayName("Today")
        .description("See what's left today and tick tasks off from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: list(limit: 3)
        case .systemLarge: list(limit: 7)
        case .accessoryCircular: circular
        default: rectangular
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressRing(fraction: entry.fraction, lineWidth: 7)
                .overlay { Text(entry.openCount == 0 ? "✓" : "\(entry.openCount)").font(.title2.weight(.semibold)).monospacedDigit() }
                .frame(width: 62, height: 62)
            Spacer(minLength: 0)
            if entry.tasks.isEmpty {
                Text(entry.total == 0 ? "Nothing planned" : "All done").font(.subheadline.weight(.semibold))
            } else {
                Text("\(entry.openCount) left").font(.subheadline.weight(.semibold))
                Text(entry.tasks[0].title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.abbreviated)).font(.caption.weight(.semibold))
                Spacer()
                Text(entry.openCount == 0 ? "All done" : "\(entry.openCount) left").font(.caption).foregroundStyle(.secondary)
                Link(destination: URL(string: "heed://add")!) {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Color("AccentColor"))
                }
            }
            if entry.tasks.isEmpty {
                Spacer()
                Text(entry.total == 0 ? "Nothing planned for today." : "Everything is done. Nice.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(limit)) { task in
                    HStack(spacing: 10) {
                        Button(intent: CompleteTaskIntent(task: TaskEntity(id: task.id, title: task.title))) {
                            Image(systemName: "circle").font(.title3)
                                .foregroundStyle(task.overdue ? Color.red : Color("AccentColor"))
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(task.title).font(.subheadline).lineLimit(1)
                            if let time = task.time { Text(time).font(.caption2).foregroundStyle(task.overdue ? Color.red : Color.secondary) }
                            else if task.overdue { Text("Overdue").font(.caption2).foregroundStyle(.red) }
                        }
                        Spacer(minLength: 0)
                    }
                }
                if entry.tasks.count > limit {
                    Text("+ \(entry.openCount - limit) more").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lock Screen

    private var circular: some View {
        Gauge(value: entry.fraction) {
            Text("Heed")
        } currentValueLabel: {
            Text(entry.openCount == 0 ? "✓" : "\(entry.openCount)").monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.openCount == 0 ? "All done today" : "\(entry.openCount) left today").font(.headline).widgetAccentable()
            if entry.tasks.isEmpty {
                Text(entry.total == 0 ? "Nothing planned" : "Nice work").font(.caption)
            } else {
                ForEach(entry.tasks.prefix(2)) { task in
                    Text("• " + task.title).font(.caption).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color("AccentColor").opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: fraction)
                .stroke(Color("AccentColor"), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
