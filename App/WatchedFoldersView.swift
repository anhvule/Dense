// App/WatchedFoldersView.swift
import SwiftUI
import AppKit
import DenseCore

/// A separate glassCard below `AdvancedPanelView` rather than another row
/// inside its `Grid` — the list is dynamic (0..N rows, each with its own
/// picker/toggle/remove control), which doesn't fit the fixed two-column
/// `GridRow` layout the rest of that panel uses. Both panels share the same
/// `showAdvanced` toggle in `MainView`, so this still reads as one
/// "Advanced" disclosure to the user.
struct WatchedFoldersView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Watched folders", systemImage: "eye")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add folder…") { addFolder() }
                    .buttonStyle(.borderless)
            }
            if env.watchedFolders.isEmpty {
                Text("Files added to a watched folder auto-compress in the background using that folder's preset.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(env.watchedFolders) { folder in
                        row(for: folder)
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
        .tint(Theme.accent)
        .padding(.horizontal, 14)
    }

    private func row(for folder: WatchedFolder) -> some View {
        HStack(spacing: 8) {
            if !folderExists(folder.path) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This folder no longer exists — watching is paused for it.")
            }
            Text((folder.path as NSString).lastPathComponent)
                .font(.caption).lineLimit(1).truncationMode(.middle)
                .help(folder.path)
                .frame(minWidth: 100, alignment: .leading)
            Spacer()
            Picker("", selection: Binding(
                get: { folder.presetRaw },
                set: { env.setWatchedFolderPreset(id: folder.id, presetRaw: $0) })) {
                ForEach(Preset.allCases) { Text($0.displayName).tag($0.rawValue) }
            }.labelsHidden().frame(width: 170)
            Toggle("", isOn: Binding(
                get: { folder.enabled },
                set: { env.setWatchedFolderEnabled(id: folder.id, enabled: $0) }))
                .toggleStyle(.switch).labelsHidden()
            Button {
                env.removeWatchedFolder(id: folder.id)
            } label: {
                Image(systemName: "trash")
            }.buttonStyle(.borderless)
        }
    }

    private func folderExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            env.addWatchedFolder(path: url.path)
        }
    }
}
