# School Timetable Widgets and Live Activity Design

Date: 2026-08-25

## Summary

Add three timetable surfaces to My Calendar:

1. A full-width Lock Screen Live Activity that renders the approved Time Rails design during a school day.
2. A permanent rectangular Lock Screen widget that shows the next class.
3. A medium Home Screen widget that shows the Monday-to-Friday timetable.

The app remains the only process that reads EventKit. It converts the user's currently visible calendar events into a small, versioned weekly snapshot, writes that snapshot to an App Group, reloads WidgetKit timelines, and updates any active Live Activity. The extension reads only this compact snapshot.

This is a local-first MVP. It does not introduce a server, ActivityKit push notifications, or a promise that a Live Activity will start and transition reliably while the app has no runtime.

## Goals

- Display the complete Monday-to-Friday timetable in one unsplit, full-width Live Activity card.
- Make class position and duration understandable through Time Rails geometry.
- Keep the current or next class prominent without hiding the week.
- Provide useful permanent widgets when the Live Activity is not running.
- Reuse existing Calendar permission and visible-calendar selection behavior.
- Minimize Lock Screen data and avoid exposing EventKit mutation identifiers or notes.
- Keep the existing app, SwiftData store, notification system, and calendar editing flows unchanged.

## Non-goals

- A backend or APNs-based ActivityKit updates.
- Guaranteed hands-free Live Activity start, class-boundary update, or removal on iOS 17–25.
- Moving or sharing the existing SwiftData store.
- A new timetable database or manual timetable editor.
- Parsing the uploaded timetable screenshot into production data.
- Showing reminders, routines, all-day events, weekends, notes, URLs, alarms, or recurrence details in timetable surfaces.
- Making the main application support dark mode. The dark appearance belongs only to the user's system Lock Screen.

## Product behavior

### Source data

Production timetable data comes from timed events in the Apple calendars already visible in My Calendar. The existing Settings screen controls that selection. A student who wants only school events in the timetable should select their school calendar as the visible calendar.

The app fetches the local-calendar week from Monday 00:00 through the following Monday 00:00. It removes all-day events and Saturday/Sunday entries, sorts occurrences deterministically, and produces short labels for dense rails.

For a title beginning with a three-letter course prefix and four digits, the compact label uses the first prefix letter and final two digits:

- `INF 2001` becomes `I01`
- `BAC 2005` becomes `B05`
- `UDE 2222` becomes `U22`

Other titles use a bounded, trimmed abbreviation. Full titles remain available in next/current class details.

### Full-width Live Activity

The Live Activity uses one uninterrupted Lock Screen card. It contains:

- A week label.
- Five weekday rails.
- A shared time scale.
- Course-code capsules positioned by start time and sized by duration.
- A current-day indicator.
- A current or next class status strip.
- Compact Dynamic Island presentations for the current or next class.

The card remains at or below 160 points high. The five rails show course codes only. Class type, full time, location, and countdown are restricted to the status strip or expanded Dynamic Island.

The user starts the Live Activity from Settings with `Start Today's Timetable`. The app also reconciles an existing activity when the app enters the foreground or receives an EventKit change while alive. The user can stop it from Settings.

For the MVP:

- The app starts an activity only while it has runtime.
- It recovers active activities through `Activity<TimetableActivityAttributes>.activities` rather than trusting a saved activity ID.
- It updates one activity and ends duplicates.
- It marks content stale at the next meaningful class boundary.
- It ends the activity on permission loss, when there are no classes for today, or when the user turns the feature off.
- It does not claim that `staleDate` switches class content or removes the activity.

A Live Activity can be active for at most eight hours. Monday's sample 09:00–18:00 schedule is nine hours, so the final hour cannot be guaranteed as an actively updating Activity without a second Activity or server coordination. The permanent widget remains the fallback. A seamless APNs-backed handover is deferred.

### Next Class Lock Screen widget

The permanent `.accessoryRectangular` widget shows:

- `NOW` or `NEXT`.
- Full course title.
- Start/end or countdown.
- Online/room location when space allows.

If Calendar access is unavailable, it says `Calendar access required`. If the cache is empty or stale, it says `Open My Calendar to sync`.

The system controls vibrant rendering on the Lock Screen, so the widget cannot depend on teal. Its state is also conveyed with text and weight.

### Week Home Screen widget

The `.systemMedium` widget shows the complete Monday-to-Friday week using the same Time Rails model. It may use the Harbor teal accent because Home Screen rendering supports richer color treatment. Tapping opens the Calendar tab.

The widget refreshes from precomputed timeline boundaries and whenever the app rewrites the snapshot.

## Shared data contract

Shared files compile into both the app and widget-extension modules.

```swift
struct TimetableSnapshotV1: Codable, Hashable, Sendable {
    let version: Int
    let availability: TimetableAvailability
    let generatedAt: Date
    let weekStart: Date
    let timeZoneIdentifier: String
    let entries: [TimetableEntry]
}

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

struct TimetableActivityAttributes: ActivityAttributes {
    let weekStart: Date
    let timeZoneIdentifier: String

    struct ContentState: Codable, Hashable {
        let generatedAt: Date
        let entries: [TimetableEntry]
    }
}
```

The snapshot mapper:

- Builds occurrence identity from display event ID plus occurrence start.
- Bounds title, short-title, and location length.
- Caps the number of entries before ActivityKit encoding.
- Excludes calendar IDs, mutation IDs, notes, URLs, alarms, recurrence metadata, and permission objects.
- Keeps the combined Activity attributes and content state below 4 KB.

## Storage and privacy

Both targets use the App Group `group.local.personalcalendar.shared`.

The app writes `timetable-v1.json` atomically into the shared container. The extension is read-only. The app calls `WidgetCenter.shared.reloadTimelines(ofKind:)` after a successful write.

On Calendar permission loss, the app atomically replaces the prior data with an empty `.calendarAccessRequired` snapshot, reloads widget timelines, and ends active timetable activities. This prevents old class titles and locations from remaining on the Lock Screen.

Widget and Live Activity text is marked privacy-sensitive where appropriate and supplies redacted placeholders. The existing `showNextItemOnLockScreen` setting belongs to morning notifications and is not reused as widget consent.

The existing SwiftData container remains app-private.

## Components

### Shared module sources

- `TimetableSnapshot.swift`: versioned DTOs, title abbreviation, filtering helpers, and display computations.
- `TimetableActivityAttributes.swift`: ActivityKit attributes/content state.
- `TimetableSnapshotStore.swift`: App Group JSON reader/writer contract with app-write and extension-read use.

### App sources

- `TimetableSnapshotCoordinator`: fetches the selected week, maps EventKit snapshots, persists the result, and reloads WidgetKit.
- `TimetableLiveActivityCoordinator`: starts, updates, recovers, and ends timetable activities.
- `TimetableSettingsView`: enablement/status plus Start and Stop actions.

`AppEnvironment` owns the coordinators for the lifetime of the app. Live and demo environments receive separate implementations; demo/UI tests must never create a real Activity.

`AppRefreshCoordinator` invokes timetable snapshot reconciliation after permission/source/agenda refresh. EventStore monitoring therefore refreshes the cache whenever the app process observes an EventKit change.

### Extension sources

- `PersonalCalendarWidgetsBundle`: declares all widgets and the Live Activity.
- `NextClassWidget`: `.accessoryRectangular` view and timeline provider.
- `WeekTimetableWidget`: `.systemMedium` view and timeline provider.
- `TimetableLiveActivity`: Lock Screen and Dynamic Island presentations.
- Reusable `TimeRailsView`: renders geometry from the shared snapshot without importing EventKit or app-only types.

## Project configuration

`project.yml` remains the project source of truth.

Add:

- An embedded `PersonalCalendarWidgets` app-extension target.
- WidgetKit, SwiftUI, and ActivityKit frameworks where required.
- App and extension entitlements containing the shared App Group.
- `NSSupportsLiveActivities = YES` for the app.
- `APPLICATION_EXTENSION_API_ONLY = YES` for the extension.
- The widget extension Info.plist with `com.apple.widgetkit-extension`.
- Shared source membership in both app and extension targets.
- Extension build membership in the existing scheme.

Regenerate `PersonalCalendar.xcodeproj` with XcodeGen. Do not edit `project.pbxproj` manually.

Physical-device installation still requires the user to choose a Development Team and provision the App Group for both bundle identifiers.

## Lifecycle and refresh flow

```text
App foreground / EventKit store change / visible-calendar change
  -> refresh Calendar permission and source selection
  -> fetch Monday-to-Monday selected calendar occurrences
  -> map privacy-minimized TimetableSnapshotV1
  -> atomic App Group write
  -> reload Next Class and Week widget timelines
  -> if a Live Activity already exists, update or end it

User taps Start Today's Timetable
  -> rebuild snapshot
  -> verify Activity authorization and today's timed classes
  -> recover/end duplicates
  -> request one Activity with bounded week content

Widget extension timeline request
  -> read shared JSON only
  -> construct entries at now, midnight, and class boundaries
  -> render ready/access-required/sync-required state
```

The iOS 17 MVP performs no network requests. iOS 26 scheduled local starts and APNs push-to-start/update are explicitly deferred until the base surfaces are stable.

## Error behavior

- Calendar access missing: clear shared event data, show access-required widget states, end Activity.
- No events this week: render a friendly `No classes this week` state and disable Start.
- App Group read failure: widgets show `Open My Calendar to sync`; the app reports an inline Settings error.
- Activity authorization disabled: Settings explains that Live Activities must be enabled in System Settings; permanent widgets still work.
- Activity request/update failure: retain widget cache, show an inline error, and never duplicate activities.
- Oversized arbitrary calendar week: deterministically cap entries and strings before writing or requesting the Activity.

## Testing strategy

Unit tests avoid EventKit, ActivityKit system UI, and App Group I/O through narrow protocols.

Required focused tests:

- Snapshot mapping uses visible calendar events, excludes all-day/weekend items, and preserves exact start/end/location.
- Compact course codes map the supplied INF/BAC/UDE titles correctly.
- Permission loss writes the access-required snapshot and requests Activity termination.
- Next/current class computation handles before-class, in-class, gap, and after-school states.
- Widget timeline boundaries include midnight and class starts/ends.
- Activity coordinator single-flights start, recovers one activity, and ends duplicates.
- Activity payload stays within the configured entry/string caps.

Widget view previews use the supplied nine-class timetable fixture. One focused app test validates the entire happy path from weekly service snapshots to persisted shared DTO and one Activity request. Simulator/manual verification checks the three approved states on the black iPhone 17 Pro Lock Screen, Always-On reduced luminance, and the medium Home Screen widget.

## Acceptance criteria

- The generated project contains and embeds a widget extension.
- The app and extension can read the same App Group snapshot on Simulator.
- A rectangular Lock Screen widget shows the correct next class.
- A medium Home Screen widget shows all supplied Monday-to-Friday classes.
- Starting the school-day Activity creates exactly one full-width card.
- The full-width card is unsplit and displays five rails with correct time geometry.
- Tuesday 09:41 highlights INF 2003 and shows its remaining time.
- Monday 13:30 exposes the 13:00–16:00 gap and BAC 2005 as next.
- Permission loss removes private cached entries and ends the Activity.
- The existing app remains light-only and all preexisting calendar/reminder/routine flows remain unchanged.

## Deferred enhancements

- iOS 26 scheduled local Activity starts with the required alert.
- APNs push-to-start and boundary updates for reliable hands-free operation.
- Seamless second Activity for days longer than eight hours.
- Separate timetable-calendar selection instead of reusing visible calendars.
- User-defined school-day time range, alias editing, and class colors.
- Lock Screen controls, StandBy-specific layouts, and Apple Watch surfaces.
