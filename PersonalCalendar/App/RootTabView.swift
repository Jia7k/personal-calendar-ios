import SwiftUI
import UIKit

enum RootTab: Hashable { case calendar, today, tasks, routines }

struct RootTabView: View {
    let environment: AppEnvironment
    let routeController: AppRouteController
    let quickEntryHandoffStore: AppRouteHandoffStore?
    let quickEntryHandoffMonitor: AppRouteHandoffMonitor
    @State private var selection: RootTab = .calendar
    @State private var presentation: RootPresentation?
    @State private var creationProfileChoice: CreationProfileChoice?
    @State private var refreshSignal: QuickEntryRefreshSignal?
    @State private var routineDeepLink: RoutineDeepLinkSignal?
    @State private var calendarDeepLink: CalendarDeepLinkSignal?
    @State private var taskDeepLink: TaskDeepLinkSignal?
    @State private var routeAlert: RootRouteAlert?
    @State private var calendarHostBusy = false
    @State private var todayHostBusy = false
    @State private var tasksHostBusy = false
    @State private var routinesHostBusy = false
    @State private var lifecycle: RootLifecycleController
    @Environment(\.scenePhase) private var scenePhase
    init(
        environment: AppEnvironment,
        routeController: AppRouteController = AppRouteController(),
        quickEntryHandoffStore: AppRouteHandoffStore? = try? AppRouteHandoffStore.appGroup(),
        quickEntryHandoffMonitor: AppRouteHandoffMonitor = AppRouteHandoffMonitor()
    ) {
        self.environment = environment
        self.routeController = routeController
        self.quickEntryHandoffStore = quickEntryHandoffStore
        self.quickEntryHandoffMonitor = quickEntryHandoffMonitor
        _lifecycle = State(initialValue: RootLifecycleController(permissions: environment.permissions, validateDefaults: {
            environment.settings.validateDefaults(
                calendarAccess: environment.calendar.accessState,
                calendars: environment.calendar.calendars(),
                remindersAccess: environment.reminders.accessState,
                lists: environment.reminders.lists()
            )
        }, refreshCoordinator: environment.refreshCoordinator,
        reconcileForegroundLiveActivity: {
            let settings = environment.settings
            guard settings.automaticallyStartsLiveActivityOnForeground else {
                return
            }
            let snapshots = environment.timetableSnapshotCoordinator
            guard snapshots.errorMessage == nil,
                  let catalog = snapshots.latestCatalog else {
                await environment.timetableLiveActivityCoordinator.stop()
                return
            }
            await environment.timetableLiveActivityCoordinator
                .applyForegroundPreference(
                    isEnabled: true,
                    preferredProfileIdentity:
                        settings.preferredLiveActivityProfile,
                    catalog: catalog
                )
        }))
    }
    var body: some View {
        let contentRevision = AppContentRevision(
            lifecycle: lifecycle.revision,
            profileScope: environment.profileSelection.scopeRevision
        )
        let routeProcessingKey = RootRouteProcessingKey(
            pendingID: routeController.pending?.id,
            onboardingComplete: environment.settings.didCompleteOnboarding,
            presentationID: presentation?.id,
            profileChoiceID: creationProfileChoice?.id,
            alertID: routeAlert?.id,
            calendarSignalID: calendarDeepLink?.id,
            taskSignalID: taskDeepLink?.id,
            routineSignalID: routineDeepLink?.id,
            presentationState: routePresentationState,
            handoffRevision: quickEntryHandoffMonitor.revision
        )
        Group {
            if environment.settings.didCompleteOnboarding {
                TabView(selection: $selection) {
                    CalendarHomeView(
                        environment: environment,
                        revision: contentRevision,
                        quickEntryRefresh: refreshSignal,
                        calendarDeepLink: calendarDeepLink,
                        openSettings: presentSettings,
                        onOpenRoutine: openRoutine,
                        onDeepLinkHandled: handleCalendarDeepLink,
                        onPresentationChanged: { calendarHostBusy = $0 }
                    )
                        .universalQuickEntry(onAdd: presentQuickEntry)
                        .tabItem { Label("Calendar", systemImage: "calendar") }
                        .tag(RootTab.calendar)
                    TodayView(
                        environment: environment,
                        revision: contentRevision,
                        quickEntryRefresh: refreshSignal,
                        openSettings: presentSettings,
                        onOpenRoutine: openRoutine,
                        onPresentationChanged: { todayHostBusy = $0 }
                    )
                        .universalQuickEntry(onAdd: presentQuickEntry)
                        .tabItem { Label("Today", systemImage: "sun.max") }
                        .tag(RootTab.today)
                    TasksView(
                        environment: environment,
                        revision: contentRevision,
                        quickEntryRefresh: refreshSignal,
                        taskDeepLink: taskDeepLink,
                        onDeepLinkHandled: handleTaskDeepLink,
                        onPresentationChanged: { tasksHostBusy = $0 }
                    )
                        .universalQuickEntry(onAdd: presentQuickEntry)
                        .tabItem { Label("Tasks", systemImage: "checklist") }
                        .tag(RootTab.tasks)
                    RoutinesView(
                        environment: environment,
                        revision: contentRevision,
                        quickEntryRefresh: refreshSignal,
                        routineDeepLink: routineDeepLink,
                        onDeepLinkHandled: handleRoutineDeepLink,
                        onPresentationChanged: { routinesHostBusy = $0 }
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
        .onOpenURL(perform: receiveRouteURL)
        .task(id: routeProcessingKey) {
            processPendingRouteIfPossible()
            processPendingHandoffIfPossible()
        }
        .alert(item: $routeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task(id: environment.settings.didCompleteOnboarding) {
            guard environment.settings.didCompleteOnboarding else { return }
            await lifecycle.appLaunched()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await lifecycle.sceneBecameActive()
                refreshPresentedQuickEntryDestinations()
                processPendingRouteIfPossible()
                processPendingHandoffIfPossible()
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
        presentQuickEntry(initialText: nil, captureSource: .inApp)
    }

    private func presentQuickEntry(
        initialText: String?,
        captureSource: QuickEntryCaptureSource = .inApp
    ) {
        guard presentation == nil, creationProfileChoice == nil else { return }
        let resolver = creationProfileResolver()
        guard let resolution = try? resolver.resolve(active: environment.profileSelection.activeIdentity) else {
            if captureSource == .shortcut {
                presentCreationProfileChoice(
                    profiles: environment.profileSelection.profiles,
                    initialText: initialText,
                    captureSource: captureSource
                )
            }
            return
        }
        switch resolution {
        case let .ready(context):
            presentQuickEntry(
                context: context,
                initialText: initialText,
                captureSource: captureSource
            )
        case let .chooseSavedProfile(ids):
            let profilesByID = Dictionary(
                uniqueKeysWithValues: environment.profileSelection.profiles.map { ($0.id, $0) }
            )
            presentCreationProfileChoice(
                profiles: ids.compactMap { profilesByID[$0] },
                initialText: initialText,
                captureSource: captureSource
            )
        }
    }

    private func chooseCreationProfile(_ id: UUID) {
        let initialText = creationProfileChoice?.initialText
        let captureSource = creationProfileChoice?.captureSource ?? .inApp
        creationProfileChoice = nil
        guard let context = try? creationProfileResolver().resolve(chosen: id) else { return }
        presentQuickEntry(
            context: context,
            initialText: initialText,
            captureSource: captureSource
        )
    }

    private func presentCreationProfileChoice(
        profiles: [ProfileSnapshot],
        initialText: String?,
        captureSource: QuickEntryCaptureSource
    ) {
        guard !profiles.isEmpty else {
            if captureSource == .shortcut { showRouteUnavailable() }
            return
        }
        creationProfileChoice = CreationProfileChoice(
            profiles: profiles,
            initialText: initialText,
            captureSource: captureSource
        )
    }

    private func presentQuickEntry(
        context creationProfile: CreationProfileContext,
        initialText: String? = nil,
        captureSource: QuickEntryCaptureSource = .inApp
    ) {
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
            historyStore: environment.settings.quickEntryHistory,
            captureSource: captureSource,
            onCommitted: { outcome in
                if case .routine = outcome {
                    try? environment.profileSelection.refreshScope()
                }
                refreshSignal = .init(id: UUID(), outcome: outcome)
                Task { await environment.rescheduleNotifications() }
            }
        )
        if let initialText {
            model.text = initialText
            model.parse()
        }
        presentation = .quickEntry(.init(profileID: creationProfile.profileID, model: model))
    }

    private func receiveRouteURL(_ url: URL) {
        do {
            guard routeController.submit(try AppRouteCodec().route(from: url)) else {
                showRouteQueueFull()
                return
            }
        } catch {
            showRouteUnavailable()
        }
    }

    private func processPendingRouteIfPossible() {
        guard environment.settings.didCompleteOnboarding,
              routePresentationState.isIdle,
              calendarDeepLink == nil,
              taskDeepLink == nil,
              routineDeepLink == nil,
              let envelope = routeController.pending else { return }

        routeController.consume(id: envelope.id)
        dispatch(envelope)
    }

    private func processPendingHandoffIfPossible() {
        guard environment.settings.didCompleteOnboarding,
              routePresentationState.isIdle,
              calendarDeepLink == nil,
              taskDeepLink == nil,
              routineDeepLink == nil,
              routeController.pending == nil,
              let quickEntryHandoffStore else { return }

        let route: AppRoute
        do {
            guard let consumed = try quickEntryHandoffStore.consume() else { return }
            route = consumed
        } catch {
            return
        }

        guard case let .quickEntry(text, profile) = route else { return }
        presentCapturedQuickEntry(text: text, profile: profile)
    }

    private func presentCapturedQuickEntry(
        text: String,
        profile: ProfileIdentity?
    ) {
        let resolution: CreationProfileResolution
        do {
            resolution = try creationProfileResolver().resolve(
                captured: profile,
                active: environment.profileSelection.activeIdentity
            )
        } catch {
            presentCreationProfileChoice(
                profiles: environment.profileSelection.profiles,
                initialText: text,
                captureSource: .shortcut
            )
            return
        }

        switch resolution {
        case let .ready(context):
            presentQuickEntry(
                context: context,
                initialText: text,
                captureSource: .shortcut
            )
        case .chooseSavedProfile:
            presentCreationProfileChoice(
                profiles: environment.profileSelection.profiles,
                initialText: text,
                captureSource: .shortcut
            )
        }
    }

    private var routePresentationState: AppRoutePresentationState {
        .init(
            root: presentation != nil
                || creationProfileChoice != nil
                || routeAlert != nil,
            calendar: calendarHostBusy,
            today: todayHostBusy,
            tasks: tasksHostBusy,
            routines: routinesHostBusy
        )
    }

    private func dispatch(_ envelope: AppRouteEnvelope) {
        switch envelope.route {
        case .today:
            selection = .today
        case let .calendar(day, profile, entryID):
            guard routeScope(for: profile) != nil else {
                showRouteUnavailable()
                return
            }
            selection = .calendar
            calendarDeepLink = .init(id: envelope.id, day: day, entryID: entryID)
        case let .task(id, profile):
            guard let scope = routeScope(for: profile),
                  let task = environment.reminders.reminder(id: id),
                  scope.reminderListIDs.contains(task.listID) else {
                showRouteUnavailable()
                return
            }
            selection = .tasks
            taskDeepLink = .init(id: envelope.id, reminderID: id)
        case let .routine(id, profile):
            guard let scope = routeScope(for: profile),
                  scope.routineIDs.contains(id),
                  (try? environment.routines.list(includeArchived: true))?
                    .contains(where: { $0.id == id }) == true else {
                showRouteUnavailable()
                return
            }
            selection = .routines
            routineDeepLink = .init(id: envelope.id, routineID: id)
        case let .quickEntry(text, profile):
            if let profile, routeScope(for: profile) == nil {
                showRouteUnavailable()
                return
            }
            presentQuickEntry(initialText: text)
        }
    }

    private func routeScope(for requestedIdentity: ProfileIdentity?) -> ProfileScope? {
        let identity = requestedIdentity ?? environment.profileSelection.activeIdentity
        if case let .saved(id) = identity,
           !environment.profileSelection.profiles.contains(where: { $0.id == id }) {
            return nil
        }
        do {
            if requestedIdentity != nil {
                try environment.profileSelection.select(identity)
            }
            return try environment.profileScopes.resolve(identity)
        } catch {
            return nil
        }
    }

    private func handleCalendarDeepLink(_ id: UUID, succeeded: Bool) {
        guard calendarDeepLink?.id == id else { return }
        calendarDeepLink = nil
        if !succeeded { showRouteUnavailable() }
    }

    private func handleTaskDeepLink(_ id: UUID, succeeded: Bool) {
        guard taskDeepLink?.id == id else { return }
        taskDeepLink = nil
        if !succeeded { showRouteUnavailable() }
    }

    private func handleRoutineDeepLink(_ id: UUID, succeeded: Bool) {
        guard routineDeepLink?.id == id else { return }
        routineDeepLink = nil
        if !succeeded { showRouteUnavailable() }
    }

    private func showRouteUnavailable() {
        routeAlert = .unavailable
    }

    private func showRouteQueueFull() {
        guard presentation == nil,
              creationProfileChoice == nil,
              routeAlert == nil else { return }
        routeAlert = .queueFull
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
    let initialText: String?
    let captureSource: QuickEntryCaptureSource
}

private struct RootRouteProcessingKey: Hashable {
    let pendingID: UUID?
    let onboardingComplete: Bool
    let presentationID: UUID?
    let profileChoiceID: UUID?
    let alertID: UUID?
    let calendarSignalID: UUID?
    let taskSignalID: UUID?
    let routineSignalID: UUID?
    let presentationState: AppRoutePresentationState
    let handoffRevision: Int
}

private struct RootRouteAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static var unavailable: RootRouteAlert {
        .init(
            title: "Can’t Open This Item",
            message: "It may have been removed or is no longer available in that profile."
        )
    }

    static var queueFull: RootRouteAlert {
        .init(
            title: "Can’t Open This Item",
            message: "Too many items are waiting to open. Please try again."
        )
    }
}
