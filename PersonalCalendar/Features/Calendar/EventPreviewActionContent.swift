import Foundation

enum EventDirectionsURL {
    static func make(location: String) -> URL? {
        let location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !location.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "daddr", value: location)]
        return components.url
    }
}

struct EventPreviewActionContent: Equatable {
    let location: String?
    let directionsLocation: String?
    let meetingURL: URL?
    let meetingDestination: String?

    static func resolve(
        location: String?,
        eventURL: URL?,
        notes: String?
    ) -> EventPreviewActionContent {
        let normalizedLocation = normalized(location)
        let meetingURL = firstMeetingURL(
            eventURL: eventURL,
            location: normalizedLocation,
            notes: notes
        )
        return .init(
            location: normalizedLocation,
            directionsLocation: physicalLocation(normalizedLocation),
            meetingURL: meetingURL,
            meetingDestination: meetingURL?.host?.lowercased()
        )
    }

    private static let meetingDomains = [
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "zoom.us",
        "webex.com",
        "meet.jit.si"
    ]

    private static let onlineOnlyLabels: Set<String> = [
        "join",
        "join call",
        "meeting",
        "online",
        "online meeting",
        "virtual",
        "virtual meeting",
        "remote",
        "video call",
        "zoom",
        "zoom meeting",
        "microsoft teams",
        "microsoft teams meeting",
        "teams",
        "teams meeting",
        "google meet",
        "google meet meeting",
        "webex",
        "webex meeting"
    ]

    private static let linkExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9+.:_-])https?://[^\s<>\"']+"#,
        options: [.caseInsensitive]
    )

    private static let anySchemeLinkExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9+.:_-])[A-Za-z][A-Za-z0-9+.-]*://[^\s<>\"']+"#,
        options: [.caseInsensitive]
    )

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func physicalLocation(_ location: String?) -> String? {
        guard let location else { return nil }
        let range = NSRange(location.startIndex..., in: location)
        let withoutLinks = anySchemeLinkExpression.stringByReplacingMatches(
            in: location,
            range: range,
            withTemplate: ""
        )
        let comparison = withoutLinks
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        guard !comparison.isEmpty,
              !onlineOnlyLabels.contains(comparison) else {
            return nil
        }
        return withoutLinks
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func firstMeetingURL(
        eventURL: URL?,
        location: String?,
        notes: String?
    ) -> URL? {
        if let eventURL, isAllowedMeetingURL(eventURL) {
            return eventURL
        }
        for text in [location, notes].compactMap({ $0 }) {
            if let match = extractedURLs(from: text).first(where: isAllowedMeetingURL) {
                return match
            }
        }
        return nil
    }

    private static func extractedURLs(from text: String) -> [URL] {
        let range = NSRange(text.startIndex..., in: text)
        return linkExpression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let candidate = String(text[swiftRange]).trimmingCharacters(
                in: CharacterSet(charactersIn: ".,;:!?)]}")
            )
            return URL(string: candidate)
        }
    }

    private static func isAllowedMeetingURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return meetingDomains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }
}

struct EventPreviewActionEffects {
    let openDirections: @MainActor (URL) async -> Bool
    let copyLocation: @MainActor (String) -> Bool
    let openMeeting: @MainActor (URL) async -> Bool

    static let unavailable = EventPreviewActionEffects(
        openDirections: { _ in false },
        copyLocation: { _ in false },
        openMeeting: { _ in false }
    )
}
