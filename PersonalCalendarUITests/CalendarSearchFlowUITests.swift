import XCTest

@MainActor
final class CalendarSearchFlowUITests: XCTestCase {
    func testSchoolSearchFindsEventTaskAndRoutineThenOpensEventEditor() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()

        let openSearch = app.buttons["calendar-search-open"]
        XCTAssertTrue(openSearch.waitForExistence(timeout: 3))
        openSearch.tap()
        XCTAssertTrue(app.otherElements["calendar-search-screen"].waitForExistence(timeout: 3))

        let field = app.textFields["calendar-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))

        replaceQuery(field, with: "INF")
        let event = app.buttons["calendar-search-result-event|demo-school-event"]
        XCTAssertTrue(event.waitForExistence(timeout: 3))

        replaceQuery(field, with: "Assignment")
        XCTAssertTrue(app.buttons["calendar-search-result-task|demo-school-task"].waitForExistence(timeout: 3))

        replaceQuery(field, with: "Review notes")
        XCTAssertTrue(
            app.buttons["calendar-search-result-routine|00000000-0000-0000-0000-000000000002"]
                .waitForExistence(timeout: 3)
        )

        replaceQuery(field, with: "INF")
        XCTAssertTrue(event.waitForExistence(timeout: 3))
        event.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
    }

    private func replaceQuery(_ field: XCUIElement, with query: String) {
        field.tap()
        let current = field.value as? String ?? ""
        for _ in current {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        field.typeText(query)
    }
}
