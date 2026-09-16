# Daily Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved B daily Live Activity with events and pending tasks/reminders, preserving weekly widgets.

**Architecture:** A profile-scoped daily provider reads existing calendar/reminder services independently of the weekly widget catalog. A pure shared projection creates a bounded, versioned ActivityKit state; the existing serialized lifecycle coordinator consumes daily profile identities. A new SwiftUI daily card replaces only the Live Activity's weekly rails.

**Tech Stack:** Swift 6, SwiftUI, ActivityKit, EventKit adapters, XCTest, XcodeGen; iOS 17 deployment floor.

**Spec:** `docs/superpowers/specs/2026-09-16-daily-live-activity-design.md`

## Global Constraints

- Test only on the user's iPhone 16 Pro. No other model or Simulator fallback without a new user instruction.
- Keep weekly `TimetableSnapshotV1`, `TimetableWidgetCatalogV1`, their App Group storage, and `TimeRailsView` unchanged.
- No backend, push service, new account, or direct editing from the Lock Screen is required.
- Undated tasks, tasks overdue from earlier days, completed tasks, and routines are outside this first version.
- Empty membership must return an empty result without calling the underlying service.
- Preserve the existing 3,500-byte content-state budget and the combined 4 KB ActivityKit limit.
- Keep the existing foreground auto-start opt-in, manual start, Stop-for-now, and profile boundaries.
- Root alone runs builds/tests to avoid concurrent device sessions. Use demo/in-memory fixtures, never create or complete real provider items for testing.
- No push. Test deployment is in scope; deleting the installed app or its data is not.

## Execution state and prerequisite

User override, 2026-09-16: “can u change the code first”. Implement now in the current checkout; defer execution of tests to the physical iPhone 16 Pro when available. This supersedes the baseline-before-code/TDD sequencing below, not the requirement to write regression tests or honestly report them as unrun. Compilation/static review are allowed now; no Simulator test substitution, phone installation, or push in this code-first pass.

2026-09-16, code-first implementation: daily projection/payload, scoped provider, lifecycle wiring, settings, daily Lock Screen/Dynamic Island UI, and isolated test-launch storage/notifications are implemented in the working tree. Added 59 unit regression cases and 3 UI settings smoke cases; none have run. Final app, extension, unit-test and UI-test compilation succeeded. Independent static review findings were addressed, including source-cache privacy, time-zone changes, concurrent fetch ordering, restore restart ordering, and bounded accessibility layouts. Weekly widget sources/storage remain unchanged. No installation, push, or commit has been performed in this pass.

Final verification: `xcodebuild build-for-testing -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS' -derivedDataPath /tmp/personal-calendar-daily-codecheck CODE_SIGNING_ALLOWED=NO` exited 0 with `TEST BUILD SUCCEEDED`; log `/tmp/personal-calendar-daily-final-build.log`. This compiles tests but does not execute them. `git diff --check` passed. All phone behavior, regression execution and visual acceptance remain pending on the physical iPhone 16 Pro. The original test-first/commit checkboxes below intentionally remain unchecked where execution has not happened; do not repeat implemented source work simply because a red/green verification box is still open.

Earlier device prerequisite: the paired physical iPhone 16 Pro was identified, but disconnected before the explicit-device `build-for-testing` command could compile (exit 70). No tests launched and no app was installed. Do not substitute another device or Simulator; reconnecting is only needed for the later phone-validation pass.

Revalidate the connected physical iPhone 16 Pro with `xcrun devicectl list devices` before running. Resolve its UDID/CoreDevice identifier and the existing development team from local device/signing settings; do not commit those device/account identifiers to the repository.

Use a new `/tmp` result bundle per test invocation. Do not reuse an existing `.xcresult` path. Keep DerivedData outside the repository. A failed build, unavailable device, signing failure, or locked phone is not a failing behavioral test and does not satisfy the TDD red step.

## File and interface map

- `PersonalCalendar/TimetableShared/DailyActivitySnapshot.swift`: Foundation-only normalized item/snapshot types shared by app and extension.
- `PersonalCalendar/TimetableShared/DailyActivityPresentation.swift`: deterministic hero, rows, overflow, status and countdown selection.
- `PersonalCalendar/TimetableShared/DailyActivityPayload.swift`: byte-bounded encoding and omission metadata.
- `PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift`: versioned daily payload and legacy decoding; no changes to weekly schema.
- `PersonalCalendar/Timetable/DailyActivitySnapshotBuilder.swift`: map app domain events/reminders to normalized daily items.
- `PersonalCalendar/Timetable/DailyActivitySnapshotCoordinator.swift`: authorized fetching, profile metadata, availability, generation invalidation.
- `PersonalCalendar/Timetable/TimetableLiveActivityCoordinator.swift`: reuse serialization and driver, replace weekly inputs.
- `PersonalCalendarWidgets/DailyActivityView.swift`: Lock Screen/expanded SwiftUI presentation.
- Existing activity widget, route resolver, settings, environment and refresh hooks consume these units.
- New tests live in `PersonalCalendarTests/Timetable/`; UI settings coverage goes in `PersonalCalendarUITests/DailyLiveActivityUITests.swift`.

The normalized item represents `.event` or `.task`, stable identity, title/abbreviation, optional event interval, optional task due date, date-only/all-day flags, optional location and `hasAlert`. It carries no notes or mutable provider address. The snapshot carries profile identity/name/icon, local day interval, time-zone identifier, generated time, per-source unavailability flags and items.

Public daily provider contract:

```swift
@MainActor
protocol DailyActivitySnapshotProviding: AnyObject {
    func snapshot(for profile: ProfileIdentity, now: Date) async throws -> DailyActivitySnapshot
    func invalidate()
}
```

`DailyActivitySnapshotBuilder.makeSnapshot(profile:scope:events:reminders:now:)` consumes `DailyActivityProfile`, `ProfileScope`, `[CalendarEventSnapshot]`, `[ReminderSnapshot]` and an explicit clock. Define `DailyActivityProfile` with `id: ProfileIdentity`, `name: String`, and `symbolName: String`; the Everything profile uses `.everything`, never a forged saved UUID.

`DailyActivityPresentation.make(snapshot:now:rowLimit:)` returns `hero`, `rows`, `hiddenCount: Int?`, `requiresRefresh`, and `countdownBoundary: Date?`. The full normalized item remains available to row rendering. `DailyActivityPayload.make(snapshot:attributes:now:)` returns an optional bounded payload; inability to fit required metadata is an explicit failure.

## Task 1: Establish safe iPhone 16 Pro baseline

**Files:** Inspect `project.yml`, the shared Xcode scheme, `PersonalCalendarApp.swift`, and demo environment before changing the test harness. Record results here.

- [x] After the user accepts the licence, run `xcrun devicectl list devices` and `xcodebuild -showdestinations -project PersonalCalendar.xcodeproj -scheme PersonalCalendar`; confirm the exact physical model/UDID. Do not select a generic or alternate test destination. Confirmed iPhone 16 Pro, iPhone17,1, iOS 27.0 and Developer Mode enabled; connectivity was subsequently lost.
- [ ] Confirm the phone is unlocked, connected and available for development. Inspect signing settings and profiles without weakening App Group entitlements.
- [ ] Make a temporary, test-only xctestrun configuration from `build-for-testing` with the unit host launched in demo/in-memory mode. Inspect launch arguments and persistent side effects first: existing `-ui-testing` startup drains the real App Group quick-entry handoff store, so it is not sufficient isolation by itself. Use a separate test handoff store and prevent real notification/route writes in the test host before any launch. Keep this harness configuration out of release behavior.
- [ ] Run the existing Timetable/Profile unit baseline only on the confirmed phone. Expected: all selected tests pass. On failure, capture diagnostics before implementing the feature; never replace a behavioral red result with a signing/build error.

Read-only startup audit found these specific prerequisites for safe physical testing:

- In `PersonalCalendarApp.init`, select a temporary app-container `AppRouteHandoffStore(fileURL:)` before any call to `.appGroup()` when `-ui-testing` is present. The present demo queue-clearing loop must never run against the real App Group queue. Use a validated namespaced test-run identifier only when a test intentionally needs the same queue across launches; otherwise use a unique temporary file.
- In `AppEnvironment.demo`, replace only the demo `SystemNotificationScheduler` construction with an in-memory `NotificationScheduling` implementation. Demo providers/SwiftData/settings are already isolated, but the current scheduler can replace the real app's pending notifications and registers system categories on initialization. The live environment must keep the system scheduler.
- Under `-ui-testing`, skip system notification-delegate configuration and App Shortcut parameter publication. Existing UI notification-action coverage uses an in-app test trigger rather than a real delivered notification.
- Force `-ui-testing` for the hosted unit test app in the generated test-run configuration. Existing UI tests already supply it to their app launches. Do not assume XCTest host initialization avoids the live environment.

These are test-harness safeguards within Task 1, not extra end-user features. They are implemented and compiled in the code-first pass, but have not yet been verified by executing tests on the phone.

Device command template after the isolation check:

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar \
  -destination 'platform=iOS,id=<iphone-16-pro-udid>' \
  -parallel-testing-enabled NO \
  -derivedDataPath /tmp/personal-calendar-daily-activity-16pro \
  -only-testing:PersonalCalendarTests/TimetableProfileActivityTests \
  DEVELOPMENT_TEAM=<existing-development-team>
```

When using the isolated xctestrun configuration, use `test-without-building -xctestrun <the generated test configuration path>` with the same explicit destination and parallel-testing setting. The actual path is discovered from the build output, not guessed.

## Task 2: Normalize and project the remaining day

**Create:** `DailyActivitySnapshot.swift`, `DailyActivityPresentation.swift`, `DailyActivitySnapshotBuilder.swift`, and corresponding `DailyActivitySnapshotBuilderTests.swift` / `DailyActivityPresentationTests.swift`.

**Consumes:** existing domain snapshots and profile scope. **Produces:** shared normalized snapshot and presentation contracts above.

- [ ] Add fixture builders in `PersonalCalendarTests/Timetable/DailyActivityTestFixtures.swift`. Use Gregorian Asia/Singapore and explicit date components for 2026-09-16, not the wall clock. Create literal fixtures: current event 09:00–10:30; task due 10:45 with a 10:15 alert; event 11:00–12:00; date-only task; completed task; undated task; task due yesterday. At 09:40 expect the current event as hero and exactly the due task, next event, date-only task in the three rows.
- [ ] Write red assertions against `DailyActivityPresentation.make` and the builder, then run only those classes on the 16 Pro. Initial tests must catch actual selection/filtering behavior, not only missing type/compiler errors.

The core independently-derived assertion shape is:

```swift
let presentation = DailyActivityPresentation.make(
    snapshot: snapshot, now: now, rowLimit: 3
)
XCTAssertEqual(presentation.hero?.title, "Software Engineering")
XCTAssertEqual(presentation.rows.map(\.title), [
    "Submit lab report", "Database Systems", "Read lecture notes"
])
XCTAssertEqual(presentation.hiddenCount, 0)
```

- [ ] Implement normalization: intersect authorized membership; discard invalid dates/intervals; event identity includes occurrence date; reminder identity is source-qualified; exclude completed/no-due/prior-day reminders; preserve due-versus-alert distinction. Use the calendar's day interval and half-open intersection (`event.start < day.end && event.end > day.start`), not 86,400-second assumptions.
- [ ] Implement pure ranking: active event hero; otherwise earliest future timed item. Remaining active events, overdue-today tasks, chronological future items, all-day events and date-only tasks form rows, excluding hero. Tie-break deterministically using interval end when present, title and identity. A no-timed-item state has no countdown/progress.
- [ ] Add and run red/green cases for weekends, overnight events, overlaps, duplicate reminders, end boundary, due boundary, midnight, DST, source scope, and all-day/task-only days. Production changes that wrongly include prior-day tasks, use alert time as due time, or drop overnight events must fail these assertions.
- [ ] Self-review and commit this tested unit only after the 16 Pro tests pass.

## Task 3: Bound and version the activity state

**Create:** `DailyActivityPayload.swift`, `DailyActivityPayloadTests.swift`. **Modify:** `TimetableActivityAttributes.swift`, `TimetableActivityRouteResolver.swift`, existing route tests.

**Consumes:** Task 2 snapshot/projection. **Produces:** optional `daily` payload inside the existing content-state decoder; static schema 3 recognizes v1/v2 as legacy. Keep old fields decodeable; new activity instances use daily data. Include represented day/time zone explicitly rather than reinterpreting `weekStart`.

- [ ] Write failing codec/budget tests with literal old JSON fixtures and large Unicode titles. Assert daily round trip, legacy recognition, and both encoded limits; compare encoded bytes, not character count.

```swift
let stateBytes = try JSONEncoder().encode(state).count
let attributeBytes = try JSONEncoder().encode(attributes).count
XCTAssertLessThanOrEqual(stateBytes, 3_500)
XCTAssertLessThanOrEqual(stateBytes + attributeBytes, 4_096)
```

- [ ] Implement byte-bounded strings and priority retention. Preserve hero/nearest rows. Record coalesced expiry counts and enough omission ordering information to avoid a false “Next” claim; when metadata itself cannot fit, use unknown count plus “More in app”. Selection at render time filters expired retained events. Never fabricate dropped titles.
- [ ] Write red/green time-advance assertions: hidden events finishing reduce the hidden count; pending tasks remain; when only a dropped next item remains, show refresh-required rather than all-done or an incorrect retained “Next”.
- [ ] Make all new activity links profile-scoped day links without an entry ID. Verify decoded route equals the represented day/profile even after midnight. Preserve legacy route safety; invalid identifiers/time zones cannot silently route to private content under another profile.
- [ ] Run codec, projection and route tests on the 16 Pro; self-review and commit after passing.

## Task 4: Fetch daily sources independently and preserve lifecycle

**Create:** `DailyActivitySnapshotCoordinator.swift`, its tests, and `DailyActivityLifecycleTests.swift`. **Modify:** `TimetableLiveActivityCoordinator.swift` and existing activity coordinator/profile tests.

**Consumes:** Task 2 builder, Task 3 payload. **Produces:** daily provider above plus these activity APIs:

```swift
func start(profileIdentity: ProfileIdentity, now: Date = .now) async
func reconcileActive(now: Date = .now) async
func applyForegroundPreference(isEnabled: Bool, preferredProfileIdentity: ProfileIdentity?, now: Date = .now) async
func applyPreferenceSelectionChange(wasAutomaticallyEnabled: Bool, preferredProfileIdentity: ProfileIdentity?, now: Date = .now) async
func applyAutomaticStartSettingChange(isEnabled: Bool, preferredProfileIdentity: ProfileIdentity?, now: Date = .now) async
```

- [ ] Use in-memory repository/service doubles to write failing tests for task-only start, no fetch for empty membership, Everything union rather than all device data, source permission loss, and superseded async result rejection. Assert requests/returned items at the real provider boundary, not mock existence.
- [ ] Implement nonempty scope fetches and post-fetch filtering. Cache per identity/day/generation only. Invalidate on refresh/profile change; capture and recheck membership/authorization after async reminder work. A superseded request cannot overwrite a newer result or stop a newer activity.
- [ ] Compare configured and available membership to report partial-source unavailability. Intentional membership removal is not an error. On uncertain fetch failure, invalidate the cache, stop stale activity through the lifecycle owner, and expose a retryable error.
- [ ] Write failing driver-recording tests for manual reconcile without auto-start, one activity only, queued Stop winning over older work, latest selection winning over stale async work, deleted profile, legacy replacement, task-only eligibility, and attribute mismatch replacement.

Key behavioral assertion after reconciling with no existing activity:

```swift
await subject.reconcileActive(now: now)
XCTAssertTrue(driver.requests.isEmpty)
```

- [ ] Adapt the existing serialized writer to profile-identity inputs and the daily provider. Keep `reconcileActive` from creating an activity when none exists. Only the preference hook starts automatically; Start remains explicit. End duplicates even if they reference different valid profiles. Derive stale/terminal boundaries from daily state and existing freshness policy.
- [ ] Run all new and existing activity lifecycle tests on the 16 Pro. Preserve meaningful legacy migration assertions; do not rewrite expectations merely to match changed behavior. Self-review and commit.

## Task 5: Wire refresh, profile settings and the approved B card

**Create:** `PersonalCalendarWidgets/DailyActivityView.swift`, `PersonalCalendarUITests/DailyLiveActivityUITests.swift`.

**Modify:** `TimetableLiveActivity.swift`, `AppEnvironment.swift`, `RootTabView.swift`, `SettingsView.swift`, `TimetableSettingsView.swift`, `ProfilesSettingsView.swift`, and focused refresh/profile tests. Regenerate `PersonalCalendar.xcodeproj` with XcodeGen when new source files are added.

**Consumes:** Tasks 2–4 daily snapshot and lifecycle APIs. **Produces:** user-visible daily activity and profile-independent refresh.

- [ ] Add failing integration tests: weekly write failure does not suppress daily update; reminder-list membership removal invalidates daily data; manual activity refreshes with auto-start off; restored auto-start-off settings stop pre-restore activity even if weekly write fails.
- [ ] In both live and demo environment construction, create/inject the daily provider; remove weekly `onFailClosed { stop() }` coupling. Keep weekly refresh/reload in its own branch, followed independently by daily invalidation/reconcile. Root's subsequent foreground preference application can reuse the current generation rather than fetch twice.

The refresh ordering must retain the current permission/source/profile steps, then execute independent surface branches:

```swift
_ = try? timetableSnapshotCoordinator.refresh(now: now)
dailyActivitySnapshotCoordinator.invalidate()
await liveActivityCoordinator.reconcileActive(now: now)
```

- [ ] Profile edit/delete and backup restore always invalidate daily state, including reminder-list/name changes. The weekly `removedCalendarMembership` flag is not the daily invalidation signal. Missing/deleted preferred profiles still clear through existing profile selection/settings reconciliation.
- [ ] Settings picker uses repository/profile-selection metadata plus Everything, never weekly snapshot membership. Add an async daily selection preview with generation guard for fast selection changes; Start enablement uses eligible daily items. Keep current accessibility identifiers stable. Display partial availability/retry errors and the eight-hour/foreground refresh explanation.
- [ ] Build the B card using existing SwiftUI system styles, charcoal background, teal event marks and orange hollow task circles. Render header, current/next hero, progress only for an active event, space-fitting rows and truthful overflow. Use date-based timer text; no completion buttons. In Dynamic Island show the focused item/count, not weekly rails.
- [ ] Adapt row count for available height and Dynamic Type; do not shrink text to conceal overflow. Preserve privacy-sensitive redaction. When expired/stale/unknown-next, render the explicit refresh-required state instead of a false “Now”/“All done”.
- [ ] Add UI paths for selecting a reminders-only profile, starting/stopping/switching the activity, refresh error/retry, and disabled automatic start. Launch with isolated demo providers and inspect actual navigation/state; never create real Calendar/Reminders fixtures.
- [ ] Run integration/UI tests on the 16 Pro, inspect the actual Lock Screen and compact/expanded/minimal Dynamic Island, and capture long-title/accessibility cases on that phone only. Record whether a check was automated or manually observed. Self-review and commit after verification.

## Task 6: Regression, review and handoff

**Modify:** README feature/update-limit documentation; this plan's verification record.

- [ ] Run the complete unit suite on the 16 Pro, followed by the new daily UI paths and existing profile/backup/settings/calendar regressions. Do not run any other phone model or Simulator to replace an unavailable device.
- [ ] Verify existing weekly widget snapshot/catalog/selection/timeline/route tests are unchanged in behavior and passing; visually inspect the weekly widget only on the 16 Pro if available.
- [ ] Request an independent whole-change review covering scope privacy, async race handling, legacy decode, bounded payload, truthful stale/overflow behavior and unchanged widgets. Fix material findings with focused failing tests and rerun affected paths on the same device.
- [ ] Run `git diff --check`, inspect the full diff and test result bundles, and update README only with behavior actually verified. No claims of background guarantees or all-device coverage.
- [ ] Report exact passing/failing/not-run checks, any physical access blocker, and no-push status. Leave code inline for the user; do not merge/push or delete the app as an unrequested cleanup step.

## Plan self-review

Coverage: Task 2 handles all item/scope/day ordering rules; Task 3 handles byte limits, omissions, legacy state and navigation; Task 4 handles source privacy, concurrency and lifecycle; Task 5 handles refresh/settings/UI/accessibility; Task 6 covers regression and device evidence. Every task inherits the 16 Pro-only restriction. Task 1 is currently blocked by physical-device connectivity and must finish before production implementation.

Interfaces: shared normalized types have no EventKit dependency; app-side builder owns mapping; daily provider owns fetch invalidation; activity coordinator owns ActivityKit serialization; widgets only consume shared state. `reconcileActive` never auto-starts. No task requires changing weekly storage or `TimeRailsView`.
