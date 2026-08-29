# Toolbar Action Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all textual modal toolbar actions use one accessible, bounded label style so Cancel and Save never spill outside native glass bubbles.

**Architecture:** A label-only SwiftUI design-system component supplies the shared typography and geometry while each screen retains ownership of its native `Button`, toolbar placement, action, role, state, and identifier. Rendered unit coverage binds the visual contract; UI coverage binds the component to Quick Entry and a two-sided editor.

**Tech Stack:** SwiftUI, XCTest, XCUITest, XcodeGen, iOS 17+

**Spec:** `docs/superpowers/specs/2026-08-29-toolbar-action-consistency-design.md`

## Global Constraints

- Preserve native SwiftUI toolbar and liquid-glass appearance.
- Use semantic `.callout` typography and cap only toolbar-label growth at `.xxxLarge`.
- Keep every toolbar action at least 44 by 44 points and on one line.
- Do not force equal widths or shrink ordinary form content.
- Preserve current actions, disabled states, roles, and accessibility identifiers.
- Leave `EditButton` and icon-based add actions system-managed.

---

### Task 1: Bind the shared label contract with a failing rendered test

**Files:**
- Modify: `PersonalCalendarTests/DesignSystem/CalendarThemeTests.swift`

**Interfaces:**
- Consumes: `CalendarTheme.minimumTapSize`
- Produces: the required `CalendarToolbarActionLabel(title: LocalizedStringKey, isProminent: Bool = false)` visual contract

- [x] **Step 1: Replace the Event-only rendered test with an app-wide test**

Render `Cancel`, `Back`, `Save`, `Saving…`, `Retry`, `Review`, `Done`, `Jump`, `Save Anyway`, `Cancel Delete`, and `Confirm Delete` at `.accessibility5`. Require each size to be at least 44 points high and wide, at most 64 points high, all heights equal within 0.5 points, and compact titles no wider than 96 points.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:PersonalCalendarTests/CalendarToolbarActionLabelTests -parallel-testing-enabled NO
```

Expected: compiler failure because `CalendarToolbarActionLabel` does not exist.

### Task 2: Create the shared component and migrate every textual modal toolbar

**Files:**
- Modify: `PersonalCalendar/DesignSystem/CalendarTheme.swift`
- Modify: `PersonalCalendar/Features/EventEditor/EventEditorView.swift`
- Modify: `PersonalCalendar/Features/QuickEntry/QuickEntrySheet.swift`
- Modify: `PersonalCalendar/Features/Tasks/TaskEditorView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutineEditorView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TaskTimeBlockView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Modify: `PersonalCalendar/Features/Today/TodayView.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Modify: `PersonalCalendar/Features/Settings/ProfileEditorView.swift`
- Modify: `PersonalCalendar/Features/Settings/CategorySettingsView.swift`
- Modify: `PersonalCalendar/Features/Settings/SettingsView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesView.swift`

**Interfaces:**
- Produces: `CalendarToolbarActionLabel`, a label-only `View`
- Preserves: every existing `Button` action, role, disabled state, and accessibility identifier

- [x] **Step 1: Implement the minimal shared label**

```swift
struct CalendarToolbarActionLabel: View {
    let title: LocalizedStringKey
    var isProminent = false

    var body: some View {
        Text(title)
            .font(.callout.weight(isProminent ? .semibold : .regular))
            .lineLimit(1)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
            .contentShape(Rectangle())
    }
}
```

- [x] **Step 2: Replace each shorthand textual toolbar label**

Use label-closure `Button` initializers with the shared label. Mark Save, Saving…, Retry, Review, Done, Jump, Save Anyway, and Confirm Delete prominent. Preserve the existing user-facing action copy, including Cancel Delete and Confirm Delete.

- [x] **Step 3: Run the rendered contract and verify GREEN**

Run the Task 1 command. Expected: all label-layout assertions pass.

### Task 3: Bind real toolbar integration at Accessibility XXXL

**Files:**
- Modify: `PersonalCalendarUITests/CompletionFlowUITests.swift`

**Interfaces:**
- Consumes: `quick-entry-cancel`, `quick-entry-back`, `quick-entry-save`, `event-editor-cancel`, `event-editor-save`
- Produces: end-to-end native toolbar geometry coverage

- [x] **Step 1: Add the UI regression before relying on the migration**

Launch with Accessibility XXXL. Open Quick Entry, verify Cancel, enter a deterministic event, reach confirmation, verify Back and Save, dismiss, then open the demo Event editor and verify Cancel and Save. For every native toolbar action assert its exact label, hittability, containment in the window and navigation bar, width at most 96, height at most 64, nonintersection, and sibling-height equality within 1 point. Do not assert a 44-point XCUI height because native navigation buttons expose a smaller accessibility frame.

- [x] **Step 2: Run the focused UI test**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:PersonalCalendarUITests/CompletionFlowUITests/testAccessibilityXXXLToolbarActionsRemainBoundedAcrossQuickEntryAndEventEditor -parallel-testing-enabled NO
```

Expected: pass only after all queried toolbars use the shared bounded label.

### Task 4: Verify, review, deliver, and reinstall

**Files:**
- Verify all files above

**Interfaces:**
- Produces: pushed commit and a freshly installed device build

- [x] **Step 1: Regenerate the project and run focused tests**

Run `xcodegen generate`, the rendered contract, the focused UI test, Swift parse checks, and `git diff --check`.

- [x] **Step 2: Run the complete scheme test suite**

Run the complete `PersonalCalendar` scheme with parallel testing disabled and require zero failures.

- [x] **Step 3: Request a read-only final review**

Review every cancellation/confirmation toolbar callsite, the rendered contract, UI coverage, localization behavior, and accessibility geometry. Fix only concrete findings with another RED/GREEN cycle.

- [ ] **Step 4: Commit, push, build, install, and launch**

Commit with `fix: keep toolbar actions inside glass bubbles`, push `feature/personal-calendar-ios`, build for the paired iPhone using team `C49CJS5VQ2`, install `My Calendar.app`, and launch `local.personalcalendar.iphone`.
