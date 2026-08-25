import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class CategorySettingsModelTests: XCTestCase {
    func testHappyPathCreatesEditsReordersAndDeletesCategories() {
        let workID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let personalID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let repository = CategorySettingsRepositorySpy(
            categories: [.init(id: workID, name: "Work", colorHex: "#CB6B4F", sortOrder: 0)],
            nextID: personalID
        )
        let subject = CategorySettingsModel(repository: repository)

        subject.load()
        subject.create(name: "Personal", colorHex: "#3A8D7C")
        subject.update(id: workID, name: "Focus", colorHex: "#4868A8")
        subject.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        subject.delete(id: personalID, reassignedTo: workID)

        XCTAssertEqual(subject.categories, [
            .init(id: workID, name: "Focus", colorHex: "#4868A8", sortOrder: 0)
        ])
        XCTAssertEqual(repository.lastDeleteID, personalID)
        XCTAssertEqual(repository.lastReplacementID, workID)
        XCTAssertNil(subject.errorMessage)
    }
}

@MainActor
private final class CategorySettingsRepositorySpy: CategoryRepository {
    private var values: [CategorySnapshot]
    private let nextID: UUID
    private(set) var lastDeleteID: UUID?
    private(set) var lastReplacementID: UUID?

    init(categories: [CategorySnapshot], nextID: UUID) {
        values = categories
        self.nextID = nextID
    }

    func list() throws -> [CategorySnapshot] { values }

    func create(name: String, colorHex: String) throws -> UUID {
        values.append(.init(id: nextID, name: name, colorHex: colorHex, sortOrder: values.count))
        return nextID
    }

    func update(id: UUID, name: String, colorHex: String) throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index].name = name
        values[index].colorHex = colorHex
    }

    func reorder(ids: [UUID]) throws {
        values = ids.enumerated().compactMap { order, id in
            guard var category = values.first(where: { $0.id == id }) else { return nil }
            category.sortOrder = order
            return category
        }
    }

    func delete(id: UUID, reassignedTo replacementID: UUID?) throws {
        lastDeleteID = id
        lastReplacementID = replacementID
        values.removeAll { $0.id == id }
        for index in values.indices { values[index].sortOrder = index }
    }

    func assign(categoryID: UUID?, to source: ExternalItemSource, externalID: String) throws {}
    func category(for source: ExternalItemSource, externalID: String) throws -> CategorySnapshot? { nil }
    func removeUnresolvedLinks(for source: ExternalItemSource, validExternalIDs: Set<String>) throws {}
    func seedDefaultsIfNeeded(settings: AppSettingsStore) throws {}
}
