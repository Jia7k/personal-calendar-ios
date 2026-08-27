# Timetable Surface Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ready timetable widgets and Live Activities open the exact configured profile, local day, and current/upcoming class when an opaque occurrence identity is available.

**Architecture:** Add one pure target-shared route builder over the existing versioned `AppRouteCodec`, then project the exact configured `ProfileIdentity` and existing privacy-safe `routeID` into WidgetKit and ActivityKit display state. SwiftUI surfaces attach one optional URL at their root; non-ready or malformed states remain inert and never fall back to Everything.

**Tech Stack:** Swift 6, Foundation, SwiftUI, WidgetKit, ActivityKit, AppIntents, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-27-timetable-surface-links-design.md`

## Global Constraints

- Use the existing `personalcalendar://v1/calendar` route; add no second URL scheme.
- URLs may contain only route version, Gregorian day, `ProfileIdentity.storageKey`, and the existing opaque occurrence `routeID`.
- Never serialize title, location, notes, alarms, EventKit display IDs, mutation IDs, or provider payloads in a route URL.
- Deleted, malformed, unconfigured, permission-required, empty-profile, and no-classes states expose no route and never fall back to Everything.
- Next Class and Live Activity use the exact current/upcoming occurrence when possible; their safe fallback is the exact profile plus local day without an entry ID.
- Week Timetable opens the exact configured profile and timeline-entry local day without arbitrarily selecting an event.
- Activity state decoding must keep pre-route running activities recoverable by treating a missing route field as nil.
- URL construction failure removes only the link; timetable content still renders.
- Keep current widget families, privacy redaction, and visual timetable layout unchanged.

---

### Task 1: Shared Privacy-Safe Timetable Route Builder

**Files:**
- Create: `PersonalCalendar/ProfileShared/TimetableSurfaceRouteBuilder.swift`
- Create: `PersonalCalendarTests/Routing/TimetableSurfaceRouteBuilderTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ProfileIdentity`, `AppRouteDay`, `AppRoute.calendar`, and `AppRouteCodec`.
- Produces:

```swift
struct TimetableSurfaceRouteBuilder: Sendable {
    let codec: AppRouteCodec

    init(codec: AppRouteCodec = .init())

    func url(
        profile: ProfileIdentity,
        date: Date,
        timeZoneIdentifier: String,
        entryRouteID: String?
    ) throws -> URL
}

enum TimetableSurfaceRouteBuilderError: Error, Equatable, Sendable {
    case invalidTimeZoneIdentifier(String)
    case invalidLocalDay
}
```

The builder trims whitespace/newlines from `entryRouteID`; an empty result becomes nil. It creates a Gregorian calendar with the supplied time zone and derives year/month/day from `date`. An unknown time-zone identifier throws `invalidTimeZoneIdentifier` so a surface fails closed instead of routing to the wrong day.

- [ ] **Step 1: Add focused RED tests**

Create behavior tests:

```swift
func testExactSavedProfileDayAndOpaqueEntryRoundTrip()
func testEverythingProfileAndBlankEntryRoundTripAsDayNavigation()
func testSuppliedTimeZoneControlsDayNearMidnight()
func testGregorianDayRemainsCorrectAcrossDSTTransition()
func testInvalidTimeZoneFailsClosed()
func testURLDoesNotContainTitleLocationDisplayIDNotesOrMutationID()
func testTwoProfilesProduceDifferentRoutesForTheSameOccurrence()
```

Use literal expected `AppRoute.calendar` values decoded through the real `AppRouteCodec`. The privacy test must provide recognizable forbidden strings only as unrelated fixture data and assert the encoded URL contains none of them; do not derive expectations with the builder.

- [ ] **Step 2: Regenerate once and capture RED**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableSurfaceRouteBuilderTests
```

Expected: missing `TimetableSurfaceRouteBuilder`.

- [ ] **Step 3: Implement the minimal builder**

```swift
func url(
    profile: ProfileIdentity,
    date: Date,
    timeZoneIdentifier: String,
    entryRouteID: String?
) throws -> URL {
    var calendar = Calendar(identifier: .gregorian)
    guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
        throw TimetableSurfaceRouteBuilderError
            .invalidTimeZoneIdentifier(timeZoneIdentifier)
    }
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else {
        throw TimetableSurfaceRouteBuilderError.invalidLocalDay
    }
    let normalized = entryRouteID?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return try codec.url(for: .calendar(
        day: .init(year: year, month: month, day: day),
        profile: profile,
        entryID: normalized?.isEmpty == false ? normalized : nil
    ))
}
```

- [ ] **Step 4: Run GREEN, mutation-check, and commit**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableSurfaceRouteBuilderTests
git add PersonalCalendar/ProfileShared/TimetableSurfaceRouteBuilder.swift PersonalCalendarTests/Routing/TimetableSurfaceRouteBuilderTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add timetable surface route builder"
```

Mutating the builder to use device-local time, omit the profile, or keep a blank entry ID must fail a focused test.

---

### Task 2: Profile-Aware Widget Links

**Files:**
- Modify: `PersonalCalendarWidgets/TimetableWidgetProvider.swift`
- Modify: `PersonalCalendarWidgets/NextClassWidget.swift`
- Modify: `PersonalCalendarWidgets/WeekTimetableWidget.swift`
- Create: `PersonalCalendar/TimetableShared/TimetableWidgetRouting.swift`
- Create: `PersonalCalendarTests/Timetable/TimetableWidgetRouteResolverTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 `TimetableSurfaceRouteBuilder`, `TimetableSnapshotV1.moment(at:calendar:)`, and the exact identity produced by `TimetableWidgetSelectionResolver`.
- Produces:

```swift
enum TimetableWidgetContent: Hashable, Sendable {
    case chooseProfile
    case profileDeleted
    case calendarAccessRequired(profileName: String)
    case emptyProfile(profileName: String)
    case noClasses(profileName: String)
    case ready(
        profile: ProfileIdentity,
        profileName: String,
        snapshot: TimetableSnapshotV1
    )
}

struct TimetableWidgetRouteResolver: Sendable {
    func nextClassURL(content: TimetableWidgetContent, date: Date) -> URL?
    func weekURL(content: TimetableWidgetContent, date: Date) -> URL?
}
```

Move the Foundation-only `TimetableWidgetContent` enum out of the extension provider into `TimetableWidgetRouting.swift`; `TimetableWidgetEntry` remains in the WidgetKit target. The pure resolver therefore compiles in both targets and app tests validate extension routing without importing WidgetKit. `nextClassURL` calls `snapshot.moment(at: date, calendar: calendar).entry`, then uses that entry's route ID and start date; when there is no current/upcoming entry it uses the supplied timeline date and nil route ID. `weekURL` always uses the supplied timeline date and nil route ID. Both return nil for non-ready states or builder errors.

- [ ] **Step 1: Add RED resolver tests before changing WidgetKit views**

Add:

```swift
func testNextClassUsesCurrentOccurrenceOpaqueRouteIDAndExactProfile()
func testNextClassUsesUpcomingOccurrenceAndItsLocalStartDay()
func testNextClassAfterLastClassFallsBackToExactProfileAndCurrentLocalDay()
func testWeekUsesExactProfileAndTimelineLocalDayWithoutEntryID()
func testTwoReadyWidgetConfigurationsProduceDifferentProfileURLs()
func testChooseDeletedPermissionEmptyAndNoClassesStatesHaveNoURL()
```

Fixtures must use an opaque `routeID` different from the entry's synthetic `id`, so accidentally routing with `id` fails.

- [ ] **Step 2: Run RED**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableWidgetRouteResolverTests
```

Expected: missing resolver and old `.ready` associated values.

- [ ] **Step 3: Thread exact identity through provider content**

Change placeholder content to:

```swift
.ready(
    profile: .everything,
    profileName: "School",
    snapshot: placeholderSnapshot(now: now)
)
```

In `loadContent`, use only the parsed configured identity and return:

```swift
.ready(profile: identity, profileName: profileName, snapshot: snapshot)
```

Update `isPlaceholder`, `containsPrivateData`, `timeline`, and every switch pattern for the new associated value. Do not attach identity to non-ready cases.

- [ ] **Step 4: Implement pure URL resolution and attach root widget URLs**

Add the resolver by calling `TimetableSurfaceRouteBuilder.url(profile:date:timeZoneIdentifier:entryRouteID:)` inside a `do/catch` that returns nil on failure. In `NextClassWidgetView`, compute the URL from `entry.content` and `entry.date`, then apply:

```swift
.widgetURL(TimetableWidgetRouteResolver().nextClassURL(
    content: entry.content,
    date: entry.date
))
.accessibilityHint(
    routeURL == nil ? "" : "Opens this class in My Calendar"
)
```

In `WeekTimetableWidgetView`, use `weekURL(content:date:)` and the hint `Opens this week in My Calendar`. Applying `.widgetURL(nil)` to a non-ready root is acceptable and remains inert; never synthesize a URL for those cases.

- [ ] **Step 5: Run GREEN, build the extension, and commit**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableWidgetRouteResolverTests
xcodebuild build -project PersonalCalendar.xcodeproj -target PersonalCalendarWidgets -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
git add PersonalCalendarWidgets/TimetableWidgetProvider.swift PersonalCalendarWidgets/NextClassWidget.swift PersonalCalendarWidgets/WeekTimetableWidget.swift PersonalCalendar/TimetableShared/TimetableWidgetRouting.swift PersonalCalendarTests/Timetable/TimetableWidgetRouteResolverTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: link timetable widgets to exact profiles"
```

---

### Task 3: Live Activity Occurrence Links with Legacy Recovery

**Files:**
- Modify: `PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift`
- Modify: `PersonalCalendarWidgets/TimetableLiveActivity.swift`
- Create: `PersonalCalendar/TimetableShared/TimetableActivityRouteResolver.swift`
- Modify: `PersonalCalendarTests/Timetable/TimetableLiveActivityCoordinatorTests.swift`
- Create: `PersonalCalendarTests/Timetable/TimetableActivityRouteResolverTests.swift`
- Regenerate: `PersonalCalendar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 route builder, existing immutable `TimetableActivityAttributes.profileIdentity`, and `ContentState.entry(at:)`.
- Produces:

```swift
extension TimetableActivityAttributes.ContentState.Entry {
    let routeID: String?
}

struct TimetableActivityRouteResolver: Sendable {
    func url(
        attributes: TimetableActivityAttributes,
        state: TimetableActivityAttributes.ContentState,
        now: Date
    ) -> URL?
}
```

The compact entry coding key is `case routeID = "r"`. Decode it with `decodeIfPresent`; encoding omits nil. Projection copies `TimetableEntry.routeID`. The resolver uses the state current/upcoming entry's route ID and start date, otherwise `now` plus nil entry ID.

- [ ] **Step 1: Add RED state and resolver tests**

Add tests:

```swift
func testCompactProjectionPreservesOpaqueOccurrenceRouteID()
func testLegacyCompactEntryWithoutRouteIDDecodesAsNil()
func testActivityCurrentAndUpcomingEntriesOpenExactProfileOccurrence()
func testActivityWithoutEntryRouteIDFallsBackToExactProfileAndLocalDay()
func testActivityRoutesForDifferentProfilesRemainDistinct()
func testActivityURLContainsNoTitleLocationOrSyntheticEntryID()
```

Construct the legacy JSON by hand using existing compact keys `i/t/s/b/e/l` and omit `r`; do not encode it using the new type.

- [ ] **Step 2: Run RED**

```bash
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableActivityRouteResolverTests -only-testing:PersonalCalendarTests/TimetableLiveActivityCoordinatorTests
```

Expected: missing `routeID`/resolver and projection assertion failure.

- [ ] **Step 3: Add compact route identity without breaking payload limits**

Add optional `routeID`, copy a bounded opaque value from the source entry, and include it in compact Codable. Retain the existing 3,500-byte loop: if the extra compact field makes the state too large, the loop still drops only the chronological tail entry and increments omissions honestly. When rebuilding `compactSnapshot` in the widget extension, pass `routeID: $0.routeID`.

- [ ] **Step 4: Attach one URL to Lock Screen and Dynamic Island roots**

Use one local helper per Activity context:

```swift
let routeURL = TimetableActivityRouteResolver().url(
    attributes: context.attributes,
    state: context.state,
    now: .now
)
```

For the Lock Screen, calculate `routeURL` and apply `.widgetURL(routeURL)` to the root inside its existing `TimelineView` closure using that closure's `context.date`; this keeps the current/upcoming destination aligned with the minute-based visual transition without adding multiple links. For Dynamic Island, apply one `.widgetURL(routeURL)` to the `DynamicIsland` root before `keylineTint`. Keep `.privacySensitive()` on visible title/location content. A nil URL leaves the Activity rendered but inert. ActivityKit ultimately controls render cadence, so exact boundary changes remain best-effort when the app has no runtime; the exact profile/day fallback stays valid.

- [ ] **Step 5: Run GREEN, extension build, privacy scan, and commit**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableActivityRouteResolverTests -only-testing:PersonalCalendarTests/TimetableLiveActivityCoordinatorTests
xcodebuild build -project PersonalCalendar.xcodeproj -target PersonalCalendarWidgets -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
rg -n "displayID|mutationID|notes|alarm" PersonalCalendar/ProfileShared/TimetableSurfaceRouteBuilder.swift PersonalCalendar/TimetableShared/TimetableWidgetRouting.swift PersonalCalendar/TimetableShared/TimetableActivityRouteResolver.swift PersonalCalendarWidgets
git diff --check
git add PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift PersonalCalendar/TimetableShared/TimetableActivityRouteResolver.swift PersonalCalendarWidgets/TimetableLiveActivity.swift PersonalCalendarTests/Timetable/TimetableLiveActivityCoordinatorTests.swift PersonalCalendarTests/Timetable/TimetableActivityRouteResolverTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: link Live Activities to exact classes"
```

The privacy scan may find existing display-only UI text references elsewhere in the widget target; manually confirm no route builder or URL construction accepts those fields.

---

### Task 4: Integrated Routing Verification

**Files:**
- Modify only if a discovered regression requires it: `PersonalCalendarTests/Routing/AppRouteHostResolverTests.swift`
- Modify: `README.md`
- Modify: `docs/manual-qa/foundation-accessibility.md`
- Verify: `PersonalCalendar/ProfileShared/AppRoute.swift`
- Verify: `PersonalCalendar/App/RootTabView.swift`

**Interfaces:**
- Consumes: all preceding tasks and the existing authoritative calendar deep-link host path.
- Produces: verified end-to-end behavior that a surface URL selects the exact profile/day and either opens the opaque occurrence or shows the existing neutral unavailable state.

- [ ] **Step 1: Run existing host authority regressions**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/AppRouteTests -only-testing:PersonalCalendarTests/AppRouteHostResolverTests
```

Expected: all existing exact-identity, stale occurrence, deleted profile, and no-fallback tests pass unchanged.

- [ ] **Step 2: Run the complete timetable focused set**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableSurfaceRouteBuilderTests -only-testing:PersonalCalendarTests/TimetableWidgetRouteResolverTests -only-testing:PersonalCalendarTests/TimetableActivityRouteResolverTests -only-testing:PersonalCalendarTests/TimetableLiveActivityCoordinatorTests -only-testing:PersonalCalendarTests/TimetableProfileActivityTests
xcodebuild build -project PersonalCalendar.xcodeproj -target PersonalCalendarWidgets -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
git diff --check
```

- [ ] **Step 3: Document the exact tap and fallback behavior**

Update the README timetable section to state:

- Next Class opens the exact current/upcoming class in the widget's configured profile;
- Weekly Timetable opens the represented day in that exact profile;
- a Live Activity opens the current/upcoming class when its occurrence identity is available and otherwise opens the exact profile/day;
- deleted profiles or occurrences show the app's neutral unavailable state, never Everything;
- links do not improve the existing foreground/local-refresh limitations.

Add manual QA checks for exact School versus Personal profile routing, after-last-class day fallback, a deleted-profile inert/unavailable path, legacy running Activity fallback, and VoiceOver's `Opens this class/week in My Calendar` hint.

- [ ] **Step 4: Commit integrated verification and docs**

```bash
git add README.md docs/manual-qa/foundation-accessibility.md PersonalCalendarTests/Routing/AppRouteHostResolverTests.swift
git commit -m "docs: explain timetable surface links"
```

The host regression file is staged only if the implementation exposed a missing behavioral assertion; do not change production host routing when the existing tests already pass.
