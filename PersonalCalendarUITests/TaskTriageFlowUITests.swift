import XCTest

@MainActor
final class TaskTriageFlowUITests: XCTestCase {
    func testOverdueTaskCanBeRescheduledUndoneAndCompletedFromWeekPlanner() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-overdue-task"]
        app.launch()

        app.tabBars.buttons["Tasks"].tap()

        let overdueSection = app.otherElements["tasks-overdue"]
        XCTAssertTrue(overdueSection.waitForExistence(timeout: 3))
        let overdueTask = app.buttons["task-open-demo-overdue-task"]
        XCTAssertTrue(overdueTask.waitForExistence(timeout: 3))

        overdueTask.swipeLeft()
        let tomorrow = app.buttons["task-reschedule-tomorrow-demo-overdue-task"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.tap()
        XCTAssertTrue(waitForDisappearance(overdueSection, timeout: 2))

        let undo = app.buttons["task-reschedule-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(overdueSection.waitForExistence(timeout: 3))

        app.tabBars.buttons["Calendar"].tap()
        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let weekTask = app.buttons["week-task-demo-task"]
        XCTAssertTrue(weekTask.waitForExistence(timeout: 3))
        weekTask.tap()
        let complete = app.buttons["week-task-complete-demo-task"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()
        XCTAssertTrue(waitForDisappearance(weekTask, timeout: 3))
        XCTAssertTrue(waitForDisappearance(complete, timeout: 3))
    }

    private func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
