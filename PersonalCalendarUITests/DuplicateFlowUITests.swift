import XCTest

@MainActor
final class DuplicateFlowUITests: XCTestCase {
    func testSchoolTaskDuplicateWaitsForSaveThenKeepsSourceAndAddsCopy() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        chooseSchoolProfile(in: app)
        app.tabBars.buttons["Tasks"].tap()

        let source = app.buttons["task-open-demo-school-task"]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        XCTAssertEqual(taskRows(named: "Assignment 1", in: app).count, 1)
        XCTAssertFalse(app.buttons["task-open-demo-task-4"].exists)

        openDuplicateEditor(from: source, in: app)
        XCTAssertTrue(
            app.staticTexts["task-duplicate-editor-screen"]
                .waitForExistence(timeout: 3)
        )
        let moreOptions = app.descendants(matching: .any)["task-duplicate-editor-form"]
            .buttons["task-editor-more-options"]
        scrollToHittable(moreOptions, in: app)
        XCTAssertTrue(moreOptions.isHittable)
        moreOptions.tap()
        let alertChoice = app.descendants(matching: .any)[
            "task-duplicate-alarm-intent"
        ]
        let repeatChoice = app.descendants(matching: .any)[
            "task-duplicate-recurrence-intent"
        ]
        scrollToHittable(alertChoice, in: app)
        XCTAssertTrue(alertChoice.waitForExistence(timeout: 3))
        XCTAssertEqual(alertChoice.value as? String, "None")
        scrollToHittable(repeatChoice, in: app)
        XCTAssertTrue(repeatChoice.waitForExistence(timeout: 3))
        XCTAssertEqual(repeatChoice.value as? String, "Never")

        let cancelDuplicate = app.navigationBars["New Task"]
            .buttons["task-editor-cancel"]
        XCTAssertTrue(cancelDuplicate.waitForExistence(timeout: 3))
        cancelDuplicate.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 3))

        let cancelSource = app.navigationBars["Task"]
            .buttons["task-editor-cancel"]
        XCTAssertTrue(cancelSource.waitForExistence(timeout: 3))
        cancelSource.tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 3))
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        XCTAssertEqual(taskRows(named: "Assignment 1", in: app).count, 1)
        XCTAssertFalse(app.buttons["task-open-demo-task-4"].exists)

        openDuplicateEditor(from: source, in: app)
        let saveDuplicate = app.navigationBars["New Task"]
            .buttons["task-editor-save"]
        XCTAssertTrue(saveDuplicate.waitForExistence(timeout: 3))
        XCTAssertTrue(saveDuplicate.isEnabled)
        saveDuplicate.tap()

        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 3))
        let copy = app.buttons["task-open-demo-task-4"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertTrue(source.exists)
        XCTAssertEqual(taskRows(named: "Assignment 1", in: app).count, 2)
        XCTAssertEqual(copy.label, "Open task Assignment 1")
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

    private func openDuplicateEditor(
        from source: XCUIElement,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 3))

        let duplicate = app.buttons["task-editor-duplicate"]
        scrollToHittable(duplicate, in: app)
        XCTAssertTrue(duplicate.isHittable)
        duplicate.tap()

        XCTAssertTrue(app.navigationBars["New Task"].waitForExistence(timeout: 3))
    }

    private func taskRows(
        named title: String,
        in app: XCUIApplication
    ) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "label == %@", "Open task \(title)")
        )
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
    }
}
