import XCTest

@testable import OfficePuppy

final class WorkdayManagerAddLogTests: XCTestCase {

    private var clock: ManualClock!
    private var store: InMemoryDailyLogStore!
    private var manager: WorkdayManager!

    override func setUp() {
        super.setUp()
        clock = ManualClock(now: date(day: 14, hour: 20))
        store = InMemoryDailyLogStore()
        let suiteName = "add-log-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let widgetSuiteName = "add-log-widget-tests-\(UUID())"
        let widgetDefaults = UserDefaults(suiteName: widgetSuiteName)!
        addTeardownBlock { widgetDefaults.removePersistentDomain(forName: widgetSuiteName) }
        manager = WorkdayManager(
            defaults: defaults, clock: clock, store: store,
            idleDetector: IdleDetector(clock: clock, idleTime: { 0 }),
            prompts: RecordingWorkdayPrompts(),
            widgetStore: SharedDefaults(defaults: widgetDefaults))
    }

    override func tearDown() {
        manager = nil
        store = nil
        clock = nil
        super.tearDown()
    }

    private func date(day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testAddsEndedLogForAMissedDay() {
        let added = manager.addLog(
            date: "2026-09-12", start: date(day: 12, hour: 9), end: date(day: 12, hour: 18),
            manualPauseSeconds: 3600, note: "Forgot to punch")

        XCTAssertNotNil(added)
        let saved = store.load(for: "2026-09-12")
        XCTAssertEqual(saved?.status, .ended)
        XCTAssertEqual(saved?.endTime, date(day: 12, hour: 18))
        XCTAssertEqual(saved?.lastActivityTime, date(day: 12, hour: 18))
        XCTAssertEqual(saved?.manualPauseSeconds, 3600)
        XCTAssertEqual(saved?.note, "Forgot to punch")
        XCTAssertNil(manager.logMutationError)
    }

    func testRefusesToOverwriteAnExistingDay() {
        let existing = TimeEntry(
            date: "2026-09-12", startTime: date(day: 12, hour: 10), endTime: date(day: 12, hour: 12),
            status: .ended)
        store.save(existing)

        let added = manager.addLog(
            date: "2026-09-12", start: date(day: 12, hour: 9), end: date(day: 12, hour: 18))

        XCTAssertNil(added)
        XCTAssertEqual(manager.logMutationError, .alreadyExists)
        XCTAssertEqual(store.load(for: "2026-09-12")?.id, existing.id)
    }

    func testRejectsEndBeforeStartOrInTheFuture() {
        XCTAssertNil(manager.addLog(
            date: "2026-09-12", start: date(day: 12, hour: 18), end: date(day: 12, hour: 9)))
        XCTAssertEqual(manager.logMutationError, .invalidTimes)

        XCTAssertNil(manager.addLog(
            date: "2026-09-15", start: date(day: 15, hour: 9), end: date(day: 15, hour: 18)))
        XCTAssertEqual(manager.logMutationError, .invalidTimes)
        XCTAssertNil(store.load(for: "2026-09-12"))
        XCTAssertNil(store.load(for: "2026-09-15"))
    }

    func testReportsSaveFailure() {
        store.saveSucceeds = false

        XCTAssertNil(manager.addLog(
            date: "2026-09-12", start: date(day: 12, hour: 9), end: date(day: 12, hour: 18)))
        XCTAssertEqual(manager.logMutationError, .saveFailed)
    }

    func testAddingTodayWhileNotStartedShowsItAsEnded() {
        XCTAssertNil(manager.currentEntry)

        manager.addLog(date: "2026-09-14", start: date(day: 14, hour: 9), end: date(day: 14, hour: 18))

        XCTAssertEqual(manager.state, .ended)
        XCTAssertEqual(manager.currentEntry?.date, "2026-09-14")
    }
}
