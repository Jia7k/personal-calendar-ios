# Task 6 Report: Local Notifications

## TDD evidence

RED command:

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/NotificationCoordinatorTests
```

RED output: `TEST FAILED` at compilation because `LocalNotificationRequest`, `NotificationScheduling`, and `NotificationCoordinator` did not exist.

GREEN command:

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/NotificationCoordinatorTests
```

GREEN output: `NotificationCoordinatorTests` executed 1 test with 0 failures; `TEST SUCCEEDED`.

## Implementation

- Added a replaceable local-notification scheduling protocol/value and a `UNUserNotificationCenter` adapter that replaces only `morning-summary` and `routine|` requests.
- Added the coordinator policy: deterministic routine identifiers, explicit reminder times only, 14-day horizon, 48-request nearest-first budget, snapshot-based morning summary, deferred count, and an actionable scheduling error.
- Persisted summary preferences and added Settings controls with bounded hour/minute inputs, next-timed-item disclosure, deferred-alert copy, and error presentation.
- Added `AppEnvironment.rescheduleNotifications`, which refreshes the scheduled day’s agenda and routines and can be reused by later tasks. It runs after foreground activation, notification permission changes, summary preference changes, routine mutations, and quick-entry saves.
- Added the single Task 6 XCTest happy path using a fake scheduler. It proves the summary body and bounded routine scheduling behavior.

## Files changed

- `PersonalCalendar.xcodeproj/project.pbxproj`
- `PersonalCalendar/App/AppEnvironment.swift`
- `PersonalCalendar/App/RootTabView.swift`
- `PersonalCalendar/Features/Routines/RoutinesView.swift`
- `PersonalCalendar/Features/Routines/RoutinesViewModel.swift`
- `PersonalCalendar/Features/Settings/NotificationSettingsView.swift`
- `PersonalCalendar/Features/Settings/SettingsView.swift`
- `PersonalCalendar/Features/Today/TodayView.swift`
- `PersonalCalendar/Features/Today/TodayViewModel.swift`
- `PersonalCalendar/Notifications/NotificationCoordinator.swift`
- `PersonalCalendar/Notifications/NotificationScheduling.swift`
- `PersonalCalendar/Notifications/SystemNotificationScheduler.swift`
- `PersonalCalendar/Settings/AppSettingsStore.swift`
- `PersonalCalendarTests/Notifications/NotificationCoordinatorTests.swift`

## Self-review

- `git diff --check` reported no whitespace errors.
- The adapter never creates duplicate local copies of Calendar or Reminders alerts.
- The coordinator clears app-owned notifications when notification authorization is unavailable and leaves unrelated pending requests untouched.
- Routine mutations from both the Routines and Today flows, plus quick entry, reschedule through the shared environment closure.

## Concerns

- Verification is deliberately limited to the requested one focused XCTest; no full suite was run.
- The real system notification adapter needs device-level manual validation for authorization, delivery, and lock-screen presentation.

## Commit

Pending commit amendment.
