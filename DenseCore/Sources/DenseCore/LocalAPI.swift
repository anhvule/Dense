import Foundation

/// Pure protocol logic for the local, loopback-only HTTP API (see
/// `LocalAPIServer` in the App target for the actual `NWListener`). Kept
/// free of Network.framework/filesystem access, same philosophy as
/// `DeepLink`: parsing and routing decisions are unit-testable without a
/// socket or a disk, and existence/`FileKind` checks happen at the app
/// layer.
///
/// Security posture (this is the ONLY thing standing between a bug here and
/// an unauthenticated local attacker — the app layer additionally binds the
/// listener to 127.0.0.1 only and requires the server to be explicitly
/// enabled, off by default):
/// - every route requires an exact `Authorization: bearer <token>` header
///   (scheme keyword case-insensitive per RFC 7235, token itself exact);
///   missing/malformed/wrong token is `.unauthorized` before anything else
///   is even looked at (so an unknown path with a bad token is still 401,
///   never a 404 that would leak route existence to an unauthenticated
///   caller);
/// - `/v1/compress` paths must be absolute (bare path or `file://` URL —
///   any other URL scheme is rejected) and must not contain a `..` path
///   component. This is checked BEFORE any standardization:
///   `NSString.standardizingPath` fully resolves `..` segments (even ones
///   that walk above root) into a plain absolute path, so a traversal
///   attempt would otherwise just silently resolve to wherever it lands.
///   Rejecting it outright is the deliberate, defense-in-depth choice.
public enum LocalAPI {
    public struct Request: Equatable {
        public let method: String
        public let path: String
        /// Header keys are lowercased (values are left as-is, trimmed of
        /// surrounding whitespace).
        public let headers: [String: String]
        public let body: Data

        public init(method: String, path: String, headers: [String: String], body: Data) {
            self.method = method
            self.path = path
            self.headers = headers
            self.body = body
        }
    }

    public enum ParseError: Error, Equatable {
        /// Request line or a header line couldn't be parsed.
        case malformed
        /// `Content-Length` exceeds the 1 MB cap.
        case bodyTooLarge
    }

    /// Body size cap for the local API — this is a control-plane protocol
    /// (paths + a preset name), never a bulk-data upload, so 1 MB is
    /// generous headroom while still bounding an attacker's ability to make
    /// the app buffer unbounded memory from a loopback connection.
    static let maxBodyBytes = 1_000_000

    /// Incremental HTTP/1.1 request parser: request line + headers +
    /// `Content-Length` body. Called repeatedly as more bytes arrive on a
    /// connection; returns `nil` until a complete request is buffered (the
    /// caller keeps accumulating and re-calling), and throws for input that
    /// can never become valid (a malformed request/header line, or a
    /// declared body over the 1 MB cap) so the caller can fail the
    /// connection immediately instead of waiting forever.
    public static func parseRequest(buffer: Data) throws -> Request? {
        let terminator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: terminator) else {
            // No full header block yet. Guard against an attacker just
            // streaming headers forever without ever sending the blank
            // line: cap how much header-only data we'll tolerate buffering.
            if buffer.count > maxBodyBytes { throw ParseError.malformed }
            return nil
        }
        guard let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else {
            throw ParseError.malformed
        }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw ParseError.malformed }
        let requestLine = lines.removeFirst()
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else { throw ParseError.malformed }
        let method = String(requestParts[0])
        let path = String(requestParts[1])

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { throw ParseError.malformed }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength: Int
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0 else { throw ParseError.malformed }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard contentLength <= maxBodyBytes else { throw ParseError.bodyTooLarge }

        let bodyStart = headerEnd.upperBound
        let available = buffer.count - bodyStart
        guard available >= contentLength else { return nil } // wait for more bytes

        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        return Request(method: method, path: path, headers: headers, body: body)
    }

    public struct CompressCall: Equatable {
        public let paths: [String]
        public let preset: Preset?

        public init(paths: [String], preset: Preset?) {
            self.paths = paths
            self.preset = preset
        }
    }

    public enum RouteResult: Equatable {
        case unauthorized                    // 401 missing/wrong bearer
        case notFound                        // 404 unknown method+path
        case badRequest(String)              // 400 malformed JSON / non-absolute path / empty paths
        case compress(CompressCall)          // POST /v1/compress
        case jobs                            // GET /v1/jobs
    }

    /// Validates authorization and, for `/v1/compress`, decodes+validates
    /// the JSON body. Every branch is a pure function of `request` and
    /// `token` — no filesystem/network access, so this is fully unit
    /// testable without a live listener.
    public static func route(_ request: Request, token: String) -> RouteResult {
        guard let authHeader = request.headers["authorization"] else { return .unauthorized }
        let schemeAndToken = authHeader.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard schemeAndToken.count == 2,
              schemeAndToken[0].caseInsensitiveCompare("bearer") == .orderedSame,
              constantTimeEquals(String(schemeAndToken[1]), token) else {
            return .unauthorized
        }

        // Ignore any query string for route matching — the local API never
        // uses one, but a client tacking one on (e.g. cache-busting) shouldn't
        // 404.
        let routePath = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path

        switch (request.method, routePath) {
        case ("GET", "/v1/jobs"):
            return .jobs
        case ("POST", "/v1/compress"):
            return decodeCompress(request.body)
        default:
            return .notFound
        }
    }

    /// Constant-time equality over the UTF-8 bytes of both strings: XORs
    /// every byte pair into a bitwise-OR accumulator so the comparison
    /// touches all bytes regardless of where the first mismatch is. The
    /// length check short-circuits, which is fine — token length is public
    /// knowledge (32 hex chars), only its content is secret. Loopback +
    /// per-launch rotation already make a timing oracle largely academic
    /// here; this closes it anyway since the cost is a few lines.
    /// Internal (not private) for direct unit testing.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var acc: UInt8 = 0
        for i in 0..<aBytes.count { acc |= aBytes[i] ^ bBytes[i] }
        return acc == 0
    }

    private struct CompressPayload: Decodable {
        let paths: [String]
        let preset: String?
    }

    private static func decodeCompress(_ body: Data) -> RouteResult {
        let payload: CompressPayload
        do {
            payload = try JSONDecoder().decode(CompressPayload.self, from: body)
        } catch {
            return .badRequest("Malformed JSON body")
        }
        guard !payload.paths.isEmpty else { return .badRequest("No paths provided") }

        var preset: Preset?
        if let presetRaw = payload.preset {
            guard let parsed = Preset(rawValue: presetRaw) else {
                return .badRequest("Unknown preset: \(presetRaw)")
            }
            preset = parsed
        }

        var validated: [String] = []
        for raw in payload.paths {
            guard let path = validatePath(raw) else {
                return .badRequest("Path must be an absolute file path with no \"..\" components: \(raw)")
            }
            validated.append(path)
        }
        return .compress(CompressCall(paths: validated, preset: preset))
    }

    /// See the type-level doc comment for why the `..` check happens before
    /// standardizing rather than after.
    private static func validatePath(_ raw: String) -> String? {
        let rawPath: String
        if let parsed = URL(string: raw), let scheme = parsed.scheme {
            guard scheme.caseInsensitiveCompare("file") == .orderedSame else { return nil }
            rawPath = parsed.path
        } else {
            rawPath = raw
        }
        guard rawPath.hasPrefix("/") else { return nil }
        guard !rawPath.split(separator: "/").contains("..") else { return nil }
        return (rawPath as NSString).standardizingPath
    }

    private static let reasonPhrases: [Int: String] = [
        200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
    ]

    /// Builds the full HTTP/1.1 response byte stream (status line + headers
    /// + body) for a JSON payload. Every response the server sends closes
    /// the connection afterward, so this always advertises `Connection: close`.
    public static func response(status: Int, json: String) -> Data {
        let reason = reasonPhrases[status] ?? "Unknown"
        let bodyData = Data(json.utf8)
        let head = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(bodyData.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var data = Data(head.utf8)
        data.append(bodyData)
        return data
    }
}
