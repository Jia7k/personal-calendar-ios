# Timetable Surface Links Design

## Status

Approved for implementation by the user's “yes go” response to the ranked QOL milestone on 2026-08-27.

## Problem

The timetable widgets and Live Activity already carry an exact profile and privacy-safe occurrence identity, and the app already routes profile-scoped calendar URLs. The system surfaces do not connect those two pieces: tapping a class opens the app generically instead of the exact class, and the weekly surface does not jump to the relevant day.

## Goals

1. Make each ready Next Class widget open its exact current or upcoming class.
2. Make each ready Weekly Timetable widget open Calendar on the represented local day and exact selected profile.
3. Make Lock Screen and Dynamic Island Live Activity taps open the exact current/upcoming class when possible, with a safe profile/day fallback.
4. Never serialize or expose EventKit mutation IDs, notes, alarms, or raw provider payloads in URLs.

## Non-goals

- No interactive provider mutations from widgets.
- No Maps URL embedded directly in WidgetKit; the exact event editor/Next Up path remains the place to launch Maps.
- No new background-refresh guarantee or push server.
- No fallback from a deleted/missing saved profile to Everything.
- No change to the current widget families or visual timetable layout.

## Considered Approaches

### A. Shared typed route builder — chosen

Add a small pure helper compiled into both app and widget targets. It converts a `ProfileIdentity`, local day, and optional opaque occurrence route ID into the existing `AppRoute.calendar` URL. Widgets and Live Activity use one implementation, and app unit tests verify encode/decode behavior.

### B. Build URLs directly in each SwiftUI view

This is fewer initial lines, but duplicates date/time-zone conversion and makes privacy/fallback behavior drift between Next Class, Week, Lock Screen, and Dynamic Island.

### C. Add a second widget-specific URL scheme

This avoids touching `AppRoute`, but creates duplicate routing semantics and another parser surface. The existing versioned `personalcalendar://v1/calendar` route already expresses the required destination.

## Design

### 1. Shared Route Builder

`TimetableSurfaceRouteBuilder` lives in `PersonalCalendar/ProfileShared` so both targets compile the same logic. It accepts an injected `AppRouteCodec` and exposes:

```swift
func url(
    profile: ProfileIdentity,
    date: Date,
    timeZoneIdentifier: String,
    entryRouteID: String?
) throws -> URL
```

It constructs a Gregorian `AppRouteDay` in the snapshot/activity time zone and encodes:

```swift
.calendar(day: day, profile: profile, entryID: normalizedEntryRouteID)
```

Blank route IDs normalize to nil. No title, location, provider ID, or other private content enters the URL.

### 2. Widget Entry Identity

`TimetableWidgetContent.ready` carries the selected `ProfileIdentity` in addition to profile name and snapshot. The provider uses the exact configured identity only after it resolves successfully in the current catalog. Deleted or malformed configurations remain `.profileDeleted` and receive no URL.

For Next Class, the view derives the current/next `TimetableMoment` at the timeline entry date and uses that entry's opaque `routeID` plus its start day. If there is no current/upcoming class, the widget routes to the current local day and exact profile without an entry ID.

For Weekly Timetable, the view routes to the timeline entry's local day and exact profile without choosing an arbitrary event.

The root widget view applies one `.widgetURL` only for `.ready` content. Choose-profile, deleted-profile, permission, empty-profile, and no-classes states do not route to another profile or expose stale content.

### 3. Live Activity Route Projection

New Activity content-state entries carry `routeID: String?` using a compact coding key. Projection copies `TimetableEntry.routeID`. Decoding older running activities uses nil for the absent field, so legacy activities remain recoverable and route only to the exact profile/day fallback.

The Lock Screen view and Dynamic Island both use the same route builder:

- if `state.entry(at: now)` has a nonblank route ID, open that exact occurrence;
- otherwise open Calendar for today's local day in `attributes.profileIdentity`;
- legacy/deleted profile handling remains fail closed in the app router.

The URL is attached at the Activity configuration's root and Dynamic Island root so all compact/expanded presentations behave consistently.

## Privacy and Failure Behavior

- URLs contain only route version, Gregorian day, `ProfileIdentity.storageKey`, and the existing opaque FNV-based occurrence route ID.
- EventKit display IDs and mutation IDs never serialize.
- URL construction failure results in no link; the widget/activity still renders.
- A stale or deleted occurrence produces the app's existing neutral unavailable message after an authoritative profile-scoped refresh.
- A stale or deleted profile never falls back to Everything.

## Accessibility

- Linked ready widgets add an accessibility hint such as “Opens this class in My Calendar” or “Opens this week in My Calendar.”
- Existing privacy-sensitive and redaction behavior stays intact.
- The link does not replace any visible timetable content or shrink hit targets.

## Testing

Unit tests cover:

- exact profile/day/opaque-entry URL round trip;
- time-zone day conversion near midnight and DST boundaries;
- blank entry ID becomes profile/day navigation;
- URLs contain no title, location, raw display ID, notes, or mutation ID;
- two widget configurations produce different profile URLs;
- Live Activity projection preserves a new opaque route ID and decodes a legacy entry without one;
- deleted/malformed/non-ready widget states expose no route.

A targeted widget target build verifies the shared helper and SwiftUI modifiers compile in the extension. Existing app-route host tests continue to prove exact-event lookup and neutral unavailable behavior.

