import SwiftUI

struct ProfileSelectorToolbar: View {
    let selection: ProfileSelectionController
    var showsName = true

    var body: some View {
        Menu {
            profileButton(
                identity: .everything,
                name: "Everything",
                symbolName: "rectangle.stack.fill",
                accessibilityIdentifier: "profile-option-everything"
            )

            ForEach(selection.profiles) { profile in
                profileButton(
                    identity: .saved(profile.id),
                    name: profile.name,
                    symbolName: profile.symbolName,
                    accessibilityIdentifier: "profile-option-\(profile.id.uuidString)"
                )
            }
        } label: {
            if showsName {
                Label(currentName, systemImage: currentSymbolName)
                    .lineLimit(1)
            } else {
                Image(systemName: currentSymbolName)
            }
        }
        .frame(
            minWidth: CalendarTheme.minimumTapSize,
            minHeight: CalendarTheme.minimumTapSize
        )
        .accessibilityLabel("Profile")
        .accessibilityValue(currentName)
        .accessibilityIdentifier("profile-selector")
    }

    private var currentProfile: ProfileSnapshot? {
        guard case let .saved(id) = selection.activeIdentity else { return nil }
        return selection.profiles.first { $0.id == id }
    }

    private var currentName: String {
        switch selection.activeIdentity {
        case .everything:
            "Everything"
        case .saved:
            currentProfile?.name ?? "Profile"
        }
    }

    private var currentSymbolName: String {
        switch selection.activeIdentity {
        case .everything:
            "rectangle.stack.fill"
        case .saved:
            currentProfile?.symbolName ?? "questionmark.circle"
        }
    }

    private func profileButton(
        identity: ProfileIdentity,
        name: String,
        symbolName: String,
        accessibilityIdentifier: String
    ) -> some View {
        Button {
            try? selection.select(identity)
        } label: {
            Label(name, systemImage: symbolName)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
