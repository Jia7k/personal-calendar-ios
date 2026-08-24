import SwiftUI

struct PermissionOnboardingView: View {
    let environment: AppEnvironment
    @State private var page = 0
    @State private var isAdvancing = false
    private let pages = ["Calendar", "Reminders", "Notifications"]
    var body: some View {
        VStack(spacing: 24) {
            Spacer(); Image(systemName: page == 0 ? "calendar" : page == 1 ? "checklist" : "bell").font(.system(size: 48)).foregroundStyle(CalendarTheme.accent)
            Text(pages[page]).font(.largeTitle.bold()); Text("Step \(page + 1) of 3").foregroundStyle(.secondary)
            Text("Choose whether to allow this personal source now. You can change it later in Settings.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer(); Button(actionTitle) { Task { await allow() } }.buttonStyle(.borderedProminent).frame(minWidth: 44, minHeight: 44).disabled(isAdvancing)
            Button("Not Now") { advance() }.frame(minWidth: 44, minHeight: 44).disabled(isAdvancing)
        }.padding(24).task { await environment.permissions.refresh() }
    }
    private var access: AccessState { [environment.permissions.calendarAccess, environment.permissions.remindersAccess, environment.permissions.notificationAccess][page] }
    private var actionTitle: String { access == .granted ? "Continue" : "Allow" }
    private func allow() async { guard access == .notDetermined else { advance(); return }; isAdvancing = true; if page == 0 { await environment.permissions.requestCalendar() } else if page == 1 { await environment.permissions.requestReminders() } else { await environment.permissions.requestNotifications() }; advanceAfterRequest() }
    private func advance() { guard !isAdvancing else { return }; advanceAfterRequest() }
    private func advanceAfterRequest() { if page == 2 { environment.settings.didCompleteOnboarding = true } else { page += 1; isAdvancing = false } }
}
