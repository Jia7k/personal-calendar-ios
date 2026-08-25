import Foundation
import SwiftData

@Model
final class CategoryRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var nameKey: String
    var name: String
    var colorHex: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        sortOrder: Int
    ) {
        self.id = id
        nameKey = Self.nameKey(for: name)
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }

    static func nameKey(for name: String) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        return name.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: locale)
            .lowercased(with: locale)
    }
}
