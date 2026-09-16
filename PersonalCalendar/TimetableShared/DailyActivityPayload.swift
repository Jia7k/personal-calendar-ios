import Foundation

struct DailyActivityPayload: Codable, Hashable, Sendable {
    struct Omission: Codable, Hashable, Sendable {
        let expiresAt: Date
        let count: Int

        private enum CodingKeys: String, CodingKey { case expiresAt = "e", count = "c" }
    }

    static let maximumCombinedEncodedBytes = 4_096
    static let maximumOmissionBoundaries = 24
    let snapshot: DailyActivitySnapshot
    let omissions: [Omission]
    let omissionCountUnknown: Bool
    /// Before this boundary the retained hero is known to outrank every dropped item.
    let heroVerifiedUntil: Date

    static func make(snapshot: DailyActivitySnapshot, attributes: TimetableActivityAttributes,
                     now: Date) -> Self? {
        guard snapshot.hasValidDay, now >= snapshot.dayStart, now < snapshot.dayEnd,
              now.timeIntervalSinceReferenceDate.isFinite, !attributes.isLegacy,
              attributes.profileIdentity == snapshot.profile.id,
              attributes.timeZoneIdentifier == snapshot.timeZoneIdentifier,
              attributes.dayStart == snapshot.dayStart, attributes.dayEnd == snapshot.dayEnd,
              let attributesSize = try? JSONEncoder().encode(attributes).count else { return nil }
        let projected = DailyActivityPresentation.make(snapshot: snapshot, now: now, rowLimit: Int.max)
        let candidates = (projected.hero.map { [$0] } ?? []) + projected.rows
        let profile = DailyActivityProfile(id: snapshot.profile.id,
            name: bounded(snapshot.profile.name, bytes: 96),
            symbolName: bounded(snapshot.profile.symbolName, bytes: 64))
        var retained = candidates.map { item in
            DailyActivityItem(id: item.id, kind: item.kind,
                title: bounded(item.title, bytes: 160), shortTitle: bounded(item.shortTitle, bytes: 32),
                start: item.start, end: item.end, isAllDay: item.isAllDay,
                location: item.location.map { bounded($0, bytes: 96) }, hasAlert: item.hasAlert)
        }
        let nextChange = candidates.flatMap { item -> [Date] in
            if item.isAllDay { return [] }
            return [item.start] + (item.end.map { [$0] } ?? [])
        }.filter { $0 > now }.min() ?? snapshot.dayEnd

        while true {
            let dropped = candidates.dropFirst(retained.count)
            let expirationCounts = Dictionary(grouping: dropped) { item in
                item.kind == .event && !item.isAllDay ? min(item.end ?? snapshot.dayEnd, snapshot.dayEnd) : snapshot.dayEnd
            }.map { Omission(expiresAt: $0.key, count: $0.value.count) }
                .sorted { $0.expiresAt < $1.expiresAt }
            let payload = Self(snapshot: snapshot.replacing(items: retained, profile: profile),
                omissions: Array(expirationCounts.prefix(maximumOmissionBoundaries)),
                omissionCountUnknown: expirationCounts.count > maximumOmissionBoundaries,
                heroVerifiedUntil: min(nextChange, snapshot.dayEnd))
            let state = TimetableActivityAttributes.ContentState(daily: payload)
            guard let stateSize = try? JSONEncoder().encode(state).count else { return nil }
            if stateSize <= TimetableActivityAttributes.ContentState.maximumEncodedBytes,
               stateSize + attributesSize <= maximumCombinedEncodedBytes {
                return payload
            }
            guard !retained.isEmpty else { return nil }
            retained.removeLast()
        }
    }

    func presentation(at now: Date, rowLimit: Int) -> DailyActivityPresentation {
        let base = DailyActivityPresentation.make(snapshot: snapshot, now: now, rowLimit: rowLimit)
        guard snapshot.hasValidDay, now.timeIntervalSinceReferenceDate.isFinite,
              now >= snapshot.dayStart, now < snapshot.dayEnd else { return base }
        // Guard decoded metadata too: corrupt or negative counts must not invent completion.
        let metadataInvalid = omissions.contains {
            $0.count <= 0 || !$0.expiresAt.timeIntervalSinceReferenceDate.isFinite
                || $0.expiresAt <= snapshot.dayStart || $0.expiresAt > snapshot.dayEnd
        } || !heroVerifiedUntil.timeIntervalSinceReferenceDate.isFinite
            || heroVerifiedUntil <= snapshot.dayStart || heroVerifiedUntil > snapshot.dayEnd
        let unknown = omissionCountUnknown || metadataInvalid
        var omitted = 0
        for omission in omissions where omission.expiresAt > now && omission.count > 0 {
            let (sum, overflow) = omitted.addingReportingOverflow(omission.count)
            if overflow { return uncertain(base: base) }
            omitted = sum
        }
        let omittedMayChangeHero = (unknown || omitted > 0)
            && (now >= heroVerifiedUntil || snapshot.items.isEmpty || unknown)
        let hero = omittedMayChangeHero ? nil : base.hero
        let displayedCount = base.rows.count + (hero == nil ? 0 : 1)
        let (remaining, overflow) = base.remainingCount.addingReportingOverflow(omitted)
        if overflow { return uncertain(base: base) }
        return DailyActivityPresentation(hero: hero, rows: base.rows,
            hiddenCount: unknown ? nil : max(0, remaining - displayedCount),
            requiresRefresh: base.requiresRefresh || omittedMayChangeHero,
            countdownBoundary: omittedMayChangeHero ? nil : base.countdownBoundary,
            remainingCount: remaining)
    }

    private func uncertain(base: DailyActivityPresentation) -> DailyActivityPresentation {
        DailyActivityPresentation(hero: nil, rows: base.rows, hiddenCount: nil,
            requiresRefresh: true, countdownBoundary: nil, remainingCount: base.remainingCount)
    }

    /// The limit includes JSON quotes and escapes; a composed Unicode character is never split.
    static func bounded(_ value: String, bytes: Int) -> String {
        var result = ""
        for character in value {
            let candidate = result + String(character)
            guard let size = try? JSONEncoder().encode(candidate).count, size <= bytes else { break }
            result = candidate
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case snapshot = "s", omissions = "o", omissionCountUnknown = "u", heroVerifiedUntil = "h"
    }
}
