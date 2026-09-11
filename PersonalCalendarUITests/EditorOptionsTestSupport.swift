import XCTest

extension XCUIApplication {
    @MainActor
    func revealEditorOptions(_ editor: String, file: StaticString = #filePath, line: UInt = #line) {
        let disclosure = buttons["\(editor)-editor-more-options"]
        for _ in 0..<8 where !disclosure.isHittable {
            swipeUp()
        }
        XCTAssertTrue(disclosure.isHittable, "More options should be reachable", file: file, line: line)
        guard disclosure.isHittable else { return }
        disclosure.tap()
    }
}
