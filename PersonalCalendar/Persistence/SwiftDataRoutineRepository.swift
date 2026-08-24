import Foundation
import SwiftData

@MainActor
final class SwiftDataRoutineRepository: RoutineRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func list(includeArchived: Bool) throws -> [RoutineSnapshot] {
        var descriptor = FetchDescriptor<RoutineRecord>(sortBy: [SortDescriptor(\RoutineRecord.createdAt)])
        if !includeArchived {
            descriptor.predicate = #Predicate { !$0.isArchived }
        }
        return try context.fetch(descriptor).map(Self.snapshot)
    }

    func create(_ draft: RoutineDraft) throws -> UUID {
        let draft = try normalized(draft)
        let record = RoutineRecord(draft: draft)
        context.insert(record)
        try context.save()
        return record.id
    }

    func update(id: UUID, draft: RoutineDraft) throws {
        let draft = try normalized(draft)
        let record = try routine(id: id)
        record.title = draft.title
        record.weekdays = draft.weekdays.sorted()
        record.windowRaw = draft.window.rawValue
        record.reminderHour = draft.reminderHour
        record.reminderMinute = draft.reminderMinute
        try context.save()
    }

    func setPaused(id: UUID, paused: Bool) throws {
        try routine(id: id).isPaused = paused
        try context.save()
    }

    func setArchived(id: UUID, archived: Bool) throws {
        try routine(id: id).isArchived = archived
        try context.save()
    }

    func delete(id: UUID) throws {
        let record = try routine(id: id)
        let completionDescriptor = FetchDescriptor<RoutineCompletionRecord>(
            predicate: #Predicate { $0.routineID == id }
        )
        for completion in try context.fetch(completionDescriptor) {
            context.delete(completion)
        }
        context.delete(record)
        try context.save()
    }

    func setCompleted(routineID: UUID, day: LocalDay, completed: Bool) throws {
        _ = try routine(id: routineID)
        let key = RoutineCompletionRecord.key(routineID: routineID, day: day)
        let descriptor = FetchDescriptor<RoutineCompletionRecord>(
            predicate: #Predicate { $0.key == key }
        )
        let records = try context.fetch(descriptor)

        if completed, records.isEmpty {
            context.insert(RoutineCompletionRecord(routineID: routineID, day: day))
        } else if !completed {
            for record in records {
                context.delete(record)
            }
        }
        try context.save()
    }

    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool {
        let key = RoutineCompletionRecord.key(routineID: routineID, day: day)
        let descriptor = FetchDescriptor<RoutineCompletionRecord>(
            predicate: #Predicate { $0.key == key }
        )
        return try !context.fetch(descriptor).isEmpty
    }

    func completedDays(routineID: UUID) throws -> Set<LocalDay> {
        let descriptor = FetchDescriptor<RoutineCompletionRecord>(
            predicate: #Predicate { $0.routineID == routineID }
        )
        return Set(try context.fetch(descriptor).map { record in
            LocalDay(year: record.year, month: record.month, day: record.day)
        })
    }

    private func routine(id: UUID) throws -> RoutineRecord {
        let descriptor = FetchDescriptor<RoutineRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            throw RoutineRepositoryError.routineNotFound
        }
        return record
    }

    private func normalized(_ draft: RoutineDraft) throws -> RoutineDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let validReminder = switch (draft.reminderHour, draft.reminderMinute) {
        case (nil, nil): true
        case let (.some(hour), .some(minute)): (0...23).contains(hour) && (0...59).contains(minute)
        default: false
        }

        guard !title.isEmpty,
              !draft.weekdays.isEmpty,
              draft.weekdays.allSatisfy({ (1...7).contains($0) }),
              validReminder else {
            throw RoutineRepositoryError.invalidDraft
        }

        return RoutineDraft(
            title: title,
            weekdays: draft.weekdays,
            window: draft.window,
            reminderHour: draft.reminderHour,
            reminderMinute: draft.reminderMinute
        )
    }

    private static func snapshot(from record: RoutineRecord) -> RoutineSnapshot {
        RoutineSnapshot(
            id: record.id,
            title: record.title,
            weekdays: Set(record.weekdays),
            window: RoutineWindow(rawValue: record.windowRaw) ?? .anytime,
            reminderHour: record.reminderHour,
            reminderMinute: record.reminderMinute,
            isPaused: record.isPaused,
            isArchived: record.isArchived
        )
    }
}
