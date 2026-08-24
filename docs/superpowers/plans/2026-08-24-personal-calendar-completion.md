# Personal Calendar Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the personal calendar with safe full editing, on-device quick entry, app-defined colors, reliable local notifications, transactional backup/restore, external-change refresh, and release-quality accessibility.

**Architecture:** This plan extends the tested service boundaries from the foundation. EventKit services gain recurrence-aware mutations, an on-device parser produces a source-neutral confirmation model, and a save router is the only component that converts confirmed previews into destination drafts. SwiftData adds categories and backup DTOs without copying Apple items, while notification and refresh coordinators remain replaceable system boundaries.

**Tech Stack:** Swift 6, SwiftUI, Observation, EventKit, SwiftData, UserNotifications, Foundation `NSDataDetector`, XCTest, XCUITest, XcodeGen 2.x, iOS 17+

**Spec:** `docs/superpowers/specs/2026-08-24-personal-calendar-ios-design.md`

**Prerequisite plan:** `docs/superpowers/plans/2026-08-24-personal-calendar-foundation.md` must be complete with all foundation tests passing.

## Global Constraints

- Build a native iPhone app with SwiftUI and a deployment target of iOS 17.0 or later.
- Use no third-party runtime dependencies and no CloudKit entitlement, account system, backend, analytics SDK, or network service.
- Apple Calendar and Apple Reminders remain authoritative; never persist a second copy of their complete item content.
- Persist only app-owned routines, completion records, categories, category links, and settings locally.
- Natural-language parsing must run entirely on device and must never save without an editable confirmation.
- Read-only, subscribed, and otherwise immutable EventKit items remain viewable; mutation actions are disabled with a plain-language explanation.
- A failed save keeps the user's draft or preview intact and offers Retry.
- App categories affect only this app; they do not change native Apple calendar or reminder-list colors.
- The morning summary is a best-effort snapshot created while the app is running; do not claim background-perfect freshness.
- Schedule routine notifications for no more than 14 days ahead and no more than 48 pending routine requests.
- Restore replaces all app-owned local data in one SwiftData transaction and never changes Apple Calendar or Reminders content.
- Use original copy and styling; do not copy TimeTree assets, icons, names, or exact screen compositions.
- Support Dark Mode, Dynamic Type, VoiceOver, 44-point touch targets, and Reduce Motion throughout implementation.
- Generate `PersonalCalendar.xcodeproj` from the committed `project.yml`; never hand-edit `project.pbxproj`.
- Run `xcodegen generate` after every source-file addition or deletion and before each `xcodebuild` command.

## File map

### Extended domain and EventKit editing

- `PersonalCalendar/Domain/Recurrence.swift` — app recurrence values and EventKit conversion.
- `PersonalCalendar/Domain/Drafts.swift` — expanded event/reminder details and recurrence fields.
- `PersonalCalendar/Services/EventKit/CalendarServicing.swift` — event detail, update, and delete signatures.
- `PersonalCalendar/Services/EventKit/RemindersServicing.swift` — reminder detail, update, and delete signatures.
- `PersonalCalendar/Services/EventKit/EventKitCalendarService.swift` — recurrence-aware event mutation.
- `PersonalCalendar/Services/EventKit/EventKitRemindersService.swift` — reminder mutation without fabricated future occurrences.
- `PersonalCalendar/Features/EventEditor/EventEditorViewModel.swift` — retained event draft and scope selection.
- `PersonalCalendar/Features/EventEditor/EventEditorView.swift` — create/edit form.
- `PersonalCalendar/Features/Tasks/TaskEditorViewModel.swift` — retained reminder draft.
- `PersonalCalendar/Features/Tasks/TaskEditorView.swift` — create/edit form.

### Quick entry

- `PersonalCalendar/QuickEntry/QuickEntryPreview.swift` — source-neutral editable confirmation model.
- `PersonalCalendar/QuickEntry/QuickEntryParsing.swift` — parser boundary and parse context.
- `PersonalCalendar/QuickEntry/RuleBasedQuickEntryParser.swift` — deterministic on-device parser.
- `PersonalCalendar/QuickEntry/SaveRouter.swift` — confirmed-preview routing and retry state.
- `PersonalCalendar/Features/QuickEntry/QuickEntryViewModel.swift` — text, preview, editing, save, and errors.
- `PersonalCalendar/Features/QuickEntry/QuickEntrySheet.swift` — universal input and confirmation UI.

### Categories, notifications, backup, and refresh

- `PersonalCalendar/Persistence/CategoryRecord.swift` — local category.
- `PersonalCalendar/Persistence/ExternalCategoryLinkRecord.swift` — external identifier-to-category metadata.
- `PersonalCalendar/Persistence/CategoryRepository.swift` — category boundary.
- `PersonalCalendar/Persistence/SwiftDataCategoryRepository.swift` — category and unresolved-link implementation.
- `PersonalCalendar/Notifications/NotificationScheduling.swift` — notification boundary.
- `PersonalCalendar/Notifications/SystemNotificationScheduler.swift` — morning and routine scheduling.
- `PersonalCalendar/Notifications/NotificationCoordinator.swift` — policy, 14-day horizon, and 48-request budget.
- `PersonalCalendar/Backup/BackupEnvelope.swift` — versioned Codable DTOs.
- `PersonalCalendar/Backup/BackupService.swift` — export and validated transactional replacement.
- `PersonalCalendar/Refresh/EventStoreChangeMonitor.swift` — EventKit change notification boundary.
- `PersonalCalendar/Refresh/AppRefreshCoordinator.swift` — foreground and external-store refresh.
- `PersonalCalendar/Features/Settings/CategorySettingsView.swift` — local category management.
- `PersonalCalendar/Features/Settings/NotificationSettingsView.swift` — summary and routine notification status.
- `PersonalCalendar/Features/Settings/BackupSettingsView.swift` — share/export and file importer.

### Tests

- `PersonalCalendarTests/Support/Fakes.swift` — extend foundation fakes with mutation failures, clocks, schedulers, and backup harnesses.
- `PersonalCalendarTests/Services/EventKitMutationTests.swift`
- `PersonalCalendarTests/QuickEntry/RuleBasedQuickEntryParserTests.swift`
- `PersonalCalendarTests/QuickEntry/SaveRouterTests.swift`
- `PersonalCalendarTests/Persistence/CategoryRepositoryTests.swift`
- `PersonalCalendarTests/Notifications/NotificationCoordinatorTests.swift`
- `PersonalCalendarTests/Backup/BackupServiceTests.swift`
- `PersonalCalendarTests/Refresh/AppRefreshCoordinatorTests.swift`
- `PersonalCalendarUITests/CompletionFlowUITests.swift`

---

### Task 1: Add safe event and reminder editing

**Files:**
- Create: `PersonalCalendar/Domain/Recurrence.swift`
- Modify: `PersonalCalendar/Domain/Drafts.swift`
- Modify: `PersonalCalendar/Services/EventKit/CalendarServicing.swift`
- Modify: `PersonalCalendar/Services/EventKit/RemindersServicing.swift`
- Modify: `PersonalCalendar/Services/EventKit/EventKitCalendarService.swift`
- Modify: `PersonalCalendar/Services/EventKit/EventKitRemindersService.swift`
- Modify: `PersonalCalendar/App/DemoEnvironment.swift`
- Create: `PersonalCalendarTests/Services/EventKitMutationTests.swift`

**Interfaces:**
- Consumes: foundation EventKit services and immutable snapshots.
- Produces: `RecurrenceRuleDraft`, `RecurrenceEditScope`, event update/delete, and reminder update/delete methods.

- [ ] **Step 1: Write failing recurrence conversion and mutability tests**

```swift
import EventKit
import XCTest
@testable import PersonalCalendar

final class EventKitMutationTests: XCTestCase {
    func testWeeklyRuleConvertsSelectedWeekdays() throws {
        let draft = RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [2, 6], endDate: nil)
        let rule = try EventKitRecurrenceMapper.makeRule(from: draft)

        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 1)
        XCTAssertEqual(Set(rule.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue) ?? []), [2, 6])
    }

    func testImmutableItemDisablesMutation() {
        let capabilities = ItemCapabilities(allowsModification: false, hasRecurrence: true)
        XCTAssertFalse(capabilities.canEdit)
        XCTAssertFalse(capabilities.canDelete)
        XCTAssertEqual(capabilities.explanation, "This item belongs to a read-only source.")
    }
}
```

- [ ] **Step 2: Run and confirm recurrence types are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/EventKitMutationTests`

Expected: FAIL with missing recurrence and capability types.

- [ ] **Step 3: Define recurrence, detail, and mutation contracts**

```swift
enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable { case daily, weekly, monthly, yearly }

struct RecurrenceRuleDraft: Codable, Equatable, Sendable {
    var frequency: RecurrenceFrequency
    var interval: Int
    var weekdays: Set<Int>
    var endDate: Date?
}

enum RecurrenceEditScope: Equatable, Sendable { case thisOccurrence, futureOccurrences }

struct ItemCapabilities: Equatable, Sendable {
    let allowsModification: Bool
    let hasRecurrence: Bool
    var canEdit: Bool { allowsModification }
    var canDelete: Bool { allowsModification }
    var explanation: String? { allowsModification ? nil : "This item belongs to a read-only source." }
}

```

Add these required methods directly to `CalendarServicing`:

```swift
func event(id: String) -> CalendarEventSnapshot?
func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws
func deleteEvent(id: String, scope: RecurrenceEditScope) throws
```

Add required reminder methods:

```swift
func reminder(id: String) -> ReminderSnapshot?
func updateReminder(id: String, draft: ReminderDraft) throws
func deleteReminder(id: String) throws
```

Add `invalidRecurrence` and `recurringReminderRequiresDueDate` to `DraftValidationError`.

Replace the foundation draft declarations with these backward-compatible initializers. Require a due date when a reminder recurrence rule is present.

```swift
struct EventDraft: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String?
    var notes: String?
    var location: String?
    var url: URL?
    var alarmOffsets: [TimeInterval]
    var recurrence: RecurrenceRuleDraft?

    init(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String?, notes: String? = nil, location: String? = nil, url: URL? = nil, alarmOffsets: [TimeInterval] = [], recurrence: RecurrenceRuleDraft? = nil) {
        self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay; self.calendarID = calendarID
        self.notes = notes; self.location = location; self.url = url; self.alarmOffsets = alarmOffsets; self.recurrence = recurrence
    }
}

struct ReminderDraft: Equatable, Sendable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var dueHasTime: Bool
    var priority: Int
    var listID: String?
    var alarmDate: Date?
    var recurrence: RecurrenceRuleDraft?

    init(title: String, notes: String?, dueDate: Date?, dueHasTime: Bool = false, priority: Int, listID: String?, alarmDate: Date? = nil, recurrence: RecurrenceRuleDraft? = nil) {
        self.title = title; self.notes = notes; self.dueDate = dueDate; self.dueHasTime = dueHasTime; self.priority = priority; self.listID = listID
        self.alarmDate = alarmDate; self.recurrence = recurrence
    }
}
```

Add these defaulted fields to the foundation snapshots so existing fixtures keep compiling and editors can round-trip all supported values:

```swift
// CalendarEventSnapshot
var notes: String? = nil
var location: String? = nil
var url: URL? = nil
var alarmOffsets: [TimeInterval] = []
var recurrence: RecurrenceRuleDraft? = nil

// ReminderSnapshot
var alarmDate: Date? = nil
var recurrence: RecurrenceRuleDraft? = nil
```

Update `CalendarEventSnapshot.init(event:)` and `ReminderSnapshot.init(reminder:)` to map these values. Map the first supported EventKit recurrence rule into `RecurrenceRuleDraft`; if a rule uses a pattern the editor cannot represent, keep `hasRecurrence = true`, display its summary read-only, and require the user to replace it explicitly before changing that recurrence pattern.

Extend the foundation fakes in `PersonalCalendarTests/Support/Fakes.swift` with the new protocol requirements and deterministic failure injection:

```swift
enum SampleError: Error { case saveFailed }

extension EventDraft {
    static var sampleDentist: EventDraft {
        .init(title: "Dentist", start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 3_700), isAllDay: false, calendarID: "home")
    }
}

struct EventMutationCall: Equatable {
    let id: String
    let draft: EventDraft
    let scope: RecurrenceEditScope
}

// Add these members to FakeCalendarService.
var updateError: Error?
var eventByID: [String: CalendarEventSnapshot] = [:]
var updateCalls: [EventMutationCall] = []
var deleteCalls: [(String, RecurrenceEditScope)] = []
convenience init(access: AccessState, updateError: Error?) {
    self.init(access: access)
    self.updateError = updateError
}
func event(id: String) -> CalendarEventSnapshot? { eventByID[id] }
func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws {
    if let updateError { throw updateError }
    updateCalls.append(.init(id: id, draft: draft, scope: scope))
}
func deleteEvent(id: String, scope: RecurrenceEditScope) throws { deleteCalls.append((id, scope)) }

// Add the corresponding members to FakeRemindersService.
var reminderByID: [String: ReminderSnapshot] = [:]
var updateReminderCalls: [(String, ReminderDraft)] = []
var deleteReminderCalls: [String] = []
func reminder(id: String) -> ReminderSnapshot? { reminderByID[id] }
func updateReminder(id: String, draft: ReminderDraft) throws { updateReminderCalls.append((id, draft)) }
func deleteReminder(id: String) throws { deleteReminderCalls.append(id) }
```

Extend the in-app demo services with the same required methods. They look up their value snapshots by identifier, replace snapshots on update, and remove snapshots on delete; they never call EventKit. This keeps every UI test path deterministic after the protocols grow.

- [ ] **Step 4: Implement EventKit mutations with explicit spans**

```swift
private extension RecurrenceEditScope {
    var eventKitSpan: EKSpan {
        switch self {
        case .thisOccurrence: .thisEvent
        case .futureOccurrences: .futureEvents
        }
    }
}

enum EventKitRecurrenceMapper {
    static func makeRule(from draft: RecurrenceRuleDraft) throws -> EKRecurrenceRule {
        guard draft.interval > 0, draft.weekdays.allSatisfy((1...7).contains) else { throw DraftValidationError.invalidRecurrence }
        let frequency: EKRecurrenceFrequency = switch draft.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let weekdays = draft.weekdays.sorted().compactMap(EKWeekday.init(rawValue:)).map(EKRecurrenceDayOfWeek.init)
        let end = draft.endDate.map(EKRecurrenceEnd.init(end:))
        return EKRecurrenceRule(recurrenceWith: frequency, interval: draft.interval, daysOfTheWeek: weekdays.isEmpty ? nil : weekdays, daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }
}

func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws {
    guard let event = store.event(withIdentifier: id), event.calendar.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
    try EventDraftValidator.validate(draft)
    try event.apply(draft, store: store)
    try store.save(event, span: scope.eventKitSpan, commit: true)
}

func deleteEvent(id: String, scope: RecurrenceEditScope) throws {
    guard let event = store.event(withIdentifier: id), event.calendar.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
    try store.remove(event, span: scope.eventKitSpan, commit: true)
}

func updateReminder(id: String, draft: ReminderDraft) throws {
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.calendar.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
    try ReminderDraftValidator.validate(draft)
    try reminder.apply(draft, store: store)
    try store.save(reminder, commit: true)
}

func deleteReminder(id: String) throws {
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.calendar.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
    try store.remove(reminder, commit: true)
}

private extension EKEvent {
    func apply(_ draft: EventDraft, store: EKEventStore) throws {
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        startDate = draft.start
        endDate = draft.end
        isAllDay = draft.isAllDay
        notes = draft.notes
        location = draft.location
        url = draft.url
        alarms = draft.alarmOffsets.map(EKAlarm.init(relativeOffset:))
        recurrenceRules = try draft.recurrence.map { [try EventKitRecurrenceMapper.makeRule(from: $0)] }
        if let id = draft.calendarID, let destination = store.calendars(for: .event).first(where: { $0.calendarIdentifier == id }) {
            guard destination.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            calendar = destination
        }
    }
}

private extension EKReminder {
    func apply(_ draft: ReminderDraft, store: EKEventStore) throws {
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = draft.notes
        priority = draft.priority
        if let dueDate = draft.dueDate {
            let requested: Set<Calendar.Component> = draft.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            var components = Calendar.current.dateComponents(requested, from: dueDate)
            components.calendar = .current
            components.timeZone = .current
            dueDateComponents = components
        } else {
            dueDateComponents = nil
        }
        alarms = draft.alarmDate.map { [EKAlarm(absoluteDate: $0)] }
        recurrenceRules = try draft.recurrence.map { [try EventKitRecurrenceMapper.makeRule(from: $0)] }
        if let id = draft.listID, let destination = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == id }) {
            guard destination.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
            calendar = destination
        }
    }
}
```

Map recurrence drafts with `EKRecurrenceRule`. Clear old rules before applying a changed rule. Never synthesize future recurring reminders; after completing one, refetch so EventKit can supply the next incomplete occurrence.

- [ ] **Step 5: Run mutation tests and commit**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/EventKitMutationTests`

Run: `xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`

Expected: PASS.

Run: `git add PersonalCalendar/Domain PersonalCalendar/Services/EventKit PersonalCalendar/App/DemoEnvironment.swift PersonalCalendarTests/Services/EventKitMutationTests.swift PersonalCalendarTests/Support/Fakes.swift`

Run: `git commit -m "feat: add recurrence-aware item editing"`

---

### Task 2: Build event and task editors with draft retention

**Files:**
- Create: `PersonalCalendar/Features/EventEditor/EventEditorViewModel.swift`
- Create: `PersonalCalendar/Features/EventEditor/EventEditorView.swift`
- Create: `PersonalCalendar/Features/Tasks/TaskEditorViewModel.swift`
- Create: `PersonalCalendar/Features/Tasks/TaskEditorView.swift`
- Modify: `PersonalCalendar/Features/Calendar/DayTrayView.swift`
- Modify: `PersonalCalendar/Features/Today/TodayView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Modify: `PersonalCalendarTests/Features/FeatureViewModelTests.swift`

**Interfaces:**
- Consumes: mutation methods from Task 1 and settings defaults.
- Produces: retained event/task drafts, recurrence scope confirmation, and user-facing retry/delete flows.

- [ ] **Step 1: Write failing retained-draft and recurring-scope tests**

```swift
@MainActor
func testFailedEventSaveKeepsDraft() async {
    let service = FakeCalendarService(access: .granted, updateError: SampleError.saveFailed)
    let draft = EventDraft.sampleDentist
    let subject = EventEditorViewModel(mode: .edit(id: "event", hasRecurrence: false), draft: draft, service: service)

    await subject.save()

    XCTAssertEqual(subject.draft, draft)
    XCTAssertEqual(subject.errorMessage, "Your event was not saved. You can try again.")
}

@MainActor
func testRecurringEventRequestsScopeBeforeDelete() {
    let subject = EventEditorViewModel(mode: .edit(id: "event", hasRecurrence: true), draft: .sampleDentist, service: FakeCalendarService(access: .granted))
    subject.requestDelete()
    XCTAssertEqual(subject.pendingConfirmation, .deleteRecurring)
}
```

- [ ] **Step 2: Run and confirm editor models are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests`

Expected: FAIL with missing editor models.

- [ ] **Step 3: Implement explicit editor state machines**

```swift
enum EventEditorMode: Equatable { case create, edit(id: String, hasRecurrence: Bool) }
enum EventEditorConfirmation: Equatable { case saveRecurring, deleteSingle, deleteRecurring }

@MainActor
@Observable
final class EventEditorViewModel {
    let mode: EventEditorMode
    var draft: EventDraft
    var pendingConfirmation: EventEditorConfirmation?
    private(set) var errorMessage: String?
    private(set) var didSave = false
    private(set) var didDelete = false
    private let service: any CalendarServicing

    init(mode: EventEditorMode, draft: EventDraft, service: any CalendarServicing) {
        self.mode = mode
        self.draft = draft
        self.service = service
    }

    func requestSave() async {
        if case let .edit(_, hasRecurrence) = mode, hasRecurrence {
            pendingConfirmation = .saveRecurring
        } else {
            await save()
        }
    }

    func requestDelete() {
        if case let .edit(_, hasRecurrence) = mode, hasRecurrence {
            pendingConfirmation = .deleteRecurring
        } else {
            pendingConfirmation = .deleteSingle
        }
    }

    func save(scope: RecurrenceEditScope = .thisOccurrence) async {
        do {
            switch mode {
            case .create: _ = try service.createEvent(draft)
            case let .edit(id, _): try service.updateEvent(id: id, draft: draft, scope: scope)
            }
            didSave = true
            errorMessage = nil
        } catch {
            errorMessage = "Your event was not saved. You can try again."
        }
    }

    func delete(scope: RecurrenceEditScope = .thisOccurrence) async {
        guard case let .edit(id, _) = mode else { return }
        do {
            try service.deleteEvent(id: id, scope: scope)
            didDelete = true
            errorMessage = nil
        } catch {
            errorMessage = "Your event was not deleted. You can try again."
        }
    }
}

enum TaskEditorMode: Equatable { case create, edit(id: String, hasRecurrence: Bool) }

@MainActor
@Observable
final class TaskEditorViewModel {
    let mode: TaskEditorMode
    var draft: ReminderDraft
    private(set) var errorMessage: String?
    private(set) var didSave = false
    private(set) var didDelete = false
    private let service: any RemindersServicing

    init(mode: TaskEditorMode, draft: ReminderDraft, service: any RemindersServicing) {
        self.mode = mode; self.draft = draft; self.service = service
    }

    func save() async {
        do {
            switch mode {
            case .create: _ = try service.createReminder(draft)
            case let .edit(id, _): try service.updateReminder(id: id, draft: draft)
            }
            didSave = true
            errorMessage = nil
        } catch {
            errorMessage = "Your task was not saved. You can try again."
        }
    }

    func delete() async {
        guard case let .edit(id, _) = mode else { return }
        do { try service.deleteReminder(id: id); didDelete = true; errorMessage = nil }
        catch { errorMessage = "Your task was not deleted. You can try again." }
    }
}
```

Implement `TaskEditorViewModel` with the exact public state `var draft: ReminderDraft`, `private(set) var errorMessage: String?`, `private(set) var didSave: Bool`, and `private(set) var didDelete: Bool`; inject `any RemindersServicing`; route create/update/delete by mode; and retain `draft` on every failure. It has no occurrence/future scope prompt because EventKit exposes only the current incomplete recurring reminder. When that reminder has recurrence, the destructive confirmation explicitly says that deleting it removes the repeating reminder, while completing it merely lets EventKit reveal the next occurrence. Forms must disable Save for blank titles or invalid date ranges, hide mutation controls for immutable items, expose every supported field, and use destructive confirmation before delete.

- [ ] **Step 4: Connect editors to agenda rows and run tests**

Open an event editor from Calendar and Today rows and a task editor from Today and Tasks rows. For repeating event changes, offer exactly “This Event” and “This and Future Events.” For read-only items, show the detail view with the explanation from `ItemCapabilities` and no enabled mutation action.

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests`

Expected: PASS.

- [ ] **Step 5: Commit editors**

Run: `git add PersonalCalendar/Features PersonalCalendarTests/Features`

Run: `git commit -m "feat: add safe event and task editors"`

---

### Task 3: Parse quick-entry text on device

**Files:**
- Create: `PersonalCalendar/QuickEntry/QuickEntryPreview.swift`
- Create: `PersonalCalendar/QuickEntry/QuickEntryParsing.swift`
- Create: `PersonalCalendar/QuickEntry/RuleBasedQuickEntryParser.swift`
- Create: `PersonalCalendarTests/QuickEntry/RuleBasedQuickEntryParserTests.swift`

**Interfaces:**
- Consumes: domain drafts, recurrence values, and `LocalDay`.
- Produces: `QuickEntryKind`, `QuickEntryPreview`, `QuickEntryParseContext`, `QuickEntryParsing`, and `RuleBasedQuickEntryParser`.

- [ ] **Step 1: Write failing examples and ambiguity tests**

```swift
import XCTest
@testable import PersonalCalendar

final class RuleBasedQuickEntryParserTests: XCTestCase {
    private var context: QuickEntryParseContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 10))!
        return QuickEntryParseContext(now: now, calendar: calendar, locale: Locale(identifier: "en_SG"))
    }

    func testAppointmentWithDateAndTimeDefaultsToEvent() throws {
        let result = try RuleBasedQuickEntryParser().parse("Dentist Friday at 3pm", context: context)
        XCTAssertEqual(result.kind, .event)
        XCTAssertEqual(result.title, "Dentist")
        XCTAssertEqual(context.calendar.component(.hour, from: result.startDate!), 15)
    }

    func testTwentyFourHourClockDefaultsToEvent() throws {
        let result = try RuleBasedQuickEntryParser().parse("Dentist Friday at 15:00", context: context)
        XCTAssertEqual(result.kind, .event)
        XCTAssertEqual(context.calendar.component(.hour, from: result.startDate!), 15)
    }

    func testActionWithoutDurationDefaultsToTask() throws {
        let result = try RuleBasedQuickEntryParser().parse("Submit report tomorrow", context: context)
        XCTAssertEqual(result.kind, .task)
        XCTAssertEqual(result.title, "Submit report")
    }

    func testHabitLanguageDefaultsToRoutine() throws {
        let result = try RuleBasedQuickEntryParser().parse("Read every night", context: context)
        XCTAssertEqual(result.kind, .routine)
        XCTAssertEqual(result.routineWindow, .evening)
        XCTAssertEqual(result.recurrence?.frequency, .daily)
    }

    func testAmbiguousTextDefaultsToTask() throws {
        XCTAssertEqual(try RuleBasedQuickEntryParser().parse("Call Alex", context: context).kind, .task)
    }

    func testBlankInputIsRejected() {
        XCTAssertThrowsError(try RuleBasedQuickEntryParser().parse("   ", context: context))
    }
}
```

- [ ] **Step 2: Run and confirm parser types are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/RuleBasedQuickEntryParserTests`

Expected: FAIL with missing quick-entry types.

- [ ] **Step 3: Implement the source-neutral preview and parser contract**

```swift
enum QuickEntryKind: String, CaseIterable, Codable, Sendable { case event, task, routine }

struct QuickEntryParseContext: Sendable {
    let now: Date
    let calendar: Calendar
    let locale: Locale
}

struct QuickEntryPreview: Equatable, Sendable {
    var kind: QuickEntryKind
    var title: String
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool
    var dueDate: Date?
    var dueHasTime: Bool
    var routineWindow: RoutineWindow?
    var weekdays: Set<Int>
    var recurrence: RecurrenceRuleDraft?
    var reminderDate: Date?
    var destinationID: String?
    var categoryID: UUID?
}

enum QuickEntryParseError: Error, Equatable { case emptyInput, noUsableTitle }

protocol QuickEntryParsing: Sendable {
    func parse(_ text: String, context: QuickEntryParseContext) throws -> QuickEntryPreview
}
```

- [ ] **Step 4: Implement deterministic rule order**

Implement `RuleBasedQuickEntryParser` in this exact order:

```swift
let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
guard !normalized.isEmpty else { throw QuickEntryParseError.emptyInput }
let recurrenceMatch = RecurrencePhraseParser.match(normalized, calendar: context.calendar)
let detectedDate = recurrenceMatch?.isHabitPhrase == true ? nil : DatePhraseParser.detect(normalized, context: context)
let kind: QuickEntryKind = recurrenceMatch?.isHabitPhrase == true ? .routine : detectedDate?.containsTime == true ? .event : .task
let matchedRanges = (recurrenceMatch?.ranges ?? []) + (detectedDate.map { [$0.range] } ?? [])
let cleanedTitle = TitleCleaner.removeMatchedRanges(from: normalized, ranges: matchedRanges)
guard !cleanedTitle.isEmpty else { throw QuickEntryParseError.noUsableTitle }
let routineDays = recurrenceMatch?.rule.frequency == .daily ? Set(1...7) : (recurrenceMatch?.rule.weekdays ?? [])
return QuickEntryPreview(
    kind: kind,
    title: cleanedTitle,
    startDate: kind == .event ? detectedDate?.date : nil,
    endDate: kind == .event ? detectedDate?.date.addingTimeInterval(3_600) : nil,
    isAllDay: false,
    dueDate: kind == .task ? detectedDate?.date : nil,
    dueHasTime: kind == .task && detectedDate?.containsTime == true,
    routineWindow: kind == .routine ? (recurrenceMatch?.window ?? .anytime) : nil,
    weekdays: kind == .routine ? routineDays : [],
    recurrence: recurrenceMatch?.rule,
    reminderDate: nil,
    destinationID: nil,
    categoryID: nil
)
```

Define the private helpers in the same file with these contracts so the parser has no undeclared collaborator:

```swift
private struct RecurrencePhraseMatch {
    let rule: RecurrenceRuleDraft
    let window: RoutineWindow?
    let isHabitPhrase: Bool
    let ranges: [Range<String.Index>]
}

private struct DetectedDatePhrase {
    let date: Date
    let containsTime: Bool
    let range: Range<String.Index>
}

private enum RecurrencePhraseParser {
    static func match(_ text: String, calendar: Calendar) -> RecurrencePhraseMatch? {
        let candidates: [(String, RoutineWindow?, RecurrenceRuleDraft)] = [
            ("every night", .evening, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("every evening", .evening, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("every morning", .morning, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("every afternoon", .afternoon, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("every day", .anytime, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("daily", .anytime, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("weekdays", .anytime, .init(frequency: .weekly, interval: 1, weekdays: [2, 3, 4, 5, 6], endDate: nil))
        ]
        for candidate in candidates {
            if let range = text.range(of: candidate.0, options: .caseInsensitive) {
                return .init(rule: candidate.2, window: candidate.1, isHabitPhrase: true, ranges: [range])
            }
        }
        let weekdayNames = calendar.weekdaySymbols.enumerated()
        for (offset, name) in weekdayNames {
            if let range = text.range(of: "every \(name)", options: .caseInsensitive) {
                let rule = RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [offset + 1], endDate: nil)
                return .init(rule: rule, window: .anytime, isHabitPhrase: true, ranges: [range])
            }
        }
        return nil
    }
}

private enum DatePhraseParser {
    static func detect(_ text: String, context: QuickEntryParseContext) -> DetectedDatePhrase? {
        var dayDate: Date?
        var dayRange: Range<String.Index>?
        if let range = text.range(of: "tomorrow", options: .caseInsensitive) {
            dayDate = context.calendar.date(byAdding: .day, value: 1, to: context.calendar.startOfDay(for: context.now))
            dayRange = range
        } else if let range = text.range(of: "today", options: .caseInsensitive) {
            dayDate = context.calendar.startOfDay(for: context.now)
            dayRange = range
        } else {
            for (offset, name) in context.calendar.weekdaySymbols.enumerated() {
                if let range = text.range(of: name, options: .caseInsensitive) {
                    let current = context.calendar.component(.weekday, from: context.now)
                    let daysAhead = (offset + 1 - current + 7) % 7
                    dayDate = context.calendar.date(byAdding: .day, value: daysAhead, to: context.calendar.startOfDay(for: context.now))
                    dayRange = range
                    break
                }
            }
        }

        let pattern = #"\b(\d{1,2}):(\d{2})\s*(am|pm)?\b|\b(\d{1,2})\s*(am|pm)\b"#
        let expression = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let clockMatch = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        var clockRange: Range<String.Index>?
        var hour: Int?
        var minute = 0
        if let clockMatch, let fullRange = Range(clockMatch.range, in: text) {
            let hourRange = Range(clockMatch.range(at: 1), in: text) ?? Range(clockMatch.range(at: 4), in: text)
            hour = hourRange.flatMap { Int(text[$0]) }
            if let minuteRange = Range(clockMatch.range(at: 2), in: text) { minute = Int(text[minuteRange]) ?? 0 }
            if let markerRange = Range(clockMatch.range(at: 3), in: text) ?? Range(clockMatch.range(at: 5), in: text) {
                let marker = text[markerRange].lowercased()
                if marker == "pm", hour = (hour ?? 0) % 12 + 12
                if marker == "am", hour = (hour ?? 0) % 12
            }
            clockRange = fullRange
            if minute > 59 || !(0...23).contains(hour ?? -1) { hour = nil; clockRange = nil }
        }

        if dayDate != nil || hour != nil {
            let base = dayDate ?? context.calendar.startOfDay(for: context.now)
            let date = context.calendar.date(bySettingHour: hour ?? 0, minute: minute, second: 0, of: base)!
            let ranges = [dayRange, clockRange].compactMap { $0 }
            let lower = ranges.map(\.lowerBound).min()!
            let upper = ranges.map(\.upperBound).max()!
            let combined = lower..<upper
            return .init(date: date, containsTime: hour != nil, range: combined)
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let date = match.date,
              let range = Range(match.range, in: text) else { return nil }
        let phrase = String(text[range]).lowercased()
        let hasClock = phrase.range(of: #"\b\d{1,2}:\d{2}\b|\b\d{1,2}\s*(am|pm)\b|\b(noon|midnight)\b"#, options: .regularExpression) != nil
        return .init(date: date, containsTime: hasClock, range: range)
    }
}

private enum TitleCleaner {
    static func removeMatchedRanges(from text: String, ranges: [Range<String.Index>]) -> String {
        var result = text
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) { result.removeSubrange(range) }
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+\b(at|on)\b\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

Use `NSDataDetector` for locale-aware dates and explicit case-insensitive patterns for `daily`, `every day`, `weekdays`, weekday names, `every morning`, `every afternoon`, `every evening`, and `every night`. If only a date is found, default to Task. If a date and clock time are found, default to Event with a one-hour duration. If no date or recurrence is found, default to Task. Parsing never reads a network resource.

- [ ] **Step 5: Run all parser tests and commit**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/RuleBasedQuickEntryParserTests`

Expected: PASS.

Run: `git add PersonalCalendar/QuickEntry PersonalCalendarTests/QuickEntry/RuleBasedQuickEntryParserTests.swift`

Run: `git commit -m "feat: parse quick entries on device"`

---

### Task 4: Add editable quick-entry confirmation and save routing

**Files:**
- Create: `PersonalCalendar/QuickEntry/SaveRouter.swift`
- Create: `PersonalCalendar/Features/QuickEntry/QuickEntryViewModel.swift`
- Create: `PersonalCalendar/Features/QuickEntry/QuickEntrySheet.swift`
- Create: `PersonalCalendar/Features/QuickEntry/UniversalQuickEntryModifier.swift`
- Create: `PersonalCalendarTests/QuickEntry/SaveRouterTests.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Create: `PersonalCalendarUITests/CompletionFlowUITests.swift`

**Interfaces:**
- Consumes: `QuickEntryPreview`, parser, all three destination repositories, settings defaults, and writable destination descriptors.
- Produces: `SaveRouter.save(_:)`, universal add button, editable preview, retained failure state, and confirmation-only saving.

- [ ] **Step 1: Write failing routing and failed-save tests**

```swift
import XCTest
@testable import PersonalCalendar

@MainActor
final class SaveRouterTests: XCTestCase {
    func testRoutinePreviewWritesOnlyRoutineStore() async throws {
        let calendar = FakeCalendarService(access: .granted)
        let reminders = FakeRemindersService(access: .granted)
        let routines = FakeRoutineRepository()
        let subject = SaveRouter(calendar: calendar, reminders: reminders, routines: routines)
        let preview = QuickEntryPreview.sampleRoutine

        try await subject.save(preview)

        XCTAssertTrue(calendar.createdDrafts.isEmpty)
        XCTAssertTrue(reminders.createdDrafts.isEmpty)
        XCTAssertEqual(routines.createdDrafts.count, 1)
    }

    func testFailedSaveLeavesPreviewAvailableForRetry() async {
        let subject = QuickEntryViewModel(parser: FakeQuickEntryParser(result: .sampleTask), router: FakeQuickEntrySaver(error: SampleError.saveFailed), contextProvider: { .fixture })
        subject.text = "Submit report tomorrow"
        subject.parse()
        await subject.confirmSave()

        XCTAssertEqual(subject.preview, .sampleTask)
        XCTAssertEqual(subject.errorMessage, "Nothing was saved. Check the details and try again.")
    }
}

extension Calendar {
    static var fixture: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }
}

extension Date {
    static var fixtureMorning: Date {
        Calendar.fixture.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 7))!
    }
}

extension QuickEntryParseContext {
    static var fixture: QuickEntryParseContext {
        .init(now: .fixtureMorning, calendar: .fixture, locale: Locale(identifier: "en_SG"))
    }
}

extension QuickEntryPreview {
    static var sampleTask: QuickEntryPreview {
        .init(kind: .task, title: "Submit report", startDate: nil, endDate: nil, isAllDay: false, dueDate: .fixtureMorning, dueHasTime: false, routineWindow: nil, weekdays: [], recurrence: nil, reminderDate: nil, destinationID: "tasks", categoryID: nil)
    }

    static var sampleRoutine: QuickEntryPreview {
        .init(kind: .routine, title: "Read", startDate: nil, endDate: nil, isAllDay: false, dueDate: nil, dueHasTime: false, routineWindow: .evening, weekdays: [1, 2, 3, 4, 5, 6, 7], recurrence: .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil), reminderDate: nil, destinationID: nil, categoryID: nil)
    }
}

struct FakeQuickEntryParser: QuickEntryParsing {
    let result: QuickEntryPreview
    func parse(_ text: String, context: QuickEntryParseContext) throws -> QuickEntryPreview { result }
}

@MainActor
final class FakeQuickEntrySaver: QuickEntrySaving {
    let error: Error?
    init(error: Error? = nil) { self.error = error }
    func save(_ preview: QuickEntryPreview) async throws -> QuickEntrySaveOutcome { if let error { throw error }; return .saved }
}
```

- [ ] **Step 2: Run and verify save router is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/SaveRouterTests`

Expected: FAIL with missing `SaveRouter` and view model.

- [ ] **Step 3: Implement routing with validation before mutation**

```swift
enum QuickEntrySaveOutcome: Equatable { case saved, savedWithWarning(String) }

@MainActor
protocol QuickEntrySaving {
    func save(_ preview: QuickEntryPreview) async throws -> QuickEntrySaveOutcome
}

@MainActor
struct SaveRouter: QuickEntrySaving {
    let calendar: any CalendarServicing
    let reminders: any RemindersServicing
    let routines: any RoutineRepository

    func save(_ preview: QuickEntryPreview) async throws -> QuickEntrySaveOutcome {
        switch preview.kind {
        case .event:
            _ = try calendar.createEvent(try preview.makeEventDraft())
        case .task:
            _ = try reminders.createReminder(try preview.makeReminderDraft())
        case .routine:
            _ = try routines.create(try preview.makeRoutineDraft())
        }
        return .saved
    }
}

enum QuickEntryConversionError: Error { case blankTitle, missingEventDates, missingRoutineSchedule }

extension QuickEntryPreview {
    func makeEventDraft() throws -> EventDraft {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuickEntryConversionError.blankTitle }
        guard let startDate, let endDate, endDate > startDate else { throw QuickEntryConversionError.missingEventDates }
        return .init(title: title, start: startDate, end: endDate, isAllDay: isAllDay, calendarID: destinationID, alarmOffsets: reminderDate.map { [$0.timeIntervalSince(startDate)] } ?? [], recurrence: recurrence)
    }

    func makeReminderDraft() throws -> ReminderDraft {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuickEntryConversionError.blankTitle }
        return .init(title: title, notes: nil, dueDate: dueDate, dueHasTime: dueHasTime, priority: 0, listID: destinationID, alarmDate: reminderDate, recurrence: recurrence)
    }

    func makeRoutineDraft() throws -> RoutineDraft {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuickEntryConversionError.blankTitle }
        guard let routineWindow, !weekdays.isEmpty else { throw QuickEntryConversionError.missingRoutineSchedule }
        let reminderParts = reminderDate.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        return .init(title: title, weekdays: weekdays, window: routineWindow, reminderHour: reminderParts?.hour, reminderMinute: reminderParts?.minute)
    }
}

enum QuickEntryStage: Equatable { case entry, confirmation, saved }

@MainActor
@Observable
final class QuickEntryViewModel {
    var text = ""
    var preview: QuickEntryPreview?
    private(set) var stage: QuickEntryStage = .entry
    private(set) var errorMessage: String?
    private(set) var warningMessage: String?
    private let parser: any QuickEntryParsing
    private let router: any QuickEntrySaving
    private let contextProvider: () -> QuickEntryParseContext

    init(parser: any QuickEntryParsing, router: any QuickEntrySaving, contextProvider: @escaping () -> QuickEntryParseContext) {
        self.parser = parser; self.router = router; self.contextProvider = contextProvider
    }

    func parse() {
        do { preview = try parser.parse(text, context: contextProvider()); stage = .confirmation; errorMessage = nil; warningMessage = nil }
        catch { errorMessage = "Add a title and try again." }
    }

    func confirmSave() async {
        guard let preview else { return }
        do {
            let outcome = try await router.save(preview)
            if case let .savedWithWarning(message) = outcome { warningMessage = message }
            stage = .saved
            errorMessage = nil
        }
        catch { errorMessage = "Nothing was saved. Check the details and try again." }
    }

    func returnToEntry() { stage = .entry }
}
```

The conversion methods must reject a blank title, missing required dates, invalid event ranges, invalid routine reminder components, and a selected read-only destination before calling a service.

- [ ] **Step 4: Build the two-stage sheet and universal add action**

`QuickEntryViewModel` uses two states: `.entry` and `.confirmation`. Parsing moves to confirmation without saving. Confirmation exposes an editable type picker, title, relevant date/time or routine window, repeat rule, category, reminder, and writable destination. Switching kind preserves the title and compatible date fields, then supplies safe defaults for newly required fields.

Replace the foundation-only “New Event” toolbar action with this universal Add action so there is one creation entry point on every tab. Event, task, and routine editors remain available for detailed editing after creation.

Apply a self-contained modifier to the existing root `TabView`:

```swift
@MainActor
struct UniversalQuickEntryModifier: ViewModifier {
    let makeModel: () -> QuickEntryViewModel
    @State private var showsQuickEntry = false
    @State private var model: QuickEntryViewModel?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                Button {
                    model = makeModel()
                    showsQuickEntry = true
                } label: {
                    Label("Add", systemImage: "plus").labelStyle(.iconOnly)
                }
                .accessibilityLabel("Add event, task, or routine")
                .frame(width: 56, height: 56)
                .background(CalendarTheme.accent, in: Circle())
                .foregroundStyle(.white)
                .padding(.trailing, 20)
            }
            .sheet(isPresented: $showsQuickEntry, onDismiss: { model = nil }) {
                if let model { QuickEntrySheet(model: model) }
            }
    }
}

extension View {
    @MainActor
    func universalQuickEntry(makeModel: @escaping () -> QuickEntryViewModel) -> some View {
        modifier(UniversalQuickEntryModifier(makeModel: makeModel))
    }
}
```

At the end of the existing root `TabView`, call `.universalQuickEntry { QuickEntryViewModel(parser: RuleBasedQuickEntryParser(), router: SaveRouter(calendar: environment.calendar, reminders: environment.reminders, routines: environment.routines), contextProvider: { .init(now: .now, calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent) }) }`.

`QuickEntrySheet` observes `stage`; when it becomes `.saved`, it shows any `warningMessage`, asks the destination views to refresh, and then dismisses. Do not dismiss on save failure.

- [ ] **Step 5: Run unit and UI tests, then commit**

Add UI tests that open Add from each tab, enter “Read every night,” verify Routine is selected, edit the title, confirm, and observe the new routine. Add a failure-mode test that verifies typed text remains after Retry appears.

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/SaveRouterTests -only-testing:PersonalCalendarUITests/CompletionFlowUITests`

Expected: PASS.

Run: `git add PersonalCalendar/QuickEntry PersonalCalendar/Features/QuickEntry PersonalCalendar/App/RootTabView.swift PersonalCalendarTests/QuickEntry PersonalCalendarTests/Support/Fakes.swift PersonalCalendarUITests/CompletionFlowUITests.swift`

Run: `git commit -m "feat: add confirmed universal quick entry"`

---

### Task 5: Persist and display app-defined color categories

**Files:**
- Create: `PersonalCalendar/Persistence/CategoryRecord.swift`
- Create: `PersonalCalendar/Persistence/ExternalCategoryLinkRecord.swift`
- Create: `PersonalCalendar/Persistence/CategoryRepository.swift`
- Create: `PersonalCalendar/Persistence/SwiftDataCategoryRepository.swift`
- Create: `PersonalCalendarTests/Persistence/CategoryRepositoryTests.swift`
- Create: `PersonalCalendar/Features/Settings/CategorySettingsView.swift`
- Modify: `PersonalCalendar/Persistence/RoutineRecord.swift`
- Modify: `PersonalCalendar/Domain/RoutineSnapshot.swift`
- Modify: `PersonalCalendar/Domain/Drafts.swift`
- Modify: `PersonalCalendar/Domain/AgendaItem.swift`
- Modify: `PersonalCalendar/Services/Agenda/AgendaComposer.swift`
- Modify: `PersonalCalendar/QuickEntry/SaveRouter.swift`
- Modify: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/Features/Settings/SettingsView.swift`
- Modify: `PersonalCalendar/Features/EventEditor/EventEditorViewModel.swift`
- Modify: `PersonalCalendar/Features/EventEditor/EventEditorView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TaskEditorViewModel.swift`
- Modify: `PersonalCalendar/Features/Tasks/TaskEditorView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutineEditorView.swift`

**Interfaces:**
- Consumes: SwiftData container, agenda item external identifiers, and quick-entry previews.
- Produces: `CategorySnapshot`, `CategoryRepository`, external metadata links, and `AgendaItem.category`.

- [ ] **Step 1: Write failing category and orphan-link tests**

```swift
import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class CategoryRepositoryTests: XCTestCase {
    func testExternalLinkResolvesWithoutCopyingItemContent() throws {
        let container = try TestContainers.categories()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let categoryID = try subject.create(name: "Health", colorHex: "#3A8D7C")
        try subject.assign(categoryID: categoryID, to: .event, externalID: "event-1")

        XCTAssertEqual(try subject.category(for: .event, externalID: "event-1")?.name, "Health")
        XCTAssertEqual(try subject.linkCount(), 1)
    }

    func testMissingExternalIdentifierCanBeMarkedUnresolvedAndRemoved() throws {
        let container = try TestContainers.categories()
        let subject = SwiftDataCategoryRepository(context: container.mainContext)
        let categoryID = try subject.create(name: "Work", colorHex: "#CB6B4F")
        try subject.assign(categoryID: categoryID, to: .task, externalID: "gone")
        try subject.removeUnresolvedLinks(validItems: Set<ExternalItemKey>())
        XCTAssertEqual(try subject.linkCount(), 0)
    }
}
```

- [ ] **Step 2: Run and confirm category models are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/CategoryRepositoryTests`

Expected: FAIL with missing category models and repository.

- [ ] **Step 3: Implement local-only categories and links**

```swift
@Model
final class CategoryRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, colorHex: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }
}

enum ExternalItemSource: String, Codable, Hashable, Sendable { case event, task }

struct ExternalItemKey: Hashable, Sendable {
    let source: ExternalItemSource
    let externalID: String
}

@Model
final class ExternalCategoryLinkRecord {
    @Attribute(.unique) var key: String
    var sourceRaw: String
    var externalID: String
    var categoryID: UUID

    init(source: ExternalItemSource, externalID: String, categoryID: UUID) {
        key = "\(source.rawValue)|\(externalID)"
        sourceRaw = source.rawValue
        self.externalID = externalID
        self.categoryID = categoryID
    }
}

struct CategorySnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
}

@MainActor
protocol CategoryRepository: AnyObject {
    func list() throws -> [CategorySnapshot]
    func create(name: String, colorHex: String) throws -> UUID
    func update(id: UUID, name: String, colorHex: String) throws
    func delete(id: UUID, reassignedTo replacementID: UUID?) throws
    func assign(categoryID: UUID?, to source: ExternalItemSource, externalID: String) throws
    func category(for source: ExternalItemSource, externalID: String) throws -> CategorySnapshot?
    func removeUnresolvedLinks(validItems: Set<ExternalItemKey>) throws
    func linkCount() throws -> Int
}
```

Add `categoryID: UUID?` to `RoutineRecord` and add `var categoryID: UUID? = nil` to `RoutineSnapshot` and `RoutineDraft` so foundation call sites keep compiling. Validate trimmed names, unique case-insensitive names, and `#RRGGBB` colors. Seed Work, Personal, Health, and Errands only when `AppSettingsStore.didSeedCategories` is false, then set that flag true; deleting all categories must not reseed them. Store no external title, date, notes, or location in a link.

`delete(id:reassignedTo:)` runs in one SwiftData transaction. It updates every routine and external link using the deleted category to the replacement identifier, or clears/removes those assignments when replacement is nil, and only then deletes the category record.

Add a category picker to event, task, and routine editors. Existing event/task editors load their assignment from `CategoryRepository`; after a confirmed EventKit save they assign the known external identifier. New Apple items use the identifier returned by creation. Routine editors bind directly to `RoutineDraft.categoryID`. A category-link failure never repeats the EventKit mutation; show “The item was saved, but its app color was not applied” and allow category reassignment from the saved item's detail screen.

Add this persisted flag to `AppSettingsStore` using the same `didSet` pattern as the foundation keys:

```swift
var didSeedCategories: Bool {
    didSet { defaults.set(didSeedCategories, forKey: "didSeedCategories") }
}
```

- [ ] **Step 4: Apply categories throughout the app**

Add `var category: CategorySnapshot? = nil` to `AgendaItem` so foundation initializers keep compiling. The composer resolves external links by identifier and routine categories by local routine ID. All-day event rows use a filled category treatment; timed items use a light tint and colored leading mark. Pair every color with the event/task/routine source icon. Category Settings supports create, rename, recolor, reorder, and delete with reassignment or “No Category.”

Inject `CategoryRepository` into `SaveRouter`. After an event or reminder is successfully created, assign its returned external identifier to `preview.categoryID`; pass `preview.categoryID` directly in the expanded `RoutineDraft`. If category assignment fails after an Apple item was created, return `.savedWithWarning("The item was saved, but its app color was not applied.")`; dismiss the sheet as a successful item save and show that warning in the destination view. Never route the same preview through Apple creation again.

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/CategoryRepositoryTests -only-testing:PersonalCalendarTests/AgendaComposerTests`

Expected: PASS.

- [ ] **Step 5: Commit categories**

Run: `git add PersonalCalendar/Persistence PersonalCalendar/Domain PersonalCalendar/Services/Agenda PersonalCalendar/QuickEntry/SaveRouter.swift PersonalCalendar/Features/Settings PersonalCalendar/Features/EventEditor PersonalCalendar/Features/Tasks PersonalCalendar/Features/Routines PersonalCalendar/App PersonalCalendarTests/Persistence PersonalCalendarTests/Services/AgendaComposerTests.swift`

Run: `git commit -m "feat: add local color categories"`

---

### Task 6: Schedule morning summaries and routine reminders

**Files:**
- Create: `PersonalCalendar/Notifications/NotificationScheduling.swift`
- Create: `PersonalCalendar/Notifications/SystemNotificationScheduler.swift`
- Create: `PersonalCalendar/Notifications/NotificationCoordinator.swift`
- Create: `PersonalCalendarTests/Notifications/NotificationCoordinatorTests.swift`
- Modify: `PersonalCalendarTests/Support/Fakes.swift`
- Create: `PersonalCalendar/Features/Settings/NotificationSettingsView.swift`
- Modify: `PersonalCalendar/Settings/AppSettingsStore.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/Features/Settings/SettingsView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesViewModel.swift`

**Interfaces:**
- Consumes: `DayAgenda`, routine schedules, completion state, permission state, and summary preferences.
- Produces: `NotificationScheduling`, `NotificationCoordinator.reschedule(summary:routines:completedDays:now:calendar:)`, and deterministic request identifiers.

- [ ] **Step 1: Write failing horizon, budget, and summary snapshot tests**

```swift
import XCTest
@testable import PersonalCalendar

@MainActor
final class NotificationCoordinatorTests: XCTestCase {
    func testRoutineRequestsStayWithinHorizonAndBudget() async {
        let scheduler = FakeNotificationScheduler()
        let subject = NotificationCoordinator(scheduler: scheduler, maximumRoutineRequests: 48, horizonDays: 14)

        await subject.reschedule(summary: nil, routines: RoutineSnapshot.manyDaily(count: 10), completedDays: [:], now: .fixtureMorning, calendar: .fixture)

        XCTAssertLessThanOrEqual(scheduler.pending.filter { $0.identifier.hasPrefix("routine|") }.count, 48)
        XCTAssertTrue(scheduler.pending.allSatisfy { $0.fireDate < Calendar.fixture.date(byAdding: .day, value: 15, to: .fixtureMorning)! })
    }

    func testMorningSummaryUsesPassedSnapshot() async {
        let scheduler = FakeNotificationScheduler()
        let subject = NotificationCoordinator(scheduler: scheduler, maximumRoutineRequests: 48, horizonDays: 14)
        let agenda = DayAgenda.fixture(eventCount: 2, taskCount: 1, routineCount: 1)

        await subject.reschedule(summary: .init(enabled: true, hour: 8, minute: 0, day: .init(year: 2026, month: 8, day: 24), agenda: agenda, showsNextTitle: false), routines: [], completedDays: [:], now: .fixtureMorning, calendar: .fixture)

        XCTAssertEqual(scheduler.pending.first { $0.identifier == "morning-summary" }?.body, "2 events, 1 task, and 1 routine today.")
    }
}

extension RoutineSnapshot {
    static func manyDaily(count: Int) -> [RoutineSnapshot] {
        (0..<count).map { index in
            .init(id: UUID(), title: "Routine \(index)", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .morning, reminderHour: 9, reminderMinute: index % 60, isPaused: false, isArchived: false, categoryID: nil)
        }
    }
}

extension DayAgenda {
    static func fixture(eventCount: Int, taskCount: Int, routineCount: Int) -> DayAgenda {
        let events = (0..<eventCount).map { AgendaItem(id: "event-\($0)", title: "Event \($0)", source: .event, placement: .allDay, sortDate: nil, priority: 0, isCompleted: false, allowsModification: true, category: nil) }
        let tasks = (0..<taskCount).map { AgendaItem(id: "task-\($0)", title: "Task \($0)", source: .task, placement: .unscheduled, sortDate: nil, priority: 0, isCompleted: false, allowsModification: true, category: nil) }
        let routines = (0..<routineCount).map { AgendaItem(id: "routine-\($0)", title: "Routine \($0)", source: .routine, placement: .window(.morning), sortDate: .fixtureMorning, priority: 0, isCompleted: false, allowsModification: true, category: nil) }
        return .init(allDay: events, scheduled: routines, priority: tasks)
    }
}

@MainActor
final class FakeNotificationScheduler: NotificationScheduling {
    var pending: [LocalNotificationRequest] = []
    func pendingRequests() async -> [LocalNotificationRequest] { pending }
    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws { pending = requests }
}
```

- [ ] **Step 2: Run and verify notification types are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/NotificationCoordinatorTests`

Expected: FAIL with missing notification types.

- [ ] **Step 3: Define scheduler values and system adapter**

```swift
struct LocalNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}

@MainActor
protocol NotificationScheduling: AnyObject {
    func pendingRequests() async -> [LocalNotificationRequest]
    func replaceAppRequests(with requests: [LocalNotificationRequest]) async throws
}

struct MorningSummaryInput: Sendable {
    let enabled: Bool
    let hour: Int
    let minute: Int
    let day: LocalDay
    let agenda: DayAgenda
    let showsNextTitle: Bool
}
```

`SystemNotificationScheduler` maps values to `UNMutableNotificationContent`, `UNCalendarNotificationTrigger(repeats: false)`, and `UNNotificationRequest`. Remove only identifiers owned by this app: `morning-summary` and the `routine|` prefix.

Do not create local-notification copies of Apple event or reminder alarms. Those alarms stay on their `EKEvent` or `EKReminder` and are delivered by Apple's Calendar or Reminders system behavior.

- [ ] **Step 4: Implement coordinator policy and Settings**

Implement the policy in one coordinator:

```swift
@MainActor
final class NotificationCoordinator {
    private let scheduler: any NotificationScheduling
    private let maximumRoutineRequests: Int
    private let horizonDays: Int
    private(set) var errorMessage: String?
    private(set) var deferredRoutineRequestCount = 0

    init(scheduler: any NotificationScheduling, maximumRoutineRequests: Int = 48, horizonDays: Int = 14) {
        self.scheduler = scheduler
        self.maximumRoutineRequests = maximumRoutineRequests
        self.horizonDays = horizonDays
    }

    func reschedule(summary: MorningSummaryInput?, routines: [RoutineSnapshot], completedDays: [UUID: Set<LocalDay>], now: Date, calendar: Calendar) async {
        var requests: [LocalNotificationRequest] = []
        if let summary, summary.enabled {
            let fireDate = calendar.date(bySettingHour: summary.hour, minute: summary.minute, second: 0, of: summary.day.startDate(in: calendar))!
            if fireDate > now {
                let items = summary.agenda.allDay + summary.agenda.scheduled + summary.agenda.priority
                let eventCount = items.filter { $0.source == .event }.count
                let taskCount = items.filter { $0.source == .task }.count
                let routineCount = items.filter { $0.source == .routine }.count
                var body = "\(eventCount) events, \(taskCount) task\(taskCount == 1 ? "" : "s"), and \(routineCount) routine\(routineCount == 1 ? "" : "s") today."
                if summary.showsNextTitle, let next = summary.agenda.scheduled.first { body += " Next: \(next.title)." }
                requests.append(.init(identifier: "morning-summary", title: "Your day", body: body, fireDate: fireDate))
            }
        }

        var routineRequests: [LocalNotificationRequest] = []
        for offset in 0..<horizonDays {
            let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            let day = LocalDay(date: date, calendar: calendar)
            let weekday = calendar.component(.weekday, from: date)
            for routine in routines where !routine.isPaused && !routine.isArchived && routine.weekdays.contains(weekday) {
                guard let hour = routine.reminderHour, let minute = routine.reminderMinute, completedDays[routine.id, default: []].contains(day) == false else { continue }
                let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
                guard fireDate > now else { continue }
                let identifier = "routine|\(routine.id.uuidString)|\(day.year)-\(day.month)-\(day.day)"
                routineRequests.append(.init(identifier: identifier, title: routine.title, body: "A gentle reminder for your routine.", fireDate: fireDate))
            }
        }
        let sortedRoutineRequests = routineRequests.sorted { $0.fireDate < $1.fireDate }
        deferredRoutineRequestCount = max(0, sortedRoutineRequests.count - maximumRoutineRequests)
        requests.append(contentsOf: sortedRoutineRequests.prefix(maximumRoutineRequests))
        do { try await scheduler.replaceAppRequests(with: requests); errorMessage = nil }
        catch { errorMessage = "Notifications could not be updated. Open Settings and try again." }
    }
}
```

Generate the summary input for the next selected summary time: use today's refreshed agenda when the time has not passed, otherwise fetch tomorrow's agenda before scheduling. Schedule a routine only if it has an explicit reminder hour/minute; broad windows alone do not create alerts. When `showsNextTitle` is true, append the next timed item's title to the summary body; otherwise keep only counts.

Add these persisted notification properties to `AppSettingsStore` and validate hours `0...23` and minutes `0...59` in Settings before assignment:

```swift
var morningSummaryEnabled: Bool { didSet { defaults.set(morningSummaryEnabled, forKey: "morningSummaryEnabled") } }
var morningSummaryHour: Int { didSet { defaults.set(morningSummaryHour, forKey: "morningSummaryHour") } }
var morningSummaryMinute: Int { didSet { defaults.set(morningSummaryMinute, forKey: "morningSummaryMinute") } }
var showNextItemOnLockScreen: Bool { didSet { defaults.set(showNextItemOnLockScreen, forKey: "showNextItemOnLockScreen") } }
```

After routine create, update, complete, pause, archive, or delete, call the coordinator again. Settings must show when later routine alerts exceed the pending budget and state that they will be filled during a future refresh.

- [ ] **Step 5: Run tests and commit notifications**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/NotificationCoordinatorTests`

Expected: PASS.

Run: `git add PersonalCalendar/Notifications PersonalCalendar/Settings/AppSettingsStore.swift PersonalCalendar/Features/Settings PersonalCalendar/Features/Routines/RoutinesViewModel.swift PersonalCalendar/App/AppEnvironment.swift PersonalCalendarTests/Notifications PersonalCalendarTests/Support/Fakes.swift`

Run: `git commit -m "feat: add calm local notifications"`

---

### Task 7: Export and transactionally restore app-owned data

**Files:**
- Create: `PersonalCalendar/Backup/BackupEnvelope.swift`
- Create: `PersonalCalendar/Backup/BackupService.swift`
- Create: `PersonalCalendarTests/Backup/BackupServiceTests.swift`
- Modify: `PersonalCalendarTests/Support/Fakes.swift`
- Create: `PersonalCalendar/Features/Settings/BackupSettingsView.swift`
- Modify: `PersonalCalendar/Features/Settings/SettingsView.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`

**Interfaces:**
- Consumes: local repositories, `AppSettingsStore`, and `ModelContext`.
- Produces: version-1 JSON backup data, `BackupService.exportData()`, `BackupService.restore(data:)`, and Settings share/import flows.

- [ ] **Step 1: Write failing round-trip, rejection, and rollback tests**

```swift
import XCTest
@testable import PersonalCalendar

@MainActor
final class BackupServiceTests: XCTestCase {
    func testRoundTripRestoresOnlyAppOwnedData() throws {
        let harness = try BackupHarness.seeded()
        let data = try harness.service.exportData()
        try harness.clearLocalData()

        try harness.service.restore(data: data)

        XCTAssertEqual(try harness.routines.list(includeArchived: true).map(\.title), ["Read"])
        XCTAssertEqual(try harness.categories.list().map(\.name), ["Personal"])
        XCTAssertEqual(harness.calendar.createdDrafts.count, 0)
        XCTAssertEqual(harness.reminders.createdDrafts.count, 0)
    }

    func testUnsupportedVersionDoesNotChangeExistingData() throws {
        let harness = try BackupHarness.seeded()
        let invalid = Data("{\"version\":99,\"exportedAt\":0}".utf8)
        XCTAssertThrowsError(try harness.service.restore(data: invalid))
        XCTAssertEqual(try harness.routines.list(includeArchived: true).map(\.title), ["Read"])
    }
}

@MainActor
struct BackupHarness {
    let container: ModelContainer
    let settings: AppSettingsStore
    let routines: SwiftDataRoutineRepository
    let categories: SwiftDataCategoryRepository
    let calendar: FakeCalendarService
    let reminders: FakeRemindersService
    let service: BackupService

    static func seeded() throws -> BackupHarness {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RoutineRecord.self, RoutineCompletionRecord.self, CategoryRecord.self, ExternalCategoryLinkRecord.self, configurations: configuration)
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.didSeedCategories = true
        let routines = SwiftDataRoutineRepository(context: container.mainContext)
        let categories = SwiftDataCategoryRepository(context: container.mainContext)
        _ = try routines.create(.init(title: "Read", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .evening, reminderHour: nil, reminderMinute: nil, categoryID: nil))
        _ = try categories.create(name: "Personal", colorHex: "#3A8D7C")
        let service = BackupService(context: container.mainContext, settings: settings)
        return .init(container: container, settings: settings, routines: routines, categories: categories, calendar: .init(access: .granted), reminders: .init(access: .granted), service: service)
    }

    func clearLocalData() throws {
        for routine in try routines.list(includeArchived: true) { try routines.delete(id: routine.id) }
        for category in try categories.list() { try categories.delete(id: category.id, reassignedTo: nil) }
    }
}
```

- [ ] **Step 2: Run and confirm backup types are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/BackupServiceTests`

Expected: FAIL with missing backup types.

- [ ] **Step 3: Define a versioned envelope with value DTOs only**

```swift
struct BackupEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let exportedAt: Date
    let routines: [RoutineBackup]
    let completions: [CompletionBackup]
    let categories: [CategorySnapshot]
    let categoryLinks: [CategoryLinkBackup]
    let settings: SettingsBackup
}

struct RoutineBackup: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let weekdays: [Int]
    let window: RoutineWindow
    let reminderHour: Int?
    let reminderMinute: Int?
    let categoryID: UUID?
    let isPaused: Bool
    let isArchived: Bool
    let createdAt: Date
}

struct CompletionBackup: Codable, Equatable, Sendable {
    let routineID: UUID
    let day: LocalDay
    let completedAt: Date
}

struct CategoryLinkBackup: Codable, Equatable, Sendable {
    let source: ExternalItemSource
    let externalID: String
    let categoryID: UUID
}

struct SettingsBackup: Codable, Equatable, Sendable {
    let selectedCalendarIDs: Set<String>
    let selectedReminderListIDs: Set<String>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
    let morningSummaryEnabled: Bool
    let morningSummaryHour: Int
    let morningSummaryMinute: Int
    let showNextItemOnLockScreen: Bool
    let didSeedCategories: Bool
    let didCompleteOnboarding: Bool
}

enum BackupError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidData(String)
    case replacementFailed
}

enum BackupValidator {
    static func validate(_ envelope: BackupEnvelope) throws {
        guard envelope.version == 1 else { throw BackupError.unsupportedVersion(envelope.version) }
        guard Set(envelope.routines.map(\.id)).count == envelope.routines.count else { throw BackupError.invalidData("Routine identifiers must be unique.") }
        guard Set(envelope.categories.map(\.id)).count == envelope.categories.count else { throw BackupError.invalidData("Category identifiers must be unique.") }
        guard Set(envelope.categories.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == envelope.categories.count else { throw BackupError.invalidData("Category names must be unique.") }
        guard Set(envelope.completions.map { "\($0.routineID)|\($0.day.year)-\($0.day.month)-\($0.day.day)" }).count == envelope.completions.count else { throw BackupError.invalidData("Routine completions must be unique per day.") }
        guard Set(envelope.categoryLinks.map { "\($0.source.rawValue)|\($0.externalID)" }).count == envelope.categoryLinks.count else { throw BackupError.invalidData("External category links must be unique.") }
        let routineIDs = Set(envelope.routines.map(\.id))
        let categoryIDs = Set(envelope.categories.map(\.id))
        guard envelope.completions.allSatisfy({ routineIDs.contains($0.routineID) }) else { throw BackupError.invalidData("A completion refers to a missing routine.") }
        guard envelope.completions.allSatisfy({ Calendar(identifier: .gregorian).date(from: DateComponents(year: $0.day.year, month: $0.day.month, day: $0.day.day)) != nil }) else { throw BackupError.invalidData("A completion date is invalid.") }
        guard envelope.routines.allSatisfy({ $0.categoryID.map(categoryIDs.contains) ?? true }) else { throw BackupError.invalidData("A routine refers to a missing category.") }
        guard envelope.categoryLinks.allSatisfy({ !$0.externalID.isEmpty && categoryIDs.contains($0.categoryID) }) else { throw BackupError.invalidData("A category link is invalid.") }
        guard envelope.routines.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.weekdays.isEmpty && $0.weekdays.allSatisfy((1...7).contains) }) else { throw BackupError.invalidData("A routine is invalid.") }
        guard envelope.routines.allSatisfy({ value in
            switch (value.reminderHour, value.reminderMinute) {
            case (nil, nil): true
            case let (hour?, minute?): (0...23).contains(hour) && (0...59).contains(minute)
            default: false
            }
        }) else { throw BackupError.invalidData("A routine reminder time is invalid.") }
        guard envelope.categories.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.colorHex.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil }) else { throw BackupError.invalidData("A category is invalid.") }
        guard (0...23).contains(envelope.settings.morningSummaryHour), (0...59).contains(envelope.settings.morningSummaryMinute) else { throw BackupError.invalidData("Summary time is invalid.") }
    }
}

@MainActor
protocol BackupServicing: AnyObject {
    func exportData() throws -> Data
    func restore(data: Data) throws
}

extension AppSettingsStore {
    var backupValue: SettingsBackup {
        .init(
            selectedCalendarIDs: selectedCalendarIDs,
            selectedReminderListIDs: selectedReminderListIDs,
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID,
            morningSummaryEnabled: morningSummaryEnabled,
            morningSummaryHour: morningSummaryHour,
            morningSummaryMinute: morningSummaryMinute,
            showNextItemOnLockScreen: showNextItemOnLockScreen,
            didSeedCategories: didSeedCategories,
            didCompleteOnboarding: didCompleteOnboarding
        )
    }

    func apply(_ value: SettingsBackup) {
        selectedCalendarIDs = value.selectedCalendarIDs
        selectedReminderListIDs = value.selectedReminderListIDs
        defaultCalendarID = value.defaultCalendarID
        defaultReminderListID = value.defaultReminderListID
        morningSummaryEnabled = value.morningSummaryEnabled
        morningSummaryHour = value.morningSummaryHour
        morningSummaryMinute = value.morningSummaryMinute
        showNextItemOnLockScreen = value.showNextItemOnLockScreen
        didSeedCategories = value.didSeedCategories
        didCompleteOnboarding = value.didCompleteOnboarding
    }
}
```

Use ISO-8601 dates, sorted arrays for deterministic output, and `JSONEncoder.OutputFormatting.sortedKeys`. Validate version `1`, unique identifiers, category-link targets, weekday range `1...7`, reminder components, nonblank names, valid colors, and setting ranges before touching SwiftData.

- [ ] **Step 4: Implement all-or-nothing local replacement and UI**

```swift
@MainActor
final class BackupService: BackupServicing {
    private let context: ModelContext
    private let settings: AppSettingsStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(context: ModelContext, settings: AppSettingsStore) {
        self.context = context
        self.settings = settings
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func exportData() throws -> Data {
        let routines = try context.fetch(FetchDescriptor<RoutineRecord>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let completions = try context.fetch(FetchDescriptor<RoutineCompletionRecord>()).sorted { $0.key < $1.key }
        let categories = try context.fetch(FetchDescriptor<CategoryRecord>()).sorted { $0.sortOrder < $1.sortOrder }
        let links = try context.fetch(FetchDescriptor<ExternalCategoryLinkRecord>()).sorted { $0.key < $1.key }
        let envelope = BackupEnvelope(
            version: 1,
            exportedAt: .now,
            routines: routines.map { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: RoutineWindow(rawValue: $0.windowRaw)!, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, categoryID: $0.categoryID, isPaused: $0.isPaused, isArchived: $0.isArchived, createdAt: $0.createdAt) },
            completions: completions.map { .init(routineID: $0.routineID, day: .init(year: $0.year, month: $0.month, day: $0.day), completedAt: $0.completedAt) },
            categories: categories.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, sortOrder: $0.sortOrder) },
            categoryLinks: links.map { .init(source: ExternalItemSource(rawValue: $0.sourceRaw)!, externalID: $0.externalID, categoryID: $0.categoryID) },
            settings: settings.backupValue
        )
        return try encoder.encode(envelope)
    }

    func restore(data: Data) throws {
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        try BackupValidator.validate(envelope)
        let previousSettings = settings.backupValue
        let previousAutosave = context.autosaveEnabled
        defer { context.autosaveEnabled = previousAutosave }
        do {
            context.autosaveEnabled = false
            try context.transaction {
                try context.delete(model: ExternalCategoryLinkRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: RoutineCompletionRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: RoutineRecord.self, where: nil, includeSubclasses: false)
                try context.delete(model: CategoryRecord.self, where: nil, includeSubclasses: false)
                for value in envelope.routines {
                    let draft = RoutineDraft(title: value.title, weekdays: Set(value.weekdays), window: value.window, reminderHour: value.reminderHour, reminderMinute: value.reminderMinute, categoryID: value.categoryID)
                    let record = RoutineRecord(id: value.id, draft: draft, createdAt: value.createdAt)
                    record.isPaused = value.isPaused
                    record.isArchived = value.isArchived
                    context.insert(record)
                }
                for value in envelope.completions { context.insert(RoutineCompletionRecord(routineID: value.routineID, day: value.day, completedAt: value.completedAt)) }
                for value in envelope.categories { context.insert(CategoryRecord(id: value.id, name: value.name, colorHex: value.colorHex, sortOrder: value.sortOrder)) }
                for value in envelope.categoryLinks { context.insert(ExternalCategoryLinkRecord(source: value.source, externalID: value.externalID, categoryID: value.categoryID)) }
            }
            settings.apply(envelope.settings)
        } catch {
            context.rollback()
            settings.apply(previousSettings)
            throw BackupError.replacementFailed
        }
    }
}
```

Do not include event or reminder titles, notes, dates, alarms, locations, URLs, or attachments. External category links may include only source, external identifier, and category identifier. Before restore, show counts for routines, completions, categories, and links; state that existing local data will be replaced; require confirmation. Use `ShareLink` for export and `.fileImporter` accepting `UTType.json` for restore.

- [ ] **Step 5: Run tests and commit backup**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/BackupServiceTests`

Expected: PASS, including rollback after injected save failure.

Run: `git add PersonalCalendar/Backup PersonalCalendar/Features/Settings PersonalCalendar/App/AppEnvironment.swift PersonalCalendarTests/Backup PersonalCalendarTests/Support/Fakes.swift`

Run: `git commit -m "feat: add local backup and restore"`

---

### Task 8: Refresh safely after external EventKit changes

**Files:**
- Create: `PersonalCalendar/Refresh/EventStoreChangeMonitor.swift`
- Create: `PersonalCalendar/Refresh/RefreshDebouncing.swift`
- Create: `PersonalCalendar/Refresh/AppRefreshCoordinator.swift`
- Create: `PersonalCalendarTests/Refresh/AppRefreshCoordinatorTests.swift`
- Modify: `PersonalCalendarTests/Support/Fakes.swift`
- Modify: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarViewModel.swift`
- Modify: `PersonalCalendar/Features/Today/TodayViewModel.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksViewModel.swift`

**Interfaces:**
- Consumes: one long-lived `EKEventStore`, feature refresh closures, category repository, and notification coordinator.
- Produces: debounced external-change refresh and foreground refresh without retaining stale EventKit objects.

- [ ] **Step 1: Write failing coalescing and refresh-order tests**

```swift
import XCTest
@testable import PersonalCalendar

@MainActor
final class AppRefreshCoordinatorTests: XCTestCase {
    func testBurstOfStoreChangesCoalescesIntoOneRefresh() async {
        let debouncer = FakeRefreshDebouncer()
        let calls = RefreshCallRecorder()
        let subject = AppRefreshCoordinator(debouncer: debouncer, actions: calls.actions)

        subject.eventStoreDidChange()
        subject.eventStoreDidChange()
        subject.eventStoreDidChange()
        await debouncer.fire()

        XCTAssertEqual(calls.completedRefreshes, 1)
    }

    func testRefreshFetchesBeforeReschedulingSummary() async {
        let calls = RefreshCallRecorder()
        let subject = AppRefreshCoordinator(debouncer: FakeRefreshDebouncer(), actions: calls.actions)
        await subject.refreshNow(reason: .foreground)
        XCTAssertEqual(calls.steps, [.permissions, .sources, .agenda, .categoryCleanup, .notifications])
    }
}

enum RefreshStep: Equatable { case permissions, sources, agenda, categoryCleanup, notifications }

@MainActor
final class RefreshCallRecorder {
    var steps: [RefreshStep] = []
    var completedRefreshes: Int { steps.filter { $0 == .notifications }.count }
    var actions: RefreshActions {
        .init(
            refreshPermissions: { self.steps.append(.permissions) },
            refreshSources: { self.steps.append(.sources) },
            refreshAgenda: { self.steps.append(.agenda) },
            cleanCategoryLinks: { self.steps.append(.categoryCleanup) },
            rescheduleNotifications: { self.steps.append(.notifications) }
        )
    }
}

@MainActor
final class FakeRefreshDebouncer: RefreshDebouncing {
    private var pending: (@MainActor () async -> Void)?
    func schedule(_ operation: @escaping @MainActor () async -> Void) { pending = operation }
    func fire() async { let operation = pending; pending = nil; await operation?() }
}
```

- [ ] **Step 2: Run and confirm refresh coordinator is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/AppRefreshCoordinatorTests`

Expected: FAIL with missing refresh types.

- [ ] **Step 3: Implement monitor and ordered refresh**

```swift
enum RefreshReason: Equatable { case launch, foreground, eventStoreChanged, localMutation }

@MainActor
protocol RefreshDebouncing: AnyObject {
    func schedule(_ operation: @escaping @MainActor () async -> Void)
}

@MainActor
final class TaskRefreshDebouncer: RefreshDebouncing {
    private var task: Task<Void, Never>?

    func schedule(_ operation: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}

struct RefreshActions {
    let refreshPermissions: @MainActor () async -> Void
    let refreshSources: @MainActor () async -> Void
    let refreshAgenda: @MainActor () async -> Void
    let cleanCategoryLinks: @MainActor () async -> Void
    let rescheduleNotifications: @MainActor () async -> Void
}

@MainActor
final class AppRefreshCoordinator {
    private let debouncer: any RefreshDebouncing
    private let actions: RefreshActions

    init(debouncer: any RefreshDebouncing, actions: RefreshActions) {
        self.debouncer = debouncer
        self.actions = actions
    }

    func eventStoreDidChange() {
        debouncer.schedule { [weak self] in await self?.refreshNow(reason: .eventStoreChanged) }
    }

    func refreshNow(reason: RefreshReason) async {
        await actions.refreshPermissions()
        await actions.refreshSources()
        await actions.refreshAgenda()
        await actions.cleanCategoryLinks()
        await actions.rescheduleNotifications()
    }
}

@MainActor
protocol EventStoreChangeMonitoring: AnyObject {
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class EventStoreChangeMonitor: EventStoreChangeMonitoring {
    var onChange: (() -> Void)?
    private var token: NSObjectProtocol?

    func start() {
        token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}
```

The coordinator debounces store-change bursts by 250 milliseconds. Each refresh must: refresh permission states; ask services for new value snapshots instead of reusing prior EventKit objects; refresh visible feature ranges; build `Set<ExternalItemKey>` from both successfully fetched EventKit sources; remove unresolved category links only when every currently granted EventKit source completed successfully; then reschedule the best-effort morning summary and routine requests.

After a successful source-list refresh, intersect saved calendar/list identifiers with identifiers that still exist. If that removes every selected source, select all currently available sources. Clear a saved default destination when it no longer exists or is no longer writable, then use EventKit's current writable default for future creation.

- [ ] **Step 4: Wire lifecycle and failure behavior**

On `.active`, call `refreshNow(reason: .foreground)`. Start the change monitor once at app creation and stop it on dependency teardown. If one source fetch fails, retain that source's last displayed value snapshots for the current session, mark them stale, show Retry, and still refresh available sources. Never keep an `EKEvent`, `EKReminder`, or `EKCalendar` in a view model.

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/AppRefreshCoordinatorTests -only-testing:PersonalCalendarTests/FeatureViewModelTests`

Expected: PASS.

- [ ] **Step 5: Commit refresh behavior**

Run: `git add PersonalCalendar/Refresh PersonalCalendar/App PersonalCalendar/Features/Calendar PersonalCalendar/Features/Today PersonalCalendar/Features/Tasks PersonalCalendarTests/Refresh PersonalCalendarTests/Features PersonalCalendarTests/Support/Fakes.swift`

Run: `git commit -m "feat: refresh after external calendar changes"`

---

### Task 9: Complete accessibility, visual polish, and release verification

**Files:**
- Modify: `PersonalCalendar/DesignSystem/CalendarTheme.swift`
- Modify: `PersonalCalendar/DesignSystem/AgendaRow.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Modify: `PersonalCalendar/Features/Calendar/MonthGridView.swift`
- Modify: `PersonalCalendar/Features/Calendar/DayTrayView.swift`
- Modify: `PersonalCalendar/Features/Today/TodayView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesView.swift`
- Modify: `PersonalCalendar/Features/QuickEntry/QuickEntrySheet.swift`
- Modify: `PersonalCalendar/Features/Settings/SettingsView.swift`
- Modify: `PersonalCalendar/App/DemoEnvironment.swift`
- Modify: `PersonalCalendarUITests/CompletionFlowUITests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: every completed feature and test seam.
- Produces: the complete first-release app and verification evidence.

- [ ] **Step 1: Add failing accessibility-state UI tests**

```swift
func testCalendarWorksWithAccessibilityTextAndReduceMotion() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-reduce-motion", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
    app.launch()

    XCTAssertTrue(app.buttons["Expand day"].waitForExistence(timeout: 3))
    app.buttons["Expand day"].tap()
    XCTAssertTrue(app.buttons["Collapse day"].exists)
    XCTAssertTrue(app.buttons["Collapse day"].isHittable)
    XCTAssertTrue(app.tabBars.buttons["Routines"].isHittable)
}

func testReadOnlyDemoEventExplainsDisabledEditing() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-read-only-event"]
    app.launch()
    app.staticTexts["Public holiday"].tap()
    XCTAssertTrue(app.staticTexts["This item belongs to a read-only source."].exists)
    XCTAssertFalse(app.buttons["Delete Event"].isEnabled)
}
```

- [ ] **Step 2: Run the full UI suite and record failures before polishing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests`

Expected: new tests FAIL until accessibility labels, adaptive layouts, and read-only details are complete.

- [ ] **Step 3: Apply the final semantic visual system**

Use semantic background tiers and dynamic category colors. Each agenda row must expose one combined accessibility element with this order:

```text
[source], [title], [all day or formatted time/window], [completion state], [read-only state when applicable]
```

Month dates announce:

```text
[full localized date], [today when true], [selected when true], [number of visible items]
```

Use `ViewThatFits`, multiline text, and flexible frames instead of fixed text heights. Every icon-only control gets an accessibility label. Every swipe action has a visible menu alternative. Color marks are paired with source icons. All destructive actions require confirmation. Reduce Motion uses no spring or geometry-matched transition.

When demo launch arguments contain `-read-only-event`, replace the normal demo event with “Public holiday,” set its snapshot `allowsModification` to false, and expose no writable mutation actions. When arguments contain `-reduce-motion`, inject a demo accessibility override so the UI test exercises the same no-spring branch as the system Reduce Motion environment value.

- [ ] **Step 4: Run automated release checks**

Run: `xcodegen generate`

Run: `xcodebuild clean build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Run: `git diff --check`

Expected: build PASS, every unit/UI test PASS, and `git diff --check` produces no output.

- [ ] **Step 5: Perform the real-iPhone acceptance pass**

Install with Xcode automatic signing and a connected iPhone running iOS 17 or later. Verify this exact matrix:

```text
Calendar permission: allow, deny, then enable in Settings.
Reminders permission: allow, deny, then enable in Settings.
Notifications permission: deny and confirm all planning features remain usable.
External edit: change one event in Apple Calendar and one task in Reminders, foreground the app, and confirm refresh.
Recurrence: edit/delete one event occurrence and future occurrences separately.
Recurring reminder: complete the current occurrence and confirm the next supplied occurrence appears after refresh.
Quick entry: save event, task, and routine examples after editing their previews.
Save failure: revoke access during an open draft and confirm the draft remains with Retry.
Notifications: confirm the next morning snapshot and one routine reminder fire at the selected local times.
Backup: export, change local routines/categories, restore, and confirm Apple items are untouched.
Accessibility: VoiceOver, largest text, Dark Mode, and Reduce Motion complete core flows.
```

If physical-device signing is unavailable, record that as the only external verification dependency; do not mark the acceptance criterion complete from simulator evidence alone.

- [ ] **Step 6: Update documentation and commit completion**

Add to `README.md`:

```markdown
## Data ownership

- Events remain in Apple Calendar.
- Tasks remain in Apple Reminders.
- Routines, completion history, categories, and preferences stay on this iPhone.
- A manual backup contains only app-owned data.

## Device installation

Open `PersonalCalendar.xcodeproj`, choose your Personal Team under Signing & Capabilities, connect an iPhone running iOS 17 or later, and press Run. A free Personal Team installation may need to be renewed periodically.
```

Run: `git add PersonalCalendar PersonalCalendarTests PersonalCalendarUITests README.md project.yml PersonalCalendar.xcodeproj`

Run: `git commit -m "feat: complete personal calendar first release"`

Run: `git status --short`

Expected: no output.

## Completion exit criteria

- Single and repeating events can be created, viewed, edited, and deleted with correct recurrence scope.
- Reminders can be created, viewed, edited, completed, and deleted without fabricating future recurrence occurrences.
- Read-only EventKit items remain visible and explain why mutation is unavailable.
- Universal quick entry parses on device, always shows an editable preview, and saves only after confirmation.
- Failed saves retain all entered details and offer Retry.
- Local categories color the combined interface without changing Apple's native colors or copying Apple item content.
- Morning summary content is accurately described as a scheduling-time snapshot.
- Routine notifications stay within the 14-day horizon and 48-request budget.
- Version-1 backup round-trips all and only app-owned data, and a failed restore rolls back.
- External Calendar and Reminders changes refresh without retaining stale EventKit reference objects.
- Core flows pass unit tests, UI tests, VoiceOver, large-text, Dark Mode, and Reduce Motion checks.
- The real-iPhone acceptance matrix is complete or its signing/device dependency is explicitly reported.

## Primary Apple references

- [EventKit](https://developer.apple.com/documentation/eventkit)
- [Accessing the Event Store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [Creating a Recurring Event or Reminder](https://developer.apple.com/documentation/eventkit/creating-a-recurring-event)
- [UserNotifications](https://developer.apple.com/documentation/usernotifications)
- [SwiftData ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext)
- [SwiftData Transaction](https://developer.apple.com/documentation/swiftdata/modelcontext/transaction(block:))
