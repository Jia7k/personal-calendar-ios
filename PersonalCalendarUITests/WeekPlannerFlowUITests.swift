import XCTest

@MainActor
final class WeekPlannerFlowUITests: XCTestCase {
    func testSchoolWeekShowsClassAndAssignmentAndOpensTheEvent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()

        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        XCTAssertTrue(app.otherElements["week-planner"].waitForExistence(timeout: 3))
        let event = app.buttons["week-event-demo-school-event"]
        XCTAssertTrue(event.exists)
        XCTAssertTrue(app.buttons["week-task-demo-school-task"].exists)

        event.tap()
        let open = app.buttons["week-open-selected-item"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        open.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
    }
}
