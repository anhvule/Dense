// App/PreviewInspectorView.swift
import SwiftUI
import DenseCore

@MainActor
final class PreviewModel: ObservableObject {
    @Published var pair: PreviewPair?
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var videoTargetMB: Double = 25
    @Published var pdfQuality: PDFQuality = .balanced
    @Published var inputBytes: Int64 = 0
    private var seededForJob: UUID?
    private var generation = 0

    func reload(job: Job, env: AppEnvironment) async {
        generation += 1
        let token = generation
        loading = true
        errorMessage = nil
        defer { if token == generation { loading = false } }
        inputBytes = ((try? FileManager.default
            .attributesOfItem(atPath: job.input.path))?[.size] as? Int64) ?? 0
        if seededForJob != job.id {
            // First look at this file: seed the slider from the destination budget.
            videoTargetMB = env.destination.preset.targetSizeMB
                ?? min(25, max(1, Double(inputBytes) / 2_000_000))
            pdfQuality = env.destination.pdfQuality
            seededForJob = job.id
        }
        do {
            switch FileKind.of(job.input) {
            case .video:
                var opts = env.options
                opts.customTargetMB = videoTargetMB
                let result = try await env.previewRenderer.videoPreview(input: job.input, options: opts)
                guard token == generation else { return }
                pair = result
            case .pdf:
                let result = try env.previewRenderer.pdfPreview(input: job.input, quality: pdfQuality)
                guard token == generation else { return }
                pair = result
            default:
                guard token == generation else { return }
                pair = nil
                errorMessage = "Preview isn't available for this file type."
            }
        } catch {
            guard token == generation else { return }
            pair = nil
            errorMessage = JobQueue.message(for: error)
        }
    }
}

struct PreviewInspectorView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var model = PreviewModel()

    private var selectedJob: Job? {
        env.queue.jobs.first { $0.id == env.selectedJobID } ?? env.queue.jobs.last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let job = selectedJob {
                    Text(job.input.lastPathComponent)
                        .font(.headline).lineLimit(1)
                    if model.loading {
                        ProgressView("Rendering preview…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if let pair = model.pair {
                        sideBySide(pair)
                        controls(for: job)
                    } else if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                } else {
                    Text("Select a file to preview quality before compressing.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(14)
        }
        .task(id: previewKey) {
            if let job = selectedJob { await model.reload(job: job, env: env) }
        }
    }

    /// Re-render when the selection or the PDF rung changes. (The video
    /// slider triggers reloads via onEditingChanged, not through this key,
    /// so dragging doesn't spawn an encode per tick.)
    private var previewKey: String {
        "\(env.selectedJobID?.uuidString ?? "none")|\(model.pdfQuality.rawValue)"
    }

    private func sideBySide(_ pair: PreviewPair) -> some View {
        HStack(alignment: .top, spacing: 8) {
            previewPane(title: "Original", image: pair.original,
                        caption: ByteCountFormatter.string(fromByteCount: model.inputBytes,
                                                           countStyle: .file))
            previewPane(title: "Compressed", image: pair.processed,
                        caption: pair.estimatedOutputBytes.map {
                            "est. " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                        } ?? "preview")
        }
    }

    private func previewPane(title: String, image: CGImage, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(caption).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func controls(for job: Job) -> some View {
        switch FileKind.of(job.input) {
        case .video:
            VStack(alignment: .leading, spacing: 6) {
                Text("Target size: \(Int(model.videoTargetMB)) MB")
                    .font(.callout.weight(.medium)).monospacedDigit()
                Slider(value: $model.videoTargetMB,
                       in: 1...max(2, Double(model.inputBytes) / 1_000_000),
                       onEditingChanged: { editing in
                    if !editing { Task { await model.reload(job: job, env: env) } }
                })
            }
            applyButton {
                var opts = env.options
                opts.customTargetMB = model.videoTargetMB
                env.queue.add(urls: [job.input], kind: .compress, options: opts,
                              outputDir: env.outputDir,
                              trashOriginalOnSuccess: env.trashOriginals)
            }
        case .pdf:
            VStack(alignment: .leading, spacing: 6) {
                Picker("Quality", selection: $model.pdfQuality) {
                    ForEach(PDFQuality.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Good keeps 300 DPI text crisp; Small rasterizes images at 96 DPI.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            applyButton {
                env.queue.add(urls: [job.input], kind: .pdf, options: env.options,
                              outputDir: env.outputDir, pdfQuality: model.pdfQuality,
                              trashOriginalOnSuccess: env.trashOriginals)
            }
        default:
            EmptyView()
        }
    }

    private func applyButton(_ action: @escaping () -> Void) -> some View {
        Button("Compress with these settings", action: action)
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .frame(maxWidth: .infinity)
    }
}
