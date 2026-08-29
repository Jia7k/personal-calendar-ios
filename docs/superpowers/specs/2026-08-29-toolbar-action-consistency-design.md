# Toolbar Action Consistency Design

## Problem

At very large Dynamic Type sizes, most navigation toolbar actions use SwiftUI's shorthand `Button(String)` label. The text keeps scaling while the native compact glass toolbar host has limited space, so labels such as Cancel can be visibly clipped. The Event editor already avoids this by bounding its label before native toolbar layout, but the pattern is local to that screen.

## Approved design

- Keep SwiftUI's native `ToolbarItem`, `Button`, roles, disabled states, tint, and glass appearance.
- Add one design-system `CalendarToolbarActionLabel` used by every textual cancellation and confirmation toolbar action.
- Use semantic `callout` typography, regular weight for cancellation/navigation actions, semibold for commits or destructive confirmations, one line, a visual Dynamic Type cap of `xxxLarge`, and a minimum 44 by 44 point label frame.
- Keep intrinsic widths. Uniformity means shared typography, height, scaling, and emphasis—not identical capsule widths.
- Preserve all existing actions and accessibility identifiers. Add identifiers only where integration coverage needs a stable query.
- Leave system-owned `EditButton` controls and icon-based add buttons unchanged.
- Body buttons such as Quick Entry's full-width Review and Done controls are outside this toolbar contract.

## Verification contract

- A rendered SwiftUI unit test measures every toolbar-title variant at Accessibility 5 and requires a 44-point minimum, a bounded single-row height, equal heights, and bounded compact-title widths.
- A real Accessibility XXXL UI flow verifies Quick Entry Cancel, Back, and Save plus Event editor Cancel and Save remain fully named, hittable, inside their navigation bars, non-overlapping, and geometrically consistent.
- Focused tests must demonstrate RED before production changes and GREEN afterward.
- The complete app test suite, signed device build, install, and launch are the final gates.
