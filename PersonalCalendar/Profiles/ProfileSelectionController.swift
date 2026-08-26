import Foundation
import Observation

enum ProfileSelectionError: Error, Equatable, Sendable {
    case savedProfileNotFound(UUID)
}

@MainActor
@Observable
final class ProfileSelectionController {
    private let repository: any ProfileRepository
    private let settings: AppSettingsStore

    private(set) var profiles: [ProfileSnapshot]
    private(set) var activeIdentity: ProfileIdentity
    private(set) var scopeRevision: Int

    init(repository: any ProfileRepository, settings: AppSettingsStore) {
        self.repository = repository
        self.settings = settings
        profiles = []
        activeIdentity = settings.activeProfileIdentity
        scopeRevision = 0
    }

    func reloadProfiles() throws {
        let refreshedProfiles = try repository.list()
        profiles = refreshedProfiles
        settings.reconcileQuickEntryHistory(
            validProfileIDs: Set(refreshedProfiles.map(\.id))
        )
        fallBackIfActiveProfileIsMissing()
    }

    func refreshScope() throws {
        let revisionBeforeReload = scopeRevision
        try reloadProfiles()
        if scopeRevision == revisionBeforeReload {
            scopeRevision += 1
        }
    }

    func select(_ identity: ProfileIdentity) throws {
        if case let .saved(id) = identity,
           !profiles.contains(where: { $0.id == id }) {
            throw ProfileSelectionError.savedProfileNotFound(id)
        }
        guard identity != activeIdentity else { return }

        activeIdentity = identity
        settings.setActiveProfile(identity)
        scopeRevision += 1
    }

    func profileDidChange(id: UUID, visibilityChanged: Bool) throws {
        let revisionBeforeReload = scopeRevision
        try reloadProfiles()

        guard scopeRevision == revisionBeforeReload, visibilityChanged else { return }
        switch activeIdentity {
        case .everything:
            scopeRevision += 1
        case let .saved(activeID) where activeID == id:
            scopeRevision += 1
        case .saved:
            break
        }
    }

    func profileWasDeleted(id _: UUID) throws {
        let revisionBeforeReload = scopeRevision
        let everythingWasActive = activeIdentity == .everything
        try reloadProfiles()
        if everythingWasActive, scopeRevision == revisionBeforeReload {
            scopeRevision += 1
        }
    }

    private func fallBackIfActiveProfileIsMissing() {
        guard case let .saved(id) = activeIdentity,
              !profiles.contains(where: { $0.id == id }) else {
            return
        }

        activeIdentity = .everything
        settings.setActiveProfile(.everything)
        scopeRevision += 1
    }
}
