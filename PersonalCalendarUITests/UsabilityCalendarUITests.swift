import XCTest

@MainActor
final class UsabilityCalendarUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testDayTrayShowsSelectedDayEventTotalBelowDate() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        let count = app.staticTexts["day-tray-event-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5), "The day card needs an event total even when its preview is collapsed.")
        revealDayElement(count, in: app)
        XCTAssertEqual(count.label, "1 event")
        let title = app.staticTexts["day-tray-date"]
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThanOrEqual(count.frame.minY, title.frame.maxY)
        XCTAssertEqual(count.frame.minX, title.frame.minX, accuracy: 1)
        attachScreenshot("Day card with total event count", app: app)
    }

    func testDayTrayTotalIncludesAllDayEventsAndUpdatesWithDateAndProfile() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles", "-demo-week-overlaps"]
        app.launch()

        let count = app.staticTexts["day-tray-event-count"]
        expectEventTotal("1 event", count: count)
        chooseSchoolProfile(in: app)
        expectEventTotal("9 events", count: count) // Five timed events and four all-day events.

        let expand = app.buttons["Expand day"]
        revealDayElement(expand, in: app)
        expand.tap()
        expectEventTotal("9 events", count: count)
        let collapse = app.buttons["Collapse day"]
        revealDayElement(collapse, in: app)
        collapse.tap()

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        let nextDay = app.buttons["calendar-day-\(parts.year!)-\(parts.month!)-\(parts.day!)"]
        revealDayElement(nextDay, in: app)
        nextDay.tap()
        expectEventTotal("0 events", count: count)

        app.buttons["calendar-period-today"].tap()
        expectEventTotal("9 events", count: count)
        app.buttons["profile-selector"].tap()
        app.buttons["profile-option-C0A10000-0000-4000-8000-000000000001"].tap()
        expectEventTotal("1 event", count: count)
    }

    func testDayTrayCountAndActionsFitAtAccessibilityXXXL() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-demo-profiles",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        let count = app.staticTexts["day-tray-event-count"]
        expectEventTotal("1 event", count: count)
        let scroller = app.scrollViews.firstMatch
        revealDayElement(count, in: app)
        XCTAssertTrue(scroller.frame.contains(count.frame))
        XCTAssertGreaterThanOrEqual(count.frame.minY, app.staticTexts["day-tray-date"].frame.maxY)
        attachScreenshot("Day event total at maximum text size", app: app)

        let expand = app.buttons["Expand day"]
        revealDayElement(expand, in: app)
        XCTAssertTrue(expand.isHittable)
        XCTAssertGreaterThanOrEqual(expand.frame.height, 44)
        expand.tap()
        expectEventTotal("1 event", count: count)
        XCTAssertTrue(app.buttons["Collapse day"].exists)
    }

    func testDayTrayDoesNotClaimZeroEventsWhenCalendarAccessIsDenied() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-calendar-denied"]
        app.launch()
        XCTAssertTrue(app.buttons["calendar-permission-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["day-tray-date"].exists)
        XCTAssertFalse(app.staticTexts["day-tray-event-count"].exists)
    }

    private func expectEventTotal(_ label: String, count: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", label), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed, file: file, line: line)
    }

    private func revealDayElement(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<30 {
            let scroller = app.scrollViews.firstMatch
            XCTAssertTrue(scroller.exists)
            let frame = scroller.frame
            let bottom = min(frame.maxY, app.tabBars.firstMatch.frame.minY)
            let visible = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bottom - frame.minY)
            if visible.contains(element.frame) { return }
            let delta = element.frame.midY - visible.midY
            let distance = min(max(abs(delta), 20), visible.height * 0.3)
            // A full swipe can begin on the floating tab bar on a short iPhone.
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: visible.midX, dy: visible.midY))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta > 0 ? -distance : distance)), withVelocity: 150, thenHoldForDuration: 0.1)
        }
        XCTFail("Could not reveal day-card element: \(element.identifier)")
    }

    func testCalendarHeaderMakesProfileAndDateActionsClearAtAccessibilityXXXL() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-demo-profiles",
            "-demo-calendar-actions",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let selector = app.buttons["profile-selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 3))
        XCTAssertTrue(selector.label.localizedCaseInsensitiveContains("Personal"))
        XCTAssertGreaterThanOrEqual(selector.frame.height, 44)

        let jump = app.buttons["calendar-jump-open"]
        XCTAssertTrue(jump.waitForExistence(timeout: 3))
        XCTAssertTrue(jump.isHittable)
        XCTAssertGreaterThanOrEqual(jump.frame.height, 44)
        jump.tap()
        XCTAssertTrue(app.datePickers["calendar-jump-date-picker"].waitForExistence(timeout: 3))
        app.buttons["calendar-jump-cancel"].tap()

        XCTAssertTrue(app.buttons["calendar-search-open"].isHittable)
        XCTAssertTrue(app.buttons["calendar-settings-open"].isHittable)
        XCTAssertTrue(app.buttons["calendar-period-today"].isHittable)
        XCTAssertTrue(app.buttons["calendar-period-previous"].isHittable)
        XCTAssertTrue(app.buttons["calendar-period-next"].isHittable)
    }

    func testClassBlockCompactsVisuallyWhilePreviewRetainsFullTitleAndOffersActions() {
        let app = launchActionFixture()
        chooseSchoolProfile(in: app)
        app.buttons["calendar-mode-week"].tap()

        let event = app.buttons["week-event-demo-calendar-actions-physical"]
        scrollToHittable(event, in: app)
        XCTAssertTrue(event.exists)
        XCTAssertTrue(event.isHittable)
        XCTAssertTrue(
            event.label.contains("INF 2001 - Introduction to Software Engineering (P7 Laboratory)"),
            "The event control must retain the full provider title for accessibility."
        )
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Task 3 compact class block before event preview"
        attachment.lifetime = .keepAlways
        add(attachment)

        event.tap()
        XCTAssertEqual(
            app.staticTexts["week-event-detail-title"].label,
            "INF 2001 - Introduction to Software Engineering (P7 Laboratory)"
        )
        revealPreviewElement(app.buttons["week-event-directions"], in: app)
        revealPreviewElement(app.buttons["week-event-copy-location"], in: app)
        let join = app.buttons["week-event-join-call"]
        revealPreviewElement(join, in: app)
        XCTAssertEqual(join.value as? String, "https://meet.google.com/abc-defg-hij")
        XCTAssertTrue(app.buttons["week-open-selected-item"].exists)

        revealPreviewElement(app.buttons["week-event-directions"], in: app)
        app.buttons["week-event-directions"].tap()
        let feedback = app.staticTexts["week-event-action-feedback"]
        revealPreviewElement(feedback, in: app)
        XCTAssertTrue(feedback.waitForExistence(timeout: 2))
        XCTAssertEqual(
            feedback.label,
            "Couldn’t open Maps. Copy the location and try another maps app."
        )

        revealPreviewElement(app.buttons["week-event-copy-location"], in: app)
        app.buttons["week-event-copy-location"].tap()
        revealPreviewElement(feedback, in: app)
        XCTAssertEqual(feedback.label, "Location copied.")
        attachScreenshot("Physical event preview with quick actions", app: app)
    }

    func testSchoolWeekHeaderWrapsAtAccessibilityXXXLOnNarrowPhone() {
        let app = launchActionFixture([
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        chooseSchoolProfile(in: app)
        app.buttons["calendar-mode-week"].tap()
        let jump = app.buttons["calendar-jump-open"]
        let selector = app.buttons["profile-selector"]
        attachScreenshot("School Week header at maximum text size", app: app)
        if app.windows.firstMatch.frame.width <= 375 {
            XCTAssertGreaterThan(jump.frame.height, 80, "The complete week range must wrap at this text size, not truncate to one line")
            XCTAssertGreaterThan(selector.frame.width, 150, "The School name needs a readable text label, not a clipped initial")
        }
        XCTAssertTrue(jump.isHittable)
        XCTAssertTrue(selector.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(jump.frame))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(selector.frame))
        XCTAssertGreaterThan(app.scrollViews["week-planner"].frame.height, 160, "Readable navigation must leave room for the agenda")
    }

    func testPhysicalEventActionsRemainReachableAtAccessibilityXXXL() {
        let app = launchActionFixture([
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        chooseSchoolProfile(in: app)
        app.buttons["calendar-mode-week"].tap()
        let event = app.buttons["week-event-demo-calendar-actions-physical"]
        scrollToHittable(event, in: app)
        XCTAssertTrue(event.isHittable)
        attachScreenshot("Accessibility event row before expansion", app: app)
        event.tap()
        XCTAssertEqual(event.value as? String, "Expanded")
        let planner = app.scrollViews["week-planner"]
        let detail = app.otherElements["week-event-detail-inline"]
        for _ in 0..<12 where !detail.exists { planner.swipeUp() }
        XCTAssertTrue(detail.exists)
        attachScreenshot("Physical event preview heading at Accessibility XXXL", app: app)

        for identifier in ["week-event-directions", "week-event-copy-location", "week-event-join-call", "week-open-selected-item"] {
            let action = app.buttons[identifier]
            planner.revealCalendarElement(action)
            XCTAssertTrue(action.isHittable, "Expected reachable \(identifier)")
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44)
        }
        attachScreenshot("Physical event preview actions at Accessibility XXXL", app: app)
    }

    func testOnlineOnlyMeetingHasCopyAndJoinWithoutDirections() {
        let app = launchActionFixture()
        chooseSchoolProfile(in: app)
        app.buttons["calendar-mode-week"].tap()

        let event = app.buttons["week-event-demo-calendar-actions-online"]
        scrollToHittable(event, in: app)
        XCTAssertTrue(event.exists)
        XCTAssertTrue(event.isHittable)
        event.tap()

        XCTAssertFalse(app.buttons["week-event-directions"].exists)
        revealPreviewElement(app.buttons["week-event-copy-location"], in: app)
        revealPreviewElement(app.buttons["week-event-join-call"], in: app)
        XCTAssertTrue(app.buttons["week-open-selected-item"].exists)
    }

    private func revealPreviewElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scroller = app.otherElements["week-event-detail-card"]
            .descendants(matching: .scrollView).firstMatch
        XCTAssertTrue(scroller.waitForExistence(timeout: 3), file: file, line: line)
        for _ in 0..<12 where !element.isHittable {
            if element.exists && element.frame.maxY <= scroller.frame.minY {
                scroller.swipeDown()
            } else {
                scroller.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    func testTallClassAtNarrowPhoneWidthRetainsFullAccessibilityTitleAndScreenshot() {
        let app = launchActionFixture()
        chooseSchoolProfile(in: app)
        app.buttons["calendar-mode-week"].tap()

        let event = app.buttons["week-event-demo-calendar-actions-tall"]
        scrollToHittable(event, in: app)
        XCTAssertTrue(event.exists)
        XCTAssertTrue(event.isHittable)
        XCTAssertTrue(
            event.label.contains(
                "BAC 2005 - Fintech Investment and Risk Management (S2 Seminar)"
            ),
            "The tall class block must retain the full provider title for accessibility."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Task 3 tall compact class block at narrow phone width"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchActionFixture(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles", "-demo-calendar-actions"] + arguments
        app.launch()
        return app
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

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        let planner = app.scrollViews["week-planner"]
        XCTAssertTrue(planner.waitForExistence(timeout: 3))
        for _ in 0..<10 where !element.isHittable {
            planner.swipeUp()
        }
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
