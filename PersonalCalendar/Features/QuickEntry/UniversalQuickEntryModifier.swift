import SwiftUI

/// Renders the root-owned universal creation affordance. Presentation state
/// deliberately remains with `RootTabView` so this modifier can never create a
/// second modal route.
struct UniversalQuickEntryModifier: ViewModifier {
    let onAdd: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.white)
                        .background(CalendarTheme.accent, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .accessibilityLabel("Add event, task, or routine")
                .accessibilityHint("Opens universal quick entry")
                .accessibilityIdentifier("universal-add")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}

extension View {
    func universalQuickEntry(onAdd: @escaping () -> Void) -> some View {
        modifier(UniversalQuickEntryModifier(onAdd: onAdd))
    }
}
