import Foundation

public enum JobKind: Equatable { case compress, gif, image, optimizeGif, extractAudio, pdf }

public enum JobStatus: Equatable {
    case queued
    case running(progress: Double)
    case done(CompressionResult)
    case failed(message: String)
    case skippedAlreadyOptimized
}

@MainActor
public final class Job: ObservableObject, Identifiable {
    public let id = UUID()
    public let input: URL
    public let kind: JobKind
    @Published public var status: JobStatus = .queued
    init(input: URL, kind: JobKind) { self.input = input; self.kind = kind }
}

@MainActor
public final class JobQueue: ObservableObject {
    @available(*, deprecated, message: "Use FileKind.videoExtensions")
    public static let videoExtensions = FileKind.videoExtensions

    @Published public private(set) var jobs: [Job] = []
    public var maxConcurrent = 2

    private let compressor: VideoCompressor
    private let gifConverter: GIFConverter
    private let imageCompressor: ImageCompressor
    private let audioExtractor: AudioExtractor
    private let pdfCompressor: PDFCompressor
    private var running = 0
    private var pending: [(Job, CompressionOptions, URL?, GIFOptions, ImageOptions, PDFQuality, Bool)] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(compressor: VideoCompressor, gifConverter: GIFConverter, imageCompressor: ImageCompressor,
               audioExtractor: AudioExtractor, pdfCompressor: PDFCompressor = PDFCompressor()) {
        self.compressor = compressor
        self.gifConverter = gifConverter
        self.imageCompressor = imageCompressor
        self.audioExtractor = audioExtractor
        self.pdfCompressor = pdfCompressor
    }

    public func add(urls: [URL], kind: JobKind, options: CompressionOptions, outputDir: URL?,
                    gifOptions: GIFOptions = GIFOptions(), imageOptions: ImageOptions = ImageOptions(),
                    pdfQuality: PDFQuality = .balanced, trashOriginalOnSuccess: Bool = false) {
        for url in urls {
            let job = Job(input: url, kind: kind)
            jobs.append(job)
            pending.append((job, options, outputDir, gifOptions, imageOptions, pdfQuality, trashOriginalOnSuccess))
        }
        pump()
    }

    public func cancelAll() {
        pending.removeAll()
        for (_, task) in tasks { task.cancel() }
        for job in jobs where job.status == .queued { job.status = .failed(message: "Cancelled") }
    }

    public func clearFinished() {
        jobs.removeAll { if case .running = $0.status { return false }
                         if case .queued = $0.status { return false }
                         return true }
    }

    public static func message(for error: Error) -> String {
        switch error {
        case CompressError.outputNotSmaller: return "Already optimized"
        case CompressError.unreachableTarget(let closest):
            return String(format: "Target too small — closest achievable is %.0f MB", closest)
        case CompressError.probeFailed(let reason):
            return reason.contains("no audio stream") ? "No audio track in this file" : "Not a readable video file"
        case CompressError.ffmpegFailed(_, let last): return "Compression failed: \(last.prefix(120))"
        default: return error.localizedDescription
        }
    }

    private func pump() {
        while running < maxConcurrent, !pending.isEmpty {
            let (job, options, outputDir, gifOptions, imageOptions, pdfQuality, trashOriginalOnSuccess) = pending.removeFirst()
            running += 1
            job.status = .running(progress: 0)
            let task = Task { [weak self] in
                await self?.execute(job: job, options: options, outputDir: outputDir, gifOptions: gifOptions,
                                    imageOptions: imageOptions, pdfQuality: pdfQuality,
                                    trashOriginalOnSuccess: trashOriginalOnSuccess)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.running -= 1
                    self.tasks[job.id] = nil
                    self.pump()
                }
            }
            tasks[job.id] = task
        }
    }

    private func execute(job: Job, options: CompressionOptions, outputDir: URL?, gifOptions: GIFOptions,
                         imageOptions: ImageOptions, pdfQuality: PDFQuality, trashOriginalOnSuccess: Bool) async {
        let onProgress: (Double) -> Void = { p in
            Task { @MainActor in job.status = .running(progress: p) }
        }
        do {
            let result: CompressionResult
            switch job.kind {
            case .compress:
                result = try await compressor.compress(input: job.input, options: options,
                                                       outputDir: outputDir, progress: onProgress)
            case .gif:
                result = try await gifConverter.convert(input: job.input, options: gifOptions,
                                                        outputDir: outputDir, progress: onProgress)
            case .image:
                result = try await imageCompressor.compress(input: job.input, options: imageOptions,
                                                            outputDir: outputDir, suffix: options.outputSuffix)
            case .optimizeGif:
                result = try await gifConverter.optimize(input: job.input, options: gifOptions,
                                                         outputDir: outputDir, suffix: options.outputSuffix,
                                                         progress: onProgress)
            case .extractAudio:
                result = try await audioExtractor.extract(input: job.input, outputDir: outputDir,
                                                          suffix: options.outputSuffix, progress: onProgress)
            case .pdf:
                result = try await pdfCompressor.compress(input: job.input, quality: pdfQuality,
                                                          outputDir: outputDir, suffix: options.outputSuffix,
                                                          progress: onProgress)
            }
            job.status = .done(result)
            // Trash applies to replacement-type outputs (a compressed video,
            // a compressed image, an optimized gif, or a compressed pdf all
            // stand in for the original); video→GIF conversions and
            // extracted audio tracks are derivatives of a kept source, so
            // they're excluded here.
            if trashOriginalOnSuccess,
               job.kind == .compress || job.kind == .image || job.kind == .optimizeGif || job.kind == .pdf {
                try? FileManager.default.trashItem(at: job.input, resultingItemURL: nil)
            }
        } catch CompressError.outputNotSmaller {
            job.status = .skippedAlreadyOptimized
        } catch {
            if Task.isCancelled || error is CancellationError {
                job.status = .failed(message: "Cancelled")
            } else {
                job.status = .failed(message: Self.message(for: error))
            }
        }
    }
}
