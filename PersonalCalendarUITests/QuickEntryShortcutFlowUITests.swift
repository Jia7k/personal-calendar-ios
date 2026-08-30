import XCTest

@MainActor
final class QuickEntryShortcutFlowUITests: XCTestCase {
    func testQueuedShortcutCapturesDrainInFIFOOrderWithoutSaving() {
        continueAfterFailure = false
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
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
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

        XCTAssertTrue(destination.waitForExistence(timeout: 5))
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
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
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
}
