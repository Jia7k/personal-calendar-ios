# Daily Usability Full Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox syntax for tracking. The root runs all Simulator builds and tests; workers never run xcodebuild concurrently.

**Goal:** Deliver all seven usability improvements accepted by the user: simpler forms, faster Quick Entry, clearer calendar controls, readable class labels, actionable event previews, local draft recovery, and a configurable opening screen.

**Architecture:** Extend the existing native SwiftUI flows. Quick Entry is the app-wide new-item capture and draft-resume surface for events, tasks, and routines. All provider writes continue through existing save/validation/profile gates; display shortening and local drafts never mutate provider data. Each independent feature area has a single file owner.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, EventKit, XCTest/XCUITest; existing dependencies only.

**Spec:** The seven numbered recommendations immediately preceding the user's “make it all” request are the approved design. This plan makes the implementation and safety details explicit. Existing-item editing keeps its explicit Save/Discard semantics; draft recovery covers the universal Quick Entry capture, including its corrected review preview, not automatic background writes to existing events/tasks.

## Global Constraints

- Preserve the current light Harbor/Linen theme, vertical-only Week scrolling, uniform Cancel/Save controls, Dynamic Type, and minimum 44-point touch targets.
- Work inline on codex/daily-qol-polish. Preserve the previous batch's uncommitted changes. No commit, push, merge, phone install, or external provider mutation during testing.
- No dependencies or network services. Native iOS 17+ APIs only; validate project membership for newly created Swift files through project.yml/XcodeGen if necessary, coordinated by root.
- Existing calendar/reminder titles, alarms, recurrence, destinations, categories, permission checks, and profile boundaries must be preserved unless explicitly changed by the user.
- Quick Entry drafts are local, profile-scoped, bounded, corruption-tolerant, and never saved automatically to Calendar/Reminders/routines. User can Resume or Discard; successful save clears the matching draft. Explicit discard clears it. A failed write keeps it. A queued shortcut must not be replaced by a recovered draft.
- New UI must have stable accessibility identifiers and usable keyboard/screen-reader behavior; critical actions retain visible buttons.
- Every behavior change gets focused RED/GREEN regression coverage; root owns Simulator execution. Workers send selectors and readiness, await RED evidence, then implement. Minimal API shells may be added solely to make new behavior tests compile and fail.

## Task 1: Shorter Event and Task Forms

**Files:** EventEditor/EventEditorView.swift, Tasks/TaskEditorView.swift, a focused shared summary helper if useful, matching unit tests, and a new PersonalCalendarUITests/UsabilityFormsUITests.swift.

**Interfaces:** Consume existing editor view models unchanged wherever possible. Produce an accessible “More options” disclosure with a concise current-options summary. This task owns only these forms and its new tests; do not edit FoundationFlowUITests or other shared UI suites.

**Acceptance:**
- Event essentials: title, all-day, Starts/Ends, location. Task essentials: title and optional due-date controls. Optional notes, URL, destination, category, alerts, repeat and priority (tasks) go into More options.
- Summarize enabled alarms/repeat/current destination/category/priority/nonempty notes without requiring expansion. Unsupported provider settings remain recognizable and unchanged.
- Delete/duplicate, error/retry messages, save confirmation and unavailable/read-only explanations remain discoverable, not hidden by a collapsed disclosure.
- Existing-item summaries reflect current provider state after load. An error concerning a hidden field should reveal that field or clearly explain how to reach it.
- Opening/collapsing options never changes model data. Keep validation, title-only task creation, duration-preservation and custom alert draft state intact.

- [x] Add UI regressions: a new event opens essentials without optional editors; More options reveals alert/repeat fields; an edited recurring event exposes a summary and retains settings after unrelated title save; task due date remains optional. Add summary unit tests only for real derived behavior.
- [x] Send root exact selectors for RED. Illustrative behavioral assertion:
```swift
XCTAssertFalse(app.descendants(matching: .any)["event-editor-alarm-intent"].exists)
app.buttons["event-editor-more-options"].tap()
XCTAssertTrue(app.descendants(matching: .any)["event-editor-alarm-intent"].exists)
```
- [x] Implement the disclosure and meaningful summary using existing sections, preserving identifiers inside them.
- [x] Send GREEN selectors, changed files and integration notes (existing UI tests that now need to expand More options).
- [x] Self-review and write report; root performs independent task review and final verification. Leave changes uncommitted.

## Task 2: Fast Quick Entry and Local Draft Recovery

**Files:** QuickEntry/QuickEntrySheet.swift and QuickEntryViewModel.swift; new QuickEntry/QuickEntryDraftStore.swift and domain snapshot if needed; QuickEntryPreview.swift for Codable support only if appropriate; new unit/UI tests. AppEnvironment.swift and RootTabView.swift integration belongs to root: send exact initializer changes to root instead of editing those two files.

**Interfaces:** Extend QuickEntryViewModel initializer with optional draftStore while preserving existing callers. Use the existing creationProfile.profileID for storage scope. Produce explicit model methods for resume/discard/local checkpoint and a clean Add Another transition, plus visible draft availability. Store initialization must support isolated tests; root injects production storage and a fresh ephemeral test store.

**Acceptance:**
- In-app blank capture autofocuses the input; keyboard Continue invokes the same Review action, only for nonblank input, and visible Review remains. Focus must not steal from a screen-reader announcement or recovery choice.
- After a successful save, Add Another resets text/preview/errors/save identity for a fresh capture in the same captured profile. Done remains. No duplicate provider writes or accidental replay of a shortcut capture.
- Save a bounded local checkpoint of raw text, fully corrected preview, parse-text marker, explicit destination choices and intended review/entry phase. Persist changes and background transitions; do not persist saving/committed transient states as replayable writes.
- On new in-app capture, offer Resume draft / Discard draft, never silently overwrite typed content or a supplied shortcut capture. Resume does not parse relative dates again if an already-corrected preview exists; it revalidates live destinations/category/profile and exposes stale-date warnings. No cross-profile content leakage.
- Explicit discard or successful save clears the matching draft; failed save retains it. Keep a draft on leaving via an explicit Save Draft choice (local only), and across app termination. Empty untouched forms create no draft. Corrupt/oversized data is ignored safely.
- Add Another must refresh current destination options through existing mechanisms and respect profile invalidation. Do not create a generic cloud sync or autosave framework.

- [x] Add unit regressions through the real model: store round trip retains corrected fields; other profile cannot see it; corruption is harmless; Resume makes zero provider calls; explicit discard/save clears; failed save retains; Add Another saves two distinct items exactly once; input/shortcut does not get overwritten.
- [x] Add UI coverage in new UsabilityCaptureUITests.swift: keyboard present on +, Continue opens Review, Add Another accepts a second task, Save Draft/Resume preserves title/date corrections, explicit discard removes prompt.
- [x] Send root RED selectors (minimal new API shells allowed only to compile tests).
- [x] Implement focused local store and state transitions. Example model boundary:
```swift
func startAnotherEntry() // only committed -> clean entry
func resumeDraft()      // explicit recovery -> editable entry/confirmation, never save
func discardDraft()     // remove the profile's local checkpoint
```
- [x] Send integration patch instructions for AppEnvironment/RootTabView, GREEN selectors and report. No commits/builds.

## Task 3: Calendar Clarity, Class Labels, and Event Actions

**Files:** Calendar/CalendarHomeView.swift, Profiles/ProfileSelectorToolbar.swift, Calendar/WeekPlannerView.swift; focused new helpers for class labels and event actions; new unit tests and PersonalCalendarUITests/UsabilityCalendarUITests.swift. Do not edit RootTabView/Settings/AppSettingsStore.

**Interfaces:** Reuse existing Jump to Date presentation and profile selection menu. Reuse EventLocationMapsOpener where suitable. New pure helpers should separate display title parsing and safe link extraction from native open/copy effects.

**Acceptance:**
- Replace the separate icon-only profile affordance with a labeled active profile dropdown, e.g. Personal plus chevron. Make the date range heading a clearly accessible Jump to Date button. Remove redundant calendar-clock button. Preserve Search, Settings, Today and previous/next navigation; fit small phones and XXXL text.
- Shorten clearly recognized academic class titles in Week blocks only: preserve the full course code (e.g. INF 2001) plus Lab/Lecture/Tutorial/Seminar and section if space permits. Full event title remains in details and accessibility; generic events and unrecognized patterns keep existing titles. Never edit source titles or apply shortening to unrelated names.
- Selected event previews provide Directions for a usable physical location; Copy Location for any nonempty location; Join Call for a safely parsed recognized meeting URL from explicit event URL/location/notes. Handle online-only placeholders without a misleading map action. Only allowed http/https meeting URLs open; no arbitrary custom schemes or automatic opening. If several valid meeting URLs exist, choose deterministically and display the destination accessibly.
- Actions run only on taps, use native openURL/Maps/pasteboard, display recovery feedback if opening fails. Original Open Event remains. No change to permissions or provider data.

- [x] Add pure-helper tests with literal school/generic titles, malformed/empty/unsafe URLs, recognized meeting hosts and online-vs-physical locations. Add native UI tests for profile/date taps and conditional actions/retained full title using controlled demo fixtures.
- [x] Send root RED selectors. Example required title expectation:
```swift
XCTAssertEqual(WeekEventDisplayTitle.compact("INF 2001 - Introduction to Software Engineering (P7 Laboratory)"), "INF 2001\nP7 Lab")
XCTAssertEqual(WeekEventDisplayTitle.compact("Driving"), "Driving")
```
- [x] Implement the minimal helpers and view wiring after RED. Keep action effects injectable/testable; existing openURL environment is preferred over global URL opening.
- [x] Send GREEN selectors and report for independent task review. No commits/builds.

## Task 4: Opening Screen, Integration and Verification (root)

**Files:** Settings/AppSettingsStore.swift; Features/Settings/SettingsView.swift; App/RootTabView.swift; App/AppEnvironment.swift for capture integration; settings/root navigation tests; existing UI suites adjusted only where intentional More options disclosure changes paths; README.md.

**Interfaces:** Introduce an opening-screen preference with Calendar, Today, Tasks, Routines and Last Used. RootTab must be safely serializable or mapped through a focused preference type. Default stays Calendar; invalid stored values fall back to Calendar. Last-used persists actual selected tab. Explicit routes and onboarding take precedence over startup preference.

- [x] Add settings round-trip/fallback and root initial-selection/routing tests. UI test changes setting, relaunches with persisted isolated settings, confirms chosen tab; last-used round trip and deep-link precedence unit tests.
- [x] Run RED then implement minimal settings and root initialization. Do not reset the selected tab when returning from sheets or foreground.
- [x] Wire Task2's draftStore and hooks into app environment/root creation without changing shortcut queue ordering, captured profile validation or save outcomes.
- [x] Adapt existing tests to expand More options where they intentionally use advanced controls; do not weaken their provider preservation/save/delete assertions. Tests must use realistic gestures/selectors and deterministic fixtures.
- [x] Run full unit suite, all new usability UI tests, existing Quick Entry/recurrence/retry/profile routing tests, and XXXL toolbar/vertical Week checks. Root uses the original iPhone 17 Pro Simulator and a dedicated 375-point iPhone SE Simulator 1E3BE65E-EB0D-49F0-9A56-2D6BB1B27D18, DerivedData /tmp/personal-calendar-qol-baseline, ad-hoc Simulator signing (required for the Shortcut App Group), and parallel-testing-enabled NO.
- [x] Capture screenshots for compact forms/header and inspect readable controls, safe areas and keyboard access. Independent task and final reviews must resolve important findings.
- [x] Update README with actual shipped behavior. Report exact test results and limitations, plus local-only/no phone install status. Do not imply all possible app paths were tested.

## Final Verification — 2026-09-10

All seven improvements are implemented inline and independently reviewed. Existing uncommitted work is preserved. No commit, push, merge, physical-device installation, or real Calendar/Reminders mutation was performed.

- Full unit suite: **1,135 passed**, including the final source state, in `/tmp/personal-calendar-usability-header-stable.log`.
- **40 distinct targeted UI paths passed across focused runs**: 18 new usability paths, 2 Shortcut queue/routing paths, 5 Week regressions, and 15 existing editor/completion/foundation regressions. Earlier failed attempts were diagnosed and rerun; this is not a claim that every UI test in the repository was run in one passing suite.
- Final affected accessibility run: **4/4 passed**, exit 0, in `/tmp/personal-calendar-usability-accessibility-final.log`. Covers header navigation, maximum-text physical event actions, full narrow-phone Week header, and School inline event details.
- Visual inspection covered compact event/task forms, narrow one- and two-hour class blocks, long popup address/notes, and full maximum-text header/actions. Touch targets, vertical-only Week behavior, local draft ownership, and provider-preserving editor paths remain covered.
- Follow-up fixes caught during testing: independent Resume/Discard buttons, width-aware class labels, scrollable popup action content, full-row event hit testing, maximum-text header height, and stable eager layout for the seven accessibility day rows.
- Final independent review: no remaining actionable findings. `git diff --check` is clean.

Real-device VoiceOver interaction, Maps/meeting-service handoff and phone installation remain manual checks; Simulator tests do not claim those are complete. Quick Entry draft recovery is device-local, exact-profile-scoped, and limited to new captures—not unsaved edits to existing provider items.

## Pre-push regression follow-up — 2026-09-11

The full-suite check exposed an accessibility identifier regression in Month view. The eager seven-row layout correctly displayed and scrolled to the selected dates, but its wrapper identifier propagated to every date button. An explicit accessibility container now preserves the wrapper and each individual date button without changing layout or weakening tests.

- Existing maximum-text date-selection/Quick Entry test reproduced **three failing assertions**, then passed unchanged after the fix: **1 test, 0 failures**, `/tmp/personal-calendar-calendar-green-20260911.log`.
- Independent review accepted the bounded fix; the stable eager layout is retained.
- The full run passed 1,135 unit tests and 103 of 107 UI paths, exposing three stale navigation assumptions in tests and a Week scrolling freeze. The tests now open the duplicate editor's More options and scroll to read-only controls/notification health before inspecting them, preserving all safety and save-count assertions. All three corrected paths passed in `/tmp/personal-calendar-prepush-repairs-20260911.log`.
- A captured 100%-CPU stack trace isolated the Week freeze to lazy height estimation across its five variable-height sections. The outer stack now lays those five sections out eagerly; inner rows and the single vertical ScrollView remain unchanged. The unchanged late-event popup regression passed **three consecutive runs**, exit 0, in `/tmp/personal-calendar-prepush-week-isolated-20260911.log`.
- After another app interrupted the shared Simulator, verification moved to dedicated iPhone 17 Pro Simulator `141C1FA0-4339-4D72-B132-3CFEB9B18F54` (iOS 26.5). Final full unit/UI verification uses isolated workers before the user-authorized commit and push.
- The next full run passed all 1,135 unit tests and 105 of 107 UI tests. Its two remaining failures were test-harness issues, confirmed from the activity logs and accessibility snapshots: the first-use iOS Slide to Type tutorial obscured the keyboard's Continue key before Add Another was reached, and a routine Retry tap targeted a partly visible row after a fling. The capture helper now dismisses only that system tutorial and checks the real key; the routine helper uses settled drags and requires a fully visible, hittable Retry button. All original save, retry, retained-edit and duplicate-count assertions remain in place.
- All five capture paths passed with the tutorial handling in `/tmp/personal-calendar-prepush-ui-harness-green-20260911.log`. That intermediate run rejected an overly large test-only Retry visibility margin; a screenshot confirmed the row was fully visible at the form's scroll limit. The corrected margin retains bottom-edge protection without excluding that valid position. No production capture or routine changes were needed. Final independent review found no actionable issues; the complete-suite result and remaining targeted repairs are recorded below.

### Final pre-push verification

- The last full run exercised **1,242 tests**, with **1,135 unit tests and 105 UI tests passing**, no skips, and two UI-test failures: `/tmp/personal-calendar-prepush-verified-20260911.log`. All earlier calendar, capture and routine regressions passed in that run.
- The custom-alert test tapped Unit while it extended below the screen, opening the preset menu instead. It now reveals Unit and Timing with the existing settled-scroll helper before tapping. Its original chosen-unit/timing and saved-provider assertions passed **three consecutive repetitions** in `/tmp/personal-calendar-prepush-last-paths-20260911.log`.
- The event/task retry test's triple tap failed to select the original title, inserting `Coffee updatedCoffee`. Its single-use text helper now focuses, places the caret at the end, clears the existing characters, and verifies both clearing and the exact replacement. An intermediate Select All attempt was rejected because the Simulator did not open that menu. The final helper and unchanged event/task retry assertions passed **three consecutive repetitions**, exit 0, in `/tmp/personal-calendar-prepush-retry-green-20260911.log`.
- Final coverage is **1,135 unit tests and all 107 distinct UI tests passing across full and focused runs**, not one entirely green full-suite invocation. The final test-only changes do not alter production behavior, remove assertions, or skip tests. Independent review is clear and `git diff --check` passes.
- Real-device VoiceOver, Maps/meeting-service handoff, and phone installation remain manual checks. The user-authorized commit and push contain source, tests and documentation only; Simulator results and existing ignored worktree archives stay outside Git.
