# Week Planner and Profile-Aware Search Design

Date: 2026-08-26

## Summary

Add two connected planning features to the existing Calendar tab:

1. A `Week` mode beside the current month mode, showing a compact seven-day timeline with real event durations, task due markers, all-day/date-only items, the current-time line, and routines for the selected day.
2. A profile-aware search screen opened from the Calendar toolbar, covering events, reminders, and routines in the currently selected profile and routing results into the existing editors.

The features reuse the existing profile scope, EventKit services, routine repository, agenda composition, editors, refresh ownership, Harbor & Linen light theme, and accessibility conventions. They do not add another root tab or another creation path.

## Approved product decisions

- Calendar keeps one top-level tab with a native `Month / Week` control.
- The active profile applies identically to month, week, and search.
- Week events are duration blocks; timed tasks are point-in-time due markers.
- All-day events and date-only tasks live in a compact strip above the timeline.
- Routines for the selected day live in a `Later` strip rather than pretending to have arbitrary durations.
- Tapping an item shows its concise details and can open the existing editor.
- Search covers event titles, locations, notes, source names, task titles/notes, routine titles, and useful date text.
- Search is reached from Calendar rather than becoming a fifth tab.
- The existing fixed light appearance and Harbor & Linen palette remain unchanged.
- Accessibility text sizes use a readable day-by-day agenda instead of squeezing seven timeline columns.

## Goals

- Let a student understand the whole school week at a glance.
- Keep early, late, and long classes visible without silently clipping them.
- Show tasks and routines in the same planning context without misrepresenting their duration.
- Let the user find an event, assignment, room, note, or routine quickly.
- Keep profile isolation exact, including the `Everything` union semantics.
- Reuse existing edit and refresh flows so search and week mode do not create competing mutation paths.
- Preserve confirmed same-profile data on an ordinary refresh failure while never showing one profile's data after switching to another.

## Non-goals

- Creating a second timetable database or importing ICS files.
- Adding a fifth Search or Week tab.
- Full-text indexing, Spotlight, cloud search, or a background search database.
- Dragging or resizing events directly on the week grid.
- Creating tasks with inferred duration.
- Showing unassigned provider sources in `Everything`.
- Replacing the existing Month view, Today view, editors, or universal Add flow.
- Searching an unbounded EventKit history.

## Week planner architecture

### Calendar state and loading

Add a typed `CalendarDisplayMode` with `.month` and `.week`. `CalendarViewModel` owns the mode so navigation, loading, tests, and accessibility all observe one source of truth.

The model derives an exact visible day range:

- Month mode uses the existing padded month grid.
- Week mode uses the seven locale-ordered days containing `selectedDay`, respecting the injected calendar's `firstWeekday` and time zone.

Switching modes retains `selectedDay`. Month navigation advances one month; week navigation advances seven calendar days. `Today` selects the injected current day and moves the visible range to it. All date arithmetic uses `Calendar`, never fixed second counts, so DST and locale boundaries remain correct.

Each load captures exactly one `ProfileScope` before fetching. Empty calendar or reminder membership short-circuits without calling services whose empty-ID contract otherwise means all sources. Routines are filtered by exact UUID before completion-history reads. Profile changes clear prior-profile content before any await; same-profile refresh failures may retain only content still in the captured scope.

### Week projection

Create a pure `WeekPlannerBuilder` that projects the model's already-scoped `visibleAgendas` plus scoped event snapshots into an immutable `WeekPlannerSnapshot`.

The snapshot contains:

- Ordered week days.
- All-day/date-only items with their owning day and `AgendaItemOrigin`.
- Timed event blocks with start and end clipped to each day.
- Timed task markers at the exact due time.
- Anchored routines for the selected day.
- The visible hour range.

The builder reuses `AgendaItem` for source, completion, category, mutation authority, and editor origin. It consults the matching `CalendarEventSnapshot` only to recover an event's end time. Multi-day events are represented once per intersected day and clipped to that day's boundary.

The visible hour range defaults to 8:00 AM–6:00 PM, expands outward to include every timed item in the week, and may reach the full 0:00–24:00 range. Nothing outside a fixed school-day window is dropped. The view scrolls vertically when the resulting range is tall.

Events that overlap within a day split the available day column width. Stable ordering is start, end, title, then identity, so layout does not jump between refreshes.

### Week interface

`CalendarHomeView` keeps the existing navigation title, Settings control, profile selector, universal Add route, and editor sheet. It adds:

- A native Month/Week picker below the title.
- Previous/next period and Today controls appropriate to the selected mode.
- `WeekPlannerView` in week mode.
- A Calendar toolbar search button.

The week view renders:

- A compact all-day/date-only strip.
- Seven day headers.
- A vertically scrollable timeline with neutral hour rules.
- Category color when present, otherwise the existing event/task source color.
- A diamond task marker paired with an accessibility label.
- A current-time line only when the current day is in the displayed week.
- One selected-item detail row with an Open action.
- A `Later` strip for the selected day's routines.

Selecting a day updates `selectedDay`. Selecting an event or task reuses the existing `CalendarHomeView.openAgendaItem` editor route. Selecting a routine sends a typed deep-link signal to `RootTabView`, which selects Routines and asks `RoutinesView` to open the matching existing row after its current scoped reload.

At accessibility Dynamic Type sizes, `WeekPlannerView` switches to seven day sections containing chronological agenda rows. It preserves every item and action while avoiding unreadable seven-column cells. All interactive controls retain a 44-point minimum target and explicit VoiceOver labels/values.

## Profile-aware search architecture

### Search corpus

Create a `CalendarSearchViewModel` with the existing Calendar and Reminders services, Routine repository, category repository, profile-scope resolver closure, injected Calendar, and injected `now`.

Opening search loads one local corpus for the captured active profile:

- Events from one year before `now` through two years after `now`.
- Reminders from the profile's exact reminder-list IDs.
- Routines from the profile's exact routine UUIDs, including paused routines but excluding archived routines.

The interval is deliberately bounded because EventKit event queries require a range and an unbounded search would be unpredictable. The screen explains the date range only when a query has no older match; it does not clutter normal results.

An empty calendar, reminder, or routine scope produces an empty contribution without a provider call. Fetched provider results are filtered again by exact IDs before entering the corpus. A profile change clears the old corpus synchronously, cancels the old generation, then loads the new scope.

### Matching and ordering

Typing filters the loaded corpus locally after a short 250 ms debounce. Matching is case- and diacritic-insensitive and token-based: every query token must appear somewhere in the result's normalized searchable text.

Searchable text includes:

- Events: title, location, notes, calendar title, weekday, localized date, and localized time.
- Tasks: title, notes, reminder-list title, due weekday/date/time, and priority label.
- Routines: title, routine window, scheduled weekday names, and category name when present.

Results are grouped as:

- `Upcoming`: current/next events and incomplete tasks, ordered by date then stable identity.
- `Past & completed`: past events and completed tasks, ordered newest first.
- `Routines`: active or paused routines, ordered by title then UUID.

Each group is capped at 50 visible results to keep the UI responsive. The model retains the full loaded corpus, so refining the query can reveal a different matching set without another provider fetch.

An empty query shows a simple prompt rather than all personal data. No-match copy suggests searching by course code, room, title, or date.

### Search interface and routing

`CalendarSearchView` is pushed from the Calendar navigation stack and uses native `.searchable` behavior. It shows the same profile selector in the toolbar and reloads on the profile scope revision.

Rows display source, title, concise secondary context, and date/time. Color is supplemental; source is always stated in text and VoiceOver.

Selecting a result returns its typed `AgendaItemOrigin`:

- Event and reminder results dismiss search and open the existing Event or Task editor from `CalendarHomeView`.
- Routine results dismiss search and use the typed root deep-link signal to switch to Routines and open the matching editor.

Search itself is read-only. Every mutation still passes through existing editor authority checks, profile-aware defaults, commit callbacks, refresh signals, and provider error handling.

## Error and empty states

- Calendar and Reminders failures are independent; successful sources still produce week/search content.
- Same-profile refresh failure preserves only previously confirmed, still-in-scope content and shows a retry message.
- A profile change or failed scope resolution clears content before showing an error, preventing cross-profile leakage.
- Denied/restricted provider access uses the existing source-specific access language and Settings action.
- An empty profile shows the existing configure-profile guidance; it never falls back to all sources.
- Search cancellation or a superseded generation never publishes stale results.
- A result that disappears before opening yields a neutral “This item is no longer available” message and does not mutate anything.

## Data flow

```text
ProfileSelectionController.scopeRevision
        ↓
ProfileScopeResolver → captured ProfileScope
        ├─→ visible-period fetches → CalendarViewModel scoped cache
        │                              ↓
        │                       WeekPlannerBuilder → WeekPlannerView
        │
        └─→ bounded search fetches → CalendarSearchViewModel corpus
                                           ↓ local token filtering
                                    CalendarSearchView results
                                           ↓ typed origin
                           existing editors / routine deep-link signal
```

The search model may perform its own bounded event fetch because the month/week cache is intentionally limited to the visible period. It does not persist a duplicate index.

## File boundaries

New focused files:

- `PersonalCalendar/Features/Calendar/WeekPlannerModels.swift` — immutable week projection types.
- `PersonalCalendar/Features/Calendar/WeekPlannerBuilder.swift` — pure projection and overlap layout inputs.
- `PersonalCalendar/Features/Calendar/WeekPlannerView.swift` — regular and accessibility layouts.
- `PersonalCalendar/Features/Search/CalendarSearchModels.swift` — result and grouping types.
- `PersonalCalendar/Features/Search/CalendarSearchViewModel.swift` — scoped corpus loading and local matching.
- `PersonalCalendar/Features/Search/CalendarSearchView.swift` — native search UI.

Existing files changed only at integration seams:

- `CalendarViewModel.swift` — display mode, exact visible range, week projection exposure.
- `CalendarHomeView.swift` — mode picker, week view, search navigation, typed selection routing.
- `RootTabView.swift` — one transient routine deep-link signal.
- `RoutinesView.swift` — consume the signal once and open the existing scoped row.
- Focused test files and generated Xcode project membership.

No provider protocol, persistence schema, profile repository, backup format, widget catalog, or notification contract changes are required.

## Testing strategy

### Pure unit tests

`WeekPlannerBuilderTests` verifies:

- Locale-ordered seven-day output.
- Event duration and per-day clipping.
- Date-only task strip placement and timed task markers.
- Routine Later-strip projection.
- Adaptive hour bounds including early/late items with no omission.
- Stable overlap grouping and sorting.

`CalendarSearchViewModelTests` verifies:

- Exact active-profile fetch IDs and strict empty-scope short-circuiting.
- Over-return filtering.
- Matching across title, room, notes, source, weekday, and date.
- Upcoming/past/routine grouping and stable ordering.
- Cross-profile cache clearing before suspended work completes.
- Partial provider failure and same-profile confirmed-data retention.
- Stale generation cancellation.

### Focused integration tests

Extend `CalendarViewModelTests` for Month/Week switching, seven-day navigation, Today, DST-safe intervals, and profile revision behavior.

Add one focused UI happy path using deterministic demo data:

1. Open Calendar in School.
2. Switch to Week and verify the visible school class and task marker.
3. Open Search, query a course code, and verify event/task/routine results.
4. Open one event result and confirm the existing editor appears.

Run only the focused test classes during development. A broader suite is reserved for the final integration gate.

## Delivery order

1. Week projection types and pure builder.
2. Calendar model range/mode support.
3. Week Planner SwiftUI and editor/deep-link integration.
4. Search models and scoped corpus loader.
5. Search SwiftUI and result routing.
6. Focused UI happy path, accessibility verification, and final regression gate.

This order leaves a useful, independently testable Week Planner before Search is introduced.
