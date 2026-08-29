# Week Event Popup Polish Design

**Approved:** 2026-08-29

## Goal

Keep the Week Planner’s tap-to-expand interaction while making long event information readable on a real iPhone and preserving Dynamic Type.

## Design

- Keep the 340-by-260-point anchored popover on regular-width layouts.
- On compact-width iPhones, adapt event, collision-choice, and task-detail presentations to a native medium/large sheet so late events cannot place content behind the tab bar or Add button.
- Keep the full event title and Close action fixed at the top, the event details vertically scrollable, and Open Event fixed at the bottom with at least 44-point targets.
- Make the shared popup surface fill the compact presentation while retaining top-leading alignment and bounded dimensions in a regular-width popover.
- Use semantic Dynamic Type fonts. Increase compact timeline titles from `caption2` to `caption`, retain a smaller secondary time, and reserve space for the `+N` badge instead of allowing it to cover text.
- Let the Event editor title grow vertically from one through three lines; do not shrink the font.
- Cap only Event editor toolbar action labels at semantic `xxxLarge` so Cancel, Save, and Review stay within their toolbar controls at larger content sizes while retaining 44-point SwiftUI targets.
- Preserve the existing accessibility-size inline Week Planner layout.

## Verification

- A deterministic long event in a collision stack shows its full title, time, calendar, location, and notes inside the popup, with Close and Open Event reachable.
- The compact sheet can close and reopen, blocks the underlying tab bar and Add button, and remains within the app window; regular-width layouts retain the anchored popover.
- The long event opens an editor whose title field wraps to more than one line.
- At Accessibility XXXL, Cancel and Save remain distinct, readable, and reachable without overflowing their toolbar controls.
- Existing Week Planner popup, collision, accessibility, profile-isolation, vertical-scroll, and editor tests remain green.
