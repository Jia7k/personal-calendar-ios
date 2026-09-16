import Foundation

enum AppLaunchStorage {
    static func handoffStore(
        isTesting: Bool,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        sharedStore: () throws -> AppRouteHandoffStore = { try .appGroup() }
    ) throws -> AppRouteHandoffStore {
        guard isTesting else { return try sharedStore() }
        let directory = temporaryDirectory
            .appendingPathComponent("calendar-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppRouteHandoffStore(fileURL: directory.appendingPathComponent(AppRouteHandoffStore.filename))
    }
}
