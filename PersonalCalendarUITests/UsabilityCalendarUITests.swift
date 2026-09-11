import XCTest

@MainActor
final class UsabilityCalendarUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
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
