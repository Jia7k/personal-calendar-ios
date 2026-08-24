import SwiftUI

struct NewEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedDay: LocalDay
    let calendarService: any CalendarServicing
    let settings: AppSettingsStore
    let systemCalendar: Calendar
    let isSaving: Bool
    let failedDraft: EventDraft?
    let saveErrorMessage: String?
    let onSave: (EventDraft) -> Void
    let onRetry: (EventDraft) -> Void

    @State private var title = ""
    @State private var start = Date.now
    @State private var end = Date.now.addingTimeInterval(3_600)
    @State private var isAllDay = false
    @State private var calendarID: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    Toggle("All-day", isOn: $isAllDay)
                    DatePicker("Starts", selection: $start, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                }
                Section("Calendar") {
                    Picker("Calendar", selection: $calendarID) {
                        ForEach(writableCalendars) { descriptor in Text(descriptor.title).tag(Optional(descriptor.id)) }
                    }
                    if writableCalendars.isEmpty { Text("No writable calendars are available.").foregroundStyle(.secondary) }
                }
                if let saveErrorMessage {
                    Section("Could not save") {
                        Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                        Button("Retry") { onRetry(draft) }.disabled(isSaving || !isValid).frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                    }
                }
                if !isValid { Text(validationMessage).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { onSave(draft) }
                        .disabled(isSaving || !isValid)
                        .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                }
            }
            .onAppear { restoreInitialDraft() }
        }
    }

    private var writableCalendars: [CalendarDescriptor] { calendarService.calendars().filter(\.allowsContentModifications) }
    private var draft: EventDraft { EventDraft(title: title, start: start, end: end, isAllDay: isAllDay, calendarID: calendarID) }
    private var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && calendarID != nil && end > start }
    private var validationMessage: String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter an event title to save." }
        if calendarID == nil { return "Choose a writable calendar to save." }
        return "The end must be after the start."
    }

    private func restoreInitialDraft() {
        let initial = failedDraft ?? EventDraft(title: "", start: systemCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay.startDate(in: systemCalendar))!, end: systemCalendar.date(bySettingHour: 10, minute: 0, second: 0, of: selectedDay.startDate(in: systemCalendar))!, isAllDay: false, calendarID: settings.defaultCalendarID)
        title = initial.title; start = initial.start; end = initial.end; isAllDay = initial.isAllDay
        calendarID = writableCalendars.contains(where: { $0.id == initial.calendarID }) ? initial.calendarID : writableCalendars.first?.id
    }
}
