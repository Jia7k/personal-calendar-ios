import SwiftUI
import UIKit
import XCTest
@testable import PersonalCalendar

final class CalendarThemeTests: XCTestCase {
    func testHarborAndLinenRemainsLightAndAccessibleWhenDeviceUsesDarkAppearance() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        let lightBackground = resolved(CalendarTheme.background, traits: light)
        let lightSurface = resolved(CalendarTheme.surface, traits: light)

        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String, "Light")

        for color in [
            CalendarTheme.accent,
            CalendarTheme.background,
            CalendarTheme.surface,
            CalendarTheme.selectionFill,
            CalendarTheme.event,
            CalendarTheme.task,
            CalendarTheme.routine
        ] {
            XCTAssertEqual(resolved(color, traits: light), resolved(color, traits: dark))
        }

        XCTAssertGreaterThanOrEqual(contrast(.white, resolved(CalendarTheme.accent, traits: light)), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(resolved(CalendarTheme.accent, traits: light), lightBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(resolved(CalendarTheme.event, traits: light), lightSurface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(resolved(CalendarTheme.task, traits: light), lightSurface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(resolved(CalendarTheme.routine, traits: light), lightSurface), 4.5)

        XCTAssertGreaterThan(contrast(lightBackground, lightSurface), 1.02)
        XCTAssertNotEqual(resolved(CalendarTheme.selectionFill, traits: light), lightBackground)
    }

    private func resolved(_ color: Color, traits: UITraitCollection) -> UIColor {
        UIColor(color).resolvedColor(with: traits)
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        func linearized(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }
}

@MainActor
final class CalendarToolbarActionLabelTests: XCTestCase {
    func testAccessibility5ActionsUseUniformBoundedLayout() {
        let actions: [(title: String, isProminent: Bool, isCompact: Bool)] = [
            ("Cancel", false, true),
            ("Back", false, true),
            ("Save", true, true),
            ("Saving…", true, true),
            ("Retry", true, true),
            ("Review", true, true),
            ("Done", true, true),
            ("Jump", true, true),
            ("Save Anyway", true, false),
            ("Cancel Delete", false, false),
            ("Confirm Delete", true, false)
        ]

        let sizes = actions.map { action in
            let size = measuredSize(
                title: action.title,
                isProminent: action.isProminent
            )
            XCTAssertGreaterThanOrEqual(size.width, CalendarTheme.minimumTapSize)
            XCTAssertGreaterThanOrEqual(size.height, CalendarTheme.minimumTapSize)
            XCTAssertLessThanOrEqual(size.height, 64, action.title)
            if action.isCompact {
                XCTAssertLessThanOrEqual(size.width, 96, action.title)
            }
            return size
        }

        let expectedHeight = sizes[0].height
        for (action, size) in zip(actions, sizes) {
            XCTAssertEqual(size.height, expectedHeight, accuracy: 0.5, action.title)
        }
    }

    private func measuredSize(title: String, isProminent: Bool) -> CGSize {
        let controller = UIHostingController(
            rootView: CalendarToolbarActionLabel(
                title: LocalizedStringKey(title),
                isProminent: isProminent
            )
            .environment(\.dynamicTypeSize, .accessibility5)
        )
        return controller.sizeThatFits(in: CGSize(width: 400, height: 400))
    }
}
