import XCTest

extension XCUIElement {
    /// Use short, settled drags: full swipes can skip a 44-point control in an
    /// accessibility-size viewport, and further swipes in one direction cannot recover it.
    @MainActor
    func revealCalendarElement(_ element: XCUIElement, fullyVisible: Bool = false) {
        for _ in 0..<24 {
            let viewport = frame.insetBy(dx: -2, dy: -2)
            let target = element.frame
            if viewport.contains(target) && (fullyVisible || element.isHittable) { return }
            if !fullyVisible && target.height > viewport.height && element.isHittable { return }
            let delta = target.midY - viewport.midY
            if abs(delta) > viewport.height * 1.5 {
                if delta > 0 { swipeUp() } else { swipeDown() }
                continue
            }
            let distance = min(max(abs(delta), 20), frame.height * 0.24)
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: 0, dy: delta > 0 ? -distance : distance))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 100, thenHoldForDuration: 0.2)
        }
    }
}
