// App/SidebarView.swift
import SwiftUI
import DenseCore
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        List(selection: Binding(
            get: { Optional(env.destinationID) },
            set: { id in
                guard let id else { return }
                env.selectDestination(id)
            })) {
            Section("Destinations") {
                ForEach(Destination.all) { dest in
                    HStack {
                        Label(dest.title, systemImage: dest.symbol)
                        Spacer()
                        Text(dest.subtitle)
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .tag(dest.id)
                    // Dropping straight onto a destination compresses for it
                    // and makes it the new default (dock-behavior parity).
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                        Task {
                            let urls = await loadDroppedURLs(from: providers)
                            env.selectDestination(dest.id)
                            env.handleGUIDrop(urls: urls, preset: dest.preset)
                        }
                        return true
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
    }
}
