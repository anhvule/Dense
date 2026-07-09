// App/AdvancedPanelView.swift
import SwiftUI
import AppKit
import CompressCore

struct AdvancedPanelView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var confirmTrash = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                label("Format")
                Picker("", selection: $env.containerRaw) {
                    Text("MP4 · H.264").tag("mp4")
                    Text("MP4 · HEVC").tag("mp4-hevc")
                    Text("MOV").tag("mov")
                }.labelsHidden().frame(width: 150)
                label("Resolution")
                Picker("", selection: $env.resolutionCapRaw) {
                    Text("Preset default").tag("")
                    ForEach(ResolutionCap.allCases) { Text($0.displayName).tag($0.rawValue) }
                }.labelsHidden().frame(width: 150)
            }
            GridRow {
                label("Target size")
                HStack(spacing: 4) {
                    TextField("auto", text: $env.customTargetMBText).frame(width: 64)
                    Text("MB").font(.caption).foregroundStyle(.secondary)
                }
                label("Audio")
                Toggle("Remove audio", isOn: $env.removeAudio).toggleStyle(.checkbox)
            }
            GridRow {
                label("Output")
                Picker("", selection: $env.outputToCustomFolder) {
                    Text("Next to original").tag(false)
                    Text("Custom folder").tag(true)
                }.labelsHidden().frame(width: 150)
                label("Suffix")
                TextField("-compressed", text: $env.outputSuffix).frame(width: 150)
            }
            if env.outputToCustomFolder {
                GridRow {
                    label("Folder")
                    HStack {
                        Text(env.customOutputPath.isEmpty ? "None chosen" : env.customOutputPath)
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                        Button("Change…") { pickFolder() }
                    }.gridCellColumns(3)
                }
            }
            GridRow {
                label("Originals")
                Toggle("Move to Trash after success", isOn: Binding(
                    get: { env.trashOriginals },
                    set: { on in if on { confirmTrash = true } else { env.trashOriginals = false } }))
                    .toggleStyle(.checkbox).gridCellColumns(3)
            }
            GridRow {
                label("GIF mode")
                Toggle("Convert to GIF", isOn: $env.gifMode).toggleStyle(.checkbox)
                Stepper("fps \(env.gifFps)", value: $env.gifFps, in: 5...30)
                Stepper("width \(env.gifWidth)", value: $env.gifWidth, in: 240...960, step: 80)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal, 14)
        .alert("Move originals to Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash") { env.trashOriginals = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("After a successful compression the original moves to the Trash. You can put it back anytime.")
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { env.customOutputPath = url.path }
    }
}
