# Daily Assist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fast task triage, actionable routes and notifications, truthful timetable surfaces, safe task time blocking, capture-anywhere Quick Entry, and focused daily QOL actions to the existing profile-aware calendar app.

**Architecture:** Introduce one typed app-route foundation, then build each user journey as a focused model/service feature that reuses existing provider authority, profile scope, editors, refresh signals, and confirmation flows. App-owned settings retain only bounded preferences and history; EventKit and the routine repository remain authoritative.

**Tech Stack:** Swift 6, SwiftUI, Observation, EventKit abstractions, UserNotifications, WidgetKit, ActivityKit, AppIntents, MapKit, SwiftData, XCTest, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-27-daily-assist-design.md`

## Global Constraints

- Keep Apple Calendar/Reminders and the routine repository authoritative; do not create an app-owned copy of provider content.
- Keep the app local-first; add no account, backend, CloudKit, or server dependency.
- Keep the existing fixed light Harbor & Linen appearance.
- Resolve one exact `ProfileScope` per operation; never pass an empty source-ID set to a provider API whose empty contract means all sources.
- Never fall back from a missing/deleted saved profile to Everything.
- Every external mutation revalidates access, membership, item/source writability, and existence immediately before one write.
- Siri/Shortcuts/Spotlight/Action Button capture must open in-app confirmation and must never silently save.
- Do not promise guaranteed background Live Activity or widget refresh behavior.
- Use injected `Calendar`/`now` in models and pure logic; do not add `Calendar.current` or `Date()` inside deterministic components.
- Preserve 44-point controls, explicit VoiceOver labels/values, and accessibility-size list alternatives.
- Use focused test classes while implementing each task. Run broad suites only at the two milestones and final gate.

---

### Task 1: Overdue Sections and Pure Quick-Reschedule Rules

**Files:**
- Create: `PersonalCalendar/Features/Tasks/TaskQuickReschedule.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksViewModel.swift`
- Create: `PersonalCalendarTests/Features/TaskQuickRescheduleTests.swift`
- Modify: `PersonalCalendarTests/Features/FeatureViewModelTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ReminderSnapshot`, `ReminderScheduleValue`, injected `Calendar`, injected `now`.
- Produces:

```swift
enum TaskQuickReschedule: Equatable, Sendable {
    case laterToday
    case tomorrow
    case nextWeek
    case pick(Date, hasTime: Bool)
}

enum TaskQuickRescheduleError: Error, Equatable, Sendable {
    case recurringTaskRequiresEditor
    case invalidDate
}

struct TaskQuickReschedulePlanner: Sendable {
    let calendar: Calendar
    func schedule(
        for reminder: ReminderSnapshot,
        command: TaskQuickReschedule,
        now: Date
    ) throws -> ReminderScheduleValue
}

struct TaskRescheduleUndo: Equatable, Sendable {
    let reminderID: String
    let previousSchedule: ReminderScheduleValue?
}
```

- `TasksViewModel` adds `overdue`, `rescheduleUndo`, `quickReschedule(id:command:)`, and `undoQuickReschedule()`.

- [ ] **Step 1: Write the focused RED tests**

Add pure tests named:

```swift
func testLaterTodayUsesSixPMWhenItIsStillFuture()
func testLaterTodayPreservesAnExistingFutureTimeToday()
func testLaterTodayClampsToFifteenMinutesAfterLateNow()
func testTomorrowAndNextWeekPreserveTimedLocalComponentsAcrossDST()
func testDateOnlyTomorrowAndNextWeekRemainDateOnly()
func testPickUsesExactDateAndTimeFlag()
func testRecurringReminderRequiresTheEditor()
```

Extend `FeatureViewModelTests` with:

```swift
func testTasksPublishOverdueSeparatelyFromToday()
func testQuickRescheduleSendsOneExactUpdateAndPublishesUndo()
func testQuickRescheduleFailureRetainsConfirmedSections()
func testUndoRestoresTheExactPreviousScheduleOnce()
func testStaleProfileTaskCannotBeRescheduledOrUndone()
```

- [ ] **Step 2: Run the focused RED gates**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TaskQuickRescheduleTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests
```

Expected: new types/methods are missing and the overdue assertion fails because current `today` includes all earlier incomplete reminders.

- [ ] **Step 3: Implement the pure schedule projection**

Use `calendar.date(byAdding:)`, `calendar.dateComponents`, and `calendar.date(bySettingHour:)`. For an absent prior due date, Tomorrow/Next Week use the injected now's local time for timed commands and local start-of-day for date-only picks. Reject non-finite dates. Do not mutate provider state in the planner.

- [ ] **Step 4: Integrate exact model updates and one-token undo**

Build an update draft from the current confirmed reminder, then replace its schedule explicitly:

```swift
var draft = ReminderDraft(
    title: item.title,
    notes: item.notes,
    dueDate: item.dueDate,
    dueHasTime: item.dueHasTime,
    priority: item.priority,
    listID: nil,
    alarm: .preserve,
    recurrence: .preserve
)
draft.schedule = .replace(projected)
```

Call `service.updateReminder(id:draft:)` once, then reload. Store the pre-write schedule only after success. A second success replaces the previous undo. Undo issues one exact reverse update and clears its token after success. Scope/access/writability/recurrence checks happen immediately before each write.

- [ ] **Step 5: Run GREEN and commit**

Run both focused commands again; expect 0 failures. Then:

```bash
git add PersonalCalendar/Features/Tasks/TaskQuickReschedule.swift PersonalCalendar/Features/Tasks/TasksViewModel.swift PersonalCalendarTests/Features/TaskQuickRescheduleTests.swift PersonalCalendarTests/Features/FeatureViewModelTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add overdue task triage core"
```

---

### Task 2: Task Triage Interface and Week-Task Completion

**Files:**
- Modify: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Modify: `PersonalCalendar/Features/Calendar/WeekPlannerView.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Create: `PersonalCalendarUITests/TaskTriageFlowUITests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 model APIs and existing `AgendaItemOrigin.reminder`.
- Produces: an overdue section, contextual quick actions, one Undo banner, and a Week Planner task completion callback.

- [ ] **Step 1: Add one deterministic UI RED flow**

The test launches a demo fixture with one overdue nonrecurring task, swipes it, taps Tomorrow, verifies it leaves Overdue, taps Undo, and verifies it returns. It then opens Week mode and completes the visible task marker. Use stable IDs:

```text
tasks-overdue
task-reschedule-tomorrow-<id>
task-reschedule-more-<id>
task-reschedule-undo
week-task-complete-<id>
```

- [ ] **Step 2: Run the focused UI RED gate**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/TaskTriageFlowUITests
```

Expected: the new identifiers/actions are absent.

- [ ] **Step 3: Implement the minimal interface**

Render Overdue before Today. Add trailing swipe actions for Tomorrow and Next Week; add a context menu for Later Today, Tomorrow, Next Week, Pick Date, and Open. If `hasRecurrence`, expose only Open. Present one small date sheet for Pick Date and an inset Undo button while `rescheduleUndo != nil`.

Add `onSetTaskCompleted: (String, Bool) -> Void` to `WeekPlannerView`; regular and accessibility selected-task details invoke it. `CalendarHomeView` routes to its scoped calendar model's existing reminder completion boundary and refreshes afterward. Do not create a separate provider service in the view.

- [ ] **Step 4: Run GREEN and commit**

Run `TaskTriageFlowUITests` again. Then:

```bash
git add PersonalCalendar/Features/Tasks/TasksView.swift PersonalCalendar/Features/Calendar/WeekPlannerView.swift PersonalCalendar/Features/Calendar/CalendarHomeView.swift PersonalCalendarUITests/TaskTriageFlowUITests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add quick task triage actions"
```

---

### Task 3: Versioned App Routes and Root Consumption

**Files:**
- Create: `PersonalCalendar/ProfileShared/AppRoute.swift`
- Create: `PersonalCalendar/Routing/AppRouteController.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Modify: `project.yml`
- Create: `PersonalCalendarTests/Routing/AppRouteTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces the exact target-shared `AppRouteDay` and `AppRoute` cases from the spec, plus:

```swift
struct AppRouteEnvelope: Equatable, Sendable, Identifiable {
    let id: UUID
    let route: AppRoute
}

struct AppRouteCodec: Sendable {
    func url(for route: AppRoute) throws -> URL
    func route(from url: URL) throws -> AppRoute
}

@MainActor @Observable
final class AppRouteController {
    private(set) var pending: AppRouteEnvelope?
    func submit(_ route: AppRoute)
    func consume(id: UUID)
}

enum AppRouteEntryIdentity {
    static func make(displayID: String, occurrenceStart: Date) -> String
}
```

- [ ] **Step 1: Write route RED tests**

Cover round trips for Today, Calendar day/profile/item, task, routine, and Quick Entry Unicode text; unknown scheme/version/kind; malformed UUID/date; absent required item ID; distinct envelopes for repeated equal routes; one-time consumption; and stable opaque entry identity that changes with display ID or occurrence start and never contains the raw display ID.

- [ ] **Step 2: Run focused RED**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/AppRouteTests
```

- [ ] **Step 3: Implement codec/controller and root hook**

Use `URLComponents` with percent-encoded query items. Store `ProfileIdentity` as `everything` or `saved:<uuid>`. Store `AppRouteDay` as `YYYY-MM-DD`. Derive entry identity with one deterministic target-shared hash over the display ID plus occurrence-start milliseconds. Do not serialize EventKit display IDs, mutation IDs, titles, locations, or notes; calendar routes carry only that opaque identity.

Register the `personalcalendar` URL scheme in `project.yml`. Attach `.onOpenURL` at the post-onboarding root. Decode, submit, then consume in `RootTabView`. Resolve a saved profile by exact repository/controller membership before selecting it. Route Today to `.today`; routine through the existing `RoutineDeepLinkSignal`; task/calendar through typed host signals; Quick Entry through the existing creation-profile session with captured text. Missing targets display one neutral alert.

- [ ] **Step 4: Run GREEN and commit**

```bash
git add PersonalCalendar/ProfileShared/AppRoute.swift PersonalCalendar/Routing PersonalCalendar/App/RootTabView.swift PersonalCalendar/App/PersonalCalendarApp.swift PersonalCalendarTests/Routing/AppRouteTests.swift project.yml PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add app-wide deep link routing"
```

---

### Task 4: Actionable Routine, Summary, and Class Notifications

**Files:**
- Modify: `PersonalCalendar/Notifications/NotificationScheduling.swift`
- Modify: `PersonalCalendar/Notifications/SystemNotificationScheduler.swift`
- Modify: `PersonalCalendar/Notifications/NotificationCoordinator.swift`
- Create: `PersonalCalendar/Notifications/AppNotificationActionHandler.swift`
- Create: `PersonalCalendar/Notifications/AppNotificationDelegate.swift`
- Create: `PersonalCalendar/Notifications/ClassAlertCoordinator.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Modify: `PersonalCalendar/Settings/AppSettingsStore.swift`
- Modify: `PersonalCalendar/Features/Settings/NotificationSettingsView.swift`
- Modify: `PersonalCalendarTests/Notifications/NotificationCoordinatorTests.swift`
- Create: `PersonalCalendarTests/Notifications/NotificationActionHandlerTests.swift`
- Create: `PersonalCalendarTests/Notifications/ClassAlertCoordinatorTests.swift`

**Interfaces:**
- Extend request without breaking call sites through defaults:

```swift
struct LocalNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let categoryIdentifier: String?
    let userInfo: [String: String]
}
```

- Add `NotificationCategoryIdentifier` and `NotificationActionIdentifier` constants.
- Extend `NotificationScheduling` with `schedule(_ request: LocalNotificationRequest) async throws` for a snooze without replacing every app-owned request.
- Add per-profile `ClassAlertPreference(enabled: Bool, leadMinutes: Int)` with valid lead values `{5,10,15,20,30}`.
- `ClassAlertCoordinator.requests(profiles:preferences:events:now:)` is pure and returns deterministically sorted requests; `NotificationCoordinator.reschedule` receives those requests and appends them before its one atomic replacement.

- [ ] **Step 1: Add focused RED tests**

Assert routine requests include exact routine/day payload and category; morning summary includes an encoded Today route; Complete is idempotent and writes the current day once; Snooze schedules exactly one replacement at response time + 15 minutes; class alerts default off, filter exact profile entries, honor lead time/horizon/budget, and disappear on deletion/revocation.

- [ ] **Step 2: Run the three focused RED classes**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/NotificationCoordinatorTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/NotificationActionHandlerTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ClassAlertCoordinatorTests
```

- [ ] **Step 3: Implement categories and response bridge**

Register `UNNotificationCategory` values once in the scheduler. Map string `userInfo` into `UNMutableNotificationContent.userInfo`. Expand app-owned identifier recognition to `class|` and `snooze|`. Implement `schedule(_:)` as one `UNUserNotificationCenter.add` call; Snooze must not call `replaceAppRequests` because that would delete unrelated pending alerts.

Use `UIApplicationDelegateAdaptor` for a delegate that installs itself on `UNUserNotificationCenter`, forwards default taps to `AppRouteController`, and forwards actions to the handler. The handler receives injected routines/scheduler/calendar/now and never constructs a second environment.

- [ ] **Step 4: Implement class preferences and settings**

Store preferences keyed by saved profile UUID. UI lists saved profiles, one enable toggle each, and a lead-time picker shown only when enabled. Everything is not configurable because it would duplicate assigned events across saved profiles.

- [ ] **Step 5: Run GREEN, milestone tests, and commit**

After focused GREEN, run:

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/NotificationCoordinatorTests -only-testing:PersonalCalendarTests/AppRouteTests -only-testing:PersonalCalendarTests/FeatureViewModelTests
```

Then commit all Task 4 files with `feat: add actionable daily notifications`.

---

### Task 5: Complete Timetable Snapshots and Adaptive Rails

**Files:**
- Modify: `PersonalCalendar/TimetableShared/TimetableSnapshot.swift`
- Modify: `PersonalCalendar/Timetable/TimetableSnapshotBuilder.swift`
- Modify: `PersonalCalendar/TimetableShared/TimeRailsLayout.swift`
- Modify: `PersonalCalendarWidgets/TimeRailsView.swift`
- Modify: `PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift`
- Modify: `PersonalCalendar/Timetable/TimetableLiveActivityCoordinator.swift`
- Modify: `PersonalCalendarWidgets/TimetableLiveActivity.swift`
- Modify: `PersonalCalendarTests/Timetable/TimetableSnapshotBuilderTests.swift`
- Create: `PersonalCalendarTests/Timetable/TimeRailsLayoutTests.swift`

**Interfaces:**
- Add `routeID: String` to `TimetableEntry` and `omittedEntryCount: Int` to snapshot encoding. Bump the snapshot schema and decode the prior schema only to trigger a fail-closed catalog rebuild; do not reinterpret an old ordinal ID as a new route identity.
- `TimetableSnapshotBuilder` accepts `maximumEncodedBytes` defaulting to 256 KB for catalog snapshots.
- `TimeRailsLayout` exposes derived `startMinute`/`endMinute` with 08:00–18:00 defaults.
- `TimetableActivityAttributes.ContentState` becomes a separate compact today-only value instead of containing `TimetableSnapshotV1`.

- [ ] **Step 1: Add RED cases**

Cover a 20-class week with no omission under the normal budget; 07:30 and 21:00 items; deterministic size-budget omission with a nonzero count; stable opaque route IDs after sort; no raw provider display ID in encoded JSON; and layout inclusion for all early/late blocks.

- [ ] **Step 2: Run focused RED**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableSnapshotBuilderTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimeRailsLayoutTests
```

- [ ] **Step 3: Replace fixed count with encoded-size projection**

Build all privacy-safe entries, deterministically sort, derive `routeID` from display identity plus occurrence start through a stable opaque hash, encode the candidate snapshot with `JSONEncoder`, and remove the furthest chronological entry until it fits. Set `omittedEntryCount` exactly. Do not include raw provider IDs in shared output. For ActivityKit, create a compact today-only content state with current/upcoming entries and enforce a 3.5 KB target before request/update.

- [ ] **Step 4: Render adaptive rails and explicit overflow**

Round earliest start down and latest end up to hours, combine with 08:00–18:00, clamp 0–24. Render `+N more` when omission occurs. Do not drop an entry solely because it lies outside 09:00–18:00.

- [ ] **Step 5: Run GREEN and commit**

Commit with `feat: show complete adaptive timetables`.

---

### Task 6: Timetable Freshness, Widget Links, and Foreground Live Activity Preference

**Files:**
- Modify: `PersonalCalendar/TimetableShared/TimetableSnapshot.swift`
- Modify: `PersonalCalendarWidgets/TimetableWidgetProvider.swift`
- Modify: `PersonalCalendarWidgets/NextClassWidget.swift`
- Modify: `PersonalCalendarWidgets/WeekTimetableWidget.swift`
- Modify: `PersonalCalendar/Features/Settings/TimetableSettingsView.swift`
- Modify: `PersonalCalendar/Timetable/TimetableLiveActivityCoordinator.swift`
- Modify: `PersonalCalendar/App/RootLifecycleController.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/Settings/AppSettingsStore.swift`
- Modify: `PersonalCalendarTests/Timetable/TimetableWidgetSelectionTests.swift`
- Modify: `PersonalCalendarTests/Timetable/TimetableLiveActivityCoordinatorTests.swift`
- Create: `PersonalCalendarTests/Timetable/TimetableFreshnessTests.swift`

**Interfaces:**
- Add pure `TimetableFreshness.generatedAt(_:now:threshold:)` returning `.fresh` or `.stale` with a six-hour default.
- Store `preferredLiveActivityProfile: ProfileIdentity?` and `automaticallyStartsLiveActivityOnForeground: Bool`.

- [ ] **Step 1: Add RED tests**

Assert fresh/stale boundaries, stale timeline refresh date, exact widget route URLs, deleted profiles do not fall back, disabled auto-start performs no request, enabled foreground starts the chosen ready profile, and disabling stops the activity.

- [ ] **Step 2: Run focused RED classes**

Run `TimetableFreshnessTests`, `TimetableWidgetSelectionTests`, and `TimetableLiveActivityCoordinatorTests` only.

- [ ] **Step 3: Implement freshness and widget links**

Show relative last-updated copy on ready states. When stale, append “Open Personal Calendar to refresh.” Use `.widgetURL` with Task 3's `AppRouteCodec`; Next Class routes to the exact entry/profile and Week routes to the profile/week without an item.

- [ ] **Step 4: Implement foreground preference**

Settings selects one catalog profile and toggle. On `sceneBecameActive`, after catalog refresh, reconcile and start only if enabled and today's data is ready. Do not schedule background starts. Copy must retain the runtime/eight-hour limitation.

- [ ] **Step 5: Build extension, run GREEN, and commit**

```bash
xcodebuild build -project PersonalCalendar.xcodeproj -target PersonalCalendarWidgets -destination 'generic/platform=iOS Simulator'
```

Commit with `feat: improve timetable freshness and routing`.

---

### Task 7: Pure Task Time-Block Planning

**Files:**
- Create: `PersonalCalendar/Features/Tasks/TaskTimeBlockPlanner.swift`
- Create: `PersonalCalendarTests/Features/TaskTimeBlockPlannerTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
struct TaskTimeBlockSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let interval: DateInterval
    let conflicts: [String]
}

struct TaskTimeBlockPlanner: Sendable {
    let calendar: Calendar
    let workingStartHour: Int
    let workingEndHour: Int
    func suggestions(
        task: ReminderSnapshot,
        durationMinutes: Int,
        events: [CalendarEventSnapshot],
        now: Date
    ) -> [TaskTimeBlockSuggestion]
    func conflicts(for interval: DateInterval, events: [CalendarEventSnapshot]) -> [String]
}
```

- [ ] **Step 1: Write RED tests**

Cover 30/60/90 validation; up to three nearest gaps before due; fallback later same day; past clamping; all-day ignore; timed conflict detection; back-to-back boundaries; DST day arithmetic; stable title ordering; and no-slot empty result.

- [ ] **Step 2: Run focused RED**

Run only `TaskTimeBlockPlannerTests`.

- [ ] **Step 3: Implement interval subtraction**

Normalize timed event intervals to the candidate local day, merge overlapping busy intervals, subtract from `[max(now, 08:00), 21:00]`, then fit the requested duration. Prefer free intervals ending no later than due, ordered nearest to due; append later candidates ordered earliest first; return at most three.

- [ ] **Step 4: Run GREEN and commit**

Commit with `feat: plan free time for tasks`.

---

### Task 8: Task Time-Block Confirmation and Event Creation

**Files:**
- Create: `PersonalCalendar/Features/Tasks/TaskTimeBlockViewModel.swift`
- Create: `PersonalCalendar/Features/Tasks/TaskTimeBlockView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TaskEditorView.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Create: `PersonalCalendarTests/Features/TaskTimeBlockViewModelTests.swift`
- Create: `PersonalCalendarUITests/TaskTimeBlockFlowUITests.swift`

**Interfaces:**
- `TaskTimeBlockViewModel` receives the exact reminder, captured `CreationProfileContext`, calendar service, scope resolver, planner, Calendar, and now.
- It exposes suggestions/duration/start/end/destination/conflicts, `requiresConflictConfirmation`, and an async single-flight `save()`.

- [ ] **Step 1: Add RED model tests**

Assert exact scoped event fetch IDs; empty profile performs no fetch; saved default seeds; Everything blocks until saved profile chosen; missing/read-only destination blocks; first overlapping save requests confirmation; confirmed save creates one exact `EventDraft`; returned nil provider ID is success; reminder receives zero writes; provider failure retains selections.

- [ ] **Step 2: Run focused RED**

Run only `TaskTimeBlockViewModelTests`.

- [ ] **Step 3: Implement creation**

Create an event with the task title, selected interval, explicit calendar ID, `.clear` alarms/recurrence, and notes containing `personalcalendar-task:v1:<percent-encoded display id>`. Never complete, delete, or update the Reminder. Use the captured profile context for defaults and live revalidation for the final destination.

- [ ] **Step 4: Add minimal sheet and one UI happy path**

Expose Schedule Time from task row context menu and Task editor. Show duration picker, suggestions, explicit calendar picker, date/time controls, conflict warning/second confirmation, Save, Cancel, and error. UI test verifies a task still exists after one created block.

- [ ] **Step 5: Run GREEN, milestone regression, and commit**

Run `TaskTimeBlockViewModelTests`, `TaskQuickRescheduleTests`, `CalendarViewModelTests`, `SaveRouterTests`, and the one UI class. Commit with `feat: schedule tasks into calendar time`.

---

### Task 9: Capture-Anywhere Quick Entry App Intent

**Files:**
- Create: `PersonalCalendar/Intents/QuickEntryProfileEntity.swift`
- Create: `PersonalCalendar/Intents/QuickEntryIntent.swift`
- Create: `PersonalCalendar/Intents/PersonalCalendarShortcuts.swift`
- Create: `PersonalCalendar/ProfileShared/AppRouteHandoffStore.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `project.yml`
- Create: `PersonalCalendarTests/Intents/QuickEntryIntentTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Intent accepts required `text: String` and optional `profile: QuickEntryProfileEntity?`.
- `openAppWhenRun` is true; the intent writes Task 3's Quick Entry route into an atomic app-group handoff store, and app activation consumes it once.

- [ ] **Step 1: Add RED tests**

Assert blank input produces a validation error; valid Unicode text yields the exact route; saved profile identity is preserved; nil profile remains nil and does not become Everything; the intent's injected saver/provider spy receives zero calls.

- [ ] **Step 2: Run focused RED**

Run only `QuickEntryIntentTests`.

- [ ] **Step 3: Implement intent and shortcuts**

Entity query reads the app-group widget profile catalog for display choices and excludes Everything as a creation destination. The intent writes one bounded route envelope to `AppRouteHandoffStore` and returns `.result()`; it never puts private natural-language text into a URL. Shortcut phrases include “Add to Personal Calendar” and “Plan with Personal Calendar”.

- [ ] **Step 4: Consume route in existing confirmation flow**

Root resolves the exact saved profile; if missing, present the profile chooser rather than falling back. Construct the existing Quick Entry session with captured text, call parse, and show confirmation. No SaveRouter call happens until the user taps Save.

- [ ] **Step 5: Run GREEN and commit**

Commit with `feat: add shortcut quick entry capture`.

---

### Task 10: Recent Quick Entry and Remembered Safe Choices

**Files:**
- Create: `PersonalCalendar/QuickEntry/QuickEntryHistory.swift`
- Modify: `PersonalCalendar/Settings/AppSettingsStore.swift`
- Modify: `PersonalCalendar/Features/QuickEntry/QuickEntryViewModel.swift`
- Modify: `PersonalCalendar/Features/QuickEntry/QuickEntrySheet.swift`
- Modify: `PersonalCalendar/Backup/BackupEnvelope.swift`
- Modify: `PersonalCalendar/Backup/BackupService.swift`
- Create: `PersonalCalendarTests/QuickEntry/QuickEntryHistoryTests.swift`
- Modify: `PersonalCalendarTests/QuickEntry/QuickEntryViewModelTests.swift`
- Modify: `PersonalCalendarTests/Backup/BackupServiceTests.swift`

**Interfaces:**
- `QuickEntryHistoryStore` keeps at most ten `QuickEntryHistoryItem(id,text,profileIdentity,lastUsedAt)` values, normalized/deduplicated by trimmed folded text plus profile.
- Preferences are namespaced by profile and kind; invalid destination/category identifiers are ignored during seeding.

- [ ] **Step 1: Add RED tests**

Cover trim/dedupe/MRU/cap, saved-profile isolation, selecting history does not save, successful commit records once, failed save records nothing, safe duration/category/destination reapplication, stale preference ignored, and backup round trip.

- [ ] **Step 2: Run focused RED**

Run `QuickEntryHistoryTests`, `QuickEntryViewModelTests`, and the focused backup class.

- [ ] **Step 3: Implement storage and sheet section**

Use versioned JSON in UserDefaults through AppSettingsStore. Render Recent only on entry stage, newest first, with Clear. Selecting a row copies text/profile context and requires Review. Record history/preferences only after one committed outcome.

- [ ] **Step 4: Run GREEN and commit**

Commit with `feat: remember recent quick entries`.

---

### Task 11: Today Next Up, Maps, and Jump to Date

**Files:**
- Create: `PersonalCalendar/Features/Today/NextUpSnapshot.swift`
- Modify: `PersonalCalendar/Features/Today/TodayViewModel.swift`
- Modify: `PersonalCalendar/Features/Today/TodayView.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarViewModel.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Create: `PersonalCalendarTests/Features/NextUpSnapshotTests.swift`
- Modify: `PersonalCalendarTests/Features/CalendarViewModelTests.swift`
- Create: `PersonalCalendarUITests/DailyQOLFlowUITests.swift`

**Interfaces:**
- `NextUpBuilder.build(agenda:events:reminders:now:) -> NextUpSnapshot?` uses already-confirmed scoped values.
- `CalendarViewModel.jump(to:) async` updates selected day/month and reloads.

- [ ] **Step 1: Add RED tests**

Cover current-event preference, next-event fallback, nearest incomplete deadline, no extra fetch, blank-location Maps absence, routine typed origin, jump across month/DST, and exact selection after load.

- [ ] **Step 2: Run focused RED**

Run `NextUpSnapshotTests` and `CalendarViewModelTests`.

- [ ] **Step 3: Implement model and UI**

Show one compact Next Up card above Today agenda. Open uses existing event/task/routine routes. Maps uses `MKLocalSearch.Request(naturalLanguageQuery:)`/`MKMapItem.openMaps` from a small injected opener seam. Add Calendar toolbar Jump to Date sheet; confirm calls `jump(to:)` and scrolls to the selected ID.

- [ ] **Step 4: Run UI GREEN and commit**

UI flow opens a Today routine, opens an event location action, jumps Calendar to a fixture date, and verifies selection. Commit with `feat: add next up and date jumping`.

---

### Task 12: Safe Duplicate Flows, Backup, Documentation, and Final Gate

**Files:**
- Modify: `PersonalCalendar/Features/EventEditor/EventEditorViewModel.swift`
- Modify: `PersonalCalendar/Features/EventEditor/EventEditorView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TaskEditorViewModel.swift`
- Modify: `PersonalCalendar/Features/Tasks/TaskEditorView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutineEditorView.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Modify: `PersonalCalendar/Features/Today/TodayView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesViewModel.swift`
- Modify: `PersonalCalendar/Backup/BackupEnvelope.swift`
- Modify: `PersonalCalendar/Backup/BackupService.swift`
- Modify: `README.md`
- Modify: `docs/manual-qa/foundation-accessibility.md`
- Create: `PersonalCalendarTests/Features/DuplicateDraftTests.swift`
- Create: `PersonalCalendarUITests/DuplicateFlowUITests.swift`

**Interfaces:**
- Each editor exposes a pure duplicate-draft factory. It copies user-owned fields but excludes external IDs, mutation IDs, completion/history, and archived/paused state.

- [ ] **Step 1: Add RED draft-fidelity tests**

Assert event duration/title/notes/location/alarm/recurrence copy with new confirmed start and no external ID; task title/notes/priority/schedule/alarm/recurrence copy with create destination validation; routine “Copy” title/schedule/reminder/category with no completion history and profile-aware atomic creation.

- [ ] **Step 2: Run focused RED**

Run only `DuplicateDraftTests`.

- [ ] **Step 3: Implement duplicate-to-create editor routes**

Show Duplicate only for editable rows. Tapping constructs a new create model and presents the existing editor; no write occurs until Save. Routine duplicate uses `RoutineProfileMutating.create` with the captured saved profile.

- [ ] **Step 4: Finish backup/docs/manual QA**

Include class alert, Live Activity preference, Quick Entry history/preferences in a versioned backup DTO with defaults for older payloads. Document task triage, class alerts, task scheduling, shortcuts, Next Up, widget freshness, and the honest foreground/runtime limitations. Extend manual QA for notifications, Shortcuts, widgets, Maps, VoiceOver, Accessibility XXXL, and light appearance.

- [ ] **Step 5: Run focused GREEN and final global verification**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project PersonalCalendar.xcodeproj -target PersonalCalendarWidgets -destination 'generic/platform=iOS Simulator'
git diff --check
```

Inspect the complete diff for profile leakage, empty-set provider calls, silent external writes, and stale/deleted-profile fallback. Fix only evidence-backed failures, rerunning their focused class before the final global command.

- [ ] **Step 6: Commit and push**

```bash
git add PersonalCalendar PersonalCalendarWidgets PersonalCalendarTests PersonalCalendarUITests README.md docs project.yml PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: complete daily assist workflows"
git push origin feature/personal-calendar-ios
```

Report the final commit SHA, focused/global test counts, widget build result, and any platform limitation that remains intentional.
