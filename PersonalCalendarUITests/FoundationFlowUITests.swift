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
}
