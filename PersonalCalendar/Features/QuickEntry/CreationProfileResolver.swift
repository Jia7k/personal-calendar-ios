import Foundation

struct CreationProfileContext: Equatable, Sendable {
    let profileID: UUID
    let profileName: String
    let memberCalendarIDs: Set<String>
    let memberReminderListIDs: Set<String>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
    let requiresExplicitCalendarDestination: Bool
    let requiresExplicitReminderDestination: Bool
}

enum CreationProfileResolution: Equatable, Sendable {
    case ready(CreationProfileContext)
    case chooseSavedProfile([UUID])
}

@MainActor
struct CreationProfileResolver {
    private let profiles: [ProfileSnapshot]
    private let resolveScope: @MainActor (ProfileIdentity) throws -> ProfileScope

    init(
        profiles: [ProfileSnapshot],
        resolveScope: @escaping @MainActor (ProfileIdentity) throws -> ProfileScope
    ) {
        self.profiles = profiles.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        self.resolveScope = resolveScope
    }

    func resolve(active identity: ProfileIdentity) throws -> CreationProfileResolution {
        switch identity {
        case .everything:
            return .chooseSavedProfile(profiles.map(\.id))
        case let .saved(id):
            return .ready(try resolve(chosen: id))
        }
    }

    func resolve(chosen id: UUID) throws -> CreationProfileContext {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileRepositoryError.profileNotFound
        }

        let scope = try resolveScope(.saved(id))
        return CreationProfileContext(
            profileID: id,
            profileName: profile.name,
            memberCalendarIDs: profile.calendarIDs,
            memberReminderListIDs: profile.reminderListIDs,
            defaultCalendarID: scope.defaultCalendarID,
            defaultReminderListID: scope.defaultReminderListID,
            requiresExplicitCalendarDestination: scope.defaultCalendarID == nil,
            requiresExplicitReminderDestination: scope.defaultReminderListID == nil
        )
    }
}
