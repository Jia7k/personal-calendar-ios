import XCTest

@MainActor
final class UsabilityFormsUITests: XCTestCase {
    func testNewEventShowsEssentialsAndRevealsOptionalEditorsOnRequest() {
        let app = launch()
        expandDay(in: app)

        app.buttons["agenda-open-event-demo-event"].tap()
        let duplicate = app.buttons["event-editor-duplicate"]
        scrollToHittable(duplicate, in: app)
        duplicate.tap()
        XCTAssertTrue(app.navigationBars["Duplicate Event"].waitForExistence(timeout: 3))
        app.buttons["event-duplicate-review"].tap()

        XCTAssertTrue(app.navigationBars["New Event"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["event-editor-title"].exists)
        XCTAssertTrue(app.switches["event-editor-all-day"].exists)
        XCTAssertTrue(app.datePickers["event-editor-start"].exists)
        XCTAssertTrue(app.datePickers["event-editor-end"].exists)
        XCTAssertTrue(app.textFields["event-editor-location"].exists)
        XCTAssertFalse(app.textFields["event-editor-notes"].exists)
        XCTAssertFalse(app.textFields["event-editor-url"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["event-editor-alarm-intent"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["event-editor-recurrence-intent"].exists)

        let optionsButtons = app.buttons.matching(identifier: "event-editor-more-options")
        var visibleOptions = optionsButtons.allElementsBoundByIndex.first { $0.isHittable }
        for _ in 0..<6 where visibleOptions == nil {
            app.swipeUp()
            visibleOptions = optionsButtons.allElementsBoundByIndex.first { $0.isHittable }
        }
        guard let moreOptions = visibleOptions else {
            XCTFail("New Event must have a reachable More options control")
            return
        }
        XCTAssertEqual(moreOptions.value as? String, "Collapsed")
        attachScreenshot(named: "New event — essentials", of: app)
        moreOptions.tap()

        XCTAssertEqual(moreOptions.value as? String, "Expanded")
        scrollToExistence(
            app.descendants(matching: .any)["event-editor-alarm-intent"],
            in: app
        )
        scrollToExistence(
            app.descendants(matching: .any)["event-editor-recurrence-intent"],
            in: app
        )
    }

    func testRecurringEventSummaryAndProviderSettingsSurviveTitleOnlySave() {
        let app = launch(["-demo-editor-recurring"])
        expandDay(in: app)

        let recurringEvent = app.buttons["agenda-open-event-demo-event-recurring"]
        scrollToHittable(recurringEvent, in: app)
        recurringEvent.tap()

        let summary = app.staticTexts["event-editor-options-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("Calendar: Personal"))
        XCTAssertTrue(summary.label.contains("2 alerts"))
        XCTAssertTrue(summary.label.contains("Every 2 weeks"))
        XCTAssertFalse(app.descendants(matching: .any)["event-editor-alarm-intent"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["event-editor-recurrence-intent"].exists)

        replaceText(app.textFields["event-editor-title"], with: "Updated planning")
        dismissKeyboard(in: app)
        app.buttons["event-editor-save"].tap()
        let confirm = app.buttons.matching(identifier: "event-editor-confirm-save").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        XCTAssertTrue(recurringEvent.waitForExistence(timeout: 3))
        recurringEvent.tap()
        let reopenedSummary = app.staticTexts["event-editor-options-summary"]
        XCTAssertTrue(reopenedSummary.waitForExistence(timeout: 3))
        XCTAssertTrue(reopenedSummary.label.contains("2 alerts"))
        XCTAssertTrue(reopenedSummary.label.contains("Every 2 weeks"))
    }

    func testUndatedTaskKeepsDueDateEssentialAndOptionalEditorsCollapsed() {
        let app = launch(["-demo-daily-task-rescue"])
        app.tabBars.buttons["Tasks"].tap()

        let undatedTask = app.buttons["task-open-demo-undated-task"]
        XCTAssertTrue(undatedTask.waitForExistence(timeout: 3))
        undatedTask.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 3))

        let dueChoice = app.descendants(matching: .any)["task-editor-schedule-intent"]
        XCTAssertTrue(dueChoice.waitForExistence(timeout: 3))
        XCTAssertFalse(app.datePickers["task-editor-due-date"].exists)
        XCTAssertFalse(app.textFields["task-editor-notes"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["task-editor-priority"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["task-editor-alarm-intent"].exists)

        let moreOptions = app.buttons["task-editor-more-options"]
        XCTAssertTrue(moreOptions.waitForExistence(timeout: 3))
        attachScreenshot(named: "Undated task — essentials", of: app)
        moreOptions.tap()
        scrollToExistence(
            app.descendants(matching: .any)["task-editor-alarm-intent"],
            in: app
        )
        scrollBackToHittable(
            app.descendants(matching: .any)["task-editor-priority"],
            in: app
        )
        scrollBackToHittable(dueChoice, in: app)
        XCTAssertFalse(app.datePickers["task-editor-due-date"].exists)
    }

    func testCollapsedInvalidTaskExplainsAndRevealsRepeatForRepair() {
        let app = launch(["-demo-daily-task-rescue"])
        app.tabBars.buttons["Tasks"].tap()
        app.buttons["task-open-demo-undated-task"].tap()

        let moreOptions = app.buttons["task-editor-more-options"]
        XCTAssertTrue(moreOptions.waitForExistence(timeout: 3))
        moreOptions.tap()
        let repeatChoice = app.descendants(matching: .any)["task-editor-recurrence-intent"]
        scrollToHittable(repeatChoice, in: app)
        repeatChoice.tap()
        app.buttons["Custom"].tap()
        XCTAssertFalse(app.buttons["task-editor-save"].isEnabled)

        scrollBackToHittable(moreOptions, in: app)
        moreOptions.tap()
        XCTAssertEqual(moreOptions.value as? String, "Collapsed")

        let explanation = app.staticTexts["task-editor-preflight-message"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 3))
        XCTAssertTrue(explanation.label.contains("repeating task needs a due date"))
        let reveal = app.buttons["task-editor-show-invalid-options"]
        scrollToHittable(reveal, in: app)
        reveal.tap()

        XCTAssertEqual(moreOptions.value as? String, "Expanded")
        scrollToHittable(repeatChoice, in: app)
        repeatChoice.tap()
        app.buttons["Never"].tap()
        XCTAssertTrue(app.buttons["task-editor-save"].isEnabled)
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        return app
    }

    private func expandDay(in app: XCUIApplication) {
        let expand = app.buttons["Expand day"]
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        scrollToHittable(expand, in: app)
        expand.tap()
    }

    private func scrollToExistence(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 where !element.exists { app.swipeUp() }
        XCTAssertTrue(element.exists, "Expected \(element) to be reachable", file: file, line: line)
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected \(element) to be hittable", file: file, line: line)
    }

    private func scrollBackToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 where !element.isHittable { app.swipeDown() }
        XCTAssertTrue(element.isHittable, "Expected \(element) to be hittable", file: file, line: line)
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        let current = field.value as? String ?? ""
        for _ in current { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        field.typeText(text)
    }

    private func attachScreenshot(named name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.keyboards.buttons["Done"]
        if done.exists { done.tap(); return }
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() }
    }
}
