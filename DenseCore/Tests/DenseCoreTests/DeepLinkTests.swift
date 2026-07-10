import XCTest
@testable import DenseCore

final class DeepLinkTests: XCTestCase {
    func testSinglePath() throws {
        let url = try XCTUnwrap(URL(string: "dense://compress?path=%2FUsers%2Fme%2Fclip.mp4"))
        let link = try DeepLink.parse(url)
        XCTAssertEqual(link.paths, [URL(fileURLWithPath: "/Users/me/clip.mp4")])
        XCTAssertNil(link.preset)
    }

    func testMultiplePaths() throws {
        let url = try XCTUnwrap(URL(string:
            "dense://compress?path=%2Fa%2Fone.mp4&path=%2Fa%2Ftwo.mp4&path=%2Fa%2Fthree.mp4"))
        let link = try DeepLink.parse(url)
        XCTAssertEqual(link.paths, [
            URL(fileURLWithPath: "/a/one.mp4"),
            URL(fileURLWithPath: "/a/two.mp4"),
            URL(fileURLWithPath: "/a/three.mp4"),
        ])
    }

    func testEncodedSpacesAndUnicode() throws {
        let url = try XCTUnwrap(URL(string:
            "dense://compress?path=%2FUsers%2Fme%2Fmy%20clip%20caf%C3%A9.mp4"))
        let link = try DeepLink.parse(url)
        XCTAssertEqual(link.paths, [URL(fileURLWithPath: "/Users/me/my clip café.mp4")])
    }

    func testValidPreset() throws {
        let url = try XCTUnwrap(URL(string: "dense://compress?path=%2Fa%2Fb.mp4&preset=small"))
        let link = try DeepLink.parse(url)
        XCTAssertEqual(link.preset, .small)
    }

    func testOmittedPresetIsNil() throws {
        let url = try XCTUnwrap(URL(string: "dense://compress?path=%2Fa%2Fb.mp4"))
        let link = try DeepLink.parse(url)
        XCTAssertNil(link.preset)
    }

    func testInvalidPresetThrowsBadPreset() throws {
        let url = try XCTUnwrap(URL(string: "dense://compress?path=%2Fa%2Fb.mp4&preset=ultraHD"))
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLink.ParseError, .badPreset("ultraHD"))
        }
    }

    func testWrongSchemeThrows() throws {
        let url = try XCTUnwrap(URL(string: "http://compress?path=%2Fa%2Fb.mp4"))
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLink.ParseError, .wrongScheme)
        }
    }

    func testWrongHostThrows() throws {
        let url = try XCTUnwrap(URL(string: "dense://open?path=%2Fa%2Fb.mp4"))
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLink.ParseError, .wrongHost)
        }
    }

    func testMissingPathThrowsNoPaths() throws {
        let url = try XCTUnwrap(URL(string: "dense://compress?preset=small"))
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLink.ParseError, .noPaths)
        }
    }

    func testNoQueryAtAllThrowsNoPaths() throws {
        let url = try XCTUnwrap(URL(string: "dense://compress"))
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLink.ParseError, .noPaths)
        }
    }

    /// Relative paths are rejected with `.badPath`, not silently resolved or
    /// folded into `.noPaths` — the caller gets the offending raw value back.
    func testRelativePathThrowsBadPath() throws {
        let url = try XCTUnwrap(URL(string: "dense://compress?path=relative%2Fclip.mp4"))
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLink.ParseError, .badPath("relative/clip.mp4"))
        }
    }

    func testEmptyPathValueThrowsBadPath() throws {
        let url = try XCTUnwrap(URL(string: "dense://compress?path="))
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLink.ParseError, .badPath(""))
        }
    }

    func testCaseInsensitiveSchemeAndHost() throws {
        let url = try XCTUnwrap(URL(string: "Dense://Compress?path=%2Fa%2Fb.mp4"))
        XCTAssertNoThrow(try DeepLink.parse(url))
    }
}
