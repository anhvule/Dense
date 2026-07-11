// App/LocalAPIServer.swift
import Foundation
import AppKit
import Network
import DenseCore

/// The app-layer half of the local HTTP API: an `NWListener` bound
/// EXPLICITLY to 127.0.0.1 (never a wildcard address, so it's unreachable
/// from any other machine on the LAN even before the OS firewall gets a
/// say), plus per-connection buffering/dispatch onto the pure
/// `LocalAPI.parseRequest`/`LocalAPI.route` logic in DenseCore.
///
/// Off by default; `AppEnvironment` only calls `start(port:)` when the user
/// explicitly flips the "Local API" toggle. A fresh random bearer token is
/// generated every time the server (re)starts — including every app launch
/// — and held only in memory plus a mode-0600 file on disk (see
/// `tokenFileURL`); it is never itself persisted to `@AppStorage`/defaults.
@MainActor
final class LocalAPIServer {
    private(set) var isRunning = false
    private(set) var token: String = ""

    /// Enqueues `urls` (already filtered to existing, `FileKind`-supported
    /// paths by `handleCompress` below) exactly like a deep link or a
    /// watched-folder arrival — an external trigger, so `updateDefaultPreset`
    /// is always `false`: an API call must never silently change what preset
    /// the user's next manual drop uses. Returns the number of jobs enqueued.
    var onCompress: (_ urls: [URL], _ preset: Preset?) -> Int = { _, _ in 0 }
    /// Snapshot of the current job list for `GET /v1/jobs`.
    var jobsProvider: () -> [Job] = { [] }

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// One idle-deadline task per open connection, reset every time data
    /// arrives; firing cancels the connection. Keyed identically to
    /// `connections` and always mutated in lockstep with it.
    private var idleTimers: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// Simultaneous-connection cap: connections accepted beyond this are
    /// cancelled immediately. The API's whole traffic model is one short
    /// request per connection from a local script, so 16 is generous —
    /// the cap exists to bound what a misbehaving local process can make
    /// the app hold open, not to serve real concurrency.
    private static let maxConnections = 16
    /// A connection that has gone this long without delivering any new
    /// bytes is cancelled — bounds half-open/stalled connections (e.g. a
    /// client that sent half a request and hung) instead of holding the
    /// buffer forever.
    private static let idleTimeoutSeconds: UInt64 = 10

    /// The token file must not outlive the process: `stop()` (which removes
    /// it) is only called on explicit disable/restart, so app quit needs its
    /// own hook. Observing `NSApplication.willTerminateNotification` here —
    /// rather than relying on a caller remembering to stop the server —
    /// keeps the cleanup with the resource's owner. Synchronous
    /// `assumeIsolated` (the notification is posted on the main thread, and
    /// this observer is registered with `queue: .main`) because a Task hop
    /// scheduled during termination may never get to run.
    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private static let tokenFileDirectory: URL? = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Dense", isDirectory: true)
    }()
    private static var tokenFileURL: URL? { tokenFileDirectory?.appendingPathComponent("api-token") }

    /// Starts (or restarts, if already running) the listener on `port`,
    /// bound to loopback only, with a freshly generated token. Silently
    /// no-ops (logging to stderr) if the listener can't be created — e.g. the
    /// port is already in use — rather than crashing the app over an
    /// optional feature.
    func start(port: Int) {
        stop()
        token = Self.generateToken()
        writeTokenFile()

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: max(0, port))) else {
            NSLog("LocalAPIServer: invalid port \(port)")
            return
        }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
        // Loopback-only client traffic never needs Bonjour advertisement.
        params.includePeerToPeer = false

        guard let listener = try? NWListener(using: params) else {
            NSLog("LocalAPIServer: failed to create listener on 127.0.0.1:\(port)")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                NSLog("LocalAPIServer: listener failed: \(error)")
                Task { @MainActor in self?.stop() }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        isRunning = true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, connection) in connections { connection.cancel() }
        connections.removeAll()
        for (_, timer) in idleTimers { timer.cancel() }
        idleTimers.removeAll()
        isRunning = false
        removeTokenFile()
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in
                    self?.connections[id] = nil
                    self?.idleTimers[id]?.cancel()
                    self?.idleTimers[id] = nil
                }
            default:
                break
            }
        }
        connection.start(queue: .main)
        resetIdleTimer(for: connection)
        receive(on: connection, buffer: Data())
    }

    /// (Re)arms the connection's idle deadline. `Task {}` inherits this
    /// class's `@MainActor` context, so the timer body runs on the main
    /// actor like everything else here.
    private func resetIdleTimer(for connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        idleTimers[id]?.cancel()
        idleTimers[id] = Task {
            try? await Task.sleep(nanoseconds: Self.idleTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            connection.cancel() // state handler above removes it from both dictionaries
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data, !data.isEmpty {
                    buffer.append(data)
                    self.resetIdleTimer(for: connection)
                }

                do {
                    if let request = try LocalAPI.parseRequest(buffer: buffer) {
                        self.handle(request: request, on: connection)
                        return
                    }
                } catch {
                    self.send(LocalAPI.response(status: 400, json: "{\"error\":\"Malformed request\"}"), on: connection)
                    return
                }

                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(request: LocalAPI.Request, on connection: NWConnection) {
        switch LocalAPI.route(request, token: token) {
        case .unauthorized:
            send(LocalAPI.response(status: 401, json: "{\"error\":\"unauthorized\"}"), on: connection)
        case .notFound:
            send(LocalAPI.response(status: 404, json: "{\"error\":\"not found\"}"), on: connection)
        case .badRequest(let message):
            send(LocalAPI.response(status: 400, json: Self.jsonObject(["error": message])), on: connection)
        case .compress(let call):
            handleCompress(call, on: connection)
        case .jobs:
            handleJobs(on: connection)
        }
    }

    /// Filters the call's paths to ones that exist on disk and are a
    /// `FileKind` the app knows how to compress; anything else (missing
    /// file, directory, unsupported extension) is reported back as
    /// "skipped" rather than silently dropped. The accepted set is routed
    /// through `onCompress`, identical handling to a manual drag-and-drop.
    private func handleCompress(_ call: LocalAPI.CompressCall, on connection: NWConnection) {
        var accepted: [URL] = []
        var skipped: [String] = []
        for path in call.paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            if exists, !isDirectory.boolValue, FileKind.of(url) != .unsupported {
                accepted.append(url)
            } else {
                skipped.append(path)
            }
        }
        let enqueuedCount = accepted.isEmpty ? 0 : onCompress(accepted, call.preset)
        let json = "{\"accepted\":\(enqueuedCount),\"skipped\":\(Self.jsonArray(skipped))}"
        send(LocalAPI.response(status: 202, json: json), on: connection)
    }

    private func handleJobs(on connection: NWConnection) {
        let entries = jobsProvider().map { job -> String in
            let (statusText, savedPercent): (String, Double?) = {
                switch job.status {
                case .queued: return ("queued", nil)
                case .running: return ("running", nil)
                case .done(let result): return ("done", result.savingsPercent)
                case .failed(let message): return ("failed: \(message)", nil)
                case .skippedAlreadyOptimized: return ("skipped", nil)
                }
            }()
            var fields = [
                "\"id\":\(Self.jsonString(job.id.uuidString))",
                "\"file\":\(Self.jsonString(job.input.path))",
                "\"status\":\(Self.jsonString(statusText))",
            ]
            if let savedPercent { fields.append("\"savedPercent\":\(savedPercent)") }
            return "{\(fields.joined(separator: ","))}"
        }
        send(LocalAPI.response(status: 200, json: "[\(entries.joined(separator: ","))]"), on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - JSON encoding helpers

    /// Hand-rolled rather than `JSONEncoder`/`JSONSerialization` for these
    /// small, fixed-shape responses — avoids defining throwaway `Codable`
    /// wrapper types for every response shape. `String`s always route
    /// through `jsonString` for escaping, so this is safe against paths or
    /// error messages containing quotes/backslashes/control characters.
    private static func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    private static func jsonArray(_ strings: [String]) -> String {
        "[\(strings.map(jsonString).joined(separator: ","))]"
    }

    private static func jsonObject(_ fields: [String: String]) -> String {
        "{\(fields.map { "\(jsonString($0.key)):\(jsonString($0.value))" }.joined(separator: ","))}"
    }

    // MARK: - Token

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            // Astronomically unlikely; fall back to UUID-derived randomness
            // rather than crashing an otherwise-working app over an optional
            // feature failing to start.
            NSLog("LocalAPIServer: SecRandomCopyBytes failed (\(status)); falling back to UUID")
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Writes the current token to a mode-0600 file at
    /// `~/Library/Application Support/Dense/api-token` so the token is
    /// scriptable without needing to copy it out of the UI — documented in
    /// the Advanced panel's Local API help text. Removed on `stop()`.
    private func writeTokenFile() {
        guard let dir = Self.tokenFileDirectory, let fileURL = Self.tokenFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: fileURL.path, contents: Data(token.utf8),
                                           attributes: [.posixPermissions: 0o600])
        } catch {
            NSLog("LocalAPIServer: failed to write token file: \(error)")
        }
    }

    private func removeTokenFile() {
        guard let fileURL = Self.tokenFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
