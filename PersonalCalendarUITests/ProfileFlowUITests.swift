import XCTest

@MainActor
final class ProfileFlowUITests: XCTestCase {
    func testSchoolProfileFiltersAllTabsWhileEverythingExcludesUnassignedBirthdays() {
        continueAfterFailure = false
        let app = launch(arguments: ["-demo-profiles"])

        chooseProfile("School", in: app)
        assertCalendarContainsSchoolEvent(in: app)

        selectTab("Today", in: app)
        let todaySchoolEvent = app.buttons["agenda-open-event-demo-school-event"]
        XCTAssertTrue(todaySchoolEvent.waitForExistence(timeout: 3))
        XCTAssertTrue(todaySchoolEvent.label.contains("INF 2003"))

        selectTab("Tasks", in: app)
        XCTAssertTrue(app.buttons["Open task Assignment 1"].waitForExistence(timeout: 3))

        selectTab("Routines", in: app)
        XCTAssertTrue(app.staticTexts["Review notes"].waitForExistence(timeout: 3))

        chooseProfile("Everything", in: app)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "Review notes")).count,
            1
        )
        selectTab("Calendar", in: app)
        assertCalendarContainsSchoolEvent(in: app)
        XCTAssertFalse(app.buttons["agenda-open-event-demo-birthday-event"].exists)
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["profile-selector"].waitForExistence(timeout: 3))
        return app
    }

    private func chooseProfile(_ name: String, in app: XCUIApplication) {
        let selector = app.buttons["profile-selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 3))
        selector.tap()

        let option = app.buttons[profileOptionIdentifier(for: name)]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()

        let selected = expectation(
            for: NSPredicate(format: "value == %@", name),
            evaluatedWith: selector
        )
        wait(for: [selected], timeout: 3)
    }

    private func profileOptionIdentifier(for name: String) -> String {
        switch name {
        case "School":
            return "profile-option-C0A10000-0000-4000-8000-000000000002"
        case "Everything":
            return "profile-option-everything"
        default:
            XCTFail("No deterministic profile option identifier for \(name)")
            return "profile-option-missing"
        }
    }

    private func selectTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 3))
    }

    private func assertCalendarContainsSchoolEvent(in app: XCUIApplication) {
        let expand = app.buttons["Expand day"]
        if expand.waitForExistence(timeout: 1) {
            expand.tap()
        }

        let event = app.buttons["agenda-open-event-demo-school-event"]
        XCTAssertTrue(event.waitForExistence(timeout: 3))
        XCTAssertTrue(event.label.contains("INF 2003"))
    }
}
