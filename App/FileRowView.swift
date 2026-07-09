// App/FileRowView.swift
import SwiftUI
import CompressCore

struct FileRowView: View {
    @ObservedObject var job: Job
    @State private var thumb: NSImage?
    @State private var inputSizeText: String = ""

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor))
                if let thumb { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "film").foregroundStyle(.secondary) }
            }
            .frame(width: 46, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.input.lastPathComponent).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    trailing
                }
                SizeBar(fraction: barFraction, active: isRunning, label: sizeBarLabel)
                subtitle
            }
        }
        .padding(.vertical, 6)
        .task {
            thumb = await ThumbnailLoader.shared.thumbnail(for: job.input, side: 92)
            let size = ((try? FileManager.default.attributesOfItem(atPath: job.input.path)[.size]) as? Int64) ?? 0
            inputSizeText = byte(size)
        }
    }

    private var isRunning: Bool { if case .running = job.status { return true }; return false }

    private var barFraction: Double {
        switch job.status {
        case .queued: return 1.0
        case .running(let p): return max(0.08, 1.0 - p * 0.9)
        case .done(let r): return max(0.04, Double(r.outputBytes) / Double(max(r.inputBytes, 1)))
        case .failed, .skippedAlreadyOptimized: return 1.0
        }
    }

    @ViewBuilder private var trailing: some View {
        switch job.status {
        case .done(let r):
            Text("−\(Int(r.savingsPercent))%").font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
            Button { NSWorkspace.shared.activateFileViewerSelecting([r.outputURL]) }
                label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
                .accessibilityLabel("Show compressed file in Finder")
                .help("Show in Finder")
        case .running(let p):
            Text("\(Int(p * 100))%").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        default: EmptyView()
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch job.status {
        case .queued:
            Text("Waiting…").font(.system(size: 11)).foregroundStyle(.secondary)
        case .running:
            Text(inputSizeText).font(.system(size: 11)).foregroundStyle(.secondary)
        case .done(let r):
            Text("\(byte(r.inputBytes)) → \(byte(r.outputBytes))").font(.system(size: 11)).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
        case .skippedAlreadyOptimized:
            Text("Already optimized").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func byte(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    private var sizeBarLabel: String {
        switch job.status {
        case .queued:
            return "Waiting"
        case .running(let p):
            return "Compressing, \(Int(p * 100)) percent complete"
        case .done(let r):
            let fraction = max(0.04, Double(r.outputBytes) / Double(max(r.inputBytes, 1)))
            return "Compressed to \(Int(fraction * 100)) percent of original size"
        case .failed, .skippedAlreadyOptimized:
            return "Not compressed"
        }
    }
}

struct SizeBar: View {
    let fraction: Double
    let active: Bool
    let label: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .quaternaryLabelColor))
                Capsule()
                    .fill(active ? Color.accentColor : Color.green)
                    .frame(width: max(6, geo.size.width * fraction))
                    .animation(.easeOut(duration: 0.35), value: fraction)
            }
        }
        .frame(height: 8)
        .accessibilityLabel(label)
    }
}
