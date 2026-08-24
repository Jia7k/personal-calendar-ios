import SwiftUI

struct CalendarHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: CalendarViewModel
    @State private var showingNewEvent = false
    private let environment: AppEnvironment
    private var calendar: Calendar { .current }

    init(environment: AppEnvironment) {
        self.environment = environment
        let systemCalendar = Calendar.current
        _viewModel = State(initialValue: CalendarViewModel(today: LocalDay(date: .now, calendar: systemCalendar), calendarService: environment.calendar, remindersService: environment.reminders, routines: environment.routines, composer: environment.agendaComposer, settings: environment.settings, systemCalendar: systemCalendar))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    grid
                    DayTrayView(day: viewModel.selectedDay, agenda: viewModel.agenda, state: viewModel.trayState, isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, deniedSourceMessages: viewModel.deniedSourceMessages, calendar: calendar, onSetState: setTray, onRetry: { Task { await viewModel.load() } })
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") {}.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
                ToolbarItem(placement: .topBarTrailing) { Button("New Event", systemImage: "plus") { showingNewEvent = true }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize) }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $showingNewEvent) {
                NewEventSheet(selectedDay: viewModel.selectedDay, calendarService: environment.calendar, settings: environment.settings, systemCalendar: calendar, isSaving: viewModel.isLoading, failedDraft: viewModel.eventDraftOnFailure, onSave: { draft in
                    Task { await viewModel.createEvent(draft); if viewModel.eventDraftOnFailure == nil { showingNewEvent = false } }
                })
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Button("Previous month", systemImage: "chevron.left") { Task { await viewModel.moveMonth(by: -1) } }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            Spacer()
            Text(viewModel.displayedMonth.startDate(in: calendar).formatted(.dateTime.month(.wide).year())).font(.title2.weight(.semibold))
            Spacer()
            Button("Next month", systemImage: "chevron.right") { Task { await viewModel.moveMonth(by: 1) } }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            Button("Today") { Task { await viewModel.showToday() } }.frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
        }
    }

    private var grid: some View {
        MonthGridView(cells: MonthGridBuilder(calendar: calendar).days(containing: viewModel.displayedMonth), displayedMonth: viewModel.displayedMonth, selectedDay: viewModel.selectedDay, today: LocalDay(date: .now, calendar: calendar), agendaByDay: [viewModel.selectedDay: viewModel.agenda], calendar: calendar, onSelect: { day in Task { await viewModel.select(day) } })
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                guard abs(value.translation.height) >= 60 else { return }
                setTray(value.translation.height < 0 ? .expanded : .resting)
            })
    }

    private func setTray(_ state: TrayState) {
        if reduceMotion { viewModel.setTray(state) }
        else { withAnimation(.easeInOut(duration: 0.2)) { viewModel.setTray(state) } }
    }
}
