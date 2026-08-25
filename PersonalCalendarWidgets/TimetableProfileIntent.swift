import AppIntents
import Foundation

struct TimetableProfileEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profile")
    static let defaultQuery = TimetableProfileEntityQuery()

    let id: String
    let name: String
    let symbolName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: symbolName)
        )
    }
}

struct TimetableProfileEntityQuery: EntityQuery, Sendable {
    func entities(for identifiers: [String]) async throws -> [TimetableProfileEntity] {
        guard let available = try? entities() else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0] }
    }

    func suggestedEntities() async throws -> [TimetableProfileEntity] {
        (try? entities()) ?? []
    }

    private func entities() throws -> [TimetableProfileEntity] {
        try TimetableWidgetCatalogStore.appGroup().read().profiles.map { profile in
            TimetableProfileEntity(
                id: profile.id.storageKey,
                name: profile.name,
                symbolName: profile.symbolName
            )
        }
    }
}

struct TimetableWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Timetable"
    static let description = IntentDescription("Choose the profile shown by this widget.")

    @Parameter(title: "Profile")
    var profile: TimetableProfileEntity?

    init() {}

    init(profile: TimetableProfileEntity?) {
        self.profile = profile
    }
}
