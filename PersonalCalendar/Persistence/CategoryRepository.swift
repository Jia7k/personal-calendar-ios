import Foundation

enum ExternalItemSource: String, Codable, Hashable, Sendable {
    case event
    case task
}

struct CategorySnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
}

enum CategoryRepositoryError: Error, Equatable, Sendable {
    case invalidName
    case invalidColor
    case duplicateName
    case categoryNotFound
    case invalidReorder
    case invalidExternalIdentifier
    case replacementCategoryNotFound
    case replacementMatchesDeletedCategory
}

@MainActor
protocol CategoryRepository: AnyObject {
    func list() throws -> [CategorySnapshot]
    func create(name: String, colorHex: String) throws -> UUID
    func update(id: UUID, name: String, colorHex: String) throws
    func reorder(ids: [UUID]) throws
    func delete(id: UUID, reassignedTo replacementID: UUID?) throws
    func assign(categoryID: UUID?, to source: ExternalItemSource, externalID: String) throws
    func category(for source: ExternalItemSource, externalID: String) throws -> CategorySnapshot?
    func removeUnresolvedLinks(for source: ExternalItemSource, validExternalIDs: Set<String>) throws
    func seedDefaultsIfNeeded(settings: AppSettingsStore) throws
}
