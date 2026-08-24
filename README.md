# Personal Calendar

Requires iOS 17+ and XcodeGen. Generate the project with `xcodegen generate`.

Build with `xcodegen generate && xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`.

Run tests with `xcodegen generate && xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

Use the [foundation accessibility manual-QA checklist](docs/manual-qa/foundation-accessibility.md) for Dark Mode, Reduce Motion, VoiceOver, and Accessibility XXXL checks that automation cannot prove visually.

The app stores events in Apple Calendar, tasks in Apple Reminders, and routines locally with SwiftData. It is local-only: no backend, account, analytics, or CloudKit entitlement.
