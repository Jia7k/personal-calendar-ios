# Personal Calendar

Requires iOS 17+ and XcodeGen. Generate the project with `xcodegen generate`.

Build with `xcodegen generate && xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`.

Run tests with `xcodegen generate && xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

Use the [foundation accessibility manual-QA checklist](docs/manual-qa/foundation-accessibility.md) for the app's light appearance, Reduce Motion, VoiceOver, and Accessibility XXXL checks that automation cannot prove visually.

The app stores events in Apple Calendar, tasks in Apple Reminders, and routines locally with SwiftData. It is local-only: no backend, account, analytics, or CloudKit entitlement.

## Data ownership

- Events remain in Apple Calendar.
- Tasks remain in Apple Reminders.
- Routines, completion history, categories, and preferences stay on this iPhone.
- Profiles store references to selected Apple/Google calendars and reminder lists. They never copy, move, or delete provider content.
- A manual backup contains only app-owned data.

## Calendar profiles

Profiles group related calendars, reminder lists, and routines without changing their original source. Create or edit them in **Settings → Profiles**, then use the Profile menu in Calendar, Today, Tasks, or Routines.

For a school timetable synced from Google Calendar:

1. Keep the timetable in its own Google calendar and ensure it appears in Apple Calendar.
2. Open **Settings → Profiles → School**.
3. Select that dedicated calendar, the relevant assignment list, and any study routines. Choose writable defaults if new school items should be saved there.

**Everything** is the deduplicated union of content assigned to saved profiles. A provider calendar that is not assigned anywhere—such as Birthdays—does not appear in Everything. This keeps unrelated calendars out without disabling or deleting them.

## Device installation

Open `PersonalCalendar.xcodeproj`, choose your Development Team under Signing & Capabilities, connect an iPhone running iOS 17 or later, and press Run. A free Personal Team installation may need to be renewed periodically.

The app and `PersonalCalendarWidgets` extension both use the App Group `group.local.personalcalendar.shared`. Provision that App Group for both bundle identifiers before installing on a physical device.

## Timetable widgets

The timetable uses timed Monday–Friday events from the profile selected for each widget. Long-press a widget, choose **Edit Widget**, and select Personal, School, Work, or Everything. Widgets created by an older static build must be configured once after updating.

- **Next Class:** customize the Lock Screen, choose **Add Widgets**, select **My Calendar**, and add the rectangular **Next Class** widget.
- **Week Timetable:** edit the Home Screen, choose **Add Widget**, select **My Calendar**, and add the medium weekly widget.
- **Full timetable Live Activity:** open **Settings → Timetable**, select a profile, and tap **Start Live Activity**. Switching profiles ends the old activity before starting the selected one. Use **Stop Live Activity** when finished.

This MVP is local-only and does not use a push server. Widgets read an app-generated weekly snapshot, so open the app after changing Calendar events or profile membership to refresh them. A Live Activity updates while the app has runtime; iOS limits it to eight active hours, and guaranteed background start/update/end is outside this MVP.
