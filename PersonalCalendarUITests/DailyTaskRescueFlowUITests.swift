import XCTest

@MainActor
final class DailyTaskRescueFlowUITests: XCTestCase {
    func testUndatedAndOverdueTasksCanBeRescuedBeforeSchedulingAWeekTask() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-daily-task-rescue"]
        app.launch()

        app.tabBars.buttons["Tasks"].tap()
        let needsScheduling = app.otherElements["tasks-needs-scheduling"]
        XCTAssertTrue(needsScheduling.waitForExistence(timeout: 3))
        let undatedTask = needsScheduling.descendants(matching: .any)[
            "task-open-demo-undated-task"
        ]
        XCTAssertTrue(undatedTask.waitForExistence(timeout: 3))

        app.buttons["task-reschedule-more-demo-undated-task"].tap()
        let scheduleToday = app.buttons["task-schedule-today-demo-undated-task"]
        XCTAssertTrue(scheduleToday.waitForExistence(timeout: 3))
        scheduleToday.tap()
        XCTAssertTrue(waitForDisappearance(needsScheduling, timeout: 3))

        let tasksUndo = app.buttons["task-reschedule-undo"]
        XCTAssertTrue(tasksUndo.waitForExistence(timeout: 3))
        tasksUndo.tap()
        XCTAssertTrue(needsScheduling.waitForExistence(timeout: 3))
        XCTAssertTrue(
            needsScheduling.descendants(matching: .any)[
                "task-open-demo-undated-task"
            ].waitForExistence(timeout: 3)
        )

        app.tabBars.buttons["Today"].tap()
        let overdue = app.otherElements["today-overdue"]
        XCTAssertTrue(overdue.waitForExistence(timeout: 3))
        let overdueAge = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Due 2 days ago")
        ).firstMatch
        XCTAssertTrue(overdueAge.waitForExistence(timeout: 3))

        app.buttons["today-overdue-actions-demo-overdue-task"].tap()
        let tomorrow = app.buttons["Tomorrow"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.tap()
        XCTAssertTrue(waitForDisappearance(overdue, timeout: 3))

        let todayUndo = app.buttons["today-reschedule-undo"]
        XCTAssertTrue(todayUndo.waitForExistence(timeout: 3))
        todayUndo.tap()
        XCTAssertTrue(overdue.waitForExistence(timeout: 3))

        app.buttons["today-overdue-actions-demo-overdue-task"].tap()
        let scheduleTodayTask = app.buttons[
            "today-schedule-time-demo-overdue-task"
        ]
        XCTAssertTrue(scheduleTodayTask.waitForExistence(timeout: 3))
        scheduleTodayTask.tap()

        let todayTimeBlockForm = app.descendants(matching: .any)[
            "time-block-form"
        ]
        XCTAssertTrue(todayTimeBlockForm.waitForExistence(timeout: 3))
        let cancelTodayTimeBlock = app.buttons["time-block-cancel"]
        XCTAssertTrue(cancelTodayTimeBlock.waitForExistence(timeout: 3))
        cancelTodayTimeBlock.tap()
        XCTAssertTrue(waitForDisappearance(todayTimeBlockForm, timeout: 3))

        app.tabBars.buttons["Calendar"].tap()
        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let weekTask = app.buttons["week-task-demo-week-task"]
        XCTAssertTrue(weekTask.waitForExistence(timeout: 3))
        weekTask.tap()
        let scheduleWeekTask = app.buttons["week-task-schedule-demo-week-task"]
        XCTAssertTrue(scheduleWeekTask.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(scheduleWeekTask.frame.height, 44)
        scheduleWeekTask.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["time-block-form"]
                .waitForExistence(timeout: 3)
        )
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
