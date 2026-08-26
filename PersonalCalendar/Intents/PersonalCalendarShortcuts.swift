import AppIntents

struct PersonalCalendarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickEntryIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Plan with \(.applicationName)"
            ],
            shortTitle: "Quick Add",
            systemImageName: "plus.circle.fill"
        )
    }
}
