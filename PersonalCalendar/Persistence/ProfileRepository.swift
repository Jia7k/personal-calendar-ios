import Foundation

enum ProfileRepositoryError: Error, Equatable, Sendable {
    case invalidName
    case invalidColor
    case invalidSymbol
    case invalidExternalIdentifier
    case duplicateName
    case duplicateIdentifier
    case profileNotFound
    case invalidReorder
    case defaultCalendarNotMember
    case defaultReminderListNotMember
    case cannotDeleteLastProfile
}

@MainActor
protocol ProfileRepository: AnyObject {
    func list() throws -> [ProfileSnapshot]
    func profile(id: UUID) throws -> ProfileSnapshot
    func create(_ draft: ProfileDraft, id: UUID?) throws -> UUID
    func update(id: UUID, draft: ProfileDraft) throws
    func reorder(_ ids: [UUID]) throws
    func delete(id: UUID) throws
    func removeRoutineID(_ id: UUID) throws
    func unionMembership() throws -> ProfileMembership
}

extension ProfileRepository {
    func create(_ draft: ProfileDraft) throws -> UUID {
        try create(draft, id: nil)
    }
}
