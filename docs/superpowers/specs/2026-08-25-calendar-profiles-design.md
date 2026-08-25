# Calendar Profiles and Merged Everything View Design

Date: 2026-08-25

## Summary

Add app-owned Personal, School, Work, and custom profiles that filter the entire planning experience without copying or moving the user's Apple Calendar, Google-synced Calendar, Reminders, or routine data.

A profile is a saved set of Apple calendar IDs, Reminders list IDs, and local routine IDs, plus presentation metadata and creation defaults. Sources and routines may belong to multiple profiles. A permanent virtual `Everything` profile shows the deduplicated union of all content assigned to at least one saved profile. Unassigned sources, such as Birthdays, remain hidden.

The selected profile applies to Calendar, Today, Tasks, Routines, and new-item defaults. Every timetable widget is configured independently to one selected profile. The existing full-width Live Activity is started from a profile chosen in the app.

## Approved product decisions

- Profiles group existing sources; they do not create new Apple calendars or accounts.
- The user's school timetable remains in its existing dedicated Google calendar synced through Apple Calendar.
- Profiles filter events, tasks, routines, Today, and widgets.
- A calendar, reminder list, or routine may belong to multiple profiles.
- `Everything` is the union of saved profiles, not every available system source.
- Each saved profile has its own default calendar and reminder list.
- Creating from `Everything` asks for a destination profile first.
- The app seeds editable Personal, School, and Work profiles plus permanent `Everything`.
- A compact profile selector appears in every main tab toolbar.
- Each widget instance chooses a profile independently through native widget configuration.

## Goals

- Let the user isolate School, Personal, Work, and future contexts with one switch.
- Keep Birthdays and other unwanted sources hidden by leaving them unassigned.
- Preserve Apple/Google as the owners of event and reminder data.
- Make the active profile consistent across all main app tabs.
- Use profile-specific creation defaults without silently writing to the wrong source.
- Keep one source or routine reusable across multiple profiles.
- Make `Everything` deterministic and duplicate-free.
- Let a School timetable widget stay pinned to School while the app displays another profile.
- Preserve profile configuration in app backup and recover gracefully when external sources disappear temporarily.

## Non-goals

- Copying, importing, or moving Google/Apple events into an app database.
- Parsing the school ICS file directly.
- Automatically inferring whether a calendar is Personal, School, or Work.
- Keyword rules or per-event profile overrides for mixed calendars.
- Separate user accounts, authentication, security boundaries, or duplicated databases per profile.
- Changing EventKit mutation identity or editor authority rules.
- Treating existing categories as profiles.
- Rendering tasks or routines as blocks in timetable widgets.
- Making unassigned sources visible in `Everything`.
- Per-profile notification enablement or alert schedules.

## Conceptual model

### Saved profile

Each saved profile contains:

- Stable UUID.
- Trimmed nonblank name.
- Light-mode color token or validated `#RRGGBB` color.
- SF Symbol name from a bounded app-provided selection.
- Dense sort order.
- Exact opaque Apple calendar IDs.
- Exact opaque Reminders list IDs.
- Local routine UUIDs.
- Optional default calendar ID.
- Optional default reminder-list ID.

Personal, School, and Work are ordinary editable records after seeding. They may be renamed, recolored, reordered, or deleted. The user may create more profiles.

The final saved profile cannot be deleted because `Everything` needs at least one saved destination choice for new items. The user may instead rename or clear that profile.

### Everything profile

The app uses a typed identity boundary, `ProfileIdentity.everything` or `ProfileIdentity.saved(UUID)`. `Everything` has a stable reserved identity but is not a mutable SwiftData record. Its resolved membership is computed as:

```text
calendar IDs     = union of calendar IDs in every saved profile
reminder list IDs = union of reminder-list IDs in every saved profile
routine IDs       = union of routine IDs in every saved profile
```

Set membership removes duplicates. Content assigned nowhere is absent from `Everything`.

`Everything` cannot be renamed, recolored, reordered, or deleted, and it stores no creation defaults. Creating from it first requires selecting a saved profile; that profile then supplies its default destination.

### Membership semantics

Profile membership belongs to the app, while the referenced content remains provider-owned:

- Calendar events are included when `CalendarEventSnapshot.calendarID` belongs to the resolved profile.
- Reminders are included when `ReminderSnapshot.listID` belongs to the resolved profile.
- Routines are included when their UUID belongs to the resolved profile.

External IDs are opaque and compared byte-for-byte. They are never parsed, normalized, or used as mutation identifiers.

## Persistence design

### SwiftData record

Use one minimal `ProfileRecord` model rather than a separate join entity:

```swift
@Model
final class ProfileRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var symbolName: String
    var sortOrder: Int
    var calendarIDs: [String]
    var reminderListIDs: [String]
    var routineIDs: [UUID]
    var defaultCalendarID: String?
    var defaultReminderListID: String?
}
```

Array membership is sufficient for the expected personal-scale data, directly expresses many-to-many membership, and avoids extra relationship models and cascading-delete behavior. Repository writes normalize duplicates and keep deterministic ordering.

`ProfileSnapshot` is the immutable `Equatable`, `Codable`, and `Sendable` boundary used by view models, backup, filtering, and widget snapshot generation. SwiftData records do not cross those boundaries.

`ProfileRecord.self` is added to the existing app `ModelContainer` schema and every in-memory container that constructs `AppEnvironment`. This adds one new table and does not alter provider-owned data or require a `RoutineRecord` schema change.

### Repository

`ProfileRepository` owns persisted profile data:

- Listing saved profiles by sort order and UUID tie-breaker.
- Fetching one profile.
- One-time seed/migration.
- Create, update, reorder, and delete.
- Removing a deleted local routine ID from all profiles.
- Validating names, colors, symbols, order membership, and stored default membership before mutation.

A long-lived `ProfileSelectionController` owns the active identity and selection revision. A `ProfileScopeResolver` combines repository snapshots with current Calendar/Reminders access and descriptors to produce the immutable scope used by features. This keeps provider authority out of the persistence repository.

A saved default must be both a member of that profile and currently writable at the moment a create form is prepared. A missing or read-only default remains visible as needing attention but is not used for a write.

Profile mutations are app-local SwiftData transactions. They never call Calendar or Reminders mutation APIs.

### Active selection

`AppSettingsStore` persists the active profile identity and the last active saved profile identity. The latter is presentation history only; it is not used as an implicit destination when creating from `Everything`.

If the active saved profile is deleted or cannot be loaded, selection falls back to `Everything`. Switching profile emits one app-level selection revision that all main tabs observe.

## Initial seed and migration

The one-time seed creates Personal, School, and Work in that order.

For an existing installation:

- Personal receives the calendar IDs currently resolved as visible.
- Personal receives the reminder-list IDs currently resolved as visible.
- Personal receives all current nonarchived routine IDs.
- Existing writable default calendar/list values are copied when they are members.
- School and Work start empty.
- Personal becomes active so the visible app initially matches the prior configuration.

For a fresh installation, the same current visibility semantics seed Personal after each provider's permission and descriptors become available. The user then assigns the dedicated Google School calendar to School and removes unwanted sources such as Birthdays from Personal.

Legacy global visibility/default settings remain readable only for one-time migration and older backup compatibility. Once profile seeding succeeds, profile resolution becomes the sole source of app filtering and creation defaults.

`AppSettingsStore` captures an immutable legacy-selection snapshot at initialization. Profile migration consumes that snapshot before the first `reconcileSources` call can intersect or replace legacy IDs. Deferred provider migration continues using the captured snapshot, not subsequently reconciled legacy fields. After a provider migration succeeds, the legacy reconciliation path is disabled for that provider; current descriptor reconciliation occurs against profile membership instead.

Seeding uses independent completion state for profile records, Calendar migration, Reminders migration, and routine migration. Creating Personal/School/Work never marks a provider migration complete by itself. On a fresh install, Calendar or Reminders access in `.notDetermined`, `.denied`, or `.restricted` keeps that provider pending; the first later granted refresh migrates its visible selection exactly once. An explicit legacy source selection can migrate from its stored IDs even while descriptors are temporarily unavailable. Routine migration runs immediately from the local repository.

Each completion marker is persisted only after its own transaction succeeds. Repeated launches do not duplicate profiles or overwrite user changes, and choosing `Not Now` during onboarding cannot permanently create an empty Personal profile.

## Profile selection and navigation

Every main tab shows the same compact toolbar control:

```text
[profile symbol] School ▾
```

The menu lists `Everything`, then saved profiles in user order. Selecting an item:

1. Persists the active identity.
2. Publishes one selection revision.
3. Refreshes Calendar, Today, Tasks, and Routines using the same resolved scope.
4. Does not change the selected tab or dismiss an editor already in progress.

The selector exposes name and icon through VoiceOver, reports the current value, and has a 44-point minimum target.

## Profile management

Settings gains a `Profiles` destination containing:

- Ordered profile rows with icon, name, and color.
- Create and reorder actions.
- An immutable `Everything` explanation row.
- A profile editor for name, icon, color, calendars, reminder lists, routines, and defaults.

The editor has separate Calendar and Reminder Lists sections and displays each available source's title and color. A source can be checked in any number of profiles. Read-only sources are valid for viewing, but cannot be selected as creation defaults. Provider/account grouping is deferred because the current source descriptors do not expose provider metadata.

Unavailable external source IDs remain stored and appear in a `Waiting to reconnect` section using neutral unavailable-source copy. Reappearance with the exact ID restores membership automatically. The app never exposes the opaque ID to the user or substitutes a similarly named calendar or list.

Deleting a profile requires confirmation. It deletes only the profile record and does not delete provider content or routines. If it was active, the app selects `Everything`. Widgets configured to the deleted identity show a configuration-required state.

The legacy `Visible calendars`, `Visible reminder lists`, and global default controls leave Settings after successful migration. Profile membership and per-profile defaults replace them; their stored values remain only as backward-compatible migration input.

Changing membership in the active saved profile, or changing any membership while `Everything` is active, publishes a new scope revision and refreshes Calendar, Today, Tasks, and Routines. Editing an inactive profile still rebuilds its widget data but does not unnecessarily reload the currently visible feature models.

## Filtering behavior

`ProfileScope` is captured before each fetch and contains exact calendar, reminder-list, and routine ID sets plus valid defaults.

- Calendar fetches only the scope's calendar IDs.
- Today fetches events and reminders from the scope and filters routines by UUID.
- Tasks fetches only the scope's reminder-list IDs.
- Routines lists only scope routine IDs.
- `Everything` uses the union scope and deduplicates fetched content by its existing display identity.

An empty saved profile is a valid state. Each tab shows an intentional empty view with a link to configure that profile, rather than falling back to all sources.

The current EventKit service contracts treat an empty source-ID set as `all sources`. Profile-aware callers must therefore short-circuit an empty calendar or reminder-list scope and return an empty snapshot without calling those fetch methods. A later service API may introduce an explicit `.all` / `.only(Set)` scope, but no profile path may pass an empty set and accidentally expose every source.

Profile switching changes visibility only. It never changes EventKit permissions, Apple Calendar visibility, recurrence, completion, or provider ownership.

Provider-owned event/reminder alarms and app-owned routine notification enablement do not turn on or off when the user changes the visible profile. The morning summary and routine-notification scheduler use the `Everything` union so a visual context switch cannot silently suppress an important alert. Membership changes that alter the union reschedule app notifications; merely switching the active profile does not. Profile-specific notification rules are deferred.

## Creation and editing

### Saved profile

Starting Quick Entry, Event editor create, Task editor create, or Routine create while a saved profile is active:

- Seeds the profile's valid default calendar or reminder list.
- Offers only currently writable destinations, while clearly identifying destinations outside the active profile.
- Allows an explicit destination override before saving.
- Assigns a newly created routine to the active profile.

An explicit destination outside the active profile is allowed, but it does not silently alter profile membership. The newly created item therefore appears only in profiles that already contain that destination source.

Routine creation and deletion change both `RoutineRecord` and profile membership. A `RoutineProfileMutationCoordinator` performs those paired changes in one `ModelContext.transaction` using the shared main context. Routines and Quick Entry use this coordinator for create/delete; they must not call the routine repository and profile repository sequentially. Unrelated routine edits and completion changes continue through `RoutineRepository`.

If a required profile default disappeared or became read-only, the creation screen asks for a destination. It never silently falls back to an unrelated system default.

### Everything

Starting creation from `Everything` first presents a profile choice. The chosen saved profile supplies defaults and routine membership. The normal creation form then opens, and the user can still override its destination.

### Existing items

Opening an existing event or reminder preserves its current source. Editing never moves it merely because a different profile is active. Existing EventKit mutation-ID and read-only authority checks remain unchanged.

## Widgets and Live Activity

### Widget configuration

The permanent timetable widgets move from static configuration to `AppIntentConfiguration` with an optional profile entity. Every widget instance stores its own profile selection. A nil or no-longer-resolvable entity renders `Choose a profile`; it never falls back to another profile. `Everything` is offered as an ordinary selectable entity backed by its reserved identity.

Examples:

- School week widget -> School.
- Personal next-event widget -> Personal.
- Combined agenda widget -> Everything.

Changing the app's active profile does not change a pinned widget.

### Shared widget catalog

The app remains the only EventKit reader. It atomically writes a bounded, versioned App Group catalog containing:

- Public widget-safe profile identity, name, color, and symbol.
- One privacy-minimized timetable snapshot per profile.
- A derived `Everything` snapshot.

Each timetable snapshot contains only event title, compact title, start, end, and location. It excludes notes, URLs, alarms, recurrence metadata, calendar IDs, and mutation IDs.

The widget extension reads the catalog to provide profile choices and timelines. Membership or event changes rewrite affected snapshots and reload WidgetKit timelines. If a configured profile is deleted, the widget says `Choose another profile`; it does not expose `Everything` as an implicit fallback.

Existing installed static timetable widgets cannot carry a profile selection into the new App Intent. Their first profile-aware timeline shows `Choose a profile`, and the user edits or re-adds each widget once. The widget kind remains stable where WidgetKit permits the configuration migration, but the design does not guess Personal or expose Everything automatically.

Timetable widgets render only calendar events. Tasks and routines remain visible in the selected profile inside the app and may power future dedicated widgets.

### Live Activity

Starting the timetable Live Activity includes a profile picker in the app. `TimetableActivityAttributes` stores the chosen stable profile identity alongside its existing week/time-zone attributes, allowing launch recovery to determine which profile owns an activity. The bounded content state is generated from that profile's calendar events. If that saved profile is deleted, the app ends its activity the next time it has runtime. Existing local-only ActivityKit lifecycle limitations remain unchanged.

## Refresh and lifecycle

```text
Profile selected
  -> resolve immutable ProfileScope
  -> refresh Calendar / Today / Tasks / Routines
  -> persist active profile

Profile membership changed or EventKit store changed
  -> refresh permissions and descriptors
  -> retain missing membership IDs
  -> if the changed scope is visible, publish one scope revision and refresh all four main models
  -> rebuild affected profile timetable snapshots
  -> rebuild Everything union snapshot
  -> atomically write widget catalog
  -> reload widget timelines
  -> update an active timetable Live Activity when its profile is affected
```

The profile repository and selection controller are long-lived in `AppEnvironment`; the repository shares the app's existing main SwiftData context. Refresh coordination remains host-owned; repositories do not trigger UI refreshes themselves.

EventKit monitoring runs only while the app process has execution time. Changes made externally while the app is suspended reach profile widget snapshots on the app's next foreground/background execution opportunity; the extension never queries EventKit and the local-only design does not promise instant background synchronization.

## Project and device configuration

`project.yml` remains the project source of truth. Add `ProfileRecord` to the app schema and compile shared profile-widget DTOs into both the app and widget extension without hand-editing `project.pbxproj`.

Simulator validation uses the existing App Group entitlement. Physical-device delivery requires the App Group identifier to be registered and provisioned for both the app and widget-extension bundle identifiers, plus a selected Development Team that supports the capability. Without that signing configuration, profile-aware widgets cannot read the shared catalog on a real device.

## Backup and restore

Backup schema version 2 adds:

- Saved profile snapshots.
- Active profile identity.
- Last active saved profile identity.
- Profile seed state.

`Everything` and App Group timetable snapshots are derived and are not backed up.

Restore requires at least one saved profile and validates profile UUID uniqueness, normalized name uniqueness, colors, symbols, sort order, membership duplicates, and default membership before any mutation. External calendar/list IDs are retained even when unavailable on the restoring device so they can reconnect. Routine membership must reference a routine present in the same restored backup; invalid local references reject the backup rather than silently pointing elsewhere.

After restore, missing active identity falls back to `Everything`, the widget catalog is rebuilt, and no EventKit item is created or changed.

Backup decoding first reads a minimal version discriminator, then decodes either the existing `BackupEnvelopeV1` shape or the new `BackupEnvelopeV2` shape. A v1 restore first restores legacy visibility/default settings and then runs the same one-time profile migration into Personal. New profile fields are never added as required fields to the v1 decoding type.

## Error behavior

- Calendar or Reminders access unavailable: keep profile configuration, show an access explanation, and return no content for that provider.
- Profile has no members: show a configure-profile empty state.
- Default missing/read-only: require explicit destination selection before creation.
- External source temporarily missing: retain exact membership and show `Waiting to reconnect`.
- Active profile deleted/missing: select `Everything`.
- Widget profile deleted: render configuration-required state.
- Ordinary event-refresh/catalog write failure: retain the prior catalog, report an app-local warning, and never alter provider content.
- Permission revocation, profile deletion, or membership removal: fail closed by atomically writing a tombstone/reduced catalog; if that write fails, delete the shared catalog, reload widgets, and end affected Live Activities so removed titles and locations are not left visible.
- Profile repository write fails: keep the previous active/profile state and show a retryable local error.

## Accessibility and visual behavior

- Profiles use color plus icon and text; color is never the sole differentiator.
- Profile colors use the approved professional, comfortable light-mode palette.
- The toolbar selector and profile rows support Dynamic Type and 44-point targets.
- VoiceOver labels read `Profile, School`, with the current selection exposed as the value.
- Empty, unavailable, and reconnecting states are written text, not icon-only indicators.
- Widget rendering follows WidgetKit system contrast and Lock Screen vibrant-mode rules.

## Testing strategy

Use focused test classes only; do not run the global suite.

Required unit coverage:

- One-time seed creates Personal/School/Work exactly once and migrates current visibility/defaults to Personal.
- Deferred Calendar/Reminders migration remains pending after `Not Now` and runs once after later permission grant.
- Many-to-many source and routine membership is preserved.
- `Everything` is the exact deduplicated union and excludes unassigned Birthdays.
- Active deletion falls back to `Everything` without deleting content.
- Missing external IDs are retained and reconnect by exact identity.
- Profile filtering reaches Calendar, Today, Tasks, and Routines consistently.
- Empty profiles do not fall back to all sources.
- Saved-profile creation seeds exact valid defaults.
- `Everything` creation requires a saved-profile selection.
- Missing/read-only defaults never produce an unintended write.
- Backup round-trip preserves profiles and rejects invalid routine references.
- Widget profile entities and timelines resolve the selected profile independently.
- Deleted widget profiles render configuration-required state.

One focused integration test should switch from Personal to School and prove that all four feature models receive the same School scope while provider data is not mutated.

Manual Simulator checks cover profile switching, profile editing, Quick Entry defaults, a School-pinned widget while Personal is active, `Everything` union behavior, Dynamic Type, and VoiceOver labels.

## Acceptance criteria

- Personal, School, Work, and permanent `Everything` are available after migration/onboarding.
- The dedicated Google School calendar can be assigned to School without copying its events.
- Birthdays can remain unassigned and absent from every app view, including `Everything`.
- Switching profiles from any main tab filters Calendar, Today, Tasks, and Routines together.
- One source or routine can appear in multiple profiles without duplicate items in `Everything`.
- Each saved profile supplies its own valid creation defaults.
- Creating from `Everything` asks for a saved profile first.
- Deleting a profile never deletes provider content or routines.
- Each timetable widget can be configured to School, Personal, Work, Everything, or another saved profile.
- A School-pinned widget stays on School when the app switches to another profile.
- Profile configuration survives backup/restore and missing Google sources reconnect by exact identity.
