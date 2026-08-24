import SwiftUI

struct CalendarHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: CalendarViewModel
    @State private var showingNewEvent = false
    private let environment: AppEnvironment
    private let openSettings: @MainActor () -> Void
    private var calendar: Calendar { .current }

    init(environment: AppEnvironment, openSettings: @escaping @MainActor () -> Void = {}) {
        self.environment = environment
        self.openSettings = openSettings
        let systemCalendar = Calendar.current
        _viewModel = State(initialValue: CalendarViewModel(today: LocalDay(date: .now, calendar: systemCalendar), calendarService: environment.calendar, remindersService: environment.reminders, routines: environment.routines, composer: environment.agendaComposer, settings: environment.settings, systemCalendar: systemCalendar))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    grid
                    DayTrayView(day: viewModel.selectedDay, agenda: viewModel.agenda, state: viewModel.trayState, isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, deniedSourceMessages: viewModel.deniedSourceMessages, calendar: calendar, openSettings: openSettings, onSetState: setTray, onRetry: { Task { await viewModel.load() } })
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape", action: openSettings).frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
                ToolbarItem(placement: .topBarTrailing) { Button("New Event", systemImage: "plus") { showingNewEvent = true }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $showingNewEvent) {
                NewEventSheet(selectedDay: viewModel.selectedDay, calendarService: environment.calendar, settings: environment.settings, systemCalendar: calendar, isSaving: viewModel.isLoading, failedDraft: viewModel.eventDraftOnFailure, saveErrorMessage: viewModel.eventDraftOnFailure == nil ? nil : viewModel.errorMessage, onSave: { draft in
                    Task { await viewModel.createEvent(draft); if viewModel.eventDraftOnFailure == nil { showingNewEvent = false } }
                }, onRetry: { draft in Task { await viewModel.createEvent(draft); if viewModel.eventDraftOnFailure == nil { showingNewEvent = false } } })
            }
        }
    }

    private var monthHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
            Button { Task { await viewModel.moveMonth(by: -1) } } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month").frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            Spacer()
            Text(viewModel.displayedMonth.startDate(in: calendar).formatted(.dateTime.month(.wide).year())).font(.title2.weight(.semibold))
            Spacer()
            Button { Task { await viewModel.moveMonth(by: 1) } } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month").frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            }
            Button("Today") { Task { await viewModel.showToday() } }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
        }
    }

    private var grid: some View {
        let builder = MonthGridBuilder(calendar: calendar)
        let cells = viewModel.trayState == .expanded
            ? builder.week(containing: viewModel.selectedDay, displayedMonth: viewModel.displayedMonth)
            : builder.days(containing: viewModel.displayedMonth)
        return MonthGridView(cells: cells, displayedMonth: viewModel.displayedMonth, selectedDay: viewModel.selectedDay, today: LocalDay(date: .now, calendar: calendar), agendaByDay: viewModel.visibleAgendas, calendar: calendar, onSelect: { day in Task { await viewModel.select(day) } })
            .accessibilityIdentifier(viewModel.trayState == .expanded ? "selected-week-strip" : "month-grid")
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) >= 60 {
                    Task { await viewModel.moveMonth(by: value.translation.width < 0 ? 1 : -1) }
                } else if abs(value.translation.height) >= 60 {
                    setTray(value.translation.height < 0 ? .expanded : .resting)
                }
            })
    }

    private func setTray(_ state: TrayState) {
        if reduceMotion { viewModel.setTray(state) }
        else { withAnimation(.easeInOut(duration: 0.2)) { viewModel.setTray(state) } }
    }
}
