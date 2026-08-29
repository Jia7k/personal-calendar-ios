# Week Event Popup Polish Design

**Approved:** 2026-08-29

## Goal

Keep the anchored Week Planner interaction the user selected while making long event information readable on a real iPhone and preserving Dynamic Type.

## Design

- Keep the Week Planner’s anchored popover on iPhone and iPad.
- Increase regular popup content to 340 points wide by 260 points high, align content to the top, and keep it inside the safe window.
- Anchor the popup from the event’s top edge instead of the bottom of the event’s full bounds so tall and late events do not force the card into the tab bar.
- Keep the full event title and details in a vertically scrollable region. Keep Close and Open Event outside that scrolling region with at least 44-point targets.
- Apply the same container dimensions and alignment to collision choice and task-detail states.
- Use semantic Dynamic Type fonts. Increase compact timeline titles from `caption2` to `caption`, retain a smaller secondary time, and reserve space for the `+N` badge instead of allowing it to cover text.
- Let the Event editor title grow vertically from one through three lines; do not shrink the font.
- Preserve the existing accessibility-size inline Week Planner layout.

## Verification

- A deterministic long event in a collision stack shows its full title, time, calendar, location, and notes inside the popup, with Close and Open Event reachable.
- The popup can close and reopen and remains within the app window.
- The long event opens an editor whose title field wraps to more than one line.
- Existing Week Planner popup, collision, accessibility, profile-isolation, vertical-scroll, and editor tests remain green.
