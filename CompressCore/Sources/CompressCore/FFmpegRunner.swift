import Foundation

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
            var buffer = Data()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                buffer.append(data)
                // ffmpeg progress lines end in \r, log lines in \n — split on both
                while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let lineData = buffer[..<idx]
                    buffer.removeSubrange(...idx)
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        onStderrLine(line)
                    }
                }
            }
            process.terminationHandler = { proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if let rest = String(data: buffer, encoding: .utf8), !rest.isEmpty {
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
