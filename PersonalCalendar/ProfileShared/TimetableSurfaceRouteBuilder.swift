import Foundation

enum TimetableSurfaceRouteBuilderError: Error, Equatable, Sendable {
    case invalidTimeZoneIdentifier(String)
    case invalidLocalDay
    case invalidEntryRouteID(String)
}

struct TimetableSurfaceRouteBuilder: Sendable {
    let codec: AppRouteCodec

    init(codec: AppRouteCodec = .init()) {
        self.codec = codec
    }

    func url(
        profile: ProfileIdentity,
        date: Date,
        timeZoneIdentifier: String,
        entryRouteID: String?
    ) throws -> URL {
        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw TimetableSurfaceRouteBuilderError
                .invalidTimeZoneIdentifier(timeZoneIdentifier)
        }
        calendar.timeZone = timeZone

        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year,
              let month = parts.month,
              let day = parts.day else {
            throw TimetableSurfaceRouteBuilderError.invalidLocalDay
        }

        let normalizedEntryRouteID = entryRouteID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedEntryRouteID,
           !normalizedEntryRouteID.isEmpty,
           !Self.isCanonicalEntryRouteID(normalizedEntryRouteID) {
            throw TimetableSurfaceRouteBuilderError
                .invalidEntryRouteID(normalizedEntryRouteID)
        }

        return try codec.url(for: .calendar(
            day: .init(year: year, month: month, day: day),
            profile: profile,
            entryID: normalizedEntryRouteID?.isEmpty == false
                ? normalizedEntryRouteID
                : nil
        ))
    }

    private static func isCanonicalEntryRouteID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 22,
              bytes.starts(with: [101, 110, 116, 114, 121, 45]) else {
            return false
        }

        return bytes.dropFirst(6).allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
        }
    }
}
