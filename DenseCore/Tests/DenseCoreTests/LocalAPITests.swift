import XCTest
@testable import DenseCore

final class LocalAPITests: XCTestCase {
    private let token = "deadbeefdeadbeefdeadbeefdeadbeef"

    // MARK: - parseRequest

    func testParseRequestReturnsNilForPartialHeaders() throws {
        let buffer = Data("GET /v1/jobs HTTP/1.1\r\nHost: 127.0.0.1".utf8)
        XCTAssertNil(try LocalAPI.parseRequest(buffer: buffer))
    }

    func testParseRequestReturnsNilWhenBodyIncomplete() throws {
        let buffer = Data(
            "POST /v1/compress HTTP/1.1\r\nContent-Length: 20\r\n\r\n{\"paths\":[".utf8)
        XCTAssertNil(try LocalAPI.parseRequest(buffer: buffer))
    }

    func testParseRequestNoBodyGET() throws {
        let buffer = Data("GET /v1/jobs HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer abc\r\n\r\n".utf8)
        let request = try XCTUnwrap(try LocalAPI.parseRequest(buffer: buffer))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/v1/jobs")
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
        XCTAssertEqual(request.headers["host"], "127.0.0.1")
        XCTAssertTrue(request.body.isEmpty)
    }

    /// Header keys are lowercased regardless of how the client cased them.
    func testParseRequestLowercasesHeaderKeys() throws {
        let buffer = Data("GET /v1/jobs HTTP/1.1\r\nAUTHORIZATION: Bearer abc\r\n\r\n".utf8)
        let request = try XCTUnwrap(try LocalAPI.parseRequest(buffer: buffer))
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
    }

    func testParseRequestWithBody() throws {
        let body = "{\"paths\":[\"/a/b.mp4\"]}"
        let buffer = Data(
            ("POST /v1/compress HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
        let request = try XCTUnwrap(try LocalAPI.parseRequest(buffer: buffer))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), body)
    }

    /// Extra bytes belonging to a *subsequent* pipelined request are left
    /// untouched — the parser only consumes exactly Content-Length bytes.
    func testParseRequestIgnoresTrailingBytesBeyondContentLength() throws {
        let body = "{\"paths\":[\"/a/b.mp4\"]}"
        let buffer = Data(
            ("POST /v1/compress HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body + "EXTRA").utf8)
        let request = try XCTUnwrap(try LocalAPI.parseRequest(buffer: buffer))
        XCTAssertEqual(String(data: request.body, encoding: .utf8), body)
    }

    func testParseRequestThrowsForMalformedRequestLine() {
        let buffer = Data("GARBAGE\r\n\r\n".utf8)
        XCTAssertThrowsError(try LocalAPI.parseRequest(buffer: buffer)) { error in
            XCTAssertEqual(error as? LocalAPI.ParseError, .malformed)
        }
    }

    func testParseRequestThrowsForMalformedHeaderLine() {
        let buffer = Data("GET /v1/jobs HTTP/1.1\r\nNotAHeader\r\n\r\n".utf8)
        XCTAssertThrowsError(try LocalAPI.parseRequest(buffer: buffer)) { error in
            XCTAssertEqual(error as? LocalAPI.ParseError, .malformed)
        }
    }

    func testParseRequestThrowsForNonNumericContentLength() {
        let buffer = Data("POST /v1/compress HTTP/1.1\r\nContent-Length: banana\r\n\r\n".utf8)
        XCTAssertThrowsError(try LocalAPI.parseRequest(buffer: buffer)) { error in
            XCTAssertEqual(error as? LocalAPI.ParseError, .malformed)
        }
    }

    func testParseRequestThrowsForOversizeBody() {
        let buffer = Data("POST /v1/compress HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n".utf8)
        XCTAssertThrowsError(try LocalAPI.parseRequest(buffer: buffer)) { error in
            XCTAssertEqual(error as? LocalAPI.ParseError, .bodyTooLarge)
        }
    }

    // MARK: - route: authorization

    func testRouteMissingAuthHeaderIsUnauthorized() {
        let request = LocalAPI.Request(method: "GET", path: "/v1/jobs", headers: [:], body: Data())
        XCTAssertEqual(LocalAPI.route(request, token: token), .unauthorized)
    }

    func testRouteWrongTokenIsUnauthorized() {
        let request = LocalAPI.Request(method: "GET", path: "/v1/jobs",
                                       headers: ["authorization": "Bearer wrongtoken"], body: Data())
        XCTAssertEqual(LocalAPI.route(request, token: token), .unauthorized)
    }

    func testRouteWrongSchemeIsUnauthorized() {
        let request = LocalAPI.Request(method: "GET", path: "/v1/jobs",
                                       headers: ["authorization": "Basic \(token)"], body: Data())
        XCTAssertEqual(LocalAPI.route(request, token: token), .unauthorized)
    }

    func testRouteCaseInsensitiveBearerScheme() {
        let request = LocalAPI.Request(method: "GET", path: "/v1/jobs",
                                       headers: ["authorization": "bearer \(token)"], body: Data())
        XCTAssertEqual(LocalAPI.route(request, token: token), .jobs)
    }

    /// An unauthenticated caller must not be able to distinguish "unknown
    /// route" from "known route, bad token" — both come back unauthorized.
    func testRouteUnknownPathWithBadTokenIsUnauthorizedNotNotFound() {
        let request = LocalAPI.Request(method: "GET", path: "/v1/nope",
                                       headers: ["authorization": "Bearer wrong"], body: Data())
        XCTAssertEqual(LocalAPI.route(request, token: token), .unauthorized)
    }

    func testRouteUnknownPathWithGoodTokenIsNotFound() {
        let request = LocalAPI.Request(method: "GET", path: "/v1/nope",
                                       headers: ["authorization": "Bearer \(token)"], body: Data())
        XCTAssertEqual(LocalAPI.route(request, token: token), .notFound)
    }

    func testRouteIgnoresQueryStringForMatching() {
        let request = LocalAPI.Request(method: "GET", path: "/v1/jobs?foo=bar",
                                       headers: ["authorization": "Bearer \(token)"], body: Data())
        XCTAssertEqual(LocalAPI.route(request, token: token), .jobs)
    }

    // MARK: - route: GET /v1/jobs

    func testRouteJobsHappyPath() {
        let request = LocalAPI.Request(method: "GET", path: "/v1/jobs",
                                       headers: ["authorization": "Bearer \(token)"], body: Data())
        XCTAssertEqual(LocalAPI.route(request, token: token), .jobs)
    }

    // MARK: - route: POST /v1/compress

    private func compressRequest(bodyJSON: String) -> LocalAPI.Request {
        LocalAPI.Request(method: "POST", path: "/v1/compress",
                         headers: ["authorization": "Bearer \(token)"], body: Data(bodyJSON.utf8))
    }

    func testRouteCompressMalformedJSONIsBadRequest() {
        let request = compressRequest(bodyJSON: "not json")
        guard case .badRequest = LocalAPI.route(request, token: token) else {
            return XCTFail("expected badRequest")
        }
    }

    func testRouteCompressEmptyPathsIsBadRequest() {
        let request = compressRequest(bodyJSON: "{\"paths\":[]}")
        guard case .badRequest = LocalAPI.route(request, token: token) else {
            return XCTFail("expected badRequest")
        }
    }

    func testRouteCompressRelativePathIsBadRequest() {
        let request = compressRequest(bodyJSON: "{\"paths\":[\"relative/clip.mp4\"]}")
        guard case .badRequest = LocalAPI.route(request, token: token) else {
            return XCTFail("expected badRequest")
        }
    }

    func testRouteCompressTraversalPathIsBadRequest() {
        let request = compressRequest(bodyJSON: "{\"paths\":[\"/Users/me/../../../etc/passwd\"]}")
        guard case .badRequest = LocalAPI.route(request, token: token) else {
            return XCTFail("expected badRequest")
        }
    }

    func testRouteCompressNonFileSchemeIsBadRequest() {
        let request = compressRequest(bodyJSON: "{\"paths\":[\"http://evil.example/x.mp4\"]}")
        guard case .badRequest = LocalAPI.route(request, token: token) else {
            return XCTFail("expected badRequest")
        }
    }

    func testRouteCompressUnknownPresetIsBadRequest() {
        let request = compressRequest(bodyJSON: "{\"paths\":[\"/a/b.mp4\"],\"preset\":\"ultraHD\"}")
        guard case .badRequest = LocalAPI.route(request, token: token) else {
            return XCTFail("expected badRequest")
        }
    }

    func testRouteCompressHappyPathWithPreset() {
        let request = compressRequest(bodyJSON: "{\"paths\":[\"/a/b.mp4\",\"/a/c.mp4\"],\"preset\":\"small\"}")
        guard case .compress(let call) = LocalAPI.route(request, token: token) else {
            return XCTFail("expected compress")
        }
        XCTAssertEqual(call.paths, ["/a/b.mp4", "/a/c.mp4"])
        XCTAssertEqual(call.preset, .small)
    }

    func testRouteCompressHappyPathOmittedPresetIsNil() {
        let request = compressRequest(bodyJSON: "{\"paths\":[\"/a/b.mp4\"]}")
        guard case .compress(let call) = LocalAPI.route(request, token: token) else {
            return XCTFail("expected compress")
        }
        XCTAssertNil(call.preset)
    }

    func testRouteCompressAcceptsFileURLPath() {
        let request = compressRequest(bodyJSON: "{\"paths\":[\"file:///a/b.mp4\"]}")
        guard case .compress(let call) = LocalAPI.route(request, token: token) else {
            return XCTFail("expected compress")
        }
        XCTAssertEqual(call.paths, ["/a/b.mp4"])
    }

    func testRouteCompressStandardizesRedundantSlashes() {
        let request = compressRequest(bodyJSON: "{\"paths\":[\"/a//b.mp4\"]}")
        guard case .compress(let call) = LocalAPI.route(request, token: token) else {
            return XCTFail("expected compress")
        }
        XCTAssertEqual(call.paths, ["/a/b.mp4"])
    }

    // MARK: - response

    func testResponseBuildsFullHTTPBytes() throws {
        let data = LocalAPI.response(status: 202, json: "{\"accepted\":1}")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 202 Accepted\r\n"))
        XCTAssertTrue(text.contains("Content-Type: application/json\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 14\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{\"accepted\":1}"))
    }

    func testResponseUnauthorizedStatusLine() throws {
        let data = LocalAPI.response(status: 401, json: "{\"error\":\"unauthorized\"}")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
    }
}
