import XCTest

@MainActor
final class QuickEntryShortcutFlowUITests: XCTestCase {
    func testQueuedShortcutCapturesDrainInFIFOOrderWithoutSaving() {
        continueAfterFailure = false
        let firstCaptureTitle = "First queued class review"
        let secondCaptureTitle = "Second queued errand"
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-demo-profiles",
            "-demo-queued-shortcut-quick-entry"
        ]
        app.launch()

        let source = app.descendants(matching: .any)["quick-entry-capture-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))

        let destination = app.descendants(matching: .any)["quick-entry-destination"]
        XCTAssertTrue(app.textFields["quick-entry-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.textFields["quick-entry-title"].value as? String,
            firstCaptureTitle
        )
        scrollToDestination(destination, in: app)
        XCTAssertEqual(destination.value as? String, "Google School")
        XCTAssertFalse(app.descendants(matching: .any)["quick-entry-saved"].exists)

        app.buttons["quick-entry-back"].tap()
        let input = app.textFields["quick-entry-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(
            input.value as? String,
            "First queued class review today at 3pm"
        )
        discardCapturedEntry(in: app)

        XCTAssertTrue(app.textFields["quick-entry-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.textFields["quick-entry-title"].value as? String,
            secondCaptureTitle
        )
        scrollToDestination(destination, in: app)
        XCTAssertEqual(destination.value as? String, "Home")
        XCTAssertFalse(app.descendants(matching: .any)["quick-entry-saved"].exists)

        app.buttons["quick-entry-back"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(
            input.value as? String,
            "Second queued errand tomorrow at 4pm"
        )
        discardCapturedEntry(in: app)

        XCTAssertFalse(source.waitForExistence(timeout: 2))
        XCTAssertTrue(app.tabBars.buttons["Calendar"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["quick-entry-saved"].exists)

        app.buttons["profile-selector"].tap()
        let everything = app.buttons["profile-option-everything"]
        XCTAssertTrue(everything.waitForExistence(timeout: 3))
        everything.tap()
        let openSearch = app.buttons["calendar-search-open"]
        XCTAssertTrue(openSearch.waitForExistence(timeout: 3))
        openSearch.tap()
        XCTAssertTrue(app.otherElements["calendar-search-screen"].waitForExistence(timeout: 3))
        let searchField = app.textFields["calendar-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        assertTaskAndEventProvidersDoNotContain(
            firstCaptureTitle,
            using: searchField,
            in: app
        )
        assertTaskAndEventProvidersDoNotContain(
            secondCaptureTitle,
            using: searchField,
            in: app
        )
    }

    func testShortcutCaptureOpensExactSchoolReviewWithoutSavingAutomatically() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-demo-profiles",
            "-demo-shortcut-quick-entry"
        ]
        app.launch()

        let source = app.descendants(matching: .any)["quick-entry-capture-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(
            source.label,
            "Captured from Siri or Shortcuts — review before saving."
        )

        let destination = app.descendants(matching: .any)["quick-entry-destination"]
        scrollToDestination(destination, in: app)
        XCTAssertEqual(destination.value as? String, "Google School")
        XCTAssertTrue(app.buttons["quick-entry-save"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["quick-entry-saved"].exists)

        app.buttons["quick-entry-back"].tap()
        let input = app.textFields["quick-entry-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(
            input.value as? String,
            "Shortcut study session today at 3pm"
        )
        XCTAssertTrue(source.exists)
    }

    private func discardCapturedEntry(in app: XCUIApplication) {
        app.buttons["quick-entry-cancel"].tap()
        let confirmation = app.alerts["Discard quick entry?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Discard"].tap()
    }

    private func scrollToDestination(
        _ destination: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3), file: file, line: line)
        for _ in 0..<10 where !destination.isHittable { form.swipeUp() }
        XCTAssertTrue(destination.isHittable, file: file, line: line)
    }

    private func assertTaskAndEventProvidersDoNotContain(
        _ title: String,
        using searchField: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        replaceQuery(searchField, with: title)
        for resultPrefix in [
            "calendar-search-result-event|",
            "calendar-search-result-task|"
        ] {
            let matchingResult = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                resultPrefix,
                title
            )).firstMatch
            XCTAssertFalse(
                matchingResult.waitForExistence(timeout: 1),
                "Discarded capture unexpectedly appeared in a task/event provider.",
                file: file,
                line: line
            )
        }
    }

    private func replaceQuery(_ field: XCUIElement, with query: String) {
        field.tap()
        let current = field.value as? String ?? ""
        if current != "Events, tasks, routines" {
            for _ in current {
                field.typeText(XCUIKeyboardKey.delete.rawValue)
            }
        }
        field.typeText(query)
    }
}
