# Daily Task Rescue Design

## Status

Approved for implementation by the user's “yes go” response to the ranked QOL milestone on 2026-08-27. This spec chooses concrete defaults under the user's standing instruction to proceed autonomously when the intent is clear.

## Problem

Personal Calendar already handles overdue task rescheduling and task-to-calendar time blocking, but those tools are exposed from only part of the app:

- incomplete tasks without a due date are mixed into `Upcoming`, where they are easy to forget;
- Today mixes overdue reminders into the generic Priority section and loses useful “due N days ago” context;
- task time blocking is available from Tasks and task editors, but not directly from Today or Calendar Week;
- the existing reschedule Undo is local to Tasks, so Today cannot safely rescue an overdue item and reverse the change in place.

The result is unnecessary navigation at exactly the moments when the user is deciding what to do next.

## Goals

1. Make every incomplete, profile-visible task without a due date visibly actionable.
2. Give overdue tasks a distinct rescue surface in Today, including age and one-tap actions.
3. Expose the existing conflict-aware Schedule Time flow from Today and Calendar Week.
4. Preserve the current provider-authority, profile-isolation, recurrence, Undo, and accessibility guarantees.

## Non-goals

- No new `My Day` database or app-owned task metadata.
- No batch editing or drag-to-reschedule.
- No automatic changes to a Reminder when a calendar time block is created.
- No quick rescheduling of recurring, completed, read-only, missing, or out-of-profile tasks.
- No change to EventKit's existing empty-ID semantics; profile-aware callers still fail closed and never fetch all sources for an empty scope.

## Considered Approaches

### A. Thin reuse of existing task actions — chosen

Keep provider mutation authority in the existing view models, reuse `TaskQuickReschedulePlanner`, `TaskRescheduleUndo`, and `TaskTimeBlockSession`, and add only the state needed by each host. This has the smallest regression surface and preserves the current root-owned refresh model.

### B. A global task-action coordinator

Move completion, rescheduling, Undo, and time-block presentation into one shared observable coordinator. This could reduce long-term duplication, but it would change ownership across Tasks, Today, Calendar, deep links, editor sheets, and tests. It is too large for this QOL milestone.

### C. A persistent My Day layer

Let the user pin arbitrary tasks into a local daily list independent of provider due dates. This is useful, but introduces a new persisted reference model, deletion reconciliation, backup versioning, and cross-profile policy. It remains a later product option.

## Design

### 1. Needs Scheduling in Tasks

`TasksViewModel` publishes a new `needsScheduling: [ReminderSnapshot]` collection containing exact-scope reminders that are:

- incomplete;
- missing `dueDate`;
- currently visible in the captured profile scope.

`Upcoming` contains only tasks whose due day is after today. Undated tasks no longer appear there.

Tasks renders `Needs Scheduling` after Overdue and before Today. Each incomplete row offers **Schedule Time** because that action creates an independent event. Editable, nonrecurring rows additionally offer:

- **Today** — set a date-only due date for the current local day;
- **Tomorrow** — set a date-only due date for the next local day;
- **Pick Date** — use the existing date/time picker;

The section and actions have stable accessibility identifiers. Read-only and recurring tasks remain visible but use the full editor instead of quick schedule mutations. Schedule Time remains available because it creates an independent event and does not mutate recurrence.

The existing one-item reschedule Undo supports a previous schedule of `nil`, so Today/Tomorrow/Pick Date can restore the task to undated. `TaskQuickReschedule` gains a `.today` command whose result is today's date with `hasTime == false`.

### 2. Overdue Rescue in Today

`TodayViewModel` publishes `overdueTasks: [TodayOverdueTask]` from the same captured, filtered reminder cache used to build Today. `TodayOverdueTask` contains the exact `ReminderSnapshot` plus a positive calendar-day `daysOverdue` value. A task is overdue when it is incomplete, has a due date, and its `LocalDay` is earlier than today in the injected calendar.

Before composing the generic agenda, Today removes those reminders from the composer input and sets `includeOverdueTasks` to false. This prevents duplicates while leaving today's tasks, events, and routines unchanged.

Today renders an `Overdue` section before the ordinary agenda sections. Each row shows:

- task title;
- `Due yesterday` or `Due N days ago`, using calendar-day arithmetic;
- the original due time when `dueHasTime` is true;
- Complete;
- a 44-point Actions menu with Later Today, Tomorrow, Pick Date, and Schedule Time.

Quick reschedule uses the same semantics as Tasks:

- Later Today preserves a still-future time today; otherwise it uses 6:00 PM, clamped to at least 15 minutes after `now`;
- Tomorrow preserves time/date-only semantics for dated tasks;
- Pick Date uses the selected date and explicit Include Time toggle.

Today owns a separate one-item reschedule Undo banner. It revalidates live Reminder access, exact profile membership, list identity, writability, recurrence, completion state, and expected post-write schedule before restoring the previous schedule. Completion Undo and reschedule Undo may coexist; each applies only to its own exact item and operation.

If scope changes, access disappears, or the provider item no longer matches, cached overdue content and pending Undo fail closed without a write.

### 3. Schedule Time from Today

Today owns one enum-backed direct-task-action presentation containing either the Pick Date form or a `TaskTimeBlockSession`; this avoids competing sibling task-action sheets. It remains mutually exclusive with the existing editor presentation. Direct scheduling is available from:

- an overdue row's actions menu;
- a task in Today's Schedule or Priority section through a trailing 44-point actions menu.

The action resolves the exact cached Reminder by origin, then calls `TaskTimeBlockSession.make(task:environment:)`. A nil session produces a neutral in-view error instead of silently falling back to another profile or destination.

The task-action sheet participates in `onPresentationChanged` so root deep links and Quick Entry wait until the host is idle. A successful save uses the session's existing `.localMutation` refresh and dismisses only after that refresh completes.

### 4. Schedule Time from Calendar Week

`WeekPlannerView` adds an optional `onScheduleTaskTime: (String) -> Void` callback. For a selected incomplete, modifiable reminder it shows **Schedule** beside Complete and Open. The accessibility-size chronological layout exposes the same selected-task action; no action is color- or gesture-only.

`CalendarViewModel` provides a fail-closed `scopedReminder(id:)` lookup that:

- re-resolves the current profile scope;
- requires Reminders access;
- requires the identifier in the model's current exact-scope cache;
- re-fetches the live Reminder by ID;
- verifies list membership, incompletion, and current visibility.

`CalendarHomeView` converts a valid lookup into `TaskTimeBlockSession`, presents one sheet, includes it in local-presentation/deep-link busy state, and surfaces a neutral error when the task or profile is no longer available.

## Data and Mutation Boundaries

- Provider task completion and due-date writes stay in their existing host view models.
- Time blocking writes one Calendar event and never updates or completes the Reminder.
- Every mutation re-resolves current scope and live provider state immediately before writing.
- Empty profile source sets never call provider fetch APIs that interpret empty as all.
- Profile switches clear cross-profile cached rows, mutation recovery, and pending Undo state.

## Error Handling

- Refresh failures for the same scope may retain only already-pruned, same-scope data.
- Scope changes and scope-resolution failures clear visible task data before any await.
- Quick reschedule failures retain the item and show retry guidance; they do not create Undo.
- Time-block session creation failures show “This task is no longer available in this profile. Refresh and try again.”
- Successful writes followed by refresh failure retain the existing “saved but could not refresh” pattern.

## Accessibility and UI

- Minimum interactive target is 44 by 44 points.
- Every swipe/context action has an explicit button or Menu alternative.
- Stable identifiers:
  - `tasks-needs-scheduling`
  - `task-schedule-today-<reminderID>`
  - `today-overdue`
  - `today-overdue-actions-<reminderID>`
  - `today-reschedule-undo`
  - `today-schedule-time-<reminderID>`
  - `week-task-schedule-<reminderID>`
- VoiceOver includes overdue age, due time when present, recurrence/read-only limitations, and action purpose.
- Accessibility Dynamic Type uses the existing chronological Week agenda and exposes Schedule there too.

## Testing

Unit tests cover:

- undated tasks publish only to Needs Scheduling;
- Today/Tomorrow date-only semantics from an undated task and exact Undo-to-nil;
- recurring/read-only/out-of-profile tasks never quick-write;
- overdue extraction, day-age calculation, stable ordering, and no duplicate agenda rows;
- Today quick reschedule and Undo authority/failure behavior;
- Calendar scoped Reminder lookup across access, profile change, provider deletion, and over-returning fakes;
- time-block presentation callbacks use exact Reminder IDs.

One focused UI test covers Needs Scheduling → Today and Undo, Today overdue rescue, and Week Schedule Time presentation using deterministic demo fixtures. Existing task triage/time-block tests remain unchanged.
