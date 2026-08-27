import XCTest
@testable import PersonalCalendar

private enum TodayTaskActionPresentationTestError: Error {
    case unavailable
}

@MainActor
final class TodayTaskActionPresentationTests: XCTestCase {
    func testEditorActiveAttemptIsBusyEvenWhenTheActionIsUnavailable() {
        let decision = TodayTaskActionPresentationGate.decide(
            editorIsPresented: true,
            actionIsPresented: false,
            actionIsAvailable: false
        )

        XCTAssertEqual(decision, .busy)
    }

    func testActionSheetActiveAttemptIsBusyEvenWhenTheActionIsUnavailable() {
        let decision = TodayTaskActionPresentationGate.decide(
            editorIsPresented: false,
            actionIsPresented: true,
            actionIsAvailable: false
        )

        XCTAssertEqual(decision, .busy)
    }

    func testIdleUnavailableAttemptIsClassifiedUnavailable() {
        let decision = TodayTaskActionPresentationGate.decide(
            editorIsPresented: false,
            actionIsPresented: false,
            actionIsAvailable: false
        )

        XCTAssertEqual(decision, .unavailable)
    }

    func testPickDateRetainsReminderIDAndUsesAStablePresentationID() {
        let request = TodayTaskPickDate(reminderID: "task-42")
        let presentation = TodayTaskActionPresentation.pickDate(request)

        XCTAssertEqual(presentation.id, presentation.id)
        guard case let .pickDate(selectedRequest) = presentation else {
            return XCTFail("Expected Pick Date presentation")
        }
        XCTAssertEqual(selectedRequest.reminderID, "task-42")
    }

    func testPickDateAndTimeBlockHaveDistinctStablePresentationIDs() {
        let pickDate = TodayTaskActionPresentation.pickDate(
            TodayTaskPickDate(reminderID: "task-42")
        )
        let timeBlock = TodayTaskActionPresentation.timeBlock(makeTimeBlockSession())

        XCTAssertEqual(pickDate.id, pickDate.id)
        XCTAssertEqual(timeBlock.id, timeBlock.id)
        XCTAssertNotEqual(pickDate.id, timeBlock.id)
    }

    func testReplacingOneDirectActionPresentationLeavesOnlyTheReplacement() {
        var presentation: TodayTaskActionPresentation? = .pickDate(
            TodayTaskPickDate(reminderID: "task-42")
        )

        let replacement = makeTimeBlockSession()
        presentation = .timeBlock(replacement)

        guard case let .timeBlock(selectedSession) = presentation else {
            return XCTFail("Expected Time Block presentation")
        }
        XCTAssertEqual(selectedSession.id, replacement.id)
    }

    private func makeTimeBlockSession() -> TaskTimeBlockSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let task = ReminderSnapshot(
            id: "task-42",
            title: "Submit assignment",
            notes: nil,
            dueDate: nil,
            dueHasTime: false,
            priority: 0,
            listID: "tasks",
            listTitle: "Tasks",
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
        return TaskTimeBlockSession(
            model: TaskTimeBlockViewModel(
                task: task,
                creationProfile: nil,
                calendarService: FakeCalendarService(access: .granted),
                resolveScope: { _ in
                    throw TodayTaskActionPresentationTestError.unavailable
                },
                planner: TaskTimeBlockPlanner(calendar: calendar),
                calendar: calendar,
                now: { Date(timeIntervalSince1970: 0) }
            ),
            profiles: [],
            resolveProfile: { _ in
                throw TodayTaskActionPresentationTestError.unavailable
            },
            onSaved: {}
        )
    }
}
