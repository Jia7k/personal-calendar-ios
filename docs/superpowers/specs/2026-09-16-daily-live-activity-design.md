# Daily Live Activity — events and tasks

Date: 2026-09-16

Status: Design and implementation approved on 2026-09-16. User constraint: test only on iPhone 16 Pro. No application changes are included in this document.

## Goal

Replace the weekly rails inside the Live Activity with a readable summary of the selected profile's remaining day: the current event, upcoming events, and pending tasks/reminders. Keep the existing weekly Home Screen widgets unchanged.

The approved B mockup uses a charcoal card, white text, teal calendar accents, orange task accents, one prominent current item, a short agenda, and a “+N more today” footer. Pending tasks use hollow circles, not completed checkmarks. Exact spacing must be adapted to the actual system presentation rather than reproducing an oversized concept image.

## Approach

Recommended: build a separate daily projection from the app's existing calendar and reminder services, then reuse the existing Live Activity lifecycle coordinator. This supports task-only days, weekends, and all-day items without changing weekly widget behavior.

Alternatives considered:

- Extend the weekly widget catalog with reminders and daily metadata. This couples two different surfaces and makes changes to the activity affect widget persistence and compatibility.
- Restyle the existing activity payload only. This is smaller, but the current weekly snapshot excludes tasks, weekends, and all-day events, so it cannot deliver the approved concept.

No backend, push service, new account, or direct editing from the Lock Screen is required.

## Content rules

- Use the Live Activity's selected/preferred profile, retaining the existing profile preference and automatic-start opt-in. Changing the app's currently viewed profile does not silently switch an existing activity.
- Resolve both calendar and reminder-list membership using the existing profile scope rules. “Everything” means the existing union of saved-profile memberships, not all device data.
- Include events intersecting the represented local day, including weekends, all-day events, and ongoing events that began the previous day. Exclude ended timed events from the remaining-day summary.
- Include incomplete reminders due on that local day. The app represents these as tasks; do not create a second reminder row for the same item.
- Timed tasks show “Due 10:45”; once that due time passes, show “Overdue · 10:45” and retain the task until completion or day rollover.
- Date-only tasks show “Today”. Undated tasks, tasks overdue from earlier days, completed tasks, and routines are outside this first version.
- An optional bell indicates that a task has an alert. Its displayed due time remains the due time, not the alert time. Unsupported alarm metadata must not be interpreted as a fabricated alert time.
- Use stable, source-qualified identities to deduplicate tasks and distinguish recurring event occurrences. Titles never determine identity.

## Presentation and ordering

### Lock Screen and expanded presentation

1. Header: “TODAY · WED 16 SEP” and profile name, with bounded wrapping/truncation for long names.
2. Hero: an active timed event first, otherwise the next timed event or task. Active event shows “Now”, title, time, optional location, time remaining, and elapsed progress. An upcoming event shows “Next”; a task shows “Due”. Only active events receive duration progress bars.
3. If no active or upcoming timed item exists, use a neutral “Today” heading with the remaining-item count rather than inventing a countdown for date-only or overdue tasks.
4. Agenda: up to three further items when the system's available space permits. Never repeat the hero. Order other active events first, then overdue-today tasks, then future timed items chronologically, then all-day events and date-only tasks. Within ties use end time where applicable, title, then stable identity.
5. For simultaneous active events, choose the earliest start, then earliest end, title, and identity for the hero; the others remain in the agenda/overflow.
6. Footer: “+N more today” when remaining items exceed the visible hero and rows. Count unique eligible items, not weekly snapshot omissions. Hide the footer when nothing is hidden.

Task rows are informational: the hollow circle is not a completion control. Tapping the card or footer opens the represented day in Calendar with the same profile. The full day remains available in the app.

Use readable system text styles and source icons in addition to color. At larger text sizes, reduce the visible row count before clipping controls or shrinking text. Long titles may wrap within the available layout; the app provides their full text. Maintain contrast on the dark surface and preserve privacy-sensitive redaction. Lock Screen and expanded Dynamic Island layouts may use different row counts.

### Compact and minimal Dynamic Island

Keep compact presentation focused on one item, not a tiny list. Prefer an active event, then the next timed item. Use the existing event abbreviation when appropriate; use a task glyph for a task. Show an end/start/due countdown only while that boundary is in the future. If only untimed or overdue items remain, show an item count without a countdown. Minimal presentation uses the appropriate source glyph, or a neutral day glyph for a mixed untimed summary.

The compact presentation opens the same profile-scoped day. No raw provider IDs, titles, locations, or reminder notes are embedded in URLs.

## Data and component boundaries

### Daily source coordinator

Add a focused app-side daily source coordinator using `CalendarServicing`, `RemindersServicing`, and `ProfileScopeResolver`. Fetch today's intersecting events and reminders only for nonempty authorized membership sets, then defensively filter the results by that scope. Empty membership must return an empty result without calling the underlying service: both concrete services interpret empty IDs as all provider sources. Reuse the guarding pattern in `ProfileSourceFetcher`. Profile selection metadata comes from the profile repository, not the weekly calendar snapshot, so a reminders-only profile is valid.

Publish a daily snapshot containing profile identity/name, represented day and time zone, generation time, source availability, and normalized items. Capture the day, time zone, and scope for a refresh; reject a late result if a newer refresh or scope change superseded it. Recheck authorization and membership before publishing.

Keep weekly `TimetableSnapshotV1`, `TimetableWidgetCatalogV1`, their App Group storage, and `TimeRailsView` unchanged. A weekly widget write failure must not prevent an otherwise valid daily activity update.

### Pure projection and versioned activity payload

Use a deterministic shared projection for eligibility, ordering, hero selection, visible rows, and overflow. It accepts a daily snapshot plus an explicit clock/calendar, so day boundaries and tests do not rely on global time.

Version the activity payload to represent source kind, event interval or task due date/date-only status, all-day status, optional location, and alert presence. Preserve the existing 3,500-byte content-state budget and separately verify static attributes and dynamic state fit the combined 4 KB ActivityKit limit. Omit notes and other unnecessary private fields. Bound strings by encoded size, not only character count. See [ActivityKit constraints](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

Trim lower-priority items after preserving the hero and nearest rows. Store a compact count of dropped candidates and their eligibility-expiration boundaries so “+N more” can decrease when hidden timed events finish. Coalesce equal boundaries. If bounded metadata cannot describe every omission, show “More in app” rather than an inaccurate number. Overdue tasks remain eligible until completion/day rollover. Never report “All done” when candidates were dropped or a required source is unavailable.

At render time, select the hero and rows from all retained full items and exclude expired events. Omission metadata cannot recreate a dropped item's title or promote it into a row. If omitted eligible items prevent determining the true next item, replace the “Next” claim with “More in app · Open to refresh”. The bounded projection must retain enough ordering metadata to detect that condition; when uncertain, use this fallback.

New decoders must safely recognize the old event-only activity state. On the next successful app refresh, end incompatible legacy activities and replace them only if current preferences and availability allow it. Do not migrate or rewrite weekly widget storage.

### Lifecycle and integration

Adapt the existing `TimetableLiveActivityCoordinator` to daily inputs while retaining its serialized start/update/end behavior, one-activity policy, explicit Stop action, and opt-in foreground automatic start. Start eligibility depends on at least one eligible daily item, not a weekday calendar entry.

Refresh daily data on existing launch, foreground, EventKit-change, and local-mutation paths. Profile edits/deletions and backup restore must also rebuild or invalidate the daily state, including reminder-list membership changes. Decouple the existing weekly coordinator's blanket `stop()` callback; the daily source coordinator owns daily privacy invalidation.

Settings retain weekly widget configuration. Label the activity section “Daily Live Activity”; use the daily source availability and selected profile for Start/Switch enablement and explanations. Preserve existing automatic-start and Stop-for-now behavior.

## Error, privacy, and time behavior

- A source with no configured membership is not an error. A tasks-only profile can start with reminder access even without calendar access, and vice versa.
- Intentional profile membership removal immediately excludes those items on reconciliation; it is not an access error. For still-configured sources with denied/revoked access or missing provider lists/calendars, remove their content before publishing the next state. If other permitted sources still have eligible items, continue with an explicit “Some calendars unavailable” or “Some tasks unavailable” indicator; otherwise end the activity and explain the reason in settings.
- On an uncertain fetch failure, do not reuse an old successful snapshot as a new authoritative result. End the existing activity on that refresh and expose a retryable error. Do not clear app calendar/task data.
- A deleted/missing profile ends its activity. Deep links validate the profile through existing routing safeguards rather than falling back to another profile's content.
- Use the snapshot time zone for item placement and the day label. A time-zone change triggers a fresh projection when the app resumes. At the represented day's end, stop labelling cached content “Today”; show a neutral refresh-required state until the app can reconcile/end it.
- Use supported SwiftUI timers for countdowns and date-based rendering for boundaries. Do not promise app execution, exact list transitions, task completion sync, or activity renewal while the app is suspended. When system content is stale, prioritize an “Open app to refresh” indication over stale “Now” claims.
- This version retains local/foreground updates, without server push. Settings must explain that it is a glanceable view of the last app refresh, not a guaranteed uninterrupted, always-current all-day service. Ending an empty/expired activity occurs when the app has execution time; the extension must still render cached terminal/stale states honestly.
- Preserve the concrete platform-duration explanation: an activity can run for up to eight hours, then leaves the Dynamic Island and can remain on the Lock Screen for up to four further hours. Starting early may therefore expire before the day ends; the activity cannot renew itself while the app is suspended. Render an ended state honestly and reconcile system-ended/dismissed activities on the next app foreground. See [ActivityKit lifecycle limits](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

Apple's guidance favors compact, glanceable content, direct navigation to related details, and focused interactions. The implementation must be checked in the actual Lock Screen and Dynamic Island containers, not only in a free-sized preview. See [Live Activities design guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities) and [ActivityKit implementation guidance](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

## Verification requirements

- Projection: mixed sources, event-only/task-only/all-day-only days, empty day, no-due tasks, completion, duplicate reminders, due versus alert time, overlap ordering, weekend, overnight event, day rollover, time-zone/DST boundaries, and overdue-today versus prior-day tasks.
- Payload: legacy decoding, all new kinds, oversized Unicode strings, bounded encoded request/state, hidden-item accounting over time, no duplicate hero, and truthful fallback when count metadata is capped.
- Lifecycle: start/update/switch/stop, opt-in behavior, no automatic duplicate activity, system expiration/dismissal, source-specific permission loss, empty-membership fetch short-circuiting, profile membership/reminder-list removal, deletion, backup restore, fetch failure, and rejecting stale asynchronous results.
- Routing: correct profile and represented day; malformed or removed profiles fail closed; no raw private data in links.
- Regression: existing weekly widget snapshot, catalog, selection, timeline, and route tests remain passing. The weekly widget retains its current appearance and filters.
- User-directed device scope: run app tests and visual checks only on the iPhone 16 Pro. Do not run the earlier small-phone/other-model matrix. On that device, check long titles/profile names, normal and accessibility text sizes, active event plus mixed rows, task-only state, all-day state, empty/stale state, compact/expanded/minimal Dynamic Island, redaction, and overflow/footer hit area. Verify the final Live Activity on the physical iPhone 16 Pro before claiming device behavior is confirmed.

## Delivery boundary

Implement and test inline in this repository. The user's approval permits test deployment to the iPhone 16 Pro; it does not authorize a GitHub push or unrelated installation. Protect real provider data during automated testing. Do not add routines, direct task completion, a notification backend, unrelated calendar redesigns, or changes to weekly Home Screen widgets.
