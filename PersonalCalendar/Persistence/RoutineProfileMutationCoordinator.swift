import Foundation
import SwiftData

@MainActor
protocol RoutineProfileMutating {
    func create(draft: RoutineDraft, profileID: UUID) throws -> UUID
    func delete(id: UUID) throws
}

enum RoutineProfileMutationError: Error, Equatable {
    case savedProfileRequired
}

@MainActor
final class RoutineProfileMutationCoordinator: RoutineProfileMutating {
    private let context: ModelContext
    private let routines: SwiftDataRoutineRepository
    private let transaction: (@escaping () throws -> Void) throws -> Void

    init(
        context: ModelContext,
        routines: SwiftDataRoutineRepository? = nil
    ) {
        self.context = context
        self.routines = routines ?? SwiftDataRoutineRepository(context: context)
        transaction = { changes in
            try context.transaction(block: changes)
        }
    }

    init(
        context: ModelContext,
        routines: SwiftDataRoutineRepository? = nil,
        transaction: @escaping (@escaping () throws -> Void) throws -> Void
    ) {
        self.context = context
        self.routines = routines ?? SwiftDataRoutineRepository(context: context)
        self.transaction = transaction
    }

    func create(draft: RoutineDraft, profileID: UUID) throws -> UUID {
        let record = try routines.makeRecord(for: draft)
        let profile = try profileRecord(id: profileID)

        try performTransaction {
            self.routines.insertWithoutSaving(record)
            profile.routineIDs = Array(Set(profile.routineIDs).union([record.id])).sorted {
                $0.uuidString < $1.uuidString
            }
        }
        return record.id
    }

    func delete(id: UUID) throws {
        let profiles = try context.fetch(FetchDescriptor<ProfileRecord>())

        try performTransaction {
            try self.routines.deleteWithoutSaving(id: id)
            for profile in profiles where profile.routineIDs.contains(id) {
                profile.routineIDs.removeAll { $0 == id }
            }
        }
    }

    private func profileRecord(id: UUID) throws -> ProfileRecord {
        let descriptor = FetchDescriptor<ProfileRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let profile = try context.fetch(descriptor).first else {
            throw ProfileRepositoryError.profileNotFound
        }
        return profile
    }

    private func performTransaction(_ changes: @escaping () throws -> Void) throws {
        do {
            try transaction(changes)
        } catch {
            context.rollback()
            throw error
        }
    }
}
