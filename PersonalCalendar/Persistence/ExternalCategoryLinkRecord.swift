import Foundation
import SwiftData

@Model
final class ExternalCategoryLinkRecord {
    @Attribute(.unique) var key: String
    var sourceRaw: String
    var externalID: String
    var categoryID: UUID

    init(
        source: ExternalItemSource,
        externalID: String,
        categoryID: UUID
    ) {
        key = Self.key(source: source, externalID: externalID)
        sourceRaw = source.rawValue
        self.externalID = externalID
        self.categoryID = categoryID
    }

    static func key(source: ExternalItemSource, externalID: String) -> String {
        "\(source.rawValue)|\(externalID)"
    }
}
