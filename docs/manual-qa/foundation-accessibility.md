# Foundation accessibility manual QA

XCUI coverage verifies semantic labels, values, state transitions, and control operability. It does not measure visual contrast or prove that an animation is absent. Complete these checks on a current iOS simulator or device before release:

- **Dark Mode:** Enable Dark appearance, then inspect the Calendar and Today degraded-permission cards and the in-app Settings sheet. Confirm primary and secondary text, source icons in Calendar day cells, selected/today outlines, outside-month indicators, disabled controls, card boundaries, and focus indicators remain distinguishable without relying on color alone.
- **Reduce Motion:** Enable Reduce Motion in Accessibility settings. Expand and collapse the Calendar day tray with both the visible button and vertical gesture. Confirm the content changes state without a large movement animation and that focus remains on a useful control.
- **VoiceOver:** On today’s Calendar cell, confirm the announcement includes a localized full date, “Today,” “Selected,” and the item count. Follow a degraded Calendar or Today permission card into the in-app Settings sheet and confirm its controls have clear names. Move through all three onboarding pages and confirm that every transition moves focus to the new page heading and announces the page and step before its benefit, status, and actions.
- **Accessibility XXXL:** From a degraded Calendar permission card, open the in-app Settings sheet. Confirm the permission explanation, system-settings action, and Done button are readable, reachable, and do not clip or overlap.

Record device/simulator, iOS version, locale, appearance, text size, and any finding with a screenshot in the release QA notes.
