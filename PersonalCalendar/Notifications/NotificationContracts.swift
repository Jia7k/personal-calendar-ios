enum NotificationCategoryIdentifier {
    static let routineReminder = "routine-reminder"
    static let morningSummary = "morning-summary"
    static let classAlert = "class-alert"
}

enum NotificationActionIdentifier {
    static let routineComplete = "routine-complete"
    static let routineSnooze15 = "routine-snooze-15"
}

enum NotificationPayloadKey {
    static let route = "route"
    static let routineID = "routineID"
    static let localDay = "localDay"
}
