import Observation
import SwiftUI

@MainActor
@Observable
final class PermissionOnboardingModel {
    enum Page: Int, CaseIterable {
        case calendar, reminders, notifications

        var title: String {
            switch self {
            case .calendar: "Calendar"
            case .reminders: "Reminders"
            case .notifications: "Notifications"
            }
        }

        var symbolName: String {
            switch self {
            case .calendar: "calendar"
            case .reminders: "checklist"
            case .notifications: "bell"
            }
        }
    }

    private let permissions: PermissionCoordinator
    private let onFinish: () -> Void
    private var hasStarted = false
    private(set) var page: Page = .calendar
    private(set) var isInitialRefreshComplete = false
    private(set) var isAdvancing = false
    private(set) var isFinished = false

    init(permissions: PermissionCoordinator, onFinish: @escaping () -> Void) {
        self.permissions = permissions
        self.onFinish = onFinish
    }

    var title: String { page.title }
    var pageIndex: Int { page.rawValue }
    var stepDescription: String { "Step \(pageIndex + 1) of \(Page.allCases.count)" }
    var actionsEnabled: Bool { isInitialRefreshComplete && !isAdvancing && !isFinished }
    var access: AccessState {
        switch page {
        case .calendar: permissions.calendarAccess
        case .reminders: permissions.remindersAccess
        case .notifications: permissions.notificationAccess
        }
    }
    var primaryTitle: String { access == .notDetermined ? "Allow" : "Continue" }
    var showsNotNow: Bool { access == .notDetermined }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await permissions.refresh()
        isInitialRefreshComplete = true
    }

    func primaryAction() async {
        guard actionsEnabled else { return }
        isAdvancing = true
        guard access == .notDetermined else {
            advanceOrFinish()
            return
        }
        switch page {
        case .calendar: await permissions.requestCalendar()
        case .reminders: await permissions.requestReminders()
        case .notifications: await permissions.requestNotifications()
        }
        advanceOrFinish()
    }

    func notNow() {
        guard actionsEnabled, showsNotNow else { return }
        isAdvancing = true
        advanceOrFinish()
    }

    private func advanceOrFinish() {
        guard !isFinished else { return }
        guard page != .notifications else {
            isFinished = true
            onFinish()
            return
        }
        page = Page(rawValue: page.rawValue + 1)!
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.isAdvancing = false
        }
    }
}

struct PermissionOnboardingView: View {
    let environment: AppEnvironment
    @State private var model: PermissionOnboardingModel
    @AccessibilityFocusState private var pageHeadingFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: PermissionOnboardingModel(permissions: environment.permissions) {
            environment.settings.didCompleteOnboarding = true
        })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                Image(systemName: model.page.symbolName)
                    .font(.system(size: 48))
                    .foregroundStyle(CalendarTheme.accent)
                    .accessibilityHidden(true)
                Text(model.title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($pageHeadingFocused)
                    .accessibilityIdentifier("onboarding-heading")
                Text(model.stepDescription)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(model.stepDescription)
                    .accessibilityIdentifier("onboarding-step")
                Text("Choose whether to allow this personal source now. You can change it later in Settings.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 24)
                Button(model.primaryTitle) { Task { await model.primaryAction() } }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(!model.actionsEnabled)
                    .accessibilityIdentifier("onboarding-primary")
                if model.showsNotNow {
                    Button("Not Now", action: model.notNow)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(!model.actionsEnabled)
                        .accessibilityIdentifier("onboarding-not-now")
                }
            }
            .frame(maxWidth: 560, minHeight: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.pageIndex)
        .task { await model.start() }
        .onChange(of: model.pageIndex) { _, _ in pageHeadingFocused = true }
    }
}
