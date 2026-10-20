import SwiftUI

/// Sheet for adding a Daily Log to a day the user forgot to punch.
struct NewLogEntryView: View {
    let manager: WorkdayManager
    let existingDates: Set<String>
    let onAdd: (TimeEntry) -> Void
    let onCancel: () -> Void

    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    @State private var pauseHours = 0
    @State private var pauseMinutes = 0
    @State private var note = ""
    @State private var addError: String?

    init(
        manager: WorkdayManager,
        existingDates: Set<String>,
        onAdd: @escaping (TimeEntry) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.manager = manager
        self.existingDates = existingDates
        self.onAdd = onAdd
        self.onCancel = onCancel

        let today = manager.clock.now
        let calendar = Calendar.current
        let defaultDay = Self.mostRecentMissingDay(before: today, existing: existingDates) ?? today
        self._day = State(initialValue: defaultDay)
        self._start = State(
            initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDay) ?? defaultDay)
        self._end = State(
            initialValue: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: defaultDay) ?? defaultDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("logEditor.addTitle")
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            Form {
                DatePicker(
                    "logEditor.addDate", selection: $day,
                    in: ...manager.clock.now, displayedComponents: [.date])
                DatePicker("logEditor.start", selection: $start, displayedComponents: [.hourAndMinute])
                DatePicker("logEditor.end", selection: $end, displayedComponents: [.hourAndMinute])
                LabeledContent("logEditor.manualPause") {
                    HStack(spacing: DesignTokens.Spacing.lg) {
                        Stepper(value: $pauseHours, in: 0...8) {
                            Text("\(pauseHours)h").monospacedDigit()
                        }
                        .accessibilityLabel(Text("logEditor.pauseHours"))
                        Stepper(value: $pauseMinutes, in: 0...59, step: 5) {
                            Text("\(pauseMinutes)m").monospacedDigit()
                        }
                        .accessibilityLabel(Text("logEditor.pauseMinutes"))
                    }
                }
                TextField("logEditor.note", text: $note)
            }

            if let message = problemMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(DesignTokens.Colors.accentRed)
            } else {
                Text(netPreview)
                    .font(DesignTokens.Typography.bodySmall)
                    .foregroundStyle(DesignTokens.Colors.onSurfaceVariant)
                    .monospacedDigit()
            }

            HStack {
                Spacer()
                Button(String(localized: "logEditor.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "logEditor.addConfirm"), action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problemMessage != nil)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 360)
        .onChange(of: [day, start, end]) { addError = nil }
    }

    // MARK: - Helpers

    private var dateString: String { TimeEntry.dateString(from: day) }

    /// The chosen day's date with the picked hour and minute.
    private func combined(_ time: Date) -> Date {
        let calendar = Calendar.current
        let hm = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: day) ?? day
    }

    private var pauseSeconds: TimeInterval { TimeInterval(pauseHours * 3600 + pauseMinutes * 60) }

    private var problemMessage: String? {
        if let addError { return addError }
        if existingDates.contains(dateString) {
            return String(localized: "logEditor.error.alreadyExists")
        }
        let startTime = combined(start), endTime = combined(end)
        if endTime <= startTime || endTime > manager.clock.now
            || pauseSeconds >= endTime.timeIntervalSince(startTime) {
            return String(localized: "logEditor.error.invalidTimes")
        }
        return nil
    }

    private var netPreview: String {
        let preview = TimeEntry(
            date: dateString, startTime: combined(start), endTime: combined(end),
            status: .ended, manualPauseSeconds: pauseSeconds)
        let net = manager.workday(for: preview).netWorkTime
        return "\(String(localized: "logEditor.netTime"))  \(net.hoursMinutesFormatted)"
    }

    private func add() {
        guard let entry = manager.addLog(
            date: dateString, start: combined(start), end: combined(end),
            manualPauseSeconds: pauseSeconds, note: note)
        else {
            addError = manager.logMutationError?.localizedDescription
            manager.clearLogMutationError()
            return
        }
        onAdd(entry)
    }

    /// Defaults to the latest past day in the last month that has no log yet.
    private static func mostRecentMissingDay(before today: Date, existing: Set<String>) -> Date? {
        let calendar = Calendar.current
        for offset in 1...31 {
            guard let candidate = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if !existing.contains(TimeEntry.dateString(from: candidate)) { return candidate }
        }
        return nil
    }
}
