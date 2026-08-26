# Profile-Aware Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fast local search for events, tasks, and routines inside the active Calendar profile, with typed routing into existing editors.

**Architecture:** A pure matcher converts a bounded, already-scoped corpus into stable grouped results. `CalendarSearchViewModel` owns provider loading and cross-profile safety; `CalendarSearchView` uses native SwiftUI search and returns typed origins to `CalendarHomeView`, reusing the Week Planner's routine deep-link signal.

**Tech Stack:** Swift 6, SwiftUI `.searchable`, Observation, Foundation locale/date formatting, XCTest, XcodeGen, existing EventKit and profile abstractions.

**Spec:** `docs/superpowers/specs/2026-08-26-week-planner-search-design.md`

## Global Constraints

- Search uses the currently active `ProfileScope`; `Everything` remains only the union of assigned sources and routines.
- Empty Calendar or Reminder membership must produce zero provider calls, never the services' empty-set-as-all behavior.
- Event search is bounded from exactly one calendar year before injected `now` through two calendar years after it.
- An empty query displays no personal results; matching is case- and diacritic-insensitive and requires every query token to match.
- Search is read-only and must route writes through existing Event, Task, and Routine editors.
- Keep Calendar as one root tab and Search as a Calendar navigation destination; do not add a fifth tab.
- Preserve source-specific partial failure, same-profile confirmed-data retention, synchronous cross-profile clearing, 44-point controls, VoiceOver source labels, and the fixed light theme.
- Do not add persistence, a full-text index, Spotlight, network services, provider protocol changes, or an unbounded EventKit fetch.
- During development run only the focused class/method named by each task; reserve broad regression testing for final integration.

---

### Task 1: Search Result Model and Pure Matcher

**Files:**
- Create: `PersonalCalendar/Features/Search/CalendarSearchModels.swift`
- Create: `PersonalCalendar/Features/Search/CalendarSearchMatcher.swift`
- Create: `PersonalCalendarTests/Features/CalendarSearchMatcherTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CalendarEventSnapshot`, `ReminderSnapshot`, `RoutineSnapshot`, `CategorySnapshot`, `AgendaItemOrigin`, injected `Calendar`, and injected `now`.
- Produces:

```swift
enum CalendarSearchGroup: Int, CaseIterable, Equatable, Sendable {
    case upcoming
    case pastAndCompleted
    case routines
}

enum CalendarSearchSource: String, Equatable, Sendable {
    case event
    case task
    case routine
}

struct CalendarSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let group: CalendarSearchGroup
    let source: CalendarSearchSource
    let title: String
    let subtitle: String
    let date: Date?
    let origin: AgendaItemOrigin
    let searchableText: String
}

struct CalendarSearchSections: Equatable, Sendable {
    let upcoming: [CalendarSearchResult]
    let pastAndCompleted: [CalendarSearchResult]
    let routines: [CalendarSearchResult]

    static let empty = CalendarSearchSections(
        upcoming: [], pastAndCompleted: [], routines: []
    )
}

struct CalendarSearchMatcher {
    let calendar: Calendar
    let locale: Locale

    func makeCorpus(
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot],
        routines: [RoutineSnapshot],
        categories: [CategorySnapshot],
        now: Date
    ) -> [CalendarSearchResult]

    func sections(
        matching query: String,
        corpus: [CalendarSearchResult]
    ) -> CalendarSearchSections
}
```

- [ ] **Step 1: Write failing matcher tests with literal expected results**

Create:

```swift
final class CalendarSearchMatcherTests: XCTestCase {
    func testEmptyQueryReturnsNoPersonalResults() { }
    func testMatchingIsCaseAndDiacriticInsensitiveAndRequiresEveryToken() { }
    func testEventMatchesTitleRoomNotesSourceWeekdayAndLocalizedDate() { }
    func testTaskMatchesTitleNotesListDueDateAndPriority() { }
    func testRoutineMatchesTitleWindowWeekdaysAndCategory() { }
    func testSectionsOrderUpcomingAscendingPastDescendingAndRoutinesAlphabetically() { }
    func testEachVisibleGroupIsCappedAtFiftyAfterMatching() { }
}
```

Use fixed Singapore dates and literal titles including `Café seminar`, `E2-07-14`, `High priority`, and category `Study`. Assert that query `cafe tuesday` matches the accented title/date tokens, while `cafe friday` does not.

- [ ] **Step 2: Regenerate and run the focused RED gate**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/CalendarSearchMatcherTests
```

Expected: compilation fails because matcher/result types do not exist.

- [ ] **Step 3: Implement corpus normalization, grouping, and stable sorting**

Normalize with Foundation folding:

```swift
private func normalized(_ value: String) -> String {
    value.folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: locale
    )
}

let tokens = normalized(query)
    .split(whereSeparator: \.isWhitespace)
    .map(String.init)
```

Use localized weekday, medium date, and short time strings created from the injected calendar/locale. Add source title and category name to `searchableText`, not only to visible copy.

Classification rules:

- Event is upcoming when `end >= now`; otherwise past.
- Incomplete task with no due date is upcoming after dated upcoming items; incomplete dated task uses its due date; completed task is past/completed.
- Nonarchived routine is in Routines whether active or paused; archived routines never enter the corpus.
- Routine origins use `.routine(id: routine.id, day: LocalDay(date: now, calendar: calendar))`; routing consumes the stable UUID and does not treat that day as completion authority.
- Upcoming sort: nonnil date ascending, nil dates last, then source/title/id.
- Past sort: nonnil date descending, nil dates last, then source/title/id.
- Routine sort: localized case-insensitive title, then UUID string.
- Filter by all tokens, sort, then take `prefix(50)` per group.

- [ ] **Step 4: Run the focused GREEN gate**

Run `CalendarSearchMatcherTests` again. Expected: 7 tests pass, 0 failures.

- [ ] **Step 5: Commit pure search behavior**

```bash
git add PersonalCalendar/Features/Search/CalendarSearchModels.swift PersonalCalendar/Features/Search/CalendarSearchMatcher.swift PersonalCalendarTests/Features/CalendarSearchMatcherTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add profile search matching"
```

---

### Task 2: Scoped Search Loading and Failure Safety

**Files:**
- Create: `PersonalCalendar/Features/Search/CalendarSearchViewModel.swift`
- Create: `PersonalCalendarTests/Features/CalendarSearchViewModelTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CalendarSearchMatcher`, `ProfileScope`, `CalendarServicing`, `RemindersServicing`, `RoutineRepository`, and `CategoryRepository`.
- Produces:

```swift
struct CalendarSearchNotice: Identifiable, Equatable, Sendable {
    enum Source: Hashable, Sendable {
        case calendar
        case reminders
        case routines
    }

    let source: Source
    let message: String
    var id: Source { source }
}

@MainActor
@Observable
final class CalendarSearchViewModel {
    var query: String
    private(set) var sections: CalendarSearchSections
    private(set) var isLoading: Bool
    private(set) var notices: [CalendarSearchNotice]
    private(set) var isProfileEmpty: Bool

    init(
        calendarService: any CalendarServicing,
        remindersService: any RemindersServicing,
        routines: any RoutineRepository,
        categories: any CategoryRepository,
        currentScope: @escaping @MainActor () throws -> ProfileScope,
        calendar: Calendar,
        locale: Locale,
        now: @escaping () -> Date,
        debounce: Duration = .milliseconds(250)
    )

    func load() async
    func retry() async
}
```

- [ ] **Step 1: Write failing scoped-loading tests**

Create these exact cases:

```swift
@MainActor
final class CalendarSearchViewModelTests: XCTestCase {
    func testLoadUsesExactScopeAndCalendarYearBoundsThenFiltersProviderOverReturn() async { }
    func testEmptyExternalAndRoutineScopePerformsZeroProviderAndRepositoryFetches() async { }
    func testPartialCalendarFailureStillPublishesTaskAndRoutineMatches() async { }
    func testSameProfileFailureRetainsConfirmedStillScopedCorpus() async { }
    func testProfileChangeClearsOldResultsBeforeSuspendedNewLoadCompletes() async { }
    func testOlderGenerationCannotPublishAfterNewerProfileLoad() async { }
    func testDebouncedQueryPublishesOnlyLatestMatcherResult() async { }
}
```

Use test-local synchronization-backed provider doubles for suspended event/reminder loads. Assert exact source IDs, exact interval dates, repository list call count, notices, and result titles.

- [ ] **Step 2: Regenerate and run the focused RED gate**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/CalendarSearchViewModelTests
```

Expected: compilation fails because `CalendarSearchViewModel` and notice types do not exist.

- [ ] **Step 3: Implement one captured scope per load with source-isolated failures**

At load start:

```swift
loadGeneration += 1
let generation = loadGeneration
let scope = try currentScope()

if cachedScopeIdentity != scope.identity {
    corpus = []
    sections = .empty
    notices = []
}
cachedScopeIdentity = scope.identity
```

Construct the event interval with injected calendar arithmetic:

```swift
let reference = now()
let start = calendar.date(byAdding: .year, value: -1, to: reference)!
let end = calendar.date(byAdding: .year, value: 2, to: reference)!
let interval = DateInterval(start: start, end: end)
```

Fetch rules:

- Calendar access not granted: empty event contribution plus a Calendar notice.
- Granted + empty `calendarIDs`: empty contribution, zero event fetches.
- Reminders access not granted: empty reminder contribution plus a Reminders notice.
- Granted + empty `reminderListIDs`: empty contribution, zero reminder fetches.
- Empty `routineIDs`: empty contribution, zero `routines.list` calls.
- Nonempty routine scope: list once, filter UUIDs, then exclude archived values in the matcher.
- Load categories once; category failure leaves category matching absent and records no user-facing source error because core results remain valid.
- Filter all provider over-return by the captured exact sets.
- Publish only when `generation == loadGeneration`.
- On same-profile source failure retain only the prior contribution intersected with the new exact membership; on identity change retain nothing.

Query changes cancel the prior debounce task. After `Task.sleep(for: debounce)`, publish matcher sections only when the task is not cancelled and the load generation still matches.

- [ ] **Step 4: Run the focused GREEN gate**

Run `CalendarSearchViewModelTests` again. Expected: 7 tests pass, 0 failures.

- [ ] **Step 5: Commit scoped loading**

```bash
git add PersonalCalendar/Features/Search/CalendarSearchViewModel.swift PersonalCalendarTests/Features/CalendarSearchViewModelTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: load profile-scoped search corpus"
```

---

### Task 3: Native Search UI and Existing-Editor Routing

**Files:**
- Create: `PersonalCalendar/Features/Search/CalendarSearchView.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Create: `PersonalCalendarUITests/CalendarSearchFlowUITests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CalendarSearchViewModel` from Task 2 and `RoutineDeepLinkSignal` plus `CalendarHomeView.onOpenRoutine` from the Week Planner plan.
- Produces:

```swift
struct CalendarSearchView: View {
    init(
        environment: AppEnvironment,
        onSelect: @escaping @MainActor (AgendaItemOrigin) -> Void
    )
}
```

- Stable accessibility IDs:
  - `calendar-search-open`
  - `calendar-search-screen`
  - `calendar-search-field`
  - `calendar-search-result-<result.id>`
  - `calendar-search-retry`

- [ ] **Step 1: Write the single deterministic UI happy path**

```swift
final class CalendarSearchFlowUITests: XCTestCase {
    func testSchoolSearchFindsEventTaskAndRoutineThenOpensEventEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-profiles"]
        app.launch()

        app.buttons["profile-selector"].tap()
        app.buttons["profile-option-C0A10000-0000-4000-8000-000000000002"].tap()
        app.buttons["calendar-search-open"].tap()

        let field = app.searchFields["calendar-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("INF")

        XCTAssertTrue(app.buttons["calendar-search-result-event|demo-school-event"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["calendar-search-result-task|demo-school-task"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar-search-result-routine|")).firstMatch.exists)

        app.buttons["calendar-search-result-event|demo-school-event"].tap()
        XCTAssertTrue(app.navigationBars["Edit Event"].waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 2: Regenerate and run the one-method RED gate**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/CalendarSearchFlowUITests/testSchoolSearchFindsEventTaskAndRoutineThenOpensEventEditor
```

Expected: fail because Calendar has no search destination/identifiers.

- [ ] **Step 3: Implement the native search screen**

Construct the model once from `AppEnvironment` and the long-lived profile selection:

```swift
let selection = environment.profileSelection
let scopes = environment.profileScopes

CalendarSearchViewModel(
    calendarService: environment.calendar,
    remindersService: environment.reminders,
    routines: environment.routines,
    categories: environment.categories,
    currentScope: { try scopes.resolve(selection.activeIdentity) },
    calendar: .current,
    locale: .current,
    now: { .now }
)
```

UI requirements:

- Use `.searchable(text: $model.query, prompt: "Events, tasks, routines")` and expose the search field identifier with SwiftUI introspection-free native modifiers available to the project; if `.searchable` cannot carry the identifier reliably, place a labeled native `TextField` with `.textInputAutocapitalization(.never)` and the exact ID.
- Show `ProfileSelectorToolbar` as the trailing toolbar item.
- Reload with `.task(id: environment.profileSelection.scopeRevision)`.
- Empty query: `ContentUnavailableView("Search your profile", systemImage: "magnifyingglass", description: Text("Try a course code, room, title, or date."))`.
- Nonempty query with no results: state that no matching items were found in the active profile and show the bounded event dates produced from injected `now`; do not imply older events were searched.
- Render Upcoming, Past & completed, and Routines only when nonempty.
- Each row visibly states Event, Task, or Routine in addition to its icon/color.
- Show source notices above results with one Retry button invoking `model.retry()`.
- Keep rows 44 points tall and combine title, source, subtitle, and date into VoiceOver order.

- [ ] **Step 4: Integrate Calendar navigation and typed result opening**

Add a toolbar search button to `CalendarHomeView` and a navigation destination for `CalendarSearchView`.

On result selection:

```swift
switch origin {
case .event, .reminder:
    showingSearch = false
    Task { @MainActor in
        await Task.yield()
        openAgendaItem(origin)
    }
case let .routine(id, _):
    showingSearch = false
    onOpenRoutine(id)
case .synthetic:
    break
}
```

Do not create alternate editor models or mutation calls. If an event/reminder no longer resolves, keep the existing editor's unavailable-item behavior.

- [ ] **Step 5: Run focused Search gates**

Run:

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/CalendarSearchMatcherTests -only-testing:PersonalCalendarTests/CalendarSearchViewModelTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/CalendarSearchFlowUITests/testSchoolSearchFindsEventTaskAndRoutineThenOpensEventEditor
```

Expected: all focused unit tests pass and the single UI method passes.

- [ ] **Step 6: Commit Search UI integration**

```bash
git add PersonalCalendar/Features/Search/CalendarSearchView.swift PersonalCalendar/Features/Calendar/CalendarHomeView.swift PersonalCalendarUITests/CalendarSearchFlowUITests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add profile-aware calendar search"
```

---

### Task 4: Combined Feature Verification and Documentation

**Files:**
- Modify: `README.md`
- Test: focused classes and two isolated UI methods from both plans.

**Interfaces:**
- Documents Month/Week usage, Calendar search, active-profile scope, bounded event history, and editor routing.
- Does not claim background indexing, ICS import, or unassigned-source search.

- [ ] **Step 1: Add concise user documentation**

Add this content under the existing profile usage section:

```markdown
### Week Planner and search

- In Calendar, choose **Week** to see events as timed blocks, tasks as due markers, and routines for the selected day.
- Week Planner follows the active profile, so School remains isolated from unassigned calendars such as Birthdays.
- Use the Calendar search button to find events, tasks, rooms, notes, dates, and routines in the active profile.
- Event search covers one year in the past through two years in the future. Selecting a result opens the existing editor.
```

- [ ] **Step 2: Run the combined targeted unit gate**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/WeekPlannerBuilderTests -only-testing:PersonalCalendarTests/CalendarViewModelTests -only-testing:PersonalCalendarTests/RoutineDeepLinkTests -only-testing:PersonalCalendarTests/CalendarSearchMatcherTests -only-testing:PersonalCalendarTests/CalendarSearchViewModelTests
```

Expected: all selected unit tests pass with 0 failures.

- [ ] **Step 3: Run the two isolated UI methods**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/WeekPlannerFlowUITests/testSchoolWeekShowsClassAndAssignmentAndOpensTheEvent -only-testing:PersonalCalendarUITests/CalendarSearchFlowUITests/testSchoolSearchFindsEventTaskAndRoutineThenOpensEventEditor
```

Expected: 2 UI tests pass, 0 failures.

- [ ] **Step 4: Perform static hygiene checks**

```bash
git diff --check
rg -n 'Calendar\.current|Date\(\)' PersonalCalendar/Features/Search PersonalCalendar/Features/Calendar/WeekPlannerBuilder.swift PersonalCalendar/Features/Calendar/WeekPlannerModels.swift
```

Expected: no whitespace errors; production dependency construction may use `.current`/`.now` only at SwiftUI composition, while pure builder and view-model behavior receive injected values.

- [ ] **Step 5: Commit documentation and verification state**

```bash
git add README.md
git commit -m "docs: explain week planner and profile search"
```
