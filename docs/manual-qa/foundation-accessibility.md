# Foundation and system-integration manual QA

XCUI coverage verifies app-owned semantics, state transitions, and control operability. It cannot prove visual quality or control the final presentation of notifications, Siri, Shortcuts, Maps, widgets, Live Activities, and some accessibility system surfaces. Complete this checklist on a current iPhone or simulator before release.

Record the device or simulator, iOS version, locale, time zone, system appearance, text size, and any finding. Attach a screenshot or screen recording for visual failures.

## Fixed light appearance

- [ ] Set the device to Light appearance. Inspect Calendar Month and Week, Today, Tasks, Quick Entry, task time blocking, Settings, permission cards, editors, and confirmation alerts. Confirm the Harbor & Linen background, text, source icons, selected/today outlines, disabled controls, card boundaries, and focus indicators remain distinguishable without relying on color alone.
- [ ] Set the device to Dark appearance, relaunch the app, and revisit the same screens. Confirm the app intentionally remains in its light appearance; no screen or presented sheet changes to a dark palette and no text becomes low contrast.
- [ ] Confirm the Home Screen weekly widget and Lock Screen surfaces remain legible against their system-controlled backgrounds. Widget and Live Activity rendering do not need to mimic the in-app light background.

## Notifications and actions

- [ ] On a device, grant notification and Calendar access. In **Settings → Notifications**, enable a class alert for one saved School profile and choose a lead time. Create or select a future timed class far enough ahead for the chosen lead. Confirm exactly one alert appears at the expected local time with the correct title, lead time, and location when present.
- [ ] Tap the class alert. Confirm the app selects the exact saved profile and date and opens the matching class. Delete the profile or revoke Calendar access, repeat with a pending route if practical, and confirm the app reports the target unavailable instead of falling back to Everything.
- [ ] Trigger a routine reminder scheduled for today. Choose **Complete** and confirm the routine is completed once for the current local day. Repeating the action must not create another completion.
- [ ] Trigger another routine reminder and choose **Snooze 15 min**. Confirm one replacement notification arrives about 15 minutes after the response and unrelated app notifications remain scheduled.
- [ ] Enable the morning summary and tap it when delivered. Confirm it opens Today. Disable class alerts and the morning summary, refresh the app, and confirm later app-owned alerts are removed.
- [ ] Repeat a class-alert check across a time-zone or daylight-saving transition if that locale is supported for release. Confirm the alert follows the event's current local date and time.

## Quick Entry, Siri, and Shortcuts

- [ ] In the Shortcuts app, run **Quick Add**, enter a phrase such as “Dentist Friday at 3pm,” and choose a saved profile. Confirm My Calendar opens its Quick Entry confirmation with the same text and exact profile.
- [ ] Cancel the confirmation and verify no Calendar event, Reminder, or routine was created. Run it again, review the parsed kind, time, destination, and category, then save and confirm exactly one item is created.
- [ ] Invoke “Add to My Calendar” or “Plan with My Calendar” through Siri. Confirm Siri hands off to the same in-app confirmation instead of reporting that the item was silently saved.
- [ ] Run Quick Add without choosing a profile while Everything is active. Confirm the app requires an explicit saved creation profile rather than guessing a destination.
- [ ] Save several entries in two profiles. Confirm Recent shows only entries for the current saved profile, selecting one restores its text, safe per-profile choices are remembered, and clearing that profile's recent entries does not clear the other profile.

## Timetable widgets and Live Activity

- [ ] Add two **Next Class** Lock Screen widgets and configure them to different saved profiles. Confirm each instance keeps its own profile after relaunch and neither falls back to Everything when its saved profile is removed.
- [ ] Add the medium **Weekly Timetable** Home Screen widget. Confirm Monday–Friday entries, early and late classes, locations, current/next state, and any explicit “more” count are readable. Confirm unassigned calendars such as Birthdays do not leak into School or Everything.
- [ ] Change a timetable event or profile membership in Calendar, Google Calendar, or Settings. Open My Calendar, allow its refresh to finish, and confirm both widgets receive the new weekly snapshot. Do not treat an immediate background-only update as a release requirement.
- [ ] Leave a timetable snapshot unchanged for more than six hours, then inspect the Live Activity. Confirm it says to open Personal Calendar to refresh. Open the app and confirm current data replaces the stale projection.
- [ ] In **Settings → Timetable**, manually start a ready profile. Confirm the full-width Lock Screen Live Activity and Dynamic Island show the selected profile's current or next classes. Switch profiles and confirm the old activity ends before the new one appears; **Stop for now** must remove it.
- [ ] Select a timetable profile, enable **Start when Personal Calendar opens**, leave and reopen the app, and confirm the exact profile starts only after refreshed data is available. Disable the setting and confirm the current activity stops. Delete the preferred saved profile and confirm the preference clears and never falls back to Everything.
- [ ] Confirm closing or suspending the app does not create a false promise of guaranteed transitions. Record that the app has no push server, updates depend on available runtime, and an activity is limited to eight active hours.

## Today, Maps, task triage, and Calendar navigation

- [ ] Give the next timed event a recognizable location. On Today, confirm **Next Up** announces and displays whether the event is happening now or upcoming, its time/countdown, location, and nearest incomplete deadline. Wait through a one-minute refresh boundary and confirm the relative state changes sensibly.
- [ ] Tap **Maps** and confirm Apple Maps opens a search for the displayed location. Cancel or return to My Calendar and confirm the Next Up card is still usable.
- [ ] In Tasks, reschedule a writable, nonrecurring overdue task with Tomorrow, then use **Undo reschedule**. Confirm it returns to its exact prior due date and time. Confirm recurring and read-only tasks do not expose unsafe quick-reschedule actions.
- [ ] Choose **Schedule Time** on an incomplete task. Confirm suggestions fit the selected 30-, 60-, or 90-minute duration, use only the active profile's events/calendars, and prefer useful space around the due time. Saving must create one Calendar event while leaving the Reminder unchanged.
- [ ] Choose a conflicting interval. Confirm the conflict names are visible and the first confirmation changes to **Save Anyway**; canceling or a failed write must leave the Reminder and Calendar unchanged.
- [ ] In Calendar, use **Jump to Date** for a date outside the visible month. Confirm Month and Week select and scroll to that exact local day. Check search and deep links still respect the active profile.

## VoiceOver

- [ ] On today's Calendar cell, confirm the announcement includes a localized full date, “Today,” “Selected,” and the item count. Check Week task completion, Jump to Date, search, and the profile selector for clear names, values, and state.
- [ ] Read the Next Up card. Confirm VoiceOver distinguishes “Happening now” from “Next event,” announces the event and deadline controls, and labels Maps with the destination.
- [ ] In Tasks and task time blocking, confirm completion, quick-reschedule, Undo, duration, suggestions, conflicts, destination, and Save Anyway controls have meaningful labels and selected/disabled state.
- [ ] In Quick Entry, confirm kind, profile, recent entry, parsed details, destination, warning, confirmation, and save-result controls are announced in a logical order.
- [ ] Follow a degraded Calendar or Today permission card into Settings and confirm controls have clear names. Move through all onboarding pages and confirm every transition moves focus to the new heading and announces the page and step before its benefit, status, and actions.
- [ ] With VoiceOver on the Lock Screen, confirm Next Class and the Live Activity expose useful profile, title, time, location, stale, and omission information without reading decorative elements as controls.

## Accessibility XXXL

- [ ] Enable the largest Accessibility text size. In Calendar Month and Week, Today, Tasks, Routines, Quick Entry, editors, task time blocking, Jump to Date, and Settings, confirm content uses the accessibility layout where provided and remains readable without clipping or overlap.
- [ ] Confirm the Add control, tab bar, profile selector, task actions, Next Up Open/Maps buttons, Undo, Cancel, Save, Save Anyway, and Done remain reachable and have at least a 44-point hit target.
- [ ] From a degraded permission card, open Settings. Confirm the permission explanation, system-settings action, and Done button remain readable and reachable.
- [ ] Rotate through any supported device orientation and test the smallest supported iPhone width. Confirm sheets scroll to obscured controls when the keyboard is shown.

## Reduce Motion

- [ ] Enable Reduce Motion. Expand and collapse the Calendar day tray with both the visible button and vertical gesture. Confirm state changes without a large movement animation and focus remains on a useful control.
- [ ] Open and dismiss Quick Entry, Jump to Date, task time blocking, and an editor. Confirm no custom transition or focus jump makes the workflow difficult to follow.
