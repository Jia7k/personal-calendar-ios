import SwiftUI
import WidgetKit

@main
struct PersonalCalendarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        WeekTimetableWidget()
        TimetableLiveActivity()
    }
}
