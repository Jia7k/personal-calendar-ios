import XCTest

@MainActor
final class WeekPlannerFlowUITests: XCTestCase {
    func testSchoolWeekShowsUsableEventPopupAndOpensTheEvent() {
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
        XCTAssertGreaterThanOrEqual(detail.frame.width, 280)
        XCTAssertGreaterThanOrEqual(detail.frame.height, 200)
        XCTAssertEqual(app.staticTexts["week-event-detail-title"].label, "INF 2003 Lecture")
        XCTAssertTrue(app.staticTexts["week-event-detail-time"].exists)
        XCTAssertEqual(app.staticTexts["week-event-detail-location"].label, "Online")
        XCTAssertEqual(app.staticTexts["week-event-detail-calendar"].label, "Google School")
        let close = app.buttons["week-event-detail-close"]
        XCTAssertTrue(close.isHittable)
        let open = app.buttons["week-open-selected-item"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(open.isHittable)
        open.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
    }

    func testWeekEventPopupDoesNotChangeTheChosenDay() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let personal = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000001"]
        XCTAssertTrue(personal.waitForExistence(timeout: 3))
        personal.tap()

        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let calendar = Calendar.current
        let today = Date()
        let offset = calendar.component(.weekday, from: today) == calendar.firstWeekday ? 1 : -1
        let otherDate = calendar.date(byAdding: .day, value: offset, to: today)!
        let otherDay = app.buttons[
            otherDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
        ]
        XCTAssertTrue(otherDay.waitForExistence(timeout: 3))
        otherDay.tap()
        let selectedDay = NSPredicate(format: "value == %@", "Selected day")
        expectation(for: selectedDay, evaluatedWith: otherDay)
        waitForExpectations(timeout: 3)

        let event = app.buttons["week-event-demo-personal-event"]
        XCTAssertTrue(event.waitForExistence(timeout: 3))
        event.tap()

        let detail = app.otherElements["week-event-detail-card"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue(selectedDay.evaluate(with: otherDay))
        XCTAssertEqual(event.value as? String, "Expanded")
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            popover.frame.minY,
            event.frame.maxY - 2,
            "Popover \(popover.frame) should open below event \(event.frame)"
        )
        XCTAssertGreaterThanOrEqual(popover.frame.height, 200)
        let visibleWindow = app.windows.firstMatch.frame.insetBy(dx: -2, dy: -2)
        XCTAssertTrue(
            visibleWindow.contains(popover.frame),
            "Popover \(popover.frame) should remain inside app window \(visibleWindow)"
        )
        XCTAssertEqual(app.staticTexts["week-event-detail-title"].label, "Coffee")
        XCTAssertTrue(app.staticTexts["week-event-detail-time"].isHittable)
        XCTAssertEqual(app.staticTexts["week-event-detail-calendar"].label, "Home")
        XCTAssertTrue(app.staticTexts["week-event-detail-calendar"].isHittable)
        let close = app.buttons["week-event-detail-close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.buttons["week-open-selected-item"].isHittable)

        close.tap()
        let dismissed = NSPredicate(format: "hittable == false")
        expectation(for: dismissed, evaluatedWith: close)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(event.isHittable)
        XCTAssertTrue(selectedDay.evaluate(with: otherDay))

        event.tap()
        let reopened = NSPredicate(format: "hittable == true")
        expectation(for: reopened, evaluatedWith: close)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(detail.exists)
        XCTAssertEqual(event.value as? String, "Expanded")
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
