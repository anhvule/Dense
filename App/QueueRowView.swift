import SwiftUI
import CompressCore

struct QueueRowView: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(job.input.lastPathComponent).lineLimit(1)
                statusLine
            }
            Spacer()
            if case .done(let result) = job.status {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusLine: some View {
        switch job.status {
        case .queued:
            Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .running(let progress):
            ProgressView(value: progress).frame(maxWidth: 300)
        case .done(let r):
            Text("\(format(r.inputBytes)) → \(format(r.outputBytes))  (−\(Int(r.savingsPercent))%)")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        case .skippedAlreadyOptimized:
            Text("Already optimized").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
