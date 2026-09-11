import XCTest

@MainActor
final class UsabilityStartupUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testChosenOpeningScreenPersistsWithoutJumpingWhenSettingsClose() {
        let app = launchIsolatedApp()
        chooseOpeningScreen("Tasks", in: app)
        XCTAssertTrue(app.tabBars.buttons["Calendar"].isSelected)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Tasks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Tasks"].isSelected)
    }

    func testLastUsedOpensTheTabSelectedBeforeRelaunch() {
        let app = launchIsolatedApp()
        chooseOpeningScreen("Last Used", in: app)
        app.tabBars.buttons["Routines"].tap()
        XCTAssertTrue(app.tabBars.buttons["Routines"].isSelected)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Routines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Routines"].isSelected)
    }

    func testIncomingRouteTakesPrecedenceOverSavedOpeningScreen() {
        let app = launchIsolatedApp()
        chooseOpeningScreen("Tasks", in: app)
        app.terminate()
        app.launchArguments.append("-demo-today-route")
        app.launch()
        let today = app.tabBars.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: today)
        waitForExpectations(timeout: 5)
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UI_TEST_SETTINGS_SUITE"] = "PersonalCalendarUITests.\(UUID().uuidString)"
        app.launch()
        XCTAssertTrue(app.buttons["calendar-settings-open"].waitForExistence(timeout: 5))
        return app
    }

    private func chooseOpeningScreen(_ title: String, in app: XCUIApplication) {
        app.buttons["calendar-settings-open"].tap()
        let picker = app.buttons["settings-opening-screen"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.collectionViews.buttons[title].tap()
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 3))
    }
}
