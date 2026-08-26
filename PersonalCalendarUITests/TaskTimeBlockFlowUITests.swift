import XCTest

@MainActor
final class TaskTimeBlockFlowUITests: XCTestCase {
    func testSchoolTaskCanBeScheduledWithoutRemovingTheReminder() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()

        let task = app.buttons["task-open-demo-school-task"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        task.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 3))
        let schedule = app.buttons["task-editor-schedule-time"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 3))
        schedule.tap()

        let form = app.descendants(matching: .any)["time-block-form"]
        XCTAssertTrue(form.waitForExistence(timeout: 3))
        let save = app.buttons["time-block-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 5))
        XCTAssertFalse(form.exists)
        app.buttons["task-editor-cancel"].tap()
        XCTAssertTrue(app.buttons["task-open-demo-school-task"].waitForExistence(timeout: 5))
    }
}
