import SwiftUI

struct PermissionCard: View {
    let title: String
    let explanation: String
    let actionTitle: String?
    let action: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(explanation).font(.subheadline).foregroundStyle(.secondary)
            if let actionTitle, let action { Button(actionTitle, action: action).frame(minHeight: CalendarTheme.minimumTapSize) }
        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: CalendarTheme.cornerRadius))
    }
}
