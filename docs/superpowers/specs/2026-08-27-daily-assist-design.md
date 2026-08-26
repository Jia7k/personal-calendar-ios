# Daily Assist Design

Date: 2026-08-27

## Summary

Daily Assist turns the existing calendar, task, routine, profile, widget, and Quick Entry foundations into a lower-friction day-to-day assistant. It adds six connected improvements without replacing Apple Calendar or Reminders as the authoritative stores:

1. Fast overdue-task triage and undo.
2. One app-wide deep-link route plus useful notification actions.
3. Complete, honest timetable widgets and opt-in foreground Live Activity automation.
4. Safe task-to-calendar time blocking.
5. Quick Entry capture from Siri, Shortcuts, Spotlight, and the Action Button with in-app confirmation.
6. A focused Next Up experience, jump-to-date, duplication, and recent Quick Entry presets.

These features reuse the existing profile scope, EventKit services, routine repository, notification scheduler, widget catalog, Live Activity coordinator, Quick Entry parser/router, editors, refresh ownership, and fixed-light Harbor & Linen theme.

## Approved product decisions

- Overdue tasks have quick actions for Later Today, Tomorrow, Next Week, and Pick Date.
- Every quick reschedule offers one in-app Undo.
- Recurring reminders open the full editor instead of applying a quick series mutation.
- Routine notifications offer Complete and Snooze 15 min actions.
- The morning summary opens Today.
- Class alerts are opt-in per saved profile and default to off.
- Event locations open in Apple Maps.
- Today routines open their routine editor, and Week Planner tasks can be completed directly.
- Weekly widgets include the complete usable timetable rather than silently keeping only twelve classes.
- Timetable rails adapt to early and late lessons, and surfaces show when their snapshot was last updated.
- Widget taps open the relevant profile and class in the app.
- Live Activity automatic start is opt-in and occurs when the app becomes active; the app never promises guaranteed background starts or updates.
- Time blocking proposes free 30, 60, and 90 minute slots, creates a normal Calendar event, and retains the original Reminder.
- Conflicting manual time-block choices show a warning but can still be confirmed.
- Siri/Shortcuts/Spotlight/Action Button capture always opens the existing Quick Entry confirmation before an external write.
- Today gains one compact Next Up card with the next event, countdown, room/Maps action, and nearest incomplete deadline.
- Calendar gains jump-to-date. Event, task, and routine editors gain Duplicate.
- Quick Entry remembers a bounded recent list and the last useful duration/category/destination choices without silently saving.

## Goals

- Reduce the number of taps needed to plan and finish a normal day.
- Prevent missed classes and deadlines without overwhelming the user with notifications.
- Make all timetable surfaces truthful for early, late, and busy school weeks.
- Preserve profile isolation and never fall back from an empty profile to every provider source.
- Keep EventKit and the routine repository authoritative; app-owned state stores only preferences, route metadata, and bounded history.
- Reuse existing editors and confirmation flows for risky or ambiguous actions.
- Fail closed when permissions, profile membership, or provider authority changes.
- Keep the app local-first with no new account, backend, CloudKit, or server dependency.

## Non-goals

- A custom timetable database or ICS importer.
- Guaranteed background Live Activity creation, refresh, or termination.
- Bidirectional coupling between a Reminder and its optional time-block event.
- Silent task deletion or completion after creating a time block.
- Quick-changing recurring Reminder series dates from an overdue swipe action.
- Replacing Apple Calendar or Reminders provider content with app-owned copies.
- Cloud synchronization of presets, settings, profiles, or routines.
- Travel-time prediction, route traffic, attachments, subtasks, collaboration, or social features.
- A new root tab.

## Shared architecture

### App route

Create one typed `AppRoute` as the only destination language used by notification responses, widgets, URLs, App Intents, and internal cross-tab navigation:

```swift
enum AppRoute: Equatable, Sendable {
    case today
    case calendar(day: LocalDay?, profile: ProfileIdentity?, item: AgendaItemOrigin?)
    case task(id: String, profile: ProfileIdentity?)
    case routine(id: UUID, profile: ProfileIdentity?)
    case quickEntry(text: String, profile: ProfileIdentity?)
}
```

`AppRouteCodec` encodes and decodes versioned `personalcalendar://v1/...` URLs. It rejects unknown versions, missing identifiers, malformed dates, and unsupported route kinds. It never interprets a missing or deleted saved profile as Everything.

`RootTabView` remains the presentation owner. A long-lived `AppRouteController` consumes each route identity once, selects the necessary tab/profile, then asks the existing host/editor route to open the exact item. Missing or no-longer-visible items show neutral unavailable copy and never fall back to a different item.

### Preference storage

Add app-owned, versioned settings for:

- per-profile class-alert enablement and lead minutes;
- preferred Live Activity profile and foreground-auto-start enablement;
- bounded recent Quick Entry records;
- last Quick Entry duration, category, calendar, and reminder-list choices.

These settings live in `AppSettingsStore`/UserDefaults and are included in the next backup schema version. They contain only app-owned identifiers/preferences, never EventKit notes, alarms, URLs, or provider objects.

### Refresh and authority

Every feature resolves the active or explicitly chosen `ProfileScope` once at the beginning of an operation. External provider calls receive exact nonempty source ID sets; empty sets short-circuit because the current service contract interprets an empty set as all sources.

Any action that mutates an event, reminder, or routine revalidates:

- current provider access;
- exact profile membership;
- source/item writability;
- existence of the target item;
- the operation's recurrence and schedule constraints.

Successful mutations use existing host refresh signals. Selection changes alone do not reschedule notifications or create external writes.

## Slice 1: Daily task triage

### Model

`TasksViewModel` publishes four sections: Overdue, Today, Upcoming, and Completed. Overdue contains incomplete dated reminders before the injected local day. Today no longer absorbs overdue rows.

Add a typed quick-reschedule command:

```swift
enum TaskQuickReschedule: Equatable, Sendable {
    case laterToday
    case tomorrow
    case nextWeek
    case pick(Date, hasTime: Bool)
}
```

The model computes dates with its injected `Calendar` and `now`:

- Later Today preserves an existing future time today; otherwise it uses 6:00 PM, clamped to at least 15 minutes after `now`.
- Tomorrow preserves the original local time when one exists; date-only reminders remain date-only.
- Next Week means seven calendar days later and preserves time/date-only semantics.
- Pick uses the explicit date and time flag.

The update draft uses `.replace(ReminderScheduleValue)` and `.preserve` for alarm and recurrence. A reminder with recurrence never exposes these quick actions and opens the existing Task editor instead.

### Undo and failure

On successful reschedule, retain one `TaskRescheduleUndo` containing the reminder ID and previous schedule. Show a short-lived Undo banner. Undo revalidates current scope and authority, then restores the prior schedule exactly. A new quick reschedule replaces the older undo token. Failed writes keep the original confirmed row and show the existing retry/error affordance.

### Interface

Overdue rows offer swipe/context actions for Tomorrow and Next Week plus a More menu containing Later Today and Pick Date. All controls have spoken labels and 44-point targets. The same commands are available from the selected Week Planner task detail.

## Slice 2: Deep links and actionable notifications

### Notification contract

Extend `LocalNotificationRequest` with a category identifier and string-only `userInfo`. Define identifiers centrally:

- `routine-reminder`: actions `routine-complete` and `routine-snooze-15`.
- `morning-summary`: default tap routes to Today.
- `class-alert`: default tap routes to the exact calendar event/profile.

`SystemNotificationScheduler` registers categories once and maps requests to `UNMutableNotificationContent`. A small `AppNotificationDelegate` forwards response payloads to an `AppNotificationActionHandler` owned by `AppEnvironment`.

Routine Complete revalidates the routine and current local day before writing a completion. Snooze schedules one replacement notification 15 minutes after the response time and does not alter the routine's persistent reminder time. Duplicate Complete responses are idempotent.

### Class alerts

Class alerts use ready, timed timetable entries from each opted-in saved profile. Default state is disabled. A profile can choose 5, 10, 15, 20, or 30 minutes. The scheduler emits only future alerts within its existing bounded horizon and deterministic budget, keyed by profile identity plus synthetic timetable entry identity and start time.

Permission loss or profile deletion immediately removes affected pending requests. Ordinary provider refresh failure retains previously confirmed requests until the next successful refresh; membership removal is security-sensitive and removes stale requests.

### Links and Maps

Widget and notification routes contain only profile identity plus privacy-safe app display identity. The app resolves the current provider snapshot after opening. It never serializes EventKit mutation IDs into shared files or URLs.

Event rows and Next Up expose a Maps action when location is nonblank. The URL uses `MKMapItem`/MapKit search terms rather than hand-built map query escaping.

## Slice 3: Reliable timetable surfaces

### Snapshot building

Remove the fixed `prefix(12)` behavior. The weekly catalog builder sorts the complete filtered week deterministically, then enforces an encoded-size budget rather than an item-count budget. It shortens already-bounded display strings before omitting an entry. If entries still exceed the budget, it keeps the nearest chronological entries and records an explicit omitted count; no surface may imply the visible list is complete when it is not.

The widget catalog may use a larger file budget because it is app-group JSON. The Live Activity content projects only today's current/upcoming entries and stays below ActivityKit's content-state size limit.

### Adaptive rails and freshness

`TimeRailsLayout` derives its start/end minutes from entries with 08:00–18:00 defaults, rounds outward to whole hours, and clamps to 00:00–24:00. The view scrolls or compresses within platform limits instead of dropping out-of-range classes.

Every timetable widget and timetable settings screen displays `generatedAt` as a concise last-updated value. A stale threshold of six hours changes copy to “Open Personal Calendar to refresh”; it does not invent background freshness.

Widget timeline entries include boundaries for class starts/ends and the stale threshold. The app rebuilds the catalog on every practical foreground, EventKit change, permission change, profile membership change, and successful relevant mutation.

### Widget links and Live Activity preference

Next Class links to the exact class/profile route. Week links to the chosen profile's current week. Deleted profile or unavailable access remains fail-closed with no fallback.

Settings lets the user choose one saved/Everything timetable for foreground auto-start. When enabled, app activation reconciles the latest catalog and starts today's activity if appropriate. Disabling it stops the activity. This is explicitly foreground behavior; user-visible copy retains the eight-hour and runtime limitations.

## Slice 4: Task time blocking

### Availability engine

`TaskTimeBlockPlanner` is a pure component that receives:

- the task's due date/time;
- a requested duration of 30, 60, or 90 minutes;
- the chosen saved profile scope;
- existing scoped calendar events for the candidate day;
- injected Calendar, now, and working-day bounds.

It proposes up to three free intervals between 8:00 AM and 9:00 PM, prioritizing slots before the task due time, then the nearest later slot on the same day. It treats timed events as busy, ignores all-day events for clock availability, and uses Calendar arithmetic.

### Creation flow

From a Task row/editor, Schedule Time opens a sheet showing suggestions, duration, explicit calendar destination, and conflict state. The destination defaults to the captured saved profile's valid writable calendar; Everything must first choose a saved profile. A missing/read-only destination blocks creation.

Saving creates one normal EventKit event titled from the task. The event notes contain a versioned app marker with the task display ID solely to support navigation; the Reminder is retained unchanged. The app records no ownership promise and does not automatically delete/update either side when the other changes.

A manually adjusted overlapping interval shows the colliding event titles and requires a second confirmation. Provider failure creates nothing else and leaves the sheet ready to retry.

## Slice 5: Capture anywhere

### App Intent

Add an app-target `QuickEntryIntent` with:

- required natural-language text;
- optional saved-profile entity;
- `openAppWhenRun == true`.

The intent validates only that text is nonblank and returns/opens a versioned Quick Entry `AppRoute`. It never invokes `SaveRouter` or EventKit from the intent process. `RootTabView` consumes the route, resolves the exact profile, constructs the existing `QuickEntryViewModel`, parses the text, and presents confirmation.

`AppShortcutsProvider` publishes concise phrases for Add to Personal Calendar and Plan with Personal Calendar. The same intent becomes available to Siri, Shortcuts, Spotlight, and the Action Button on supported devices.

### Confirmation and presets

External capture is visibly marked as coming from a shortcut and otherwise uses the same validation, profile-aware destinations, confirmation, exactly-once commit, warning, refresh, and retry rules as in-app Quick Entry.

Recent Quick Entry stores at most ten unique normalized text/profile pairs, newest first. It stores no provider notes or resolved event data. Selecting a recent item repopulates entry and requires Review/Save again. Successful edits update last duration/category/destination preferences only when those choices remain valid for the same kind/profile.

## Slice 6: Next Up and small QOL actions

### Next Up

`TodayViewModel` derives one immutable `NextUpSnapshot` from already-scoped confirmed content:

- current event, otherwise next timed event;
- countdown/start/end and nonblank location;
- nearest incomplete dated task after now;
- typed origins for Open and Maps actions.

`TodayView` displays one compact card above the agenda. It does not make a second provider fetch. Routine rows in Today use the existing routine deep-link route.

### Jump to date

Calendar adds a toolbar Jump to Date action with a graphical DatePicker. Confirming updates `selectedDay`, synchronizes month/week state, loads the exact visible range, then scrolls/highlights the selected day.

### Duplicate

Duplicate actions appear only for editable content:

- Event duplicates into a create draft with the same duration, title, notes, location, alarms, and recurrence but a user-confirmed new start.
- Task duplicates into a create draft with title, notes, priority, schedule, alarm, and recurrence, requiring a valid destination.
- Routine duplicates into a new draft with title suffixed “Copy”, schedule, reminder, and category, then uses the profile-aware atomic creation boundary.

Duplication always opens a create editor before writing. External identifiers, completion state/history, and mutation IDs are never copied.

## Data flow

```text
Widget / notification / URL / App Intent / in-app action
                         ↓
                    AppRouteCodec
                         ↓
                 AppRouteController
                         ↓
        RootTabView selects profile + destination tab
                         ↓
     existing editor / Quick Entry / Today / Calendar host
                         ↓
  live authority check → one provider/repository mutation
                         ↓
 typed refresh signal → agenda/widget/notification reconciliation
```

Task triage, time blocking, and duplicate flows all use this same authority and refresh boundary. No deep-link target performs a provider mutation merely by opening.

## Error, privacy, and accessibility rules

- Never expose another profile's cached content while a new scope is loading or failing.
- Never call an external fetch with an empty source-ID set.
- Never fall back from a deleted/missing selected profile to Everything for a widget, notification, Live Activity, Quick Entry, or time-block route.
- Permission denial surfaces existing source-specific Settings guidance.
- Notification and widget payloads contain only bounded display fields and privacy-safe synthetic identities.
- Destructive or series-affecting actions use existing confirmation/editor flows.
- Every swipe action has a context-menu/button equivalent.
- Notification actions have equivalent in-app controls.
- Regular controls retain 44-point hit targets and explicit VoiceOver labels/values.
- Accessibility Dynamic Type uses list/agenda presentations instead of compressed multi-column interactions.
- The fixed light appearance and Harbor & Linen palette remain unchanged.

## File boundaries

New focused domains:

- `PersonalCalendar/Routing/` — route types, codec, controller, and notification action bridge.
- `PersonalCalendar/Features/Tasks/TaskQuickReschedule.swift` — pure scheduling rules and undo value.
- `PersonalCalendar/Notifications/ClassAlertCoordinator.swift` — per-profile class alert projection.
- `PersonalCalendar/Features/Tasks/TaskTimeBlockPlanner.swift` and `TaskTimeBlockView.swift` — pure free-slot planning and confirmation UI.
- `PersonalCalendar/Intents/` — app Quick Entry intent/entities/shortcuts.
- `PersonalCalendar/Features/Today/NextUpSnapshot.swift` — pure derived card model.
- Focused settings/value types remain in existing settings and timetable domains.

Existing integration files change only at their current ownership seams: `RootTabView`, `AppEnvironment`, `AppSettingsStore`, `TasksViewModel/View`, `TodayViewModel/View`, `CalendarHomeView/Model`, editors, notification scheduler/coordinator, timetable builder/provider/views, and backup DTO/service.

## Testing strategy

Each slice begins with pure or model-level RED tests and runs only its focused class while iterating. Provider repositories and notification drivers use existing fakes or narrow local doubles; App Intent tests assert route generation and zero saver/provider calls.

Required focused coverage:

- Task reschedule date arithmetic, recurrence refusal, exact drafts, failure retention, and one-token Undo.
- Route codec round trips and malformed/deleted-profile fail-closed behavior.
- Routine Complete/Snooze idempotence and morning/class route payloads.
- Class alert opt-in, lead times, source/profile filtering, budget, and removal.
- 13+ class weeks, 08:00/evening lessons, encoded-size overflow disclosure, adaptive rails, stale timelines, and widget URLs.
- Live Activity foreground preference without background guarantees.
- Free-slot suggestions, DST arithmetic, exact destination authority, conflict confirmation, one event create, and unchanged Reminder.
- App Intent always opens confirmation and never saves directly.
- Next Up ordering, Maps visibility, routine opening, jump-to-date, duplication draft fidelity, and bounded preset history.

After slices 1–2 and 3–4, run a milestone regression suite. After all six slices, run the global unit/UI suite, build the widget extension, inspect the final diff, then commit and push.

## Delivery order

1. Daily task triage.
2. Shared route foundation and actionable notifications.
3. Timetable completeness, freshness, links, and foreground Live Activity preference.
4. Task time blocking.
5. Capture-anywhere App Intent and recent presets.
6. Next Up, jump-to-date, duplicate actions, and final integration.

Every slice is independently useful and keeps the app functional if later slices are deferred.
