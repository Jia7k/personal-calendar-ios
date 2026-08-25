@preconcurrency import ActivityKit
import Foundation

@MainActor
protocol TimetableActivityDriving: AnyObject {
    var activitiesEnabled: Bool { get }
    func activityIDs() -> [String]
    func request(
        attributes: TimetableActivityAttributes,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> String
    func update(
        id: String,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) async
    func end(id: String, immediately: Bool) async
}

@MainActor
final class SystemTimetableActivityDriver: TimetableActivityDriving {
    var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func activityIDs() -> [String] {
        Activity<TimetableActivityAttributes>.activities.map(\.id)
    }

    func request(
        attributes: TimetableActivityAttributes,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> String {
        let activity = try Activity<TimetableActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: staleDate),
            pushType: nil
        )
        return activity.id
    }

    func update(
        id: String,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        guard let activity = activity(id: id) else { return }
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    func end(id: String, immediately: Bool) async {
        guard let activity = activity(id: id) else { return }
        await activity.end(
            nil,
            dismissalPolicy: immediately ? .immediate : .default
        )
    }

    private func activity(id: String) -> Activity<TimetableActivityAttributes>? {
        Activity<TimetableActivityAttributes>.activities.first { $0.id == id }
    }
}

@MainActor
final class NoopTimetableActivityDriver: TimetableActivityDriving {
    var activitiesEnabled: Bool { false }
    func activityIDs() -> [String] { [] }

    func request(
        attributes: TimetableActivityAttributes,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> String {
        throw TimetableActivityDriverError.unavailable
    }

    func update(
        id: String,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) async {}

    func end(id: String, immediately: Bool) async {}
}

enum TimetableActivityDriverError: Error {
    case unavailable
}
