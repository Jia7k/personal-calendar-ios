import XCTest

@MainActor
final class FoundationFlowUITests: XCTestCase {
    func testLaunchShowsFourPrimaryTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Tasks"].exists)
        XCTAssertTrue(app.tabBars.buttons["Routines"].exists)
    }

    func testCalendarDateSelectionAndAccessibleTrayButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["calendar-day-today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["month-grid"].exists)
        app.buttons["Expand day"].tap()

        XCTAssertTrue(app.buttons["Collapse day"].exists)
        XCTAssertTrue(app.otherElements["selected-week-strip"].exists)
        XCTAssertFalse(app.otherElements["month-grid"].exists)
        app.buttons["Collapse day"].tap()
        XCTAssertTrue(app.otherElements["month-grid"].exists)
    }

    func testCreateBasicEventInDemoMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["New Event"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Dentist")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Dentist"].waitForExistence(timeout: 3))
    }

    func testRetryUsesEditedEventDraftAfterFailOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-event-save-fails-once"]
        app.launch()
        app.buttons["New Event"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Dentist")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 3))
        title.tap()
        for _ in 0..<7 { title.typeText(XCUIKeyboardKey.delete.rawValue) }
        title.typeText("Dentist Updated")
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["Dentist Updated"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Dentist"].exists)
    }

    func testTodayTabShowsDemoAgenda() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Coffee"].exists)
        XCTAssertTrue(app.staticTexts["Buy milk"].exists)
        XCTAssertTrue(app.staticTexts["Read"].exists)
    }

    func testTodayShowsCalendarPermissionWhileRemainingAgendaStaysVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-denied"]
        app.launch()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Calendar events are unavailable"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open System Settings"].exists)
        XCTAssertTrue(app.staticTexts["Buy milk"].exists)
        XCTAssertTrue(app.staticTexts["Read"].exists)
    }

    func testTodayTaskCompletionCanBeUndone() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Today"].tap()
        let complete = app.buttons["Mark Buy milk complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()
        XCTAssertTrue(app.buttons["Undo completion for Buy milk"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Buy milk"].exists)
        app.buttons["Undo completion for Buy milk"].tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Mark Buy milk complete"].exists)
    }

    func testCreateTaskAndCompleteRoutineInDemoMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["New Task"].tap()
        let title = app.textFields["Task title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap(); title.typeText("Call Alex")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Call Alex"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Routines"].tap()
        let complete = app.buttons["Mark Read complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertTrue(app.staticTexts["1 day streak"].exists)
        XCTAssertTrue(app.otherElements["14-day history"].exists)
    }

    func testEditedTaskRetryAfterDemoFailOnceCreatesOnlyEditedTask() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-task-save-fails-once"]; app.launch()
        app.tabBars.buttons["Tasks"].tap(); app.buttons["New Task"].tap()
        let title = app.textFields["Task title"]; XCTAssertTrue(title.waitForExistence(timeout: 3)); title.tap(); title.typeText("First")
        app.buttons["Save"].tap(); XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 3))
        title.tap(); for _ in 0..<5 { title.typeText(XCUIKeyboardKey.delete.rawValue) }; title.typeText("Edited")
        app.buttons["Retry"].tap(); XCTAssertTrue(app.staticTexts["Edited"].waitForExistence(timeout: 3)); XCTAssertFalse(app.staticTexts["First"].exists)
    }

    func testRoutineDeleteCancelPreservesThenConfirmRemoves() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.tabBars.buttons["Routines"].tap()
        XCTAssertTrue(app.staticTexts["Read"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap(); XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3)); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Read"].exists)
        app.buttons["Delete"].tap(); XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3)); app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["Read"].waitForExistence(timeout: 1))
    }

    func testRoutineDeleteRetryRequiresSecondConfirmation() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-routine-delete-fails-once"]; app.launch(); app.tabBars.buttons["Routines"].tap()
        app.buttons["Delete"].tap(); app.buttons["Delete"].tap(); XCTAssertTrue(app.staticTexts["Read"].exists)
        XCTAssertTrue(app.buttons["Retry Delete"].waitForExistence(timeout: 3)); app.buttons["Retry Delete"].tap(); XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3)); XCTAssertTrue(app.staticTexts["Read"].exists)
        app.buttons["Delete"].tap(); XCTAssertFalse(app.staticTexts["Read"].waitForExistence(timeout: 1))
    }
}
