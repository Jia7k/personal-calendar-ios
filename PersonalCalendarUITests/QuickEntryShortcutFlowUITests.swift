import XCTest

@MainActor
final class QuickEntryShortcutFlowUITests: XCTestCase {
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
}
