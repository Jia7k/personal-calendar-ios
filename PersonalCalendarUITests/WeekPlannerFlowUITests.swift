import XCTest

@MainActor
final class WeekPlannerFlowUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        XCUIDevice.shared.orientation = .portrait
    }

    func testSchoolWeekShowsUsableEventPopupAndOpensTheEvent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()

        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        XCTAssertTrue(app.scrollViews["week-planner"].waitForExistence(timeout: 3))
        let event = app.buttons["week-event-demo-school-event"]
        XCTAssertTrue(event.exists)
        XCTAssertTrue(app.buttons["week-task-demo-school-task"].exists)

        event.tap()
        let detail = app.otherElements["week-event-detail-card"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(detail.frame.width, 280)
        XCTAssertGreaterThanOrEqual(detail.frame.height, 200)
        XCTAssertEqual(app.staticTexts["week-event-detail-title"].label, "INF 2003 Lecture")
        XCTAssertTrue(app.staticTexts["week-event-detail-time"].exists)
        XCTAssertEqual(app.staticTexts["week-event-detail-location"].label, "Online")
        XCTAssertEqual(app.staticTexts["week-event-detail-calendar"].label, "Google School")
        let close = app.buttons["week-event-detail-close"]
        XCTAssertTrue(close.isHittable)
        let open = app.buttons["week-open-selected-item"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(
            open.isHittable,
            "Open frame \(open.frame), detail frame \(detail.frame), window \(app.windows.firstMatch.frame)"
        )
        open.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 3))
    }

    func testWeekEventPopupDoesNotChangeTheChosenDay() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let personal = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000001"]
        XCTAssertTrue(personal.waitForExistence(timeout: 3))
        personal.tap()

        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let calendar = Calendar.current
        let today = Date()
        let offset = calendar.component(.weekday, from: today) == calendar.firstWeekday ? 1 : -1
        let otherDate = calendar.date(byAdding: .day, value: offset, to: today)!
        let otherDay = app.buttons[
            otherDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
        ]
        XCTAssertTrue(otherDay.waitForExistence(timeout: 3))
        otherDay.tap()
        let selectedDay = NSPredicate(format: "value == %@", "Selected day")
        expectation(for: selectedDay, evaluatedWith: otherDay)
        waitForExpectations(timeout: 3)

        let event = app.buttons["week-event-demo-personal-event"]
        XCTAssertTrue(event.waitForExistence(timeout: 3))
        event.tap()

        let detail = app.otherElements["week-event-detail-card"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue(selectedDay.evaluate(with: otherDay))
        XCTAssertEqual(event.value as? String, "Expanded")
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            popover.frame.minY,
            event.frame.maxY - 2,
            "Popover \(popover.frame) should open below event \(event.frame)"
        )
        XCTAssertGreaterThanOrEqual(popover.frame.height, 200)
        let visibleWindow = app.windows.firstMatch.frame.insetBy(dx: -2, dy: -2)
        XCTAssertTrue(
            visibleWindow.contains(popover.frame),
            "Popover \(popover.frame) should remain inside app window \(visibleWindow)"
        )
        XCTAssertEqual(app.staticTexts["week-event-detail-title"].label, "Coffee")
        XCTAssertTrue(app.staticTexts["week-event-detail-time"].isHittable)
        XCTAssertEqual(app.staticTexts["week-event-detail-calendar"].label, "Home")
        XCTAssertTrue(app.staticTexts["week-event-detail-calendar"].isHittable)
        let close = app.buttons["week-event-detail-close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.buttons["week-open-selected-item"].isHittable)

        close.tap()
        let dismissed = NSPredicate(format: "hittable == false")
        expectation(for: dismissed, evaluatedWith: close)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(event.isHittable)
        XCTAssertTrue(selectedDay.evaluate(with: otherDay))

        event.tap()
        let reopened = NSPredicate(format: "hittable == true")
        expectation(for: reopened, evaluatedWith: close)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(detail.exists)
        XCTAssertEqual(event.value as? String, "Expanded")
    }

    func testWeekTimelineScrollsVerticallyOnlyAndOverlapsOpenFromOneStack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles", "-demo-week-overlaps"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()

        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let planner = app.scrollViews["week-planner"]
        XCTAssertTrue(planner.waitForExistence(timeout: 3))
        let stack = app.buttons["week-event-stack-demo-week-overlap-a"]
        XCTAssertTrue(stack.waitForExistence(timeout: 3))
        for _ in 0..<4 where !stack.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(stack.isHittable)
        XCTAssertGreaterThanOrEqual(stack.frame.width, 44)
        XCTAssertGreaterThanOrEqual(stack.frame.height, 44)
        let boundaryTask = app.buttons["week-task-demo-week-boundary-task"]
        XCTAssertTrue(boundaryTask.waitForExistence(timeout: 3))
        XCTAssertTrue(boundaryTask.isHittable)
        XCTAssertGreaterThanOrEqual(boundaryTask.frame.height, 44)
        XCTAssertTrue(
            planner.frame.insetBy(dx: -1, dy: -1).contains(boundaryTask.frame),
            "Boundary task \(boundaryTask.frame) should fit inside planner \(planner.frame)"
        )

        let initialX = stack.frame.minX
        let periodTitle = app.staticTexts["calendar-header-period"]
        let initialPeriod = periodTitle.label
        let normalizedStackY = (stack.frame.midY - planner.frame.minY) / planner.frame.height
        planner.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: normalizedStackY))
            .press(
                forDuration: 0.1,
                thenDragTo: planner.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: normalizedStackY))
            )
        XCTAssertEqual(stack.frame.minX, initialX, accuracy: 1)
        XCTAssertEqual(periodTitle.label, initialPeriod)

        stack.tap()
        let picker = app.otherElements["week-event-stack-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        let algorithms = app.buttons["week-event-choice-demo-week-overlap-a"]
        let database = app.buttons["week-event-choice-demo-week-overlap-b"]
        let overlappingTask = app.buttons["week-task-choice-demo-week-overlap-task"]
        XCTAssertTrue(algorithms.isHittable)
        XCTAssertTrue(database.isHittable)
        XCTAssertTrue(overlappingTask.exists)
        if !overlappingTask.isHittable {
            picker.swipeUp()
        }
        XCTAssertTrue(overlappingTask.isHittable)
        overlappingTask.tap()
        XCTAssertTrue(app.otherElements["week-task-stack-detail"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["week-task-stack-close"].isHittable)
        app.buttons["week-task-stack-close"].tap()

        stack.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        database.tap()
        XCTAssertTrue(app.otherElements["week-event-detail-card"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["week-event-detail-title"].label, "Database Lab")
        app.buttons["week-event-detail-close"].tap()

        let lateEvent = app.buttons["week-event-demo-week-late-event"]
        XCTAssertTrue(lateEvent.exists)
        for _ in 0..<6 where !lateEvent.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(lateEvent.isHittable)
        XCTAssertEqual(lateEvent.frame.minX, initialX, accuracy: 1)

        let boundaryEvent = app.buttons["week-event-demo-week-boundary-event"]
        XCTAssertTrue(boundaryEvent.exists)
        for _ in 0..<4 where !boundaryEvent.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(boundaryEvent.isHittable)
        XCTAssertGreaterThanOrEqual(boundaryEvent.frame.height, 44)
        XCTAssertTrue(
            planner.frame.insetBy(dx: -1, dy: -1).contains(boundaryEvent.frame),
            "Boundary event \(boundaryEvent.frame) should fit inside planner \(planner.frame)"
        )
    }

    func testWeekAllDayRowsStayFixedDuringHorizontalDrag() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles", "-demo-week-overlaps"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()
        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let planner = app.scrollViews["week-planner"]
        let allDayList = app.descendants(matching: .any)["week-all-day-list"]
        XCTAssertTrue(planner.waitForExistence(timeout: 3))
        let allDayEvent = app.buttons["week-all-day-demo-week-all-day-event-2"]
        let lateAllDayEvent = app.buttons["week-all-day-demo-week-all-day-event"]
        XCTAssertTrue(allDayList.waitForExistence(timeout: 3))
        XCTAssertTrue(allDayEvent.waitForExistence(timeout: 3))
        XCTAssertTrue(lateAllDayEvent.exists)
        XCTAssertTrue(allDayEvent.isHittable)
        let initialFrame = allDayEvent.frame
        let periodTitle = app.staticTexts["calendar-header-period"]
        let initialPeriod = periodTitle.label

        allDayList.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: allDayList.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
            )

        XCTAssertEqual(allDayEvent.frame.minX, initialFrame.minX, accuracy: 1)
        XCTAssertEqual(periodTitle.label, initialPeriod)

        for _ in 0..<4 where !lateAllDayEvent.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(lateAllDayEvent.isHittable)
        let boundaryTask = app.buttons["week-task-demo-week-boundary-task"]
        for _ in 0..<4 where !boundaryTask.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(boundaryTask.isHittable)
    }

    func testWeekSelectionClearsWhenProfileChanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles", "-demo-week-overlaps"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()
        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let schoolAllDayEvent = app.buttons["week-all-day-demo-week-all-day-event-2"]
        XCTAssertTrue(schoolAllDayEvent.waitForExistence(timeout: 3))
        schoolAllDayEvent.tap()
        let openSelectedItem = app.buttons["week-open-selected-item"]
        let planner = app.scrollViews["week-planner"]
        for _ in 0..<8 where !openSelectedItem.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(openSelectedItem.waitForExistence(timeout: 3))
        XCTAssertTrue(openSelectedItem.isHittable)

        app.buttons["profile-selector"].tap()
        let personal = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000001"]
        XCTAssertTrue(personal.waitForExistence(timeout: 3))
        personal.tap()

        XCTAssertTrue(openSelectedItem.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["week-all-day-demo-week-all-day-event-2"].exists)
    }

    func testWeekSelectionClearsWhenMovingToAnotherWeek() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles", "-demo-week-overlaps"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()
        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let schoolAllDayEvent = app.buttons["week-all-day-demo-week-all-day-event-2"]
        XCTAssertTrue(schoolAllDayEvent.waitForExistence(timeout: 3))
        schoolAllDayEvent.tap()
        let openSelectedItem = app.buttons["week-open-selected-item"]
        let planner = app.scrollViews["week-planner"]
        for _ in 0..<8 where !openSelectedItem.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(openSelectedItem.waitForExistence(timeout: 3))
        XCTAssertTrue(openSelectedItem.isHittable)

        let period = app.staticTexts["calendar-header-period"]
        let originalPeriod = period.label
        app.buttons["calendar-period-next"].tap()
        let changedPeriod = NSPredicate(format: "label != %@", originalPeriod)
        expectation(for: changedPeriod, evaluatedWith: period)
        waitForExpectations(timeout: 3)

        XCTAssertTrue(openSelectedItem.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["week-all-day-demo-week-all-day-event-2"].exists)
    }

    func testCompactHeightWeekKeepsAllDayActionsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles", "-demo-week-overlaps"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()
        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let planner = app.scrollViews["week-planner"]
        XCTAssertTrue(planner.waitForExistence(timeout: 3))

        let allDayEvent = app.buttons["week-all-day-demo-week-all-day-event-2"]
        XCTAssertTrue(allDayEvent.waitForExistence(timeout: 3))
        for _ in 0..<4 where !allDayEvent.isHittable {
            planner.swipeDown()
        }
        XCTAssertTrue(allDayEvent.isHittable)
        allDayEvent.tap()

        let open = app.buttons["week-open-selected-item"]
        for _ in 0..<8 where !open.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(open.isHittable)
    }

    func testCompactHeightWeekKeepsStandaloneTaskActionsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles", "-demo-week-overlaps"]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()
        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let planner = app.scrollViews["week-planner"]
        XCTAssertTrue(planner.waitForExistence(timeout: 3))

        let task = app.buttons["week-task-demo-week-boundary-task"]
        for _ in 0..<8 where !task.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(task.isHittable)
        task.tap()

        let schedule = app.buttons["week-task-schedule-demo-week-boundary-task"]
        for _ in 0..<8 where !schedule.isHittable {
            planner.swipeUp()
        }
        XCTAssertTrue(schedule.waitForExistence(timeout: 3))
        XCTAssertTrue(schedule.isHittable)
    }

    func testSchoolWeekEventDetailsExpandInlineAtAccessibilityXXXL() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-demo-profiles",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        app.buttons["profile-selector"].tap()
        let school = app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"]
        XCTAssertTrue(school.waitForExistence(timeout: 3))
        school.tap()

        let weekMode = app.buttons["calendar-mode-week"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 3))
        weekMode.tap()

        let event = app.buttons["week-event-demo-school-event"]
        XCTAssertTrue(event.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(event.frame.width, 44)
        XCTAssertGreaterThanOrEqual(event.frame.height, 44)
        event.tap()

        let inlineDetail = app.otherElements["week-event-detail-inline"]
        XCTAssertTrue(inlineDetail.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["week-event-detail-title"].label, "INF 2003 Lecture")
        let close = app.buttons["week-event-detail-close"]
        let open = app.buttons["week-open-selected-item"]
        XCTAssertTrue(close.isHittable)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)

        for _ in 0..<6 where !open.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(open.isHittable)
        XCTAssertGreaterThanOrEqual(open.frame.height, 44)
    }
}
