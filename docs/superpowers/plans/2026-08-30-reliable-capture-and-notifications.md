# Reliable Capture and Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Every production change follows a witnessed RED test and a focused GREEN rerun.

**Goal:** Preserve every accepted external capture in order, keep notifications as current as iOS permits, remove stale alerts when authority is unavailable, and reconcile all visible routine state after notification completion.

**Architecture:** A locked versioned App Group FIFO stores Siri/Shortcut captures, while a bounded main-actor FIFO stores app routes. A testable notification rescheduler owns authoritative input collection and fail-closed health state. A short `BGAppRefreshTask` invokes only that rescheduler. Notification routine completion invokes the existing agenda refresh registry and notification rescheduler after its repository commit.

**Tech Stack:** Swift 6, SwiftUI, Observation, App Intents, BackgroundTasks, UserNotifications, EventKit, XCTest, XCUITest, XcodeGen, iOS 17+

**Spec:** `docs/superpowers/specs/2026-08-30-reliable-capture-and-notifications-design.md`

## Global Constraints

- Accepted captures and routes must be FIFO and at-most-once; duplicates are distinct user actions.
- Both queues hold at most 16 items and reject the newest arrival when full.
- The durable queue holds at most 64 KiB encoded and prunes captures older than 24 hours.
- Never serialize captured text, event/task details, provider IDs, or profile names into filenames, Darwin notification payloads, background identifiers, health state, or diagnostics.
- Everything is never a valid captured Quick Entry creation profile.
- Notification input failure is fail-closed: the latest generation removes every app-owned pending alert, including snoozes, and persists a non-sensitive paused state.
- Background refresh is best-effort and must never be presented as an exact scheduling guarantee.
- A failed post-completion refresh must never repeat or roll back the successful routine completion write.
- Snooze never refreshes view models and never schedules for an already-completed routine.
- Operational notification health is device-local and excluded from backup schemas.

---

### Task 1: Replace the Quick Entry singleton handoff with a locked durable FIFO

**Files:**
- Modify: `PersonalCalendar/ProfileShared/AppRouteHandoffStore.swift`
- Modify: `PersonalCalendar/Intents/QuickEntryIntent.swift`
- Modify: `PersonalCalendarTests/Intents/QuickEntryIntentTests.swift`

**Interfaces:**
- Preserve: `AppRouteHandoffStore.write(_:)`, `consume()`, `fileURL`, `appGroup(fileManager:)`
- Add: `AppRouteHandoffStoreError.queueFull`
- Add: `QuickEntryIntentError.queueFull`
- Persist: version-2 FIFO envelope; decode version 1 as one queued item

- [ ] **Step 1: Add failing durable-queue tests**

Cover two sequential writes consumed in exact order, repeated identical captures as separate items, exact Unicode/profile preservation, non-head loss prevention under concurrent writers, version-1 migration, 24-hour pruning, malformed version-2 recovery, per-item/aggregate size rejection, and a full 16-item queue rejecting item 17 while retaining items 1–16.

- [ ] **Step 2: Run the focused class and verify RED**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:PersonalCalendarTests/QuickEntryIntentTests -parallel-testing-enabled NO
```

Expected: new FIFO, migration, concurrency, and queue-full assertions fail against the singleton file.

- [ ] **Step 3: Implement the version-2 queue**

Use a fixed sibling lock filename and POSIX `flock` around the complete read/prune/mutate/atomic-rewrite operation. Encode stable IDs, enqueue timestamps, and validated payloads with sorted JSON keys. On consume, remove only the oldest valid item and atomically retain the rest. Delete malformed/unsupported envelopes fail-closed. Continue idempotent legacy claim cleanup.

- [ ] **Step 4: Map queue overflow into App Intent failure and verify GREEN**

Map `queueFull` to concise user-facing retry copy without including capture text. Re-run the focused class, Swift parse both production files, and `git diff --check`.

---

### Task 2: Queue rapid URLs, widget, Live Activity, and notification routes

**Files:**
- Modify: `PersonalCalendar/Routing/AppRouteController.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `PersonalCalendar/Notifications/AppNotificationDelegate.swift`
- Modify: `PersonalCalendarTests/Routing/AppRouteTests.swift`
- Modify: `PersonalCalendarTests/Routing/AppRouteHostResolverTests.swift` only if host integration requires it

**Interfaces:**
- Preserve: observable `pending` head envelope and `consume(id:)`
- Change: `@discardableResult func submit(_ route: AppRoute) -> Bool`
- Bound: 16 pending envelopes, rejecting the newest on overflow

- [ ] **Step 1: Add failing controller and Root-processing tests**

Require exact FIFO order, duplicate routes with distinct envelopes, non-head consume as a no-op, overflow retention, and automatic exposure of item 2 after item 1 is consumed. Bind foreground URL overflow to a neutral visible error without replacing an existing root presentation.

- [ ] **Step 2: Run routing tests and verify RED**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:PersonalCalendarTests/AppRouteTests -only-testing:PersonalCalendarTests/AppRouteHostResolverTests -parallel-testing-enabled NO
```

Expected: submission replacement and overflow behavior fail.

- [ ] **Step 3: Implement the bounded main-actor FIFO**

Append accepted envelopes, expose `queue.first` as `pending`, and remove only a matching head ID. Preserve Root's route-before-handoff precedence. Root handles a `false` URL submission with generic overflow copy; the notification delegate safely ignores rejection without evicting earlier actions.

- [ ] **Step 4: Verify GREEN and route privacy**

Re-run both routing classes, parse changed production files, search route serialization for forbidden titles/notes/locations, and run `git diff --check`.

---

### Task 3: Extract an authoritative fail-closed notification rescheduler and persist health

**Files:**
- Add: `PersonalCalendar/Notifications/NotificationRescheduler.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/Notifications/NotificationCoordinator.swift`
- Modify: `PersonalCalendar/Settings/AppSettingsStore.swift`
- Modify: `PersonalCalendar/Features/Settings/NotificationSettingsView.swift`
- Add: `PersonalCalendarTests/Notifications/NotificationReschedulerTests.swift`
- Modify: `PersonalCalendarTests/Notifications/NotificationCoordinatorTests.swift`
- Modify: `PersonalCalendarTests/Settings/AppSettingsStoreTests.swift`

**Interfaces:**
- Add: testable `NotificationRescheduler.reschedule() async -> NotificationRescheduleOutcome`
- Add: device-local settings state `notificationsPausedForStaleInput` and `lastSuccessfulNotificationRefresh`
- Add: semantic coordinator operation for stale-input removal
- Preserve: `AppEnvironment.rescheduleNotifications` compatibility closure

- [ ] **Step 1: Add failing health and fail-closed tests**

Inject failures independently for authorization, scope, routine listing/completions, event fetch, reminder fetch, and profile fetch. For each latest-generation authoritative failure require all app-owned requests—including snoozes—to be removed, paused health to persist, and no partial replacement. Prove an older failed generation cannot clear a newer success. Prove a later complete success clears paused state and records its timestamp.

- [ ] **Step 2: Run focused notification/settings tests and verify RED**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:PersonalCalendarTests/NotificationReschedulerTests -only-testing:PersonalCalendarTests/NotificationCoordinatorTests -only-testing:PersonalCalendarTests/AppSettingsStoreTests -parallel-testing-enabled NO
```

Expected: missing rescheduler/health APIs and stale-alert retention fail.

- [ ] **Step 3: Extract input collection and fail closed**

Move the closure body from `AppEnvironment` into an injected main-actor rescheduler with generation authority. Return a typed outcome. Permission loss and any authoritative input failure call the semantic stale-input clear only if the generation is still latest. Successful scheduling clears health only after coordinator replacement succeeds.

- [ ] **Step 4: Surface honest Settings status**

Show paused/retry copy and last-success context with stable ID `notification-schedule-status`. Do not back up this operational state. Preserve existing class-alert settings and coordinator errors.

- [ ] **Step 5: Verify GREEN**

Run the focused command, parse changed production files, confirm no backup envelope contains the new health fields, and run `git diff --check`.

---

### Task 4: Add best-effort background notification renewal

**Files:**
- Add: `PersonalCalendar/Notifications/NotificationRenewalScheduler.swift`
- Modify: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/Resources/Info.plist`
- Add: `PersonalCalendarTests/Notifications/NotificationRenewalSchedulerTests.swift`
- Modify: `PersonalCalendarTests/App/RootLifecycleControllerTests.swift` only if lifecycle submission is composed there

**Interfaces:**
- Identifier: `local.personalcalendar.notification-renewal`
- Task type: `BGAppRefreshTask`
- Default renewal delay: 12 hours after successful scheduling
- Driver abstraction: register, submit one replacement request, attach expiration, report completion

- [ ] **Step 1: Add failing driver-policy tests**

Require launch registration with the exact identifier, one outstanding replacement request, a 12-hour earliest date, successor submission before renewal work, correct success/failure completion, cancellation on expiration, and no immediate retry loop.

- [ ] **Step 2: Run the focused class and verify RED**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:PersonalCalendarTests/NotificationRenewalSchedulerTests -parallel-testing-enabled NO
```

Expected: the background renewal types and launch integration do not exist.

- [ ] **Step 3: Implement the BackgroundTasks adapter and app composition**

Register before launch completes, submit only one replacement request, and invoke only `NotificationRescheduler`. The handler schedules its successor and then starts work. Its expiration handler cancels work and completes the task as failed. Foreground successful scheduling submits/replaces the next request.

- [ ] **Step 4: Add required app metadata and honest copy**

Add Background Fetch and `BGTaskSchedulerPermittedIdentifiers` to Info.plist. Notification Settings must say renewal is best-effort and iOS chooses execution time.

- [ ] **Step 5: Verify GREEN and target configuration**

Re-run the focused class, regenerate with `xcodegen generate`, inspect the generated app Info.plist settings, build the app target for the simulator, and run `git diff --check`.

---

### Task 5: Reconcile visible routine state after notification completion

**Files:**
- Modify: `PersonalCalendar/Notifications/AppNotificationActionHandler.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesViewModel.swift`
- Modify: `PersonalCalendarTests/Notifications/NotificationActionHandlerTests.swift`
- Modify: `PersonalCalendarTests/Features/FeatureViewModelTests.swift`

**Interfaces:**
- Add: awaited `onRoutineCompletionCommitted` hook with a default no-op
- Add: `RoutinesViewModel.refreshForExternalChange() async`
- Register/unregister: `RoutinesView` with `AgendaRefreshRegistry`

- [ ] **Step 1: Add failing handler and model tests**

Prove the hook runs exactly once and after the first successful completion write; is awaited before `handle` returns; and never runs for duplicate, invalid, out-of-scope, failed, or Snooze actions. Prove completed routines reject Snooze. Prove an externally committed completion appears after the model refresh without another write.

- [ ] **Step 2: Run focused classes and verify RED**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:PersonalCalendarTests/NotificationActionHandlerTests -only-testing:PersonalCalendarTests/FeatureViewModelTests -parallel-testing-enabled NO
```

Expected: missing hook/refresh registration and completed-routine Snooze acceptance fail.

- [ ] **Step 3: Implement post-commit reconciliation**

Replace ignored completion write errors with explicit success/failure handling. After the first successful commit, await `agendaRefreshRegistry.refreshAll()` followed by notification rescheduling. Register Routines with the registry using the same weak-lifetime pattern as Calendar, Today, and Tasks. Snooze checks completion before scheduling but does not invoke the hook.

- [ ] **Step 4: Verify GREEN and failure isolation**

Re-run the focused classes and prove an injected refresh failure does not produce a second completion write. Parse changed files and run `git diff --check`.

---

### Task 6: Integrate, review, verify, and deliver

**Files:**
- Verify all files above
- Modify: `README.md` and `docs/manual-qa/foundation-accessibility.md` only for user-facing queue/background/paused-state behavior

- [ ] **Step 1: Regenerate and run the combined focused gate**

Run `xcodegen generate`, then all new/changed test classes from Tasks 1–5 together with parallel testing disabled. Run the existing notification, route-host, Quick Entry, settings, profile, and refresh coordinator regression classes.

- [ ] **Step 2: Run UI smoke coverage**

Add or extend one deterministic flow that drains two queued Quick Entry captures in order and one Settings flow that exposes paused notification health. Do not depend on actual simulator background-task launch timing.

- [ ] **Step 3: Run broad verification**

Run Swift parse checks, `git diff --check`, the complete PersonalCalendar scheme with parallel testing disabled, a signing-disabled `PersonalCalendarWidgets` simulator build, and a signed generic iOS device build.

- [ ] **Step 4: Request independent final review**

Review concurrency, FIFO/at-most-once behavior, App Group locking, stale-generation authority, privacy, background-task lifecycle, Info.plist configuration, post-completion ordering, and tests for false positives/negatives. Fix concrete Critical or Important findings with another RED/GREEN cycle.

- [ ] **Step 5: Commit, push, install, and launch**

After all verification is green, commit the integrated work, push `feature/personal-calendar-ios`, build with team `C49CJS5VQ2`, install `My Calendar.app` on the paired iPhone, and launch `local.personalcalendar.iphone` when the device is available and unlocked.
