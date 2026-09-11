import Foundation

enum WeekEventDisplayTitle {
    static func compact(_ title: String) -> String {
        guard let parts = classTitleParts(title) else { return title }
        return "\(parts.courseCode)\n\(parts.detail)"
    }

    static func narrowBlock(_ title: String) -> String? {
        guard let parts = classTitleParts(title) else { return nil }
        let courseParts = parts.courseCode.split(separator: " ", maxSplits: 1)
        guard courseParts.count == 2 else { return nil }
        return "\(courseParts[0])\n\(courseParts[1])\n\(narrowKind(parts.kind))"
    }

    private struct ClassTitleParts {
        let courseCode: String
        let detail: String
        let kind: String
    }

    private static func classTitleParts(_ title: String) -> ClassTitleParts? {
        let pattern = #"^([A-Z]{2,5}\s+[0-9]{3,4}[A-Z]?)\s*[-–—:]\s*.+\s+\(\s*([A-Z][0-9]{1,2})?\s*(Laboratory|Lab|Lecture|Tutorial|Seminar)\s*\)\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: title,
                range: NSRange(title.startIndex..., in: title)
              ),
              match.range == NSRange(title.startIndex..., in: title),
              let courseRange = Range(match.range(at: 1), in: title),
              let kindRange = Range(match.range(at: 3), in: title) else {
            return nil
        }

        let courseCode = String(title[courseRange])
        let classKind = compactKind(String(title[kindRange]))
        let section = Range(match.range(at: 2), in: title).map { String(title[$0]) }
        let detail = [section, classKind]
            .compactMap { $0 }
            .joined(separator: " ")
        return .init(courseCode: courseCode, detail: detail, kind: classKind)
    }

    private static func compactKind(_ value: String) -> String {
        switch value {
        case "Laboratory", "Lab": "Lab"
        case "Lecture": "Lecture"
        case "Tutorial": "Tutorial"
        case "Seminar": "Seminar"
        default: value
        }
    }

    private static func narrowKind(_ value: String) -> String {
        switch value {
        case "Lecture": "Lec"
        case "Tutorial": "Tut"
        case "Seminar": "Sem"
        default: value
        }
    }
}

struct WeekEventBlockPresentation: Equatable, Sendable {
    let displayTitle: String
    let showsTime: Bool
    let titleLineLimit: Int
    let usesCompactClassStyle: Bool

    static func resolve(
        title: String,
        height: CGFloat,
        itemCount: Int,
        availableTextWidth: CGFloat? = nil
    ) -> Self {
        let generic = WeekPlannerCompactCardPresentation.resolve(
            height: height,
            itemCount: itemCount
        )
        let displayTitle = WeekEventDisplayTitle.compact(title)
        let usesCompactClassStyle = displayTitle != title
        // Phone columns cannot reliably fit a course code and section on two lines.
        let isNarrowColumn = availableTextWidth.map { $0 < 72 } ?? false
        let narrowTitle = generic.titleLineLimit == 1 || isNarrowColumn
            ? WeekEventDisplayTitle.narrowBlock(title)
            : nil
        return .init(
            displayTitle: narrowTitle ?? displayTitle,
            showsTime: generic.showsTime,
            titleLineLimit: narrowTitle == nil ? generic.titleLineLimit : 3,
            usesCompactClassStyle: usesCompactClassStyle
        )
    }
}
