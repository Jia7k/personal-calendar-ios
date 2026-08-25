import Foundation

enum ProfileIdentity: Hashable, Sendable {
    case everything
    case saved(UUID)

    var storageKey: String {
        switch self {
        case .everything:
            "everything"
        case let .saved(id):
            "saved:\(id.uuidString.lowercased())"
        }
    }

    init?(storageKey: String) {
        if storageKey == "everything" {
            self = .everything
            return
        }
        guard storageKey.hasPrefix("saved:"),
              let id = UUID(uuidString: String(storageKey.dropFirst(6))) else {
            return nil
        }
        self = .saved(id)
    }
}

extension ProfileIdentity: Codable {
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let identity = Self(storageKey: value) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid profile identity.")
            )
        }
        self = identity
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }
}
