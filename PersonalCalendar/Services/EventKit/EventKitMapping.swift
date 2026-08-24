import EventKit
import UIKit

extension CGColor {
    var hexRGB: String {
        let color = UIColor(cgColor: self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: nil) else {
            return "#000000"
        }

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

extension CalendarEventSnapshot {
    init(event: EKEvent) {
        let calendar = event.calendar

        self.init(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: calendar?.calendarIdentifier ?? "",
            calendarTitle: calendar?.title ?? "",
            allowsModification: calendar?.allowsContentModifications ?? false,
            hasRecurrence: event.hasRecurrenceRules
        )
    }
}
