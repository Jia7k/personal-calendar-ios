import AppIntents
import Foundation

enum QuickEntryIntentError: Error, Equatable {
    case blankText
    case invalidProfile
    case handoffUnavailable
    case queueFull
}

extension QuickEntryIntentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .queueFull:
            "Quick Entry is full. Open Personal Calendar and try again."
        case .blankText, .invalidProfile, .handoffUnavailable:
            nil
        }
    }
}

struct QuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Personal Calendar"
    static let description = IntentDescription(
        "Capture an event or task, then review it in My Calendar before saving."
    )
    static let openAppWhenRun = true

    @Parameter(title: "What do you want to add?")
    var text: String

    @Parameter(title: "Profile")
    var profile: QuickEntryProfileEntity?

    private var injectedHandoffStore: AppRouteHandoffStore?

    init() {
        injectedHandoffStore = nil
    }

    init(
        text: String,
        profile: QuickEntryProfileEntity?,
        handoffStore: AppRouteHandoffStore
    ) {
        self.text = text
        self.profile = profile
        injectedHandoffStore = handoffStore
    }

    func perform() async throws -> some IntentResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickEntryIntentError.blankText
        }

        let identity: ProfileIdentity?
        if let profile {
            guard let decoded = ProfileIdentity(storageKey: profile.id),
                  case .saved = decoded else {
                throw QuickEntryIntentError.invalidProfile
            }
            identity = decoded
        } else {
            identity = nil
        }

        let handoffStore: AppRouteHandoffStore
        if let injectedHandoffStore {
            handoffStore = injectedHandoffStore
        } else {
            do {
                handoffStore = try AppRouteHandoffStore.appGroup()
            } catch {
                throw QuickEntryIntentError.handoffUnavailable
            }
        }

        do {
            try handoffStore.write(.quickEntry(text: text, profile: identity))
        } catch AppRouteHandoffStoreError.queueFull {
            throw QuickEntryIntentError.queueFull
        } catch {
            throw QuickEntryIntentError.handoffUnavailable
        }
        return .result()
    }
}
