# Week Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a profile-scoped, seven-day Calendar mode that presents events as duration blocks, tasks as due markers, date-only items above the grid, and selected-day routines below it.

**Architecture:** Extend `CalendarViewModel` with a typed display mode and exact visible-day range, then project its already-scoped cache through a pure `WeekPlannerBuilder`. A focused SwiftUI view renders regular and accessibility layouts, while one typed root signal reuses the existing Routines editor for routine selections.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation Calendar/DateInterval, XCTest, XcodeGen, existing EventKit service abstractions.

**Spec:** `docs/superpowers/specs/2026-08-26-week-planner-search-design.md`

## Global Constraints

- Keep Calendar as one root tab; do not add another creation route or root tab.
- Use the existing active `ProfileScope` exactly; an empty source set must never be passed to a provider API that interprets empty as all sources.
- Use injected `Calendar` arithmetic for week boundaries and navigation; do not add fixed-day second counts or `Calendar.current` inside pure builders.
- Events are duration blocks, timed tasks are point markers, date-only tasks/all-day events are top-strip items, and routines are selected-day Later items.
- The visible hour range defaults to 08:00–18:00 and expands through 00:00–24:00 as required; do not omit early or late items.
- Preserve the existing fixed light Harbor & Linen theme, existing editors, host-owned refresh behavior, 44-point targets, VoiceOver semantics, and accessibility Dynamic Type fallback.
- Add no persistence schema, provider protocol, backup, widget, or notification contract changes.
- During development run only the focused test class named by each task; reserve broad regression testing for final integration.

---

### Task 1: Pure Week Projection

**Files:**
- Create: `PersonalCalendar/Features/Calendar/WeekPlannerModels.swift`
- Create: `PersonalCalendar/Features/Calendar/WeekPlannerBuilder.swift`
- Create: `PersonalCalendarTests/Features/WeekPlannerBuilderTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `LocalDay`, `DayAgenda`, `AgendaItem`, `AgendaItemOrigin`, `CategorySnapshot`, `CalendarEventSnapshot`, `ReminderSnapshot`.
- Produces:

```swift
enum WeekPlannerTimedKind: Equatable, Sendable {
    case event
    case taskDue
}

struct WeekPlannerAllDayItem: Identifiable, Equatable, Sendable {
    let id: String
    let day: LocalDay
    let item: AgendaItem
}

struct WeekPlannerTimedItem: Identifiable, Equatable, Sendable {
    let id: String
    let day: LocalDay
    let item: AgendaItem
    let kind: WeekPlannerTimedKind
    let start: Date
    let end: Date?
    let overlapColumn: Int
    let overlapColumnCount: Int
}

struct WeekPlannerSnapshot: Equatable, Sendable {
    let days: [LocalDay]
    let allDayItems: [WeekPlannerAllDayItem]
    let timedItems: [WeekPlannerTimedItem]
    let laterItems: [AgendaItem]
    let startHour: Int
    let endHour: Int

    static let empty = WeekPlannerSnapshot(
        days: [], allDayItems: [], timedItems: [], laterItems: [],
        startHour: 8, endHour: 18
    )
}

struct WeekPlannerBuilder {
    let calendar: Calendar

    func build(
        days: [LocalDay],
        agendas: [LocalDay: DayAgenda],
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot],
        selectedDay: LocalDay
    ) -> WeekPlannerSnapshot
}
```

- Stable overlap ordering is `(start, end ?? start, title, id)`; intersecting event intervals receive zero-based columns and the maximum simultaneous count for that overlap group.

- [ ] **Step 1: Write the failing pure-builder tests**

Create `WeekPlannerBuilderTests` with exact cases:

```swift
@MainActor
final class WeekPlannerBuilderTests: XCTestCase {
    func testBuildPlacesAllDayEventsAndDateOnlyTasksInTopStrip() { }
    func testBuildClipsMultiDayEventToEachIntersectedDay() { }
    func testBuildRepresentsTimedTaskAsPointMarker() { }
    func testBuildShowsOnlySelectedDayAnchoredRoutinesInLaterStrip() { }
    func testBuildExpandsDefaultHoursForEarlyAndLateItemsWithoutDroppingThem() { }
    func testBuildAssignsStableColumnsToOverlappingEvents() { }
}
```

Use an injected Gregorian calendar in `Asia/Singapore`, a Monday-start week, one all-day event, one date-only reminder, a 05:30 event, a 22:30 event, and three pairwise-overlapping events. Assert full value equality for day, origin, start/end, hour bounds, and overlap columns.

- [ ] **Step 2: Regenerate the project and run the focused RED gate**

Run:

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/WeekPlannerBuilderTests
```

Expected: compilation fails because `WeekPlannerBuilder` and its projection types do not exist.

- [ ] **Step 3: Implement the immutable projection and deterministic overlap assignment**

Implement these exact rules:

```swift
let defaultStartHour = 8
let defaultEndHour = 18

// Date-only task top-strip membership must be verified from ReminderSnapshot,
// so an overdue item included in today's priority agenda is not mislabeled as due today.
let reminderByID = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
let eventByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
```

- Include every `agenda.allDay` item.
- Include a priority task only when its matching reminder has `dueHasTime == false`, has a due date, and `LocalDay(dueDate) == day`.
- Turn each scheduled task into a marker with `end == nil`.
- Turn each timed event into one item per intersected day, clipped to `[dayStart, nextDayStart]`.
- Put only `.routine` scheduled or priority items from `selectedDay` into `laterItems`.
- Compute `startHour` from the earliest start rounded down and `endHour` from the latest event end/marker rounded up, then combine with the 08:00–18:00 defaults and clamp to `0...24`.
- Assign overlap columns only among event items on the same day; task markers do not consume a duration column.

- [ ] **Step 4: Run the focused GREEN gate**

Run the same `WeekPlannerBuilderTests` command. Expected: 6 tests pass, 0 failures.

- [ ] **Step 5: Commit the pure projection**

```bash
git add PersonalCalendar/Features/Calendar/WeekPlannerModels.swift PersonalCalendar/Features/Calendar/WeekPlannerBuilder.swift PersonalCalendarTests/Features/WeekPlannerBuilderTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add week planner projection"
```

---

### Task 2: Calendar Mode and Exact Week Loading

**Files:**
- Modify: `PersonalCalendar/Features/Calendar/CalendarViewModel.swift`
- Modify: `PersonalCalendarTests/Features/CalendarViewModelTests.swift`

**Interfaces:**
- Consumes: `WeekPlannerBuilder.build(days:agendas:events:reminders:selectedDay:)` from Task 1.
- Produces:

```swift
enum CalendarDisplayMode: String, CaseIterable, Equatable, Sendable {
    case month
    case week
}

// CalendarViewModel additions
private(set) var displayMode: CalendarDisplayMode
private(set) var weekPlanner: WeekPlannerSnapshot
var visibleDays: [LocalDay] { get }
func setDisplayMode(_ mode: CalendarDisplayMode) async
func movePeriod(by value: Int) async
```

- Existing `moveMonth(by:)`, `select(_:)`, and `showToday()` remain source-compatible for current tests/callers.

- [ ] **Step 1: Add failing CalendarViewModel behavior tests**

Add these methods to the existing focused class:

```swift
func testWeekModeLoadsExactlySevenProfileScopedDays() async { }
func testWeekNavigationAdvancesSevenCalendarDaysAcrossDST() async { }
func testSwitchingBackToMonthLoadsThePaddedMonthRange() async { }
func testWeekProjectionUsesOnlyTheCapturedProfileScope() async { }
func testWeekEmptyExternalScopePerformsNoCalendarOrReminderFetch() async { }
func testTodayInWeekModeSelectsAndLoadsTheInjectedCurrentDay() async { }
```

Use the existing fake services and an injected Gregorian calendar. For the DST case use `America/New_York`, navigate across 8 March 2026, and assert local day equality plus the exact fetched `DateInterval` boundaries rather than a `7 * 86_400` duration.

- [ ] **Step 2: Run the focused RED gate**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/CalendarViewModelTests
```

Expected: new tests fail to compile because display mode and week projection APIs are missing.

- [ ] **Step 3: Implement mode-aware visible days and cache publication**

Use one helper for both fetch intervals and agenda publication:

```swift
private func daysForCurrentMode() -> [LocalDay] {
    let builder = MonthGridBuilder(calendar: systemCalendar)
    switch displayMode {
    case .month:
        return builder.days(containing: displayedMonth).map(\.day)
    case .week:
        return builder.week(
            containing: selectedDay,
            displayedMonth: displayedMonth
        ).map(\.day)
    }
}
```

Set the event interval to the first day start through the day after the last day. Rebuild `visibleAgendas` for exactly `visibleDays`. After the scoped cache is published, build `weekPlanner` from those days, agendas, scoped events, scoped reminders, and selected day.

`setDisplayMode` is a no-op for the current mode; otherwise it updates mode and calls `load()`. `movePeriod(by:)` delegates to `moveMonth(by:)` in month mode and adds seven calendar days to `selectedDay` in week mode, synchronizes `displayedMonth` to that selected local month, and calls `load()`.

On scope failure or strict empty profile publication, assign a snapshot with the current `visibleDays`, empty items, and hours 8–18 rather than retaining a prior-profile week.

- [ ] **Step 4: Run the focused GREEN gate**

Run `CalendarViewModelTests` again. Expected: all methods in that class pass with 0 failures.

- [ ] **Step 5: Commit Calendar model integration**

```bash
git add PersonalCalendar/Features/Calendar/CalendarViewModel.swift PersonalCalendarTests/Features/CalendarViewModelTests.swift
git commit -m "feat: load profile-scoped calendar weeks"
```

---

### Task 3: Week Planner SwiftUI and Item Opening

**Files:**
- Create: `PersonalCalendar/Features/Calendar/WeekPlannerView.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesView.swift`
- Create: `PersonalCalendarTests/Features/RoutineDeepLinkTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CalendarViewModel.displayMode`, `weekPlanner`, `setDisplayMode`, and `movePeriod` from Task 2.
- Produces:

```swift
struct RoutineDeepLinkSignal: Equatable, Sendable {
    let id: UUID
    let routineID: UUID
}

struct WeekPlannerView: View {
    init(
        snapshot: WeekPlannerSnapshot,
        selectedDay: LocalDay,
        now: Date,
        calendar: Calendar,
        onSelectDay: @escaping (LocalDay) -> Void,
        onOpenItem: @escaping (AgendaItemOrigin) -> Void
    )
}
```

- `RootTabView` owns `@State private var routineDeepLink: RoutineDeepLinkSignal?`, passes it to `RoutinesView`, and provides `CalendarHomeView` an `onOpenRoutine` closure that sets the signal then selects `.routines`.
- `RoutinesView` consumes each signal UUID once, reloads its current scoped model if necessary, and sets its existing `editing` row only when the routine remains present.

- [ ] **Step 1: Write the failing deep-link state test**

Create a small pure helper in the test's wished API:

```swift
@MainActor
final class RoutineDeepLinkTests: XCTestCase {
    func testFreshSignalSelectsMatchingScopedRowExactlyOnce() { }
    func testMissingOrReplayedSignalDoesNotOpenAnEditor() { }
}
```

The implementation helper may be internal to `RoutinesView.swift`:

```swift
struct RoutineDeepLinkResolver {
    private(set) var lastSignalID: UUID?
    mutating func resolve(
        _ signal: RoutineDeepLinkSignal?,
        rows: [RoutineRowState]
    ) -> RoutineRowState?
}
```

- [ ] **Step 2: Regenerate and run the focused RED gate**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/RoutineDeepLinkTests
```

Expected: compilation fails because the deep-link signal/resolver do not exist.

- [ ] **Step 3: Implement the regular and accessibility week layouts**

Use native SwiftUI primitives:

```swift
@Environment(\.dynamicTypeSize) private var dynamicTypeSize

@ViewBuilder
var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
        accessibleAgenda
    } else {
        sevenDayTimeline
    }
}
```

Regular layout requirements:

- Top strip lists day abbreviation plus all-day/date-only title.
- Timeline height is `(endHour - startHour) * 52` points inside a vertical `ScrollView`; seven columns use `GeometryReader` and stable calculated frames.
- Event height follows clipped duration with a minimum 28 points; timed tasks use a labeled diamond marker.
- Category color is used when available; otherwise `CalendarTheme.event` or `CalendarTheme.task`.
- Current-time line renders only when today is in the snapshot and current hour is inside its bounds.
- Tapping a block/marker opens a selected-detail row; its Open button invokes `onOpenItem`.
- Selected-day routines appear in a Later section and invoke `onOpenItem`.

Accessibility layout requirements:

- Seven `Section`-like day groups in date order.
- Reuse `AgendaRow` semantics where possible.
- Every event states start/end, every task states due time, and routine copy states its window.
- No item is reachable only by color or gesture.

Integrate a segmented `Picker("Calendar view", selection:)` with Month and Week labels. Replace month-only header navigation calls with `movePeriod(by:)`; preserve the existing Month grid and tray unchanged when `.month` is selected.

- [ ] **Step 4: Implement and verify typed routine routing**

Implement `RoutineDeepLinkResolver` so it records a fresh signal ID before lookup, preventing repeated sheet presentation. Combine `model.active + model.archived` only after the current revision reload. Missing IDs do nothing and never fall back to another row.

Run:

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/RoutineDeepLinkTests
```

Expected: 2 tests pass, 0 failures.

- [ ] **Step 5: Run the Week Planner focused integration gates**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/WeekPlannerBuilderTests -only-testing:PersonalCalendarTests/CalendarViewModelTests -only-testing:PersonalCalendarTests/RoutineDeepLinkTests
```

Expected: all three focused classes pass. Then run `swiftc -frontend -parse` on `WeekPlannerView.swift`, `CalendarHomeView.swift`, `RootTabView.swift`, and `RoutinesView.swift`; expect exit 0.

- [ ] **Step 6: Commit the complete Week Planner**

```bash
git add PersonalCalendar/Features/Calendar/WeekPlannerView.swift PersonalCalendar/Features/Calendar/CalendarHomeView.swift PersonalCalendar/App/RootTabView.swift PersonalCalendar/Features/Routines/RoutinesView.swift PersonalCalendarTests/Features/RoutineDeepLinkTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add interactive calendar week planner"
```

---

### Task 4: Week Planner UI Happy Path

**Files:**
- Create: `PersonalCalendarUITests/WeekPlannerFlowUITests.swift`
- Modify: `PersonalCalendar/App/DemoEnvironment.swift` only if a stable timed task is absent from `-demo-profiles`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes stable IDs from the Week Planner UI:
  - `calendar-mode-week`
  - `week-planner`
  - `week-event-demo-school-event`
  - `week-task-demo-school-task`
  - `week-open-selected-item`
- Produces one deterministic UI regression proving the primary flow.

- [ ] **Step 1: Write the focused UI test**

```swift
final class WeekPlannerFlowUITests: XCTestCase {
    func testSchoolWeekShowsClassAndAssignmentAndOpensTheEvent() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        app.buttons["profile-selector"].tap()
        app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"].tap()
        app.buttons["calendar-mode-week"].tap()

        XCTAssertTrue(app.otherElements["week-planner"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["week-event-demo-school-event"].exists)
        XCTAssertTrue(app.buttons["week-task-demo-school-task"].exists)

        app.buttons["week-event-demo-school-event"].tap()
        app.buttons["week-open-selected-item"].tap()
        XCTAssertTrue(app.navigationBars["Edit Event"].waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 2: Regenerate and run the single UI RED gate**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/WeekPlannerFlowUITests/testSchoolWeekShowsClassAndAssignmentAndOpensTheEvent
```

Expected: fail only on missing/unreachable Week UI IDs or absent deterministic task fixture.

- [ ] **Step 3: Add only the fixture/identifier wiring required by the test**

If the School fixture reminder has a timed due date outside the displayed week, adjust only its deterministic due date in `-demo-profiles` mode to the Friday of the fixture week. Do not change normal demo mode or production data.

Apply the exact accessibility identifiers listed above to the native controls and item buttons.

- [ ] **Step 4: Run the single UI GREEN gate**

Run the same one-method command. Expected: 1 test passes, 0 failures.

- [ ] **Step 5: Commit the Week Planner UI regression**

```bash
git add PersonalCalendarUITests/WeekPlannerFlowUITests.swift PersonalCalendar/App/DemoEnvironment.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "test: cover school week planner flow"
```
