import Foundation

/// Accumulates stderr bytes behind a lock so the pipe's readability-handler queue
/// and the process's termination-handler queue can never race on the same storage.
/// Marked `@unchecked Sendable` because all access to `data` is guarded by `lock`.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    /// Appends `chunk` and returns any complete lines (terminated by \n or \r) that
    /// can now be split off the front of the buffer.
    func appendAndDrainLines(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
        return drainCompleteLines()
    }

    /// Removes and returns whatever is left in the buffer, without requiring a
    /// trailing line terminator. Used for the final flush at process exit.
    func drainRemainder() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let rest = data
        data.removeAll()
        guard !rest.isEmpty, let line = String(data: rest, encoding: .utf8), !line.isEmpty else {
            return nil
        }
        return line
    }

    /// Must be called with `lock` held.
    private func drainCompleteLines() -> [String] {
        var lines: [String] = []
        while let idx = data.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = data[..<idx]
            data.removeSubrange(...idx)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

public struct FFmpegRunner {
    public let binaryURL: URL

    public init(binaryURL: URL) { self.binaryURL = binaryURL }

    @discardableResult
    public func run(arguments: [String], onStderrLine: @escaping (String) -> Void) async throws -> Int32 {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            let buffer = LineBuffer()

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                for line in buffer.appendAndDrainLines(chunk) {
                    onStderrLine(line)
                }
            }
            process.terminationHandler = { proc in
                // Unhook the handler first, then explicitly drain any bytes that were
                // written after the last `availableData` read (or while a handler
                // invocation was still in flight) so nothing is lost or raced on.
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty {
                    for line in buffer.appendAndDrainLines(remaining) {
                        onStderrLine(line)
                    }
                }
                if let rest = buffer.drainRemainder() {
                    onStderrLine(rest)
                }
                continuation.resume(returning: proc.terminationStatus)
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    public func runCapturingStdout(arguments: [String]) async throws -> (exitCode: Int32, stdout: Data) {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    public static func locateTool(named name: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil) { return bundled }
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Tools/bin/\(name)")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}
