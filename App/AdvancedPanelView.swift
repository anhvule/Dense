// App/AdvancedPanelView.swift
import SwiftUI
import AppKit
import DenseCore

struct AdvancedPanelView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var confirmTrash = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                label("Format", systemImage: "shippingbox")
                Picker("", selection: $env.containerRaw) {
                    Text("MP4 · H.264").tag("mp4")
                    Text("MP4 · HEVC").tag("mp4-hevc")
                    Text("MOV").tag("mov")
                    Text("WebM · VP9 (slow, software)").tag("webm-vp9")
                }.labelsHidden().frame(width: 180)
                label("Resolution", systemImage: "aspectratio")
                Picker("", selection: $env.resolutionCapRaw) {
                    Text("Preset default").tag("")
                    ForEach(ResolutionCap.allCases) { Text($0.displayName).tag($0.rawValue) }
                }.labelsHidden().frame(width: 150)
            }
            GridRow {
                label("Target size", systemImage: "scalemass")
                HStack(spacing: 4) {
                    TextField("auto", text: $env.customTargetMBText).frame(width: 64)
                    Text("MB").font(.caption).foregroundStyle(.secondary)
                }
                label("Audio", systemImage: "speaker.wave.2")
                Toggle("Remove audio", isOn: $env.removeAudio).toggleStyle(.checkbox)
            }
            GridRow {
                label("Output", systemImage: "folder")
                Picker("", selection: $env.outputToCustomFolder) {
                    Text("Next to original").tag(false)
                    Text("Custom folder").tag(true)
                }.labelsHidden().frame(width: 150)
                label("Suffix", systemImage: "textformat")
                // Routed through setOutputSuffix (not $env.outputSuffix)
                // so the folder watcher's own-output loop guard re-syncs
                // on every keystroke.
                TextField("-compressed", text: Binding(
                    get: { env.outputSuffix },
                    set: { env.setOutputSuffix($0) })).frame(width: 150)
            }
            if env.outputToCustomFolder {
                GridRow {
                    label("Folder", systemImage: "folder.badge.gearshape")
                    HStack {
                        Text(env.customOutputPath.isEmpty ? "None chosen" : env.customOutputPath)
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                        Button("Change…") { pickFolder() }
                    }.gridCellColumns(3)
                }
            }
            GridRow {
                label("FPS cap", systemImage: "timer")
                Picker("", selection: $env.fpsCapRaw) {
                    Text("Off").tag(0)
                    Text("24").tag(24)
                    Text("30").tag(30)
                    Text("60").tag(60)
                }.labelsHidden().frame(width: 150)
                label("CPU cores", systemImage: "cpu")
                Stepper(env.threadLimitRaw == 0 ? "Off" : "\(env.threadLimitRaw) core\(env.threadLimitRaw == 1 ? "" : "s")",
                        value: $env.threadLimitRaw, in: 0...ProcessInfo.processInfo.processorCount)
            }
            GridRow {
                label("Metadata", systemImage: "doc.text.magnifyingglass")
                Toggle("Strip metadata", isOn: $env.stripMetadata).toggleStyle(.checkbox)
                    .gridCellColumns(3)
            }
            GridRow {
                label("Originals", systemImage: "trash")
                Toggle("Move to Trash after success", isOn: Binding(
                    get: { env.trashOriginals },
                    set: { on in if on { confirmTrash = true } else { env.trashOriginals = false } }))
                    .toggleStyle(.checkbox).gridCellColumns(3)
            }
            GridRow {
                label("GIF mode", systemImage: "photo.stack")
                Toggle("Convert to GIF", isOn: $env.gifMode).toggleStyle(.checkbox)
                Stepper("fps \(env.gifFps)", value: $env.gifFps, in: 5...30)
                Stepper("width \(env.gifWidth)", value: $env.gifWidth, in: 240...960, step: 80)
            }
            GridRow {
                label("Image quality", systemImage: "photo")
                Picker("", selection: $env.imageQuality) {
                    Text("Good").tag(0.85)
                    Text("Balanced").tag(0.75)
                    Text("Small").tag(0.55)
                }.labelsHidden().frame(width: 150)
                label("PDF quality", systemImage: "doc.richtext")
                Picker("", selection: $env.pdfQualityRaw) {
                    ForEach(PDFQuality.allCases) { Text($0.displayName).tag($0.rawValue) }
                }.labelsHidden().frame(width: 150)
            }
            GridRow {
                label("Local API", systemImage: "network")
                Toggle("Enable", isOn: Binding(
                    get: { env.apiEnabled },
                    set: { env.setAPIEnabled($0) })).toggleStyle(.checkbox)
                if env.apiEnabled {
                    HStack(spacing: 4) {
                        Text("Port").font(.caption).foregroundStyle(.secondary)
                        TextField("4499", value: Binding(
                            get: { env.apiPort },
                            set: { env.setAPIPort($0) }), format: .number)
                            .frame(width: 60)
                    }
                }
            }
            if env.apiEnabled {
                GridRow {
                    Color.clear.frame(width: 84, height: 1)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(env.localAPIServer.token)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(env.localAPIServer.token, forType: .string)
                            }
                        }
                        Text("curl -s http://127.0.0.1:\(env.apiPort)/v1/jobs "
                             + "-H \"Authorization: Bearer \(env.localAPIServer.token)\"")
                            .font(.caption2).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Bound to 127.0.0.1 only, off unless enabled here. Loopback only — "
                             + "not reachable from other machines. The token also rotates every "
                             + "launch/restart and is written to ~/Library/Application Support/Dense/"
                             + "api-token (readable only by you) while the server is on, so scripts "
                             + "can read it without the UI.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .gridCellColumns(3)
                }
            }
        }
        .padding(14)
        .glassCard()
        .tint(Theme.accent)
        .padding(.horizontal, 14)
        .transition(.move(edge: .top).combined(with: .opacity))
        .alert("Move originals to Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash") { env.trashOriginals = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("After a successful compression the original moves to the Trash. You can put it back anytime.")
        }
    }

    private func label(_ s: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(s).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 84, alignment: .leading)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { env.setCustomOutputPath(url.path) }
    }
}
