import Foundation

struct RuleBasedQuickEntryParser: QuickEntryParsing, Sendable {
    func parse(_ text: String, context: QuickEntryParseContext) throws -> QuickEntryPreview {
        let input = Self.normalizedWhitespace(text)
        guard !input.isEmpty else { throw QuickEntryParseError.emptyInput }
        try Self.rejectFusedSlashDateClockOverlap(in: input)

        let recurrence = try Self.recurrence(in: input)
        let date = try Self.date(in: input, context: context, excluding: recurrence?.ranges ?? [])
        let clock = try Self.clock(in: input)

        if recurrence != nil, date != nil, clock == nil {
            throw QuickEntryParseError.ambiguousExpression
        }
        if recurrence?.rule.frequency == .weekly,
           let eligibleWeekdays = recurrence?.rule.weekdays,
           !eligibleWeekdays.isEmpty,
           let date,
           !eligibleWeekdays.contains(context.calendar.component(.weekday, from: date.day)) {
            throw QuickEntryParseError.ambiguousExpression
        }

        let syntaxRanges = (recurrence?.ranges ?? []) + (date?.ranges ?? []) + (clock?.ranges ?? [])
        let title = Self.cleanedTitle(input, removing: syntaxRanges)
        guard Self.hasUsableTitleContent(title) else { throw QuickEntryParseError.noUsableTitle }

        let scheduled = try Self.scheduledDate(date: date, clock: clock, recurrence: recurrence, context: context)
        let hasStrongWindow = recurrence?.window != nil
        let kind: QuickEntryKind
        if hasStrongWindow {
            kind = .routine
        } else if recurrence != nil, clock == nil {
            kind = .routine
        } else if clock != nil {
            kind = .event
        } else {
            kind = .task
        }

        switch kind {
        case .event:
            guard let scheduled else { throw QuickEntryParseError.invalidDate }
            let warnings: Set<QuickEntryParseWarning> = scheduled < context.now ? [.scheduledTimeIsPast] : []
            return QuickEntryPreview(
                kind: .event, title: title, startDate: scheduled, endDate: scheduled.addingTimeInterval(3_600),
                recurrence: recurrence?.rule, warnings: warnings
            )
        case .task:
            let warnings: Set<QuickEntryParseWarning>
            if let scheduled,
               context.calendar.startOfDay(for: scheduled) < context.calendar.startOfDay(for: context.now) {
                warnings = [.scheduledTimeIsPast]
            } else {
                warnings = []
            }
            return QuickEntryPreview(
                kind: .task, title: title, dueDate: scheduled, dueHasTime: false, warnings: warnings
            )
        case .routine:
            guard let recurrence else { throw QuickEntryParseError.ambiguousExpression }
            let days: Set<Int> = recurrence.rule.frequency == .daily ? Set(1 ... 7) : recurrence.rule.weekdays
            let reminder = recurrence.window == nil ? nil : clock.flatMap { _ in scheduled }
            let warnings: Set<QuickEntryParseWarning> = reminder.map { $0 < context.now ? [.scheduledTimeIsPast] : [] } ?? []
            return QuickEntryPreview(
                kind: .routine, title: title, routineWindow: recurrence.window ?? .anytime,
                weekdays: days, recurrence: recurrence.rule, reminderDate: reminder, warnings: warnings
            )
        }
    }
}

private extension RuleBasedQuickEntryParser {
    struct RecurrenceMatch {
        let rule: RecurrenceRuleDraft
        let window: RoutineWindow?
        let ranges: [Range<String.Index>]
    }

    struct DateMatch {
        enum Style { case explicit, bareWeekday, relative }
        let day: Date
        let style: Style
        let ranges: [Range<String.Index>]
    }

    struct ClockMatch {
        let hour: Int
        let minute: Int
        let ranges: [Range<String.Index>]
    }

    static func normalizedWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func recurrence(in text: String) throws -> RecurrenceMatch? {
        let values: [(String, RoutineWindow?, RecurrenceRuleDraft)] = [
            ("every morning", .morning, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("every afternoon", .afternoon, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("every evening", .evening, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("every night", .evening, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("every day", nil, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("daily", nil, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil)),
            ("weekdays", nil, .init(frequency: .weekly, interval: 1, weekdays: Set(2 ... 6), endDate: nil))
        ]
        var matches: [(RecurrenceMatch, Int)] = []
        for (phrase, window, rule) in values {
            for range in ranges(of: "(?i)(?<![\\p{L}\\p{M}\\p{N}\\p{Pc}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{M}\\p{N}\\p{Pc}])", in: text) {
                matches.append((.init(rule: rule, window: window, ranges: [range]), range.lowerBound.utf16Offset(in: text)))
            }
        }
        let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (offset, name) in weekdayNames.enumerated() {
            let pattern = "(?i)(?<![\\p{L}\\p{M}\\p{N}\\p{Pc}])every\\s+" + name + "(?![\\p{L}\\p{M}\\p{N}\\p{Pc}])"
            for range in ranges(of: pattern, in: text) {
                matches.append((.init(rule: .init(frequency: .weekly, interval: 1, weekdays: [offset + 1], endDate: nil), window: nil, ranges: [range]), range.lowerBound.utf16Offset(in: text)))
            }
        }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1 else { throw QuickEntryParseError.ambiguousExpression }
        return matches[0].0
    }

    static func date(
        in text: String,
        context: QuickEntryParseContext,
        excluding ownedRanges: [Range<String.Index>]
    ) throws -> DateMatch? {
        var matches: [DateMatch] = []
        let startToday = context.calendar.startOfDay(for: context.now)
        func add(_ day: Date, _ style: DateMatch.Style, _ range: Range<String.Index>) { matches.append(.init(day: day, style: style, ranges: [range])) }

        for (word, offset) in [("today", 0), ("tomorrow", 1)] {
            for range in ranges(of: "(?i)(?<![\\p{L}\\p{M}\\p{N}\\p{Pc}])(?:on\\s+)?" + word + "(?![\\p{L}\\p{M}\\p{N}\\p{Pc}])", in: text) {
                guard let day = context.calendar.date(byAdding: .day, value: offset, to: startToday) else { throw QuickEntryParseError.invalidDate }
                add(day, .explicit, range)
            }
        }
        for (unit, component) in [("month", Calendar.Component.month), ("year", .year)] {
            for range in ranges(of: "(?i)(?<![\\p{L}\\p{M}\\p{N}\\p{Pc}])in\\s+1\\s+" + unit + "(?![\\p{L}\\p{M}\\p{N}\\p{Pc}])", in: text) {
                guard let day = context.calendar.date(byAdding: component, value: 1, to: startToday) else { throw QuickEntryParseError.invalidDate }
                add(day, .relative, range)
            }
        }
        let numericPattern = "(?i)(?<![\\p{L}\\p{M}\\p{N}\\p{Pc}/])(?:on\\s+)?([0-9]{1,4})/([0-9]{1,2})(?:/([0-9]{1,4}))?(?![\\p{L}\\p{M}\\p{N}\\p{Pc}/])"
        for range in ranges(of: numericPattern, in: text) {
            let captures = captureGroups(of: numericPattern, in: text, range: range)
            guard captures.count == 3 else { throw QuickEntryParseError.invalidDate }
            let values = captures.compactMap(Int.init)
            let fieldOrder = numericDateFieldOrder(locale: context.locale)
            let year: Int
            let month: Int
            let day: Int
            if captures[2].isEmpty {
                guard values.count == 2,
                      let monthIndex = fieldOrder.filter({ $0 != .year }).firstIndex(of: .month),
                      let dayIndex = fieldOrder.filter({ $0 != .year }).firstIndex(of: .day) else {
                    throw QuickEntryParseError.invalidDate
                }
                let yearlessOrder = fieldOrder.filter { $0 != .year }
                year = context.calendar.component(.year, from: context.now)
                month = values[monthIndex]
                day = values[dayIndex]
                guard yearlessOrder.count == 2 else { throw QuickEntryParseError.invalidDate }
            } else {
                guard values.count == 3, fieldOrder.count == 3,
                      let yearIndex = fieldOrder.firstIndex(of: .year),
                      let monthIndex = fieldOrder.firstIndex(of: .month),
                      let dayIndex = fieldOrder.firstIndex(of: .day),
                      captures[yearIndex].count == 4 else {
                    throw QuickEntryParseError.invalidDate
                }
                year = values[yearIndex]
                month = values[monthIndex]
                day = values[dayIndex]
            }
            guard let constructed = localDate(year: year, month: month, day: day, hour: 0, minute: 0, context: context) else { throw QuickEntryParseError.invalidDate }
            add(constructed, .explicit, range)
        }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (index, name) in names.enumerated() {
            let weekday = index + 1
            for range in ranges(of: "(?i)(?<![\\p{L}\\p{M}\\p{N}\\p{Pc}])(?:on\\s+)?next\\s+" + name + "(?![\\p{L}\\p{M}\\p{N}\\p{Pc}])", in: text) {
                let todayWeekday = context.calendar.component(.weekday, from: context.now)
                let rawDelta = (weekday - todayWeekday + 7) % 7
                let delta = rawDelta == 0 ? 7 : rawDelta
                guard let day = context.calendar.date(byAdding: .day, value: delta, to: startToday) else { throw QuickEntryParseError.invalidDate }
                add(day, .explicit, range)
            }
            for range in ranges(of: "(?i)(?<![\\p{L}\\p{M}\\p{N}\\p{Pc}])(?:on\\s+)?" + name + "(?![\\p{L}\\p{M}\\p{N}\\p{Pc}])", in: text) {
                let prefix = text[..<range.lowerBound].lowercased()
                guard !prefix.hasSuffix("next ") else { continue }
                guard !ownedRanges.contains(where: { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }) else { continue }
                let todayWeekday = context.calendar.component(.weekday, from: context.now)
                let delta = (weekday - todayWeekday + 7) % 7
                guard let day = context.calendar.date(byAdding: .day, value: delta, to: startToday) else { throw QuickEntryParseError.invalidDate }
                add(day, .bareWeekday, range)
            }
        }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1 else { throw QuickEntryParseError.ambiguousExpression }
        return matches[0]
    }

    static func clock(in text: String) throws -> ClockMatch? {
        let token = "\\p{L}\\p{M}\\p{N}\\p{Pc}"
        let rangePattern = "(?i)(?<![\(token)/])(?:at\\s+)?([0-9]{1,4})(?::([0-9]+))?\\s*([ap]m)?\\s*(?:-|–|—|to)\\s*([0-9]{1,4})(?::([0-9]+))?\\s*([ap]m)?(?![\(token)])"
        let exactPattern = "(?i)(?<![\(token):/])((?:at\\s+)?)([0-9]{1,2})(?::([0-9]{2})(?:\\s*([ap]m))?|\\s*([ap]m))(?![\(token)]|:[0-9])"
        let spacedTruncatedSuffixPattern = "(?i)(?<![\(token)/])(?:at\\s+[0-9]{1,2}(?::[0-9]{2})?|[0-9]{1,2}:[0-9]{2})\\s+[ap](?![\(token)])"
        let dottedClockPattern = "(?i)(?<![\(token)/])(?:at\\s+)?[0-9]*\\.(?:(?=[0-9:]*:)[0-9][0-9:]*(?:[ap]m?|\\s+[ap]m)?|[0-9]+(?:[ap]m?|\\s+[ap]m))(?![\(token)])"
        let connectedSpacedDottedTruncationPattern = "(?i)(?<![\(token)/])at\\s+[0-9]*\\.[0-9][0-9:]*\\s+[ap](?![\(token)])"
        guard ranges(of: spacedTruncatedSuffixPattern, in: text).isEmpty,
              ranges(of: dottedClockPattern, in: text).isEmpty,
              ranges(of: connectedSpacedDottedTruncationPattern, in: text).isEmpty else {
            throw QuickEntryParseError.invalidClock
        }

        var timeRangeRanges: [Range<String.Index>] = []
        for range in ranges(of: rangePattern, in: text) {
            let groups = captureGroups(of: rangePattern, in: text, range: range)
            guard groups.count == 6,
                  let firstHour = Int(groups[0]),
                  let secondHour = Int(groups[3]) else {
                throw QuickEntryParseError.invalidClock
            }
            let firstSuffix = groups[2].lowercased()
            let secondSuffix = groups[5].lowercased()
            let hasClockSignal = !groups[1].isEmpty || !firstSuffix.isEmpty
                || !groups[4].isEmpty || !secondSuffix.isEmpty
            guard hasClockSignal else { continue }
            timeRangeRanges.append(range)
            _ = try validatedClock(
                rawHour: firstHour,
                minuteText: groups[1],
                suffix: firstSuffix.isEmpty && groups[1].isEmpty ? secondSuffix : firstSuffix
            )
            _ = try validatedClock(
                rawHour: secondHour,
                minuteText: groups[4],
                suffix: secondSuffix.isEmpty && groups[4].isEmpty ? firstSuffix : secondSuffix
            )
        }

        let isInsideTimeRange: (Range<String.Index>) -> Bool = { candidate in
            timeRangeRanges.contains { $0.lowerBound <= candidate.lowerBound && candidate.upperBound <= $0.upperBound }
        }
        let found = ranges(of: exactPattern, in: text).filter { !isInsideTimeRange($0) }
        let suffixAwareLexicalPattern = "(?i)(?<![\(token):/])((?:at\\s+)?)([0-9:]+)(?:([ap])|\\s*([ap]m))?(?![\(token)])"
        let lexical = ranges(of: suffixAwareLexicalPattern, in: text).filter { !isInsideTimeRange($0) }
        for range in found {
            var cursor = range.upperBound
            while cursor < text.endIndex,
                  text[cursor].unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) {
                cursor = text.index(after: cursor)
            }
            var colonCount = 0
            while cursor < text.endIndex, text[cursor] == ":" {
                colonCount += 1
                cursor = text.index(after: cursor)
            }
            if colonCount >= 2 { throw QuickEntryParseError.invalidClock }
            if colonCount == 1, cursor < text.endIndex,
               text[cursor].unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) {
                throw QuickEntryParseError.invalidClock
            }
        }
        for range in lexical {
            let groups = captureGroups(of: suffixAwareLexicalPattern, in: text, range: range)
            guard groups.count == 4 else { throw QuickEntryParseError.invalidClock }
            let ownsConnector = !groups[0].isEmpty
            let body = groups[1]
            let suffix = [groups[2], groups[3]].first(where: { !$0.isEmpty })?.lowercased() ?? ""
            let hasClockSignal = body.contains(":") || !suffix.isEmpty
            guard hasClockSignal else { continue }

            if found.contains(where: { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }) {
                continue
            }
            if body == ":", suffix.isEmpty { continue }
            if body.hasSuffix(":"), suffix.isEmpty {
                let punctuationEnd = text.index(before: range.upperBound)
                if found.contains(range.lowerBound ..< punctuationEnd) { continue }
            }
            let pieces = body.split(separator: ":", omittingEmptySubsequences: false)
            let isRatio = !ownsConnector && suffix.isEmpty && pieces.count == 2
                && (1 ... 2).contains(pieces[0].count) && pieces[1].count == 1
            guard isRatio else { throw QuickEntryParseError.invalidClock }
        }

        var valid: [ClockMatch] = []
        for range in found {
            let groups = captureGroups(of: exactPattern, in: text, range: range)
            guard groups.count == 5, let rawHour = Int(groups[1]) else { throw QuickEntryParseError.invalidClock }
            let minuteText = groups[2]
            let suffix = [groups[3], groups[4]].first(where: { !$0.isEmpty })?.lowercased() ?? ""
            let (hour, minute) = try validatedClock(rawHour: rawHour, minuteText: minuteText, suffix: suffix)
            valid.append(.init(hour: hour, minute: minute, ranges: [range]))
        }
        if !timeRangeRanges.isEmpty { throw QuickEntryParseError.ambiguousExpression }
        guard !valid.isEmpty else { return nil }
        guard valid.count == 1 else { throw QuickEntryParseError.ambiguousExpression }
        return valid[0]
    }

    static func rejectFusedSlashDateClockOverlap(in text: String) throws {
        let token = "\\p{L}\\p{M}\\p{N}\\p{Pc}"
        let candidatePattern = "(?i)(?<![\(token)/])(?:at\\s+)?([0-9]{1,4})/([0-9]{1,2})(?:/([0-9]{1,4}))?([^\\s]*)(?:\\s+([ap]m?)(?![\(token)]))?"

        func isASCIIDigit(_ character: Character) -> Bool {
            guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
            return (48 ... 57).contains(Int(scalar.value))
        }

        func startsWithTokenCharacter(_ value: Substring) -> Bool {
            guard let first = value.first else { return false }
            return !ranges(of: "^[\(token)]", in: String(first)).isEmpty
        }

        func splitSuffix(_ value: Substring) -> (suffix: String?, remainder: Substring, truncated: Bool, embedded: Bool) {
            if value.hasPrefix("am") || value.hasPrefix("pm") {
                return (String(value.prefix(2)), value.dropFirst(2), false, false)
            }
            if value.first == "a" || value.first == "p" {
                let remainder = value.dropFirst()
                if remainder.isEmpty || !startsWithTokenCharacter(remainder) {
                    return (nil, remainder, true, false)
                }
                return (nil, remainder, false, true)
            }
            return (nil, value, false, false)
        }

        for range in ranges(of: candidatePattern, in: text) {
            let groups = captureGroups(of: candidatePattern, in: text, range: range)
            guard groups.count == 5,
                  let rawHour = Int(groups[2].isEmpty ? groups[1] : groups[2]) else { continue }
            var attached = groups[3].lowercased()[...]
            let spacedSuffix = groups[4].lowercased()
            var minuteText = ""
            var suffix = ""
            var hasClockCore = false

            if attached.first == ":" {
                let afterColon = attached.dropFirst()
                guard afterColon.first.map(isASCIIDigit) == true else { continue }
                let minuteDigits = afterColon.prefix(while: isASCIIDigit)
                guard minuteDigits.count == 2 else { throw QuickEntryParseError.invalidClock }
                minuteText = String(minuteDigits)
                attached = afterColon.dropFirst(minuteDigits.count)
                hasClockCore = true

                let parsedSuffix = splitSuffix(attached)
                if parsedSuffix.truncated { throw QuickEntryParseError.invalidClock }
                if parsedSuffix.embedded { continue }
                if let parsed = parsedSuffix.suffix {
                    suffix = parsed
                    attached = parsedSuffix.remainder
                }
            } else {
                let parsedSuffix = splitSuffix(attached)
                if parsedSuffix.truncated { throw QuickEntryParseError.invalidClock }
                if parsedSuffix.embedded { continue }
                if let parsed = parsedSuffix.suffix {
                    suffix = parsed
                    attached = parsedSuffix.remainder
                    hasClockCore = true
                } else if attached.isEmpty {
                    if spacedSuffix == "am" || spacedSuffix == "pm" {
                        suffix = spacedSuffix
                        hasClockCore = true
                    } else {
                        continue
                    }
                } else {
                    continue
                }
            }

            guard hasClockCore else { continue }
            if attached.isEmpty, suffix.isEmpty, !spacedSuffix.isEmpty {
                guard spacedSuffix == "am" || spacedSuffix == "pm" else {
                    throw QuickEntryParseError.invalidClock
                }
                suffix = spacedSuffix
            }

            if let first = attached.first {
                if first == ":" {
                    let afterSeam = attached.dropFirst()
                    if let next = afterSeam.first, isASCIIDigit(next) || next == ":" {
                        throw QuickEntryParseError.invalidClock
                    }
                } else if first != "/", startsWithTokenCharacter(attached) {
                    continue
                }
            }
            _ = try validatedClock(
                rawHour: rawHour,
                minuteText: minuteText,
                suffix: suffix
            )
            throw QuickEntryParseError.ambiguousExpression
        }
    }

    static func validatedClock(rawHour: Int, minuteText: String, suffix: String) throws -> (hour: Int, minute: Int) {
        guard minuteText.isEmpty || minuteText.count == 2 else { throw QuickEntryParseError.invalidClock }
        let minute = minuteText.isEmpty ? 0 : Int(minuteText) ?? -1
        guard (0 ... 59).contains(minute) else { throw QuickEntryParseError.invalidClock }
        var hour: Int
        if suffix.isEmpty {
            guard (0 ... 23).contains(rawHour) else { throw QuickEntryParseError.invalidClock }
            hour = rawHour
        } else {
            guard suffix == "am" || suffix == "pm", (1 ... 12).contains(rawHour) else {
                throw QuickEntryParseError.invalidClock
            }
            hour = rawHour == 12 ? 0 : rawHour
            if suffix == "pm" { hour += 12 }
        }
        return (hour, minute)
    }

    static func scheduledDate(
        date: DateMatch?,
        clock: ClockMatch?,
        recurrence: RecurrenceMatch?,
        context: QuickEntryParseContext
    ) throws -> Date? {
        guard let date else {
            guard let clock else { return nil }
            if recurrence?.rule.frequency == .weekly, let weekdays = recurrence?.rule.weekdays, !weekdays.isEmpty {
                for dayOffset in 0 ... 7 {
                    guard let day = context.calendar.date(byAdding: .day, value: dayOffset, to: context.calendar.startOfDay(for: context.now)) else {
                        throw QuickEntryParseError.invalidDate
                    }
                    guard weekdays.contains(context.calendar.component(.weekday, from: day)) else { continue }
                    let candidate = try requireLocalDate(day: day, clock: clock, context: context)
                    if candidate > context.now { return candidate }
                }
                throw QuickEntryParseError.invalidDate
            }
            var day = context.calendar.startOfDay(for: context.now)
            var candidate = try requireLocalDate(day: day, clock: clock, context: context)
            if candidate <= context.now {
                guard let tomorrow = context.calendar.date(byAdding: .day, value: 1, to: day) else { throw QuickEntryParseError.invalidDate }
                day = tomorrow
                candidate = try requireLocalDate(day: day, clock: clock, context: context)
            }
            return candidate
        }
        guard let clock else { return date.day }
        var candidate = try requireLocalDate(day: date.day, clock: clock, context: context)
        if date.style == .bareWeekday, candidate < context.now {
            guard let nextWeek = context.calendar.date(byAdding: .day, value: 7, to: date.day) else { throw QuickEntryParseError.invalidDate }
            candidate = try requireLocalDate(day: nextWeek, clock: clock, context: context)
        }
        return candidate
    }

    static func requireLocalDate(day: Date, clock: ClockMatch, context: QuickEntryParseContext) throws -> Date {
        let parts = context.calendar.dateComponents([.year, .month, .day], from: day)
        guard let date = localDate(year: parts.year, month: parts.month, day: parts.day, hour: clock.hour, minute: clock.minute, context: context) else {
            throw QuickEntryParseError.nonexistentLocalTime
        }
        return date
    }

    static func localDate(year: Int?, month: Int?, day: Int?, hour: Int, minute: Int, context: QuickEntryParseContext) -> Date? {
        guard let year, let month, let day else { return nil }
        let start = context.calendar.date(from: DateComponents(timeZone: context.timeZone, year: year, month: month, day: day))
        guard let start else { return nil }
        let wanted = DateComponents(timeZone: context.timeZone, hour: hour, minute: minute, second: 0)
        guard let candidate = context.calendar.nextDate(after: start.addingTimeInterval(-1), matching: wanted, matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward) else { return nil }
        let actual = context.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate)
        guard actual.year == year, actual.month == month, actual.day == day, actual.hour == hour, actual.minute == minute else { return nil }
        return candidate
    }

    static func cleanedTitle(_ text: String, removing rangesToRemove: [Range<String.Index>]) -> String {
        let sorted = rangesToRemove.sorted { $0.lowerBound < $1.lowerBound }
        var syntaxRanges: [Range<String.Index>] = []
        for range in sorted {
            if let last = syntaxRanges.last, range.lowerBound <= last.upperBound {
                syntaxRanges[syntaxRanges.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else { syntaxRanges.append(range) }
        }
        guard !syntaxRanges.isEmpty else { return text }

        let seamDelimiters = CharacterSet(charactersIn: ",;:")
        var removalRanges: [Range<String.Index>] = []
        for range in syntaxRanges {
            if let last = removalRanges.last {
                let gap = text[last.upperBound ..< range.lowerBound]
                let isSyntaxSeam = gap.unicodeScalars.allSatisfy {
                    CharacterSet.whitespacesAndNewlines.contains($0) || seamDelimiters.contains($0)
                }
                if isSyntaxSeam {
                    removalRanges[removalRanges.count - 1] = last.lowerBound ..< range.upperBound
                    continue
                }
            }
            removalRanges.append(range)
        }

        let closingPunctuation = CharacterSet(charactersIn: "!?.,;:")
        removalRanges = removalRanges.map { range in
            var lowerBound = range.lowerBound
            var upperBound = range.upperBound
            var right = upperBound
            while right < text.endIndex, text[right].unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) {
                right = text.index(after: right)
            }
            let isClosingPunctuation = right < text.endIndex
                && text[right].unicodeScalars.allSatisfy(closingPunctuation.contains)
            let isDelimiterSeam = right < text.endIndex
                && text[right].unicodeScalars.allSatisfy(seamDelimiters.contains)
            if isClosingPunctuation, right == range.upperBound || isDelimiterSeam {
                while lowerBound > text.startIndex {
                    let previous = text.index(before: lowerBound)
                    guard text[previous].unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) else { break }
                    lowerBound = previous
                }
                upperBound = right
            }
            return lowerBound ..< upperBound
        }

        let removesLeadingSyntax = text[..<removalRanges[0].lowerBound].unicodeScalars.allSatisfy(
            CharacterSet.whitespacesAndNewlines.contains
        )
        var result = text
        for range in removalRanges.reversed() { result.removeSubrange(range) }
        result = normalizedWhitespace(result)
        if removesLeadingSyntax {
            let leadingArtifacts = CharacterSet(charactersIn: ",;:-")
            while let first = result.first,
                  first.unicodeScalars.allSatisfy({
                      CharacterSet.whitespacesAndNewlines.contains($0) || leadingArtifacts.contains($0)
                  }) {
                result.removeFirst()
            }
        }
        return result
    }

    enum NumericDateField: Equatable { case year, month, day }

    static func numericDateFieldOrder(locale: Locale) -> [NumericDateField] {
        guard let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) else {
            return [.day, .month, .year]
        }
        var order: [NumericDateField] = []
        var isQuoted = false
        for character in pattern {
            if character == "'" { isQuoted.toggle(); continue }
            guard !isQuoted else { continue }
            let field: NumericDateField?
            switch character {
            case "y", "Y": field = .year
            case "M", "L": field = .month
            case "d", "D": field = .day
            default: field = nil
            }
            if let field, !order.contains(field) { order.append(field) }
        }
        return order.count == 3 ? order : [.day, .month, .year]
    }

    static func hasUsableTitleContent(_ title: String) -> Bool {
        title.unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.symbols.contains(scalar)
        }
    }

    static func ranges(of pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: full).compactMap { Range($0.range, in: text) }
    }

    static func captureGroups(of pattern: String, in text: String, range: Range<String.Index>) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(range, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return [] }
        return (1 ..< match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
