import XCTest

@MainActor
final class FoundationFlowUITests: XCTestCase {
    func testShowOnboardingOrdersPagesAndNotNowReachesTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-show-onboarding", "-calendar-not-determined", "-reminders-not-determined", "-notifications-not-determined"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Calendar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].exists)
        XCTAssertTrue(app.buttons["Not Now"].isHittable)
        app.buttons["Not Now"].tap()
        XCTAssertTrue(app.staticTexts["Reminders"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].exists)
        app.buttons["Not Now"].tap()
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Step 3 of 3"].exists)
        app.buttons["Not Now"].tap()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 2))
    }

    func testShowOnboardingUsesContinueForTerminalAccess() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-show-onboarding", "-calendar-denied"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Calendar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continue"].exists)
        XCTAssertFalse(app.buttons["Not Now"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Reminders"].waitForExistence(timeout: 2))
    }

    func testRestrictedOnboardingAtAccessibilityXXXLTraversesTerminalPagesWithStableControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-show-onboarding", "-calendar-restricted", "-reminders-restricted", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let heading = app.staticTexts["onboarding-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        waitForLabel("Calendar", on: heading)
        XCTAssertTrue(app.staticTexts["Show your schedule and events in one place."].exists)
        XCTAssertTrue(app.staticTexts["Calendar access is restricted by device or account controls."].exists)
        XCTAssertFalse(app.buttons["onboarding-not-now"].exists)
        let primary = app.buttons["onboarding-primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        XCTAssertEqual(primary.label, "Continue")
        scrollToHittable(primary, in: app)
        primary.tap()

        waitForLabel("Reminders", on: heading)
        XCTAssertTrue(app.staticTexts["Show and manage your tasks alongside your schedule."].exists)
        XCTAssertTrue(app.staticTexts["Reminders access is restricted by device or account controls."].exists)
        XCTAssertFalse(app.buttons["onboarding-not-now"].exists)
        XCTAssertEqual(primary.label, "Continue")
        scrollToHittable(primary, in: app)
        primary.tap()

        waitForLabel("Notifications", on: heading)
        XCTAssertTrue(app.staticTexts["Deliver local reminders and summaries."].exists)
        XCTAssertTrue(app.staticTexts["Notifications access is allowed."].exists)
        XCTAssertFalse(app.buttons["onboarding-not-now"].exists)
        XCTAssertEqual(primary.label, "Continue")
        scrollToHittable(primary, in: app)
        primary.tap()

        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 3))
    }

    func testSettingsExplainsDeniedCalendarWithoutBlockingRoutines() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-denied"]
        app.launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Routines"].tap()
        XCTAssertTrue(app.navigationBars["Routines"].exists)
    }

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

        let today = app.buttons["calendar-day-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 3))
        XCTAssertFalse(today.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotEqual(today.label, "calendar-day-today")
        let todayValue = today.value as? String ?? ""
        XCTAssertTrue(todayValue.contains("Today"), "Expected Today in accessibility value: \(todayValue)")
        XCTAssertTrue(todayValue.contains("Selected"), "Expected Selected in accessibility value: \(todayValue)")
        XCTAssertNotNil(todayValue.range(of: #"\b\d+ items\b"#, options: .regularExpression), "Expected an item count in accessibility value: \(todayValue)")
        XCTAssertTrue(app.otherElements["month-grid"].exists)
        app.buttons["Expand day"].tap()

        XCTAssertTrue(app.buttons["Collapse day"].exists)
        XCTAssertTrue(app.otherElements["selected-week-strip"].exists)
        XCTAssertFalse(app.otherElements["month-grid"].exists)
        app.buttons["Collapse day"].tap()
        XCTAssertTrue(app.otherElements["month-grid"].exists)
    }

    func testCreateBasicEventThroughUniversalQuickEntryInDemoMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-quick-entry-fixed-context"]
        app.launch()

        openAndParseQuickEntry("Dentist today at 3pm", in: app)
        XCTAssertEqual(app.descendants(matching: .any)["quick-entry-kind"].value as? String, "Event")
        app.buttons["quick-entry-save"].tap()
        finishSavedQuickEntry("Event saved", in: app)

        app.buttons["Expand day"].tap()
        XCTAssertTrue(app.buttons["agenda-open-event-demo-event-2"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "agenda-open-event-demo-event-2").count, 1)
    }

    func testUniversalQuickEntryRetryUsesEditedEventPreviewAfterFailOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-quick-entry-fixed-context", "-event-save-fails-once"]
        app.launch()
        openAndParseQuickEntry("Dentist today at 3pm", in: app)
        let title = app.textFields["quick-entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        app.buttons["quick-entry-save"].tap()
        let error = app.descendants(matching: .any)["quick-entry-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(error.label, "Your event was not saved. Edit it and try again.")
        let retry = app.buttons["quick-entry-retry"]
        scrollToHittable(retry, in: app)
        for _ in 0..<6 where !title.isHittable { app.swipeDown() }
        XCTAssertTrue(title.isHittable)
        replaceText(title, with: "Dentist Updated")
        dismissKeyboard(in: app)
        scrollToHittable(retry, in: app)
        retry.tap()
        finishSavedQuickEntry("Event saved", in: app)
        app.buttons["Expand day"].tap()
        let created = app.buttons["agenda-open-event-demo-event-2"]
        XCTAssertTrue(created.waitForExistence(timeout: 3))
        XCTAssertEqual(created.label, "Event, Dentist Updated, 15:00, Not completed")
        XCTAssertEqual(app.buttons.matching(identifier: "agenda-open-event-demo-event-2").count, 1)
        XCTAssertFalse(app.staticTexts["Dentist"].exists)
    }

    func testTodayTabShowsDemoAgenda() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Coffee"].exists)
        XCTAssertTrue(app.staticTexts["Buy milk"].exists)
        XCTAssertTrue(app.staticTexts["Read"].exists)
    }

    func testTodayShowsCalendarPermissionWhileRemainingAgendaStaysVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-denied"]
        app.launch()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Calendar events are unavailable"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["today-calendar-permission-settings"].exists)
        XCTAssertTrue(app.staticTexts["Buy milk"].exists)
        XCTAssertTrue(app.staticTexts["Read"].exists)

        app.buttons["today-calendar-permission-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    func testCalendarPermissionCardRoutesToTheInAppSettingsSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-denied"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Calendar access is unavailable. Calendar events are hidden."].waitForExistence(timeout: 3))
        let settings = app.buttons["calendar-permission-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    func testRestrictedCalendarHasNoCardActionAndToolbarSettingsRemainsUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-restricted"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Calendar access is restricted. Calendar events are hidden because this access is controlled by your device or account."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["calendar-permission-settings"].exists)
        XCTAssertTrue(app.staticTexts["Buy milk"].exists)
        XCTAssertTrue(app.staticTexts["Read"].exists)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Calendar access is restricted"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["This access is controlled by your device or account."].exists)
    }

    func testRestrictedRemindersHasNoCardActionAndToolbarSettingsRemainsUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reminders-restricted"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Reminders access is restricted. Tasks are hidden because this access is controlled by your device or account."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["reminders-permission-settings"].exists)
        XCTAssertTrue(app.staticTexts["Coffee"].exists)
        XCTAssertTrue(app.staticTexts["Read"].exists)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Reminders access is restricted"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["This access is controlled by your device or account."].exists)
    }

    func testCalendarDegradedPathReachesHittableSettingsControlsAtAccessibilityXXXL() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-denied", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Calendar access is unavailable. Calendar events are hidden."].waitForExistence(timeout: 3))
        let degradedSettings = app.buttons["calendar-permission-settings"]
        XCTAssertTrue(degradedSettings.waitForExistence(timeout: 3))
        scrollToHittable(degradedSettings, in: app)
        degradedSettings.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let done = app.buttons["Done"]
        XCTAssertTrue(done.exists)
        XCTAssertTrue(done.isHittable)
        XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 3))
        let systemSettings = app.buttons["Open System Settings"].firstMatch
        XCTAssertTrue(systemSettings.waitForExistence(timeout: 3))
        scrollToHittable(systemSettings, in: app)
    }

    func testReduceMotionLaunchExpandsAndCollapsesCalendarTray() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reduce-motion"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["month-grid"].waitForExistence(timeout: 3))
        app.buttons["Expand day"].tap()
        XCTAssertTrue(app.otherElements["selected-week-strip"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["month-grid"].exists)
        app.buttons["Collapse day"].tap()
        XCTAssertTrue(app.otherElements["month-grid"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["selected-week-strip"].exists)
    }

    func testDarkModeDegradedPermissionSurfaceRemainsOperable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-denied", "-reminders-denied", "-AppleInterfaceStyle", "Dark"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Calendar access is unavailable. Calendar events are hidden."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Reminders access is unavailable. Tasks are hidden."].exists)
        let degradedSettings = app.buttons["calendar-permission-settings"]
        XCTAssertTrue(degradedSettings.waitForExistence(timeout: 3))
        scrollToHittable(degradedSettings, in: app)
        degradedSettings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].isHittable)
    }

    func testAllDeniedKeepsCalendarTodayAndRoutinesOperable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-denied", "-reminders-denied", "-notifications-denied"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Calendar access is unavailable. Calendar events are hidden."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Reminders access is unavailable. Tasks are hidden."].exists)
        XCTAssertTrue(app.buttons["calendar-permission-settings"].exists)
        XCTAssertTrue(app.buttons["reminders-permission-settings"].exists)
        XCTAssertTrue(app.staticTexts["Read"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Calendar events are unavailable"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Tasks are unavailable"].exists)
        XCTAssertTrue(app.buttons["today-calendar-permission-settings"].exists)
        XCTAssertTrue(app.buttons["today-reminders-permission-settings"].exists)
        XCTAssertTrue(app.staticTexts["Read"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Routines"].tap()
        XCTAssertTrue(app.navigationBars["Routines"].waitForExistence(timeout: 3))
        let complete = app.buttons["Mark Read complete"]
        let undo = app.buttons["Mark Read incomplete"]
        if undo.exists {
            undo.tap()
            XCTAssertTrue(complete.waitForExistence(timeout: 3))
        }
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()
        let completed = app.buttons["Mark Read incomplete"]
        XCTAssertTrue(completed.waitForExistence(timeout: 3))
        XCTAssertEqual(completed.value as? String, "Completed")
    }

    func testProfileSwitchRefreshesCalendarAndToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        app.buttons["Expand day"].tap()
        XCTAssertTrue(app.staticTexts["Coffee"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Planning"].exists)
        app.buttons["profile-selector"].tap()
        app.buttons["profile-option-everything"].tap()
        XCTAssertTrue(app.otherElements["selected-week-strip"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Planning"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Coffee"].exists)

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Planning"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Coffee"].exists)
    }

    func testTodayTaskCompletionCanBeUndone() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Today"].tap()
        let complete = app.buttons["agenda-complete-task-demo-task"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        XCTAssertEqual(complete.value as? String, "Not completed")
        complete.tap()
        XCTAssertTrue(app.buttons["Undo completion for Buy milk"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Buy milk"].exists)
        app.buttons["Undo completion for Buy milk"].tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3))
        let restored = app.buttons["agenda-complete-task-demo-task"]
        XCTAssertTrue(restored.exists)
        XCTAssertEqual(restored.value as? String, "Not completed")
    }

    func testUniversalQuickEntryCreatesTaskAndExistingRoutineCompletesInDemoMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-quick-entry-fixed-context"]
        app.launch()

        app.tabBars.buttons["Tasks"].tap()
        openAndParseQuickEntry("Call Alex", in: app)
        XCTAssertEqual(app.descendants(matching: .any)["quick-entry-kind"].value as? String, "Task")
        app.buttons["quick-entry-save"].tap()
        finishSavedQuickEntry("Task saved", in: app)
        let createdTask = app.buttons["task-open-demo-task-2"]
        XCTAssertTrue(createdTask.waitForExistence(timeout: 3))
        XCTAssertEqual(createdTask.label, "Open task Call Alex")
        XCTAssertEqual(app.buttons.matching(identifier: "task-open-demo-task-2").count, 1)

        app.tabBars.buttons["Routines"].tap()
        let complete = app.buttons["Mark Read complete"]
        let undo = app.buttons["Mark Read incomplete"]
        if undo.exists { undo.tap(); XCTAssertTrue(complete.waitForExistence(timeout: 3)) }
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()
        let completed = app.buttons["Mark Read incomplete"]
        XCTAssertTrue(completed.waitForExistence(timeout: 3))
        XCTAssertEqual(completed.value as? String, "Completed")
        XCTAssertTrue(app.staticTexts["1 day streak"].exists)
        XCTAssertTrue(app.otherElements["14-day history"].exists)
    }

    func testUniversalQuickEntryTaskRetryAfterDemoFailOnceCreatesOnlyEditedTask() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-quick-entry-fixed-context", "-task-save-fails-once"]; app.launch()
        app.tabBars.buttons["Tasks"].tap(); openAndParseQuickEntry("First", in: app)
        let title = app.textFields["quick-entry-title"]; XCTAssertTrue(title.waitForExistence(timeout: 3))
        app.buttons["quick-entry-save"].tap()
        let error = app.descendants(matching: .any)["quick-entry-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3)); XCTAssertEqual(error.label, "Your task was not saved. Edit it and try again.")
        let retry = app.buttons["quick-entry-retry"]
        scrollToHittable(retry, in: app)
        XCTAssertEqual(title.value as? String, "First")
        for _ in 0..<6 where !title.isHittable { app.swipeDown() }
        XCTAssertTrue(title.isHittable)
        replaceText(title, with: "Edited")
        dismissKeyboard(in: app)
        scrollToHittable(retry, in: app); retry.tap(); finishSavedQuickEntry("Task saved", in: app)
        let created = app.buttons["task-open-demo-task-2"]
        XCTAssertTrue(created.waitForExistence(timeout: 3)); XCTAssertEqual(created.label, "Open task Edited"); XCTAssertEqual(app.buttons.matching(identifier: "task-open-demo-task-2").count, 1); XCTAssertFalse(app.staticTexts["First"].exists)
    }

    func testUniversalQuickEntryRoutineFailureRetainsEditsForRetry() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-quick-entry-fixed-context", "-routine-create-fails-once"]; app.launch(); app.tabBars.buttons["Routines"].tap()
        openAndParseQuickEntry("Read every night", in: app); let title = app.textFields["quick-entry-title"]; XCTAssertTrue(title.waitForExistence(timeout: 3)); replaceText(title, with: "Draft Routine"); dismissKeyboard(in: app)
        XCTAssertTrue(app.buttons["quick-entry-save"].isHittable); app.buttons["quick-entry-save"].tap(); let error = app.descendants(matching: .any)["quick-entry-error"]; XCTAssertTrue(error.waitForExistence(timeout: 3)); XCTAssertEqual(error.label, "Your routine was not saved. Edit it and try again."); XCTAssertEqual(title.value as? String, "Draft Routine")
        replaceText(title, with: "Edited Routine"); dismissKeyboard(in: app)
        app.buttons["quick-entry-retry"].tap(); finishSavedQuickEntry("Routine saved", in: app); let created = app.staticTexts.matching(NSPredicate(format: "label == %@", "Edited Routine")); XCTAssertTrue(created.firstMatch.waitForExistence(timeout: 3)); XCTAssertEqual(created.count, 1); XCTAssertFalse(app.staticTexts["Draft Routine"].exists)
    }

    func testRoutineUpdateFailureCancelReopenAndEditedRetry() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-routine-update-fails-once"]; app.launch(); app.tabBars.buttons["Routines"].tap()
        tapRoutineAction("edit", in: app); let title = app.textFields["Routine title"]; XCTAssertTrue(title.waitForExistence(timeout: 3)); title.tap(); for _ in 0..<4 { title.typeText(XCUIKeyboardKey.delete.rawValue) }; title.typeText("Draft Read"); app.keyboards.buttons["Return"].tap()
        XCTAssertTrue(app.buttons["routine-save"].isHittable); app.buttons["routine-save"].tap(); XCTAssertTrue(findRoutineRetry(in: app).exists); XCTAssertTrue(app.staticTexts["Your routine was not saved. Edit it and try again."].exists)
        app.buttons["Cancel"].tap(); tapRoutineAction("edit", in: app); let reopenedTitle = app.textFields["Routine title"]; XCTAssertEqual(reopenedTitle.value as? String, "Draft Read")
        reopenedTitle.tap(); for _ in 0..<10 { reopenedTitle.typeText(XCUIKeyboardKey.delete.rawValue) }; reopenedTitle.typeText("Edited Read"); app.keyboards.buttons["Return"].tap()
        findRoutineRetry(in: app).tap(); XCTAssertTrue(app.staticTexts["Edited Read"].waitForExistence(timeout: 3)); XCTAssertFalse(app.staticTexts["Read"].exists)
    }

    func testRoutineDeleteCancelPreservesThenConfirmRemoves() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        app.tabBars.buttons["Routines"].tap()
        XCTAssertTrue(app.staticTexts["Read"].waitForExistence(timeout: 3))
        tapRoutineAction("delete", in: app); XCTAssertTrue(app.navigationBars["Confirm delete"].waitForExistence(timeout: 3)); XCTAssertFalse(app.navigationBars["Edit Routine"].exists); XCTAssertTrue(app.buttons["Cancel Delete"].waitForExistence(timeout: 3)); app.buttons["Cancel Delete"].tap(); XCTAssertFalse(app.navigationBars["Edit Routine"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Read"].exists)
        tapRoutineAction("delete", in: app); XCTAssertTrue(app.navigationBars["Confirm delete"].waitForExistence(timeout: 3)); confirmationDelete(in: app).tap()
        XCTAssertFalse(app.staticTexts["Read"].waitForExistence(timeout: 1))
    }

    func testRoutineDeleteRetryRequiresSecondConfirmation() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-routine-delete-fails-once"]; app.launch(); app.tabBars.buttons["Routines"].tap()
        tapRoutineAction("delete", in: app); XCTAssertTrue(app.navigationBars["Confirm delete"].waitForExistence(timeout: 3)); confirmationDelete(in: app).tap()
        XCTAssertTrue(app.staticTexts["Your routine was not deleted. Try again. The routine and its completion history are still safe on this iPhone."].waitForExistence(timeout: 3)); XCTAssertTrue(confirmationDelete(in: app).exists); XCTAssertTrue(confirmationDelete(in: app).isHittable)
        app.buttons["Cancel Delete"].tap(); XCTAssertTrue(app.staticTexts["Read"].exists); XCTAssertTrue(app.buttons["Retry Delete"].waitForExistence(timeout: 3)); app.buttons["Retry Delete"].tap()
        XCTAssertTrue(app.navigationBars["Confirm delete"].waitForExistence(timeout: 3)); XCTAssertTrue(confirmationDelete(in: app).exists); XCTAssertTrue(confirmationDelete(in: app).isHittable); confirmationDelete(in: app).tap(); XCTAssertFalse(app.staticTexts["Read"].waitForExistence(timeout: 1)); XCTAssertFalse(app.navigationBars["Confirm delete"].exists)
    }

    func testRoutinesRemainOperableAtAccessibilityXXXL() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        app.tabBars.buttons["Routines"].tap(); XCTAssertTrue(app.staticTexts["Read"].waitForExistence(timeout: 3)); XCTAssertTrue(app.otherElements["14-day history"].exists)
        for action in ["edit", "pause", "archive", "delete"] { XCTAssertTrue(routineAction(action, in: app).waitForExistence(timeout: 3)); if !routineAction(action, in: app).isHittable { app.swipeUp() }; XCTAssertTrue(routineAction(action, in: app).isHittable) }
        tapRoutineAction("delete", in: app); XCTAssertTrue(app.navigationBars["Confirm delete"].waitForExistence(timeout: 3)); XCTAssertTrue(app.buttons["Cancel Delete"].waitForExistence(timeout: 3)); XCTAssertTrue(app.buttons["Cancel Delete"].isHittable); XCTAssertTrue(confirmationDelete(in: app).exists); XCTAssertTrue(confirmationDelete(in: app).isHittable); app.buttons["Cancel Delete"].tap()
    }

    func testLongDeleteFailureRemainsOperableAtAccessibilityXXXL() {
        let title = "Read a long and thoughtfully named routine before bed every evening"
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-routine-delete-fails-once", "-routine-long-title", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); app.tabBars.buttons["Routines"].tap()
        tapRoutineAction("delete", in: app); XCTAssertTrue(app.navigationBars["Confirm delete"].waitForExistence(timeout: 3)); XCTAssertTrue(app.staticTexts["Delete \(title)?"].exists); XCTAssertTrue(app.buttons["Cancel Delete"].isHittable); XCTAssertTrue(confirmationDelete(in: app).isHittable)
        confirmationDelete(in: app).tap(); XCTAssertTrue(app.staticTexts["Your routine was not deleted. Try again. The routine and its completion history are still safe on this iPhone."].waitForExistence(timeout: 3)); XCTAssertTrue(app.buttons["Cancel Delete"].isHittable); XCTAssertTrue(confirmationDelete(in: app).isHittable); XCTAssertTrue(app.staticTexts[title].exists)
    }

    func testCalendarTrayRoutesEventAndTaskByOrigin() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["Expand day"].tap()
        let event = app.buttons["agenda-open-event-demo-event"]
        XCTAssertTrue(event.waitForExistence(timeout: 3))
        event.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
        app.buttons["event-editor-cancel"].tap()

        let task = app.buttons["agenda-open-task-demo-task"]
        let completion = app.buttons["agenda-complete-task-demo-task"]
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        XCTAssertTrue(completion.exists)
        XCTAssertEqual(completion.value as? String, "Not completed")
        task.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 3))
        app.buttons["task-editor-cancel"].tap()

        XCTAssertTrue(completion.waitForExistence(timeout: 3))
        XCTAssertEqual(completion.value as? String, "Not completed")
        completion.tap()
        XCTAssertFalse(task.waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Task"].exists)
    }

    func testTodayRoutesEventAndTaskByOrigin() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Today"].tap()

        app.buttons["agenda-open-event-demo-event"].tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
        app.buttons["event-editor-cancel"].tap()

        let task = app.buttons["agenda-open-task-demo-task"]
        let completion = app.buttons["agenda-complete-task-demo-task"]
        XCTAssertTrue(completion.waitForExistence(timeout: 3))
        XCTAssertEqual(completion.value as? String, "Not completed")
        task.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 3))
        app.buttons["task-editor-cancel"].tap()

        XCTAssertTrue(completion.waitForExistence(timeout: 3))
        XCTAssertEqual(completion.value as? String, "Not completed")
        completion.tap()
        XCTAssertTrue(app.buttons["Undo completion for Buy milk"].waitForExistence(timeout: 3))
        XCTAssertFalse(task.exists)
    }

    func testTaskTitleOpensDetailWhileSeparateCompletionControlAloneToggles() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Tasks"].tap()

        let openTask = app.buttons["task-open-demo-task"]
        let completion = app.buttons["task-complete-demo-task"]
        XCTAssertTrue(openTask.waitForExistence(timeout: 3))
        XCTAssertTrue(completion.exists)
        XCTAssertEqual(completion.value as? String, "Not completed")
        openTask.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 3))
        app.buttons["task-editor-cancel"].tap()
        completion.tap()
        XCTAssertFalse(openTask.waitForExistence(timeout: 3))
        app.buttons["Completed"].tap()
        let completedControl = app.buttons["task-complete-demo-task"]
        XCTAssertTrue(completedControl.waitForExistence(timeout: 3))
        XCTAssertEqual(completedControl.value as? String, "Completed")
    }

    func testReadOnlyEditorDetailsShowDistinctReasonAndDisabledEditDelete() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-editor-read-only"]
        app.launch()
        app.buttons["Expand day"].tap()

        app.buttons["agenda-open-event-demo-event-read-only"].tap()
        let readOnlyEventReason = app.staticTexts["This event belongs to a read-only calendar."]
        scrollToExistence(readOnlyEventReason, in: app)
        let unavailableEdit = app.buttons["event-editor-edit-unavailable"]
        let unavailableDelete = app.buttons["event-editor-delete"]
        scrollToExistence(unavailableEdit, in: app)
        XCTAssertTrue(unavailableDelete.exists)
        XCTAssertFalse(unavailableEdit.isEnabled)
        XCTAssertFalse(unavailableDelete.isEnabled)
        app.buttons["event-editor-cancel"].tap()

        app.buttons["agenda-open-event-demo-event-nonaddressable"].tap()
        let nonaddressableReason = app.staticTexts["Calendar did not provide a stable editing identifier for this event."]
        scrollToExistence(nonaddressableReason, in: app)
        XCTAssertFalse(app.buttons["event-editor-edit-unavailable"].isEnabled)
        XCTAssertFalse(app.buttons["event-editor-delete"].isEnabled)
        app.buttons["event-editor-cancel"].tap()

        app.buttons["agenda-open-task-demo-task-read-only"].tap()
        let taskReason = app.staticTexts["This task belongs to a read-only reminders list."]
        scrollToExistence(taskReason, in: app)
        let taskUnavailableEdit = app.buttons["task-editor-edit-unavailable"]
        let taskUnavailableDelete = app.buttons["task-editor-delete"]
        scrollToExistence(taskUnavailableEdit, in: app)
        XCTAssertTrue(taskUnavailableDelete.exists)
        XCTAssertFalse(taskUnavailableEdit.isEnabled)
        XCTAssertFalse(taskUnavailableDelete.isEnabled)
    }

    func testUnsupportedProviderEditorValuesRemainVisibleAndProtected() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-editor-unsupported"]
        app.launch()
        app.buttons["Expand day"].tap()

        app.buttons["agenda-open-event-demo-event-unsupported"].tap()
        let eventAlarm = app.descendants(matching: .any)["event-editor-unsupported-alarm"]
        let eventRepeat = app.descendants(matching: .any)["event-editor-unsupported-recurrence"]
        scrollToExistence(eventAlarm, in: app)
        XCTAssertTrue(eventAlarm.label.contains("Provider-defined alerts"))
        scrollToExistence(eventRepeat, in: app)
        XCTAssertTrue(eventRepeat.label.contains("Provider-defined repeat"))
        app.buttons["event-editor-cancel"].tap()

        app.buttons["agenda-open-task-demo-task-unsupported"].tap()
        let taskAlarm = app.descendants(matching: .any)["task-editor-unsupported-alarm"]
        let taskRepeat = app.descendants(matching: .any)["task-editor-unsupported-recurrence"]
        scrollToExistence(taskAlarm, in: app)
        XCTAssertTrue(taskAlarm.label.contains("Provider-defined alert"))
        scrollToExistence(taskRepeat, in: app)
        XCTAssertTrue(taskRepeat.label.contains("Provider-defined repeat"))
    }

    func testRecurringEditorsExposeEventScopesAndExactReminderSafetyCopy() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-editor-recurring"]
        app.launch()
        app.buttons["Expand day"].tap()

        app.buttons["agenda-open-event-demo-event-recurring"].tap()
        let currentAlerts = app.descendants(matching: .any)["event-editor-current-alarm"]
        scrollToExistence(currentAlerts, in: app)
        let alertValue = currentAlerts.label + " " + (currentAlerts.value as? String ?? "")
        XCTAssertTrue(alertValue.contains("15 minutes before"))
        XCTAssertTrue(alertValue.contains("1 hour before"))
        let currentRepeat = app.descendants(matching: .any)["event-editor-current-recurrence"]
        scrollToExistence(currentRepeat, in: app)
        let repeatValue = currentRepeat.label + " " + (currentRepeat.value as? String ?? "")
        XCTAssertTrue(repeatValue.contains("2 weeks"))
        XCTAssertTrue(repeatValue.contains("until"))

        let saveScope = app.descendants(matching: .any)["event-editor-recurrence-scope"]
        scrollToExistence(saveScope, in: app)
        let saveScopeValue = saveScope.label + " " + (saveScope.value as? String ?? "")
        XCTAssertTrue(saveScopeValue.contains("This Event"))

        let repeatPicker = app.descendants(matching: .any)["event-editor-recurrence-intent"]
        scrollToHittable(repeatPicker, in: app)
        repeatPicker.tap(); app.buttons["Never"].tap()
        let delete = app.buttons["event-editor-delete"]
        scrollToHittable(delete, in: app); delete.tap()
        let singleDelete = app.buttons.matching(identifier: "event-editor-confirm-delete").firstMatch
        XCTAssertTrue(singleDelete.waitForExistence(timeout: 3))
        XCTAssertEqual(singleDelete.label, "Delete This Event")
        XCTAssertTrue(app.staticTexts["Delete only this event? This can’t be undone."].exists)
        app.buttons.matching(identifier: "event-editor-confirm-cancel").firstMatch.tap()

        app.buttons["event-editor-cancel"].tap()
        app.buttons.matching(identifier: "event-editor-discard").firstMatch.tap()

        app.buttons["agenda-open-task-demo-task-recurring"].tap()
        let occurrenceCopy = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Only the current incomplete reminder occurrence is shown. Completing it may reveal the next occurrence supplied by Apple Reminders.")
        ).firstMatch
        scrollToExistence(occurrenceCopy, in: app)
        let deleteCopy = app.staticTexts["Deleting this task removes the repeating reminder."]
        scrollToExistence(deleteCopy, in: app)
        let taskAlarm = app.descendants(matching: .any)["task-editor-current-alarm"]
        scrollToExistence(taskAlarm, in: app)
        let taskAlarmValue = taskAlarm.label + " " + (taskAlarm.value as? String ?? "")
        // The demo task is due at 16:30 today and carries a provider alert 30
        // minutes earlier. Derive the localized expected provider value instead
        // of hard-coding the simulator's launch day.
        let expectedAlarm = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now)!
            .formatted(date: .abbreviated, time: .shortened)
        XCTAssertTrue(taskAlarmValue.contains(expectedAlarm))
        let taskRepeat = app.descendants(matching: .any)["task-editor-current-recurrence"]
        scrollToExistence(taskRepeat, in: app)
        let taskRepeatValue = taskRepeat.label + " " + (taskRepeat.value as? String ?? "")
        XCTAssertTrue(taskRepeatValue.contains("2 weeks"))
        XCTAssertTrue(taskRepeatValue.contains("until"))
        XCTAssertFalse(app.descendants(matching: .any)["task-editor-recurrence-scope"].exists)
    }

    func testFailedEventAndTaskUpdatesKeepEditedFormForRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-event-update-fails-once", "-task-update-fails-once"]
        app.launch()

        app.buttons["agenda-open-event-demo-event"].tap()
        let eventTitle = app.textFields["event-editor-title"]
        XCTAssertTrue(eventTitle.waitForExistence(timeout: 3))
        replaceText(eventTitle, with: "Coffee updated")
        dismissKeyboard(in: app)
        app.buttons["event-editor-save"].tap()
        XCTAssertEqual(eventTitle.value as? String, "Coffee updated")
        let eventRetry = app.buttons["event-save-retry"]
        scrollToHittable(eventRetry, in: app)
        eventRetry.tap()
        XCTAssertTrue(app.staticTexts["Coffee updated"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["task-open-demo-task"].tap()
        let taskTitle = app.textFields["task-editor-title"]
        XCTAssertTrue(taskTitle.waitForExistence(timeout: 3))
        replaceText(taskTitle, with: "Buy oat milk")
        dismissKeyboard(in: app)
        app.buttons["task-editor-save"].tap()
        XCTAssertEqual(taskTitle.value as? String, "Buy oat milk")
        let taskRetry = app.buttons["task-save-retry"]
        scrollToHittable(taskRetry, in: app)
        taskRetry.tap()
        XCTAssertTrue(app.staticTexts["Buy oat milk"].waitForExistence(timeout: 3))
    }

    func testEventAndTaskDeleteRetryRequireFreshConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-event-delete-fails-once", "-task-delete-fails-once"]
        app.launch()

        app.buttons["agenda-open-event-demo-event"].tap()
        let eventDelete = app.buttons["event-editor-delete"]
        scrollToHittable(eventDelete, in: app)
        eventDelete.tap()
        let firstEventConfirm = app.buttons.matching(identifier: "event-editor-confirm-delete").firstMatch
        XCTAssertTrue(firstEventConfirm.waitForExistence(timeout: 3))
        firstEventConfirm.tap()
        let eventRetry = app.buttons["event-delete-retry"]
        scrollToHittable(eventRetry, in: app)
        eventRetry.tap()
        let eventConfirm = app.buttons.matching(identifier: "event-editor-confirm-delete").firstMatch
        XCTAssertTrue(eventConfirm.waitForExistence(timeout: 3))
        eventConfirm.tap()
        XCTAssertFalse(app.buttons["agenda-open-event-demo-event"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["task-open-demo-task"].tap()
        let taskDelete = app.buttons["task-editor-delete"]
        scrollToHittable(taskDelete, in: app)
        taskDelete.tap()
        let firstTaskConfirm = app.buttons.matching(identifier: "task-editor-confirm-delete").firstMatch
        XCTAssertTrue(firstTaskConfirm.waitForExistence(timeout: 3))
        firstTaskConfirm.tap()
        let taskRetry = app.buttons["task-delete-retry"]
        scrollToHittable(taskRetry, in: app)
        taskRetry.tap()
        let taskConfirm = app.buttons.matching(identifier: "task-editor-confirm-delete").firstMatch
        XCTAssertTrue(taskConfirm.waitForExistence(timeout: 3))
        taskConfirm.tap()
        XCTAssertFalse(app.buttons["task-open-demo-task"].waitForExistence(timeout: 3))
    }

    func testEventEditorActionsRemainScrollableAndHittableAtAccessibilityXXXL() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-editor-recurring", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        app.buttons["Expand day"].tap()
        let recurringEvent = app.buttons["agenda-open-event-demo-event-recurring"]
        scrollToHittable(recurringEvent, in: app)
        recurringEvent.tap()
        let scope = app.descendants(matching: .any)["event-editor-recurrence-scope"]
        scrollToHittable(scope, in: app)
        let delete = app.buttons["event-editor-delete"]
        scrollToHittable(delete, in: app)
    }

    func testTaskEditorActionsAndRecurringDeletionCopyRemainAccessibleAtAccessibilityXXXL() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-editor-recurring", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        app.buttons["Expand day"].tap()
        let recurringTask = app.buttons["agenda-open-task-demo-task-recurring"]
        scrollToHittable(recurringTask, in: app)
        recurringTask.tap()

        let schedule = app.descendants(matching: .any)["task-editor-schedule-intent"]
        scrollToHittable(schedule, in: app)
        let recurrence = app.descendants(matching: .any)["task-editor-recurrence-intent"]
        scrollToHittable(recurrence, in: app)
        let recurringDeleteCopy = app.staticTexts["Deleting this task removes the repeating reminder."]
        scrollToHittable(recurringDeleteCopy, in: app)

        let save = app.buttons["task-editor-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isHittable)
        let delete = app.buttons["task-editor-delete"]
        scrollToHittable(delete, in: app)
    }

    private func openAndParseQuickEntry(
        _ text: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let add = app.buttons["universal-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(add.label, "Add event, task, or routine", file: file, line: line)
        add.tap()
        let input = app.textFields["quick-entry-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(input.placeholderValue, "Describe what you want to add", file: file, line: line)
        input.tap()
        input.typeText(text)
        dismissKeyboard(in: app)
        let review = app.buttons["quick-entry-parse"]
        XCTAssertTrue(review.exists, file: file, line: line)
        XCTAssertEqual(review.label, "Review", file: file, line: line)
        review.tap()
        XCTAssertTrue(app.textFields["quick-entry-title"].waitForExistence(timeout: 3), file: file, line: line)
    }

    private func finishSavedQuickEntry(
        _ copy: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let saved = app.descendants(matching: .any)["quick-entry-saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(saved.label, copy, file: file, line: line)
        let done = app.buttons["quick-entry-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(done.isHittable, file: file, line: line)
        XCTAssertFalse(app.buttons["quick-entry-save"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["quick-entry-retry"].exists, file: file, line: line)
        done.tap()
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) {
        let expectation = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
    }

    private func waitForLabel(_ label: String, on element: XCUIElement, timeout: TimeInterval = 3) {
        let expectation = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
    }

    private func waitForValue(_ value: String, on element: XCUIElement, timeout: TimeInterval = 3) {
        let expectation = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected \(element) to be reachable and hittable", file: file, line: line)
    }

    private func scrollToExistence(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 where !element.exists { app.swipeUp() }
        XCTAssertTrue(element.exists, "Expected \(element) to be present after scrolling", file: file, line: line)
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        for _ in current { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        field.typeText(text)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() }
    }

    private func routineAction(_ action: String, in app: XCUIApplication) -> XCUIElement { app.buttons["routine-\(action)-00000000-0000-0000-0000-000000000001"] }
    private func tapRoutineAction(_ action: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = routineAction(action, in: app)
        for _ in 0..<4 {
            if target.exists && target.isHittable { target.tap(); return }
            app.swipeUp()
        }
        XCTFail("Routine \(action) action was not hittable", file: file, line: line)
    }
    private func confirmationDelete(in app: XCUIApplication) -> XCUIElement { app.buttons["Confirm Delete"] }
    private func findRoutineRetry(in app: XCUIApplication) -> XCUIElement { for _ in 0..<5 { let button = app.buttons["routine-save-retry"]; if button.exists && button.isHittable { return button }; app.swipeUp() }; return app.buttons["routine-save-retry"] }
}
