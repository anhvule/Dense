import Foundation

public enum JobKind: Equatable { case compress, gif }

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
    public static let videoExtensions = ["mp4","mov","m4v","avi","mkv","webm","flv","wmv","mts","m2ts"]

    @Published public private(set) var jobs: [Job] = []
    public var maxConcurrent = 2

    private let compressor: VideoCompressor
    private let gifConverter: GIFConverter
    private var running = 0
    private var pending: [(Job, CompressionOptions, URL?, GIFOptions, Bool)] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(compressor: VideoCompressor, gifConverter: GIFConverter) {
        self.compressor = compressor
        self.gifConverter = gifConverter
    }

    public func add(urls: [URL], kind: JobKind, options: CompressionOptions, outputDir: URL?,
                    gifOptions: GIFOptions = GIFOptions(), trashOriginalOnSuccess: Bool = false) {
        for url in urls {
            let job = Job(input: url, kind: kind)
            jobs.append(job)
            pending.append((job, options, outputDir, gifOptions, trashOriginalOnSuccess))
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
        case CompressError.probeFailed: return "Not a readable video file"
        case CompressError.ffmpegFailed(_, let last): return "Compression failed: \(last.prefix(120))"
        default: return error.localizedDescription
        }
    }

    private func pump() {
        while running < maxConcurrent, !pending.isEmpty {
            let (job, options, outputDir, gifOptions, trashOriginalOnSuccess) = pending.removeFirst()
            running += 1
            job.status = .running(progress: 0)
            let task = Task { [weak self] in
                await self?.execute(job: job, options: options, outputDir: outputDir,
                                    gifOptions: gifOptions, trashOriginalOnSuccess: trashOriginalOnSuccess)
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

    private func execute(job: Job, options: CompressionOptions, outputDir: URL?,
                         gifOptions: GIFOptions, trashOriginalOnSuccess: Bool) async {
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
            }
            job.status = .done(result)
            if trashOriginalOnSuccess, job.kind == .compress {
                try? FileManager.default.trashItem(at: job.input, resultingItemURL: nil)
            }
        } catch CompressError.outputNotSmaller {
            job.status = .skippedAlreadyOptimized
        } catch {
            job.status = .failed(message: Self.message(for: error))
        }
    }
}
