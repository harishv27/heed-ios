import XCTest
@testable import HeedCore

// MARK: - Notification health

final class NotificationHealthTests: XCTestCase {
    func testEverythingOnIsHealthy() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .authorized))
        XCTAssertTrue(issues.isEmpty)
        XCTAssertTrue(NotificationHealth.isHealthy(issues))
    }

    func testDeniedPointsToSettings() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .denied))
        XCTAssertEqual(issues.map(\.id), ["denied"])
        XCTAssertEqual(issues[0].severity, .problem)
        XCTAssertEqual(issues[0].fix, .openSettings)
        XCTAssertFalse(NotificationHealth.isHealthy(issues))
    }

    func testNotAskedYetOffersThePrompt() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .notDetermined))
        XCTAssertEqual(issues.first?.fix, .askPermission)
        XCTAssertEqual(issues.first?.severity, .problem)
    }

    func testAlertsOffIsAProblemEvenWhenAuthorised() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .authorized, alerts: .disabled))
        XCTAssertEqual(issues.map(\.id), ["no-alerts"])
        XCTAssertEqual(issues[0].severity, .problem)
    }

    func testLockScreenAndNotificationCenterAreWarnings() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .authorized, lockScreen: .disabled,
                                                                      notificationCenter: .disabled))
        XCTAssertEqual(Set(issues.map(\.id)), ["no-lock-screen", "no-center"])
        XCTAssertTrue(issues.allSatisfy { $0.severity == .warning })
        XCTAssertFalse(NotificationHealth.isHealthy(issues))
    }

    func testSoundOffIsOnlyANote() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .authorized, sound: .disabled))
        XCTAssertEqual(issues.map(\.severity), [.info])
        XCTAssertTrue(NotificationHealth.isHealthy(issues))
    }

    func testQuietDeliveryIsAWarning() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .provisional))
        XCTAssertEqual(issues.map(\.id), ["quiet"])
        XCTAssertEqual(issues[0].severity, .warning)
    }

    func testDeferredRemindersAreExplained() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .authorized, deferredCount: 12))
        XCTAssertEqual(issues.map(\.id), ["cap"])
        XCTAssertTrue(issues[0].title.contains("12"))
        XCTAssertTrue(NotificationHealth.isHealthy(issues))
    }

    func testIssuesAreSortedWorstFirst() {
        let snapshot = NotificationSnapshot(authorization: .authorized, alerts: .disabled, sound: .disabled,
                                            lockScreen: .disabled, deferredCount: 3)
        let severities = NotificationHealth.evaluate(snapshot).map(\.severity)
        XCTAssertEqual(severities, severities.sorted(by: >))
        XCTAssertEqual(severities.first, .problem)
    }

    func testDisabledDetailsAreIgnoredWhenNotificationsAreDenied() {
        let issues = NotificationHealth.evaluate(NotificationSnapshot(authorization: .denied, alerts: .disabled, sound: .disabled))
        XCTAssertEqual(issues.map(\.id), ["denied"], "one clear cause, not a list of symptoms")
    }
}

// MARK: - Filters

final class TaskFilterTests: XCTestCase {
    private let work = UUID()
    private let home = UUID()

    private var sample: [TaskSummary] {
        [
            T.task("Report", due: T.today, priority: .high, list: work, tags: ["finance"]),
            T.task("Email boss", due: T.today - 2, priority: .medium, list: work, tags: ["waiting"]),
            T.task("Fix tap", due: T.today + 3, list: home, tags: ["Errand"]),
            T.task("Read book", list: home),
            T.task("Old", due: T.today - 1, list: work, done: T.today - 1),
        ]
    }

    private func titles(_ filter: TaskFilter) -> [String] {
        sample.filter { filter.matches($0, today: T.today) }.map(\.title)
    }

    func testAnEmptyFilterMatchesEveryOpenTask() {
        let filter = TaskFilter()
        XCTAssertTrue(filter.isEmpty)
        XCTAssertEqual(titles(filter), ["Report", "Email boss", "Fix tap", "Read book"])
    }

    func testCompletedTasksCanBeIncluded() {
        XCTAssertEqual(titles(TaskFilter(includeCompleted: true)).count, 5)
    }

    func testByList() {
        XCTAssertEqual(titles(TaskFilter(listIDs: [work])), ["Report", "Email boss"])
        XCTAssertEqual(titles(TaskFilter(listIDs: [work, home])).count, 4)
    }

    func testAnyTagIgnoresCase() {
        XCTAssertEqual(titles(TaskFilter(anyTags: ["errand"])), ["Fix tap"])
        XCTAssertEqual(titles(TaskFilter(anyTags: ["ERRAND", "finance"])), ["Report", "Fix tap"])
    }

    func testExcludedTags() {
        XCTAssertEqual(titles(TaskFilter(listIDs: [work], excludedTags: ["waiting"])), ["Report"])
    }

    func testWorkButNotWaitingAndHighPriority() {
        let filter = TaskFilter(listIDs: [work], excludedTags: ["waiting"], minimumPriority: .high, due: .todayOrOverdue)
        XCTAssertEqual(titles(filter), ["Report"])
    }

    func testMinimumPriority() {
        XCTAssertEqual(titles(TaskFilter(minimumPriority: .medium)), ["Report", "Email boss"])
        XCTAssertEqual(titles(TaskFilter(minimumPriority: .high)), ["Report"])
    }

    func testDueWindows() {
        XCTAssertEqual(titles(TaskFilter(due: .overdue)), ["Email boss"])
        XCTAssertEqual(titles(TaskFilter(due: .today)), ["Report"])
        XCTAssertEqual(titles(TaskFilter(due: .todayOrOverdue)), ["Report", "Email boss"])
        XCTAssertEqual(titles(TaskFilter(due: .next7Days)), ["Report", "Fix tap"])
        XCTAssertEqual(titles(TaskFilter(due: .next30Days)), ["Report", "Fix tap"])
        XCTAssertEqual(titles(TaskFilter(due: .noDate)), ["Read book"])
        XCTAssertEqual(titles(TaskFilter(due: .hasDate)), ["Report", "Email boss", "Fix tap"])
    }

    func testTheSevenDayWindowEndsAfterSixDaysAhead() {
        let filter = TaskFilter(due: .next7Days)
        XCTAssertTrue(filter.matches(T.task("a", due: T.today + 6), today: T.today))
        XCTAssertFalse(filter.matches(T.task("b", due: T.today + 7), today: T.today))
    }

    func testTextSearch() {
        XCTAssertEqual(titles(TaskFilter(text: "tap")), ["Fix tap"])
        XCTAssertEqual(titles(TaskFilter(listIDs: [home], text: "book")), ["Read book"])
    }

    func testPresetsAreUsable() {
        XCTAssertEqual(Set(TaskFilter.presets.map(\.name)).count, TaskFilter.presets.count)
        let high = TaskFilter.presets.first { $0.name == "High priority" }!
        XCTAssertEqual(titles(high.filter), ["Report"])
    }

    func testEncodingRoundTrips() {
        let filter = TaskFilter(listIDs: [work], anyTags: ["A"], excludedTags: ["b"], minimumPriority: .medium, due: .next7Days, text: "x")
        XCTAssertEqual(TaskFilter.decode(filter.encoded), filter)
        XCTAssertTrue(TaskFilter.decode(Data()).isEmpty, "bad data falls back to an empty filter")
    }
}

// MARK: - Backup

final class BackupTests: XCTestCase {
    private let created = T.date(2026, 10, 1, 8, 0)
    private let edited = T.date(2026, 10, 10, 8, 0)

    private func document() -> BackupDocument {
        let list = BackupList(id: UUID(), name: "Home", symbol: "house", colorIndex: 2, sortOrder: 1, modifiedAt: edited)
        let task = BackupTask(id: UUID(), title: "Pay rent", notes: "Transfer on the 1st", dueDay: T.oct(20), dueMinutes: 540,
                              recurrence: Recurrence.monthly.anchored(to: T.oct(20)), priority: 3, listID: list.id,
                              tags: ["bills"], checklist: [ChecklistItem(title: "Check balance", done: true)],
                              reminderLeadMinutes: 60, sortOrder: 4, timesCompleted: 7, createdAt: created, modifiedAt: edited)
        let trashed = BackupTask(id: UUID(), title: "Old idea", createdAt: created, modifiedAt: edited,
                                 completedAt: nil, deletedAt: T.date(2026, 10, 12, 9, 0))
        let filter = BackupFilter(id: UUID(), name: "Urgent", symbol: "flag", filter: TaskFilter(minimumPriority: .high),
                                  sortOrder: 0, modifiedAt: edited)
        return BackupDocument(exportedAt: T.now, lists: [list], tasks: [task, trashed], filters: [filter])
    }

    func testRoundTripKeepsEverything() throws {
        let original = document()
        let data = try BackupCodec.encode(original)
        XCTAssertEqual(try BackupCodec.decode(data), original)
    }

    func testRoundTripKeepsRecurrenceChecklistAndTrash() throws {
        let decoded = try BackupCodec.decode(BackupCodec.encode(document()))
        XCTAssertEqual(decoded.tasks[0].recurrence?.dayOfMonth, 20)
        XCTAssertEqual(decoded.tasks[0].checklist.first?.done, true)
        XCTAssertNotNil(decoded.tasks[1].deletedAt)
        XCTAssertEqual(decoded.tasks[0].timesCompleted, 7)
    }

    func testTheFileIsReadableJSONAndStableBetweenExports() throws {
        let original = document()
        let a = try BackupCodec.encode(original)
        let b = try BackupCodec.encode(original)
        XCTAssertEqual(a, b, "sorted keys: the same data gives the same bytes, so backups diff cleanly")
        let text = String(decoding: a, as: UTF8.self)
        XCTAssertTrue(text.contains("\"app\" : \"Heed\""))
        XCTAssertTrue(text.contains("Pay rent"))
    }

    func testFilesThatAreNotBackupsAreRejected() {
        XCTAssertThrowsError(try BackupCodec.decode(Data("hello".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"app\":\"Other\",\"version\":1}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"app\":\"Heed\"}".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"app\":\"Heed\",\"version\":1,\"tasks\":5}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
    }

    func testBackupsFromANewerAppAreRefusedWithAClearMessage() {
        let data = Data("{\"app\":\"Heed\",\"version\":99}".utf8)
        XCTAssertThrowsError(try BackupCodec.decode(data)) { error in
            XCTAssertEqual(error as? BackupError, .newerThanThisApp(version: 99))
            XCTAssertTrue((error as? BackupError)?.errorDescription?.contains("Update Heed") == true)
        }
    }

    // MARK: Merge

    func testMergeInsertsMissingUpdatesOlderAndSkipsNewer() {
        let missing = BackupTask(id: UUID(), title: "Missing", createdAt: created, modifiedAt: edited)
        let older = BackupTask(id: UUID(), title: "Backup is newer", createdAt: created, modifiedAt: edited)
        let newer = BackupTask(id: UUID(), title: "Live is newer", createdAt: created, modifiedAt: edited)
        let same = BackupTask(id: UUID(), title: "Identical", createdAt: created, modifiedAt: edited)
        let existing: [UUID: Date] = [
            older.id: edited.addingTimeInterval(-3600),
            newer.id: edited.addingTimeInterval(3600),
            same.id: edited,
        ]
        let plan = MergePlan.make(existing: existing, incoming: [missing, older, newer, same])
        XCTAssertEqual(plan.insert, [missing.id])
        XCTAssertEqual(plan.update, [older.id])
        XCTAssertEqual(plan.skip, [newer.id, same.id])
    }

    func testMergeWorksForListsAndFilters() {
        let list = BackupList(id: UUID(), name: "Home", symbol: "house", colorIndex: 0, sortOrder: 0, modifiedAt: edited)
        XCTAssertEqual(MergePlan.make(existing: [:], incoming: [list]).insert, [list.id])
        XCTAssertEqual(MergePlan.make(existing: [list.id: edited], incoming: [list]).skip, [list.id])
    }

    func testImportingTheSameBackupTwiceChangesNothingTheSecondTime() {
        let tasks = (0..<5).map { BackupTask(id: UUID(), title: "T\($0)", createdAt: created, modifiedAt: edited) }
        let first = MergePlan.make(existing: [:], incoming: tasks)
        XCTAssertEqual(first.insert.count, 5)
        let second = MergePlan.make(existing: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.modifiedAt) }), incoming: tasks)
        XCTAssertTrue(second.insert.isEmpty)
        XCTAssertTrue(second.update.isEmpty)
        XCTAssertEqual(second.skip.count, 5)
    }
}

// MARK: - Checklist and summary

final class ChecklistTests: XCTestCase {
    func testProgress() {
        XCTAssertNil(Checklist.progress([]))
        let items = [ChecklistItem(title: "a", done: true), ChecklistItem(title: "b"), ChecklistItem(title: "c", done: true)]
        let progress = Checklist.progress(items)
        XCTAssertEqual(progress?.done, 2)
        XCTAssertEqual(progress?.total, 3)
    }

    func testEncodingRoundTripsAndToleratesBadData() {
        let items = [ChecklistItem(title: "a"), ChecklistItem(title: "b", done: true)]
        XCTAssertEqual(Checklist.decode(Checklist.encode(items)), items)
        XCTAssertEqual(Checklist.decode(Data()), [])
        XCTAssertEqual(Checklist.decode(Data("nope".utf8)), [])
    }

    func testPriorityOrderingAndShorthand() {
        XCTAssertTrue(Priority.high > Priority.medium)
        XCTAssertTrue(Priority.none < Priority.low)
        XCTAssertEqual(Priority.high.shorthand, "!1")
        XCTAssertNil(Priority.none.shorthand)
        XCTAssertEqual(Priority(rawValue: 2), .medium)
    }
}
