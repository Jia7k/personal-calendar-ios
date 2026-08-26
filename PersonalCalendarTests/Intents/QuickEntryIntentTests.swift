import AppIntents
import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class QuickEntryIntentTests: XCTestCase {
    private static let schoolID = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
    private static let workID = UUID(uuidString: "B2000000-0000-4000-8000-000000000002")!

    func testWhitespaceOnlyTextIsRejectedWithoutCreatingHandoff() async throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }
        let intent = QuickEntryIntent(
            text: " \n\t\u{00A0} ",
            profile: nil,
            handoffStore: fixture.store
        )

        do {
            _ = try await intent.perform()
            XCTFail("Whitespace-only capture must not open an empty confirmation.")
        } catch {
            XCTAssertEqual(error as? QuickEntryIntentError, .blankText)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
        XCTAssertTrue(try contents(of: fixture.directory).isEmpty)
    }

    func testUnicodeTextRoundTripsExactlyAndIsConsumedOnlyOnce() async throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }
        let text = "  Réviser 研究ノート / mañana at 9:30 ✨\nBring café notes  "
        let intent = QuickEntryIntent(
            text: text,
            profile: nil,
            handoffStore: fixture.store
        )

        _ = try await intent.perform()

        let payload = try Data(contentsOf: fixture.store.fileURL)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertFalse(String(decoding: payload, as: UTF8.self).contains("personalcalendar://"))
        XCTAssertFalse(fixture.store.fileURL.absoluteString.contains(text))
        XCTAssertEqual(
            try fixture.store.consume(),
            .quickEntry(text: text, profile: nil)
        )
        XCTAssertNil(try fixture.store.consume())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
    }

    func testWritingHandoffPublishesArrivalRevisionWithoutPayloadInSignal() async throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }
        let monitor = AppRouteHandoffMonitor()
        let initialRevision = monitor.revision
        let privateText = "Therapy notes tomorrow at 2pm"

        try fixture.store.write(.quickEntry(text: privateText, profile: nil))

        let deadline = ContinuousClock.now + .seconds(1)
        while monitor.revision == initialRevision, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(monitor.revision, initialRevision + 1)
        XCTAssertFalse(AppRouteHandoffStore.arrivalNotificationName.contains(privateText))
    }

    func testConsumeRemovesDeadProcessClaimsWithoutTouchingCurrentProcessClaim() throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }
        let prefix = ".\(fixture.store.fileURL.lastPathComponent).consuming-"
        let deadClaim = fixture.directory.appendingPathComponent(
            "\(prefix)2147483647-\(UUID().uuidString)"
        )
        let liveClaim = fixture.directory.appendingPathComponent(
            "\(prefix)\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
        )
        try Data("abandoned private capture".utf8).write(to: deadClaim)
        try Data("currently consuming".utf8).write(to: liveClaim)

        XCTAssertNil(try fixture.store.consume())

        XCTAssertFalse(FileManager.default.fileExists(atPath: deadClaim.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveClaim.path))
    }

    func testSavedProfileIdentityIsPreservedExactly() async throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }
        let profile = QuickEntryProfileEntity(
            id: ProfileIdentity.saved(Self.schoolID).storageKey,
            name: "School",
            symbolName: "graduationcap.fill"
        )
        let intent = QuickEntryIntent(
            text: "Review algorithms tomorrow at 4pm",
            profile: profile,
            handoffStore: fixture.store
        )

        _ = try await intent.perform()

        XCTAssertEqual(
            try fixture.store.consume(),
            .quickEntry(
                text: "Review algorithms tomorrow at 4pm",
                profile: .saved(Self.schoolID)
            )
        )
    }

    func testNilProfileStaysNilAndNeverBecomesEverything() async throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }
        let intent = QuickEntryIntent(
            text: "Buy oat milk",
            profile: nil,
            handoffStore: fixture.store
        )

        _ = try await intent.perform()

        XCTAssertEqual(
            try fixture.store.consume(),
            .quickEntry(text: "Buy oat milk", profile: nil)
        )
    }

    func testEverythingAndMalformedProfileEntitiesFailClosedWithoutHandoff() async throws {
        for entity in [
            QuickEntryProfileEntity(
                id: ProfileIdentity.everything.storageKey,
                name: "Everything",
                symbolName: "rectangle.3.group.fill"
            ),
            QuickEntryProfileEntity(
                id: "saved:not-a-uuid",
                name: "Broken",
                symbolName: "questionmark"
            )
        ] {
            let fixture = try makeHandoffFixture()
            defer { fixture.remove() }
            let intent = QuickEntryIntent(
                text: "Private capture",
                profile: entity,
                handoffStore: fixture.store
            )

            do {
                _ = try await intent.perform()
                XCTFail("Only a concrete saved profile may be handed off.")
            } catch {
                XCTAssertEqual(error as? QuickEntryIntentError, .invalidProfile)
            }

            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
        }
    }

    func testStoreRejectsEverythingProfileEvenWhenCalledDirectly() throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }

        XCTAssertThrowsError(
            try fixture.store.write(
                .quickEntry(text: "Private capture", profile: .everything)
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
    }

    func testMalformedAndUnsupportedEnvelopesAreDiscarded() throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }

        try Data("{not-json".utf8).write(to: fixture.store.fileURL, options: .atomic)
        XCTAssertNil(try fixture.store.consume())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))

        try fixture.store.write(.quickEntry(text: "Private capture", profile: nil))
        let validPayload = try Data(contentsOf: fixture.store.fileURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validPayload) as? [String: Any]
        )
        object["version"] = 999
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: fixture.store.fileURL, options: .atomic)

        XCTAssertNil(try fixture.store.consume())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
    }

    func testOversizedWritesAndExistingPayloadsFailClosed() throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }
        let oversizedText = String(repeating: "x", count: 1_000_000)

        XCTAssertThrowsError(
            try fixture.store.write(.quickEntry(text: oversizedText, profile: nil))
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))

        try Data(repeating: 0x41, count: 1_000_000)
            .write(to: fixture.store.fileURL, options: .atomic)
        XCTAssertNil(try fixture.store.consume())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
    }

    func testIntentAlwaysOpensAppForExistingConfirmationFlow() {
        XCTAssertTrue(QuickEntryIntent.openAppWhenRun)
    }

    func testProfileEntityQueryOffersOnlySavedProfiles() async throws {
        let fixture = try makeCatalogFixture()
        defer { fixture.remove() }
        let query = QuickEntryProfileEntityQuery(catalogStore: fixture.store)

        let suggested = try await query.suggestedEntities()

        XCTAssertEqual(
            suggested.map(\.id),
            [
                ProfileIdentity.saved(Self.schoolID).storageKey,
                ProfileIdentity.saved(Self.workID).storageKey
            ]
        )
        XCTAssertEqual(suggested.map(\.name), ["School", "Work"])
        XCTAssertFalse(suggested.contains { $0.id == ProfileIdentity.everything.storageKey })

        let resolved = try await query.entities(for: [
            ProfileIdentity.everything.storageKey,
            ProfileIdentity.saved(Self.workID).storageKey,
            "saved:not-a-uuid"
        ])
        XCTAssertEqual(resolved.map(\.id), [ProfileIdentity.saved(Self.workID).storageKey])
    }

    func testPerformWritesOnlyTheHandoffArtifactForLaterConfirmation() async throws {
        let fixture = try makeHandoffFixture()
        defer { fixture.remove() }
        let intent = QuickEntryIntent(
            text: "Dentist Friday at 3pm",
            profile: nil,
            handoffStore: fixture.store
        )

        _ = try await intent.perform()

        XCTAssertEqual(
            try contents(of: fixture.directory).map(\.lastPathComponent),
            [fixture.store.fileURL.lastPathComponent]
        )
        XCTAssertEqual(
            try fixture.store.consume(),
            .quickEntry(text: "Dentist Friday at 3pm", profile: nil)
        )
    }

    private func makeHandoffFixture() throws -> HandoffFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickEntryIntentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return HandoffFixture(
            directory: directory,
            store: AppRouteHandoffStore(
                fileURL: directory.appendingPathComponent("quick-entry-handoff-v1.json")
            )
        )
    }

    private func makeCatalogFixture() throws -> CatalogFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickEntryProfileQueryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let store = TimetableWidgetCatalogStore(
            fileURL: directory.appendingPathComponent("timetable-catalog-v1.json")
        )
        try store.write(
            TimetableWidgetCatalogV1(
                version: TimetableWidgetCatalogV1.currentVersion,
                generatedAt: .init(timeIntervalSince1970: 1_788_000_000),
                profiles: [
                    profile(
                        id: .everything,
                        name: "Everything",
                        symbolName: "rectangle.3.group.fill"
                    ),
                    profile(
                        id: .saved(Self.schoolID),
                        name: "School",
                        symbolName: "graduationcap.fill"
                    ),
                    profile(
                        id: .saved(Self.workID),
                        name: "Work",
                        symbolName: "briefcase.fill"
                    )
                ]
            )
        )
        return CatalogFixture(directory: directory, store: store)
    }

    private func profile(
        id: ProfileIdentity,
        name: String,
        symbolName: String
    ) -> TimetableWidgetProfile {
        let generatedAt = Date(timeIntervalSince1970: 1_788_000_000)
        return TimetableWidgetProfile(
            id: id,
            name: name,
            colorHex: "#4F6F64",
            symbolName: symbolName,
            snapshot: TimetableSnapshotV1(
                version: TimetableSnapshotV1.currentVersion,
                availability: .ready,
                generatedAt: generatedAt,
                weekStart: generatedAt,
                timeZoneIdentifier: "Asia/Singapore",
                entries: []
            )
        )
    }

    private func contents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
    }
}

private struct HandoffFixture {
    let directory: URL
    let store: AppRouteHandoffStore

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct CatalogFixture {
    let directory: URL
    let store: TimetableWidgetCatalogStore

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
