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

    func testRetryUsesEditedEventDraftAfterFailOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-event-save-fails-once"]
        app.launch()
        app.buttons["New Event"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Dentist")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["event-save-retry"].waitForExistence(timeout: 3))
        title.tap()
        for _ in 0..<7 { title.typeText(XCUIKeyboardKey.delete.rawValue) }
        title.typeText("Dentist Updated")
        app.buttons["event-save-retry"].tap()
        XCTAssertTrue(app.staticTexts["Dentist Updated"].waitForExistence(timeout: 3))
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

    func testSettingsSourceToggleRefreshesCalendarAndTodayWithoutHidingOtherSource() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-multiple-sources"]
        app.launch()

        app.buttons["Expand day"].tap()
        XCTAssertTrue(app.staticTexts["Coffee"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Planning"].exists)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Work"].waitForExistence(timeout: 3))
        let work = app.switches["Work"]
        work.tap()
        XCTAssertEqual(work.value as? String, "0")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.otherElements["selected-week-strip"].waitForExistence(timeout: 3))
        waitForDisappearance(app.staticTexts["Planning"])
        XCTAssertTrue(app.staticTexts["Coffee"].exists)

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 3))
        waitForDisappearance(app.staticTexts["Planning"])
        XCTAssertTrue(app.staticTexts["Coffee"].exists)
    }

    func testTodayTaskCompletionCanBeUndone() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Today"].tap()
        let complete = app.buttons["Mark Buy milk complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()
        XCTAssertTrue(app.buttons["Undo completion for Buy milk"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Buy milk"].exists)
        app.buttons["Undo completion for Buy milk"].tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Mark Buy milk complete"].exists)
    }

    func testTaskTitleTapDoesNotToggleButCompletionControlDoes() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch(); app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 3)); app.staticTexts["Buy milk"].tap()
        XCTAssertTrue(app.buttons["Mark Buy milk complete"].exists); XCTAssertFalse(app.buttons["Mark Buy milk incomplete"].exists)
        app.buttons["Mark Buy milk complete"].tap(); app.buttons["Completed"].tap(); let undo = app.buttons["Mark Buy milk incomplete"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3)); XCTAssertEqual(undo.value as? String, "Completed")
    }

    func testCreateTaskAndCompleteRoutineInDemoMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.tabBars.buttons["Tasks"].tap()
        app.buttons["New Task"].tap()
        let title = app.textFields["Task title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap(); title.typeText("Call Alex")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Call Alex"].waitForExistence(timeout: 3))
        waitForDisappearance(app.navigationBars["New Task"])

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

    func testEditedTaskRetryAfterDemoFailOnceCreatesOnlyEditedTask() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-task-save-fails-once"]; app.launch()
        app.tabBars.buttons["Tasks"].tap(); app.buttons["New Task"].tap()
        let title = app.textFields["Task title"]; XCTAssertTrue(title.waitForExistence(timeout: 3)); title.tap(); title.typeText("First")
        app.buttons["Save"].tap(); XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap(); app.buttons["New Task"].tap(); XCTAssertEqual(title.value as? String, "First")
        title.tap(); for _ in 0..<5 { title.typeText(XCUIKeyboardKey.delete.rawValue) }; title.typeText("Edited")
        app.buttons["Retry"].tap(); XCTAssertTrue(app.staticTexts["Edited"].waitForExistence(timeout: 3)); XCTAssertFalse(app.staticTexts["First"].exists)
    }

    func testRoutineCreateFailureCancelReopenAndEditedRetry() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-routine-create-fails-once"]; app.launch(); app.tabBars.buttons["Routines"].tap()
        app.buttons["New Routine"].tap(); let title = app.textFields["Routine title"]; XCTAssertTrue(title.waitForExistence(timeout: 3)); title.tap(); title.typeText("Draft Routine"); app.keyboards.buttons["Return"].tap(); app.buttons["Daily"].tap()
        XCTAssertTrue(app.buttons["routine-save"].isHittable); app.buttons["routine-save"].tap(); XCTAssertTrue(findRoutineRetry(in: app).exists); XCTAssertTrue(app.staticTexts["Your routine was not saved. Edit it and try again."].exists)
        app.buttons["Cancel"].tap(); app.buttons["New Routine"].tap(); let reopenedTitle = app.textFields["Routine title"]; XCTAssertEqual(reopenedTitle.value as? String, "Draft Routine"); XCTAssertTrue(app.buttons["Clear daily"].exists)
        reopenedTitle.tap(); for _ in 0..<13 { reopenedTitle.typeText(XCUIKeyboardKey.delete.rawValue) }; reopenedTitle.typeText("Edited Routine")
        findRoutineRetry(in: app).tap(); XCTAssertTrue(app.staticTexts["Edited Routine"].waitForExistence(timeout: 3)); XCTAssertFalse(app.staticTexts["Draft Routine"].exists)
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

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) {
        let expectation = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
    }

    private func waitForLabel(_ label: String, on element: XCUIElement, timeout: TimeInterval = 3) {
        let expectation = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        wait(for: [expectation], timeout: timeout)
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected \(element) to be reachable and hittable", file: file, line: line)
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
