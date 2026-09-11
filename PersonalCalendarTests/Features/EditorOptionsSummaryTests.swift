import Foundation
import XCTest
@testable import PersonalCalendar

final class EditorOptionsSummaryTests: XCTestCase {
    func testEventSummaryDerivesEffectiveLoadedProviderOptions() {
        let summary = EditorOptionsSummary.event(
            alarmIntent: .preserve,
            alarmSnapshot: .editable([-900, -3_600]),
            recurrenceIntent: .preserve,
            recurrenceSnapshot: .editable(
                .init(frequency: .weekly, interval: 2, weekdays: [], endDate: nil)
            ),
            destinationTitle: "Personal",
            categoryTitle: "School",
            notes: "Bring the agenda",
            url: URL(string: "https://example.com/meeting")
        )

        XCTAssertEqual(
            summary,
            "Calendar: Personal · Category: School · 2 alerts · Every 2 weeks · Notes · Link"
        )
    }

    func testEventSummaryKeepsUnsupportedProviderOptionsRecognizable() {
        let summary = EditorOptionsSummary.event(
            alarmIntent: .preserve,
            alarmSnapshot: .unsupported(summary: "Provider-defined alerts"),
            recurrenceIntent: .preserve,
            recurrenceSnapshot: .unsupported(summary: "Provider-defined repeat"),
            destinationTitle: "Personal",
            categoryTitle: nil,
            notes: nil,
            url: nil
        )

        XCTAssertEqual(
            summary,
            "Calendar: Personal · Provider-defined alerts · Provider-defined repeat"
        )
    }

    func testEventSummaryUsesExplicitMutationsInsteadOfStaleProviderOptions() {
        let summary = EditorOptionsSummary.event(
            alarmIntent: .clear,
            alarmSnapshot: .unsupported(summary: "Provider-defined alerts"),
            recurrenceIntent: .replace(
                .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
            ),
            recurrenceSnapshot: .unsupported(summary: "Provider-defined repeat"),
            destinationTitle: "Work",
            categoryTitle: nil,
            notes: "   ",
            url: nil
        )

        XCTAssertEqual(summary, "Calendar: Work · Every day")
    }

    func testTaskSummaryDerivesReplacementOptionsAndUnknownProviderPriority() {
        let summary = EditorOptionsSummary.task(
            alarmIntent: .replace(Date(timeIntervalSinceReferenceDate: 100)),
            alarmSnapshot: .unsupported(summary: "Stale alert"),
            recurrenceIntent: .replace(
                .init(frequency: .monthly, interval: 1, weekdays: [], endDate: nil)
            ),
            recurrenceSnapshot: .unsupported(summary: "Stale repeat"),
            destinationTitle: "Tasks",
            categoryTitle: nil,
            priority: 4,
            notes: "  "
        )

        XCTAssertEqual(
            summary,
            "List: Tasks · Alert set · Every month · Provider priority 4"
        )
    }
}
