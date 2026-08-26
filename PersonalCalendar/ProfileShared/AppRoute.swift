import Foundation

struct AppRouteDay: Codable, Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)

        guard Self.isValid(year: year, month: month, day: day) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid Gregorian calendar day.")
            )
        }

        self.init(year: year, month: month, day: day)
    }

    func encode(to encoder: any Encoder) throws {
        guard Self.isValid(year: year, month: month, day: day) else {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: encoder.codingPath, debugDescription: "Invalid Gregorian calendar day.")
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(day, forKey: .day)
    }

    fileprivate static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1 ... 9_999).contains(year), (1 ... 12).contains(month), day >= 1 else {
            return false
        }

        let daysInMonth: Int
        switch month {
        case 2:
            let isLeapYear = year.isMultiple(of: 400)
                || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
            daysInMonth = isLeapYear ? 29 : 28
        case 4, 6, 9, 11:
            daysInMonth = 30
        default:
            daysInMonth = 31
        }

        return day <= daysInMonth
    }
}

enum AppRoute: Equatable, Sendable {
    case today
    case calendar(day: AppRouteDay?, profile: ProfileIdentity?, entryID: String?)
    case task(id: String, profile: ProfileIdentity?)
    case routine(id: UUID, profile: ProfileIdentity?)
    case quickEntry(text: String, profile: ProfileIdentity?)
}

enum AppRouteCodecError: Error, Equatable, Sendable {
    case invalidURL
    case unsupportedScheme
    case unsupportedVersion
    case unsupportedRoute
    case invalidQuery
    case invalidDay
    case invalidProfile
    case missingRequiredValue(String)
}

struct AppRouteCodec: Sendable {
    private static let scheme = "personalcalendar"
    private static let version = "v1"

    func url(for route: AppRoute) throws -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.version

        switch route {
        case .today:
            components.path = "/today"
        case let .calendar(day, profile, entryID):
            components.path = "/calendar"
            var queryItems: [URLQueryItem] = []
            if let day {
                queryItems.append(.init(name: "day", value: try encoded(day: day)))
            }
            if let profile {
                queryItems.append(.init(name: "profile", value: profile.storageKey))
            }
            if let entryID {
                guard !entryID.isEmpty else {
                    throw AppRouteCodecError.missingRequiredValue("entry")
                }
                queryItems.append(.init(name: "entry", value: entryID))
            }
            components.queryItems = queryItems.isEmpty ? nil : queryItems
        case let .task(id, profile):
            guard !id.isEmpty else {
                throw AppRouteCodecError.missingRequiredValue("id")
            }
            components.path = "/task"
            components.queryItems = queryItems(id: id, profile: profile)
        case let .routine(id, profile):
            components.path = "/routine"
            components.queryItems = queryItems(id: id.uuidString.lowercased(), profile: profile)
        case let .quickEntry(text, profile):
            guard !text.isEmpty else {
                throw AppRouteCodecError.missingRequiredValue("text")
            }
            components.path = "/quick-entry"
            var queryItems = [URLQueryItem(name: "text", value: text)]
            if let profile {
                queryItems.append(.init(name: "profile", value: profile.storageKey))
            }
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw AppRouteCodecError.invalidURL
        }
        return url
    }

    func route(from url: URL) throws -> AppRoute {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AppRouteCodecError.invalidURL
        }
        guard components.scheme == Self.scheme else {
            throw AppRouteCodecError.unsupportedScheme
        }
        guard components.host == Self.version else {
            throw AppRouteCodecError.unsupportedVersion
        }
        guard components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil else {
            throw AppRouteCodecError.invalidURL
        }

        switch components.percentEncodedPath {
        case "/today":
            _ = try queryValues(in: components, allowing: [])
            return .today
        case "/calendar":
            let values = try queryValues(in: components, allowing: ["day", "profile", "entry"])
            let day = try values["day"].map(decodedDay(from:))
            let profile = try decodedProfile(from: values["profile"])
            let entryID = try nonemptyOptional(values["entry"], named: "entry")
            return .calendar(day: day, profile: profile, entryID: entryID)
        case "/task":
            let values = try queryValues(in: components, allowing: ["id", "profile"])
            let id = try requiredValue("id", in: values)
            return .task(id: id, profile: try decodedProfile(from: values["profile"]))
        case "/routine":
            let values = try queryValues(in: components, allowing: ["id", "profile"])
            let rawID = try requiredValue("id", in: values)
            guard let id = UUID(uuidString: rawID) else {
                throw AppRouteCodecError.invalidQuery
            }
            return .routine(id: id, profile: try decodedProfile(from: values["profile"]))
        case "/quick-entry":
            let values = try queryValues(in: components, allowing: ["text", "profile"])
            let text = try requiredValue("text", in: values)
            return .quickEntry(text: text, profile: try decodedProfile(from: values["profile"]))
        default:
            throw AppRouteCodecError.unsupportedRoute
        }
    }

    private func queryItems(id: String, profile: ProfileIdentity?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "id", value: id)]
        if let profile {
            items.append(.init(name: "profile", value: profile.storageKey))
        }
        return items
    }

    private func queryValues(
        in components: URLComponents,
        allowing names: Set<String>
    ) throws -> [String: String] {
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard names.contains(item.name),
                  values[item.name] == nil,
                  let value = item.value else {
                throw AppRouteCodecError.invalidQuery
            }
            values[item.name] = value
        }
        return values
    }

    private func requiredValue(_ name: String, in values: [String: String]) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw AppRouteCodecError.missingRequiredValue(name)
        }
        return value
    }

    private func nonemptyOptional(_ value: String?, named name: String) throws -> String? {
        guard let value else { return nil }
        guard !value.isEmpty else {
            throw AppRouteCodecError.missingRequiredValue(name)
        }
        return value
    }

    private func decodedProfile(from value: String?) throws -> ProfileIdentity? {
        guard let value else { return nil }
        guard let identity = ProfileIdentity(storageKey: value) else {
            throw AppRouteCodecError.invalidProfile
        }
        return identity
    }

    private func encoded(day: AppRouteDay) throws -> String {
        guard AppRouteDay.isValid(year: day.year, month: day.month, day: day.day) else {
            throw AppRouteCodecError.invalidDay
        }
        return "\(zeroPadded(day.year, width: 4))-\(zeroPadded(day.month, width: 2))-\(zeroPadded(day.day, width: 2))"
    }

    private func decodedDay(from value: String) throws -> AppRouteDay {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48 ... 57).contains(byte)
              }) else {
            throw AppRouteCodecError.invalidDay
        }

        let year = decimal(bytes[0 ... 3])
        let month = decimal(bytes[5 ... 6])
        let day = decimal(bytes[8 ... 9])
        guard AppRouteDay.isValid(year: year, month: month, day: day) else {
            throw AppRouteCodecError.invalidDay
        }
        return .init(year: year, month: month, day: day)
    }

    private func decimal(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { partialResult, byte in
            (partialResult * 10) + Int(byte - 48)
        }
    }

    private func zeroPadded(_ value: Int, width: Int) -> String {
        let raw = String(value)
        return String(repeating: "0", count: max(0, width - raw.count)) + raw
    }
}

enum AppRouteEntryIdentity {
    static func make(displayID: String, occurrenceStart: Date) -> String {
        let scaledMilliseconds = occurrenceStart.timeIntervalSince1970 * 1_000
        let milliseconds: Int64
        if scaledMilliseconds >= Double(Int64.max) {
            milliseconds = .max
        } else if scaledMilliseconds <= Double(Int64.min) {
            milliseconds = .min
        } else {
            milliseconds = Int64(scaledMilliseconds.rounded())
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in displayID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        hash = (hash ^ 0) &* 1_099_511_628_211

        var encodedMilliseconds = UInt64(bitPattern: milliseconds).bigEndian
        withUnsafeBytes(of: &encodedMilliseconds) { bytes in
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }

        let hexadecimal = String(hash, radix: 16, uppercase: false)
        return "entry-" + String(repeating: "0", count: 16 - hexadecimal.count) + hexadecimal
    }
}
