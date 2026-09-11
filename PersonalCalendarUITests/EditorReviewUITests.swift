import XCTest

/// Regression coverage for editor controls whose state is otherwise easy to
/// lose between a system confirmation dialog and an in-place recurrence edit.
@MainActor
final class EditorReviewUITests: XCTestCase {
    func testQuickEntryBackThenReviewPreservesCorrectedTitleWhenInputIsUnchanged() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-quick-entry-fixed-context"]
        app.launch()

        let add = app.buttons["universal-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        let input = app.textFields["quick-entry-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("Dentist today at 3pm")
        dismissKeyboard(in: app)
        app.buttons["quick-entry-parse"].tap()

        let title = app.textFields["quick-entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replaceText(title, with: "Dentist follow-up")
        dismissKeyboard(in: app)
        app.buttons["quick-entry-back"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "Dentist today at 3pm")

        app.buttons["quick-entry-parse"].tap()

        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "Dentist follow-up")
    }

    func testCancellingEventConfirmationLeavesEditorReadyForAnotherDeleteRequest() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        expandDay(in: app)
        app.buttons["agenda-open-event-demo-event"].tap()
        let delete = app.buttons["event-editor-delete"]
        scrollToHittable(delete, in: app)
        delete.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "event-editor-confirm-delete").firstMatch.waitForExistence(timeout: 3))

        app.buttons.matching(identifier: "event-editor-confirm-cancel").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
        scrollToHittable(delete, in: app)
        delete.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "event-editor-confirm-delete").firstMatch.waitForExistence(timeout: 3))
    }

    func testAffirmativeEventDeleteCommitsExactlyOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        expandDay(in: app)
        let open = app.buttons["agenda-open-event-demo-event"]
        open.tap()
        let delete = app.buttons["event-editor-delete"]
        scrollToHittable(delete, in: app)
        delete.tap()
        app.buttons.matching(identifier: "event-editor-confirm-delete").firstMatch.tap()
        waitForDisappearance(open)
        XCTAssertFalse(open.exists)
    }

    func testEventWeeklyCustomRuleClearsWeekdaysAfterChangingFrequencyAndSaving() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-editor-recurring"]
        app.launch()
        expandDay(in: app)

        app.buttons["agenda-open-event-demo-event-recurring"].tap()
        app.revealEditorOptions("event")
        let repeatChoice = app.descendants(matching: .any)["event-editor-recurrence-intent"]
        scrollToHittable(repeatChoice, in: app)
        repeatChoice.tap()
        app.buttons["Custom"].tap()
        let frequency = app.descendants(matching: .any)["event-editor-recurrence-frequency"]
        scrollToHittable(frequency, in: app)
        frequency.tap()
        app.buttons["Daily"].tap()
        XCTAssertFalse(app.switches["event-editor-recurrence-weekday-2"].exists)

        app.buttons["event-editor-save"].tap()
        app.buttons.matching(identifier: "event-editor-confirm-save").firstMatch.tap()
        XCTAssertTrue(app.buttons["agenda-open-event-demo-event-recurring"].waitForExistence(timeout: 3))
    }

    func testEventIntervalAboveNinetyNineIsEditableAndRoundTrips() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-editor-recurring"]
        app.launch()
        expandDay(in: app)

        app.buttons["agenda-open-event-demo-event-recurring"].tap()
        app.revealEditorOptions("event")
        let repeatChoice = app.descendants(matching: .any)["event-editor-recurrence-intent"]
        scrollToHittable(repeatChoice, in: app)
        repeatChoice.tap()
        app.buttons["Custom"].tap()
        let interval = app.textFields["event-editor-recurrence-interval"]
        scrollToHittable(interval, in: app)
        replaceText(interval, with: "120")
        XCTAssertEqual(interval.value as? String, "120")
        dismissKeyboard(in: app)

        app.buttons["event-editor-save"].tap()
        confirmEventSaveIfPresented(in: app)
        let recurringEvent = app.buttons["agenda-open-event-demo-event-recurring"]
        XCTAssertTrue(recurringEvent.waitForExistence(timeout: 3))

        recurringEvent.tap()
        app.revealEditorOptions("event")
        let reopenedRepeatChoice = app.descendants(matching: .any)["event-editor-recurrence-intent"]
        scrollToHittable(reopenedRepeatChoice, in: app)
        reopenedRepeatChoice.tap()
        app.buttons["Custom"].tap()
        let reopenedInterval = app.textFields["event-editor-recurrence-interval"]
        scrollToHittable(reopenedInterval, in: app)
        XCTAssertEqual(reopenedInterval.value as? String, "120")
    }

    func testTaskEndRepeatSeedsAtOrAfterItsEffectiveDueDate() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-editor-recurring"]
        app.launch()
        app.buttons["Expand day"].tap()
        app.buttons["agenda-open-task-demo-task-recurring"].tap()
        app.revealEditorOptions("task")

        let repeatChoice = app.descendants(matching: .any)["task-editor-recurrence-intent"]
        scrollToHittable(repeatChoice, in: app)
        repeatChoice.tap()
        app.buttons["Custom"].tap()
        let endToggle = app.switches["task-editor-recurrence-end-toggle"]
        scrollToHittable(endToggle, in: app)
        let endDate = app.datePickers["task-editor-recurrence-end-date"]
        tapSwitch(endToggle)
        waitForSwitch(endToggle, isOn: false)
        waitForDisappearance(endDate)
        tapSwitch(endToggle)
        waitForSwitch(endToggle, isOn: true)
        scrollToHittable(endDate, in: app)
        let expectedDate = Date.now.formatted(date: .abbreviated, time: .omitted)
        XCTAssertEqual(endDate.value as? String, expectedDate)
    }

    private func tapSwitch(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func expandDay(in app: XCUIApplication) {
        let expand = app.buttons["Expand day"]
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        scrollToHittable(expand, in: app)
        expand.tap()
    }

    private func waitForSwitch(_ element: XCUIElement, isOn: Bool, timeout: TimeInterval = 3) {
        let acceptedValues = isOn ? Set(["1", "On"]) : Set(["0", "Off"])
        let predicate = NSPredicate { object, _ in
            guard let control = object as? XCUIElement else { return false }
            return acceptedValues.contains(String(describing: control.value ?? ""))
        }
        let switchExpectation = expectation(for: predicate, evaluatedWith: element)
        wait(for: [switchExpectation], timeout: timeout)
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) {
        let expectation = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected \(element) to be reachable and hittable", file: file, line: line)
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        for _ in current { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        field.typeText(text)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.keyboards.buttons["Done"]
        if done.exists { done.tap(); return }
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() }
    }

    private func confirmEventSaveIfPresented(in app: XCUIApplication) {
        let confirmation = app.buttons.matching(identifier: "event-editor-confirm-save").firstMatch
        if confirmation.waitForExistence(timeout: 1) {
            scrollToHittable(confirmation, in: app)
            confirmation.tap()
        }
    }
}
