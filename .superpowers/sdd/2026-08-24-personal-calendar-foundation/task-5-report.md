# Task 5 Report — Apple Reminders

## Result

Implemented basic Apple Reminders read, create, and completion support. `AppEnvironment.bootstrap` constructs one long-lived `EKEventStore` and injects it into both `EventKitCalendarService` and `EventKitRemindersService`.

## Behaviour delivered

- Reminder validation rejects whitespace-only titles.
- Reminder lists respect reminder full-access state.
- Fetch filters selected lists, returns a real empty EventKit result as `[]`, and throws `ReminderFetchError.missingResult` if EventKit supplies `nil`.
- Fetch maps only callback-supplied `EKReminder` occurrences; it never expands recurrence rules.
- Explicit missing lists and read-only lists fail creation; nil list IDs use Apple’s default list. Completion rejects missing/read-only reminders and saves with `commit: true`.
- Mapping preserves date-only semantics: `dueHasTime` is set only if `dueDateComponents.hour` exists, and date-only agenda items are unscheduled rather than given an invented time.

## Actor isolation

`EventKitRemindersService` and its `EKEventStore` are `@MainActor`. The EventKit fetch callback immediately creates `Task { @MainActor in ... }`; `EKReminder` objects are converted to immutable `ReminderSnapshot` values only in that main-actor task. The Swift 6 focused-test build compiled this code without actor/sendability diagnostics, so no unsafe annotation or preconcurrency suppression was used.

## RED → GREEN evidence

1. RED: after adding `testReminderDraftRejectsBlankTitle`, regeneration plus the focused mapping command failed with `cannot find 'ReminderDraftValidator' in scope` (and consequent type-inference errors).
2. GREEN: after adding the validator/service, the focused suite completed with `Executed 7 tests, with 0 failures`.
3. RED: after temporarily removing the date-only agenda initializer, the focused command failed with `extra argument 'reminder' in call`.
4. GREEN: restoring the initializer passed. Final focused command (`xcodegen generate && xcodebuild test ... -only-testing:PersonalCalendarTests/EventKitServiceMappingTests`) passed with 9 tests and 0 failures; the generic simulator build passed. `git diff --check` also passed.

## Deferred-ledger coverage

- Added a focused fake-reminder test proving the configured fetch error is thrown.
- Added valid EventDraft no-throw coverage and equal-date rejection.
- Added deterministic RGB hex-format coverage (`#4080BF`).

## Files changed

- `PersonalCalendar/Services/EventKit/EventKitRemindersService.swift` (new)
- `PersonalCalendar/Services/EventKit/EventKitMapping.swift`
- `PersonalCalendar/App/AppEnvironment.swift`
- `PersonalCalendar/Domain/AgendaItem.swift`
- `PersonalCalendarTests/Services/EventKitServiceMappingTests.swift`
- `PersonalCalendarTests/Support/Fakes.swift`
- `PersonalCalendar.xcodeproj/project.pbxproj` (regenerated and staged)

## Self-review

Checked the explicit-list fallback branch, write permissions, save commits, `nil` callback failure, recurring-occurrence non-synthesis, date-only mapping, shared-store lifetime, and Swift 6 compilation. No formatting errors were reported by `git diff --check`.

## Concerns

No known code concerns. EventKit objects are not unit-constructed for mapper tests because doing so would require a brittle Apple-framework harness; pure snapshot/agenda behavior is covered, while the full service compiles under the simulator SDK.
