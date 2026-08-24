import XCTest

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
        app.buttons["Expand day"].tap()

        XCTAssertTrue(app.buttons["Collapse day"].exists)
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
}
