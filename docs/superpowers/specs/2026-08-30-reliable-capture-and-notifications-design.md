# Reliable Capture and Notifications Design

## Problem

The app currently has five related reliability gaps:

1. Siri and Shortcuts Quick Entry handoffs share one App Group file, so a later capture can overwrite an earlier unreviewed capture.
2. URL, widget, Live Activity, and notification routes share one in-memory pending slot, so rapid opens can overwrite each other.
3. Notification requests are renewed only while the app is launched, foregrounded, or mutated. A user who does not reopen the app can eventually exhaust the one-shot notification horizon.
4. When authoritative calendar, reminder, routine, or profile input cannot be refreshed, previously scheduled notifications remain pending and may become stale.
5. Completing a routine from a notification commits the repository change without refreshing the visible Calendar, Today, Tasks, and Routines surfaces.

## Approved design

### Durable Quick Entry queue

- Preserve `AppRouteHandoffStore.write(_:)` and `consume()` as the producer/consumer boundary.
- Replace the version-1 single payload with a version-2 FIFO envelope containing stable item IDs, enqueue timestamps, and validated Quick Entry payloads.
- Decode a version-1 payload as a one-item queue and upgrade it during the next write or consume operation.
- Protect the complete cross-process read, prune, mutate, and atomic rewrite sequence with an App Group lock file. Atomic file replacement alone does not prevent two processes from losing a concurrent read-modify-write update.
- Keep at most 16 captures and 64 KiB of serialized queue data. Prune captures older than 24 hours before capacity checks.
- Reject the newest capture with an explicit queue-full error when the queue is full. Never silently evict an older accepted capture.
- Preserve exact text and saved-profile identity. Continue rejecting blank text, Everything as a creation profile, malformed payloads, unsupported versions, and oversized content.
- Keep filenames, Darwin notifications, diagnostics, and error copy free of captured text and provider identifiers.

### In-memory route queue

- Replace `AppRouteController`'s single pending envelope with a main-actor FIFO queue while retaining `pending` as the first item.
- Preserve duplicates as separate user actions and consume only the matching head envelope.
- Bound the queue to 16 items. Reject the newest route when full and preserve all previously accepted routes.
- Keep Root routing precedence unchanged: drain app routes before durable Quick Entry handoffs. Ordering is guaranteed within each queue, not globally across the two independent transports.
- Foreground URL overflow receives a neutral visible error; background notification overflow fails closed without evicting another user action.

### Notification renewal and stale-input safety

- Keep one-shot local notifications and the current bounded scheduling horizon.
- Add one `BGAppRefreshTask` identifier, `local.personalcalendar.notification-renewal`, for short best-effort notification replenishment.
- Register the task during app launch, enable Background Fetch, add the permitted identifier to Info.plist, and maintain at most one submitted renewal request.
- Schedule renewal approximately 12 hours after a successful foreground/background notification refresh. The handler submits its successor and then runs only the notification rescheduler, not the complete view/timetable refresh pipeline.
- Treat background execution honestly: iOS chooses whether and when the task runs. `earliestBeginDate` is a lower bound, not a delivery guarantee, so the product must not promise an exact daily refresh while the app stays closed.
- On any latest-generation authoritative-input failure—scope, profile, routines/completions, calendar events, or reminders—remove every app-owned pending notification, including snoozes, and persist a non-sensitive paused health state.
- Show the paused state and a retry explanation in Notification Settings. Clear it only after a complete successful replacement and record the last successful refresh time.
- Keep notification health operational and device-local. Do not include it in manual backups and do not persist source titles, locations, raw IDs, or failure payloads.
- On task expiration, cancel in-flight renewal work and report failure to the system. Do not spin or immediately retry.

### Routine completion reconciliation

- Add an awaited post-commit hook to `AppNotificationActionHandler`.
- Invoke it exactly once after the first successful routine completion write, never for repeated, invalid, rejected, or failed actions.
- Compose the hook in `AppEnvironment` as an agenda refresh followed by authoritative notification rescheduling.
- Register `RoutinesView` with `AgendaRefreshRegistry`, matching Calendar, Today, and Tasks, and expose a model refresh entry point that performs no mutation.
- Do not run the entire app refresh pipeline for this action; permission, migration, timetable, and Live Activity work is unrelated.
- Snooze does not refresh view models because it does not mutate visible app content. It must, however, reject an already-completed routine so a replayed Snooze cannot recreate a stale alert after completion.

## Failure and concurrency behavior

- Accepted captures and routes are never silently overwritten.
- Queue operations preserve FIFO order and at-most-once consumption.
- A full queue rejects new work while retaining existing work.
- Older notification refresh generations cannot clear or replace a newer successful schedule.
- A successful routine completion is never retried because a later UI refresh fails.
- Cold-launch notification actions remain safe when no view is registered: persisted repository state is authoritative and each view's initial load observes it.

## Verification contract

- Quick Entry queue tests cover FIFO order, duplicate captures, exact text/profile preservation, version-1 migration, expiration, malformed data, aggregate and per-item limits, full-queue retention, and concurrent writers/consumers without loss or duplication.
- Route-controller tests cover FIFO order, repeated identical routes, non-head consumption, overflow retention, and sequential Root processing.
- Background-renewal tests cover registration, one outstanding request, successor submission, earliest-date policy, expiration, and success/failure completion.
- Notification-rescheduler tests inject every authoritative-input failure and prove all owned requests are removed only by the latest generation, paused health persists, and a later success recovers.
- Notification-action tests prove the refresh hook runs once and after commit, never runs for ignored/failed/Snooze actions, and completed routines reject Snooze.
- Routines tests prove an external repository completion appears after refresh without another write.
- Focused tests demonstrate RED before production changes and GREEN afterward. Final verification includes affected integration classes, the full scheme, widget build, signed device build, and physical-device install/launch when the paired phone is available.

## Product constraints

- Background renewal improves continuity but cannot guarantee it because iOS schedules background work opportunistically.
- The queues are intentionally small and local. They are reliability buffers, not a long-term inbox or synchronization service.
- No new network service, account, analytics stream, or user permission is introduced.
