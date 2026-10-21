import Foundation
import os.log

private let logger = Logger(subsystem: "com.memocubee.officepuppy", category: "Workday")

// MARK: - Adding a missed day

/// The Log Editor's "Add a day" sheet goes through `addLog(...)`, which
/// records the error and refreshes the UI around this commit.
extension WorkdayManager {

    /// Writes an ended Daily Log for a day without one. Never overwrites an
    /// existing day and never ends in the future.
    func commitAddedLog(
        date: String, start: Date, end: Date, pause: TimeInterval, note: String
    ) -> Result<TimeEntry, DailyLogMutationError> {
        guard store.load(for: date) == nil else {
            logger.error("Cannot add a Daily Log over an existing one: \(date)")
            return .failure(.alreadyExists)
        }
        let entry = TimeEntry(
            date: date, startTime: start, endTime: end, status: .ended,
            manualPauseSeconds: pause, note: note, lastActivityTime: end)
        guard hasValidLogTimes(entry), end <= clock.now else {
            logger.error("Cannot add invalid workday times: \(date)")
            return .failure(.invalidTimes)
        }
        guard store.saveAndWait(entry) else {
            logger.error("Failed to commit added Daily Log: \(date)")
            return .failure(.saveFailed)
        }
        return .success(entry)
    }

    /// Today with no Workday yet: an added log becomes the current Workday.
    func isUnstartedToday(_ date: String) -> Bool {
        currentWorkday == nil
            && date == WorkdayDetector(newDayStartHour: newDayStartHour).effectiveDateString(for: clock.now)
    }
}
