// App/DropZonePanel.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Small always-on-top drop target that floats above every Space and every
/// other app, so files can be dropped on Dense without switching to (or even
/// having open) the main window. Toggled from the `MainView` header via
/// `AppEnvironment.dropZoneEnabled`; owned/retained by `AppEnvironment`.
///
/// Drops route through the exact same `AppEnvironment.handleDrop(urls:preset:)`
/// path as the main window's background drop target, with `preset: nil` so
/// they use whatever the current default preset is — identical semantics to
/// dropping onto the main window background (not onto a specific destination
/// dock preset).
final class DropZonePanel: NSPanel {
    private static let autosaveName = "DropZonePanel"
    static let defaultSize = NSSize(width: 160, height: 160)

    init(env: AppEnvironment) {
        let size = Self.defaultSize
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Default to the top-right corner the first time this ever runs;
        // `setFrameAutosaveName` below restores any previously-dragged
        // position on subsequent launches and silently no-ops if there's
        // nothing saved yet, so this initial frame only matters once.
        let origin = NSPoint(x: screenFrame.maxX - size.width - 32, y: screenFrame.maxY - size.height - 32)
        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        // Visible on every Space (including full-screen spaces of other
        // apps) and doesn't itself get pulled along when the user switches
        // Spaces away from wherever it was created.
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        // A floating drop target that vanished whenever the app lost focus
        // (e.g. right after the drag that's about to drop onto it) would be
        // useless — keep it visible across activation changes.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        contentView = NSHostingView(rootView: DropZoneContentView().environmentObject(env))

        // Persists (and restores) frame origin across launches under this
        // key; must come after the initial frame is set so a first-run user
        // sees the top-right default instead of Cocoa's arbitrary fallback.
        setFrameAutosaveName(Self.autosaveName)
    }
}

/// The circular SwiftUI drop-target content hosted inside `DropZonePanel`.
private struct DropZoneContentView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(isTargeted ? Theme.accent : Color.primary.opacity(0.12),
                                  lineWidth: isTargeted ? 3 : 1.5)
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                Text("Drop").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: DropZonePanel.defaultSize.width, height: DropZonePanel.defaultSize.height)
        .contentShape(Circle())
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                let urls = await loadDroppedURLs(from: providers)
                env.handleGUIDrop(urls: urls, preset: nil)
            }
            return true
        }
    }
}
