# Week Event Popup Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Week Planner event information and long editor titles readable with an anchored regular-width popover and a safe compact-width sheet.

**Architecture:** Keep the existing selection and occurrence-authority model. Use a bounded top-anchored popover at regular width, adapt that presentation to a medium/large sheet at compact width, retain progressive disclosure in narrow timeline cells, and keep the multiline Event editor title. Add deterministic dense-week fixtures so UI automation exercises the real popup and editor.

**Tech Stack:** SwiftUI, XCTest/XCUITest, XcodeGen, iOS 17+

**Spec:** `docs/superpowers/specs/2026-08-29-week-event-popup-polish-design.md`

## Global Constraints

- Preserve vertical-only Week Planner scrolling and seven fixed day columns.
- Preserve semantic Dynamic Type fonts and 44-point minimum interactive targets.
- Preserve exact occurrence routing, profile isolation, and existing accessibility-size inline details.
- Do not add dependencies or fixed point font sizes.

---

### Task 1: Bind the long-content behavior with a failing UI test

**Files:**
- Modify: `PersonalCalendar/App/DemoEnvironment.swift`
- Modify: `PersonalCalendarUITests/WeekPlannerFlowUITests.swift`

**Interfaces:**
- Consumes: existing `-demo-week-overlaps` fixture and Week Planner accessibility identifiers.
- Produces: a long `demo-week-overlap-a` fixture and a UI regression covering popup containment plus editor wrapping.

- [x] **Step 1: Extend the deterministic fixture**

Give `demo-week-overlap-a` a long course/flight-style title, location, and notes while preserving its stable ID and collision interval.

- [x] **Step 2: Write the failing UI regression**

Add a test that chooses the long event from the collision popup and independently asserts the full title, notes, popup containment, hittable Close/Open controls, close/reopen behavior, and a multiline editor-title frame after Open Event.

- [x] **Step 3: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/WeekPlannerFlowUITests/testLongCollisionEventPopupAndEditorKeepInformationReadable -parallel-testing-enabled NO
```

Expected: fail against the current 320×200 centered popup and single-line editor field.

### Task 2: Implement the popup, compact-card, and editor typography changes

**Files:**
- Modify: `PersonalCalendar/Features/Calendar/WeekPlannerView.swift`
- Modify: `PersonalCalendar/Features/EventEditor/EventEditorView.swift`

**Interfaces:**
- Consumes: existing `WeekPlannerTimedCollisionStack`, `CalendarEventSnapshot`, and editor model bindings.
- Produces: top-point anchored 340×260 popup states and a vertically growing title field.

- [x] **Step 1: Fix popup geometry**

Use a shared regular popup size of 340×260, attach collision popovers at the event’s top point, align popup content to `.topLeading`, and retain vertical scroll areas with fixed Close/Open actions.

- [x] **Step 2: Improve compact event hierarchy**

Use `.caption.weight(.semibold)` for the event title, keep secondary time at `.caption2`, reserve badge space, and omit secondary time when the rendered stack is too short to show it cleanly.

- [x] **Step 3: Make editor titles multiline**

Change the Event title to `TextField("Title", text: binding(\.title), axis: .vertical).lineLimit(1...3)` while retaining its identifier and system font.

- [x] **Step 4: Run the focused UI test and verify GREEN**

Run the Task 1 command. Expected: pass with popup content inside the window and the long editor title using multiple lines.

### Task 3: Regression verification and review

**Files:**
- Verify only: all touched production and test files.

**Interfaces:**
- Consumes: completed popup/editor implementation.
- Produces: evidence that the refinement did not regress Week Planner interaction or accessibility.

- [x] **Step 1: Run the full Week Planner UI class**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/WeekPlannerFlowUITests -parallel-testing-enabled NO
```

- [x] **Step 2: Run relevant unit and editor regressions**

```bash
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/WeekPlannerBuilderTests -only-testing:PersonalCalendarTests/DemoEnvironmentTests -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testEventEditorActionsRemainScrollableAndHittableAtAccessibilityXXXL -parallel-testing-enabled NO
```

- [x] **Step 3: Run static checks**

```bash
xcrun swiftc -frontend -parse PersonalCalendar/Features/Calendar/WeekPlannerView.swift PersonalCalendar/Features/EventEditor/EventEditorView.swift PersonalCalendar/App/DemoEnvironment.swift PersonalCalendarUITests/WeekPlannerFlowUITests.swift
git diff --check
```

- [x] **Step 4: Request an independent code review and address validated findings**

Review popup geometry, Dynamic Type, safe-area containment, occurrence routing, collision selection, and presentation dismissal before completion.

### Task 4: Real-device compact presentation and toolbar remediation

**Files:**
- Modify: `PersonalCalendar/Features/Calendar/WeekPlannerView.swift`
- Modify: `PersonalCalendar/Features/EventEditor/EventEditorView.swift`
- Modify: `PersonalCalendar/App/DemoEnvironment.swift`
- Modify: `PersonalCalendarUITests/WeekPlannerFlowUITests.swift`
- Modify: `PersonalCalendarUITests/FoundationFlowUITests.swift`
- Modify: `PersonalCalendarTests/DesignSystem/CalendarThemeTests.swift`

- [x] **Step 1: Bind the physical-phone popup failure with a long late-event regression**

Require a native compact sheet, fixed Close/Open actions, scroll-reachable location and notes, blocked background controls, and full window containment.

- [x] **Step 2: Adapt compact presentations without changing regular-width behavior**

Use medium/large sheet detents on compact width and keep the 340-by-260-point popover on regular width. Share the adaptive surface across event, overlap, and task-detail states.

- [x] **Step 3: Bound Event editor toolbar labels**

Use semantic callout labels capped at Dynamic Type `xxxLarge` for Cancel, Save, Saving, and Review while retaining a minimum 44-point SwiftUI frame.

- [x] **Step 4: Verify the targeted regressions and complete UI class**

Run the focused long-event and toolbar tests, then the complete Week Planner UI class and relevant editor accessibility regressions before device installation.
