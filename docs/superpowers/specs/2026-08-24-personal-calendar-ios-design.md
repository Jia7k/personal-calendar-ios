# Personal Calendar for iPhone — Design Specification

**Date:** 2026-08-24  
**Status:** Approved in conversation; awaiting review of this written specification

## 1. Product summary

Build a private, single-user iPhone calendar app inspired by TimeTree's calendar-first organization and approachable color system. The app combines Apple Calendar events, Apple Reminders tasks, and private routines in one calm daily view.

The product is original rather than a visual copy of TimeTree. It borrows useful interaction ideas—month-first navigation, quick creation, clear color coding, and friendly event presentation—while using its own layout, wording, visual identity, and assets.

The first release is local-first. It has no account, server, social features, or CloudKit database. Apple Calendar events and Apple Reminders tasks continue to use Apple's normal storage and synchronization. App-owned routines, completion history, categories, and settings remain on the iPhone unless the user manually exports a backup.

## 2. Goals

The first version must help one person:

- See events, tasks, and routines together without switching apps.
- Understand the month at a glance through clear color coding.
- Focus on the selected day through a useful agenda and priority list.
- Quickly capture an event, task, or routine using natural language.
- Build flexible habits without turning every habit into a calendar event.
- Receive a calm morning summary and only the reminders they choose.
- Keep control of their data without paying for a backend service.

Success means the user can open the app, understand the day in a few seconds, create common items with minimal typing, and trust that edits appear in the correct Apple or local store.

## 3. First-release scope

### Included

- Native iPhone app built with SwiftUI for iOS 17 or later.
- Four main tabs: Calendar, Today, Tasks, and Routines.
- Month calendar with a draggable day tray.
- Read and write access to Apple Calendar events.
- Read and write access to Apple Reminders tasks.
- Local routines, completion tracking, and streaks.
- App-defined color categories across the combined interface.
- Natural-language quick entry with an editable confirmation step.
- Morning summary, routine reminders, and user-selected item reminders.
- Manual export and import of app-owned data.
- Dark Mode, Dynamic Type, VoiceOver, and Reduce Motion support.

### Not included

- Shared calendars, invitations between app users, chat, comments, or profiles.
- Public calendars, albums, social activity feeds, or collaborative memos.
- A separate app account, backend, or CloudKit storage for app-owned data.
- Apple Watch, iPad-specific layouts, widgets, or Live Activities.
- File or photo attachments.
- Cloud-based or generative-AI text parsing.
- Advanced analytics, coaching, or competitive habit features.

These items may be considered after the first version works reliably.

### Delivery sequence

The complete first-release scope remains one product, but its implementation plan must use two verifiable milestones:

1. **Foundation milestone:** app shell and visual system; service interfaces; permission flows; Calendar and Today read views; basic event and task creation; core routines and completion tracking; accessibility foundation.
2. **Completion milestone:** full edit and delete flows including recurrence; smart quick entry; app categories; notifications; backup and restore; synchronization edge cases; complete accessibility and real-device verification.

The second milestone builds on the tested service boundaries from the first. No feature outside this specification is added between them.

## 4. Experience and navigation

### 4.1 Calendar tab

Calendar is the default tab and the product's home base.

- The upper area shows a full month grid.
- Each date can show compact colored items or indicators for events, due tasks, and routines.
- All-day events use a stronger filled treatment. Timed items use a lighter treatment so the two are easy to distinguish.
- Tapping a date selects it and updates the tray below.
- A Today control returns to the current date.
- Month navigation supports horizontal movement and an accessible previous/next control.

The lower day tray has two positions:

1. **Resting:** shows the selected date, the next scheduled event, the highest-priority due task, and the next incomplete routine.
2. **Expanded:** the month compresses to a week strip while the tray reveals the selected day's full agenda. It shows all-day events first; timed events and due tasks in time order alongside routines at their window anchor; then a priority section for tasks without a time and Anytime routines.

The tray must also work without dragging: a visible control lets VoiceOver and keyboard users expand or collapse it.

### 4.2 Today tab

Today gives a full-screen chronological view of the current day. It merges:

- All-day and timed Apple Calendar events.
- Apple Reminders tasks due today or overdue.
- Routines scheduled for today.

All-day items appear first. Timed items follow chronologically. Tasks without a time appear in a dedicated priority section. Flexible routines appear in their chosen time window and can be checked off in place.

### 4.3 Tasks tab

Tasks is a focused view of Apple Reminders.

- Show Today, Upcoming, and Completed groupings.
- Create, edit, complete, and delete reminders.
- Support title, notes, due date and time, recurrence, priority, list, and alert where the selected reminder list permits them.
- Treat category as app-defined metadata stored locally rather than as a native Apple Reminders field.
- Changes save to Apple Reminders rather than to a copied app database.

For a recurring Apple Reminder, the app displays only the current incomplete occurrence supplied by EventKit. Completing it may cause Apple Reminders to provide the next occurrence. The app does not invent or preview future occurrences that EventKit has not supplied.

### 4.4 Routines tab

Routines manages private, app-owned habits.

- Create, edit, pause, archive, and delete a routine.
- Choose scheduled weekdays or a daily schedule.
- Choose a broad time window: morning, afternoon, evening, or anytime.
- Choose an optional local reminder time.
- Choose a color category.
- Mark scheduled occurrences complete or undo completion.
- Show the current streak and a simple recent-completion history.

Routines are flexible intentions, not busy blocks on Apple Calendar. Fixed recurring commitments remain recurring Apple Calendar events.

For agenda ordering only, Morning, Afternoon, and Evening use local anchors of 9:00, 13:00, and 18:00. Anytime routines have no time anchor. These anchors do not create alerts; a routine sends an alert only when the user chooses a separate reminder time.

### 4.5 Universal quick entry

A prominent add button is available from every tab. It opens a single text field with examples such as:

- `Dentist Friday at 3pm`
- `Submit report tomorrow`
- `Read every night`

Parsing happens on the device. Before anything is saved, the app shows an editable preview containing:

- Item type: Event, Task, or Routine.
- Title.
- Date and time or routine time window.
- Repeat rule when detected.
- Category.
- Reminder choice.
- Destination Apple calendar or reminders list when relevant.

The user can correct every field or switch the item type. Nothing is saved until the user confirms.

Creation destinations and edit or delete actions are limited to EventKit calendars and reminder lists that allow modification. Read-only, subscribed, or otherwise immutable items remain viewable. Unavailable actions are disabled with a short explanation.

Default classification rules are deterministic:

- Repeating habit language such as “every night” defaults to Routine.
- Action or reminder language without a scheduled duration defaults to Task.
- A scheduled appointment or activity with a date or start time defaults to Event.
- When meaning is uncertain, the app defaults to Task because that does not reserve calendar time, and it makes the type selector prominent in the preview.

### 4.6 Settings

Settings opens from a toolbar rather than occupying a fifth tab. It provides one place to:

- Choose which Apple calendars and reminder lists appear in the combined views.
- Choose the default Apple calendar and reminder list used by quick entry.
- Create, rename, recolor, and remove app categories.
- Set the morning-summary time and notification preferences.
- Review permission status and open the app's system Settings page.
- Export or restore an app-owned backup.

## 5. Visual direction

The interface combines TimeTree's friendly calendar clarity with a calmer personal-dashboard feel.

- Use a warm, light base with restrained surfaces and generous spacing.
- Give categories distinct, accessible colors that remain understandable in Dark Mode.
- Never use color as the only signal; include item icons, labels, or shape differences.
- Keep the month grid information-dense but legible.
- Use native typography and controls where they improve familiarity and accessibility.
- Use subtle motion for tray movement and state changes, with reduced or removed motion when Reduce Motion is enabled.
- Keep the universal add action visually prominent without covering content.

The app will use an original name, icon, illustrations, and component styling before public release.

## 6. Data ownership and storage

The app does not duplicate complete Apple Calendar events or Apple Reminders tasks.

| Information | Source of truth | Synchronization |
| --- | --- | --- |
| Calendar events and event alerts | Apple Calendar through EventKit | Apple's configured calendar accounts |
| Tasks and task alerts | Apple Reminders through EventKit | Apple's configured reminder accounts |
| Routines and archived state | Local SwiftData store | This iPhone only |
| Routine completion history and streak inputs | Local SwiftData store | This iPhone only |
| App color categories and links to Apple item identifiers | Local SwiftData store | This iPhone only |
| Preferences such as summary time and default destinations | Local app settings | This iPhone only |

Local category links store only the Apple item identifier and app metadata, not a second copy of event or task content. If an Apple item is removed or a full account synchronization changes its identifier, the unused link is safely ignored and later cleaned up. The category assignment may then need to be reapplied by the user; the app does not guess and attach it to a different item.

App categories control presentation inside this app. They do not change the native color of an Apple calendar or reminders list.

The manual backup contains only app-owned data: routines, routine completions, categories, category links, and settings. It does not copy Calendar or Reminders content because Apple remains the source of truth for those items. The backup is a versioned file so a future app version can migrate older backups safely.

## 7. Technical structure

The app uses small components with one responsibility each:

- **Calendar service:** requests Calendar access and reads, creates, edits, or removes events through EventKit.
- **Reminders service:** requests Reminders access and reads, creates, edits, completes, or removes tasks through EventKit.
- **Routine store:** owns routines and completion records in SwiftData.
- **Category store:** owns color categories and links them to external or local items.
- **Agenda composer:** converts items from all three sources into one display model, sorts them, and groups them for Calendar and Today.
- **Quick-entry parser:** extracts type, title, date, time, and repetition from text without saving anything.
- **Save router:** sends a confirmed preview to Calendar, Reminders, or the routine store.
- **Notification coordinator:** schedules the app's morning summary and routine notifications, and keeps them consistent when data changes.
- **Backup service:** exports and validates versioned app-owned backup files and imports them transactionally.
- **Permission coordinator:** explains and requests each permission only when it becomes useful.

Screens depend on these service interfaces rather than directly controlling EventKit or SwiftData. This lets automated tests use safe in-memory replacements.

## 8. Data flow and refresh behavior

On launch or return to the foreground:

1. Read the current authorization state for Calendar, Reminders, and notifications.
2. Fetch the visible date range from each available source.
3. Load scheduled routines and their completion states.
4. Merge the results into one agenda representation.
5. Render each item with its source, category, status, and available actions.

The app listens for EventKit store-change notifications. When Apple Calendar or Reminders changes, the visible date range refreshes rather than relying on stale cached content.

For quick entry:

1. Parse the text locally.
2. Present an editable preview.
3. Validate required fields and destination access.
4. Save through the correct source only after confirmation.
5. Refresh the affected view and show a brief success state.

## 9. Permissions, errors, and data safety

### Permissions

The first-run experience briefly explains the benefit of each permission. Calendar, Reminders, and notifications are requested separately and in context rather than in one block.

- If Calendar is denied, Calendar events are hidden but tasks and routines still work.
- If Reminders is denied, Apple tasks are hidden but events and routines still work.
- If notifications are denied, app-owned morning summaries and routine alerts are disabled; the planning features still work.
- A clear settings card explains what is unavailable and links to the app's system Settings page.

Permission denial never creates a blank or broken home screen.

### Save failures

- Keep the user's draft and edits in memory until a save succeeds or the user discards them.
- Explain the failure in plain language and offer Retry.
- Never show success before the destination store confirms the save.
- If an external item disappeared while it was being edited, refresh the view and explain that it is no longer available.

### Repeating items

When editing or deleting a repeating Apple Calendar event, ask whether the change applies to only this occurrence or this and future occurrences. Use Apple's supported recurrence behavior and do not silently alter an entire series.

### Backup import

Validate the backup version and contents before changing local data. Restore replaces all app-owned local data rather than merging it. It is all-or-nothing: if validation or saving fails, keep the existing local data unchanged. Before replacing local data, explain what will change and require confirmation.

## 10. Notifications

- The morning summary is an optional local notification at a user-selected time.
- The app schedules the next summary while it is running, after a foreground refresh or a relevant in-app change. Its content is a best-effort snapshot at scheduling time and may not include external Calendar or Reminders changes made afterward.
- The summary gives the scheduled snapshot's event, due-task, and routine counts and highlights its next timed item without exposing unnecessary detail on the lock screen.
- Calendar event alerts are stored with Apple Calendar events.
- Reminder alerts are stored with Apple Reminders tasks where supported.
- Routine alerts are local app notifications.
- Changing or completing a routine updates its pending notification.
- The app schedules routine alerts for the next 14 days, subject to a conservative maximum of 48 pending routine notifications. It schedules the nearest occurrences first and refills them on launch, foreground refresh, and routine changes.
- If requested routine alerts exceed that budget, Settings explains that later occurrences will be scheduled during a future refresh.
- The app avoids duplicate notifications for the same item.

## 11. Privacy

- No sign-in is required.
- No app-owned calendar data is sent to a server.
- Natural-language parsing runs on the device.
- The app requests only the access needed for the features the user chooses.
- The backup leaves the app only when the user deliberately exports it through the system share sheet.

## 12. Accessibility and quality requirements

- All controls have meaningful VoiceOver names, values, and hints.
- Text supports Dynamic Type without clipping important information.
- Touch targets are at least 44 by 44 points.
- Category contrast meets accessibility expectations in Light and Dark Mode.
- Color is paired with text, icons, or shape.
- The day tray has non-gesture alternatives.
- Reduce Motion replaces large tray animations with simple state changes.
- Date and time presentation respects the device locale, calendar, 12/24-hour preference, and time zone.

## 13. Testing strategy

### Automated unit tests

- Quick-entry parsing for common, ambiguous, repeating, and invalid phrases.
- Date calculations across month boundaries, daylight-saving changes, and time zones.
- Routine scheduling, completion, undo, pause, archive, and streak calculations.
- Agenda merging, ordering, overdue-task placement, and category presentation.
- Save routing to the correct destination.
- Backup export, version validation, round-trip import, and failed-import rollback.
- Permission-state behavior and clear degraded modes.

### Integration tests

- Calendar and Reminders services through test doubles for all routine test runs.
- SwiftData using an in-memory store.
- Notification scheduling and cancellation through a replaceable interface.
- Refresh behavior when a simulated external store change occurs.

### UI and real-device checks

- First-run permission paths: allow, deny, and later enable in Settings.
- Create, edit, and delete single and repeating events.
- Create, complete, edit, and delete reminders.
- Create and complete routines and verify streak updates.
- Quick entry from every tab, including correction before save and retry after failure.
- Tray drag, tap alternative, collapsed state, and expanded state.
- Light Mode, Dark Mode, large accessibility text, VoiceOver, and Reduce Motion.
- Manual backup export and successful restore on a clean local store.

## 14. Acceptance criteria

The first version is ready when:

1. A user can grant either, both, or neither Apple data permission and still reach a useful, stable app state.
2. Calendar accurately combines accessible items for its visible date range, and Today accurately combines accessible items for the current local day.
3. Creating or editing an Apple event or task changes the corresponding Apple app without creating a duplicate local record.
4. A routine can be scheduled, reminded, completed, undone, and reflected correctly in its streak.
5. Common natural-language entries produce an editable preview and never save without confirmation.
6. Failed saves preserve the draft and provide a retry path.
7. Repeating event changes clearly distinguish one occurrence from future occurrences.
8. Exported app-owned data can be restored without touching Apple Calendar or Reminders data.
9. Core flows remain usable with VoiceOver, large text, Dark Mode, and Reduce Motion.
10. Automated tests pass and the permission, synchronization, notification, recurrence, and backup flows have been verified on a real iPhone.
