import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    let backup: BackupService
    let onRestored: @MainActor () -> Void
    @State private var exportData: Data?
    @State private var isImporting = false
    @State private var pendingImport: Data?
    @State private var pendingSummary: BackupSummary?
    @State private var resultMessage: String?

    var body: some View {
        List {
            Section("Export") {
                Button("Prepare backup") { prepareExport() }
                if let exportData {
                    ShareLink(item: exportData, preview: SharePreview("Personal Calendar Backup")) {
                        Label("Share backup", systemImage: "square.and.arrow.up")
                    }
                }
            }
            Section("Restore") {
                Button("Import backup") { isImporting = true }
                Text("Importing replaces your existing profiles, routines, completions, categories, and category links. Calendar events and reminders are never included.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let resultMessage {
                Section { Text(resultMessage) }
            }
        }
        .navigationTitle("Backup & Restore")
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .alert("Replace local data?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil; pendingSummary = nil } })) {
            Button("Cancel", role: .cancel) { pendingImport = nil; pendingSummary = nil }
            Button("Replace", role: .destructive) { restorePendingImport() }
        } message: {
            if let pendingSummary {
                Text("This backup contains \(pendingSummary.profiles) profiles, \(pendingSummary.routines) routines, \(pendingSummary.completions) completions, \(pendingSummary.categories) categories, and \(pendingSummary.categoryLinks) category links. Existing local data will be replaced.")
            }
        }
    }

    private func prepareExport() {
        do {
            exportData = try backup.exportData()
            resultMessage = "Backup is ready to share."
        } catch {
            resultMessage = "Could not create a backup."
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { throw BackupError.invalidData("The selected file could not be accessed.") }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            pendingSummary = try backup.summary(data: data)
            pendingImport = data
            resultMessage = nil
        } catch {
            resultMessage = "Could not read that backup file."
        }
    }

    private func restorePendingImport() {
        guard let pendingImport else { return }
        do {
            try backup.restore(data: pendingImport)
            self.pendingImport = nil
            pendingSummary = nil
            resultMessage = "Backup restored."
            onRestored()
        } catch {
            self.pendingImport = nil
            pendingSummary = nil
            resultMessage = "Could not restore that backup."
        }
    }
}
