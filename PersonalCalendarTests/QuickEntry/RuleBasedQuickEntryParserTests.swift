import XCTest
@testable import PersonalCalendar

final class RuleBasedQuickEntryParserTests: XCTestCase {
    // MARK: - API and isolation

    func testParserCanBeUsedThroughProtocolExistential() throws {
        let parser: any QuickEntryParsing = RuleBasedQuickEntryParser()

        XCTAssertEqual(try parser.parse("Call Alex", context: singaporeContext()).kind, .task)
    }

    func testParserContractAndContextAreSendable() {
        assertSendable(RuleBasedQuickEntryParser())
        assertSendable(singaporeContext())
        let parser: any QuickEntryParsing = RuleBasedQuickEntryParser()
        assertSendable(parser)
    }

    func testQuickEntryPreviewIsSendable() {
        assertSendableType(QuickEntryPreview.self)
        assertHashableType(QuickEntryParseWarning.self)
    }

    func testPreviewWarningsAreAUniqueHashableSet() throws {
        let preview = try parse("Call today at 9am")
        let warnings: Set<QuickEntryParseWarning> = preview.warnings

        XCTAssertEqual(warnings, [.scheduledTimeIsPast])
    }

    func testParserCanParseFromDetachedTask() async throws {
        let context = singaporeContext()
        let preview = try await Task.detached {
            try RuleBasedQuickEntryParser().parse("Dentist Friday at 3pm", context: context)
        }.value

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.title, "Dentist")
    }

    // MARK: - Classification

    func testAppointmentWithDateAndClockIsAnEvent() throws {
        let preview = try parse("Dentist Friday at 3pm")

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.title, "Dentist")
        assertTime(preview.startDate, hour: 15, minute: 0)
        XCTAssertEqual(preview.endDate?.timeIntervalSince(preview.startDate!), 3_600)
    }

    func testDateOnlyActionIsATask() throws {
        let preview = try parse("Submit report tomorrow")

        XCTAssertEqual(preview.kind, .task)
        XCTAssertEqual(preview.title, "Submit report")
        XCTAssertNotNil(preview.dueDate)
        XCTAssertFalse(preview.dueHasTime)
    }

    func testStrongWindowHabitWithClockIsARoutine() throws {
        let preview = try parse("Read every night at 9pm")

        XCTAssertEqual(preview.kind, .routine)
        XCTAssertEqual(preview.title, "Read")
        XCTAssertEqual(preview.routineWindow, .evening)
        XCTAssertEqual(preview.recurrence?.frequency, .daily)
        XCTAssertEqual(preview.reminderDate.map { singaporeContext().calendar.component(.hour, from: $0) }, 21)
    }

    func testGenericWeeklyRecurrenceWithClockIsAnEvent() throws {
        let preview = try parse("Team sync every Monday at 10am")

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.title, "Team sync")
        XCTAssertEqual(preview.recurrence?.frequency, .weekly)
        XCTAssertEqual(preview.recurrence?.weekdays, [2])
        assertTime(preview.startDate, hour: 10, minute: 0)
    }

    func testTwentyFourHourClockIsAnEvent() throws {
        let preview = try parse("Dentist Friday at 15:00")

        XCTAssertEqual(preview.kind, .event)
        assertTime(preview.startDate, hour: 15, minute: 0)
    }

    func testFutureClockOnlySchedulesToday() throws {
        let context = singaporeContext(hour: 10, minute: 0)
        let preview = try parse("Call Alex at 3pm", context: context)

        XCTAssertEqual(preview.kind, .event)
        assertDate(preview.startDate, year: 2026, month: 8, day: 24, hour: 15, minute: 0, context: context)
    }

    func testClockWithoutAtConnectorIsAnEvent() throws {
        let preview = try parse("Call Alex 3pm")

        XCTAssertEqual(preview.kind, .event)
        assertTime(preview.startDate, hour: 15, minute: 0)
        XCTAssertEqual(preview.title, "Call Alex")
    }

    func testPastClockOnlyRollsToTomorrow() throws {
        let context = singaporeContext(hour: 16, minute: 0)
        let preview = try parse("Call Alex at 3pm", context: context)

        XCTAssertEqual(preview.kind, .event)
        assertDate(preview.startDate, year: 2026, month: 8, day: 25, hour: 15, minute: 0, context: context)
    }

    func testPlainTextIsAnUnscheduledTask() throws {
        let preview = try parse("Call Alex")

        XCTAssertEqual(preview.kind, .task)
        XCTAssertNil(preview.dueDate)
        XCTAssertFalse(preview.dueHasTime)
    }

    func testGenericDailyRecurrenceWithoutClockIsARoutine() throws {
        let preview = try parse("Stretch daily")

        XCTAssertEqual(preview.kind, .routine)
        XCTAssertEqual(preview.routineWindow, .anytime)
    }

    func testEveryWeekdayWithoutClockIsARoutine() throws {
        let preview = try parse("Review every Monday")

        XCTAssertEqual(preview.kind, .routine)
        XCTAssertEqual(preview.weekdays, [2])
    }

    // MARK: - Title ranges and cleanup

    func testTitleCleanupPreservesWordsBetweenIndependentDateAndClockRanges() throws {
        XCTAssertEqual(try parse("Meet Friday with Alex at 3pm").title, "Meet with Alex")
    }

    func testTitleCleanupWorksWhenSyntaxAppearsBeforeTheTitle() throws {
        XCTAssertEqual(try parse("Friday at 3pm, meet Alex").title, "meet Alex")
    }

    func testTitleCleanupRemovesOnlySyntaxOwnedConnectorsAndPreservesPunctuation() throws {
        XCTAssertEqual(try parse("Call Alex on Friday, at 3pm!").title, "Call Alex!")
    }

    func testTokenBoundariesDoNotTreatEmbeddedWordsAsDateSyntax() throws {
        for text in ["Review FridayReport", "Read DailyMail", "Call Mondayish"] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .task, text)
            XCTAssertEqual(preview.title, text, text)
        }
    }

    func testUnicodeLettersKeepEmbeddedDateWordsOutOfSyntax() throws {
        let preview = try parse("Plan caféToday")

        XCTAssertEqual(preview.kind, .task)
        XCTAssertEqual(preview.title, "Plan caféToday")
        XCTAssertNil(preview.dueDate)
    }

    func testDecomposedCombiningMarksProtectEmbeddedSyntaxLikePrecomposedLetters() throws {
        let pairs = [
            ("Plan caféToday", "Plan cafe\u{301}Today"),
            ("Plan caféDaily", "Plan cafe\u{301}Daily"),
            ("Plan café3pm", "Plan cafe\u{301}3pm"),
            ("Plan café03/09/2026", "Plan cafe\u{301}03/09/2026")
        ]

        for (precomposed, decomposed) in pairs {
            for text in [precomposed, decomposed] {
                let preview = try parse(text)
                XCTAssertEqual(preview.kind, .task, text)
                XCTAssertEqual(preview.title, text, text)
                XCTAssertNil(preview.startDate, text)
                XCTAssertNil(preview.dueDate, text)
                XCTAssertNil(preview.recurrence, text)
            }
        }
    }

    func testOverlappingOrAdjacentSyntaxRangesAreRemovedOnce() throws {
        XCTAssertEqual(try parse("Read every Monday at 10am").title, "Read")
    }

    // MARK: - Invalid or unusable input

    func testUnicodeWhitespaceOnlyInputThrowsEmptyInput() {
        assertError(.emptyInput, for: "\u{00A0}\u{202F}\n\t")
    }

    func testUnicodeWhitespaceIsNormalizedBeforeSyntaxOnlyTitleValidation() {
        assertError(.noUsableTitle, for: "\u{00A0}Friday\u{202F}at\u{00A0}3pm\u{00A0}")
    }

    func testSyntaxOnlyRecurrenceThrowsNoUsableTitle() {
        assertError(.noUsableTitle, for: "every day")
    }

    func testPunctuationOnlyRemainderThrowsNoUsableTitle() {
        for text in ["!!! Friday at 3pm", "— — tomorrow"] {
            assertError(.noUsableTitle, for: text)
        }
    }

    func testMeaningfulPunctuationAndEmojiRemainUsableTitles() throws {
        let punctuated = try parse("Call Mom! Friday at 3pm")
        let emoji = try parse("🎂 Friday at 3pm")

        XCTAssertEqual(punctuated.title, "Call Mom!")
        XCTAssertEqual(emoji.title, "🎂")
    }

    func testInvalidClockFormsThrowInvalidClock() {
        for text in [
            "Call at 25:00", "Call at 12:99", "Call at 13pm", "Call at 0pm",
            "Call at 15:00pm", "Call 25:00", "Call 13pm", "Call at 9:6pm", "Call at 0:0am"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testMalformedClockShapesWithRepeatedOrOversizedFieldsThrowInvalidClock() {
        for text in ["Call at 9::30", "Call at 123:45"] {
            assertError(.invalidClock, for: text)
        }
    }

    func testIncompleteSecondsAndLongHourClockShapesThrowInvalidClock() {
        for text in [
            "Call at 9:", "Call at :30", "Call at 9:30:45", "Call at 1234:56",
            "Call 9:", "Call :30", "Call 9:30:45", "Call 1234:56"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testConnectorFreeTruncatedClockSuffixesAndDoubleColonThrowInvalidClock() {
        for text in ["Call 9p", "Call 9a", "Call 9:30p", "Call 9:30a", "Call ::30"] {
            assertError(.invalidClock, for: text)
        }
    }

    func testSpacedTruncatedMeridiemClockShapesThrowInvalidClock() {
        for text in [
            "Call at 9 p", "Call at 9 a", "Call at 9:30 p", "Call at 9:30 a",
            "Call 9:30 p", "Call 9:30 a"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testDotSeparatedPartialMeridiemClockShapesThrowInvalidClock() {
        for text in [
            "Call 9.3pm", "Call at 9.3pm", "Call 9.30pm", "Call at 9.30pm",
            "Call 9.3am", "Call at 9.3am", "Call 9.30am", "Call at 9.30am"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testLongOrMissingHourDottedMeridiemShapesThrowInvalidClock() {
        for text in ["Call 123.3pm", "Call at 123.3pm", "Call .3pm", "Call at .3am"] {
            assertError(.invalidClock, for: text)
        }
    }

    func testSpacedDottedMeridiemShapesThrowInvalidClockWithoutTrailingSalvage() {
        for text in [
            "Call 9.3 pm", "Call at 9.3 pm", "Call 123.3 pm", "Call at 123.3 pm",
            "Call 9.3 am", "Call at 9.3 am", "Call 123.3 am", "Call at 123.3 am",
            "Call 9.3:30pm", "Call at 9.3:30pm", "Call 9.3:30am", "Call at 9.3:30am",
            "Call .3 am", "Call at .3 am"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testDottedColonCompoundsAndTruncatedSuffixHybridsThrowInvalidClock() {
        for text in [
            "Call 9.3:30", "Call at 9.3:30", "Call 9.15:00", "Call at 123.3:30",
            "Call at 9.3:30 p", "Call at 9.3:30 a",
            "Call at 9.3 p", "Call at 9.3 a"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testFusedSlashDateAndClockTokensThrowAmbiguousExpression() {
        for text in ["Call 9/3pm", "Call at 9/3pm", "Call 9/3:30pm", "Call at 9/3:30am"] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testFusedSlashDateAndTwentyFourHourTokensThrowAmbiguousBeforeLocaleResolution() {
        let singapore = singaporeContext(locale: "en_SG")
        let unitedStates = singaporeContext(locale: "en_US")

        for text in ["Call 9/3:30", "Call at 9/3:30"] {
            assertError(.ambiguousExpression, for: text, context: singapore)
        }
        for text in ["Call 9/15:00", "Call at 9/15:00"] {
            assertError(.ambiguousExpression, for: text, context: unitedStates)
        }
    }

    func testMalformedFusedSlashClockTakesInvalidClockPrecedenceOverAmbiguity() {
        for text in [
            "Call 9/3:99", "Call at 9/3:99",
            "Call 9/25:00", "Call at 9/25:00",
            "Call 9/3:30:45", "Call at 9/3:30:45",
            "Call 9/3:30 p", "Call at 9/3:30 p",
            "Call 9/3:30::", "Call at 9/3:30::"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testFusedSlashTokensOutsideDateGrammarDoNotSalvageValidClockTails() {
        for text in [
            "Call 123/3pm", "Call at 123/3pm",
            "Call 2026/9pm", "Call at 2026/9pm",
            "Call 9/3/3pm", "Call at 9/3/3pm",
            "Call 2026/9/3:30", "Call at 2026/9/3:30"
        ] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testMalformedClockTailInSlashTokenStillTakesInvalidClockPrecedence() {
        for text in [
            "Call 123/25:00", "Call at 123/25:00",
            "Call 2026/9:99", "Call at 2026/9:99",
            "Call 9/3/3:30:45", "Call at 9/3/3:30:45"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testLongTwoPartSlashDateRetainsInvalidDateBehavior() {
        assertError(.invalidDate, for: "Call 123/3")
    }

    func testFusedSlashClockSeamsWithTitlePunctuationRemainAmbiguous() {
        for text in [
            "Call 9/3pm: discuss", "Call at 9/3pm: discuss",
            "Call 9/3pm:discuss", "Call at 9/3pm:discuss",
            "Call 9/3:30:abc", "Call at 9/3:30:abc",
            "Call 9/3pm/notes", "Call at 9/3pm/notes"
        ] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testCompleteFusedSlashClockFollowedBySingleLetterProseRemainsAmbiguous() {
        for text in [
            "Call 9/3pm a day", "Call at 9/3pm a day",
            "Call 9/3pm A batteries", "Call at 9/3pm A batteries",
            "Call 9/3:30pm p units", "Call at 9/3:30pm p units"
        ] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testFusedSlashClockWithSpacedFullMeridiemRemainsAmbiguous() {
        for text in [
            "Call 9/3 pm", "Call at 9/3 pm",
            "Call 9/3 am", "Call at 9/3 am",
            "Call 9/3:30 pm", "Call at 9/3:30 pm"
        ] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testFusedSlashNumericSecondsRemainInvalidClockAtTheSeam() {
        for text in ["Call 9/3:30:45", "Call at 9/3:30:45"] {
            assertError(.invalidClock, for: text)
        }
    }

    func testOrdinaryClockFollowedByArticleProseRemainsAValidEvent() throws {
        for (text, title) in [
            ("Call 3pm a day", "Call a day"),
            ("Call at 3pm A batteries", "Call A batteries")
        ] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .event, text)
            XCTAssertEqual(preview.title, title, text)
            assertTime(preview.startDate, hour: 15, minute: 0)
        }
    }

    func testSeparatedDotPunctuationBeforeValidClockRemainsAnEvent() throws {
        let preview = try parse("Version 9. 3:30pm")

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.title, "Version 9.")
        assertTime(preview.startDate, hour: 15, minute: 30)
    }

    func testCompleteClockSuffixesRemainValidEvents() throws {
        for (text, minute) in [("Call 9pm", 0), ("Call 9:30pm", 30)] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .event, text)
            XCTAssertEqual(preview.title, "Call", text)
            assertTime(preview.startDate, hour: 21, minute: minute)
        }
    }

    func testFullSpacedMeridiemSuffixesRemainValidEvents() throws {
        for (text, hour, minute) in [
            ("Call 9 pm", 21, 0),
            ("Call 9:30 am", 9, 30),
            ("Call at 9:30 am", 9, 30)
        ] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .event, text)
            XCTAssertEqual(preview.title, "Call", text)
            assertTime(preview.startDate, hour: hour, minute: minute)
        }
    }

    func testArticleAAfterOrdinaryNumberRemainsPlainTaskText() throws {
        for text in ["Buy 9 a day", "Take 2 a day", "Take 2 a week", "Buy 9 A batteries"] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .task, text)
            XCTAssertEqual(preview.title, text, text)
            XCTAssertNil(preview.dueDate, text)
        }
    }

    func testEmbeddedClockLikeTextAndNonTimeColonsRemainTasks() throws {
        for text in ["Call A9p", "Call A9:30p", "Ratio9:6", "Discuss chapter:30"] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .task, text)
            XCTAssertEqual(preview.title, text, text)
            XCTAssertNil(preview.dueDate, text)
        }
    }

    func testSharedSuffixTimeRangesThrowAmbiguousExpression() {
        for text in [
            "Meet 9-10am", "Meet 9–10am", "Meet 9 to 10am",
            "Meet at 9-10am", "Meet at 9–10am", "Meet at 9 to 10am",
            "Meet 9am-10am"
        ] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testTimeRangesWithClockSignalOnlyOnFirstEndpointAreAmbiguous() {
        for text in [
            "Meet 9am-10",
            "Meet at 9am-10",
            "Meet 9:30am to 10",
            "Meet at 9:00-10"
        ] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testTimeRangesWithClockSignalOnlyOnSecondEndpointAreAmbiguous() {
        for text in ["Meet 9-15:00", "Meet 9 to 15:00"] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testMalformedTimeRangeEndpointTakesInvalidClockPrecedence() {
        for text in ["Meet 9am-25:00", "Meet 25:00-9am"] {
            assertError(.invalidClock, for: text)
        }
    }

    func testIndependentTwentyFourHourEndpointDoesNotInheritMeridiemFromRangeEnd() {
        for text in ["Meet 15:00-10am", "Meet 0:00-1pm"] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testInvalidLexicalClockOutranksOtherwiseValidSharedSuffixRange() {
        for text in ["Meet 9-10am at 25:00", "Meet at 25:00 then 9-10am"] {
            assertError(.invalidClock, for: text)
        }
    }

    func testHyphenatedVersionNumbersRemainTasks() throws {
        let preview = try parse("Version 9-10")

        XCTAssertEqual(preview.kind, .task)
        XCTAssertEqual(preview.title, "Version 9-10")
        XCTAssertNil(preview.dueDate)
    }

    func testColonAfterValidClockIsTitlePunctuationForConnectedAndConnectorFreeForms() throws {
        for (text, hour) in [
            ("Meet at 3pm: discuss", 15),
            ("Meet at 15:00: discuss", 15),
            ("Meet 3pm: discuss", 15),
            ("Meet 15:00: discuss", 15)
        ] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .event, text)
            XCTAssertEqual(preview.title, "Meet: discuss", text)
            assertTime(preview.startDate, hour: hour, minute: 0)
        }
    }

    func testSpacedSingleColonAfterValidClockRemainsTitlePunctuation() throws {
        let preview = try parse("Meet at 9:30 : discuss")

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.title, "Meet: discuss")
        assertTime(preview.startDate, hour: 9, minute: 30)

        let punctuation = try parse("Meet 9:30 ! discuss")
        XCTAssertEqual(punctuation.kind, .event)
        XCTAssertEqual(punctuation.title, "Meet ! discuss")
        assertTime(punctuation.startDate, hour: 9, minute: 30)
    }

    func testClockWithSecondsRemainsInvalid() {
        for text in ["Meet at 15:00:30", "Meet 15:00:30"] {
            assertError(.invalidClock, for: text)
        }
    }

    func testTwoOrMoreColonsAfterValidClockThrowInvalidClock() {
        for text in [
            "Meet at 15:00:: discuss", "Meet at 15:00 :: discuss",
            "Meet 15:00:: discuss", "Meet 15:00 :: discuss",
            "Meet at 3pm:: discuss", "Meet at 3pm :: discuss",
            "Meet 3pm:: discuss", "Meet 3pm :: discuss"
        ] {
            assertError(.invalidClock, for: text)
        }
    }

    func testOrdinaryNumbersVersionsAndNonTimeColonsAreNotClockErrors() throws {
        for text in ["Buy 123 apples", "Release version 1.2", "Discuss chapter:30", "Ratio 9:6"] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .task, text)
            XCTAssertEqual(preview.title, text, text)
            XCTAssertNil(preview.dueDate, text)
        }
    }

    func testDotSeparatedVersionNumbersRemainExactTasks() throws {
        for text in ["Version 9.3", "Release 1.2"] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .task, text)
            XCTAssertEqual(preview.title, text, text)
            XCTAssertNil(preview.dueDate, text)
        }
    }

    func testDecimalNumbersFollowedBySpacedArticlesRemainExactTasks() throws {
        for text in ["Take 9.3 a day", "Dose 1.2 A day", "Take 0.5 a week"] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .task, text)
            XCTAssertEqual(preview.title, text, text)
            XCTAssertNil(preview.dueDate, text)
        }
    }

    func testConnectorFreeDecimalProseWithSpacedLetterRemainsExactTask() throws {
        let preview = try parse("Value 9.3 p units")

        XCTAssertEqual(preview.kind, .task)
        XCTAssertEqual(preview.title, "Value 9.3 p units")
        XCTAssertNil(preview.dueDate)
    }

    func testConnectorPunctuationBoundSyntaxLikeTokensRemainExactTasks() throws {
        for text in [
            "Call 9_3pm", "Meet _3pm", "foo_3pm", "Release_3pm",
            "project_daily", "plan_Friday"
        ] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .task, text)
            XCTAssertEqual(preview.title, text, text)
            XCTAssertNil(preview.dueDate, text)
        }
    }

    func testInvalidExplicitDateThrowsInvalidDate() {
        assertError(.invalidDate, for: "Plan 31/02/2026")
    }

    func testConflictingDateExpressionsThrowAmbiguousExpression() {
        assertError(.ambiguousExpression, for: "Meet today tomorrow at 3pm")
    }

    func testDistinctDatePhrasesResolvingToSameDayAreAmbiguous() {
        let monday = singaporeContext(hour: 10, minute: 0)

        assertError(.ambiguousExpression, for: "Meet today Monday at 3pm", context: monday)
    }

    func testDuplicateDatePhrasesAreAmbiguous() {
        assertError(.ambiguousExpression, for: "Meet today today at 3pm")
    }

    func testNextAndEveryWeekdayPhrasesRemainValid() throws {
        let next = try parse("Meet next Monday at 3pm")
        let every = try parse("Meet every Monday at 3pm")

        XCTAssertEqual(next.kind, .event)
        XCTAssertNil(next.recurrence)
        XCTAssertEqual(every.kind, .event)
        XCTAssertEqual(every.recurrence?.weekdays, [2])
    }

    func testWeeklyRecurrenceRejectsMismatchedExplicitWeekday() {
        assertError(.ambiguousExpression, for: "Team sync every Monday on Tuesday at 10am")
    }

    func testWeeklyRecurrenceAcceptsAlignedExplicitWeekday() throws {
        let preview = try parse("Team sync every Monday on Monday at 10am")

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.title, "Team sync")
        XCTAssertEqual(preview.recurrence?.weekdays, [2])
        XCTAssertEqual(singaporeContext().calendar.component(.weekday, from: try XCTUnwrap(preview.startDate)), 2)
    }

    func testEveryWeeklyEventStartsOnAWeekdayBelongingToItsRule() throws {
        let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

        for (offset, weekdayName) in weekdayNames.enumerated() {
            let preview = try parse("Meet every \(weekdayName) at 3pm")
            let start = try XCTUnwrap(preview.startDate, weekdayName)
            let startWeekday = singaporeContext().calendar.component(.weekday, from: start)
            XCTAssertEqual(preview.kind, .event, weekdayName)
            XCTAssertEqual(preview.recurrence?.weekdays, [offset + 1], weekdayName)
            XCTAssertEqual(startWeekday, offset + 1, weekdayName)
        }
    }

    func testRecurrenceWithIndependentDateAndNoClockIsAmbiguous() {
        for text in ["Review every Monday tomorrow", "Read every night tomorrow"] {
            assertError(.ambiguousExpression, for: text)
        }
    }

    func testRecurrenceWithoutIndependentDateRemainsValid() throws {
        let generic = try parse("Review every Monday")
        let strong = try parse("Read every night")

        XCTAssertEqual(generic.kind, .routine)
        XCTAssertEqual(generic.recurrence?.weekdays, [2])
        XCTAssertEqual(strong.kind, .routine)
        XCTAssertEqual(strong.routineWindow, .evening)
    }

    func testConflictingClockExpressionsThrowAmbiguousExpression() {
        assertError(.ambiguousExpression, for: "Meet Friday at 3pm at 4pm")
    }

    // MARK: - Calendar, locale, and time-zone behavior

    func testClockRolloverUsesTomorrowAfterElapsedTime() throws {
        let context = singaporeContext(hour: 23, minute: 59)
        let preview = try parse("Water plants at 12:01am", context: context)

        assertDate(preview.startDate, year: 2026, month: 8, day: 25, hour: 0, minute: 1, context: context)
    }

    func testClockRolloverCrossesFromDecemberIntoTheNextYear() throws {
        let context = self.context(
            timeZoneIdentifier: "Asia/Singapore",
            year: 2026,
            month: 12,
            day: 31,
            hour: 23,
            minute: 59
        )
        let preview = try parse("Toast at 12:01am", context: context)

        assertDate(preview.startDate, year: 2027, month: 1, day: 1, hour: 0, minute: 1, context: context)
    }

    func testBareWeekdayUsesSameDayWhenClockIsStillFuture() throws {
        let context = singaporeContext(hour: 10, minute: 0) // Monday
        let preview = try parse("Lunch Monday at 11am", context: context)

        assertDate(preview.startDate, year: 2026, month: 8, day: 24, hour: 11, minute: 0, context: context)
    }

    func testBareWeekdayWithElapsedSameDayClockMovesOneWeek() throws {
        let context = singaporeContext(hour: 10, minute: 0) // Monday
        let preview = try parse("Lunch Monday at 9am", context: context)

        assertDate(preview.startDate, year: 2026, month: 8, day: 31, hour: 9, minute: 0, context: context)
    }

    func testBareWeekdayAtExactNowStaysOnToday() throws {
        let context = singaporeContext(hour: 10, minute: 0, second: 0) // Monday
        let preview = try parse("Lunch Monday at 10am", context: context)

        assertDate(preview.startDate, year: 2026, month: 8, day: 24, hour: 10, minute: 0, context: context)
    }

    func testBareWeekdayOneSecondAfterClockMovesOneWeek() throws {
        let context = singaporeContext(hour: 10, minute: 0, second: 1) // Monday
        let preview = try parse("Lunch Monday at 10am", context: context)

        assertDate(preview.startDate, year: 2026, month: 8, day: 31, hour: 10, minute: 0, context: context)
    }

    func testClockOnlyAtExactNowMovesToTomorrow() throws {
        let context = singaporeContext(hour: 10, minute: 0, second: 0)
        let preview = try parse("Call Alex at 10am", context: context)

        assertDate(preview.startDate, year: 2026, month: 8, day: 25, hour: 10, minute: 0, context: context)
    }

    func testNextWeekdayIsStrictlyInTheFuture() throws {
        let context = singaporeContext(hour: 10, minute: 0) // Monday
        let preview = try parse("Lunch next Monday at 9am", context: context)

        assertDate(preview.startDate, year: 2026, month: 8, day: 31, hour: 9, minute: 0, context: context)
    }

    func testOnNextWeekdayRemovesTheWholeOwnedConnectorFromTitle() throws {
        let context = singaporeContext(hour: 10, minute: 0) // Monday
        let preview = try parse("Meet on next Monday at 3pm", context: context)

        XCTAssertEqual(preview.title, "Meet")
        assertDate(preview.startDate, year: 2026, month: 8, day: 31, hour: 15, minute: 0, context: context)
    }

    func testWeekdaysAtElapsedFridayClockAnchorsTheFollowingMonday() throws {
        let fridayAfterClock = self.context(
            timeZoneIdentifier: "Asia/Singapore",
            year: 2026,
            month: 8,
            day: 28,
            hour: 10,
            minute: 0
        )
        let preview = try parse("Standup weekdays at 9am", context: fridayAfterClock)

        assertDate(preview.startDate, year: 2026, month: 8, day: 31, hour: 9, minute: 0, context: fridayAfterClock)
    }

    func testWeekdaysAtClockAnchorsMondayWhenNowIsSaturday() throws {
        let saturday = self.context(
            timeZoneIdentifier: "Asia/Singapore",
            year: 2026,
            month: 8,
            day: 29,
            hour: 10,
            minute: 0
        )
        let preview = try parse("Standup weekdays at 9am", context: saturday)

        assertDate(preview.startDate, year: 2026, month: 8, day: 31, hour: 9, minute: 0, context: saturday)
    }

    func testWeekdaysAtFutureClockUsesTheCurrentEligibleWeekday() throws {
        let tuesdayBeforeClock = self.context(
            timeZoneIdentifier: "Asia/Singapore",
            year: 2026,
            month: 8,
            day: 25,
            hour: 8,
            minute: 0
        )
        let preview = try parse("Standup weekdays at 9am", context: tuesdayBeforeClock)

        assertDate(preview.startDate, year: 2026, month: 8, day: 25, hour: 9, minute: 0, context: tuesdayBeforeClock)
    }

    func testOneMonthRelativeDateUsesInjectedCalendar() throws {
        let preview = try parse("Renew passport in 1 month")

        assertDate(preview.dueDate, year: 2026, month: 9, day: 24, hour: 0, minute: 0, context: singaporeContext())
    }

    func testOneYearRelativeDateUsesInjectedCalendar() throws {
        let preview = try parse("Renew passport in 1 year")

        assertDate(preview.dueDate, year: 2027, month: 8, day: 24, hour: 0, minute: 0, context: singaporeContext())
    }

    func testNumericDateUsesEnSingaporeDayFirstOrder() throws {
        let context = singaporeContext(locale: "en_SG")
        let preview = try parse("Pay rent 03/09/2026", context: context)

        assertDate(preview.dueDate, year: 2026, month: 9, day: 3, hour: 0, minute: 0, context: context)
    }

    func testNumericDateUsesEnUSMonthFirstOrder() throws {
        let context = singaporeContext(locale: "en_US")
        let preview = try parse("Pay rent 03/09/2026", context: context)

        assertDate(preview.dueDate, year: 2026, month: 3, day: 9, hour: 0, minute: 0, context: context)
    }

    func testYearlessNumericDateUsesEnSingaporeDayFirstOrderInCurrentYear() throws {
        let context = singaporeContext(locale: "en_SG")
        let preview = try parse("Pay rent 03/09", context: context)

        assertDate(preview.dueDate, year: 2026, month: 9, day: 3, hour: 0, minute: 0, context: context)
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testYearlessNumericDateUsesEnUSMonthFirstOrderAndWarnsWhenPast() throws {
        let context = singaporeContext(locale: "en_US")
        let preview = try parse("Pay rent 03/09", context: context)

        assertDate(preview.dueDate, year: 2026, month: 3, day: 9, hour: 0, minute: 0, context: context)
        XCTAssertEqual(preview.warnings, [.scheduledTimeIsPast])
    }

    func testSeparatedSlashDateAndClockParseUsingInjectedLocale() throws {
        let singapore = singaporeContext(locale: "en_SG")
        let unitedStates = singaporeContext(locale: "en_US")
        let dayFirst = try parse("Call 9/3 3pm", context: singapore)
        let monthFirst = try parse("Call 9/3 at 3:30pm", context: unitedStates)

        XCTAssertEqual(dayFirst.kind, .event)
        XCTAssertEqual(dayFirst.title, "Call")
        assertDate(dayFirst.startDate, year: 2026, month: 3, day: 9, hour: 15, minute: 0, context: singapore)
        XCTAssertEqual(monthFirst.kind, .event)
        XCTAssertEqual(monthFirst.title, "Call")
        assertDate(monthFirst.startDate, year: 2026, month: 9, day: 3, hour: 15, minute: 30, context: unitedStates)
    }

    func testPlainYearlessSlashDateRemainsADateOnlyTask() throws {
        let context = singaporeContext(locale: "en_SG")
        let preview = try parse("Version 9/3", context: context)

        XCTAssertEqual(preview.kind, .task)
        XCTAssertEqual(preview.title, "Version")
        assertDate(preview.dueDate, year: 2026, month: 3, day: 9, hour: 0, minute: 0, context: context)
        XCTAssertFalse(preview.dueHasTime)
    }

    func testCallWithPlainYearlessSlashDateRemainsADateOnlyTask() throws {
        let context = singaporeContext(locale: "en_SG")
        let preview = try parse("Call 9/3", context: context)

        XCTAssertEqual(preview.kind, .task)
        XCTAssertEqual(preview.title, "Call")
        assertDate(preview.dueDate, year: 2026, month: 3, day: 9, hour: 0, minute: 0, context: context)
        XCTAssertFalse(preview.dueHasTime)
    }

    func testPlainSlashDatePreservesFollowingTitleColonPunctuation() throws {
        let context = singaporeContext(locale: "en_SG")
        let spaced = try parse("Call 9/3: discuss", context: context)
        let attached = try parse("Call 9/3:notes", context: context)

        XCTAssertEqual(spaced.kind, .task)
        XCTAssertEqual(spaced.title, "Call: discuss")
        assertDate(spaced.dueDate, year: 2026, month: 3, day: 9, hour: 0, minute: 0, context: context)
        XCTAssertEqual(attached.kind, .task)
        XCTAssertEqual(attached.title, "Call:notes")
        assertDate(attached.dueDate, year: 2026, month: 3, day: 9, hour: 0, minute: 0, context: context)
    }

    func testSeparatedSlashDateAndClockRangesRemainValidEvents() throws {
        let context = singaporeContext(locale: "en_SG")
        for (text, hour, minute) in [
            ("Call 9/3 3:30pm", 15, 30),
            ("Call 9/3 at 3:30pm", 15, 30),
            ("Call 9/3 15:00", 15, 0)
        ] {
            let preview = try parse(text, context: context)
            XCTAssertEqual(preview.kind, .event, text)
            XCTAssertEqual(preview.title, "Call", text)
            assertDate(preview.startDate, year: 2026, month: 3, day: 9, hour: hour, minute: minute, context: context)
        }
    }

    func testSeparatedSlashDateAndClockPreserveFollowingTitleColonPunctuation() throws {
        let context = singaporeContext(locale: "en_SG")
        let preview = try parse("Call 9/3 3pm: discuss", context: context)

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.title, "Call: discuss")
        assertDate(preview.startDate, year: 2026, month: 3, day: 9, hour: 15, minute: 0, context: context)
    }

    func testFullySeparatedThreePartLocaleDateAndClockRemainAValidEvent() throws {
        let context = singaporeContext(locale: "en_SG")
        let preview = try parse("Call 03/09/2026 at 3:30pm", context: context)

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.title, "Call")
        assertDate(preview.startDate, year: 2026, month: 9, day: 3, hour: 15, minute: 30, context: context)
    }

    func testNumericDateUsesLocalizedShortDateOrderForNonUSMonthFirstLocale() throws {
        let locale = Locale(identifier: "en_PH")
        let pattern = try XCTUnwrap(DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale))
        let monthPosition = try XCTUnwrap(pattern.firstIndex(of: "M"))
        let dayPosition = try XCTUnwrap(pattern.firstIndex(of: "d"))
        XCTAssertLessThan(monthPosition, dayPosition, "The fixed regression locale must remain month-first")
        let context = singaporeContext(locale: locale.identifier)
        let preview = try parse("Pay rent 03/09/2026", context: context)

        assertDate(preview.dueDate, year: 2026, month: 3, day: 9, hour: 0, minute: 0, context: context)
    }

    func testNumericDatesRequireUnicodeAlphanumericTokenBoundaries() throws {
        for text in ["Review café03/09/2026", "Review 03/09/2026年"] {
            let preview = try parse(text)
            XCTAssertEqual(preview.kind, .task, text)
            XCTAssertEqual(preview.title, text, text)
            XCTAssertNil(preview.dueDate, text)
        }
    }

    func testConfiguredTimeZoneControlsClockConstruction() throws {
        let utc = context(timeZoneIdentifier: "UTC", hour: 10, minute: 0)
        let singapore = context(timeZoneIdentifier: "Asia/Singapore", hour: 10, minute: 0)
        let utcPreview = try parse("Call at 3pm", context: utc)
        let singaporePreview = try parse("Call at 3pm", context: singapore)

        assertDate(utcPreview.startDate, year: 2026, month: 8, day: 24, hour: 15, minute: 0, context: utc)
        assertDate(singaporePreview.startDate, year: 2026, month: 8, day: 24, hour: 15, minute: 0, context: singapore)
        XCTAssertEqual(utcPreview.startDate!.timeIntervalSince(singaporePreview.startDate!), 28_800)
    }

    func testNonexistentLosAngelesDSTGapThrows() {
        let context = self.context(timeZoneIdentifier: "America/Los_Angeles", year: 2026, month: 3, day: 8, hour: 0, minute: 0)

        assertError(.nonexistentLocalTime, for: "Meet today at 2:30am", context: context)
    }

    func testLosAngelesDSTFallBackChoosesFirstOccurrence() throws {
        let context = self.context(timeZoneIdentifier: "America/Los_Angeles", year: 2026, month: 11, day: 1, hour: 0, minute: 0)
        let preview = try parse("Meet today at 1:30am", context: context)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        XCTAssertEqual(utc.component(.hour, from: preview.startDate!), 8)
        XCTAssertEqual(utc.component(.minute, from: preview.startDate!), 30)
    }

    func testExplicitElapsedTodayIsHonoredAndWarnedAbout() throws {
        let context = singaporeContext(hour: 10, minute: 0)
        let preview = try parse("Call today at 9am", context: context)

        assertDate(preview.startDate, year: 2026, month: 8, day: 24, hour: 9, minute: 0, context: context)
        XCTAssertEqual(preview.warnings, [.scheduledTimeIsPast])
    }

    func testExplicitPastRoutineReminderIsHonoredAndWarnedAbout() throws {
        let context = singaporeContext(hour: 10, minute: 0)
        let preview = try parse("Read every night today at 9am", context: context)

        XCTAssertEqual(preview.kind, .routine)
        assertDate(preview.reminderDate, year: 2026, month: 8, day: 24, hour: 9, minute: 0, context: context)
        XCTAssertEqual(preview.warnings, [.scheduledTimeIsPast])
    }

    func testExplicitPastNumericDateIsHonoredAndWarnedAbout() throws {
        let context = singaporeContext(hour: 10, minute: 0)
        let preview = try parse("Submit report 01/08/2026", context: context)

        XCTAssertEqual(preview.kind, .task)
        assertDate(preview.dueDate, year: 2026, month: 8, day: 1, hour: 0, minute: 0, context: context)
        XCTAssertEqual(preview.warnings, [.scheduledTimeIsPast])
    }

    func testSameDayDateOnlyTaskDoesNotWarnBeforeTheDayEnds() throws {
        let preview = try parse("Submit report today")

        XCTAssertEqual(preview.kind, .task)
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testRecurrenceOnlyRoutineDoesNotWarnWithoutAReminder() throws {
        let preview = try parse("Review every Monday")

        XCTAssertEqual(preview.kind, .routine)
        XCTAssertNil(preview.reminderDate)
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testSyntaxFreePunctuationTitlesRemainExactWhileSyntaxCleanupStaysPolished() throws {
        XCTAssertEqual(try parse("Call  Mom,!").title, "Call Mom,!")
        XCTAssertEqual(try parse("Agenda:").title, "Agenda:")
        XCTAssertEqual(try parse("Call Alex on Friday, at 3pm!").title, "Call Alex!")
    }

    func testSyntaxCleanupPreservesMeaningfulImportantPunctuation() throws {
        XCTAssertEqual(try parse("Discuss CSS, !important Friday at 3pm").title, "Discuss CSS, !important")
        XCTAssertEqual(try parse("Call Alex on Friday, at 3pm!").title, "Call Alex!")
    }

    // MARK: - Recurrence and preview invariants

    func testDailyRoutineUsesEmptyRuleWeekdaysAndAllRoutineWeekdays() throws {
        let preview = try parse("Stretch every day")

        XCTAssertEqual(preview.kind, .routine)
        XCTAssertEqual(preview.recurrence?.frequency, .daily)
        XCTAssertEqual(preview.recurrence?.weekdays, [])
        XCTAssertEqual(preview.weekdays, Set(1 ... 7))
    }

    func testWeekdaysRoutineUsesMondayThroughFriday() throws {
        let preview = try parse("Plan weekdays")

        XCTAssertEqual(preview.kind, .routine)
        XCTAssertEqual(preview.recurrence?.frequency, .weekly)
        XCTAssertEqual(preview.recurrence?.weekdays, Set(2 ... 6))
        XCTAssertEqual(preview.weekdays, Set(2 ... 6))
    }

    func testWeeklyEventRetainsRuleAndFiniteStart() throws {
        let preview = try parse("Team sync every Monday at 10am")

        XCTAssertEqual(preview.kind, .event)
        XCTAssertEqual(preview.recurrence?.frequency, .weekly)
        XCTAssertEqual(preview.recurrence?.weekdays, [2])
        XCTAssertNotNil(preview.startDate)
        XCTAssertEqual(preview.endDate?.timeIntervalSince(preview.startDate!), 3_600)
    }

    func testEventPreviewHasNoTaskOrRoutineFields() throws {
        let preview = try parse("Call Friday at 3pm")

        XCTAssertNotNil(preview.startDate)
        XCTAssertNotNil(preview.endDate)
        XCTAssertNil(preview.dueDate)
        XCTAssertNil(preview.routineWindow)
        XCTAssertTrue(preview.weekdays.isEmpty)
    }

    func testTaskAndRoutinePreviewsHaveMutuallyExclusiveScheduleFields() throws {
        let task = try parse("Submit report tomorrow")
        let routine = try parse("Read every night")

        XCTAssertNil(task.startDate)
        XCTAssertNil(task.endDate)
        XCTAssertNil(task.routineWindow)
        XCTAssertNil(routine.startDate)
        XCTAssertNil(routine.endDate)
        XCTAssertNil(routine.dueDate)
    }

    func testParserLeavesDestinationAndCategoryUnset() throws {
        let preview = try parse("Dentist Friday at 3pm")

        XCTAssertNil(preview.destinationID)
        XCTAssertNil(preview.categoryID)
    }

    // MARK: - Helpers

    private func parse(_ text: String, context: QuickEntryParseContext? = nil) throws -> QuickEntryPreview {
        try RuleBasedQuickEntryParser().parse(text, context: context ?? singaporeContext())
    }

    private func singaporeContext(
        hour: Int = 10,
        minute: Int = 0,
        second: Int = 0,
        locale: String = "en_SG"
    ) -> QuickEntryParseContext {
        context(timeZoneIdentifier: "Asia/Singapore", hour: hour, minute: minute, second: second, locale: locale)
    }

    private func context(
        timeZoneIdentifier: String,
        year: Int = 2026,
        month: Int = 8,
        day: Int = 24,
        hour: Int,
        minute: Int,
        second: Int = 0,
        locale: String = "en_SG"
    ) -> QuickEntryParseContext {
        let timeZone = TimeZone(identifier: timeZoneIdentifier)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        calendar.timeZone = timeZone
        let now = calendar.date(from: DateComponents(timeZone: timeZone, year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
        return QuickEntryParseContext(now: now, calendar: calendar, locale: Locale(identifier: locale), timeZone: timeZone)
    }

    private func assertTime(_ date: Date?, hour: Int, minute: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(date, file: file, line: line)
        guard let date else { return }
        let calendar = singaporeContext().calendar
        XCTAssertEqual(calendar.component(.hour, from: date), hour, file: file, line: line)
        XCTAssertEqual(calendar.component(.minute, from: date), minute, file: file, line: line)
    }

    private func assertDate(
        _ date: Date?,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        context: QuickEntryParseContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(date, file: file, line: line)
        guard let date else { return }
        let components = context.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(components.year, year, file: file, line: line)
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
        XCTAssertEqual(components.hour, hour, file: file, line: line)
        XCTAssertEqual(components.minute, minute, file: file, line: line)
    }

    private func assertError(
        _ expected: QuickEntryParseError,
        for text: String,
        context: QuickEntryParseContext? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try parse(text, context: context), file: file, line: line) { error in
            XCTAssertEqual(error as? QuickEntryParseError, expected, file: file, line: line)
        }
    }

    private func assertSendable<Value: Sendable>(_ value: Value) {}

    private func assertSendableType<Value: Sendable>(_ type: Value.Type) {}
    private func assertHashableType<Value: Hashable>(_ type: Value.Type) {}
}
