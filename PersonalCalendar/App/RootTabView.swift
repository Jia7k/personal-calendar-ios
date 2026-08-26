import SwiftUI
import UIKit

enum RootTab: Hashable { case calendar, today, tasks, routines }

struct RootTabView: View {
    let environment: AppEnvironment
    @State private var selection: RootTab = .calendar
    @State private var presentation: RootPresentation?
    @State private var creationProfileChoice: CreationProfileChoice?
    @State private var refreshSignal: QuickEntryRefreshSignal?
    @State private var routineDeepLink: RoutineDeepLinkSignal?
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
        }, refreshCoordinator: environment.refreshCoordinator))
    }
    var body: some View {
        let contentRevision = AppContentRevision(
            lifecycle: lifecycle.revision,
            profileScope: environment.profileSelection.scopeRevision
        )
        Group {
            if environment.settings.didCompleteOnboarding {
                TabView(selection: $selection) {
                    CalendarHomeView(
                        environment: environment,
                        revision: contentRevision,
                        quickEntryRefresh: refreshSignal,
                        openSettings: presentSettings,
                        onOpenRoutine: openRoutine
                    )
                        .universalQuickEntry(onAdd: presentQuickEntry)
                        .tabItem { Label("Calendar", systemImage: "calendar") }
                        .tag(RootTab.calendar)
                    TodayView(environment: environment, revision: contentRevision, quickEntryRefresh: refreshSignal, openSettings: presentSettings)
                        .universalQuickEntry(onAdd: presentQuickEntry)
                        .tabItem { Label("Today", systemImage: "sun.max") }
                        .tag(RootTab.today)
                    TasksView(environment: environment, revision: contentRevision, quickEntryRefresh: refreshSignal)
                        .universalQuickEntry(onAdd: presentQuickEntry)
                        .tabItem { Label("Tasks", systemImage: "checklist") }
                        .tag(RootTab.tasks)
                    RoutinesView(
                        environment: environment,
                        revision: contentRevision,
                        quickEntryRefresh: refreshSignal,
                        routineDeepLink: routineDeepLink
                    )
                        .universalQuickEntry(onAdd: presentQuickEntry)
                        .tabItem { Label("Routines", systemImage: "repeat") }
                        .tag(RootTab.routines)
                }
                .sheet(item: $presentation) { presentation in
                    switch presentation {
                    case .settings:
                        SettingsView(environment: environment, onContentChanged: { lifecycle.advanceRevision() })
                    case let .quickEntry(session):
                        QuickEntrySheet(
                            model: session.model,
                            onDismiss: { self.presentation = nil },
                            onRequestAccess: { kind in
                                requestAccess(
                                    for: kind,
                                    profileID: session.profileID,
                                    model: session.model
                                )
                            },
                            onOpenSettings: openSystemSettings
                        )
                    }
                }
                .confirmationDialog(
                    "Create in Profile",
                    isPresented: Binding(
                        get: { creationProfileChoice != nil },
                        set: { if !$0 { creationProfileChoice = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    if let choice = creationProfileChoice {
                        ForEach(choice.profiles) { profile in
                            Button {
                                chooseCreationProfile(profile.id)
                            } label: {
                                Label(profile.name, systemImage: profile.symbolName)
                            }
                            .accessibilityIdentifier("quick-entry-profile-\(profile.id.uuidString)")
                        }
                    }
                    Button("Cancel", role: .cancel) { creationProfileChoice = nil }
                } message: {
                    Text("Choose where this new item belongs. You can still change its calendar or list before saving.")
                }
            } else { PermissionOnboardingView(environment: environment) }
        }
        .tint(CalendarTheme.accent)
        .task(id: environment.settings.didCompleteOnboarding) {
            guard environment.settings.didCompleteOnboarding else { return }
            await environment.refreshCoordinator.refreshNow(reason: .launch)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await lifecycle.sceneBecameActive()
                refreshPresentedQuickEntryDestinations()
            }
        }
    }

    private func presentSettings() {
        guard presentation == nil else { return }
        presentation = .settings(id: UUID())
    }

    private func openRoutine(_ id: UUID) {
        routineDeepLink = RoutineDeepLinkSignal(id: UUID(), routineID: id)
        selection = .routines
    }

    private func presentQuickEntry() {
        guard presentation == nil, creationProfileChoice == nil else { return }
        let resolver = creationProfileResolver()
        guard let resolution = try? resolver.resolve(
            active: environment.profileSelection.activeIdentity
        ) else { return }
        switch resolution {
        case let .ready(context):
            presentQuickEntry(context: context)
        case let .chooseSavedProfile(ids):
            let profilesByID = Dictionary(
                uniqueKeysWithValues: environment.profileSelection.profiles.map { ($0.id, $0) }
            )
            creationProfileChoice = CreationProfileChoice(
                profiles: ids.compactMap { profilesByID[$0] }
            )
        }
    }

    private func chooseCreationProfile(_ id: UUID) {
        creationProfileChoice = nil
        guard let context = try? creationProfileResolver().resolve(chosen: id) else { return }
        presentQuickEntry(context: context)
    }

    private func presentQuickEntry(context creationProfile: CreationProfileContext) {
        guard presentation == nil else { return }
        let context = environment.quickEntryContext()
        let options = QuickEntryDestinationOptions.resolve(
            calendar: environment.calendar,
            reminders: environment.reminders,
            context: creationProfile
        )
        let router = SaveRouter(
            calendar: environment.calendar,
            reminders: environment.reminders,
            routines: environment.routines,
            categories: environment.categories,
            routineProfileMutations: environment.routineProfileMutations,
            creationProfile: creationProfile,
            localCalendar: context.calendar
        )
        let model = QuickEntryViewModel(
            parser: RuleBasedQuickEntryParser(),
            saver: router,
            context: context,
            destinations: options,
            categories: (try? environment.categories.list()) ?? [],
            creationProfile: creationProfile,
            onCommitted: { outcome in
                if case .routine = outcome {
                    try? environment.profileSelection.refreshScope()
                }
                refreshSignal = .init(id: UUID(), outcome: outcome)
                Task { await environment.rescheduleNotifications() }
            }
        )
        presentation = .quickEntry(.init(profileID: creationProfile.profileID, model: model))
    }

    private func requestAccess(
        for kind: QuickEntryKind,
        profileID: UUID,
        model: QuickEntryViewModel
    ) {
        Task { @MainActor in
            switch kind {
            case .event:
                _ = await environment.calendar.requestFullAccess()
            case .task:
                _ = await environment.reminders.requestFullAccess()
            case .routine:
                break
            }
            guard let creationProfile = try? creationProfileResolver().resolve(
                chosen: profileID
            ) else { return }
            model.updateDestinationOptions(
                .resolve(
                    calendar: environment.calendar,
                    reminders: environment.reminders,
                    context: creationProfile
                )
            )
        }
    }

    private func refreshPresentedQuickEntryDestinations() {
        guard let presentation,
              case let .quickEntry(session) = presentation else { return }
        guard let creationProfile = try? creationProfileResolver().resolve(
            chosen: session.profileID
        ) else { return }
        session.model.updateDestinationOptions(
            .resolve(
                calendar: environment.calendar,
                reminders: environment.reminders,
                context: creationProfile
            )
        )
    }

    private func creationProfileResolver() -> CreationProfileResolver {
        CreationProfileResolver(
            profiles: environment.profileSelection.profiles,
            resolveScope: { try environment.profileScopes.resolve($0) }
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
    let profileID: UUID
    let model: QuickEntryViewModel
}

private struct CreationProfileChoice: Identifiable {
    let id = UUID()
    let profiles: [ProfileSnapshot]
}
