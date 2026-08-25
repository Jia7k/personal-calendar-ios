import XCTest

/// RED contract for Task 4's root-owned, confirmed universal quick entry.
///
/// These tests intentionally address the UI only through spoken copy and stable
/// accessibility identifiers. Provider conversion, single-flight writes, and
/// exact callback counts remain unit-test responsibilities.
@MainActor
final class CompletionFlowUITests: XCTestCase {
    func testCalendarExposesTheSoleUniversalAddRoute() {
        assertSoleUniversalAdd(on: "Calendar")
    }

    func testTodayExposesTheSoleUniversalAddRoute() {
        assertSoleUniversalAdd(on: "Today")
    }

    func testTasksExposesTheSoleUniversalAddRoute() {
        assertSoleUniversalAdd(on: "Tasks")
    }

    func testRoutinesExposesTheSoleUniversalAddRoute() {
        assertSoleUniversalAdd(on: "Routines")
    }

    func testUniversalAddIsAbsentDuringOnboardingAndAppearsAfterCompletion() {
        let app = launch([
            "-show-onboarding",
            "-calendar-not-determined",
            "-reminders-not-determined",
            "-notifications-not-determined"
        ])

        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["universal-add"].exists)
        app.buttons["onboarding-not-now"].tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["universal-add"].exists)
        app.buttons["onboarding-not-now"].tap()
        XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["universal-add"].exists)
        app.buttons["onboarding-not-now"].tap()

        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 3))
        let add = app.buttons["universal-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertEqual(add.label, "Add event, task, or routine")
    }

    func testEventCanBeCorrectedSavedAndDismissedOnlyWithDone() {
        let app = launch()
        parse("Dentist today at 3pm", in: app)
        assertKind("Event", in: app)

        let title = app.textFields["quick-entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replaceText(title, with: "Dentist appointment")
        dismissKeyboard(in: app)
        assertCategoryNone(in: app)
        app.buttons["quick-entry-save"].tap()

        assertSaved("Event saved", in: app)
        app.buttons["quick-entry-done"].tap()
        waitForDisappearance(app.descendants(matching: .any)["quick-entry-saved"])
        app.buttons["Expand day"].tap()
        let created = app.buttons["agenda-open-event-demo-event-2"]
        XCTAssertTrue(created.waitForExistence(timeout: 3))
        XCTAssertEqual(created.label, "Event, Dentist appointment, 15:00, Not completed")
        XCTAssertEqual(app.buttons.matching(identifier: "agenda-open-event-demo-event-2").count, 1)
    }

    func testTaskCanBeCorrectedSavedAndDismissedOnlyWithDone() {
        let app = launch()
        app.tabBars.buttons["Tasks"].tap()
        parse("Submit report tomorrow", in: app)
        assertKind("Task", in: app)

        let title = app.textFields["quick-entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replaceText(title, with: "Submit final report")
        dismissKeyboard(in: app)
        assertCategoryNone(in: app)
        app.buttons["quick-entry-save"].tap()

        assertSaved("Task saved", in: app)
        app.buttons["quick-entry-done"].tap()
        let created = app.buttons["task-open-demo-task-2"]
        XCTAssertTrue(created.waitForExistence(timeout: 3))
        XCTAssertEqual(created.label, "Open task Submit final report")
        XCTAssertEqual(app.buttons.matching(identifier: "task-open-demo-task-2").count, 1)
    }

    func testRoutineCanBeCorrectedSavedAnnouncedAndSeenAfterDone() {
        let app = launch()
        app.tabBars.buttons["Routines"].tap()
        parse("Read every night", in: app)
        assertKind("Routine", in: app)

        let title = app.textFields["quick-entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replaceText(title, with: "Read poetry")
        dismissKeyboard(in: app)
        assertCategoryNone(in: app)
        app.buttons["quick-entry-save"].tap()

        assertSaved("Routine saved", in: app)
        app.buttons["quick-entry-done"].tap()
        let created = app.staticTexts.matching(NSPredicate(format: "label == %@", "Read poetry"))
        XCTAssertTrue(created.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(created.count, 1)
    }

    func testEventFailOnceRetainsLatestEditAndRetryCreatesExactlyOneEvent() {
        let app = launch(["-event-save-fails-once"])
        parse("Dentist today at 3pm", in: app)
        assertKind("Event", in: app)
        let title = app.textFields["quick-entry-title"]
        replaceText(title, with: "First dentist draft")
        dismissKeyboard(in: app)
        app.buttons["quick-entry-save"].tap()

        assertSaveFailure("Your event was not saved. Edit it and try again.", in: app)
        XCTAssertEqual(title.value as? String, "First dentist draft")
        replaceText(title, with: "Dentist retry")
        dismissKeyboard(in: app)
        app.buttons["quick-entry-retry"].tap()

        assertSaved("Event saved", in: app)
        app.buttons["quick-entry-done"].tap()
        app.buttons["Expand day"].tap()
        let created = app.buttons["agenda-open-event-demo-event-2"]
        XCTAssertTrue(created.waitForExistence(timeout: 3))
        XCTAssertEqual(created.label, "Event, Dentist retry, 15:00, Not completed")
        XCTAssertEqual(app.buttons.matching(identifier: "agenda-open-event-demo-event-2").count, 1)
        XCTAssertFalse(app.staticTexts["First dentist draft"].exists)
    }

    func testTaskFailOnceRetainsLatestEditAndRetryCreatesExactlyOneTask() {
        let app = launch(["-task-save-fails-once"])
        app.tabBars.buttons["Tasks"].tap()
        parse("Call Alex", in: app)
        assertKind("Task", in: app)
        let title = app.textFields["quick-entry-title"]
        replaceText(title, with: "First call draft")
        dismissKeyboard(in: app)
        app.buttons["quick-entry-save"].tap()

        assertSaveFailure("Your task was not saved. Edit it and try again.", in: app)
        XCTAssertEqual(title.value as? String, "First call draft")
        replaceText(title, with: "Call Alex retry")
        dismissKeyboard(in: app)
        app.buttons["quick-entry-retry"].tap()

        assertSaved("Task saved", in: app)
        app.buttons["quick-entry-done"].tap()
        let created = app.buttons["task-open-demo-task-2"]
        XCTAssertTrue(created.waitForExistence(timeout: 3))
        XCTAssertEqual(created.label, "Open task Call Alex retry")
        XCTAssertEqual(app.buttons.matching(identifier: "task-open-demo-task-2").count, 1)
        XCTAssertFalse(app.staticTexts["First call draft"].exists)
    }

    func testRoutineFailOnceRetainsEveryEditedFieldAndRetryCreatesExactlyOneRoutine() {
        let app = launch(["-routine-create-fails-once"])
        app.tabBars.buttons["Routines"].tap()
        parse("Read every night", in: app)
        assertKind("Routine", in: app)

        let title = app.textFields["quick-entry-title"]
        replaceText(title, with: "Stretch gently")
        dismissKeyboard(in: app)
        selectRoutineWindow("Morning", in: app)
        let sunday = app.buttons["quick-entry-routine-weekday-1"]
        XCTAssertTrue(sunday.waitForExistence(timeout: 3))
        sunday.tap()
        waitForValue("Not selected", on: sunday)
        let reminder = app.switches["quick-entry-reminder-enabled"]
        scrollToHittable(reminder, in: app)
        tapSwitch(reminder)
        waitForSwitch(reminder, isOn: true)
        scrollToExistence(app.datePickers["quick-entry-reminder-date"], in: app)
        let save = app.buttons["quick-entry-save"]
        scrollToHittable(save, in: app)
        save.tap()

        assertSaveFailure("Your routine was not saved. Edit it and try again.", in: app)
        let retainedTitle = app.textFields["quick-entry-title"]
        scrollTowardTopToHittable(retainedTitle, in: app)
        XCTAssertEqual(retainedTitle.value as? String, "Stretch gently")
        let retainedWindow = app.descendants(matching: .any)["quick-entry-routine-window"]
        scrollToExistence(retainedWindow, in: app)
        waitForValue("Morning", on: retainedWindow)
        let retainedSunday = app.buttons["quick-entry-routine-weekday-1"]
        scrollToExistence(retainedSunday, in: app)
        waitForValue("Not selected", on: retainedSunday)
        let retainedReminder = app.switches["quick-entry-reminder-enabled"]
        scrollToHittable(retainedReminder, in: app)
        waitForSwitch(retainedReminder, isOn: true)
        scrollToExistence(app.datePickers["quick-entry-reminder-date"], in: app)
        scrollTowardTopToHittable(retainedTitle, in: app)
        replaceText(retainedTitle, with: "Stretch gently retry")
        dismissKeyboard(in: app)
        let retry = app.buttons["quick-entry-retry"]
        scrollToHittable(retry, in: app)
        retry.tap()

        assertSaved("Routine saved", in: app)
        app.buttons["quick-entry-done"].tap()
        let created = app.staticTexts.matching(NSPredicate(format: "label == %@", "Stretch gently retry"))
        XCTAssertTrue(created.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(created.count, 1)
        XCTAssertFalse(app.staticTexts["Stretch gently"].exists)
    }

    func testDeniedEventAndTaskExplainUnavailabilityButCanSwitchToRoutine() {
        let app = launch(["-calendar-denied", "-reminders-denied"])
        parse("Dentist today at 3pm", in: app)
        assertKind("Event", in: app)
        let save = app.buttons["quick-entry-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertFalse(save.isEnabled)
        assertSourceExplanation(
            "Calendar access is unavailable. Choose Task or Routine, or enable Calendar access in Settings.",
            in: app
        )

        selectKind("Task", in: app)
        XCTAssertFalse(save.isEnabled)
        assertSourceExplanation(
            "Reminders access is unavailable. Choose Event or Routine, or enable Reminders access in Settings.",
            in: app
        )

        selectKind("Routine", in: app)
        XCTAssertTrue(save.isEnabled)
        waitForDisappearance(app.descendants(matching: .any)["quick-entry-source-explanation"])
        save.tap()
        assertSaved("Routine saved", in: app)
        app.buttons["quick-entry-done"].tap()
        app.tabBars.buttons["Routines"].tap()
        XCTAssertTrue(app.staticTexts["Dentist"].waitForExistence(timeout: 3))
    }

    func testConfirmationOffersEveryWritableDestinationAndNoReadOnlyDestination() {
        let app = launch(["-demo-multiple-sources", "-demo-editor-read-only"])
        parse("Planning today at 3pm", in: app)
        assertKind("Event", in: app)

        let destination = app.descendants(matching: .any)["quick-entry-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        destination.tap()
        XCTAssertTrue(app.buttons["quick-entry-destination-system-default"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["quick-entry-destination-demo-calendar"].exists)
        XCTAssertTrue(app.buttons["quick-entry-destination-demo-calendar-work"].exists)
        XCTAssertFalse(app.buttons["quick-entry-destination-demo-calendar-read-only"].exists)
        app.buttons["quick-entry-destination-demo-calendar-work"].tap()
        waitForValue("Work", on: destination)

        selectKind("Task", in: app)
        destination.tap()
        XCTAssertTrue(app.buttons["quick-entry-destination-system-default"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["quick-entry-destination-demo-list"].exists)
        XCTAssertTrue(app.buttons["quick-entry-destination-demo-list-alternate"].exists)
        XCTAssertFalse(app.buttons["quick-entry-destination-demo-list-read-only"].exists)
    }

    func testDirtyEntryRequiresExplicitDiscardAndNeverCreatesAnything() {
        let app = launch()
        openQuickEntry(in: app)
        let input = app.textFields["quick-entry-input"]
        input.tap()
        input.typeText("Journal privately")
        dismissKeyboard(in: app)
        app.buttons["quick-entry-cancel"].tap()

        XCTAssertTrue(app.staticTexts["Discard quick entry?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Discard"].exists)
        XCTAssertTrue(app.buttons["Keep Editing"].exists)
        app.buttons["Keep Editing"].tap()
        XCTAssertEqual(input.value as? String, "Journal privately")
        app.buttons["quick-entry-cancel"].tap()
        app.buttons["Discard"].tap()

        waitForDisappearance(input)
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertFalse(app.staticTexts["Journal privately"].exists)
    }

    func testWeeklyRecurrenceIntervalOneHundredAndAlarmRemainEditableAndSave() {
        let app = launch()
        parse("Team sync every Monday at 10am", in: app)
        assertKind("Event", in: app)

        let interval = app.textFields["quick-entry-recurrence-interval"]
        scrollToHittable(interval, in: app)
        XCTAssertEqual(interval.value as? String, "1")
        replaceText(interval, with: "100")
        dismissKeyboard(in: app)
        XCTAssertEqual(interval.value as? String, "100")
        let reminder = app.switches["quick-entry-reminder-enabled"]
        scrollToHittable(reminder, in: app)
        tapSwitch(reminder)
        waitForSwitch(reminder, isOn: true)
        XCTAssertTrue(app.datePickers["quick-entry-reminder-date"].waitForExistence(timeout: 3))

        let save = app.buttons["quick-entry-save"]
        scrollToHittable(save, in: app)
        save.tap()
        assertSaved("Event saved", in: app)
        app.buttons["quick-entry-done"].tap()
    }

    func testInvalidClockRetainsInputAndShowsStableParseError() {
        let app = launch()
        openQuickEntry(in: app)
        let input = app.textFields["quick-entry-input"]
        input.tap()
        input.typeText("Call at 25:00")
        dismissKeyboard(in: app)
        app.buttons["quick-entry-parse"].tap()

        let error = app.descendants(matching: .any)["quick-entry-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(error.label, "Enter a valid time.")
        XCTAssertEqual(input.value as? String, "Call at 25:00")
        XCTAssertFalse(app.buttons["quick-entry-save"].exists)
    }

    func testAccessibilityXXXLKeepsAddTabBarAndConfirmationActionsHittableWithoutOverlap() {
        let app = launch([
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let add = app.buttons["universal-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(add.frame.width, 56)
        XCTAssertGreaterThanOrEqual(add.frame.height, 56)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertFalse(add.frame.intersects(tabBar.frame))
        XCTAssertTrue(app.buttons["calendar-day-today"].isHittable)

        app.buttons["Next month"].tap()
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date())!
        let components = calendar.dateComponents([.year, .month, .day], from: nextMonth)
        let nextMonthSelection = app.buttons["calendar-day-\(components.year!)-\(components.month!)-\(components.day!)"]
        XCTAssertTrue(nextMonthSelection.waitForExistence(timeout: 3))
        XCTAssertTrue(nextMonthSelection.isHittable)

        parse("Read every night", in: app)
        assertKind("Routine", in: app)
        let category = app.descendants(matching: .any)["quick-entry-category"]
        scrollToExistence(category, in: app)
        let back = app.buttons["quick-entry-back"]
        scrollToHittable(back, in: app)
        let save = app.buttons["quick-entry-save"]
        scrollToHittable(save, in: app)
        XCTAssertTrue(save.isEnabled)
    }

    private func assertSoleUniversalAdd(
        on tab: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = launch()
        if tab != "Calendar" { app.tabBars.buttons[tab].tap() }
        XCTAssertTrue(app.tabBars.buttons[tab].isSelected, file: file, line: line)
        let adds = app.buttons.matching(identifier: "universal-add")
        XCTAssertEqual(adds.count, 1, "There must be one root-owned Add action", file: file, line: line)
        let add = adds.firstMatch
        XCTAssertTrue(add.isHittable, file: file, line: line)
        XCTAssertEqual(add.label, "Add event, task, or routine", file: file, line: line)
        XCTAssertGreaterThanOrEqual(add.frame.width, 56, file: file, line: line)
        XCTAssertGreaterThanOrEqual(add.frame.height, 56, file: file, line: line)
        for oldTitle in ["New Event", "New Task", "New Routine"] {
            XCTAssertFalse(app.buttons[oldTitle].exists, "Legacy \(oldTitle) must not remain reachable", file: file, line: line)
        }
        add.tap()
        XCTAssertTrue(app.textFields["quick-entry-input"].waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(app.textFields["quick-entry-input"].placeholderValue, "Describe what you want to add", file: file, line: line)
        app.buttons["quick-entry-cancel"].tap()
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-quick-entry-fixed-context"] + arguments
        app.launch()
        return app
    }

    private func openQuickEntry(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let add = app.buttons["universal-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3), file: file, line: line)
        add.tap()
        let input = app.textFields["quick-entry-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(input.placeholderValue, "Describe what you want to add", file: file, line: line)
        XCTAssertTrue(app.buttons["quick-entry-parse"].exists, file: file, line: line)
        XCTAssertEqual(app.buttons["quick-entry-parse"].label, "Review", file: file, line: line)
    }

    private func parse(_ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        openQuickEntry(in: app, file: file, line: line)
        let input = app.textFields["quick-entry-input"]
        input.tap()
        input.typeText(text)
        dismissKeyboard(in: app)
        app.buttons["quick-entry-parse"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quick-entry-kind"].waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(app.textFields["quick-entry-title"].exists, file: file, line: line)
    }

    private func assertKind(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let kind = app.descendants(matching: .any)["quick-entry-kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 3), file: file, line: line)
        waitForValue(expected, on: kind, file: file, line: line)
    }

    private func selectKind(_ kind: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let control = app.descendants(matching: .any)["quick-entry-kind"]
        let option = app.buttons["quick-entry-kind-\(kind.lowercased())"]
        if !option.exists { control.tap() }
        XCTAssertTrue(option.waitForExistence(timeout: 3), file: file, line: line)
        option.tap()
        waitForValue(kind, on: control, file: file, line: line)
    }

    private func selectRoutineWindow(_ window: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let control = app.descendants(matching: .any)["quick-entry-routine-window"]
        XCTAssertTrue(control.waitForExistence(timeout: 3), file: file, line: line)
        let option = app.buttons["quick-entry-routine-window-\(window.lowercased())"]
        if !option.exists { control.tap() }
        XCTAssertTrue(option.waitForExistence(timeout: 3), file: file, line: line)
        option.tap()
        waitForValue(window, on: control, file: file, line: line)
    }

    private func assertCategoryNone(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let category = app.descendants(matching: .any)["quick-entry-category"]
        scrollToExistence(category, in: app, file: file, line: line)
        XCTAssertEqual(category.label, "Category, No Category", file: file, line: line)
    }

    private func assertSaved(_ copy: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let saved = app.descendants(matching: .any)["quick-entry-saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(saved.label, copy, file: file, line: line)
        let done = app.buttons["quick-entry-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(done.label, "Done", file: file, line: line)
        XCTAssertTrue(done.isHittable, file: file, line: line)
        XCTAssertFalse(app.buttons["quick-entry-save"].exists, "Committed state must not expose another write", file: file, line: line)
        XCTAssertFalse(app.buttons["quick-entry-retry"].exists, "Committed state must not expose Retry", file: file, line: line)
    }

    private func assertSaveFailure(_ copy: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let error = app.descendants(matching: .any)["quick-entry-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(error.label, copy, file: file, line: line)
        let retry = app.buttons["quick-entry-retry"]
        scrollToHittable(retry, in: app, file: file, line: line)
        XCTAssertEqual(retry.label, "Retry", file: file, line: line)
    }

    private func assertSourceExplanation(_ copy: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let explanation = app.descendants(matching: .any)["quick-entry-source-explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(explanation.label, copy, file: file, line: line)
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
        if returnKey.exists { returnKey.tap(); return }
        if app.keyboards.firstMatch.exists { app.swipeDown() }
    }

    private func tapSwitch(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func waitForSwitch(
        _ element: XCUIElement,
        isOn: Bool,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let accepted = isOn ? Set(["1", "On"]) : Set(["0", "Off"])
        let predicate = NSPredicate { object, _ in
            guard let control = object as? XCUIElement else { return false }
            return accepted.contains(String(describing: control.value ?? ""))
        }
        let expectation = expectation(for: predicate, evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
        XCTAssertTrue(accepted.contains(String(describing: element.value ?? "")), file: file, line: line)
    }

    private func waitForValue(
        _ value: String,
        on element: XCUIElement,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = expectation(for: predicate, evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(element.value as? String, value, file: file, line: line)
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) {
        let expectation = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected \(element) to be reachable and hittable", file: file, line: line)
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

    private func scrollTowardTopToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 where !element.isHittable { app.swipeDown() }
        XCTAssertTrue(element.isHittable, "Expected \(element) to be reachable and hittable", file: file, line: line)
    }
}
