import SwiftUI

struct CalendarSearchView: View {
    @State private var model: CalendarSearchViewModel
    private let environment: AppEnvironment
    private let onSelect: @MainActor (AgendaItemOrigin) -> Void
    private let calendar: Calendar

    init(
        environment: AppEnvironment,
        onSelect: @escaping @MainActor (AgendaItemOrigin) -> Void
    ) {
        self.environment = environment
        self.onSelect = onSelect
        let calendar = Calendar.current
        self.calendar = calendar
        let selection = environment.profileSelection
        let scopes = environment.profileScopes
        _model = State(initialValue: CalendarSearchViewModel(
            calendarService: environment.calendar,
            remindersService: environment.reminders,
            routines: environment.routines,
            categories: environment.categories,
            currentScope: { try scopes.resolve(selection.activeIdentity) },
            calendar: calendar,
            locale: .current,
            now: { .now }
        ))
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            searchField(text: $model.query)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            if model.isLoading, allResults.isEmpty {
                ProgressView("Searching your profile")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Search your profile",
                    systemImage: "magnifyingglass",
                    description: Text("Try a course code, room, title, or date.")
                )
            } else if model.isProfileEmpty {
                ContentUnavailableView(
                    "This profile is empty",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text("Add a calendar, reminder list, or routine in Profiles.")
                )
            } else if allResults.isEmpty, model.notices.isEmpty {
                ContentUnavailableView(
                    "No matches in this profile",
                    systemImage: "magnifyingglass",
                    description: Text(searchRangeDescription)
                )
            } else {
                resultsList
            }
        }
        .background(CalendarTheme.background)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileSelectorToolbar(selection: environment.profileSelection)
            }
        }
        .task(id: environment.profileSelection.scopeRevision) {
            await model.load()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-search-screen")
    }

    private func searchField(text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Events, tasks, routines", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search events, tasks, and routines")
                .accessibilityIdentifier("calendar-search-field")
            if !text.wrappedValue.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    text.wrappedValue = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("calendar-search-clear")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: CalendarTheme.minimumTapSize)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var resultsList: some View {
        List {
            if !model.notices.isEmpty {
                Section("Some sources need attention") {
                    ForEach(model.notices) { notice in
                        Label(notice.message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Retry") { Task { await model.retry() } }
                        .accessibilityIdentifier("calendar-search-retry")
                }
            }

            resultSection("Upcoming", results: model.sections.upcoming)
            resultSection("Past & completed", results: model.sections.pastAndCompleted)
            resultSection("Routines", results: model.sections.routines)

            if allResults.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No matches in available sources",
                        systemImage: "magnifyingglass",
                        description: Text(searchRangeDescription)
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func resultSection(_ title: String, results: [CalendarSearchResult]) -> some View {
        if !results.isEmpty {
            Section(title) {
                ForEach(results) { result in
                    Button {
                        onSelect(result.origin)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: result.source.symbolName)
                                .foregroundStyle(result.source.tint)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(result.source.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(result.source.tint)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: CalendarTheme.minimumTapSize)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: result))
                    .accessibilityIdentifier("calendar-search-result-\(result.id)")
                }
            }
        }
    }

    private var allResults: [CalendarSearchResult] {
        model.sections.upcoming + model.sections.pastAndCompleted + model.sections.routines
    }

    private var searchRangeDescription: String {
        let now = Date.now
        let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let end = calendar.date(byAdding: .year, value: 2, to: now) ?? now
        let startText = start.formatted(.dateTime.month(.abbreviated).year())
        let endText = end.formatted(.dateTime.month(.abbreviated).year())
        return "No matching items were found. Events are searched from \(startText) through \(endText)."
    }

    private func accessibilityLabel(for result: CalendarSearchResult) -> String {
        [result.title, result.source.displayName, result.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private extension CalendarSearchSource {
    var displayName: String {
        switch self {
        case .event: "Event"
        case .task: "Task"
        case .routine: "Routine"
        }
    }

    var symbolName: String {
        switch self {
        case .event: "calendar"
        case .task: "checkmark.circle"
        case .routine: "repeat"
        }
    }

    var tint: Color {
        switch self {
        case .event: CalendarTheme.accent
        case .task: .orange
        case .routine: .purple
        }
    }
}
