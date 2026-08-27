# Daily Task Rescue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make undated and overdue reminders easy to rescue from Tasks, Today, and Calendar Week without weakening profile, recurrence, provider-authority, or Undo guarantees.

**Architecture:** Extend the existing pure quick-reschedule planner and host-owned view models instead of introducing a second mutation layer. Tasks owns its existing one-item reschedule Undo; Today gains an independent reschedule/Undo state built from its exact scoped reminder cache; Calendar Week resolves an exact live reminder before constructing the already-existing `TaskTimeBlockSession`.

**Tech Stack:** Swift 6, SwiftUI, Observation, EventKit service abstractions, XCTest, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-27-daily-task-rescue-design.md`

## Global Constraints

- Apple Reminders remains authoritative; do not add an app-owned task or “My Day” database.
- Resolve one exact `ProfileScope` per operation and revalidate provider access, list membership, item existence, writability, recurrence, completion state, and expected schedule immediately before every Reminder write.
- Never call a provider fetch with an empty source-ID set when that provider interprets empty as all sources.
- Schedule Time creates one independent Calendar event and never edits or completes its source Reminder.
- Recurring, completed, read-only, missing, and out-of-profile reminders never use quick due-date mutations.
- Profile switches and scope failures clear cross-profile rows, mutation recovery, and reschedule Undo state before any await.
- Every gesture action has a visible 44-by-44-point Button or Menu alternative with an explicit VoiceOver label.
- Use injected `Calendar` and `now` in deterministic logic; do not introduce `Calendar.current` or `Date()` inside model calculations.
- Keep direct task-action presentations mutually exclusive with editor, search, jump-date, Quick Entry, and deep-link presentation.

---

### Task 1: Needs Scheduling and Today Quick-Reschedule Semantics

**Files:**
- Modify: `PersonalCalendar/Features/Tasks/TaskQuickReschedule.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksViewModel.swift`
- Modify: `PersonalCalendarTests/Features/TaskQuickRescheduleTests.swift`
- Modify: `PersonalCalendarTests/Features/TaskQuickRescheduleViewModelTests.swift`
- Modify: `PersonalCalendarTests/Features/FeatureViewModelTests.swift`

**Interfaces:**
- Consumes: existing `ReminderSnapshot`, `ReminderScheduleValue`, `TaskRescheduleUndo`, `TasksViewModel.quickReschedule(id:command:)`, and `TasksViewModel.undoQuickReschedule()`.
- Produces:

```swift
enum TaskQuickReschedule: Equatable, Sendable {
    case today
    case laterToday
    case tomorrow
    case nextWeek
    case pick(Date, hasTime: Bool)
}

@MainActor @Observable
final class TasksViewModel {
    private(set) var needsScheduling: [ReminderSnapshot]
}
```

- `.today` returns the injected calendar's local start of today with `hasTime == false`.
- `needsScheduling` contains only exact-scope, incomplete reminders whose `dueDate == nil`; `upcoming` contains only incomplete reminders whose local due day is later than today.

- [ ] **Step 1: Add RED planner and publication tests**

Add these behavior tests, deriving expected dates with literal calendar components rather than the production planner:

```swift
func testTodayMakesAnUndatedReminderDateOnlyOnTheCurrentLocalDay()
func testUndatedRemindersPublishOnlyInNeedsScheduling()
func testNeedsSchedulingIsClearedWhenTheActiveProfileChanges()
func testTodayCommandPublishesUndoWhosePreviousScheduleIsNil()
func testUndoTodayCommandClearsTheScheduleExactlyOnce()
func testRecurringReadOnlyAndOutOfProfileUndatedRemindersNeverQuickWrite()
```

The undated publication fixture must include one undated incomplete reminder, one future reminder, and one undated completed reminder. Assert exact IDs in all four arrays so an implementation cannot leave the same task in `upcoming`.

Update the existing `FeatureViewModelTests.testTasksGroupsOverdueTodayTomorrowUndatedAndCompletedInInjectedTimezone` contract: the undated fixture is present only in `needsScheduling`, not `upcoming`.

- [ ] **Step 2: Run the focused RED gates**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TaskQuickRescheduleTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TaskQuickRescheduleViewModelTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests/testTasksGroupsOverdueTodayTomorrowUndatedAndCompletedInInjectedTimezone
```

Expected: compile failure for `.today`/`needsScheduling`, followed by behavioral failure if `upcoming` still accepts nil due dates.

- [ ] **Step 3: Implement the minimal planner and model projection**

In `TaskQuickReschedulePlanner.schedule`, add:

```swift
case .today:
    result = .init(date: calendar.startOfDay(for: now), hasTime: false)
```

Initialize and clear `needsScheduling` wherever the other published arrays are initialized or fail closed. In `publish(scope:)`, partition incomplete reminders once:

```swift
needsScheduling = incomplete
    .filter { $0.dueDate == nil }
    .sorted(by: sort)
upcoming = incomplete
    .filter { item in
        item.dueDate.map { LocalDay(date: $0, calendar: calendar) > todayDay } ?? false
    }
    .sorted(by: sort)
```

Keep the existing `.clear` Undo branch for a nil `previousSchedule`; do not add a second provider write or separate undo type.

- [ ] **Step 4: Run GREEN and mutation-check the boundary**

Run both focused commands again. Mentally mutate `.today` to a timed date, put nil due dates back in Upcoming, and omit `needsScheduling` from scope clearing; at least one focused test must fail for each mutation.

- [ ] **Step 5: Commit**

```bash
git add PersonalCalendar/Features/Tasks/TaskQuickReschedule.swift PersonalCalendar/Features/Tasks/TasksViewModel.swift PersonalCalendarTests/Features/TaskQuickRescheduleTests.swift PersonalCalendarTests/Features/TaskQuickRescheduleViewModelTests.swift PersonalCalendarTests/Features/FeatureViewModelTests.swift
git commit -m "feat: add needs-scheduling task state"
```

---

### Task 2: Today Overdue Rescue Model

**Files:**
- Create: `PersonalCalendar/Features/Today/TodayOverdueTask.swift`
- Modify: `PersonalCalendar/Features/Today/TodayViewModel.swift`
- Create: `PersonalCalendarTests/Features/TodayTaskRescueViewModelTests.swift`
- Modify: `PersonalCalendarTests/Features/FeatureViewModelTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TaskQuickReschedulePlanner`, `TaskRescheduleUndo`, the existing `TodayViewModel` reminder cache/scope resolution, and `RemindersServicing.reminder(id:)`/`updateReminder(id:draft:)`.
- Produces:

```swift
struct TodayOverdueTask: Identifiable, Equatable, Sendable {
    let reminder: ReminderSnapshot
    let daysOverdue: Int
    var id: String { reminder.id }

    static func order(_ left: Self, _ right: Self) -> Bool {
        let leftDue = left.reminder.dueDate ?? .distantFuture
        let rightDue = right.reminder.dueDate ?? .distantFuture
        if leftDue != rightDue { return leftDue < rightDue }
        return left.id < right.id
    }
}

@MainActor @Observable
final class TodayViewModel {
    private(set) var overdueTasks: [TodayOverdueTask]
    private(set) var latestRescheduleUndo: TaskRescheduleUndo?
    private(set) var rescheduleError: String?

    func quickRescheduleTask(id: String, command: TaskQuickReschedule) async
    func undoLastTaskReschedule() async
func scopedIncompleteReminder(id: String) -> ReminderSnapshot?
}
```

`scopedIncompleteReminder(id:)` is a synchronous exact-scope lookup for the independent time-block presentation. It re-resolves the current scope, requires granted access and a matching cached identity, reacquires the live provider snapshot, and verifies list membership plus incompletion. It deliberately does not require task writability or nonrecurrence because time blocking never mutates the Reminder. Mutation methods still perform stricter authority checks immediately before writing.

- [ ] **Step 1: Add RED extraction, mutation, and Undo tests**

Add focused tests named:

```swift
func testOverdueTasksExposePositiveCalendarDayAgeAndStableDueOrder()
func testOverdueTasksAreRemovedFromGenericAgendaWithoutRemovingTodaysTasks()
func testDateOnlyAndTimedOverdueDescriptionsRetainTheirProviderSchedule()
func testTodayQuickRescheduleWritesOneExactPreservingDraftAndPublishesUndo()
func testTodayUndoRestoresTheExactPreviousScheduleOnce()
func testCompletionUndoAndRescheduleUndoCanCoexistForDifferentItems()
func testProfileChangeAccessLossProviderDeletionAndExternalScheduleEditClearRescheduleUndoWithoutWriting()
func testRecurringReadOnlyCompletedAndOutOfProfileTasksNeverReschedule()
func testEmptyReminderScopeDoesNotFetchAllLists()
```

For duplicate prevention, give the composer one overdue reminder and one due-today reminder; assert the overdue ID appears only in `overdueTasks` and the due-today ID remains in the generic agenda.

Update `FeatureViewModelTests.testTodayComposesFixedTimezoneItemsInSectionsAndExcludesUndatedReminder`: the overdue fixture moves from `agenda.priority` to `overdueTasks` and is absent from every generic agenda section.

- [ ] **Step 2: Regenerate once and run the RED class**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TodayTaskRescueViewModelTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests/testTodayComposesFixedTimezoneItemsInSectionsAndExcludesUndatedReminder
```

Expected: missing `TodayOverdueTask` and model APIs.

- [ ] **Step 3: Implement overdue extraction and duplicate-free composition**

In `compose(day:calendar:scope:)`, derive selected reminders as today already does, then partition them before calling `AgendaComposer`:

```swift
let overdue = reminderSnapshots.compactMap { reminder -> TodayOverdueTask? in
    guard !reminder.isCompleted, let dueDate = reminder.dueDate else { return nil }
    let dueDay = LocalDay(date: dueDate, calendar: calendar)
    guard dueDay < day else { return nil }
    let distance = calendar.dateComponents(
        [.day],
        from: dueDay.startDate(in: calendar),
        to: day.startDate(in: calendar)
    ).day ?? 0
    guard distance > 0 else { return nil }
    return .init(reminder: reminder, daysOverdue: distance)
}
overdueTasks = overdue.sorted(by: TodayOverdueTask.order)
let agendaReminders = reminderSnapshots.filter { reminder in
    !overdueTasks.contains(where: { $0.id == reminder.id })
}
```

Call the composer with `agendaReminders` and `includeOverdueTasks: false`. Clear `overdueTasks`, reschedule Undo, and reschedule errors on unknown scope, profile identity change, or unavailable Reminders access.

- [ ] **Step 4: Implement exact Today reschedule and Undo authority**

Reuse the preserving draft shape from Tasks:

```swift
var draft = ReminderDraft(
    title: live.title,
    notes: live.notes,
    dueDate: live.dueDate,
    dueHasTime: live.dueHasTime,
    priority: live.priority,
    listID: nil,
    alarm: .preserve,
    recurrence: .preserve
)
draft.schedule = .replace(projected)
```

After one successful write, patch the cache, compose, record the prior schedule plus expected post-write schedule/list, then use the existing scoped reminder refresh. Undo requires the current live schedule to match the recorded expected schedule; restore with `.replace(previous)` or `.clear` and clear only the reschedule token on success. Do not alter `latestTaskUndo`.

- [ ] **Step 5: Run GREEN and commit**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TodayTaskRescueViewModelTests
git add PersonalCalendar/Features/Today/TodayOverdueTask.swift PersonalCalendar/Features/Today/TodayViewModel.swift PersonalCalendarTests/Features/TodayTaskRescueViewModelTests.swift PersonalCalendarTests/Features/FeatureViewModelTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add Today overdue rescue model"
```

---

### Task 3: Accessible Rescue Actions in Tasks and Today

**Files:**
- Modify: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Modify: `PersonalCalendar/Features/Today/TodayView.swift`
- Create: `PersonalCalendar/Features/Today/TodayTaskActionPresentation.swift`
- Create: `PersonalCalendarTests/Features/TodayTaskActionPresentationTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 `needsScheduling`, Task 2 `overdueTasks`/reschedule APIs, and existing `TaskTimeBlockSession.make(task:environment:)`.
- Produces:

```swift
struct TodayTaskPickDate: Identifiable {
    let id = UUID()
    let reminderID: String
}

enum TodayTaskActionPresentation: Identifiable {
    case pickDate(TodayTaskPickDate)
    case timeBlock(TaskTimeBlockSession)

    var id: UUID {
        switch self {
        case let .pickDate(request): request.id
        case let .timeBlock(session): session.id
        }
    }
}
```

The enum is the only direct-task-action sheet in Today. It never overlaps `TodayEditorPresentation`.

- [ ] **Step 1: Add RED presentation-state tests**

Test that Pick Date and Time Block have distinct stable IDs, the selected reminder ID is retained, and replacing one enum case leaves only one presentation. These are pure state tests; do not assert SwiftUI implementation details.

- [ ] **Step 2: Run the RED class**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TodayTaskActionPresentationTests
```

Expected: missing presentation types.

- [ ] **Step 3: Add Needs Scheduling to Tasks**

Render `Needs Scheduling` immediately after Overdue and before Today with identifier `tasks-needs-scheduling`. For every incomplete row, keep the existing explicit ellipsis Menu and add Schedule Time. For writable nonrecurring rows add Today, Tomorrow, and Pick Date; keep existing Later Today/Next Week only where they make sense for already-dated overdue tasks. Add `task-schedule-today-<id>` to the Today action. Preserve the existing swipe alternatives and 44-point menu target.

- [ ] **Step 4: Add Today Overdue UI and direct task actions**

Render `Overdue` before Next Up and the normal agenda, with identifier `today-overdue`. Each row must show:

```swift
daysOverdue == 1 ? "Due yesterday" : "Due \(daysOverdue) days ago"
```

Append the due time only when `dueHasTime == true`. Keep Complete as a separate 44-point Button. Add a 44-point Menu with identifier `today-overdue-actions-<id>` and visible alternatives Later Today, Tomorrow, Pick Date, Schedule Time, and Open.

For generic Today reminder rows, add a 44-point task-actions Menu beside the existing `AgendaRow`; Schedule Time is available for every incomplete task, while quick due-date actions require a writable nonrecurring task. Resolve time-block presentation inputs through `model.scopedIncompleteReminder(id:)`; on nil session show `This task is no longer available in this profile. Refresh and try again.`

Show a separate `today-reschedule-undo` banner without replacing the existing completion Undo banner. Drive one `.sheet(item:)` from `TodayTaskActionPresentation`; include it in `onPresentationChanged` and refuse to present it while an editor is active.

- [ ] **Step 5: Run GREEN, parse the SwiftUI files, and commit**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TodayTaskActionPresentationTests
xcrun swiftc -frontend -parse PersonalCalendar/Features/Tasks/TasksView.swift PersonalCalendar/Features/Today/TodayView.swift PersonalCalendar/Features/Today/TodayTaskActionPresentation.swift
git add PersonalCalendar/Features/Tasks/TasksView.swift PersonalCalendar/Features/Today/TodayView.swift PersonalCalendar/Features/Today/TodayTaskActionPresentation.swift PersonalCalendarTests/Features/TodayTaskActionPresentationTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: expose daily task rescue actions"
```

---

### Task 4: Schedule Time from Calendar Week and End-to-End Rescue Flow

**Files:**
- Modify: `PersonalCalendar/Features/Calendar/CalendarViewModel.swift`
- Modify: `PersonalCalendar/Features/Calendar/WeekPlannerView.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Modify: `PersonalCalendar/App/DemoEnvironment.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendarTests/Features/CalendarViewModelTests.swift`
- Create: `PersonalCalendarUITests/DailyTaskRescueFlowUITests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: existing week planner reminder origins and `TaskTimeBlockSession`.
- Produces:

```swift
@MainActor
func CalendarViewModel.scopedIncompleteReminder(id: String) -> ReminderSnapshot?

struct WeekPlannerView: View {
    let onScheduleTaskTime: (String) -> Void
}
```

`scopedIncompleteReminder(id:)` re-resolves the current profile, requires granted Reminders access and matching cached profile identity, requires the ID in the current exact-scope cache, reacquires `remindersService.reminder(id:)`, and verifies list membership plus incompletion. It returns nil on every authority failure and never falls back to another list/profile. Week displays Schedule only for modifiable reminder rows, but the lookup itself remains reusable for independent time blocking.

- [ ] **Step 1: Add RED model and UI-flow tests**

Extend `CalendarViewModelTests`:

```swift
func testScopedIncompleteReminderReturnsTheExactLiveVisibleIncompleteReminder()
func testScopedIncompleteReminderFailsClosedAfterProfileChangeAccessLossDeletionCompletionOrListMove()
func testScopedIncompleteReminderDoesNotExposeAnythingForAnEmptyScope()
```

Create one deterministic XCUITest launched with `-ui-testing -demo-daily-task-rescue`. It must:

1. Open Tasks and verify `tasks-needs-scheduling` contains `demo-undated-task`.
2. Use `task-schedule-today-demo-undated-task`, verify it leaves Needs Scheduling, then use the existing task reschedule Undo and verify it returns.
3. Open Today, verify `today-overdue` and its overdue-age copy, reschedule `demo-overdue-task`, then use `today-reschedule-undo`.
4. Open Calendar Week, select `week-task-demo-week-task`, tap `week-task-schedule-demo-week-task`, and verify `time-block-form` appears without saving.

- [ ] **Step 2: Run the focused RED gates**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/CalendarViewModelTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/DailyTaskRescueFlowUITests
```

Expected: missing scoped lookup/callback/fixture identifiers.

- [ ] **Step 3: Implement scoped lookup and Week action**

Add the exact lookup to `CalendarViewModel`. In both regular and accessibility Week selected-task detail, show Schedule only for an incomplete modifiable reminder and only when the optional host callback is nonnil; use identifier `week-task-schedule-<id>` and a 44-point bordered Button. Keep Complete and Open independently accessible.

- [ ] **Step 4: Integrate one Calendar time-block sheet safely**

Add `@State private var timeBlockPresentation: TaskTimeBlockSession?`. The Week callback calls `viewModel.scopedIncompleteReminder(id:)`, then `TaskTimeBlockSession.make`. Present `TaskTimeBlockView` with the session's resolver and post-save callback. Include `timeBlockPresentation` in:

- the host `onPresentationChanged` expression;
- `CalendarDeepLinkProcessingKey`;
- deep-link entry guards and post-await presentation checks;
- Search and Jump-to-Date presentation guards.

Do not set `editorPresentation` and `timeBlockPresentation` in the same update. A missing session shows the neutral task-unavailable error and performs no write.

- [ ] **Step 5: Add a launch-isolated demo fixture**

Route a new `-demo-daily-task-rescue` argument through `AppEnvironment.demo`, then under only that flag add deterministic exact-scope reminders:

- `demo-undated-task`: incomplete, writable, nonrecurring, no due date;
- `demo-overdue-task`: incomplete, writable, nonrecurring, due exactly two local calendar days before launch;
- `demo-week-task`: incomplete, writable, due with time inside the displayed current week.

Keep every existing demo mode unchanged when this flag is absent.

- [ ] **Step 6: Run GREEN, accessibility checks, and commit**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/CalendarViewModelTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/DailyTaskRescueFlowUITests
xcrun swiftc -frontend -parse PersonalCalendar/Features/Calendar/CalendarViewModel.swift PersonalCalendar/Features/Calendar/WeekPlannerView.swift PersonalCalendar/Features/Calendar/CalendarHomeView.swift PersonalCalendar/App/DemoEnvironment.swift PersonalCalendar/App/AppEnvironment.swift
git diff --check
git add PersonalCalendar/Features/Calendar/CalendarViewModel.swift PersonalCalendar/Features/Calendar/WeekPlannerView.swift PersonalCalendar/Features/Calendar/CalendarHomeView.swift PersonalCalendar/App/DemoEnvironment.swift PersonalCalendar/App/AppEnvironment.swift PersonalCalendarTests/Features/CalendarViewModelTests.swift PersonalCalendarUITests/DailyTaskRescueFlowUITests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: schedule tasks from Calendar week"
```

At the manual review checkpoint, verify the Today and Week action layouts at Accessibility XXXL, confirm every action can be reached without a swipe/context menu, and confirm canceling the time-block sheet leaves the Reminder unchanged.
