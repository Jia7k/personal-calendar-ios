# School Timetable Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full-width school-day Time Rails Live Activity, a permanent Next Class Lock Screen widget, and a medium Home Screen weekly timetable driven by the app's selected Apple Calendar events.

**Architecture:** The app is the sole EventKit reader. It maps the selected Monday-to-Friday occurrences into a bounded, privacy-minimized Codable snapshot stored atomically in an App Group; WidgetKit reads that snapshot, while ActivityKit receives the same bounded content through an injected driver. The MVP starts and reconciles Live Activities only while the app has runtime and uses permanent widgets as the serverless fallback.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, ActivityKit, EventKit, App Groups, XcodeGen, XCTest, iOS 17 deployment target.

**Spec:** `docs/superpowers/specs/2026-08-25-school-timetable-widgets-design.md`

## Global Constraints

- Keep `IPHONEOS_DEPLOYMENT_TARGET` at iOS 17.0.
- Do not add a server, APNs, third-party package, shared SwiftData store, or timetable database.
- Do not query EventKit from the widget extension.
- Use the existing visible-calendar selection from `AppSettingsStore`.
- Exclude all-day events, Saturday/Sunday, notes, URLs, alarms, recurrence metadata, mutation IDs, and calendar IDs from shared data.
- Keep ActivityKit attributes plus content state under 4 KB through deterministic entry and string caps.
- Keep the Lock Screen Live Activity at or below 160 points and render it as one unsplit card.
- Preserve the app's light-only appearance; Lock Screen rendering follows the system surface.
- Regenerate `PersonalCalendar.xcodeproj` from `project.yml`; never hand-edit `project.pbxproj`.
- Run only each task's named test file or method. Do not run the global test suite.
- Commit after every task using the exact scoped file set listed in that task.

## File Map

### Shared app/extension sources

- Create `PersonalCalendar/TimetableShared/TimetableSnapshot.swift`: Codable DTOs, current/next status, compact course labels.
- Create `PersonalCalendar/TimetableShared/TimetableSnapshotStore.swift`: App Group JSON storage and read/write protocols.
- Create `PersonalCalendar/TimetableShared/TimetableTimelineBuilder.swift`: deterministic widget refresh dates.
- Create `PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift`: ActivityKit attributes and content state.
- Create `PersonalCalendar/TimetableShared/TimeRailsLayout.swift`: normalized block geometry used by widget and Live Activity views.

### App-only sources

- Create `PersonalCalendar/Timetable/TimetableSnapshotBuilder.swift`: maps `CalendarEventSnapshot` into shared DTOs.
- Create `PersonalCalendar/Timetable/TimetableSnapshotCoordinator.swift`: fetches the selected week, persists it, and reloads WidgetKit.
- Create `PersonalCalendar/Timetable/TimetableActivityDriver.swift`: ActivityKit abstraction plus system/no-op drivers.
- Create `PersonalCalendar/Timetable/TimetableLiveActivityCoordinator.swift`: observable start/update/recover/stop state machine.
- Create `PersonalCalendar/Features/Settings/TimetableSettingsView.swift`: refresh, Start, and Stop UI.
- Modify `PersonalCalendar/App/AppEnvironment.swift`: own the timetable coordinators.
- Modify `PersonalCalendar/App/RootTabView.swift`: perform the first snapshot refresh.
- Modify `PersonalCalendar/Refresh/AppRefreshCoordinator.swift`: refresh timetable data in the existing ordered pipeline.
- Modify `PersonalCalendar/Features/Settings/SettingsView.swift`: expose timetable settings and refresh after source changes.

### Widget-extension sources

- Create `PersonalCalendarWidgets/Info.plist`: WidgetKit extension point.
- Create `PersonalCalendarWidgets/PersonalCalendarWidgets.entitlements`: App Group capability.
- Create `PersonalCalendarWidgets/PersonalCalendarWidgetsBundle.swift`: widget bundle.
- Create `PersonalCalendarWidgets/TimetableWidgetProvider.swift`: App Group timeline provider.
- Create `PersonalCalendarWidgets/NextClassWidget.swift`: accessory rectangular widget.
- Create `PersonalCalendarWidgets/WeekTimetableWidget.swift`: system medium widget.
- Create `PersonalCalendarWidgets/TimeRailsView.swift`: shared SwiftUI rail renderer.
- Create `PersonalCalendarWidgets/TimetableLiveActivity.swift`: Lock Screen and Dynamic Island UI.
- Create `PersonalCalendar/Resources/PersonalCalendar.entitlements`: app App Group capability.
- Modify `project.yml`: add capabilities, Info keys, target, embedding, and scheme membership.

### Tests and documentation

- Create `PersonalCalendarTests/Timetable/TimetableSnapshotBuilderTests.swift`.
- Create `PersonalCalendarTests/Timetable/TimetableSnapshotCoordinatorTests.swift`.
- Create `PersonalCalendarTests/Timetable/TimetableTimelineBuilderTests.swift`.
- Create `PersonalCalendarTests/Timetable/TimetableLiveActivityCoordinatorTests.swift`.
- Create `PersonalCalendarTests/Timetable/TimeRailsLayoutTests.swift`.
- Modify `PersonalCalendarTests/Refresh/AppRefreshCoordinatorTests.swift`.
- Modify `README.md` with installation and feature behavior.

---

### Task 1: Shared Timetable Domain and EventKit Mapping

**Files:**
- Create: `PersonalCalendar/TimetableShared/TimetableSnapshot.swift`
- Create: `PersonalCalendar/Timetable/TimetableSnapshotBuilder.swift`
- Create: `PersonalCalendarTests/Timetable/TimetableSnapshotBuilderTests.swift`

**Interfaces:**
- Consumes: `CalendarEventSnapshot`, `AccessState`, injected `Calendar`, and an injected `now` date.
- Produces: `TimetableAvailability`, `TimetableEntry`, `TimetableSnapshotV1`, `TimetableMoment`, `TimetableSnapshotBuilder.makeSnapshot(access:events:now:)`.

- [ ] **Step 1: Write the failing snapshot mapping tests**

Create deterministic Singapore-calendar fixtures containing the supplied nine timed classes plus one all-day event and one Saturday event. Bind exact fields and filtering:

```swift
import XCTest
@testable import PersonalCalendar

final class TimetableSnapshotBuilderTests: XCTestCase {
    func testBuildsMondayToFridaySnapshotFromTimedVisibleEvents() throws {
        let fixture = TimetableTestFixture()
        let subject = TimetableSnapshotBuilder(calendar: fixture.calendar)

        let snapshot = subject.makeSnapshot(
            access: .granted,
            events: fixture.weekEvents + [fixture.allDayEvent, fixture.saturdayEvent],
            now: fixture.tuesday0941
        )

        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.availability, .ready)
        XCTAssertEqual(snapshot.weekStart, fixture.mondayStart)
        XCTAssertEqual(snapshot.timeZoneIdentifier, "Asia/Singapore")
        XCTAssertEqual(snapshot.entries.count, 9)
        XCTAssertEqual(snapshot.entries.map(\.shortTitle), ["I01", "I06", "B05", "I03", "B05", "I03", "I06", "I01", "U22"])
        XCTAssertFalse(snapshot.entries.contains { Calendar(identifier: .gregorian).component(.weekday, from: $0.start) == 7 })
    }

    func testMomentDistinguishesBeforeCurrentGapAndAfterSchool() throws {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.monday0840)

        XCTAssertEqual(snapshot.moment(at: fixture.monday0840, calendar: fixture.calendar), .next(snapshot.entries[0]))
        XCTAssertEqual(snapshot.moment(at: fixture.tuesday0941, calendar: fixture.calendar).entry?.shortTitle, "I03")
        XCTAssertEqual(snapshot.moment(at: fixture.monday1330, calendar: fixture.calendar).entry?.shortTitle, "B05")
        XCTAssertEqual(snapshot.moment(at: fixture.monday1830, calendar: fixture.calendar), .none)
    }

    func testPermissionLossContainsNoEventData() {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .denied, events: fixture.weekEvents, now: fixture.tuesday0941)
        XCTAssertEqual(snapshot.availability, .calendarAccessRequired)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }
}
```

The test fixture must build exact `CalendarEventSnapshot` values and expected dates rather than calling production mapping helpers.

Keep `TimetableTestFixture` internal so later focused test files can reuse it. Its `weekEvents` array is exactly:

```swift
struct TimetableTestFixture {
    let timeZone = TimeZone(identifier: "Asia/Singapore")!
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        value.locale = Locale(identifier: "en_SG")
        return value
    }

    func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: day == 31 ? 8 : 9,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    func event(_ id: String, _ title: String, day: Int, start: Int, end: Int, location: String) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: id,
            title: title,
            start: date(day: day, hour: start),
            end: date(day: day, hour: end),
            isAllDay: false,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: false,
            location: location
        )
    }

    var mondayStart: Date { date(day: 31, hour: 0) }
    var monday0840: Date { date(day: 31, hour: 8, minute: 40) }
    var monday0900: Date { date(day: 31, hour: 9) }
    var monday1100: Date { date(day: 31, hour: 11) }
    var monday1330: Date { date(day: 31, hour: 13, minute: 30) }
    var monday1830: Date { date(day: 31, hour: 18, minute: 30) }
    var tuesdayStart: Date { date(day: 1, hour: 0) }
    var tuesday0941: Date { date(day: 1, hour: 9, minute: 41) }

    var allDayEvent: CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: "holiday",
            title: "Holiday",
            start: mondayStart,
            end: tuesdayStart,
            isAllDay: true,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: false,
            hasRecurrence: false
        )
    }

    var saturdayEvent: CalendarEventSnapshot {
        event("sat", "INF 2099 Tutorial", day: 5, start: 9, end: 10, location: "Online")
    }

    var weekEvents: [CalendarEventSnapshot] {
        [
            event("i01-mon", "INF 2001 Lecture", day: 31, start: 9, end: 11, location: "Online"),
            event("i06-mon", "INF 2006 Lecture", day: 31, start: 11, end: 13, location: "Online"),
            event("b05-mon", "BAC 2005 Seminar", day: 31, start: 16, end: 18, location: "E2-02-07-SR204"),
            event("i03-tue", "INF 2003 Lecture", day: 1, start: 9, end: 11, location: "Online"),
            event("b05-wed", "BAC 2005 Laboratory", day: 2, start: 9, end: 11, location: "E2-08-01"),
            event("i03-wed", "INF 2003 Laboratory", day: 2, start: 11, end: 13, location: "E2-07-14"),
            event("i06-thu", "INF 2006 Laboratory", day: 3, start: 9, end: 11, location: "E2-03-05-SR223"),
            event("i01-thu", "INF 2001 Laboratory", day: 3, start: 11, end: 13, location: "E6-03-05-SR335"),
            event("u22-fri", "UDE 2222 Seminar", day: 4, start: 9, end: 12, location: "E6-03-05-SR335")
        ]
    }
}
```

- [ ] **Step 2: Run the targeted test file to verify RED**

Run:

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PersonalCalendarTests/TimetableSnapshotBuilderTests
```

Expected: compiler failure for missing `TimetableSnapshotBuilder` and shared DTOs.

- [ ] **Step 3: Implement the shared DTO and presentation state**

Use these exact public-in-module shapes:

```swift
enum TimetableAvailability: String, Codable, Hashable, Sendable {
    case ready
    case calendarAccessRequired
}

struct TimetableEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let shortTitle: String
    let start: Date
    let end: Date
    let location: String?
}

enum TimetableMoment: Hashable, Sendable {
    case none
    case next(TimetableEntry)
    case current(TimetableEntry)
    case gap(next: TimetableEntry)

    var entry: TimetableEntry? {
        switch self {
        case .none: nil
        case let .next(entry), let .current(entry), let .gap(entry): entry
        }
    }
}

struct TimetableSnapshotV1: Codable, Hashable, Sendable {
    static let currentVersion = 1
    let version: Int
    let availability: TimetableAvailability
    let generatedAt: Date
    let weekStart: Date
    let timeZoneIdentifier: String
    let entries: [TimetableEntry]

    func moment(at now: Date, calendar: Calendar) -> TimetableMoment
}
```

`moment(at:)` must look only at entries on the injected local day, prefer a matching `start <= now < end`, return `.next` before the first event, `.gap` between events, and `.none` after the final event.

- [ ] **Step 4: Implement deterministic EventKit mapping**

Implement:

```swift
struct TimetableSnapshotBuilder {
    let calendar: Calendar

    func makeSnapshot(
        access: AccessState,
        events: [CalendarEventSnapshot],
        now: Date
    ) -> TimetableSnapshotV1

    func weekInterval(containing now: Date) -> DateInterval
}
```

Use Monday-offset calculation `(weekday + 5) % 7`, a Monday-to-next-Monday interval, weekdays `2...6`, non-all-day finite `start < end` entries, and deterministic `start/end/id` ordering. Bound full titles to 48 characters and locations to 64 characters. Cap the snapshot at 12 entries so the approved nine-class week and ActivityKit payload remain comfortably below 4 KB.

Use a regular expression equivalent to `^([A-Za-z])[A-Za-z]{2}\s*([0-9]{2})([0-9]{2})\b` for `I01`, `B05`, and `U22`; otherwise use the first four alphanumeric characters of the trimmed title.

- [ ] **Step 5: Run the targeted test file to verify GREEN**

Run the Task 1 command again. Expected: `3 tests, 0 failures`.

- [ ] **Step 6: Commit Task 1**

```bash
git add PersonalCalendar/TimetableShared/TimetableSnapshot.swift \
  PersonalCalendar/Timetable/TimetableSnapshotBuilder.swift \
  PersonalCalendarTests/Timetable/TimetableSnapshotBuilderTests.swift
git commit -m "feat: add shared timetable snapshot model"
```

### Task 2: App Group Snapshot Storage and Refresh Coordinator

**Files:**
- Create: `PersonalCalendar/TimetableShared/TimetableSnapshotStore.swift`
- Create: `PersonalCalendar/Timetable/TimetableSnapshotCoordinator.swift`
- Create: `PersonalCalendarTests/Timetable/TimetableSnapshotCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 1 DTOs and builder, `CalendarServicing`, `AppSettingsStore`.
- Produces: `TimetableSnapshotReading`, `TimetableSnapshotWriting`, `TimetableWidgetReloading`, `TimetableSnapshotStore`, and `TimetableSnapshotCoordinator.refresh(now:)`.

- [ ] **Step 1: Write failing storage and coordinator tests**

Bind one atomic round trip and one coordinator happy path:

```swift
@MainActor
final class TimetableSnapshotCoordinatorTests: XCTestCase {
    func testRefreshFetchesSelectedWeekWritesSnapshotAndReloadsWidgetsOnce() throws {
        let fixture = TimetableTestFixture()
        let calendarService = RecordingTimetableCalendarService(events: fixture.weekEvents)
        let writer = RecordingTimetableWriter()
        let reloader = RecordingTimetableReloader()
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.replaceSelectedCalendarIDs(["school"], availableIDs: ["school", "personal"])
        let subject = TimetableSnapshotCoordinator(
            calendar: calendarService,
            settings: settings,
            builder: .init(calendar: fixture.calendar),
            writer: writer,
            reloader: reloader
        )

        let snapshot = try subject.refresh(now: fixture.tuesday0941)

        XCTAssertEqual(calendarService.requestedCalendarIDs, ["school"])
        XCTAssertEqual(writer.values, [snapshot])
        XCTAssertEqual(reloader.reloadCount, 1)
        XCTAssertEqual(snapshot.entries.count, 9)
    }

    func testStoreRoundTripsVersionedJSONAtomically() throws {
        let fixture = TimetableTestFixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TimetableSnapshotStore(fileURL: directory.appendingPathComponent("timetable-v1.json"))
        let expected = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)
        try store.write(expected)
        XCTAssertEqual(try store.read(), expected)
    }
}
```

Also assert denied access writes `.calendarAccessRequired`, fetches zero events, and reloads once.

- [ ] **Step 2: Run the targeted coordinator test file to verify RED**

Use `-only-testing:PersonalCalendarTests/TimetableSnapshotCoordinatorTests`; expect missing store/coordinator symbols.

- [ ] **Step 3: Implement the App Group store**

Define:

```swift
protocol TimetableSnapshotReading {
    func read() throws -> TimetableSnapshotV1
}

protocol TimetableSnapshotWriting {
    func write(_ value: TimetableSnapshotV1) throws
}

struct TimetableSnapshotStore: TimetableSnapshotReading, TimetableSnapshotWriting, Sendable {
    static let appGroupIdentifier = "group.local.personalcalendar.shared"
    static let filename = "timetable-v1.json"
    let fileURL: URL

    static func appGroup(fileManager: FileManager = .default) throws -> Self
    func read() throws -> TimetableSnapshotV1
    func write(_ value: TimetableSnapshotV1) throws
}
```

`appGroup()` must throw a typed `TimetableSnapshotStoreError.containerUnavailable` when `containerURL(forSecurityApplicationGroupIdentifier:)` is nil. Encode with ISO-8601 dates and sorted keys; write using `Data.write(to:options:.atomic)`.

- [ ] **Step 4: Implement the snapshot coordinator**

Define:

```swift
@MainActor
protocol TimetableWidgetReloading: AnyObject {
    func reloadTimetableWidgets()
}

@MainActor
@Observable
final class TimetableSnapshotCoordinator {
    private(set) var latestSnapshot: TimetableSnapshotV1?
    private(set) var errorMessage: String?

    init(
        calendar: any CalendarServicing,
        settings: AppSettingsStore,
        builder: TimetableSnapshotBuilder,
        writer: any TimetableSnapshotWriting,
        reloader: any TimetableWidgetReloading
    )

    @discardableResult
    func refresh(now: Date = .now) throws -> TimetableSnapshotV1
}
```

When access is granted, fetch the builder's Monday-to-Monday interval with `settings.visibleCalendarIDs(availableIDs:)`. When access is not granted, do not call `fetchEvents`. Always write the new snapshot before replacing `latestSnapshot`, then reload exactly once. Map storage/fetch failure to `errorMessage` and rethrow without reloading.

Implement `SystemTimetableWidgetReloader` using `WidgetCenter.shared.reloadTimelines(ofKind:)` for `NextClassWidget` and `WeekTimetableWidget`.

- [ ] **Step 5: Run the targeted coordinator tests to verify GREEN**

Expected: storage, happy-path refresh, and permission-loss tests all pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add PersonalCalendar/TimetableShared/TimetableSnapshotStore.swift \
  PersonalCalendar/Timetable/TimetableSnapshotCoordinator.swift \
  PersonalCalendarTests/Timetable/TimetableSnapshotCoordinatorTests.swift
git commit -m "feat: cache timetable snapshots for widgets"
```

### Task 3: Widget Extension, Next Class Widget, and Week Widget

**Files:**
- Create: `PersonalCalendar/TimetableShared/TimetableTimelineBuilder.swift`
- Create: `PersonalCalendarWidgets/Info.plist`
- Create: `PersonalCalendarWidgets/PersonalCalendarWidgets.entitlements`
- Create: `PersonalCalendar/Resources/PersonalCalendar.entitlements`
- Create: `PersonalCalendarWidgets/PersonalCalendarWidgetsBundle.swift`
- Create: `PersonalCalendarWidgets/TimetableWidgetProvider.swift`
- Create: `PersonalCalendarWidgets/NextClassWidget.swift`
- Create: `PersonalCalendarWidgets/WeekTimetableWidget.swift`
- Create: `PersonalCalendarWidgets/TimeRailsView.swift`
- Create: `PersonalCalendarTests/Timetable/TimetableTimelineBuilderTests.swift`
- Modify: `project.yml`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 DTO/status and Task 2 snapshot reader.
- Produces: widget extension target, two widget kinds, `TimetableTimelineBuilder.refreshDates(snapshot:now:calendar:)`, and reusable `TimeRailsView`.

- [ ] **Step 1: Write the failing timeline-boundary tests**

```swift
final class TimetableTimelineBuilderTests: XCTestCase {
    func testRefreshDatesContainUpcomingClassBoundariesAndNextMidnight() {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.monday0840)
        let dates = TimetableTimelineBuilder(calendar: fixture.calendar)
            .refreshDates(snapshot: snapshot, now: fixture.monday0840)

        XCTAssertEqual(dates.first, fixture.monday0840)
        XCTAssertTrue(dates.contains(fixture.monday0900))
        XCTAssertTrue(dates.contains(fixture.monday1100))
        XCTAssertTrue(dates.contains(fixture.tuesdayStart))
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
    }
}
```

- [ ] **Step 2: Run only `TimetableTimelineBuilderTests` to verify RED**

Expected: missing `TimetableTimelineBuilder`.

- [ ] **Step 3: Implement deterministic timeline dates**

`refreshDates` returns sorted unique dates containing `now`, every future entry start/end in the cached week, and the next local midnight. Drop dates `<= now` except the exact first `now` entry.

```swift
struct TimetableTimelineBuilder {
    let calendar: Calendar

    func refreshDates(
        snapshot: TimetableSnapshotV1,
        now: Date
    ) -> [Date] {
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let boundaries = snapshot.entries.flatMap { [$0.start, $0.end] }
        return Array(Set([now, nextMidnight] + boundaries.filter { $0 > now })).sorted()
    }
}
```

- [ ] **Step 4: Add extension project configuration**

Add app settings:

```yaml
CODE_SIGN_ENTITLEMENTS: PersonalCalendar/Resources/PersonalCalendar.entitlements
INFOPLIST_KEY_NSSupportsLiveActivities: YES
```

Add an embedded dependency from `PersonalCalendar` to `PersonalCalendarWidgets`. Add the target:

```yaml
PersonalCalendarWidgets:
  type: app-extension
  platform: iOS
  deploymentTarget: "17.0"
  sources:
    - path: PersonalCalendarWidgets
    - path: PersonalCalendar/TimetableShared
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: local.personalcalendar.iphone.widgets
      PRODUCT_NAME: PersonalCalendarWidgets
      INFOPLIST_FILE: PersonalCalendarWidgets/Info.plist
      CODE_SIGN_ENTITLEMENTS: PersonalCalendarWidgets/PersonalCalendarWidgets.entitlements
      APPLICATION_EXTENSION_API_ONLY: YES
      SKIP_INSTALL: YES
      TARGETED_DEVICE_FAMILY: "1"
```

Both entitlements files contain only:

```xml
<key>com.apple.security.application-groups</key>
<array><string>group.local.personalcalendar.shared</string></array>
```

The extension Info.plist uses `com.apple.widgetkit-extension`. Run `xcodegen generate` and inspect that the app target embeds `PersonalCalendarWidgets.appex`.

- [ ] **Step 5: Implement the provider and permanent widgets**

`TimetableWidgetProvider` reads `TimetableSnapshotStore.appGroup()`, emits a placeholder on failure, and supplies timeline entries at Task 3's refresh dates.

`NextClassWidget` supports only `.accessoryRectangular` and renders the snapshot's current/next/gap state with `NOW`/`NEXT`, title, time/countdown, and optional location. Add `.privacySensitive()` and redacted placeholders. Do not use color as the only state signal.

`WeekTimetableWidget` supports only `.systemMedium` and renders Monday-Friday through `TimeRailsView`. The widget's default tap behavior opens My Calendar without introducing a custom URL scheme.

`TimeRailsView` accepts `snapshot`, `now`, and `showsStatusStrip`; do not import EventKit or app-only theme types.

Use these target-level shapes:

```swift
struct TimetableWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TimetableSnapshotV1
}

struct TimetableWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimetableWidgetEntry
    func getSnapshot(in context: Context, completion: @escaping (TimetableWidgetEntry) -> Void)
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableWidgetEntry>) -> Void)
}

struct NextClassWidget: Widget {
    let kind = "NextClassWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimetableWidgetProvider()) { entry in
            NextClassWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Class")
        .description("See the current or next class on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct WeekTimetableWidget: Widget {
    let kind = "WeekTimetableWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimetableWidgetProvider()) { entry in
            WeekTimetableWidgetView(entry: entry)
        }
        .configurationDisplayName("School Week")
        .description("See Monday through Friday at a glance.")
        .supportedFamilies([.systemMedium])
    }
}
```

- [ ] **Step 6: Run the targeted timeline tests and build the extension**

Run only `TimetableTimelineBuilderTests`, then:

```bash
xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Expected: focused tests pass and the app build embeds `PersonalCalendarWidgets.appex`.

- [ ] **Step 7: Commit Task 3**

```bash
git add project.yml PersonalCalendar.xcodeproj/project.pbxproj \
  PersonalCalendar/Resources/PersonalCalendar.entitlements \
  PersonalCalendar/TimetableShared/TimetableTimelineBuilder.swift \
  PersonalCalendarWidgets PersonalCalendarTests/Timetable/TimetableTimelineBuilderTests.swift
git commit -m "feat: add timetable widgets"
```

### Task 4: ActivityKit Driver and Lifecycle Coordinator

**Files:**
- Create: `PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift`
- Create: `PersonalCalendar/Timetable/TimetableActivityDriver.swift`
- Create: `PersonalCalendar/Timetable/TimetableLiveActivityCoordinator.swift`
- Create: `PersonalCalendarTests/Timetable/TimetableLiveActivityCoordinatorTests.swift`

**Interfaces:**
- Consumes: bounded `TimetableSnapshotV1` values.
- Produces: `TimetableActivityAttributes`, `TimetableActivityDriving`, `SystemTimetableActivityDriver`, `NoopTimetableActivityDriver`, `TimetableLiveActivityStatus`, and observable `TimetableLiveActivityCoordinator`.

- [ ] **Step 1: Write failing lifecycle tests with a recording driver**

Bind the critical no-duplicate behavior:

```swift
@MainActor
final class TimetableLiveActivityCoordinatorTests: XCTestCase {
    func testStartRequestsExactlyOneActivityAndEndsDuplicates() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver(existingIDs: ["old-a", "old-b"])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)

        await subject.start(snapshot: snapshot, now: fixture.tuesday0941)

        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.updatedIDs, ["old-a"])
        XCTAssertEqual(driver.endedIDs, ["old-b"])
        XCTAssertEqual(subject.status, .running)
    }

    func testStartWithoutExistingActivityRequestsOnce() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver(existingIDs: [])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)
        await subject.start(snapshot: snapshot, now: fixture.tuesday0941)
        XCTAssertEqual(driver.requestCount, 1)
        XCTAssertTrue(driver.updatedIDs.isEmpty)
        XCTAssertTrue(driver.endedIDs.isEmpty)
        XCTAssertEqual(subject.status, .running)
    }

    func testPermissionLossStopsAllActivitiesAndNeverRequests() async {
        let fixture = TimetableTestFixture()
        let driver = RecordingTimetableActivityDriver(existingIDs: ["old-a", "old-b"])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: fixture.calendar)
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .denied, events: fixture.weekEvents, now: fixture.tuesday0941)
        await subject.start(snapshot: snapshot, now: fixture.tuesday0941)
        XCTAssertEqual(driver.requestCount, 0)
        XCTAssertEqual(driver.endedIDs, ["old-a", "old-b"])
        XCTAssertNotEqual(subject.status, .running)
    }
}
```

Also assert two simultaneous `start` calls produce one request through a synchronous `isWriting` guard.

- [ ] **Step 2: Run only `TimetableLiveActivityCoordinatorTests` to verify RED**

Expected: missing Activity attributes, driver, and coordinator symbols.

- [ ] **Step 3: Implement ActivityKit attributes and driver abstraction**

```swift
struct TimetableActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let snapshot: TimetableSnapshotV1
    }

    let weekStart: Date
    let timeZoneIdentifier: String
}

@MainActor
protocol TimetableActivityDriving: AnyObject {
    var activitiesEnabled: Bool { get }
    func activityIDs() -> [String]
    func request(attributes: TimetableActivityAttributes, state: TimetableActivityAttributes.ContentState, staleDate: Date?) throws -> String
    func update(id: String, state: TimetableActivityAttributes.ContentState, staleDate: Date?) async
    func end(id: String, immediately: Bool) async
}
```

The system driver resolves IDs against `Activity<TimetableActivityAttributes>.activities`, uses `ActivityContent(state:staleDate:)`, requests with `pushType: nil`, and ends with `.immediate` when privacy requires removal.

- [ ] **Step 4: Implement the observable coordinator**

```swift
enum TimetableLiveActivityStatus: Equatable {
    case idle
    case unavailable(String)
    case running
    case failed(String)
}

@MainActor
@Observable
final class TimetableLiveActivityCoordinator {
    private(set) var status: TimetableLiveActivityStatus = .idle
    private var isWriting = false

    func start(snapshot: TimetableSnapshotV1, now: Date = .now) async
    func reconcile(snapshot: TimetableSnapshotV1, now: Date = .now) async
    func stop() async
}
```

`start` validates authorization and today's nonempty entries, updates the first recovered activity or requests one, and ends duplicates. `reconcile` never starts a new activity; it only updates the first recovered one and ends duplicates, or ends all for permission loss/no classes. `stop` ends every activity immediately. Compute `staleDate` as the next start/end boundary after `now`.

- [ ] **Step 5: Run the targeted lifecycle tests to verify GREEN**

Expected: start, recovery, permission-loss, and double-call tests pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift \
  PersonalCalendar/Timetable/TimetableActivityDriver.swift \
  PersonalCalendar/Timetable/TimetableLiveActivityCoordinator.swift \
  PersonalCalendarTests/Timetable/TimetableLiveActivityCoordinatorTests.swift
git commit -m "feat: manage school day live activity"
```

### Task 5: Unsplit Time Rails Live Activity UI

**Files:**
- Create: `PersonalCalendar/TimetableShared/TimeRailsLayout.swift`
- Create: `PersonalCalendarWidgets/TimetableLiveActivity.swift`
- Create: `PersonalCalendarTests/Timetable/TimeRailsLayoutTests.swift`
- Modify: `PersonalCalendarWidgets/PersonalCalendarWidgetsBundle.swift`
- Modify: `PersonalCalendarWidgets/TimeRailsView.swift`

**Interfaces:**
- Consumes: Task 1 snapshots/status and Task 4 Activity attributes.
- Produces: normalized `TimeRailPlacement` values and the complete ActivityConfiguration.

- [ ] **Step 1: Write failing normalized-geometry tests**

```swift
final class TimeRailsLayoutTests: XCTestCase {
    func testGeometryPreservesDurationsAndMondayGap() {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)
        let placements = TimeRailsLayout(calendar: fixture.calendar, startHour: 9, endHour: 18)
            .placements(snapshot: snapshot)

        let friday = try XCTUnwrap(placements.first { $0.entry.shortTitle == "U22" })
        let tuesday = try XCTUnwrap(placements.first { $0.entry.shortTitle == "I03" && $0.weekdayIndex == 1 })
        let mondayLate = try XCTUnwrap(placements.first { $0.entry.shortTitle == "B05" && $0.weekdayIndex == 0 })
        XCTAssertEqual(friday.heightFraction, 3.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(tuesday.heightFraction, 2.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(mondayLate.startFraction, 7.0 / 9.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run only `TimeRailsLayoutTests` to verify RED**

Expected: missing normalized layout types.

- [ ] **Step 3: Implement the normalized layout model**

Define `TimeRailPlacement { entry, weekdayIndex, startFraction, heightFraction }`. Clamp entries to the 09:00–18:00 rail while preserving original details for the status strip. Sort by weekday, start, end, ID.

```swift
struct TimeRailPlacement: Hashable, Sendable {
    let entry: TimetableEntry
    let weekdayIndex: Int
    let startFraction: Double
    let heightFraction: Double
}

struct TimeRailsLayout: Sendable {
    let calendar: Calendar
    let startHour: Int
    let endHour: Int

    func placements(snapshot: TimetableSnapshotV1) -> [TimeRailPlacement]
}
```

For each entry, derive `weekdayIndex` as Monday-based `(weekday + 5) % 7`, intersect the event interval with that day's `startHour...endHour`, and divide offset/duration by `Double(endHour - startHour)`.

- [ ] **Step 4: Implement the full-width Lock Screen presentation**

Add `TimetableLiveActivity: Widget` using:

```swift
ActivityConfiguration(for: TimetableActivityAttributes.self) { context in
    TimetableLockScreenView(snapshot: context.state.snapshot)
        .privacySensitive()
        .activityBackgroundTint(.black.opacity(0.78))
        .activitySystemActionForegroundColor(.white)
} dynamicIsland: { context in
    DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { currentOrNextCode(context) }
        DynamicIslandExpandedRegion(.trailing) { boundaryTimer(context) }
        DynamicIslandExpandedRegion(.bottom) { currentOrNextDetail(context) }
    } compactLeading: {
        currentOrNextCode(context)
    } compactTrailing: {
        boundaryTimer(context)
    } minimal: {
        Circle().fill(Color.teal).frame(width: 8, height: 8)
    }
}
```

The Lock Screen view is one rounded card with a week label, shared 09/13/18 scale, five weekday columns, normalized blocks, current-time hairline, and one status strip. Keep its vertical content within 160 points and use codes only inside rails.

Handle `isLuminanceReduced` by removing teal fills and retaining `NOW`/`NEXT` text plus thicker outlines. Do not split the card or use multiple accessory widgets.

- [ ] **Step 5: Add the Activity to the widget bundle and build**

Add `TimetableLiveActivity()` as the third bundle member. Run only `TimeRailsLayoutTests`, then the Task 3 build command. Expected: focused tests pass and ActivityConfiguration compiles for iOS 17.

- [ ] **Step 6: Commit Task 5**

```bash
git add PersonalCalendar/TimetableShared/TimeRailsLayout.swift \
  PersonalCalendarWidgets/TimetableLiveActivity.swift \
  PersonalCalendarWidgets/PersonalCalendarWidgetsBundle.swift \
  PersonalCalendarWidgets/TimeRailsView.swift \
  PersonalCalendarTests/Timetable/TimeRailsLayoutTests.swift
git commit -m "feat: render full width timetable live activity"
```

### Task 6: App Environment, Refresh Pipeline, and Settings Controls

**Files:**
- Create: `PersonalCalendar/Features/Settings/TimetableSettingsView.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `PersonalCalendar/Refresh/AppRefreshCoordinator.swift`
- Modify: `PersonalCalendar/Features/Settings/SettingsView.swift`
- Modify: `PersonalCalendarTests/Refresh/AppRefreshCoordinatorTests.swift`

**Interfaces:**
- Consumes: Tasks 2 and 4 coordinators.
- Produces: app-owned timetable runtime, initial refresh, ordered store-change refresh, and user Start/Stop controls.

- [ ] **Step 1: Extend the focused refresh-order test first**

Update the existing recording-actions test to bind this sequence:

```swift
XCTAssertEqual(
    calls,
    ["permissions", "sources", "agenda", "category-links", "timetable", "notifications"]
)
```

Add `refreshTimetable` to `RefreshActions` and verify notifications do not begin until an asynchronously suspended timetable refresh completes.

- [ ] **Step 2: Run only `AppRefreshCoordinatorTests` to verify RED**

Expected: compiler failure because `RefreshActions` has no `refreshTimetable` member.

- [ ] **Step 3: Add timetable refresh to the coordinator pipeline**

Add:

```swift
let refreshTimetable: @MainActor () async -> Void
```

Call it after `cleanCategoryLinks()` and before `rescheduleNotifications()`. Update every production and test initializer explicitly.

- [ ] **Step 4: Compose live and demo timetable dependencies**

Add to `AppEnvironment`:

```swift
let timetableSnapshotCoordinator: TimetableSnapshotCoordinator
let timetableLiveActivityCoordinator: TimetableLiveActivityCoordinator
```

Live composition uses `TimetableSnapshotStore.appGroup()`, `SystemTimetableWidgetReloader`, and `SystemTimetableActivityDriver`. If App Group lookup fails, inject a writer that throws `containerUnavailable` so the app still launches and Settings exposes the error.

Demo composition uses a unique temporary file, a recording/no-op reloader, and `NoopTimetableActivityDriver` so UI tests never create system activities.

The refresh action calls `snapshotCoordinator.refresh()` and then `liveActivityCoordinator.reconcile(snapshot:)`. On thrown refresh, retain the prior Activity and expose the snapshot error; on permission-loss snapshot, reconcile ends it.

- [ ] **Step 5: Add Settings UI and first-launch refresh**

Add a `School timetable` NavigationLink in Settings. `TimetableSettingsView` contains:

- Current sync/access status.
- `Refresh timetable` button.
- `Start Today's Timetable` button, disabled unless the latest ready snapshot has timed entries today.
- `Stop Live Activity` button when status is running.
- Inline Activity authorization or storage error copy.
- A note that automatic background transitions require future push support.

Add a single root `.task` that calls `refreshCoordinator.refreshNow(reason: .launch)`. Keep the existing `scenePhase` foreground refresh. When visible calendar selection changes, the Settings dismissal path invokes the same refresh coordinator rather than only notification scheduling.

Use this view contract:

```swift
struct TimetableSettingsView: View {
    let snapshotCoordinator: TimetableSnapshotCoordinator
    let activityCoordinator: TimetableLiveActivityCoordinator
    let refresh: @MainActor () async -> Void

    var body: some View {
        List {
            Section("School timetable") {
                statusText
                Button("Refresh timetable") { Task { await refresh() } }
                Button("Start Today's Timetable") {
                    guard let snapshot = snapshotCoordinator.latestSnapshot else { return }
                    Task { await activityCoordinator.start(snapshot: snapshot) }
                }
                .disabled(!canStart)
                if activityCoordinator.status == .running {
                    Button("Stop Live Activity", role: .destructive) {
                        Task { await activityCoordinator.stop() }
                    }
                }
            }
        }
        .navigationTitle("School Timetable")
    }
}
```

`canStart` is true only for a `.ready` latest snapshot with an entry on the current injected local day and Activity status other than `.running`.

- [ ] **Step 6: Run only `AppRefreshCoordinatorTests` and build the app**

Expected: focused tests pass; build succeeds without a real Live Activity during demo/UI-test composition.

- [ ] **Step 7: Commit Task 6**

```bash
git add PersonalCalendar/Features/Settings/TimetableSettingsView.swift \
  PersonalCalendar/App/AppEnvironment.swift PersonalCalendar/App/RootTabView.swift \
  PersonalCalendar/Refresh/AppRefreshCoordinator.swift \
  PersonalCalendar/Features/Settings/SettingsView.swift \
  PersonalCalendarTests/Refresh/AppRefreshCoordinatorTests.swift
git commit -m "feat: wire timetable activity into the app"
```

### Task 7: Documentation and Focused Release Verification

**Files:**
- Modify: `README.md`
- Verify: all files from Tasks 1–6

**Interfaces:**
- Consumes: the complete feature.
- Produces: installation instructions and evidence that every focused contract and both targets compile.

- [ ] **Step 1: Document user setup and constraints**

Add README sections explaining:

- Add `Next Class` from Lock Screen customization.
- Add `School Week` as a medium Home Screen widget.
- Open My Calendar and use Settings → School timetable → Start Today's Timetable.
- The app must be opened to sync EventKit changes in the local-only MVP.
- Live Activities are limited to eight active hours.
- Physical-device builds require selecting a Development Team and provisioning `group.local.personalcalendar.shared` for both bundle IDs.

- [ ] **Step 2: Run each new focused test file separately**

Run these five commands independently, never as a combined/global suite:

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableSnapshotBuilderTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableSnapshotCoordinatorTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableTimelineBuilderTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableLiveActivityCoordinatorTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimeRailsLayoutTests
```

Then run only `PersonalCalendarTests/AppRefreshCoordinatorTests`.

- [ ] **Step 3: Regenerate and build both targets**

```bash
xcodegen generate
xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
git diff --check
```

Expected: app and embedded extension build with zero errors; diff check is clean.

- [ ] **Step 4: Perform the bounded manual simulator check**

Using the nine-class fixture or Calendar events on Simulator, verify only:

1. The medium widget shows all nine Monday-Friday entries.
2. The rectangular widget reports the correct current/next class.
3. Starting from Settings produces one unsplit full-width Activity.
4. Tuesday 09:41 highlights `I03` and Monday 13:30 shows the BAC 2005 gap state.
5. Stopping removes the Activity.

Record screenshots under `simulator-screenshots/timetable-widgets/` without committing generated screenshots unless requested.

- [ ] **Step 5: Commit Task 7**

```bash
git add README.md
git commit -m "docs: explain timetable widgets"
```

- [ ] **Step 6: Final status check**

Run `git status --short`. Expected: no uncommitted files.
