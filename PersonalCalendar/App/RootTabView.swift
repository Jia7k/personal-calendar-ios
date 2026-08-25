import SwiftUI
import UIKit

enum RootTab: Hashable { case calendar, today, tasks, routines }

struct RootTabView: View {
    let environment: AppEnvironment
    @State private var selection: RootTab = .calendar
    @State private var presentation: RootPresentation?
    @State private var refreshSignal: QuickEntryRefreshSignal?
    @State private var refreshAfterPresentationDismissal = false
    @State private var lifecycle: RootLifecycleController
    @Environment(\.scenePhase) private var scenePhase
    init(environment: AppEnvironment) {
        self.environment = environment
        _lifecycle = State(initialValue: RootLifecycleController(permissions: environment.permissions, validateDefaults: {
            environment.settings.validateDefaults(
                calendarAccess: environment.calendar.accessState,
                calendars: environment.calendar.calendars(),
                remindersAccess: environment.reminders.accessState,
                lists: environment.reminders.lists()
            )
        }))
    }
    var body: some View {
        Group {
            if environment.settings.didCompleteOnboarding {
                TabView(selection: $selection) {
                    CalendarHomeView(environment: environment, revision: lifecycle.revision, quickEntryRefresh: refreshSignal, openSettings: presentSettings).tabItem { Label("Calendar", systemImage: "calendar") }.tag(RootTab.calendar)
                    TodayView(environment: environment, revision: lifecycle.revision, quickEntryRefresh: refreshSignal, openSettings: presentSettings).tabItem { Label("Today", systemImage: "sun.max") }.tag(RootTab.today)
                    TasksView(environment: environment, revision: lifecycle.revision, quickEntryRefresh: refreshSignal).tabItem { Label("Tasks", systemImage: "checklist") }.tag(RootTab.tasks)
                    RoutinesView(environment: environment, revision: lifecycle.revision, quickEntryRefresh: refreshSignal).tabItem { Label("Routines", systemImage: "repeat") }.tag(RootTab.routines)
                }
                .universalQuickEntry(onAdd: presentQuickEntry)
                .sheet(item: $presentation, onDismiss: presentationDidDismiss) { presentation in
                    switch presentation {
                    case .settings:
                        SettingsView(environment: environment, onContentChanged: { lifecycle.advanceRevision() })
                    case let .quickEntry(session):
                        QuickEntrySheet(
                            model: session.model,
                            onDismiss: { self.presentation = nil },
                            onRequestAccess: { kind in requestAccess(for: kind, model: session.model) },
                            onOpenSettings: openSystemSettings
                        )
                    }
                }
            } else { PermissionOnboardingView(environment: environment) }
        }.tint(CalendarTheme.accent).onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await lifecycle.sceneBecameActive()
                refreshPresentedQuickEntryDestinations()
            }
        }
    }

    private func presentSettings() {
        guard presentation == nil else { return }
        refreshAfterPresentationDismissal = true
        presentation = .settings(id: UUID())
    }

    private func presentQuickEntry() {
        guard presentation == nil else { return }
        let context = environment.quickEntryContext()
        let options = QuickEntryDestinationOptions.resolve(
            calendar: environment.calendar,
            reminders: environment.reminders,
            settings: environment.settings
        )
        let router = SaveRouter(
            calendar: environment.calendar,
            reminders: environment.reminders,
            routines: environment.routines,
            localCalendar: context.calendar
        )
        let model = QuickEntryViewModel(
            parser: RuleBasedQuickEntryParser(),
            saver: router,
            context: context,
            destinations: options,
            onCommitted: { outcome in
                refreshSignal = .init(id: UUID(), outcome: outcome)
            }
        )
        refreshAfterPresentationDismissal = false
        presentation = .quickEntry(.init(model: model))
    }

    private func presentationDidDismiss() {
        guard refreshAfterPresentationDismissal else { return }
        refreshAfterPresentationDismissal = false
        lifecycle.advanceRevision()
    }

    private func requestAccess(for kind: QuickEntryKind, model: QuickEntryViewModel) {
        Task { @MainActor in
            switch kind {
            case .event:
                _ = await environment.calendar.requestFullAccess()
            case .task:
                _ = await environment.reminders.requestFullAccess()
            case .routine:
                break
            }
            model.updateDestinationOptions(
                .resolve(
                    calendar: environment.calendar,
                    reminders: environment.reminders,
                    settings: environment.settings
                )
            )
        }
    }

    private func refreshPresentedQuickEntryDestinations() {
        guard let presentation,
              case let .quickEntry(session) = presentation else { return }
        session.model.updateDestinationOptions(
            .resolve(
                calendar: environment.calendar,
                reminders: environment.reminders,
                settings: environment.settings
            )
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum RootPresentation: Identifiable {
    case settings(id: UUID)
    case quickEntry(RootQuickEntrySession)

    var id: UUID {
        switch self {
        case let .settings(id): id
        case let .quickEntry(session): session.id
        }
    }
}

private struct RootQuickEntrySession: Identifiable {
    let id = UUID()
    let model: QuickEntryViewModel
}
