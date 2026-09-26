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
    private var pending: [(Job, CompressionOptions, URL?, GIFOptions, ImageOptions, PDFQuality, Double?, Bool)] = []
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
                    pdfQuality: PDFQuality = .balanced, pdfTargetMB: Double? = nil, trashOriginalOnSuccess: Bool = false) {
        for url in urls {
            let job = Job(input: url, kind: kind)
            jobs.append(job)
            pending.append((job, options, outputDir, gifOptions, imageOptions, pdfQuality, pdfTargetMB, trashOriginalOnSuccess))
        }
        pump()
    }

    /// Appends a job that's already known to have failed before any
    /// compression work could even be attempted — e.g. a deep-link path that
    /// doesn't exist on disk. Skips `pending`/`pump()` entirely so it never
    /// gets a chance to run; it shows up in the UI as a normal failed row
    /// alongside real compression failures.
    public func addFailed(url: URL, message: String) {
        let job = Job(input: url, kind: .compress)
        job.status = .failed(message: message)
        jobs.append(job)
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
            if reason.contains("no audio stream") { return "No audio track in this file" }
            if reason.contains("Password-protected") { return "Password-protected PDF — remove the password first" }
            return "Can't read this file — it may be corrupted or unsupported (\(reason))"
        case CompressError.ffmpegFailed(_, let last): return "Compression failed: \(last.prefix(120))"
        default: return error.localizedDescription
        }
    }

    private func pump() {
        while running < maxConcurrent, !pending.isEmpty {
            let (job, options, outputDir, gifOptions, imageOptions, pdfQuality, pdfTargetMB, trashOriginalOnSuccess) = pending.removeFirst()
            running += 1
            job.status = .running(progress: 0)
            let task = Task { [weak self] in
                await self?.execute(job: job, options: options, outputDir: outputDir, gifOptions: gifOptions,
                                    imageOptions: imageOptions, pdfQuality: pdfQuality, pdfTargetMB: pdfTargetMB,
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
                         imageOptions: ImageOptions, pdfQuality: PDFQuality, pdfTargetMB: Double?, trashOriginalOnSuccess: Bool) async {
        let onProgress: (Double) -> Void = { p in
            // Progress hops can land after execute() has already set a
            // terminal status; they must not revert it to .running.
            Task { @MainActor in
                if case .running = job.status { job.status = .running(progress: p) }
            }
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
                if let targetMB = pdfTargetMB {
                    result = try await pdfCompressor.compress(input: job.input, targetMB: targetMB,
                                                              outputDir: outputDir, suffix: options.outputSuffix,
                                                              progress: onProgress)
                } else {
                    result = try await pdfCompressor.compress(input: job.input, quality: pdfQuality,
                                                              outputDir: outputDir, suffix: options.outputSuffix,
                                                              progress: onProgress)
                }
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
