import Foundation

enum TimetableWidgetSelectionResult: Equatable, Sendable {
    case chooseProfile
    case profileDeleted
    case calendarAccessRequired
    case emptyProfile
    case noClasses
    case ready(TimetableSnapshotV1)
}

enum TimetableWidgetSelectionResolver {
    static func resolve(
        _ selection: ProfileIdentity?,
        in catalog: TimetableWidgetCatalogV1
    ) -> TimetableWidgetSelectionResult {
        guard let selection else { return .chooseProfile }
        guard let snapshot = catalog.snapshot(for: selection) else { return .profileDeleted }
        switch snapshot.availability {
        case .ready:
            return .ready(snapshot)
        case .calendarAccessRequired:
            return .calendarAccessRequired
        case .emptyProfile:
            return .emptyProfile
        case .noClasses:
            return .noClasses
        }
    }
}
