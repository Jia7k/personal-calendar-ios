import XCTest
@testable import PersonalCalendar

final class WeekEventDisplayTitleTests: XCTestCase {
    func testRecognizedLaboratoryTitleKeepsCourseCodeSectionAndCompactKind() {
        XCTAssertEqual(
            WeekEventDisplayTitle.compact(
                "INF 2001 - Introduction to Software Engineering (P7 Laboratory)"
            ),
            "INF 2001\nP7 Lab"
        )
    }

    func testOneHourClassBlockStacksCourseCodeAndKindWithoutSectionOrTime() {
        let subject = WeekEventBlockPresentation.resolve(
            title: "INF 2001 - Introduction to Software Engineering (P7 Laboratory)",
            height: WeekPlannerTimelineMetrics.pointsPerHour,
            itemCount: 1
        )

        XCTAssertEqual(subject.displayTitle, "INF\n2001\nLab")
        XCTAssertEqual(subject.titleLineLimit, 3)
        XCTAssertFalse(subject.showsTime)
        XCTAssertTrue(subject.usesCompactClassStyle)
    }

    func testOneHourGenericEventKeepsExistingSingleLinePresentation() {
        let subject = WeekEventBlockPresentation.resolve(
            title: "Driving",
            height: WeekPlannerTimelineMetrics.pointsPerHour,
            itemCount: 1
        )

        XCTAssertEqual(subject.displayTitle, "Driving")
        XCTAssertEqual(subject.titleLineLimit, 1)
        XCTAssertFalse(subject.showsTime)
        XCTAssertFalse(subject.usesCompactClassStyle)
    }

    func testTallClassAtNarrowPhoneWidthRetainsCourseCodeAndCompactKind() {
        let subject = WeekEventBlockPresentation.resolve(
            title: "BAC 2005 - Fintech Investment and Risk Management (S2 Seminar)",
            height: WeekPlannerTimelineMetrics.pointsPerHour * 2,
            itemCount: 1,
            availableTextWidth: 36
        )

        XCTAssertEqual(subject.displayTitle, "BAC\n2005\nSem")
        XCTAssertEqual(subject.titleLineLimit, 3)
        XCTAssertTrue(subject.showsTime)
        XCTAssertTrue(subject.usesCompactClassStyle)
    }

    func testTallClassAtWideWidthRetainsFullCompactTitleAndSection() {
        let subject = WeekEventBlockPresentation.resolve(
            title: "BAC 2005 - Fintech Investment and Risk Management (S2 Seminar)",
            height: WeekPlannerTimelineMetrics.pointsPerHour * 2,
            itemCount: 1,
            availableTextWidth: 120
        )

        XCTAssertEqual(subject.displayTitle, "BAC 2005\nS2 Seminar")
        XCTAssertEqual(subject.titleLineLimit, 2)
        XCTAssertTrue(subject.showsTime)
        XCTAssertTrue(subject.usesCompactClassStyle)
    }

    func testTallGenericEventAtNarrowWidthKeepsExistingPresentation() {
        let subject = WeekEventBlockPresentation.resolve(
            title: "Driving",
            height: WeekPlannerTimelineMetrics.pointsPerHour * 2,
            itemCount: 1,
            availableTextWidth: 36
        )

        XCTAssertEqual(subject.displayTitle, "Driving")
        XCTAssertEqual(subject.titleLineLimit, 2)
        XCTAssertTrue(subject.showsTime)
        XCTAssertFalse(subject.usesCompactClassStyle)
    }

    func testNarrowClassKindsUseRecognizableAliasesThatFitPhoneColumns() {
        let cases = [
            (
                "INF 2003 - Database Systems (L1 Lecture)",
                "INF\n2003\nLec"
            ),
            (
                "MAT 1001 - Discrete Mathematics (T12 Tutorial)",
                "MAT\n1001\nTut"
            ),
            (
                "BAC 2005 - Fintech Investment and Risk Management (S2 Seminar)",
                "BAC\n2005\nSem"
            )
        ]

        for (title, expected) in cases {
            let subject = WeekEventBlockPresentation.resolve(
                title: title,
                height: WeekPlannerTimelineMetrics.pointsPerHour * 2,
                itemCount: 1,
                availableTextWidth: 36
            )
            XCTAssertEqual(subject.displayTitle, expected)
            XCTAssertEqual(subject.titleLineLimit, 3)
        }
    }

    func testRecognizedSeminarTitleDropsOnlyTheVerboseCourseName() {
        XCTAssertEqual(
            WeekEventDisplayTitle.compact(
                "BAC 2005 - Fintech Investment and Risk Management (S2 Seminar)"
            ),
            "BAC 2005\nS2 Seminar"
        )
    }

    func testRecognizedLectureAndTutorialTitlesPreserveTheirClassKinds() {
        XCTAssertEqual(
            WeekEventDisplayTitle.compact("INF 2003 - Database Systems (L1 Lecture)"),
            "INF 2003\nL1 Lecture"
        )
        XCTAssertEqual(
            WeekEventDisplayTitle.compact("MAT 1001 - Discrete Mathematics (T12 Tutorial)"),
            "MAT 1001\nT12 Tutorial"
        )
    }

    func testGenericAndAcademicLookingButUnrecognizedTitlesRemainVerbatim() {
        XCTAssertEqual(WeekEventDisplayTitle.compact("Driving"), "Driving")
        XCTAssertEqual(WeekEventDisplayTitle.compact("Meet INF 2001 project group"), "Meet INF 2001 project group")
        XCTAssertEqual(WeekEventDisplayTitle.compact("INF 2001 - Exam"), "INF 2001 - Exam")
        XCTAssertEqual(WeekEventDisplayTitle.compact("INF 2001 - Software Engineering (Final)"), "INF 2001 - Software Engineering (Final)")
    }

    func testAlreadyCompactAcademicTitleRemainsUnchanged() {
        XCTAssertEqual(WeekEventDisplayTitle.compact("INF 2003 Lecture"), "INF 2003 Lecture")
    }
}
