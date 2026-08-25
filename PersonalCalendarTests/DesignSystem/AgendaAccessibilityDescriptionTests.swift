import XCTest
@testable import PersonalCalendar

final class AgendaAccessibilityDescriptionTests: XCTestCase {
    func testBuildsAgendaAccessibilityDescriptionInSourceTitleScheduleCompletionReadOnlyOrder() {
        let item = AgendaItem(
            id: "routine",
            title: "Morning walk",
            source: .routine,
            placement: .window(.morning),
            sortDate: nil,
            priority: 0,
            isCompleted: false,
            allowsModification: false
        )

        XCTAssertEqual(
            AgendaAccessibilityDescription.build(for: item),
            "Routine, Morning walk, Morning, Not completed, Read-only"
        )
    }
}
