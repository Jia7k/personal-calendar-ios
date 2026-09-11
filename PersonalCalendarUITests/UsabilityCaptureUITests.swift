import XCTest

@MainActor
final class UsabilityCaptureUITests: XCTestCase {
    func testBlankAddAutofocusesAndKeyboardContinueOpensReview() {
        let app = launch()
        openQuickEntry(in: app)

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let input = app.textFields["quick-entry-input"]
        input.typeText("Submit report tomorrow")
        let continueButton = continueButton(in: app)
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertTrue(continueButton.isHittable)

        continueButton.tap()

        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["quick-entry-save"].isEnabled)
    }

    func testAddAnotherAcceptsASecondTaskWithoutReplayingTheFirst() {
        let app = launch()
        openQuickEntry(in: app)
        enterAndReview("First capture tomorrow", in: app)
        selectTask(in: app)
        replaceText(app.textFields["quick-entry-title"], with: "First captured task")
        app.buttons["quick-entry-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quick-entry-saved"].waitForExistence(timeout: 3))

        let addAnother = app.buttons["quick-entry-add-another"]
        XCTAssertTrue(addAnother.waitForExistence(timeout: 3))
        addAnother.tap()
        let input = app.textFields["quick-entry-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "Describe what you want to add")
        enterAndReview("Second capture tomorrow", in: app)
        selectTask(in: app)
        replaceText(app.textFields["quick-entry-title"], with: "Second captured task")
        app.buttons["quick-entry-save"].tap()

        let saved = app.descendants(matching: .any)["quick-entry-saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 3))
        XCTAssertEqual(saved.label, "Task saved")
        XCTAssertFalse(app.textFields["quick-entry-title"].exists)
    }

    func testSaveDraftAndResumeAcrossLaunchPreserveTitleAndRemovedDueDate() {
        let suite = "PersonalCalendarUITests.UsabilityCapture.\(UUID().uuidString)"
        var app = launch(settingsSuite: suite)
        openQuickEntry(in: app)
        enterAndReview("Submit report tomorrow", in: app)
        selectTask(in: app)
        replaceText(app.textFields["quick-entry-title"], with: "Corrected report title")
        let dueToggle = app.switches["quick-entry-task-due-enabled"]
        XCTAssertTrue(dueToggle.waitForExistence(timeout: 3))
        tapSwitch(dueToggle)
        waitForSwitch(dueToggle, isOn: false)
        app.buttons["quick-entry-back"].tap()
        saveDraftAndDismiss(in: app)
        app.terminate()

        app = launch(settingsSuite: suite)
        openQuickEntry(in: app)
        XCTAssertTrue(app.otherElements["quick-entry-draft-recovery"].waitForExistence(timeout: 3))
        app.buttons["quick-entry-draft-resume"].tap()
        XCTAssertEqual(app.textFields["quick-entry-input"].value as? String, "Submit report tomorrow")
        app.buttons["quick-entry-parse"].tap()

        XCTAssertEqual(app.textFields["quick-entry-title"].value as? String, "Corrected report title")
        XCTAssertEqual(app.switches["quick-entry-task-due-enabled"].value as? String, "0")
    }

    func testExplicitDraftDiscardRemovesRecoveryPrompt() {
        let app = launch()
        openQuickEntry(in: app)
        app.textFields["quick-entry-input"].typeText("Draft to discard")
        saveDraftAndDismiss(in: app)
        openQuickEntry(in: app)
        let recovery = app.otherElements["quick-entry-draft-recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 3))

        app.buttons["quick-entry-draft-discard"].tap()

        XCTAssertFalse(recovery.exists)
        XCTAssertEqual(
            app.textFields["quick-entry-input"].value as? String,
            "Describe what you want to add"
        )
        app.buttons["quick-entry-cancel"].tap()
        openQuickEntry(in: app)
        XCTAssertFalse(recovery.exists, "Discarded text must not reappear as another checkpoint.")
    }

    func testDirectQuickEntryRouteCannotConsumeAnExistingCorrectedDraft() {
        let app = launch()
        openQuickEntry(in: app)
        enterAndReview("My original event tomorrow at 2pm", in: app)
        replaceText(app.textFields["quick-entry-title"], with: "My corrected local draft")
        app.buttons["quick-entry-back"].tap()
        saveDraftAndDismiss(in: app)
        app.terminate()

        app.launchArguments.append("-demo-direct-quick-entry-route")
        app.launch()
        let title = app.textFields["quick-entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "External event")
        XCTAssertTrue(app.buttons["quick-entry-save"].isEnabled)
        app.buttons["quick-entry-save"].tap()
        XCTAssertTrue(app.buttons["quick-entry-add-another"].waitForExistence(timeout: 3))
        app.buttons["quick-entry-add-another"].tap()

        let resume = app.buttons["quick-entry-draft-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        resume.tap()
        app.buttons["quick-entry-parse"].tap()
        XCTAssertEqual(title.value as? String, "My corrected local draft")
    }

    private func launch(settingsSuite: String = "PersonalCalendarUITests.UsabilityCapture.\(UUID().uuidString)") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-quick-entry-fixed-context"]
        app.launchEnvironment["UI_TEST_SETTINGS_SUITE"] = settingsSuite
        app.launch()
        return app
    }

    private func openQuickEntry(in app: XCUIApplication) {
        let add = app.buttons["universal-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.textFields["quick-entry-input"].waitForExistence(timeout: 3))
    }

    private func enterAndReview(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["quick-entry-input"]
        if !app.keyboards.firstMatch.exists { input.tap() }
        input.typeText(text)
        let continueButton = continueButton(in: app)
        if continueButton.waitForExistence(timeout: 2) {
            XCTAssertTrue(continueButton.isHittable)
            continueButton.tap()
        } else {
            app.buttons["quick-entry-parse"].tap()
        }
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 3))
    }

    private func selectTask(in app: XCUIApplication) {
        let task = app.buttons["quick-entry-kind-task"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        task.tap()
        XCTAssertEqual(app.descendants(matching: .any)["quick-entry-kind"].value as? String, "Task")
    }

    private func saveDraftAndDismiss(in app: XCUIApplication) {
        app.buttons["quick-entry-cancel"].tap()
        let alert = app.alerts["Discard quick entry?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let saveDraft = alert.buttons
            .matching(identifier: "quick-entry-save-draft")
            .firstMatch
        XCTAssertTrue(saveDraft.waitForExistence(timeout: 3))
        saveDraft.tap()
        XCTAssertFalse(app.textFields["quick-entry-input"].waitForExistence(timeout: 2))
    }

    private func continueButton(in app: XCUIApplication) -> XCUIElement {
        // A fresh Simulator can cover the real return key with iOS's
        // Slide to Type introduction after the first character is entered.
        let introduction = app.otherElements["UIContinuousPathIntroductionView"]
        if introduction.exists {
            introduction.buttons["Continue"].tap()
            XCTAssertTrue(introduction.waitForNonExistence(timeout: 3))
        }
        return app.keyboards.buttons.matching(
            NSPredicate(format: "label =[c] %@", "continue")
        ).firstMatch
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        for _ in current { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        field.typeText(text)
    }

    private func tapSwitch(_ element: XCUIElement) {
        element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
    }

    private func waitForSwitch(
        _ element: XCUIElement,
        isOn: Bool,
        timeout: TimeInterval = 3
    ) {
        let accepted = isOn ? Set(["1", "On"]) : Set(["0", "Off"])
        let predicate = NSPredicate { object, _ in
            guard let control = object as? XCUIElement else { return false }
            return accepted.contains(String(describing: control.value ?? ""))
        }
        let expectation = expectation(for: predicate, evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
        XCTAssertTrue(accepted.contains(String(describing: element.value ?? "")))
    }
}
