# Personal Calendar

Requires iOS 17+ and XcodeGen. Generate the project with `xcodegen generate`.

Build with `xcodegen generate && xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`.

Run tests with `xcodegen generate && xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

Use the [foundation accessibility manual-QA checklist](docs/manual-qa/foundation-accessibility.md) for Dark Mode, Reduce Motion, VoiceOver, and Accessibility XXXL checks that automation cannot prove visually.

The app stores events in Apple Calendar, tasks in Apple Reminders, and routines locally with SwiftData. It is local-only: no backend, account, analytics, or CloudKit entitlement.

## Data ownership

- Events remain in Apple Calendar.
- Tasks remain in Apple Reminders.
- Routines, completion history, categories, and preferences stay on this iPhone.
- A manual backup contains only app-owned data.

## Device installation

Open `PersonalCalendar.xcodeproj`, choose your Development Team under Signing & Capabilities, connect an iPhone running iOS 17 or later, and press Run. A free Personal Team installation may need to be renewed periodically.

The app and `PersonalCalendarWidgets` extension both use the App Group `group.local.personalcalendar.shared`. Provision that App Group for both bundle identifiers before installing on a physical device.

## School timetable widgets

The timetable uses timed Monday–Friday events from the calendars selected in Settings. Open the app after changing Calendar events so the local widget snapshot can sync.

- **Next Class:** customize the Lock Screen, choose **Add Widgets**, select **My Calendar**, and add the rectangular **Next Class** widget.
- **School Week:** edit the Home Screen, choose **Add Widget**, select **My Calendar**, and add the medium **School Week** widget.
- **Full timetable Live Activity:** in My Calendar, open **Settings → School timetable** and tap **Start Today's Timetable**. Use **Stop Live Activity** from the same screen when finished.

This MVP is local-only and does not use a push server. Permanent widgets remain available from the shared weekly snapshot, but the app must be opened to sync EventKit changes. The Live Activity updates while the app has runtime and iOS limits a Live Activity to eight active hours; guaranteed automatic background start, update, and end are outside this MVP.
