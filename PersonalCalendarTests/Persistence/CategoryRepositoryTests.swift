import Foundation
import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class CategoryRepositoryTests: XCTestCase {
    func testCreateUpdateAndListNormalizeValuesInStableOrder() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)

        let personalID = try subject.create(name: "  Personal  ", colorHex: "#3a8d7c")
        let workID = try subject.create(name: "Work", colorHex: "#cb6b4f")

        var categories = try subject.list()
        XCTAssertEqual(categories.map(\.id), [personalID, workID])
        XCTAssertEqual(categories.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(categories.map(\.colorHex), ["#3A8D7C", "#CB6B4F"])
        XCTAssertEqual(categories.map(\.sortOrder), [0, 1])

        try subject.update(id: workID, name: "  Deep Work  ", colorHex: "#4868a8")

        categories = try subject.list()
        XCTAssertEqual(categories.map(\.id), [personalID, workID])
        XCTAssertEqual(categories.map(\.name), ["Personal", "Deep Work"])
        XCTAssertEqual(categories.map(\.colorHex), ["#3A8D7C", "#4868A8"])
        XCTAssertEqual(categories.map(\.sortOrder), [0, 1])
    }

    func testInvalidNamesColorsAndCaseInsensitiveDuplicatesLeaveStoreUnchanged() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let workID = try subject.create(name: "Work", colorHex: "#CB6B4F")
        let personalID = try subject.create(name: "Personal", colorHex: "#3A8D7C")

        assertError(.invalidName) {
            _ = try subject.create(name: " \n ", colorHex: "#4868A8")
        }
        for color in ["#FFF", "3A8D7C", "#GGGGGG", "#3A8D7C00"] {
            assertError(.invalidColor) {
                _ = try subject.create(name: "Health", colorHex: color)
            }
        }
        assertError(.duplicateName) {
            _ = try subject.create(name: "  work  ", colorHex: "#4868A8")
        }
        assertError(.duplicateName) {
            try subject.update(id: personalID, name: "WORK", colorHex: "#3A8D7C")
        }
        assertError(.categoryNotFound) {
            try subject.update(id: UUID(), name: "Missing", colorHex: "#4868A8")
        }

        let categories = try subject.list()
        XCTAssertEqual(categories.map(\.id), [workID, personalID])
        XCTAssertEqual(categories.map(\.name), ["Work", "Personal"])
        XCTAssertEqual(categories.map(\.colorHex), ["#CB6B4F", "#3A8D7C"])
        XCTAssertEqual(categories.map(\.sortOrder), [0, 1])
    }

    func testReorderRequiresEveryCategoryExactlyOnceAndPersistsDenseOrder() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let workID = try subject.create(name: "Work", colorHex: "#CB6B4F")
        let personalID = try subject.create(name: "Personal", colorHex: "#3A8D7C")
        let healthID = try subject.create(name: "Health", colorHex: "#4868A8")

        try subject.reorder(ids: [healthID, workID, personalID])

        XCTAssertEqual(try subject.list().map(\.id), [healthID, workID, personalID])
        XCTAssertEqual(try subject.list().map(\.sortOrder), [0, 1, 2])

        assertError(.invalidReorder) {
            try subject.reorder(ids: [healthID, workID])
        }
        assertError(.invalidReorder) {
            try subject.reorder(ids: [healthID, workID, workID])
        }
        assertError(.invalidReorder) {
            try subject.reorder(ids: [healthID, workID, UUID()])
        }
        XCTAssertEqual(try subject.list().map(\.id), [healthID, workID, personalID])
        XCTAssertEqual(try subject.list().map(\.sortOrder), [0, 1, 2])
    }

    func testAssignNamespacesUpsertsClearsAndRejectsMissingTargets() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let workID = try subject.create(name: "Work", colorHex: "#CB6B4F")
        let personalID = try subject.create(name: "Personal", colorHex: "#3A8D7C")

        try subject.assign(categoryID: workID, to: .event, externalID: "shared-id")
        try subject.assign(categoryID: personalID, to: .task, externalID: "shared-id")
        XCTAssertEqual(try subject.category(for: .event, externalID: "shared-id")?.id, workID)
        XCTAssertEqual(try subject.category(for: .task, externalID: "shared-id")?.id, personalID)

        try subject.assign(categoryID: personalID, to: .event, externalID: "shared-id")
        XCTAssertEqual(try subject.category(for: .event, externalID: "shared-id")?.id, personalID)
        var links = try container.mainContext.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
        XCTAssertEqual(Set(links.map(\.key)), Set(["event|shared-id", "task|shared-id"]))
        XCTAssertEqual(links.count, 2)

        try subject.assign(categoryID: nil, to: .event, externalID: "shared-id")
        XCTAssertNil(try subject.category(for: .event, externalID: "shared-id"))
        XCTAssertEqual(try subject.category(for: .task, externalID: "shared-id")?.id, personalID)
        links = try container.mainContext.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.sourceRaw, "task")
        XCTAssertEqual(links.first?.externalID, "shared-id")
        XCTAssertEqual(links.first?.categoryID, personalID)

        assertError(.categoryNotFound) {
            try subject.assign(categoryID: UUID(), to: .task, externalID: "shared-id")
        }
        assertError(.invalidExternalIdentifier) {
            try subject.assign(categoryID: personalID, to: .event, externalID: "")
        }
        assertError(.invalidExternalIdentifier) {
            try subject.assign(categoryID: personalID, to: .event, externalID: "  ")
        }
        XCTAssertEqual(try subject.category(for: .task, externalID: "shared-id")?.id, personalID)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<ExternalCategoryLinkRecord>()).count, 1)
    }

    func testSourceScopedOrphanCleanupPreservesTheOtherSource() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let workID = try subject.create(name: "Work", colorHex: "#CB6B4F")
        for source in [ExternalItemSource.event, .task] {
            try subject.assign(categoryID: workID, to: source, externalID: "keep")
            try subject.assign(categoryID: workID, to: source, externalID: "drop")
        }

        try subject.removeUnresolvedLinks(for: .event, validExternalIDs: ["keep"])

        XCTAssertEqual(try subject.category(for: .event, externalID: "keep")?.id, workID)
        XCTAssertNil(try subject.category(for: .event, externalID: "drop"))
        XCTAssertEqual(try subject.category(for: .task, externalID: "keep")?.id, workID)
        XCTAssertEqual(try subject.category(for: .task, externalID: "drop")?.id, workID)

        try subject.removeUnresolvedLinks(for: .task, validExternalIDs: ["drop"])

        XCTAssertNil(try subject.category(for: .task, externalID: "keep"))
        XCTAssertEqual(try subject.category(for: .task, externalID: "drop")?.id, workID)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<ExternalCategoryLinkRecord>()).count, 2)
    }

    func testDeleteWithReplacementAtomicallyReassignsRoutineAndLinks() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let oldID = try subject.create(name: "Work", colorHex: "#CB6B4F")
        let replacementID = try subject.create(name: "Personal", colorHex: "#3A8D7C")
        let routine = RoutineRecord(
            draft: routineDraft(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        routine.categoryID = oldID
        container.mainContext.insert(routine)
        try container.mainContext.save()
        try subject.assign(categoryID: oldID, to: .event, externalID: "event-1")
        try subject.assign(categoryID: oldID, to: .task, externalID: "task-1")

        try subject.delete(id: oldID, reassignedTo: replacementID)

        XCTAssertEqual(try subject.list().map(\.id), [replacementID])
        XCTAssertEqual(routine.categoryID, replacementID)
        XCTAssertEqual(try subject.category(for: .event, externalID: "event-1")?.id, replacementID)
        XCTAssertEqual(try subject.category(for: .task, externalID: "task-1")?.id, replacementID)
        let links = try container.mainContext.fetch(FetchDescriptor<ExternalCategoryLinkRecord>())
        XCTAssertEqual(links.count, 2)
        XCTAssertTrue(links.allSatisfy { $0.categoryID == replacementID })
    }

    func testDeleteWithoutReplacementClearsAssignmentsOnlyAfterValidation() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let oldID = try subject.create(name: "Work", colorHex: "#CB6B4F")
        let routine = RoutineRecord(
            draft: routineDraft(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        routine.categoryID = oldID
        container.mainContext.insert(routine)
        try container.mainContext.save()
        try subject.assign(categoryID: oldID, to: .event, externalID: "event-1")

        assertError(.replacementCategoryNotFound) {
            try subject.delete(id: oldID, reassignedTo: UUID())
        }
        assertError(.replacementMatchesDeletedCategory) {
            try subject.delete(id: oldID, reassignedTo: oldID)
        }
        assertError(.categoryNotFound) {
            try subject.delete(id: UUID(), reassignedTo: nil)
        }
        XCTAssertEqual(try subject.list().map(\.id), [oldID])
        XCTAssertEqual(routine.categoryID, oldID)
        XCTAssertEqual(try subject.category(for: .event, externalID: "event-1")?.id, oldID)

        try subject.delete(id: oldID, reassignedTo: nil)

        XCTAssertTrue(try subject.list().isEmpty)
        XCTAssertNil(routine.categoryID)
        XCTAssertNil(try subject.category(for: .event, externalID: "event-1"))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ExternalCategoryLinkRecord>()).isEmpty)
    }

    func testDefaultSeedIsIdempotentPersistsFlagAndNeverReseedsAfterDeletion() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let defaults = makeDefaults()
        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(settings.didSeedCategories)

        try subject.seedDefaultsIfNeeded(settings: settings)

        var categories = try subject.list()
        XCTAssertEqual(categories.map(\.name), ["Work", "Personal", "Health", "Errands"])
        XCTAssertEqual(categories.map(\.colorHex), ["#CB6B4F", "#3A8D7C", "#4868A8", "#8A63B8"])
        XCTAssertEqual(categories.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertTrue(settings.didSeedCategories)
        XCTAssertTrue(AppSettingsStore(defaults: defaults).didSeedCategories)
        let originalIDs = categories.map(\.id)

        settings.didSeedCategories = false
        try subject.seedDefaultsIfNeeded(settings: settings)
        categories = try subject.list()
        XCTAssertEqual(categories.map(\.id), originalIDs)
        XCTAssertEqual(categories.count, 4)
        XCTAssertTrue(settings.didSeedCategories)

        for category in categories {
            try subject.delete(id: category.id, reassignedTo: nil)
        }
        XCTAssertTrue(try subject.list().isEmpty)

        try subject.seedDefaultsIfNeeded(settings: settings)
        XCTAssertTrue(try subject.list().isEmpty)
        XCTAssertTrue(settings.didSeedCategories)
    }

    func testDefaultSeedAppendsOnlyMissingDefaultsWithoutReplacingExistingCategories() throws {
        let container = try makeContainer()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let defaults = makeDefaults()
        let settings = AppSettingsStore(defaults: defaults)
        let customID = try subject.create(name: "Custom", colorHex: "#112233")
        let workID = try subject.create(name: "Work", colorHex: "#ABCDEF")

        try subject.seedDefaultsIfNeeded(settings: settings)

        let categories = try subject.list()
        XCTAssertEqual(categories.map(\.id).prefix(2), [customID, workID])
        XCTAssertEqual(categories.map(\.name), ["Custom", "Work", "Personal", "Health", "Errands"])
        XCTAssertEqual(categories.map(\.colorHex), ["#112233", "#ABCDEF", "#3A8D7C", "#4868A8", "#8A63B8"])
        XCTAssertEqual(categories.map(\.sortOrder), [0, 1, 2, 3, 4])
        XCTAssertTrue(settings.didSeedCategories)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: RoutineRecord.self,
            RoutineCompletionRecord.self,
            CategoryRecord.self,
            ExternalCategoryLinkRecord.self,
            configurations: configuration
        )
    }

    private func routineDraft() -> RoutineDraft {
        RoutineDraft(
            title: "Read",
            weekdays: [2, 4, 6],
            window: .evening,
            reminderHour: nil,
            reminderMinute: nil
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CategoryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func assertError(
        _ expected: CategoryRepositoryError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? CategoryRepositoryError, expected, file: file, line: line)
        }
    }
}
