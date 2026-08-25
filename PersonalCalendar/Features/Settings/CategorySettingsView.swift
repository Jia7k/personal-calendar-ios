import Observation
import SwiftUI

@MainActor
@Observable
final class CategorySettingsModel {
    private(set) var categories: [CategorySnapshot] = []
    private(set) var errorMessage: String?
    private let repository: any CategoryRepository

    init(repository: any CategoryRepository) {
        self.repository = repository
    }

    func load() {
        perform { try repository.list() }
    }

    func create(name: String, colorHex: String) {
        perform {
            _ = try repository.create(name: name, colorHex: colorHex)
            return try repository.list()
        }
    }

    func update(id: UUID, name: String, colorHex: String) {
        perform {
            try repository.update(id: id, name: name, colorHex: colorHex)
            return try repository.list()
        }
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = categories
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        perform {
            try repository.reorder(ids: reordered.map(\.id))
            return try repository.list()
        }
    }

    func delete(id: UUID, reassignedTo replacementID: UUID?) {
        perform {
            try repository.delete(id: id, reassignedTo: replacementID)
            return try repository.list()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func perform(_ operation: () throws -> [CategorySnapshot]) {
        do {
            categories = try operation().sorted { $0.sortOrder < $1.sortOrder }
            errorMessage = nil
        } catch {
            errorMessage = "Categories could not be updated."
        }
    }
}

struct CategorySettingsView: View {
    @State private var model: CategorySettingsModel
    @State private var editor: CategoryEditorItem?
    @State private var pendingDelete: CategorySnapshot?
    private let onContentChanged: @MainActor () -> Void

    init(
        repository: any CategoryRepository,
        onContentChanged: @escaping @MainActor () -> Void = {}
    ) {
        _model = State(initialValue: CategorySettingsModel(repository: repository))
        self.onContentChanged = onContentChanged
    }

    var body: some View {
        List {
            if model.categories.isEmpty {
                ContentUnavailableView(
                    "No Categories",
                    systemImage: "tag",
                    description: Text("Add a category to organize events, tasks, and routines.")
                )
            } else {
                ForEach(model.categories) { category in
                    categoryRow(category)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                pendingDelete = category
                            }
                            Button("Edit") {
                                editor = .init(category: category)
                            }
                            .tint(CalendarTheme.accent)
                        }
                }
                .onMove { source, destination in
                    model.move(fromOffsets: source, toOffset: destination)
                    onContentChanged()
                }
            }
        }
        .navigationTitle("Categories")
        .task { model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editor = .init(category: nil)
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .frame(minWidth: CalendarTheme.minimumTapSize, minHeight: CalendarTheme.minimumTapSize)
                .accessibilityIdentifier("category-add")
            }
        }
        .sheet(item: $editor) { item in
            CategoryEditorSheet(category: item.category) { name, colorHex in
                if let category = item.category {
                    model.update(id: category.id, name: name, colorHex: colorHex)
                } else {
                    model.create(name: name, colorHex: colorHex)
                }
                onContentChanged()
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "category")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let category = pendingDelete {
                Button("Remove Category", role: .destructive) {
                    delete(category, replacementID: nil)
                }
                ForEach(model.categories.filter { $0.id != category.id }) { replacement in
                    Button("Move Items to \(replacement.name)", role: .destructive) {
                        delete(category, replacementID: replacement.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Choose where items using this category should go.")
        }
        .alert(
            "Couldn’t Update Categories",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func categoryRow(_ category: CategorySnapshot) -> some View {
        Button {
            editor = .init(category: category)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(CalendarTheme.color(hex: category.colorHex) ?? Color.gray)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: CalendarTheme.minimumTapSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.name) category")
        .accessibilityHint("Opens category editing")
        .accessibilityIdentifier("category-row-\(category.id.uuidString)")
    }

    private func delete(_ category: CategorySnapshot, replacementID: UUID?) {
        model.delete(id: category.id, reassignedTo: replacementID)
        pendingDelete = nil
        onContentChanged()
    }
}

private struct CategoryEditorItem: Identifiable {
    let id = UUID()
    let category: CategorySnapshot?
}

private struct CategoryEditorSheet: View {
    private static let colors = ["#CB6B4F", "#3A8D7C", "#4868A8", "#8A63B8"]

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    let onSave: (String, String) -> Void

    init(category: CategorySnapshot?, onSave: @escaping (String, String) -> Void) {
        _name = State(initialValue: category?.name ?? "")
        _colorHex = State(initialValue: category?.colorHex ?? Self.colors[0])
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("category-name")

                Picker("Color", selection: $colorHex) {
                    ForEach(Self.colors, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(CalendarTheme.color(hex: color) ?? Color.gray)
                                .frame(width: 16, height: 16)
                            Text(color)
                        }
                        .tag(color)
                    }
                }
                .accessibilityIdentifier("category-color")
            }
            .navigationTitle(name.isEmpty ? "New Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, colorHex)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("category-save")
                }
            }
        }
    }
}
