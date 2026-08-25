import AppIntents
import Foundation
import WidgetKit

enum TimetableWidgetContent: Hashable, Sendable {
    case chooseProfile
    case profileDeleted
    case calendarAccessRequired(profileName: String)
    case emptyProfile(profileName: String)
    case noClasses(profileName: String)
    case ready(profileName: String, snapshot: TimetableSnapshotV1)
}

struct TimetableWidgetEntry: TimelineEntry {
    let date: Date
    let content: TimetableWidgetContent

    var isPlaceholder: Bool {
        guard case let .ready(_, snapshot) = content else { return false }
        return snapshot.generatedAt == .distantPast
    }

    var containsPrivateData: Bool {
        guard case let .ready(_, snapshot) = content else { return false }
        return !snapshot.entries.isEmpty
    }
}

struct TimetableWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TimetableWidgetEntry {
        let now = Date()
        return TimetableWidgetEntry(
            date: now,
            content: .ready(profileName: "School", snapshot: placeholderSnapshot(now: now))
        )
    }

    func snapshot(
        for configuration: TimetableWidgetConfigurationIntent,
        in context: Context
    ) async -> TimetableWidgetEntry {
        let now = Date()
        if context.isPreview { return placeholder(in: context) }
        return TimetableWidgetEntry(date: now, content: loadContent(configuration: configuration))
    }

    func timeline(
        for configuration: TimetableWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<TimetableWidgetEntry> {
        let now = Date()
        let content = loadContent(configuration: configuration)
        guard case let .ready(_, snapshot) = content else {
            return Timeline(
                entries: [TimetableWidgetEntry(date: now, content: content)],
                policy: .never
            )
        }
        let calendar = calendar(for: snapshot)
        let dates = TimetableTimelineBuilder(calendar: calendar).refreshDates(snapshot: snapshot, now: now)
        return Timeline(
            entries: dates.map { TimetableWidgetEntry(date: $0, content: content) },
            policy: .atEnd
        )
    }

    private func loadContent(
        configuration: TimetableWidgetConfigurationIntent
    ) -> TimetableWidgetContent {
        guard let configuredProfile = configuration.profile else { return .chooseProfile }
        guard let identity = ProfileIdentity(storageKey: configuredProfile.id) else {
            return .profileDeleted
        }
        guard let catalog = try? TimetableWidgetCatalogStore.appGroup().read() else {
            return .profileDeleted
        }
        let profileName = catalog.profile(for: identity)?.name ?? configuredProfile.name

        switch TimetableWidgetSelectionResolver.resolve(identity, in: catalog) {
        case .chooseProfile:
            return .chooseProfile
        case .profileDeleted:
            return .profileDeleted
        case .calendarAccessRequired:
            return .calendarAccessRequired(profileName: profileName)
        case .emptyProfile:
            return .emptyProfile(profileName: profileName)
        case .noClasses:
            return .noClasses(profileName: profileName)
        case let .ready(snapshot):
            guard !snapshot.entries.isEmpty else {
                return .noClasses(profileName: profileName)
            }
            return .ready(profileName: profileName, snapshot: snapshot)
        }
    }

    private func calendar(for snapshot: TimetableSnapshotV1) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        return value
    }

    private func placeholderSnapshot(now: Date) -> TimetableSnapshotV1 {
        let end = now.addingTimeInterval(90 * 60)
        return TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: .ready,
            generatedAt: .distantPast,
            weekStart: Calendar.current.startOfDay(for: now),
            timeZoneIdentifier: TimeZone.current.identifier,
            entries: [
                TimetableEntry(
                    id: "placeholder",
                    title: "INF 2003 Lecture",
                    shortTitle: "I03",
                    start: now.addingTimeInterval(-30 * 60),
                    end: end,
                    location: "Online"
                )
            ]
        )
    }
}
