import XCTest

/// Runs only against the existing -ui-testing demo environment and its Noop activity driver.
/// These smoke tests do not create a system Live Activity or use real provider data.
@MainActor
final class DailyLiveActivityUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTimetableSettingsShowsDailyControlsAndHonestUpdateLimits() {
        let app = launchIsolatedApp()
        openTimetable(in: app)

        let dailyHeading = app.staticTexts.matching(
            NSPredicate(format: "label ==[c] %@", "Daily Live Activity")
        ).firstMatch
        XCTAssertTrue(dailyHeading.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["timetable-profile"].exists)
        XCTAssertTrue(app.switches["timetable-auto-start"].exists)
        XCTAssertTrue(app.buttons["timetable-refresh"].exists)
        XCTAssertTrue(app.buttons["timetable-start"].exists)
        XCTAssertFalse(app.buttons["timetable-stop"].exists)

        let contentExplanation = text(containing: "incomplete tasks due today", in: app)
        scrollToHittable(contentExplanation, in: app)
        XCTAssertTrue(contentExplanation.label.contains("Weekly Home Screen widgets stay unchanged"))

        let freshnessExplanation = text(containing: "last app refresh", in: app)
        scrollToHittable(freshnessExplanation, in: app)
        XCTAssertTrue(freshnessExplanation.label.contains("not an always-current all-day service"))

        let durationExplanation = text(containing: "up to eight active hours", in: app)
        scrollToHittable(durationExplanation, in: app)
        XCTAssertTrue(durationExplanation.label.contains("up to four more hours"))
        XCTAssertTrue(durationExplanation.label.contains("cannot renew itself while the app is suspended"))
    }

    func testDailyProfilePickerRetainsSelectedSavedProfileWhenSettingsReopen() {
        // Existing deterministic demo profiles include School and Personal; no task-only
        // membership fixture is assumed or fabricated by this UI test.
        let app = launchIsolatedApp(arguments: ["-demo-profiles"])
        openTimetable(in: app)
        chooseDailyProfile("School", in: app)
        closeSettings(in: app)

        openTimetable(in: app)
        assertPickerValue("School", in: app)
        chooseDailyProfile("Personal", in: app)
        closeSettings(in: app)

        openTimetable(in: app)
        assertPickerValue("Personal", in: app)
        XCTAssertFalse(app.buttons["timetable-stop"].exists)
    }

    func testAutomaticPreferencePersistsButNoopDriverNeverShowsRunningOrStop() {
        // Ordinary demo launch resets profile migration for the in-memory model while
        // retaining this isolated settings suite, matching UsabilityStartupUITests.
        let app = launchIsolatedApp()
        openTimetable(in: app)
        chooseDailyProfile("Everything", in: app)
        let automatic = app.switches["timetable-auto-start"]
        assertSwitch(automatic, hasValue: "0")
        automatic.tap()
        assertSwitch(automatic, hasValue: "1")

        let disabled = app.staticTexts["Live Activities are disabled."]
        XCTAssertTrue(disabled.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["timetable-stop"].exists)
        XCTAssertFalse(text(containing: "is active on the Lock Screen", in: app).exists)

        app.terminate()
        app.launch()
        openTimetable(in: app)
        assertPickerValue("Everything", in: app)
        let persistedAutomatic = app.switches["timetable-auto-start"]
        assertSwitch(persistedAutomatic, hasValue: "1")
        XCTAssertFalse(app.buttons["timetable-stop"].exists)
        persistedAutomatic.tap()
        assertSwitch(persistedAutomatic, hasValue: "0")

        app.terminate()
        app.launch()
        openTimetable(in: app)
        assertSwitch(app.switches["timetable-auto-start"], hasValue: "0")
        XCTAssertFalse(app.buttons["timetable-stop"].exists)
        XCTAssertFalse(text(containing: "is active on the Lock Screen", in: app).exists)
    }

    private func launchIsolatedApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launchEnvironment["UI_TEST_SETTINGS_SUITE"] = "PersonalCalendarUITests.\(UUID().uuidString)"
        app.launch()
        XCTAssertTrue(app.buttons["calendar-settings-open"].waitForExistence(timeout: 5))
        return app
    }

    private func openTimetable(in app: XCUIApplication) {
        let settings = app.buttons["calendar-settings-open"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let timetable = app.buttons["settings-school-timetable"]
        scrollToHittable(timetable, in: app)
        timetable.tap()
        XCTAssertTrue(app.navigationBars["Timetable"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["timetable-profile"].waitForExistence(timeout: 3))
    }

    private func chooseDailyProfile(_ name: String, in app: XCUIApplication) {
        let picker = app.buttons["timetable-profile"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        let option = app.buttons[name].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        assertPickerValue(name, in: app)
    }

    private func assertPickerValue(_ name: String, in app: XCUIApplication) {
        let selected = expectation(
            for: NSPredicate(format: "value == %@ OR label CONTAINS %@", name, name),
            evaluatedWith: app.buttons["timetable-profile"]
        )
        wait(for: [selected], timeout: 3)
    }

    private func assertSwitch(_ element: XCUIElement, hasValue value: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let changed = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        wait(for: [changed], timeout: 3)
    }

    private func closeSettings(in app: XCUIApplication) {
        let back = app.navigationBars["Timetable"].buttons["Settings"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        let done = app.buttons["settings-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertTrue(app.buttons["calendar-settings-open"].waitForExistence(timeout: 3))
    }

    private func text(containing value: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected the daily settings element to remain reachable")
    }
}
