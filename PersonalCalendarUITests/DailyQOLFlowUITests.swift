import XCTest

@MainActor
final class DailyQOLFlowUITests: XCTestCase {
    func testJumpToChosenDateThenOpenExactTodayRoutine() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-demo-profiles",
            "-demo-daily-qol"
        ]
        app.launch()

        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.component(.day, from: now)
        var targetComponents = calendar.dateComponents([.year, .month], from: now)
        targetComponents.day = currentDay == 15 ? 16 : 15
        let targetDate = calendar.date(from: targetComponents)!
        let components = calendar.dateComponents([.year, .month, .day], from: targetDate)
        let targetIdentifier = "calendar-day-\(components.year!)-\(components.month!)-\(components.day!)"

        let openJump = app.buttons["calendar-jump-open"]
        XCTAssertTrue(openJump.waitForExistence(timeout: 3))
        openJump.tap()

        let picker = app.datePickers["calendar-jump-date-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        let spokenDate = targetDate.formatted(
            .dateTime.weekday(.wide).month(.wide).day()
        )
        let targetDateButton = picker.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", spokenDate)
        ).firstMatch
        XCTAssertTrue(targetDateButton.waitForExistence(timeout: 3))
        targetDateButton.tap()
        app.buttons["calendar-jump-confirm"].tap()

        let selectedDate = app.buttons[targetIdentifier]
        XCTAssertTrue(selectedDate.waitForExistence(timeout: 3))
        let selectionValue = selectedDate.value as? String ?? ""
        XCTAssertTrue(
            selectionValue.contains("Selected"),
            "Expected selected state after jumping, got: \(selectionValue)"
        )

        app.tabBars.buttons["Today"].tap()
        let routine = app.buttons[
            "agenda-open-routine-00000000-0000-0000-0000-000000000001"
        ]
        scrollToHittable(routine, in: app)
        XCTAssertTrue(routine.isHittable)
        routine.tap()

        XCTAssertTrue(app.navigationBars["Edit Routine"].waitForExistence(timeout: 3))
        let title = app.textFields["Routine title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "Read")
        app.buttons["Cancel"].tap()

        chooseSchoolProfile(in: app)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))

        let nextEvent = app.buttons["today-next-up-open-event"]
        scrollTowardTopToHittable(nextEvent, in: app)
        XCTAssertTrue(nextEvent.waitForExistence(timeout: 3))
        XCTAssertEqual(nextEvent.label, "Open event INF 2003 Lecture")
        let maps = app.buttons["today-next-up-maps"]
        XCTAssertTrue(maps.waitForExistence(timeout: 3))
        XCTAssertEqual(maps.label, "Open Online in Maps")
        let nextTask = app.buttons["today-next-up-open-task"]
        XCTAssertTrue(nextTask.waitForExistence(timeout: 3))
        XCTAssertEqual(nextTask.label, "Open task Assignment 1")
        XCTAssertGreaterThanOrEqual(nextEvent.frame.height, 44)
        XCTAssertGreaterThanOrEqual(maps.frame.height, 44)
        XCTAssertGreaterThanOrEqual(nextTask.frame.height, 44)

        nextEvent.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
        app.buttons["event-editor-cancel"].tap()

        XCTAssertTrue(nextTask.waitForExistence(timeout: 3))
        nextTask.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 3))
        app.buttons["task-editor-cancel"].tap()

        XCTAssertTrue(maps.waitForExistence(timeout: 3))
        maps.tap()
        XCTAssertTrue(maps.exists)
    }

    private func chooseSchoolProfile(in app: XCUIApplication) {
        let selector = app.buttons["profile-selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 3))
        selector.tap()

        let school = app.buttons[
            "profile-option-C0A10000-0000-4000-8000-000000000002"
        ]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()

        let selected = expectation(
            for: NSPredicate(format: "value == %@", "School"),
            evaluatedWith: selector
        )
        wait(for: [selected], timeout: 3)
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func scrollTowardTopToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeDown()
        }
    }
}
