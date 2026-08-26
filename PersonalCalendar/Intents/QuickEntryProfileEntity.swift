import AppIntents
import Foundation

struct QuickEntryProfileEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profile")
    static let defaultQuery = QuickEntryProfileEntityQuery()

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

struct QuickEntryProfileEntityQuery: EntityQuery, Sendable {
    private let catalogStore: TimetableWidgetCatalogStore?

    init() {
        catalogStore = try? TimetableWidgetCatalogStore.appGroup()
    }

    init(catalogStore: TimetableWidgetCatalogStore) {
        self.catalogStore = catalogStore
    }

    func entities(for identifiers: [String]) async throws -> [QuickEntryProfileEntity] {
        let byID = Dictionary(uniqueKeysWithValues: savedEntities().map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0] }
    }

    func suggestedEntities() async throws -> [QuickEntryProfileEntity] {
        savedEntities()
    }

    private func savedEntities() -> [QuickEntryProfileEntity] {
        guard let catalogStore,
              let profiles = try? catalogStore.read().profiles else { return [] }

        return profiles.compactMap { profile in
            guard case .saved = profile.id else { return nil }
            return QuickEntryProfileEntity(
                id: profile.id.storageKey,
                name: profile.name,
                symbolName: profile.symbolName
            )
        }
    }
}
