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
        let detail = app.otherElements["week-event-detail-card"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["week-event-detail-title"].label, "INF 2003 Lecture")
        XCTAssertTrue(app.staticTexts["week-event-detail-time"].exists)
        XCTAssertEqual(app.staticTexts["week-event-detail-location"].label, "Online")
        XCTAssertEqual(app.staticTexts["week-event-detail-calendar"].label, "Google School")
        let open = app.buttons["week-open-selected-item"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        open.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
    }

    func testSchoolWeekEventDetailsExpandInlineAtAccessibilityXXXL() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-demo-profiles",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()

        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let event = app.buttons["week-event-demo-school-event"]
        XCTAssertTrue(event.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(event.frame.width, 44)
        XCTAssertGreaterThanOrEqual(event.frame.height, 44)
        event.tap()

        let inlineDetail = app.otherElements["week-event-detail-inline"]
        XCTAssertTrue(inlineDetail.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["week-event-detail-title"].label, "INF 2003 Lecture")
        let close = app.buttons["week-event-detail-close"]
        let open = app.buttons["week-open-selected-item"]
        XCTAssertTrue(close.isHittable)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)

        for _ in 0..<6 where !open.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(open.isHittable)
        XCTAssertGreaterThanOrEqual(open.frame.height, 44)
    }
}
