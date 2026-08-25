import Foundation

protocol QuickEntryParsing: Sendable {
    func parse(_ text: String, context: QuickEntryParseContext) throws -> QuickEntryPreview
}
